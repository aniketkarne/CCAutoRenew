#!/bin/bash

# Comprehensive Test Script for CC AutoRenew with Start-Time Feature
# Tests all components including new start-time functionality

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Test files and directories
TEST_DIR="/tmp/cc-autorenew-test-$$"
DAEMON_MANAGER="./claude-daemon-manager.sh"
DAEMON_SCRIPT="./claude-auto-renew-daemon.sh"
SETUP_SCRIPT="./setup-claude-cron.sh"

print_header() {
    echo -e "\n${PURPLE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${NC}                ${BLUE}CC AutoRenew - Comprehensive Test Suite${NC}                ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════════════════════════════╝${NC}\n"
}

print_test() {
    ((TESTS_TOTAL++))
    echo -e "\n${BLUE}[TEST $TESTS_TOTAL]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++))
}

print_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

print_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Test 1: Basic file existence and permissions
test_basic_setup() {
    print_test "Checking basic setup and file permissions"
    
    local scripts=(
        "claude-daemon-manager.sh"
        "claude-auto-renew-daemon.sh"
        "claude-auto-renew-advanced.sh"
        "claude-auto-renew.sh"
        "setup-claude-cron.sh"
        "test-quick.sh"
        "test-claude-renewal.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [ -f "$script" ] && [ -x "$script" ]; then
            print_success "$script exists and is executable"
        else
            print_fail "$script missing or not executable"
        fi
    done
}

# Test 2: Dependencies check
test_dependencies() {
    print_test "Checking dependencies and tools"
    
    # Check for claude command
    if command -v claude &> /dev/null; then
        print_success "claude command found"
    else
        print_warning "claude command not found - some tests will be limited"
    fi
    
    # Check for ccusage availability
    if command -v ccusage &> /dev/null; then
        print_success "ccusage found (direct install)"
    elif command -v bunx &> /dev/null; then
        print_success "bunx available for ccusage"
    elif command -v npx &> /dev/null; then
        print_success "npx available for ccusage"
    else
        print_warning "ccusage not available - will test fallback mode"
    fi
    
    # Check for expect (optional)
    if command -v expect &> /dev/null; then
        print_success "expect found for advanced automation"
    else
        print_info "expect not found - will use fallback methods"
    fi
}

# Test 3: Daemon manager basic functionality
test_daemon_manager_basic() {
    print_test "Testing daemon manager basic functionality"
    
    # Test help message
    if "$DAEMON_MANAGER" 2>&1 | grep -q "Usage:"; then
        print_success "Help message displays correctly"
    else
        print_fail "Help message not working"
    fi
    
    # Test status when not running
    if "$DAEMON_MANAGER" status 2>&1 | grep -q "not running"; then
        print_success "Status correctly reports daemon not running"
    else
        print_fail "Status command not working when daemon stopped"
    fi
}

# Test 4: Start time parsing and validation
test_start_time_parsing() {
    print_test "Testing start time parsing and validation"
    
    # Test invalid time format
    if "$DAEMON_MANAGER" start --at "invalid" 2>&1 | grep -qE "Invalid (start |stop )?time format"; then
        print_success "Invalid time format correctly rejected"
    else
        print_fail "Invalid time format not properly handled"
    fi
    
    # Test valid time format (future time)
    future_time=$(date -d "+1 hour" "+%H:%M" 2>/dev/null || date -v+1H "+%H:%M" 2>/dev/null)
    if [ -n "$future_time" ]; then
        print_info "Testing with future time: $future_time"
        # This should succeed but we'll stop it immediately
        if "$DAEMON_MANAGER" start --at "$future_time" 2>&1 | grep -q "Daemon started successfully"; then
            print_success "Valid future time format accepted"
            # Stop the daemon
            "$DAEMON_MANAGER" stop >/dev/null 2>&1
        else
            print_fail "Valid time format rejected"
        fi
    else
        print_warning "Could not generate future time for testing"
    fi
}

# Test 5: Start time file management
test_start_time_files() {
    print_test "Testing start time file management"
    
    # Start daemon with specific time
    future_time=$(date -d "+2 hours" "+%H:%M" 2>/dev/null || date -v+2H "+%H:%M" 2>/dev/null)
    if [ -n "$future_time" ]; then
        "$DAEMON_MANAGER" start --at "$future_time" >/dev/null 2>&1
        
        # Check if start time file was created
        if [ -f "$HOME/.claude-auto-renew-start-time" ]; then
            print_success "Start time file created correctly"
            
            # Check if file contains valid epoch timestamp
            start_epoch=$(cat "$HOME/.claude-auto-renew-start-time")
            if [[ "$start_epoch" =~ ^[0-9]+$ ]]; then
                print_success "Start time file contains valid timestamp"
            else
                print_fail "Start time file contains invalid data"
            fi
        else
            print_fail "Start time file not created"
        fi
        
        # Stop daemon
        "$DAEMON_MANAGER" stop >/dev/null 2>&1
        
        # Start without time (should remove file)
        "$DAEMON_MANAGER" start >/dev/null 2>&1
        sleep 1
        
        if [ ! -f "$HOME/.claude-auto-renew-start-time" ]; then
            print_success "Start time file correctly removed when starting without time"
        else
            print_fail "Start time file not removed when starting without time"
        fi
        
        "$DAEMON_MANAGER" stop >/dev/null 2>&1
    else
        print_warning "Could not test start time files - date command issues"
    fi
}

# Test 6: Daemon status with start times
test_daemon_status_with_start_time() {
    print_test "Testing daemon status with start time information"
    
    # Start with future time
    future_time=$(date -d "+30 minutes" "+%H:%M" 2>/dev/null || date -v+30M "+%H:%M" 2>/dev/null)
    if [ -n "$future_time" ]; then
        "$DAEMON_MANAGER" start --at "$future_time" >/dev/null 2>&1
        sleep 2
        
        # Check status output
        status_output=$("$DAEMON_MANAGER" status 2>&1)
        
        if echo "$status_output" | grep -q "WAITING"; then
            print_success "Status correctly shows WAITING when before start time"
        else
            print_fail "Status does not show WAITING state"
        fi
        
        if echo "$status_output" | grep -q "Will activate in"; then
            print_success "Status shows time until activation"
        else
            print_fail "Status does not show activation countdown"
        fi
        
        "$DAEMON_MANAGER" stop >/dev/null 2>&1
    else
        print_warning "Could not test status with start time - date command issues"
    fi
}

# Test 7: Daemon log messages with start time
test_daemon_logging_with_start_time() {
    print_test "Testing daemon logging with start time functionality"
    
    # Clear existing log
    > "$HOME/.claude-auto-renew-daemon.log" 2>/dev/null
    
    # Start with future time
    future_time=$(date -d "+15 minutes" "+%H:%M" 2>/dev/null || date -v+15M "+%H:%M" 2>/dev/null)
    if [ -n "$future_time" ]; then
        "$DAEMON_MANAGER" start --at "$future_time" >/dev/null 2>&1
        sleep 3
        
        # Check log for start time messages
        if [ -f "$HOME/.claude-auto-renew-daemon.log" ]; then
            if grep -q "Start time configured" "$HOME/.claude-auto-renew-daemon.log"; then
                print_success "Daemon logs start time configuration"
            else
                print_fail "Daemon does not log start time configuration"
            fi
            
            if grep -q "Waiting for start time" "$HOME/.claude-auto-renew-daemon.log"; then
                print_success "Daemon logs waiting state"
            else
                print_fail "Daemon does not log waiting state"
            fi
        else
            print_fail "Daemon log file not created"
        fi
        
        "$DAEMON_MANAGER" stop >/dev/null 2>&1
    else
        print_warning "Could not test daemon logging - date command issues"
    fi
}

# Test 8: Setup script functionality
test_setup_script() {
    print_test "Testing setup script functionality"
    
    # Test help/options display
    if echo "invalid" | "$SETUP_SCRIPT" 2>&1 | grep -q "Invalid choice"; then
        print_success "Setup script handles invalid input correctly"
    else
        print_fail "Setup script does not handle invalid input"
    fi
    
    # The interactive nature makes it hard to fully test automatically
    print_info "Setup script requires manual testing for full validation"
}

# Test 9: Integration test with very short start time
test_short_start_time_integration() {
    print_test "Testing integration with short start time (next minute)"
    
    # Only run this test if user confirms
    echo ""
    echo "This test will start the daemon with a start time in the next minute"
    echo "and verify it activates correctly. This takes about 90 seconds."
    read -p "Run integration test? (y/n): " run_integration
    
    if [[ "$run_integration" =~ ^[Yy]$ ]]; then
        print_info "Starting 30-second integration test..."
        
        # Clear logs
        > "$HOME/.claude-auto-renew-daemon.log" 2>/dev/null
        
        # Calculate time 45 seconds in future (but rounded to next minute)
        current_epoch=$(date +%s)
        future_epoch=$((current_epoch + 45))
        # Round up to next minute to ensure we have a proper window
        future_minute=$((future_epoch / 60 + 1))
        future_epoch=$((future_minute * 60))
        future_time=$(date -d "@$future_epoch" "+%H:%M" 2>/dev/null || date -r "$future_epoch" "+%H:%M" 2>/dev/null)
        
        if [ -n "$future_time" ]; then
            # Start daemon
            "$DAEMON_MANAGER" start --at "$future_time" >/dev/null 2>&1
            
            print_info "Daemon started, waiting for start time activation..."
            print_info "Start time: $future_time"
            
            # Calculate how long to wait (time until start + 10 seconds buffer)
            wait_time=$((future_epoch - current_epoch + 10))
            print_info "Waiting ${wait_time} seconds for activation..."
            sleep "$wait_time"
            
            # Check if daemon is now active
            status_output=$("$DAEMON_MANAGER" status 2>&1)
            if echo "$status_output" | grep -q "ACTIVE"; then
                print_success "Daemon successfully activated after start time"
            else
                print_fail "Daemon did not activate after start time"
            fi
            
            # Check logs for activation message
            if grep -q "Start time reached" "$HOME/.claude-auto-renew-daemon.log"; then
                print_success "Daemon logged start time activation"
            else
                print_fail "Daemon did not log start time activation"
            fi
            
            "$DAEMON_MANAGER" stop >/dev/null 2>&1
        else
            print_fail "Could not calculate future time for integration test"
        fi
    else
        print_info "Integration test skipped"
    fi
}

# Test 10: Cleanup and file management
test_cleanup() {
    print_test "Testing cleanup and file management"
    
    # Ensure daemon is stopped
    "$DAEMON_MANAGER" stop >/dev/null 2>&1
    
    # Check that PID file is removed
    if [ ! -f "$HOME/.claude-auto-renew-daemon.pid" ]; then
        print_success "PID file correctly removed after stop"
    else
        print_fail "PID file not removed after stop"
        rm -f "$HOME/.claude-auto-renew-daemon.pid"
    fi
    
    # Clean up test files
    rm -f "$HOME/.claude-auto-renew-start-time" 2>/dev/null
    rm -f "$HOME/.claude-auto-renew-start-time.activated" 2>/dev/null
    
    print_info "Test cleanup completed"
}

# Main test execution
main() {
    print_header
    
    print_info "Testing CC AutoRenew with Start-Time Feature"
    print_info "Test timestamp: $(date)"
    print_info "Current directory: $(pwd)"
    
    # Run all tests
    test_basic_setup
    test_dependencies
    test_daemon_manager_basic
    test_start_time_parsing
    test_start_time_files
    test_daemon_status_with_start_time
    test_daemon_logging_with_start_time
    test_setup_script
    test_short_start_time_integration
    test_cleanup
    
    # Summary
    echo -e "\n${PURPLE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${NC}                           ${BLUE}TEST SUMMARY${NC}                            ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "Total Tests: ${BLUE}$TESTS_TOTAL${NC}"
    echo -e "${GREEN}Passed:${NC} $TESTS_PASSED"
    echo -e "${RED}Failed:${NC} $TESTS_FAILED"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "\n${GREEN}🎉 All tests passed! CC AutoRenew with start-time feature is working correctly.${NC}"
        echo ""
        echo "Ready for production use with commands like:"
        echo "  ./claude-daemon-manager.sh start --at '09:00'"
        echo "  ./setup-claude-cron.sh"
        exit 0
    else
        echo -e "\n${RED}❌ Some tests failed. Please check the errors above.${NC}"
        exit 1
    fi
}

# Handle Ctrl+C gracefully
trap 'echo -e "\n${YELLOW}Test interrupted. Cleaning up...${NC}"; "$DAEMON_MANAGER" stop >/dev/null 2>&1; exit 1' INT

# Run tests
main "$@" 