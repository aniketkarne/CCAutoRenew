#!/bin/bash
# Shared library for ccusage query logic
# Used by both daemon and manager scripts

# Config file to track daemon state
DAEMON_CONFIG_FILE="$HOME/.claude-auto-renew-daemon-config"
DAEMON_STATE_FILE="$HOME/.claude-auto-renew-state"

# Global variables set by get_remaining_time()
TIMING_SOURCE=""
REMAINING_SECONDS=0

# Global variable set by read_state_file()
BLOCK_END_EPOCH=""

# Get the ccusage command (ccusage, bunx, or npx)
# Returns: command name or exits with error code
get_ccusage_cmd() {
    if command -v ccusage &> /dev/null; then
        echo "ccusage"
        return 0
    elif command -v bunx &> /dev/null; then
        echo "bunx"
        return 0
    elif command -v npx &> /dev/null; then
        echo "npx"
        return 0
    else
        return 1
    fi
}

# Query ccusage and return minutes remaining in the active block
# Returns: minutes remaining via echo, or error code
# Return codes: 0=success, 1=no ccusage, 3=no active block, 4=invalid format, 5=invalid range, 7=no jq
get_minutes_until_reset() {
    local cmd=$(get_ccusage_cmd)
    if [ $? -ne 0 ]; then
        return 1  # ccusage not available
    fi

    if ! command -v jq &> /dev/null; then
        return 7  # jq not available
    fi

    local json_output
    if [ "$cmd" = "ccusage" ]; then
        json_output=$(ccusage blocks --json 2>/dev/null)
    else
        json_output=$($cmd ccusage blocks --json 2>/dev/null)
    fi

    if [ -z "$json_output" ]; then
        return 3  # No output from ccusage
    fi

    local active_block=$(echo "$json_output" | jq -r '.blocks[] | select(.isActive == true)' 2>/dev/null | head -1)

    if [ -z "$active_block" ]; then
        return 3  # No active block found
    fi

    # Try projection.remainingMinutes first (most accurate)
    local remaining_minutes=$(echo "$json_output" | jq -r '.blocks[] | select(.isActive == true) | .projection.remainingMinutes' 2>/dev/null | head -1)

    # Fall back to endTime calculation if projection not yet available
    if [ -z "$remaining_minutes" ] || [ "$remaining_minutes" = "null" ]; then
        local end_time=$(echo "$json_output" | jq -r '.blocks[] | select(.isActive == true) | .endTime' 2>/dev/null | head -1)
        if [ -n "$end_time" ] && [ "$end_time" != "null" ]; then
            local end_epoch=$(date -d "$end_time" +%s 2>/dev/null)
            local now_epoch=$(date +%s)
            remaining_minutes=$(( (end_epoch - now_epoch) / 60 ))
        else
            return 3  # No usable timing data
        fi
    fi

    if ! [[ "$remaining_minutes" =~ ^[0-9]+$ ]]; then
        return 4  # Invalid format
    fi

    if [ "$remaining_minutes" -lt 0 ] || [ "$remaining_minutes" -gt 300 ]; then
        return 5  # Invalid range
    fi

    echo "$remaining_minutes"
    return 0
}

# Get the Unix epoch timestamp when the active billing block expires
# Returns: epoch via echo
# Return codes: 0=success, 1=no ccusage, 3=no active block, 7=no jq
get_block_end_epoch() {
    local cmd=$(get_ccusage_cmd)
    if [ $? -ne 0 ]; then
        return 1  # ccusage not available
    fi

    if ! command -v jq &> /dev/null; then
        return 7  # jq not available
    fi

    local json_output
    if [ "$cmd" = "ccusage" ]; then
        json_output=$(ccusage blocks --json 2>/dev/null)
    else
        json_output=$($cmd ccusage blocks --json 2>/dev/null)
    fi

    if [ -z "$json_output" ]; then
        return 3  # No output
    fi

    local end_time=$(echo "$json_output" | jq -r '.blocks[] | select(.isActive == true) | .endTime' 2>/dev/null | head -1)

    if [ -z "$end_time" ] || [ "$end_time" = "null" ]; then
        return 3  # No active block
    fi

    local end_epoch=$(date -d "$end_time" +%s 2>/dev/null)
    if [ -z "$end_epoch" ]; then
        return 3  # Could not parse time
    fi

    echo "$end_epoch"
    return 0
}

# Query ccusage for remaining time in the active block.
# Sets: TIMING_SOURCE and REMAINING_SECONDS globals
# Returns: 0 on success, 1 if no data available
get_remaining_time() {
    local minutes=$(get_minutes_until_reset 2>/dev/null)
    local ret=$?
    if [ $ret -eq 0 ] && [ -n "$minutes" ]; then
        TIMING_SOURCE="ccusage"
        REMAINING_SECONDS=$((minutes * 60))
        return 0
    fi

    TIMING_SOURCE="none"
    REMAINING_SECONDS=0
    return 1
}

# Verify that an active Claude session exists with sufficient time remaining
# Returns: 0 if verified active (>60 min via ccusage), 1 otherwise
# Sets: TIMING_SOURCE and REMAINING_SECONDS globals
verify_session_active() {
    get_remaining_time
    local ret=$?

    if [ $ret -ne 0 ]; then
        return 1  # No timing available
    fi

    if [ "$TIMING_SOURCE" != "ccusage" ]; then
        return 2  # Not API-verified
    fi

    local minutes=$((REMAINING_SECONDS / 60))

    if [ "$minutes" -le 60 ]; then
        return 3  # Not enough time remaining
    fi

    return 0
}

# Write block end epoch to state file (read by dashboard)
write_state_file() {
    local end_epoch="$1"
    echo "BLOCK_END_EPOCH=$end_epoch" > "$DAEMON_STATE_FILE"
}

# Read state file into BLOCK_END_EPOCH global
# Returns: 0 on success, 1 if unavailable
read_state_file() {
    BLOCK_END_EPOCH=""
    if [ ! -f "$DAEMON_STATE_FILE" ]; then
        return 1
    fi
    local val
    val=$(grep "^BLOCK_END_EPOCH=" "$DAEMON_STATE_FILE" 2>/dev/null | cut -d= -f2)
    if [ -z "$val" ]; then
        return 1
    fi
    BLOCK_END_EPOCH="$val"
    return 0
}

# Clear state file (called on daemon shutdown)
clear_state_file() {
    rm -f "$DAEMON_STATE_FILE"
}

# Save daemon PID to config file (called on daemon startup)
save_daemon_config() {
    cat > "$DAEMON_CONFIG_FILE" <<EOF
# Auto-generated daemon config
# Created: $(date)
DAEMON_PID=$$
EOF
    chmod 600 "$DAEMON_CONFIG_FILE"
}

# Clear daemon configuration (called on daemon shutdown)
clear_daemon_config() {
    rm -f "$DAEMON_CONFIG_FILE"
}
