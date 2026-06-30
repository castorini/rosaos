# macOS Reachy Mini setup notes

These notes capture the first-run setup path for a fresh Mac with a Reachy Mini
Lite, plus the local rosaOS setup for a wireless Reachy Mini.

## Python environment

The project expects Python 3.12. On a Mac without Python 3.12, use `uv` to create the virtual environment where the start scripts expect it:

```bash
uv venv --python 3.12 scripts/reachy_mini_env
uv pip install -p scripts/reachy_mini_env/bin/python -r requirements.txt
```

The start scripts use `scripts/reachy_mini_env/bin/python` and `scripts/reachy_mini_env/bin/reachy-mini-daemon` directly. If the venv is missing, they print the install commands above and exit.

## API keys

`python-dotenv` loads `.env` from the repo root. Keep `.env` local; it is ignored by git.

For an Anthropic-backed kernel with Groq speech services:

```bash
ANTHROPIC_API_KEY=...
LLM_PROVIDER=anthropic
ANTHROPIC_MODEL=claude-sonnet-4-6
GROQ_API_KEY=...
```

`GROQ_API_KEY` is still needed for voice input because the Reachy speech-to-text loop uses Groq Whisper. Without it, typed chat can work while spoken wake-word checks transcribe as empty strings.

## Camera and media backend

On macOS, camera permission is attached to the app that launches Python. For video/camera tools, launch the stack from Terminal after granting Terminal camera access:

```bash
cd /Users/lily/dev/rosaos
./scripts/start_all.sh
```

If macOS has not prompted yet, trigger the camera permission prompt from Terminal:

```bash
cd /Users/lily/dev/rosaos
scripts/reachy_mini_env/bin/python - <<'PY'
import cv2
cap = cv2.VideoCapture(0, cv2.CAP_AVFOUNDATION)
print("opened:", cap.isOpened())
if cap.isOpened():
    ok, frame = cap.read()
    print("read:", ok, None if frame is None else frame.shape)
cap.release()
PY
```

Approve camera access for Terminal, then rerun the probe. A healthy camera path prints `opened: True`.

Known Codex app limitation: camera access can fail from the Codex app terminal
even when the same OpenCV / AVFoundation path works from Terminal.app. See
https://github.com/openai/codex/issues/17361. If Reachy Mini starts from Codex
but the MCP server crashes with `RuntimeError: Camera not found`, stop the stack
and the user should manually rerun it from a normal Terminal window.

## Running and stopping: Lite

Start all services for a local Reachy Mini Lite daemon:

```bash
./scripts/start_all.sh
```

Stop all services:

```bash
./scripts/stop_all.sh
```

The services and ports are:

- Reachy Mini daemon: `8000`
- Reachy MCP server: `5001`
- Process manager MCP server: `7001`
- rosaOS web UI: `8765`

Plain `GET /mcp` requests often return `406 Not Acceptable`; that still confirms the MCP server is reachable. Use the web UI at `http://127.0.0.1:8765/` for typed chat.

## Running and stopping: wireless Reachy Mini

For the wireless Reachy Mini, leave the official daemon running on the robot's
onboard Raspberry Pi and start only the local rosaOS services on the Mac:

```bash
cd /Users/lily/dev/rosaos
./scripts/start_wireless_reachy.sh
```

The wireless script defaults to `reachy-mini.local`. If mDNS is unavailable on
your network, provide the robot host/IP or the full daemon API base URL:

```bash
REACHY_HOST=<robot-ip-or-hostname> ./scripts/start_wireless_reachy.sh
```

```bash
REACHY_DAEMON_URL=http://<robot-ip-or-hostname>:8000/api ./scripts/start_wireless_reachy.sh
```

The wireless script does not start `reachy-mini-daemon` locally. It sets
`REACHY_CONNECTION_MODE=network`, `REACHY_SPAWN_DAEMON=0`,
`REACHY_MEDIA_BACKEND=default`, `REACHY_ENABLE_MOTORS_ON_MOVE=1`, and
`REACHY_EYE_CONTACT_ENABLED=0`.

Motion and emotions use the HTTP daemon endpoint. Camera and microphone access
use the official SDK's network/WebRTC media path; if that fails, verify the
robot daemon's wireless media support and the Mac's GStreamer/WebRTC
dependencies. The Pi should not run rosaOS, MCP servers, client workers, or any
custom helper service.

Wireless STT remains enabled by default, but camera-based eye-contact activation
is disabled to avoid continuous idle frame polling. Set
`REACHY_EYE_CONTACT_ENABLED=1` before `./scripts/start_wireless_reachy.sh` to
restore the full eye-contact trigger.

## Quick checks

Check the daemon and UI:

```bash
curl http://127.0.0.1:8000/openapi.json
curl http://127.0.0.1:8765/
```

Check the Reachy camera tool through MCP:

```bash
scripts/reachy_mini_env/bin/python - <<'PY'
import asyncio
from fastmcp import Client

async def main():
    async with Client("http://127.0.0.1:5001/mcp") as client:
        result = await client.call_tool("take_picture", {"for_text_only_model": False})
        print(result)

asyncio.run(main())
PY
```
