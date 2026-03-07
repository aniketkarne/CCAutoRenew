#!/bin/bash

# Advanced Claude Auto-Renewal Script with ccusage integration
# This version uses ccusage to get accurate reset times

LOG_FILE="$HOME/.claude-auto-renew.log"
LAST_ACTIVITY_FILE="$HOME/.claude-last-activity"

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Function to get ccusage command
get_ccusage_cmd() {
    if command -v ccusage &> /dev/null; then
        echo "ccusage"
    elif command -v bunx &> /dev/null; then
        echo "bunx ccusage"
    elif command -v npx &> /dev/null; then
        echo "npx ccusage@latest"
    else
        return 1
    fi
}

# Function to parse time remaining from ccusage output
parse_time_remaining() {
    local ccusage_cmd=$(get_ccusage_cmd)
    if [ $? -ne 0 ]; then
        log_message "ERROR: ccusage not available"
        return 1
    fi
    
    # Try to get blocks info and extract time remaining
    local output=$($ccusage_cmd blocks 2>/dev/null | grep -i "time remaining" | head -1)
    
    if [ -z "$output" ]; then
        # Try live mode for more accurate info
        output=$($ccusage_cmd blocks --live 2>/dev/null | grep -i "remaining" | head -1)
    fi
    
    # Extract hours and minutes from various formats
    local hours=0
    local minutes=0
    
    if [[ "$output" =~ ([0-9]+)h[[:space:]]*([0-9]+)m ]]; then
        hours=${BASH_REMATCH[1]}
        minutes=${BASH_REMATCH[2]}
    elif [[ "$output" =~ ([0-9]+):[0-9]{2}:[0-9]{2} ]]; then
        hours=${BASH_REMATCH[1]}
        minutes=$(echo "$output" | sed -E 's/.*([0-9]+):([0-9]{2}):[0-9]{2}.*/\2/')
    elif [[ "$output" =~ ([0-9]+)m ]]; then
        minutes=${BASH_REMATCH[1]}
    fi
    
    # Convert to total minutes
    local total_minutes=$((hours * 60 + minutes))
    echo "$total_minutes"
}

# Function to check if we should start a session
should_start_session() {
    # First try to get accurate time from ccusage
    local minutes_remaining=$(parse_time_remaining)
    
    if [ -n "$minutes_remaining" ] && [ "$minutes_remaining" -gt 0 ]; then
        log_message "Time remaining in current block: $minutes_remaining minutes"
        
        # Start session if less than 5 minutes remaining
        if [ "$minutes_remaining" -lt 5 ]; then
            log_message "Reset window approaching, preparing to start session"
            return 0
        else
            return 1
        fi
    fi
    
    # Fallback: Check last activity time
    if [ -f "$LAST_ACTIVITY_FILE" ]; then
        local last_activity=$(cat "$LAST_ACTIVITY_FILE")
        local current_time=$(date +%s)
        local time_diff=$((current_time - last_activity))
        
        # If more than 5 hours (18000 seconds) have passed
        if [ $time_diff -gt 18000 ]; then
            log_message "More than 5 hours since last activity, starting session"
            return 0
        else
            local remaining=$((18000 - time_diff))
            log_message "Fallback check: $((remaining / 60)) minutes until 5-hour mark"
            
            # Start if within 5 minutes of the 5-hour mark
            if [ $remaining -lt 300 ]; then
                return 0
            fi
        fi
    else
        # No activity file exists, safe to start
        log_message "No previous activity found, starting session"
        return 0
    fi
    
    return 1
}

# Function to start Claude session
start_claude_session() {
    log_message "Attempting to start Claude session"
    
    # Check if claude command exists
    if ! command -v claude &> /dev/null; then
        log_message "ERROR: claude command not found"
        return 1
    fi
    
    # Create a temporary expect script for better automation
    cat > /tmp/claude_auto_start.exp << 'EOF'
#!/usr/bin/expect -f
set timeout 10
spawn claude
expect {
    ">" {
        send "hi\r"
        expect ">"
        send "exit\r"
    }
    timeout {
        send \003
        exit 1
    }
}
expect eof
EOF
    
    chmod +x /tmp/claude_auto_start.exp
    
    # Try using expect if available
    if command -v expect &> /dev/null; then
        /tmp/claude_auto_start.exp >> "$LOG_FILE" 2>&1
        local result=$?
    else
        # Fallback to simple echo with macOS-compatible timeout
        # Unset CLAUDECODE to allow renewal from within an existing Claude session
        (unset CLAUDECODE; echo "hi" | claude >> "$LOG_FILE" 2>&1) &
        local pid=$!
        
        # Wait up to 10 seconds
        local count=0
        while kill -0 $pid 2>/dev/null && [ $count -lt 10 ]; do
            sleep 1
            ((count++))
        done
        
        # Kill if still running
        if kill -0 $pid 2>/dev/null; then
            kill $pid 2>/dev/null
            wait $pid 2>/dev/null
            local result=124
        else
            wait $pid
            local result=$?
        fi
    fi
    
    # Clean up
    rm -f /tmp/claude_auto_start.exp
    
    if [ $result -eq 0 ]; then
        log_message "Successfully started Claude session"
        date +%s > "$LAST_ACTIVITY_FILE"
        return 0
    else
        log_message "ERROR: Failed to start Claude session (exit code: $result)"
        return 1
    fi
}

# Main execution
main() {
    log_message "=== Starting Claude auto-renewal check ==="
    
    # Check ccusage availability
    if ! get_ccusage_cmd &> /dev/null; then
        log_message "WARNING: ccusage not found. Install with: npm install -g ccusage"
        log_message "Falling back to time-based checking"
    fi
    
    # Check if we should start a session
    if should_start_session; then
        # Wait a moment to ensure we're in the renewal window
        log_message "Waiting 60 seconds to ensure renewal window..."
        sleep 60
        
        # Try to start session up to 3 times
        local attempts=0
        while [ $attempts -lt 3 ]; do
            if start_claude_session; then
                log_message "Session renewal successful"
                break
            else
                attempts=$((attempts + 1))
                log_message "Attempt $attempts failed, retrying in 30 seconds..."
                sleep 30
            fi
        done
        
        if [ $attempts -eq 3 ]; then
            log_message "ERROR: Failed to start session after 3 attempts"
        fi
    else
        log_message "Not time for renewal yet"
    fi
    
    log_message "=== Check complete ==="
}

# Run main function
main