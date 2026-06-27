#!/bin/bash
# Start rosaOS against a wireless Reachy Mini daemon running on the robot.

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

REACHY_HOST="${REACHY_HOST:-10.20.125.233}"
export REACHY_DAEMON_URL="${REACHY_DAEMON_URL:-http://${REACHY_HOST}:8000/api}"
export REACHY_DAEMON_URL="${REACHY_DAEMON_URL%/}"
export REACHY_CONNECTION_MODE="${REACHY_CONNECTION_MODE:-network}"
export REACHY_SPAWN_DAEMON="${REACHY_SPAWN_DAEMON:-0}"
export REACHY_HTTP_ONLY="${REACHY_HTTP_ONLY:-1}"
export REACHY_WAKE_ON_START="${REACHY_WAKE_ON_START:-1}"

mkdir -p scripts/logs

PID_FILE="scripts/logs/services.pid"
rm -f "$PID_FILE"

echo "Starting rosaOS for wireless Reachy Mini..."
echo "Logs directory: $SCRIPT_DIR/logs"
echo "Reachy daemon: $REACHY_DAEMON_URL"
echo ""

echo "Checking wireless Reachy daemon..."
if ! curl -fsS "$REACHY_DAEMON_URL/daemon/status" > /dev/null; then
    echo "Could not reach $REACHY_DAEMON_URL/daemon/status"
    echo "Set REACHY_HOST or REACHY_DAEMON_URL to the wireless Reachy address."
    exit 1
fi
echo "  ✓ Wireless Reachy daemon is reachable"

if [ "$REACHY_WAKE_ON_START" = "1" ] || [ "$REACHY_WAKE_ON_START" = "true" ]; then
    echo "Waking wireless Reachy..."
    curl -fsS -X POST "$REACHY_DAEMON_URL/motors/set_mode/enabled" > /dev/null
    curl -fsS -X POST "$REACHY_DAEMON_URL/move/play/wake_up" > /dev/null
    echo "  ✓ Wake-up requested"
fi

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
