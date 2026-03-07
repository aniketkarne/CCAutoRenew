#!/bin/bash

# Claude Auto-Renewal Script
# This script checks if Claude usage limits have reset and automatically starts a session

# Configuration
LOG_FILE="$HOME/.claude-auto-renew.log"

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Function to check if we're within the reset window
check_reset_window() {
    # Run ccusage to get current block info
    # We'll parse the output to determine if we should start a session
    
    # First, check if ccusage is available
    if ! command -v ccusage &> /dev/null && ! command -v bunx &> /dev/null; then
        log_message "ERROR: ccusage not found. Please install it first."
        return 1
    fi
    
    # Get the current block information
    if command -v ccusage &> /dev/null; then
        BLOCK_INFO=$(ccusage blocks --json 2>/dev/null | jq -r '.current_block.time_remaining' 2>/dev/null)
    else
        BLOCK_INFO=$(bunx ccusage blocks --json 2>/dev/null | jq -r '.current_block.time_remaining' 2>/dev/null)
    fi
    
    # If we can't get block info, try alternative approach
    if [ -z "$BLOCK_INFO" ] || [ "$BLOCK_INFO" = "null" ]; then
        log_message "Could not get block info from ccusage, checking alternative method"
        
        # Check if there's been recent activity (within last 5 hours)
        LAST_ACTIVITY_FILE="$HOME/.claude-last-activity"
        
        if [ -f "$LAST_ACTIVITY_FILE" ]; then
            LAST_ACTIVITY=$(cat "$LAST_ACTIVITY_FILE")
            CURRENT_TIME=$(date +%s)
            TIME_DIFF=$((CURRENT_TIME - LAST_ACTIVITY))
            
            # If more than 5 hours have passed, we should start a session
            if [ $TIME_DIFF -gt 18000 ]; then  # 5 hours = 18000 seconds
                return 0  # Should start session
            else
                REMAINING=$((18000 - TIME_DIFF))
                log_message "Time until next reset: $((REMAINING / 60)) minutes"
                return 1  # Should not start session yet
            fi
        else
            # No activity file, safe to start
            return 0
        fi
    fi
    
    # Parse time remaining (assuming format like "2h 30m" or minutes)
    # If time remaining is less than 10 minutes, we should prepare to start a new session
    if [[ "$BLOCK_INFO" =~ ([0-9]+)m$ ]]; then
        MINUTES="${BASH_REMATCH[1]}"
        if [ "$MINUTES" -lt 10 ]; then
            log_message "Reset window approaching in $MINUTES minutes"
            return 0
        fi
    fi
    
    return 1
}

# Function to start Claude session
start_claude_session() {
    log_message "Starting Claude session to maintain renewal window"
    
    # Check if claude command exists
    if ! command -v claude &> /dev/null; then
        log_message "ERROR: claude command not found"
        return 1
    fi
    
    # Start claude with a simple command that exits immediately
    # Unset CLAUDECODE to allow renewal from within an existing Claude session
    (unset CLAUDECODE; echo "hi" | claude 2>&1 >> "$LOG_FILE")
    
    if [ $? -eq 0 ]; then
        log_message "Successfully started Claude session"
        # Update last activity time
        date +%s > "$HOME/.claude-last-activity"
        return 0
    else
        log_message "ERROR: Failed to start Claude session"
        return 1
    fi
}

# Main execution
log_message "Running Claude auto-renewal check"

# Check if we should start a session
if check_reset_window; then
    # Wait a bit to ensure we're past the reset time
    sleep 30
    start_claude_session
else
    log_message "Not time for renewal yet"
fi