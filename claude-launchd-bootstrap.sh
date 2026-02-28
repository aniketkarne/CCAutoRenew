#!/bin/bash

# launchd helper: start the daemon if it is not already running.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DAEMON_MANAGER="$SCRIPT_DIR/claude-daemon-manager.sh"
PID_FILE="$HOME/.claude-auto-renew-daemon.pid"

if [ ! -x "$DAEMON_MANAGER" ]; then
    echo "ERROR: claude-daemon-manager.sh not found or not executable at $DAEMON_MANAGER" >&2
    exit 1
fi

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        exit 0
    fi

    rm -f "$PID_FILE"
fi

exec "$DAEMON_MANAGER" start "$@"
