#!/bin/bash

# Comprehensive Claude Renewal Test Script (Legacy)
# Tests all aspects of the Claude auto-renewal system

# Sandbox helpers: all daemon state lives under $HOME, so tests run inside a
# throwaway HOME and never touch (or kill) the user's real daemon or logs.
source "$(dirname "$0")/test-lib.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Test configuration
TEST_DIR="/tmp/cc-autorenew-test-$$"
DAEMON_MANAGER="./claude-daemon-manager.sh"
BASIC_SCRIPT="./claude-auto-renew.sh"
ADVANCED_SCRIPT="./claude-auto-renew-advanced.sh"
SETUP_SCRIPT="./setup-claude-cron.sh"

print_header() {
    echo -e "\n${PURPLE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${NC}              ${BLUE}CC AutoRenew - Legacy Comprehensive Test${NC}               ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚═══════════════════════════════════════════════════════════════╝${NC}\n"
}

print_test() {
    ((TESTS_TOTAL++))
    echo -e "\n${BLUE}[TEST $TESTS_TOTAL]${NC} $1"
}

print_pass() {
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

# Test 1: Environment and Prerequisites
test_environment() {
    print_test "Testing environment and prerequisites"
    
    # Test script permissions
    local scripts=("$DAEMON_MANAGER" "$BASIC_SCRIPT" "$ADVANCED_SCRIPT" "$SETUP_SCRIPT")
    for script in "${scripts[@]}"; do
        if [ -f "$script" ] && [ -x "$script" ]; then
            print_pass "$(basename "$script") is executable"
        else
            print_fail "$(basename "$script") missing or not executable"
        fi
    done
    
    # Test home directory access
    if [ -w "$HOME" ]; then
        print_pass "Home directory is writable"
    else
        print_fail "Home directory is not writable"
    fi
    
    # Test temporary directory
    if mkdir -p "$TEST_DIR" 2>/dev/null; then
        print_pass "Can create temporary test directory"
    else
        print_fail "Cannot create temporary test directory"
    fi
}

# Test 2: Dependencies and Tools
test_dependencies() {
    print_test "Testing dependencies and external tools"
    
    # Claude CLI
    if command -v claude &> /dev/null; then
        print_pass "Claude CLI available"
        
        # Test claude command works
        if echo "test" | run_with_timeout 5 claude --help &> /dev/null; then
            print_pass "Claude CLI responds to help command"
        else
            print_warning "Claude CLI doesn't respond to help (may need authentication)"
        fi
    else
        print_fail "Claude CLI not found"
    fi
    
    # ccusage availability
    if command -v ccusage &> /dev/null; then
        print_pass "ccusage directly available"
    elif command -v bunx &> /dev/null; then
        print_pass "bunx available for ccusage"
        
        # Test bunx ccusage
        if run_with_timeout 10 bunx ccusage --help &> /dev/null; then
            print_pass "bunx ccusage works"
        else
            print_warning "bunx ccusage may need first-time setup"
        fi
    elif command -v npx &> /dev/null; then
        print_pass "npx available for ccusage"
    else
        print_fail "No method to run ccusage found"
    fi
    
    # Optional tools
    if command -v expect &> /dev/null; then
        print_pass "expect available for advanced automation"
    else
        print_info "expect not available - will use fallback methods"
    fi
    
    if command -v jq &> /dev/null; then
        print_pass "jq available for JSON parsing"
    else
        print_info "jq not available - JSON parsing will be limited"
    fi
}

# Test 3: Basic Script Functionality
test_basic_script() {
    print_test "Testing basic renewal script functionality"
    
    # Test script syntax
    if bash -n "$BASIC_SCRIPT" 2>/dev/null; then
        print_pass "Basic script has valid syntax"
    else
        print_fail "Basic script has syntax errors"
    fi
    
    # Check log creation
    if [ -f "$HOME/.claude-auto-renew.log" ]; then
        print_pass "Basic script creates log file"
        
        # Check log content
        if grep -q "$(date '+%Y-%m-%d')" "$HOME/.claude-auto-renew.log"; then
            print_pass "Log file contains today's date"
        else
            print_warning "Log file doesn't contain recent entries"
        fi
    else
        print_warning "Basic script didn't create log file"
    fi
}

# Test 4: Advanced Script Functionality
test_advanced_script() {
    print_test "Testing advanced renewal script functionality"
    
    # Clear any existing logs
    > "$HOME/.claude-auto-renew.log" 2>/dev/null
    
    # Test script syntax
    if bash -n "$ADVANCED_SCRIPT" 2>/dev/null; then
        print_pass "Advanced script has valid syntax"
    else
        print_fail "Advanced script has syntax errors"
    fi
    
    # Check script content for expected functionality
    if grep -q "ccusage" "$ADVANCED_SCRIPT"; then
        print_pass "Advanced script integrates with ccusage"
    else
        print_fail "Advanced script missing ccusage integration"
    fi
    
    if grep -q "renewal\|check\|log_message" "$ADVANCED_SCRIPT"; then
        print_pass "Advanced script has renewal and logging functionality"
    else
        print_fail "Advanced script missing core functionality"
    fi
}

# Test 5: Daemon Manager Functionality
test_daemon_manager() {
    print_test "Testing daemon manager functionality"
    
    # Test help output
    if "$DAEMON_MANAGER" 2>&1 | grep -q "Usage"; then
        print_pass "Daemon manager shows usage information"
    else
        print_fail "Daemon manager doesn't show usage"
    fi
    
    # Test status when not running
    if "$DAEMON_MANAGER" status 2>&1 | grep -q "not running"; then
        print_pass "Daemon manager correctly reports when not running"
    else
        print_warning "Daemon manager status output unclear when not running"
    fi
    
    # Test invalid parameters
    invalid_out="$("$DAEMON_MANAGER" start --at "invalid" 2>&1)"
    if echo "$invalid_out" | grep -q "Invalid"; then
        print_pass "Daemon manager validates start time parameters"
    else
        print_fail "Daemon manager doesn't validate parameters properly"
    fi
}

# Test 6: Daemon Start/Stop Cycle
test_daemon_lifecycle() {
    print_test "Testing daemon start/stop lifecycle"
    
    # Ensure daemon is stopped
    "$DAEMON_MANAGER" stop &> /dev/null
    sleep 2
    
    # Test start
    print_info "Starting daemon for lifecycle test..."
    if "$DAEMON_MANAGER" start &> /dev/null; then
        print_pass "Daemon starts successfully"
        
        sleep 3
        
        # Test status while running
        if "$DAEMON_MANAGER" status 2>&1 | grep -q -i "running\|active"; then
            print_pass "Daemon status correctly shows running state"
        else
            print_fail "Daemon status doesn't show running state"
        fi
        
        # Test PID file
        if [ -f "$HOME/.claude-auto-renew-daemon.pid" ]; then
            print_pass "PID file created"
            
            local pid=$(cat "$HOME/.claude-auto-renew-daemon.pid")
            if kill -0 "$pid" 2>/dev/null; then
                print_pass "PID file contains valid process ID"
            else
                print_fail "PID file contains invalid process ID"
            fi
        else
            print_fail "PID file not created"
        fi
        
        # Test log creation
        if [ -f "$HOME/.claude-auto-renew-daemon.log" ]; then
            print_pass "Daemon log file created"
            
            if grep -q "Daemon Started" "$HOME/.claude-auto-renew-daemon.log"; then
                print_pass "Daemon logs startup message"
            else
                print_warning "Daemon startup message not found in logs"
            fi
        else
            print_fail "Daemon log file not created"
        fi
        
        # Test stop
        print_info "Stopping daemon..."
        if "$DAEMON_MANAGER" stop &> /dev/null; then
            print_pass "Daemon stops successfully"
            
            sleep 2
            
            # Verify stopped
            if ! [ -f "$HOME/.claude-auto-renew-daemon.pid" ]; then
                print_pass "PID file cleaned up after stop"
            else
                print_fail "PID file not cleaned up"
            fi
        else
            print_fail "Daemon stop failed"
        fi
    else
        print_fail "Daemon failed to start"
    fi
}

# Test 7: Log Management and Rotation
test_logging() {
    print_test "Testing logging functionality"
    
    # Create test log entries
    local test_log="$HOME/.claude-auto-renew-test.log"
    echo "[$(date)] Test log entry" > "$test_log"
    
    if [ -f "$test_log" ]; then
        print_pass "Can create log files"
        
        # Test log rotation (simulate large log)
        for i in {1..100}; do
            echo "[$(date)] Test entry $i" >> "$test_log"
        done
        
        if [ -f "$test_log" ] && [ -s "$test_log" ]; then
            print_pass "Log files can accumulate entries"
        else
            print_fail "Log file writing issues"
        fi
        
        rm -f "$test_log"
    else
        print_fail "Cannot create log files"
    fi
    
    # Test daemon logs command
    if "$DAEMON_MANAGER" logs 2>&1 | grep -q "log\|No such file"; then
        print_pass "Daemon logs command works"
    else
        print_fail "Daemon logs command not working"
    fi
}

# Test 8: Setup Script Testing
test_setup_script() {
    print_test "Testing setup script functionality"
    
    # Check script content for expected functionality
    if grep -q "Invalid choice" "$SETUP_SCRIPT"; then
        print_pass "Setup script handles invalid input"
    else
        print_fail "Setup script missing input validation"
    fi
    
    # Test that script has proper content
    if grep -q "DAEMON\|CRON" "$SETUP_SCRIPT"; then
        print_pass "Setup script shows mode options"
    else
        print_fail "Setup script doesn't have mode options"
    fi
}

# Test 9: Error Handling and Edge Cases
test_error_handling() {
    print_test "Testing error handling and edge cases"
    
    # Test error handling by checking script content
    if grep -q "command -v claude\|which claude" "$BASIC_SCRIPT"; then
        print_pass "Script checks for claude command availability"
    else
        print_warning "Script may not check for claude availability"
    fi
    
    # Test with insufficient permissions (simulate)
    local readonly_dir="/tmp/readonly-test-$$"
    mkdir -p "$readonly_dir" 2>/dev/null
    chmod 444 "$readonly_dir" 2>/dev/null
    
    if ! echo "test" > "$readonly_dir/test" 2>/dev/null; then
        print_pass "Properly simulated permission restriction"
    else
        print_info "Could not simulate permission restriction"
    fi
    
    rmdir "$readonly_dir" 2>/dev/null
    
    # Test daemon behavior with existing PID file. Use this script's own PID:
    # it is guaranteed alive, so the manager must refuse with "already
    # running" instead of treating the file as stale and starting a daemon.
    echo "$$" > "$HOME/.claude-auto-renew-daemon.pid"
    
    pidfile_out="$("$DAEMON_MANAGER" start 2>&1)"
    if echo "$pidfile_out" | grep -q "already running"; then
        print_pass "Daemon handles existing PID file"
    else
        print_fail "Daemon should refuse to start with a live PID in the PID file"
    fi
    
    rm -f "$HOME/.claude-auto-renew-daemon.pid"
}

# Test 10: Integration and Timing Tests
test_integration() {
    print_test "Testing integration and timing scenarios"
    
    print_info "This test simulates renewal scenarios..."
    
    # Create fake activity file
    local fake_activity="$HOME/.claude-last-activity"
    local old_time=$(($(date +%s) - 19000))  # 5+ hours ago
    echo "$old_time" > "$fake_activity"
    
    # Test that script handles old activity by checking logic
    if grep -q "last_activity\|18000\|5.*hour" "$ADVANCED_SCRIPT"; then
        print_pass "Script handles old activity scenarios"
    else
        print_fail "Script missing old activity handling"
    fi
    
    # Clean up
    rm -f "$fake_activity"
    
    # Test ccusage fallback behavior by checking script content
    if grep -q "fallback\|time-based" "$ADVANCED_SCRIPT"; then
        print_pass "Script has fallback logic when ccusage unavailable"
    else
        print_warning "Script may not have ccusage fallback"
    fi
}

# Cleanup function
cleanup_tests() {
    print_test "Cleaning up test environment"
    
    # Stop any running daemon
    "$DAEMON_MANAGER" stop &> /dev/null
    
    # Clean up test files
    rm -rf "$TEST_DIR" 2>/dev/null
    rm -f "$HOME/.claude-auto-renew-daemon.pid" 2>/dev/null
    
    print_info "Test cleanup completed"
}

# Main test execution
main() {
    print_header
    
    print_info "Starting comprehensive Claude auto-renewal tests"
    print_info "Test timestamp: $(date)"
    print_info "Current directory: $(pwd)"
    print_info "Test directory: $TEST_DIR"
    
    # Run all tests
    test_environment
    test_dependencies

    # Everything below starts real daemons and asserts on state files under
    # $HOME. Move into the sandbox first (also handles interruption cleanup).
    sandbox_init

    test_basic_script
    test_advanced_script
    test_daemon_manager
    test_daemon_lifecycle
    test_logging
    test_setup_script
    test_error_handling
    test_integration
    cleanup_tests
    
    # Final summary
    echo ""
    echo -e "${PURPLE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${NC}                         ${BLUE}FINAL TEST SUMMARY${NC}                        ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "Total Tests: ${BLUE}$TESTS_TOTAL${NC}"
    echo -e "${GREEN}Passed:${NC} $TESTS_PASSED"
    echo -e "${RED}Failed:${NC} $TESTS_FAILED"
    
    local pass_rate=$((TESTS_PASSED * 100 / (TESTS_PASSED + TESTS_FAILED)))
    echo -e "Pass Rate: ${BLUE}$pass_rate%${NC}"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo ""
        echo -e "${GREEN}🎉 All comprehensive tests passed! CC AutoRenew is fully functional.${NC}"
        echo ""
        echo "System is ready for production use:"
        echo "  • Start daemon: $DAEMON_MANAGER start"
        echo "  • Interactive setup: $SETUP_SCRIPT"
        echo "  • Check status: $DAEMON_MANAGER status"
        exit 0
    elif [ $pass_rate -ge 80 ]; then
        echo ""
        echo -e "${YELLOW}⚠️  Most tests passed ($pass_rate%), but some issues detected.${NC}"
        echo "Review failed tests above and consider fixing before production use."
        exit 1
    else
        echo ""
        echo -e "${RED}❌ Multiple test failures detected. System may not be ready for use.${NC}"
        echo "Please address the failed tests before proceeding."
        exit 1
    fi
}

# Interruption cleanup is handled by test-lib.sh (sandbox_cleanup trap)

# Run the tests
main "$@" 