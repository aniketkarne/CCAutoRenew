#!/bin/bash

# Test script for the new --message feature

# Sandbox helpers: the manager writes state under $HOME and the daemon runs
# for real, so tests run inside a throwaway HOME and never touch (or kill)
# the user's live daemon or its message config.
source "$(dirname "$0")/test-lib.sh"
sandbox_init

echo "Testing Claude Auto-Renewal Custom Message Feature"
echo "=================================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

TESTS_FAILED=0

print_test() {
    echo -e "${YELLOW}[TEST]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

# Test 1: Check that the daemon manager accepts --message parameter
print_test "Testing daemon manager with --message parameter..."
./claude-daemon-manager.sh stop 2>/dev/null

# Start daemon with custom message
./claude-daemon-manager.sh start --message "continue working on the React feature" --disableccusage

# Give it a moment to start
sleep 3

# Check if daemon is running
if ./claude-daemon-manager.sh status | grep -q "running"; then
    print_success "Daemon started successfully with --message parameter"
else
    print_error "Failed to start daemon with --message parameter"
    exit 1
fi

# Test 2: Check if message file was created
MESSAGE_FILE="$HOME/.claude-auto-renew-message"
if [ -f "$MESSAGE_FILE" ]; then
    message_content=$(cat "$MESSAGE_FILE")
    if [ "$message_content" = "continue working on the React feature" ]; then
        print_success "Custom message correctly saved: '$message_content'"
    else
        print_error "Message content incorrect: '$message_content'"
    fi
else
    print_error "Message file not created"
fi

# Test 3: Check daemon logs for custom message confirmation
LOG_FILE="$HOME/.claude-auto-renew-daemon.log"
if grep -q "Custom renewal message configured" "$LOG_FILE"; then
    print_success "Daemon logged custom message configuration"
else
    print_error "Daemon did not log custom message configuration"
fi

# Test 4: Stop and restart without message (should use default)
print_test "Testing daemon restart without --message parameter..."
./claude-daemon-manager.sh stop
sleep 2
./claude-daemon-manager.sh start --disableccusage
sleep 3

if [ -f "$MESSAGE_FILE" ]; then
    print_error "Message file still exists after restart without --message"
else
    print_success "Message file correctly removed when not using --message"
fi

# Check logs for default message confirmation
if tail -20 "$LOG_FILE" | grep -q "Using default random greeting messages"; then
    print_success "Daemon correctly switched to default messages"
else
    print_error "Daemon did not log switch to default messages"
fi

# Test 5: Test with different message
print_test "Testing with different custom message..."
./claude-daemon-manager.sh stop
sleep 2
./claude-daemon-manager.sh start --message "please resume our discussion about database optimization" --disableccusage
sleep 3

if [ -f "$MESSAGE_FILE" ]; then
    new_message=$(cat "$MESSAGE_FILE")
    if [ "$new_message" = "please resume our discussion about database optimization" ]; then
        print_success "New custom message correctly saved: '$new_message'"
    else
        print_error "New message content incorrect: '$new_message'"
    fi
else
    print_error "Message file not created for new message"
fi

# Cleanup
print_test "Cleaning up..."
./claude-daemon-manager.sh stop
sleep 2

echo ""
echo "=================================================="
echo "Test Summary:"
if [ "$TESTS_FAILED" -eq 0 ]; then
    echo "- Custom message parameter is working correctly"
    echo "- Message file is created and removed as expected"
    echo "- Daemon properly logs custom message usage"
    echo "- Multiple message changes work correctly"
    echo ""
    print_success "All tests passed! The --message feature is ready to use."
else
    echo ""
    print_error "$TESTS_FAILED check(s) failed - see [✗] lines above."
fi
echo ""
echo "Example usage:"
echo "  ./claude-daemon-manager.sh start --message \"continue working on the React feature\""
echo "  ./claude-daemon-manager.sh start --at \"09:00\" --message \"resume our Python project\""
echo ""

exit $((TESTS_FAILED > 0))