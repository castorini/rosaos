#!/bin/bash
# Stop all Reachy MCP services

# Get the script's directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

PID_FILE="logs/services.pid"
GRACEFUL_STOP_TIMEOUT_SEC="${GRACEFUL_STOP_TIMEOUT_SEC:-12}"

if [ ! -f "$PID_FILE" ]; then
    echo "No PID file found. Services may not be running."
    exit 1
fi

echo "Stopping Reachy MCP services..."

# Read PIDs and kill processes
while read pid; do
    if ps -p $pid > /dev/null 2>&1; then
        echo "  Stopping process $pid..."
        kill $pid
    else
        echo "  Process $pid already stopped"
    fi
done < "$PID_FILE"

# Wait for processes to terminate cleanly. The Reachy daemon can need a few
# seconds to release camera/audio resources.
deadline=$((SECONDS + GRACEFUL_STOP_TIMEOUT_SEC))
while [ "$SECONDS" -lt "$deadline" ]; do
    any_running=0
    while read pid; do
        if ps -p $pid > /dev/null 2>&1; then
            any_running=1
            break
        fi
    done < "$PID_FILE"
    if [ "$any_running" -eq 0 ]; then
        break
    fi
    sleep 1
done

# Force kill any remaining processes
while read pid; do
    if ps -p $pid > /dev/null 2>&1; then
        echo "  Force stopping process $pid..."
        kill -9 $pid
    fi
done < "$PID_FILE"

rm -f "$PID_FILE"
echo "All services stopped."
