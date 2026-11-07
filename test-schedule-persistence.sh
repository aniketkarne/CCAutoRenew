#!/bin/bash

# Regression tests for schedule persistence (restart / launchd re-trigger),
# explicit setting clears (--days all, empty values), the 'YYYY-MM-DD HH:MM'
# time form on BSD date, and end-of-day rollover across inactive days.
#
# Runs fully sandboxed: fake $HOME, stub claude/ccusage on PATH. No real
# daemon state is touched.

set -u

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
MANAGER="$REPO_DIR/claude-daemon-manager.sh"
DAEMON="$REPO_DIR/claude-auto-renew-daemon.sh"

PASS=0
FAIL=0

t()  { printf '\n[TEST] %s\n' "$1"; }
ok() { printf '[PASS] %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '[FAIL] %s\n' "$1"; FAIL=$((FAIL + 1)); }

assert_eq() {
    # assert_eq <label> <expected> <actual>
    if [ "$2" = "$3" ]; then
        ok "$1"
    else
        bad "$1 (expected '$2', got '$3')"
    fi
}

assert_file() {
    if [ -f "$2" ]; then ok "$1"; else bad "$1 (missing $2)"; fi
}

assert_no_file() {
    if [ ! -f "$2" ]; then ok "$1"; else bad "$1 (still exists: $2)"; fi
}

# --- sandbox: fake HOME + stub claude/ccusage on PATH -----------------------

SANDBOX="$(mktemp -d)"
cleanup() {
    # Kill any daemon left over from a failed assertion, then drop the sandbox.
    if [ -f "$HOME/.claude-auto-renew-daemon.pid" ]; then
        kill "$(cat "$HOME/.claude-auto-renew-daemon.pid")" 2>/dev/null
    fi
    rm -rf "$SANDBOX"
}
trap cleanup EXIT

export HOME="$SANDBOX/home"
mkdir -p "$HOME"
FAKE_BIN="$SANDBOX/bin"
mkdir -p "$FAKE_BIN"
export PATH="$FAKE_BIN:$PATH"

printf '#!/bin/bash\nexit 0\n' > "$FAKE_BIN/claude"
printf '#!/bin/bash\nexit 0\n' > "$FAKE_BIN/ccusage"
chmod +x "$FAKE_BIN/claude" "$FAKE_BIN/ccusage"

START_FILE="$HOME/.claude-auto-renew-start-time"
STOP_FILE="$HOME/.claude-auto-renew-stop-time"
MESSAGE_FILE="$HOME/.claude-auto-renew-message"
DAYS_FILE="$HOME/.claude-auto-renew-days"
PID_FILE="$HOME/.claude-auto-renew-daemon.pid"

to_epoch() {
    date -d "$1" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$1" +%s
}

stop_daemon_quiet() {
    # Kill directly: bash defers the daemon's SIGTERM trap until its current
    # `sleep` finishes, so the manager's graceful stop takes its full 10s
    # grace period on every call. That path isn't what these tests exercise.
    if [ -f "$PID_FILE" ]; then
        kill -9 "$(cat "$PID_FILE")" 2>/dev/null
    fi
    rm -f "$PID_FILE"
}

run_bounded() {
    # run_bounded <seconds> <command...> — kill the command at the deadline so
    # a daemon that wrongly starts from a sourced script can't hang the suite.
    local deadline="$1"
    shift
    "$@" >/dev/null 2>&1 &
    local p=$!
    local i=0
    while kill -0 "$p" 2>/dev/null && [ "$i" -lt "$deadline" ]; do
        sleep 1
        i=$((i + 1))
    done
    kill "$p" 2>/dev/null
    sleep 1
    kill -9 "$p" 2>/dev/null
    wait "$p" 2>/dev/null
    return 0
}

# Far-future dates: the daemon never hits its stop time during the test, so
# it cannot roll the stored schedule forward underneath the assertions.
D1="2030-01-01 09:00:00"
D1_STOP="2030-01-01 17:00:00"
D2="2030-01-01 10:00:00"

# --- 1. fresh start writes every setting ------------------------------------

t "start with full config writes start/stop/message/days"
"$MANAGER" start --at "$D1" --stop "$D1_STOP" --message "resume the auth work" --days weekdays >/dev/null 2>&1
stop_daemon_quiet
assert_file "start time file written" "$START_FILE"
assert_file "stop time file written" "$STOP_FILE"
assert_file "message file written" "$MESSAGE_FILE"
assert_file "days file written" "$DAYS_FILE"
assert_eq "start epoch stored" "$(to_epoch "$D1")" "$(cat "$START_FILE")"
assert_eq "stop epoch stored" "$(to_epoch "$D1_STOP")" "$(cat "$STOP_FILE")"
assert_eq "message stored" "resume the auth work" "$(cat "$MESSAGE_FILE")"
assert_eq "--days weekdays normalizes to mon..fri" "mon,tue,wed,thu,fri" "$(cat "$DAYS_FILE")"

# --- 2. restart keeps settings that aren't mentioned ------------------------

t "restart without flags keeps start/stop/message/days (README contract)"
"$MANAGER" restart >/dev/null 2>&1
stop_daemon_quiet
assert_eq "start kept" "$(to_epoch "$D1")" "$(cat "$START_FILE" 2>/dev/null)"
assert_eq "stop kept" "$(to_epoch "$D1_STOP")" "$(cat "$STOP_FILE" 2>/dev/null)"
assert_eq "message kept" "resume the auth work" "$(cat "$MESSAGE_FILE" 2>/dev/null)"
assert_eq "days kept" "mon,tue,wed,thu,fri" "$(cat "$DAYS_FILE" 2>/dev/null)"

t "restart --at replaces only the start time"
"$MANAGER" restart --at "$D2" >/dev/null 2>&1
stop_daemon_quiet
assert_eq "start replaced" "$(to_epoch "$D2")" "$(cat "$START_FILE" 2>/dev/null)"
assert_eq "stop kept after --at" "$(to_epoch "$D1_STOP")" "$(cat "$STOP_FILE" 2>/dev/null)"
assert_eq "message kept after --at" "resume the auth work" "$(cat "$MESSAGE_FILE" 2>/dev/null)"
assert_eq "days kept after --at" "mon,tue,wed,thu,fri" "$(cat "$DAYS_FILE" 2>/dev/null)"

t "restart --message replaces only the message"
"$MANAGER" restart --message "resume the database work" >/dev/null 2>&1
stop_daemon_quiet
assert_eq "message replaced" "resume the database work" "$(cat "$MESSAGE_FILE" 2>/dev/null)"
assert_eq "start kept after --message" "$(to_epoch "$D2")" "$(cat "$START_FILE" 2>/dev/null)"
assert_eq "days kept after --message" "mon,tue,wed,thu,fri" "$(cat "$DAYS_FILE" 2>/dev/null)"

# --- 3. explicit clears -----------------------------------------------------

t "restart --days all clears only the day filter"
"$MANAGER" restart --days all >/dev/null 2>&1
stop_daemon_quiet
assert_no_file "days cleared by --days all" "$DAYS_FILE"
assert_eq "start kept after --days all" "$(to_epoch "$D2")" "$(cat "$START_FILE" 2>/dev/null)"
assert_eq "message kept after --days all" "resume the database work" "$(cat "$MESSAGE_FILE" 2>/dev/null)"

t "restart --message '' clears only the message"
"$MANAGER" restart --message "" >/dev/null 2>&1
stop_daemon_quiet
assert_no_file "message cleared by empty --message" "$MESSAGE_FILE"
assert_eq "start kept after message clear" "$(to_epoch "$D2")" "$(cat "$START_FILE" 2>/dev/null)"
assert_eq "stop kept after message clear" "$(to_epoch "$D1_STOP")" "$(cat "$STOP_FILE" 2>/dev/null)"

t "restart --stop '' clears only the stop time"
"$MANAGER" restart --stop "" >/dev/null 2>&1
stop_daemon_quiet
assert_no_file "stop cleared by empty --stop" "$STOP_FILE"
assert_eq "start kept after stop clear" "$(to_epoch "$D2")" "$(cat "$START_FILE" 2>/dev/null)"

# --- 4. fresh start (no --keep-config) still resets to defaults -------------

t "plain start after stop resets to defaults"
stop_daemon_quiet
"$MANAGER" start >/dev/null 2>&1
stop_daemon_quiet
assert_no_file "start cleared by plain start" "$START_FILE"
assert_no_file "stop cleared by plain start" "$STOP_FILE"
assert_no_file "message cleared by plain start" "$MESSAGE_FILE"
assert_no_file "days cleared by plain start" "$DAYS_FILE"

# --- 5. documented 'YYYY-MM-DD HH:MM' form parses on BSD date ---------------

t "start accepts 'YYYY-MM-DD HH:MM' without seconds (README form)"
"$MANAGER" start --at "2030-01-03 14:30" >/dev/null 2>&1
stop_daemon_quiet
assert_eq "HH:MM-only date form stored" "$(to_epoch "2030-01-03 14:30:00")" "$(cat "$START_FILE" 2>/dev/null)"

# --- 6. sourcing the daemon must not start it -------------------------------

t "sourcing claude-auto-renew-daemon.sh does not start the daemon"
rm -f "$HOME/.claude-auto-renew-daemon.log" "$PID_FILE"
run_bounded 3 bash -c "source '$DAEMON'"
assert_no_file "no PID file after sourcing" "$PID_FILE"

# --- 7. rollover skips inactive days ----------------------------------------

t "end-of-day rollover advances past inactive days to the next active day"
# Freeze "now" just past Friday's stop time: the day that just ended is
# active but the newly scheduled day (Saturday) is not. The rollover must
# consult the NEW day and skip the weekend in one step — checking "today"
# (active) instead would leave Saturday scheduled and spam the off-day.
FROZEN_BIN="$SANDBOX/frozenbin"
mkdir -p "$FROZEN_BIN"
REAL_DATE="$(command -v date)"
cat > "$FROZEN_BIN/date" <<EOF
#!/bin/bash
case "\$1" in
    +%s) echo "$(to_epoch "2026-11-06 17:05:05")"; exit 0 ;;
    +%a) echo Fri; exit 0 ;;
    *) exec "$REAL_DATE" "\$@" ;;
