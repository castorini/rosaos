#!/bin/bash
# Start rosaOS locally against a wireless Reachy Mini daemon running on the robot.

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR/.."

VENV_DIR="scripts/reachy_mini_env"
PYTHON="$VENV_DIR/bin/python"

if [ ! -x "$PYTHON" ]; then
    echo "Missing virtual environment. Run:"
    echo "  uv venv --python 3.12 scripts/reachy_mini_env"
    echo "  uv pip install -p scripts/reachy_mini_env/bin/python -r requirements.txt"
    exit 1
fi

if [ -z "$REACHY_DAEMON_URL" ]; then
    export REACHY_HOST="${REACHY_HOST:-reachy-mini.local}"
    export REACHY_DAEMON_URL="http://${REACHY_HOST}:8000/api"
fi
export REACHY_DAEMON_URL="${REACHY_DAEMON_URL%/}"
export REACHY_CONNECTION_MODE="${REACHY_CONNECTION_MODE:-network}"
export REACHY_SPAWN_DAEMON="${REACHY_SPAWN_DAEMON:-0}"
export REACHY_CONNECTION_TIMEOUT="${REACHY_CONNECTION_TIMEOUT:-5.0}"
export REACHY_MEDIA_BACKEND="${REACHY_MEDIA_BACKEND:-default}"
export REACHY_ENABLE_MOTORS_ON_MOVE="${REACHY_ENABLE_MOTORS_ON_MOVE:-1}"
export REACHY_EYE_CONTACT_ENABLED="${REACHY_EYE_CONTACT_ENABLED:-0}"

mkdir -p scripts/logs

PID_FILE="scripts/logs/services.pid"

echo "Starting rosaOS for wireless Reachy Mini..."
echo "Logs directory: $SCRIPT_DIR/logs"
echo "Reachy daemon: $REACHY_DAEMON_URL"
echo "SDK connection mode: $REACHY_CONNECTION_MODE"
echo "Eye-contact trigger: $REACHY_EYE_CONTACT_ENABLED"
echo ""

echo "Checking wireless Reachy daemon..."
if ! curl --connect-timeout 3 --max-time 5 -fsS "$REACHY_DAEMON_URL/daemon/status" > /dev/null; then
    echo "Could not reach $REACHY_DAEMON_URL/daemon/status"
    echo "If mDNS is unavailable on this network, set REACHY_HOST to the robot IP"
    echo "or set REACHY_DAEMON_URL to the full wireless Reachy daemon API URL."
    exit 1
fi
echo "  ✓ Wireless Reachy daemon is reachable"

echo "Checking Reachy SDK network connection..."
if ! "$PYTHON" - <<'PY'
import os
import sys
from reachy_mini import ReachyMini

def status_value(status, key):
    if hasattr(status, "model_dump"):
        return status.model_dump().get(key)
    if isinstance(status, dict):
        return status.get(key)
    return getattr(status, key, None)

try:
    with ReachyMini(
        connection_mode=os.environ.get("REACHY_CONNECTION_MODE", "network"),
        spawn_daemon=os.environ.get("REACHY_SPAWN_DAEMON", "0").lower() in {"1", "true", "yes", "on"},
        timeout=float(os.environ.get("REACHY_CONNECTION_TIMEOUT", "5.0")),
        media_backend=os.environ.get("REACHY_PREFLIGHT_MEDIA_BACKEND", "no_media"),
    ) as mini:
        status = mini.client.get_status()
        print(
            "  SDK connected:"
            f" mode={mini.connection_mode},"
            f" wireless={status_value(status, 'wireless_version')},"
            f" wlan_ip={status_value(status, 'wlan_ip')},"
            f" version={status_value(status, 'version')}"
        )
except Exception as exc:
    print(f"Reachy SDK network connection failed: {exc}", file=sys.stderr)
    sys.exit(1)
PY
then
    echo "The HTTP daemon is reachable, but the local Reachy SDK could not connect."
    echo "Full wireless robot UX requires SDK network/WebRTC access."
    echo "Check that the Mac and robot are on the same network and that the local"
    echo "reachy_mini package is compatible with the robot daemon."
    exit 1
fi

rm -f "$PID_FILE"

echo "Starting MCP server..."
nohup "$PYTHON" -u -m server > scripts/logs/mcp_server.log 2>&1 &
MCP_PID=$!
echo $MCP_PID >> "$PID_FILE"
echo "  ✓ MCP server started (PID: $MCP_PID)"

sleep 5

echo "Starting RAG agent..."
nohup "$PYTHON" -u -m client > scripts/logs/client.log 2>&1 &
AGENT_PID=$!
echo $AGENT_PID >> "$PID_FILE"
echo "  ✓ RAG agent started (PID: $AGENT_PID)"

echo ""
echo "Wireless rosaOS services started successfully!"
echo ""
echo "Access points:"
echo "  - Agent UI: http://localhost:8765"
echo "  - MCP Server: http://localhost:5001/mcp"
echo ""
echo "View logs:"
echo "  tail -f scripts/logs/mcp_server.log"
echo "  tail -f scripts/logs/client.log"
echo ""
echo "To stop services, run: ./scripts/stop_all.sh"
