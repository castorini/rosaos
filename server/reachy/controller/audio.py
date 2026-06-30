import os
import queue
import scipy
import soundfile as sf
import numpy as np
import subprocess
import sys
import threading
import time
from pathlib import Path
import httpx
from reachy_mini import ReachyMini
from threading import Thread

_TTS_SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tts.py")
_DAEMON_URL = os.environ.get("REACHY_DAEMON_URL", "http://localhost:8000/api").rstrip("/")

# Simple queue for speak requests from multiple agents
_speak_queue: queue.Queue[tuple[ReachyMini, str]] = queue.Queue()
_speak_worker_thread: Thread | None = None
_speak_lock = threading.Lock()


def _play(path: str, mini: ReachyMini) -> None:
    """Play audio file synchronously."""
    data, samplerate_in = sf.read(path, dtype="float32")
    output_sr = mini.media.get_output_audio_samplerate()
    if samplerate_in != output_sr:
        data = scipy.signal.resample(
            data,
            int(
                len(data)
                * (output_sr / samplerate_in)
            ),
        )
    output_channels = mini.media.get_output_channels()
    if output_channels == 1 and data.ndim > 1:
        data = np.mean(data, axis=1)
    elif output_channels > 1:
        if data.ndim == 1:
            data = np.repeat(data[:, np.newaxis], output_channels, axis=1)
        elif data.shape[1] != output_channels:
            data = data[:, :1]
            data = np.repeat(data, output_channels, axis=1)
    mini.media.start_playing()
    print("Playing audio...")
    # Push samples in chunks
    chunk_size = 1024
    for i in range(0, len(data), chunk_size):
        chunk = data[i : i + chunk_size]
        mini.media.push_audio_sample(chunk)
    # Wait for playback to finish: duration = samples / sample_rate
    duration_sec = len(data) / output_sr
    time.sleep(duration_sec)
    mini.media.stop_playing()
    print("Playback finished.")


def _has_sdk_playback(mini: ReachyMini) -> bool:
    try:
        media = mini.media
        return media.audio is not None and media.get_output_audio_samplerate() > 0
    except Exception:
        return False


def _generate_tts(text: str, output: Path) -> None:
    subprocess.run(
        [sys.executable, _TTS_SCRIPT, text, output.name],
        check=True,
        cwd=output.parent,
    )


def _speak_daemon_http(text: str, forcefully_interrupt: bool = False) -> str:
    """Generate speech locally and ask a daemon media API to play it on the robot."""
    project_dir = Path(__file__).resolve().parent
    output = project_dir / "output.wav"
    _generate_tts(text, output)

    try:
        with httpx.Client(base_url=_DAEMON_URL, timeout=60.0) as client:
            if forcefully_interrupt:
                client.post("/media/stop_sound")
            with output.open("rb") as f:
                upload = client.post(
                    "/media/sounds/upload",
                    files={"file": (output.name, f, "audio/wav")},
                )
            if upload.status_code == 404:
                raise RuntimeError(
                    "Robot speech playback is unavailable: this Reachy daemon does "
                    "not expose a media upload endpoint."
                )
            upload.raise_for_status()
            filename = upload.json().get("filename", output.name)
            play = client.post("/media/play_sound", json={"file": filename})
            if play.status_code == 404:
                raise RuntimeError(
                    "Robot speech playback is unavailable: this Reachy daemon does "
                    "not expose a media play endpoint."
                )
            play.raise_for_status()
    except httpx.HTTPError as exc:
        raise RuntimeError(f"Robot speech playback failed via daemon media API: {exc}") from exc
    return "Done"


def _speak_worker() -> None:
    """Background thread that processes the speak queue one item at a time."""
    global _speak_worker_thread
    while True:
        try:
            mini, text = _speak_queue.get()
            if mini is None:  # Sentinel to stop
                break
            print("Generating audio: " + text)
            project_dir = Path(__file__).resolve().parent
            _generate_tts(text, project_dir / "output.wav")
            print("TTS done, playing...")
            _play("server/reachy/controller/output.wav", mini)
            _speak_queue.task_done()
        except Exception as e:
            print(f"Error in speak worker: {e}", file=sys.stderr)
            import traceback
            traceback.print_exc()
            _speak_queue.task_done()


def speak(mini: ReachyMini, text: str, forcefully_interrupt: bool = False) -> str:
    """Speak words using text to speech with Reachy Mini's speaker.
    
    Multiple calls are queued and processed sequentially by a background thread.

    Args:
        mini: ReachyMini instance
        text: Text to speak
        forcefully_interrupt: If True, clear the queue and stop current playback before queuing this.
    """
    global _speak_worker_thread

    if not _has_sdk_playback(mini):
        return _speak_daemon_http(text, forcefully_interrupt)
    
    with _speak_lock:
        if forcefully_interrupt:
            # Clear queue and stop playback
            try:
                mini.media.stop_playing()
            except Exception:
                pass
            while not _speak_queue.empty():
                try:
                    _speak_queue.get_nowait()
                    _speak_queue.task_done()
                except queue.Empty:
                    break
        
        # Start worker thread if not running
        if _speak_worker_thread is None or not _speak_worker_thread.is_alive():
            _speak_worker_thread = Thread(target=_speak_worker, daemon=True)
            _speak_worker_thread.start()
        
        # Queue the request
        _speak_queue.put((mini, text))
    
    return "Done"
