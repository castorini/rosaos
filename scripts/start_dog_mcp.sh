#!/bin/bash
# Start the ROS MCP server for a HiWonder PuppyPi robot dog.

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR/.."

VENV_DIR="scripts/reachy_mini_env"
PYTHON="$VENV_DIR/bin/python"

DOG_ROSBRIDGE_IP="${1:-${DOG_ROSBRIDGE_IP:-129.97.71.85}}"
DOG_ROSBRIDGE_PORT="${DOG_ROSBRIDGE_PORT:-9090}"
DOG_MCP_HOST="${DOG_MCP_HOST:-0.0.0.0}"
DOG_MCP_PORT="${DOG_MCP_PORT:-9090}"
DOG_CAMERA_TOPIC="${DOG_CAMERA_TOPIC:-/image_raw}"

if [ ! -x "$PYTHON" ]; then
    echo "Missing virtual environment. Run:"
    echo "  uv venv --python 3.12 scripts/reachy_mini_env"
    echo "  uv pip install -p scripts/reachy_mini_env/bin/python -r requirements.txt"
    echo "  uv pip install -p scripts/reachy_mini_env/bin/python -e server/ros-mcp-server"
    exit 1
fi

mkdir -p scripts/logs

echo "Starting PuppyPi ROS MCP server..."
echo "  rosbridge: ${DOG_ROSBRIDGE_IP}:${DOG_ROSBRIDGE_PORT}"
echo "  MCP:       http://localhost:${DOG_MCP_PORT}/mcp"
echo "  camera:    ${DOG_CAMERA_TOPIC}"

exec "$PYTHON" -m ros_mcp.main \
    --transport streamable-http \
    --host "$DOG_MCP_HOST" \
    --port "$DOG_MCP_PORT" \
    --rosbridge-ip "$DOG_ROSBRIDGE_IP" \
    --rosbridge-port "$DOG_ROSBRIDGE_PORT" \
    --name dog \
    --camera-topic "$DOG_CAMERA_TOPIC"
