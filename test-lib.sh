#!/bin/bash

# Shared sandboxing for the CC AutoRenew test scripts.
#
# The daemon manager and the daemon keep every piece of state under $HOME
# (PID file, start/stop times, custom message, day filter, logs) and the test
# scripts start real daemons. Run against the real HOME, a test run kills the
# user's live daemon, overwrites its schedule and message config, truncates
# its logs, and leaves daemon processes behind.
#
# Every test script calls sandbox_init before touching the manager. Tests then
# run inside a throwaway HOME with stub claude/ccusage binaries on PATH: the
# daemon pipes renewal messages into `claude` after 60 seconds of uptime, so
# without the stub a slow test run starts real Claude sessions.

TESTLIB_REAL_HOME="$HOME"
TESTLIB_REAL_PATH="$PATH"
SANDBOX_HOME=""
SANDBOX_STUB_BIN=""

sandbox_init() {
    SANDBOX_HOME="$(mktemp -d -t cc-autorenew-test-home-XXXXXX)" || {
        echo "test-lib: cannot create sandbox HOME" >&2
        exit 1
    }
    SANDBOX_STUB_BIN="$SANDBOX_HOME/stub-bin"
    mkdir -p "$SANDBOX_STUB_BIN"

    # Stub claude: answers instantly and successfully so daemon renewals can
    # never reach the real CLI. Stub ccusage: exits non-zero so the daemon
    # takes its deterministic clock-based fallback path.
    printf '#!/bin/bash\nexit 0\n' > "$SANDBOX_STUB_BIN/claude"
    printf '#!/bin/bash\nexit 1\n' > "$SANDBOX_STUB_BIN/ccusage"
    chmod +x "$SANDBOX_STUB_BIN/claude" "$SANDBOX_STUB_BIN/ccusage"

    HOME="$SANDBOX_HOME"
    PATH="$SANDBOX_STUB_BIN:$PATH"
    export HOME PATH

    trap 'sandbox_cleanup' EXIT
    trap 'sandbox_cleanup; exit 1' INT TERM
}

sandbox_cleanup() {
    trap - EXIT INT TERM
    sandbox_kill_daemon
    HOME="$TESTLIB_REAL_HOME"
    PATH="$TESTLIB_REAL_PATH"
    export HOME PATH
    if [ -n "$SANDBOX_HOME" ]; then
        rm -rf "$SANDBOX_HOME"
    fi
    SANDBOX_HOME=""
    return 0
}

# Kill whatever daemon the tests started. The PID file lives in the sandbox
# HOME; SIGKILL is deliberate: the daemon defers its SIGTERM trap past a
# running sleep, and tests just need it gone. Leaves nothing running and no
# PID file behind.
sandbox_kill_daemon() {
    local pid_file pid
    pid_file="$HOME/.claude-auto-renew-daemon.pid"
    [ -f "$pid_file" ] || return 0
    pid="$(cat "$pid_file" 2>/dev/null)"
    rm -f "$pid_file"
    case "$pid" in
        ''|*[!0-9]*) return 0 ;;
    esac
    kill -9 "$pid" 2>/dev/null
    return 0
}

# Portable `timeout`: macOS ships none. Runs the command in the background
# and force-kills it on expiry. Returns 124 on timeout like GNU timeout.
run_with_timeout() {
    local seconds waited cmd_pid
    seconds="$1"
    shift
    "$@" &
    cmd_pid=$!
    waited=0
    while [ "$waited" -lt "$seconds" ]; do
        kill -0 "$cmd_pid" 2>/dev/null || break
        sleep 1
        waited=$((waited + 1))
    done
    if kill -0 "$cmd_pid" 2>/dev/null; then
        kill -9 "$cmd_pid" 2>/dev/null
        wait "$cmd_pid" 2>/dev/null
        return 124
    fi
    wait "$cmd_pid"
}
