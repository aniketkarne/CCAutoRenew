#!/bin/bash

# Graceful daemon shutdown.
#
# Stops the daemon recorded in the PID file first: SIGTERM, up to 10 seconds
# to exit cleanly (the daemon's SIGTERM handling can be deferred past a
# running sleep), then SIGKILL. The PID file is always removed so `status`
# and `start` see clean state afterwards. Any daemon process not tracked by
# the PID file is swept up by pattern match.

PID_FILE="$HOME/.claude-auto-renew-daemon.pid"

echo "Stopping Claude Auto Renew daemon..."

if [ -f "$PID_FILE" ]; then
    pid="$(cat "$PID_FILE" 2>/dev/null)"
    case "$pid" in
        ''|*[!0-9]*) pid="" ;;
    esac

    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        echo "Sending SIGTERM to daemon (PID $pid)..."
        kill "$pid" 2>/dev/null

        waited=0
        while [ "$waited" -lt 10 ] && kill -0 "$pid" 2>/dev/null; do
            sleep 1
            waited=$((waited + 1))
        done

        if kill -0 "$pid" 2>/dev/null; then
            echo "Warning: daemon did not stop gracefully, forcing..."
            kill -9 "$pid" 2>/dev/null
            sleep 1
        fi
    fi

    # Stale or not, the PID file is done with.
    rm -f "$PID_FILE"
fi

# Sweep up any daemon processes not tracked by the PID file
remaining=$(ps aux | grep -i "claude-auto-renew-daemon" | grep -v grep | wc -l)

if [ "$remaining" -eq 0 ]; then
    echo "Daemon stopped successfully."
else
    echo "Warning: $remaining daemon process(es) still running."
    echo "Trying force kill..."
    pkill -9 -f "claude-auto-renew-daemon.sh"
    sleep 1

    # Final check
    remaining=$(ps aux | grep -i "claude-auto-renew-daemon" | grep -v grep | wc -l)
    if [ "$remaining" -eq 0 ]; then
        echo "Daemon force stopped successfully."
    else
        echo "Error: Unable to stop all daemon processes."
    fi
fi
