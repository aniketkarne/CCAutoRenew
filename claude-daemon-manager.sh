#!/bin/bash

# Claude Daemon Manager - Start, stop, and manage the auto-renewal daemon

DAEMON_SCRIPT="$(cd "$(dirname "$0")" && pwd)/claude-auto-renew-daemon.sh"
PID_FILE="$HOME/.claude-auto-renew-daemon.pid"
LOG_FILE="$HOME/.claude-auto-renew-daemon.log"
START_TIME_FILE="$HOME/.claude-auto-renew-start-time"
STOP_TIME_FILE="$HOME/.claude-auto-renew-stop-time"
MESSAGE_FILE="$HOME/.claude-auto-renew-message"

# Load shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/ccusage-utils.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

start_daemon() {
    # Parse --at and --stop parameters
    START_TIME=""
    STOP_TIME=""
    CUSTOM_MESSAGE=""

    # Parse parameters
    while [[ $# -gt 1 ]]; do
        case $2 in
            --at)
                START_TIME="$3"
                shift 2
                ;;
            --stop)
                STOP_TIME="$3"
                shift 2
                ;;
            --message)
                CUSTOM_MESSAGE="$3"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    # Process start time
    if [ -n "$START_TIME" ]; then
        # Validate and convert start time to epoch
        if [[ "$START_TIME" =~ ^[0-9]{2}:[0-9]{2}$ ]]; then
            # Format: "HH:MM" - assume today
            START_TIME="$(date '+%Y-%m-%d') $START_TIME:00"
        fi
        
        # Convert to epoch timestamp
        START_EPOCH=$(date -d "$START_TIME" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$START_TIME" +%s 2>/dev/null)
        
        if [ $? -ne 0 ]; then
            print_error "Invalid start time format. Use 'HH:MM' or 'YYYY-MM-DD HH:MM'"
            return 1
        fi
        
        # Store start time
        echo "$START_EPOCH" > "$START_TIME_FILE"
        print_status "Daemon will start monitoring at: $(date -d "@$START_EPOCH" 2>/dev/null || date -r "$START_EPOCH")"
    else
        # Remove any existing start time (start immediately)
        rm -f "$START_TIME_FILE" 2>/dev/null
    fi
    
    # Process stop time
    if [ -n "$STOP_TIME" ]; then
        # Validate and convert stop time to epoch
        if [[ "$STOP_TIME" =~ ^[0-9]{2}:[0-9]{2}$ ]]; then
            # Format: "HH:MM" - assume today
            STOP_TIME="$(date '+%Y-%m-%d') $STOP_TIME:00"
        fi
        
        # Convert to epoch timestamp
        STOP_EPOCH=$(date -d "$STOP_TIME" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$STOP_TIME" +%s 2>/dev/null)
        
        if [ $? -ne 0 ]; then
            print_error "Invalid stop time format. Use 'HH:MM' or 'YYYY-MM-DD HH:MM'"
            return 1
        fi
        
        # Validate that stop time is after start time
        if [ -n "$START_EPOCH" ] && [ "$STOP_EPOCH" -le "$START_EPOCH" ]; then
            print_error "Stop time must be after start time"
            return 1
        fi
        
        # Store stop time
        echo "$STOP_EPOCH" > "$STOP_TIME_FILE"
        print_status "Daemon will stop monitoring at: $(date -d "@$STOP_EPOCH" 2>/dev/null || date -r "$STOP_EPOCH")"
    else
        # Remove any existing stop time
        rm -f "$STOP_TIME_FILE" 2>/dev/null
    fi
    
    # Process custom message
    if [ -n "$CUSTOM_MESSAGE" ]; then
        # Store custom message
        echo "$CUSTOM_MESSAGE" > "$MESSAGE_FILE"
        print_status "Using custom renewal message: \"$CUSTOM_MESSAGE\""
    else
        # Remove any existing custom message (use default messages)
        rm -f "$MESSAGE_FILE" 2>/dev/null
    fi
    
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            print_error "Daemon is already running with PID $PID"
            return 1
        fi
    fi
    
    print_status "Starting Claude auto-renewal daemon..."
    touch "$HOME/.claude-auto-renew-renew-on-start"
    nohup "$DAEMON_SCRIPT" > /dev/null 2>&1 &
    
    sleep 2
    
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            print_status "Daemon started successfully with PID $PID"
            if [ -f "$START_TIME_FILE" ]; then
                START_EPOCH=$(cat "$START_TIME_FILE")
                print_status "Will begin auto-renewal at: $(date -d "@$START_EPOCH" 2>/dev/null || date -r "$START_EPOCH")"
            fi
            print_status "Logs: $LOG_FILE"
            return 0
        fi
    fi
    
    print_error "Failed to start daemon"
    return 1
}

stop_daemon() {
    if [ ! -f "$PID_FILE" ]; then
        print_warning "Daemon is not running (no PID file found)"
        return 1
    fi
    
    PID=$(cat "$PID_FILE")
    
    if ! kill -0 "$PID" 2>/dev/null; then
        print_warning "Daemon is not running (process $PID not found)"
        rm -f "$PID_FILE"
        return 1
    fi
    
    print_status "Stopping daemon with PID $PID..."
    kill "$PID"
    
    # Wait for graceful shutdown
    for i in {1..10}; do
        if ! kill -0 "$PID" 2>/dev/null; then
            print_status "Daemon stopped successfully"
            rm -f "$PID_FILE"
            return 0
        fi
        sleep 1
    done
    
    # Force kill if still running
    print_warning "Daemon did not stop gracefully, forcing..."
    kill -9 "$PID" 2>/dev/null
    rm -f "$PID_FILE"
    print_status "Daemon stopped"
}

# Get daemon timing information
get_daemon_timing_info() {
    current_epoch=$(date +%s)
    start_epoch=""
    stop_epoch=""
    
    if [ -f "$START_TIME_FILE" ]; then
        start_epoch=$(cat "$START_TIME_FILE")
    fi
    
    if [ -f "$STOP_TIME_FILE" ]; then
        stop_epoch=$(cat "$STOP_TIME_FILE")
    fi
    
    # Return values via global variables
    CURRENT_EPOCH="$current_epoch"
    START_EPOCH="$start_epoch"
    STOP_EPOCH="$stop_epoch"
}

# Get daemon status information
get_daemon_status() {
    get_daemon_timing_info
    
    # Determine current status
    if [ -n "$START_EPOCH" ] && [ "$CURRENT_EPOCH" -lt "$START_EPOCH" ]; then
        # Before start time
        time_until_start=$((START_EPOCH - CURRENT_EPOCH))
        hours=$((time_until_start / 3600))
        minutes=$(((time_until_start % 3600) / 60))
        DAEMON_STATUS="WAITING"
        DAEMON_STATUS_TEXT="⏰ WAITING - Will activate in ${hours}h ${minutes}m"
        DAEMON_STATUS_DETAIL="Start time: $(date -d "@$START_EPOCH" 2>/dev/null || date -r "$START_EPOCH")"
    elif [ -n "$STOP_EPOCH" ] && [ "$CURRENT_EPOCH" -ge "$STOP_EPOCH" ]; then
        # After stop time
        DAEMON_STATUS="STOPPED"
        DAEMON_STATUS_TEXT="🛑 STOPPED - Monitoring ended for today"
        DAEMON_STATUS_DETAIL="Stop time: $(date -d "@$STOP_EPOCH" 2>/dev/null || date -r "$STOP_EPOCH")"
        if [ -n "$START_EPOCH" ]; then
            # Calculate next day start time
            next_start=$((START_EPOCH + 86400))
            DAEMON_STATUS_DETAIL="$DAEMON_STATUS_DETAIL\nNext start: $(date -d "@$next_start" 2>/dev/null || date -r "$next_start")"
        fi
    else
        # Active period
        DAEMON_STATUS="ACTIVE"
        DAEMON_STATUS_TEXT="✅ ACTIVE - Auto-renewal monitoring enabled"
        if [ -n "$STOP_EPOCH" ]; then
            time_until_stop=$((STOP_EPOCH - CURRENT_EPOCH))
            if [ "$time_until_stop" -gt 0 ]; then
                hours=$((time_until_stop / 3600))
                minutes=$(((time_until_stop % 3600) / 60))
                DAEMON_STATUS_DETAIL="Will stop in ${hours}h ${minutes}m at: $(date -d "@$STOP_EPOCH" 2>/dev/null || date -r "$STOP_EPOCH")"
            fi
        fi
    fi
}

# Get next renewal estimate from daemon state file
get_next_renewal_estimate() {
    get_daemon_timing_info

    NEXT_RENEWAL_TIME=""
    NEXT_RENEWAL_REMAINING=""

    read_state_file
    if [ -z "$BLOCK_END_EPOCH" ]; then
        return
    fi

    local remaining_secs=$(( BLOCK_END_EPOCH - CURRENT_EPOCH ))
    if [ "$remaining_secs" -le 0 ]; then
        return
    fi

    local hours=$((remaining_secs / 3600))
    local minutes=$(((remaining_secs % 3600) / 60))
    NEXT_RENEWAL_REMAINING="${hours}h ${minutes}m"

    # Renewal fires 5 min past block end (blocks expire at the top of the hour)
    local next_renewal_epoch=$(( BLOCK_END_EPOCH + 300 ))
    NEXT_RENEWAL_TIME=$(date -d "@$next_renewal_epoch" '+%H:%M' 2>/dev/null || date -r "$next_renewal_epoch" '+%H:%M')
}

# Generate day plan with estimated renewal times
generate_day_plan() {
    get_daemon_timing_info
    
    # Clear the day plan array
    DAY_PLAN=()
    
    # Get current date for calculations
    current_date=$(date '+%Y-%m-%d')
    day_start_epoch=$(date -d "$current_date 00:00:00" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$current_date 00:00:00" +%s 2>/dev/null)
    day_end_epoch=$((day_start_epoch + 86400))
    
    # Determine the active window for today
    active_start=$day_start_epoch
    active_end=$day_end_epoch
    
    if [ -n "$START_EPOCH" ]; then
        # Use today's version of start time
        start_time_today=$(date -d "@$START_EPOCH" '+%H:%M:%S' 2>/dev/null || date -r "$START_EPOCH" '+%H:%M:%S')
        active_start=$(date -d "$current_date $start_time_today" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$current_date $start_time_today" +%s 2>/dev/null)
    fi
    
    if [ -n "$STOP_EPOCH" ]; then
        # Use today's version of stop time
        stop_time_today=$(date -d "@$STOP_EPOCH" '+%H:%M:%S' 2>/dev/null || date -r "$STOP_EPOCH" '+%H:%M:%S')
        active_end=$(date -d "$current_date $stop_time_today" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$current_date $stop_time_today" +%s 2>/dev/null)
    fi
    
    # Use state file for renewal schedule (written by daemon, no ccusage call needed)
    read_state_file

    if [ -n "$BLOCK_END_EPOCH" ]; then
        # First renewal is 5 min past block end (blocks expire at top of hour)
        local first_renewal=$(( BLOCK_END_EPOCH + 300 ))

        current_renewal=$first_renewal
        local is_first_renewal=true
        while [ $current_renewal -lt $day_end_epoch ]; do
            if [ $current_renewal -ge $active_start ] && [ $current_renewal -le $active_end ]; then
                renewal_time_str=$(date -d "@$current_renewal" '+%H:%M' 2>/dev/null || date -r "$current_renewal" '+%H:%M')

                if [ "$is_first_renewal" = true ]; then
                    DAY_PLAN+=("$renewal_time_str (NEXT)")
                    is_first_renewal=false
                else
                    DAY_PLAN+=("$renewal_time_str")
                fi
            fi

            # Next renewal is 5 hours later
            current_renewal=$((current_renewal + 18000))
        done
    fi
    
    # If no renewals planned, show when monitoring is active
    if [ ${#DAY_PLAN[@]} -eq 0 ]; then
        if [ -n "$START_EPOCH" ] && [ -n "$STOP_EPOCH" ]; then
            start_time_str=$(date -d "@$START_EPOCH" '+%H:%M' 2>/dev/null || date -r "$START_EPOCH" '+%H:%M')
            stop_time_str=$(date -d "@$STOP_EPOCH" '+%H:%M' 2>/dev/null || date -r "$STOP_EPOCH" '+%H:%M')
            DAY_PLAN+=("Monitoring: $start_time_str - $stop_time_str")
            DAY_PLAN+=("(No renewals needed today)")
        else
            DAY_PLAN+=("24/7 monitoring active")
            DAY_PLAN+=("(Renewals as needed)")
        fi
    fi
}

# Create progress bar for time until next reset
create_progress_bar() {
    local current_time="$1"
    local total_time="$2"
    local remaining_time="$3"
    
    if [ $total_time -le 0 ]; then
        echo "No progress data available"
        return
    fi
    
    # Calculate percentage
    local elapsed_time=$((total_time - remaining_time))
    local percentage=$((elapsed_time * 100 / total_time))
    
    # Ensure percentage is within bounds
    if [ $percentage -lt 0 ]; then
        percentage=0
    elif [ $percentage -gt 100 ]; then
        percentage=100
    fi
    
    # Create the bar (40 characters wide)
    local bar_length=40
    local filled_length=$((percentage * bar_length / 100))
    local empty_length=$((bar_length - filled_length))
    
    # Color codes
    local green='\033[0;32m'
    local yellow='\033[1;33m'
    local red='\033[0;31m'
    local nc='\033[0m'
    
    # Choose color based on remaining time
    local color="$green"
    if [ $remaining_time -lt 1800 ]; then  # Less than 30 minutes
        color="$red"
    elif [ $remaining_time -lt 3600 ]; then  # Less than 1 hour
        color="$yellow"
    fi
    
    # Build the progress bar
    local filled_bar=""
    local empty_bar=""
    
    # Create filled portion
    for i in $(seq 1 $filled_length); do
        filled_bar="${filled_bar}█"
    done
    
    # Create empty portion  
    for i in $(seq 1 $empty_length); do
        empty_bar="${empty_bar}░"
    done
    
    # Format remaining time
    local hours=$((remaining_time / 3600))
    local minutes=$(((remaining_time % 3600) / 60))
    
    # Display the progress bar
    echo -e "  ${color}${filled_bar}${nc}${empty_bar} ${percentage}% (${hours}h ${minutes}m remaining)"
}

# Dashboard function with live updates
dash_daemon() {
    # Check if daemon is running first
    if [ ! -f "$PID_FILE" ]; then
        print_error "Daemon is not running"
        echo "Start the daemon with: $0 start"
        return 1
    fi
    
    PID=$(cat "$PID_FILE")
    if ! kill -0 "$PID" 2>/dev/null; then
        print_error "Daemon is not running (process $PID not found)"
        rm -f "$PID_FILE"
        echo "Start the daemon with: $0 start"
        return 1
    fi
    
    # Trap Ctrl+C to exit gracefully
    trap 'echo ""; echo "Dashboard stopped."; exit 0' INT
    
    echo "Claude Auto-Renewal Dashboard (Press Ctrl+C to exit)"
    echo "Updating every minute..."
    echo ""
    
    while true; do
        # Clear screen and show header
        clear
        echo "╔══════════════════════════════════════════════════════════════════════════════╗"
        echo "║                    Claude Auto-Renewal Dashboard                            ║"
        echo "║                   $(date '+%A, %B %d, %Y - %H:%M:%S')                   ║"
        echo "╚══════════════════════════════════════════════════════════════════════════════╝"
        echo ""
        
        # Get current daemon status
        get_daemon_status
        
        echo "🔧 DAEMON STATUS:"
        echo "  PID: $PID"
        echo "  Status: $DAEMON_STATUS_TEXT"
        if [ -n "$DAEMON_STATUS_DETAIL" ]; then
            echo -e "$DAEMON_STATUS_DETAIL" | sed 's/^/  /'
        fi
        echo ""
        
        # Show progress bar for next renewal (reads state file, no ccusage call)
        get_next_renewal_estimate
        echo "⏱️  TIME TO NEXT RESET:"
        if [ -n "$NEXT_RENEWAL_REMAINING" ]; then
            local remaining_secs=$(( BLOCK_END_EPOCH - $(date +%s) ))
            if [ "$remaining_secs" -gt 0 ]; then
                create_progress_bar "$(date +%s)" 18000 "$remaining_secs"
                echo "  Next renewal at: $NEXT_RENEWAL_TIME"
            else
                echo "  🚨 Renewal window active now!"
            fi
        else
            echo "  No active session block detected"
        fi
        echo ""
        
        # Show day plan
        generate_day_plan
        echo "📅 TODAY'S RENEWAL PLAN:"
        if [ ${#DAY_PLAN[@]} -gt 0 ]; then
            for plan_item in "${DAY_PLAN[@]}"; do
                echo "  • $plan_item"
            done
        else
            echo "  No renewal plan available"
        fi
        echo ""
        
        # Show recent activity
        if [ -f "$LOG_FILE" ]; then
            local last_model
            last_model=$(grep "Starting Claude session for renewal" "$LOG_FILE" | tail -1 | grep -o 'model: [^)]*' | sed 's/model: //')
            echo "📝 RECENT ACTIVITY:"
            [ -n "$last_model" ] && echo "  Last renewal model: $last_model"
            tail -10 "$LOG_FILE" | sed 's/^/  /'
        else
            echo "📝 RECENT ACTIVITY:"
            echo "  No log file found"
        fi
        echo ""
        
        echo "Last updated: $(date '+%H:%M:%S') | Press Ctrl+C to exit"
        
        # Wait 60 seconds before next update
        sleep 60
    done
}

status_daemon() {
    if [ ! -f "$PID_FILE" ]; then
        print_status "Daemon is not running"
        return 1
    fi
    
    PID=$(cat "$PID_FILE")
    
    if kill -0 "$PID" 2>/dev/null; then
        print_status "Daemon is running with PID $PID"
        
        get_daemon_status
        print_status "Status: $DAEMON_STATUS_TEXT"
        if [ -n "$DAEMON_STATUS_DETAIL" ]; then
            echo -e "$DAEMON_STATUS_DETAIL" | while IFS= read -r line; do
                print_status "$line"
            done
        fi
        
        # Show recent activity
        if [ -f "$LOG_FILE" ]; then
            echo ""
            print_status "Recent activity:"
            tail -5 "$LOG_FILE" | sed 's/^/  /'
        fi
        
        # Show next renewal estimate
        get_next_renewal_estimate
        if [ -n "$NEXT_RENEWAL_REMAINING" ]; then
            echo ""
            print_status "Estimated time until next renewal: $NEXT_RENEWAL_REMAINING"
        fi
        
        return 0
    else
        print_warning "Daemon is not running (process $PID not found)"
        rm -f "$PID_FILE"
        return 1
    fi
}

restart_daemon() {
    print_status "Restarting daemon..."
    stop_daemon
    sleep 2
    start_daemon
}

show_logs() {
    if [ ! -f "$LOG_FILE" ]; then
        print_error "No log file found"
        return 1
    fi
    
    if [ "$1" = "-f" ]; then
        tail -f "$LOG_FILE"
    else
        tail -50 "$LOG_FILE"
    fi
}

# Main command handling
case "$1" in
    start)
        start_daemon "$@"
        ;;
    stop)
        stop_daemon
        ;;
    restart)
        stop_daemon
        sleep 2
        start_daemon "$@"
        ;;
    status)
        status_daemon
        ;;
    logs)
        show_logs "$2"
        ;;
    dash)
        dash_daemon
        ;;
    *)
        echo "Claude Auto-Renewal Daemon Manager"
        echo ""
        echo "Usage: $0 {start|stop|restart|status|dash|logs} [options]"
        echo ""
        echo "Commands:"
        echo "  start                      - Start the daemon"
        echo "  start --at TIME            - Start daemon but begin monitoring at specified time"
        echo "  start --at TIME --stop END - Start monitoring at TIME, stop at END"
        echo "  start --message \"text\"     - Use custom message for renewal instead of random greetings"
        echo "                               Examples: --at '09:00' --stop '17:00'"
        echo "                                        --at '2025-01-28 09:00' --stop '2025-01-28 17:00'"
        echo "                                        --message 'continue working on the React feature'"
        echo "  stop                       - Stop the daemon"
        echo "  restart                    - Restart the daemon"
        echo "  status                     - Show daemon status"
        echo "  dash                       - Live dashboard with updates every minute"
        echo "  logs                       - Show recent logs (use 'logs -f' to follow)"
        echo ""
        echo "The daemon will:"
        echo "  - Monitor your Claude usage blocks within scheduled hours"
        echo "  - Automatically start a session when renewal is needed"
        echo "  - Stop monitoring at specified stop time"
        echo "  - Resume monitoring the next day at start time"
        echo "  - Prevent gaps in your 5-hour usage windows"
        ;;
esac