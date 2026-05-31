# Agent Notes

## macOS Camera Access

Reachy Mini camera access may fail when the stack is launched from the Codex app
terminal because macOS camera authorization does not currently behave like it
does in Terminal.app. This is tracked upstream:

- https://github.com/openai/codex/issues/17361

If Reachy Mini fails with OpenCV / AVFoundation messages such as
`not authorized to capture video` or `RuntimeError: Camera not found`, launch the
stack from a normal macOS Terminal instead. The expected Terminal.app setup and
camera probe are documented in `docs/macos-reachy-mini-setup.md`.