esac
EOF
chmod +x "$FROZEN_BIN/date"

rm -f "$PID_FILE"
cat > "$DAYS_FILE" <<'EOF'
mon,tue,wed,thu,fri
EOF
# Friday 2026-11-06 09:00 - 17:00; the weekend must be skipped in one step.
FRI_START="$(to_epoch "2026-11-06 09:00:00")"
FRI_STOP="$(to_epoch "2026-11-06 17:00:00")"
echo "$FRI_START" > "$START_FILE"
echo "$FRI_STOP" > "$STOP_FILE"
touch "${START_FILE}.activated"

run_bounded 3 env "PATH=$FROZEN_BIN:$PATH" bash "$DAEMON"
assert_eq "start advanced to Monday" "$(to_epoch "2026-11-09 09:00:00")" "$(cat "$START_FILE")"
assert_eq "stop advanced to Monday" "$(to_epoch "2026-11-09 17:00:00")" "$(cat "$STOP_FILE")"
assert_no_file "activation marker cleared for the new day" "${START_FILE}.activated"

t "rollover_to_next_day advances exactly one day without a day filter"
rm -f "$PID_FILE"
echo "all" > "$DAYS_FILE"
echo "$FRI_START" > "$START_FILE"
echo "$FRI_STOP" > "$STOP_FILE"
run_bounded 3 bash -c "source '$DAEMON'; rollover_to_next_day"
assert_eq "start advanced one day (no filter)" "$(to_epoch "2026-11-07 09:00:00")" "$(cat "$START_FILE")"
assert_eq "stop advanced one day (no filter)" "$(to_epoch "2026-11-07 17:00:00")" "$(cat "$STOP_FILE")"

# --- summary ----------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
