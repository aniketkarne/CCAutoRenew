#!/bin/bash

# Setup script for macOS launchd auto-start.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DAEMON_MANAGER="$SCRIPT_DIR/claude-daemon-manager.sh"
BOOTSTRAP_SCRIPT="$SCRIPT_DIR/claude-launchd-bootstrap.sh"
LABEL="com.ccautorenew.launchd"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$PLIST_DIR/$LABEL.plist"
STDOUT_LOG="$HOME/.claude-auto-renew-launchd.out.log"
STDERR_LOG="$HOME/.claude-auto-renew-launchd.err.log"
LAUNCHD_DOMAIN="gui/$(id -u)"
ACTION="install"
EXTRA_ARGS=()

print_help() {
    cat <<'EOF'
Usage:
  ./setup-claude-launchd.sh install [-- daemon start args...]
  ./setup-claude-launchd.sh status
  ./setup-claude-launchd.sh uninstall

Examples:
  ./setup-claude-launchd.sh install
  ./setup-claude-launchd.sh install -- --at "09:00" --stop "17:00"
  ./setup-claude-launchd.sh install -- --disableccusage
  ./setup-claude-launchd.sh status
  ./setup-claude-launchd.sh uninstall

Notes:
  - This is for macOS only.
  - The launch agent runs at login and triggers the normal daemon manager.
  - Any arguments after -- are passed to:
      ./claude-daemon-manager.sh start
EOF
}

xml_escape() {
    local value="$1"
    value=${value//&/&amp;}
    value=${value//</&lt;}
    value=${value//>/&gt;}
    value=${value//\"/&quot;}
    value=${value//\'/&apos;}
    printf '%s' "$value"
}

ensure_supported() {
    if [ "$(uname -s)" != "Darwin" ]; then
        echo "ERROR: launchd setup is only supported on macOS."
        exit 1
    fi

    if [ ! -x "$DAEMON_MANAGER" ]; then
        echo "ERROR: claude-daemon-manager.sh not found or not executable at $DAEMON_MANAGER"
        exit 1
    fi

    if [ ! -x "$BOOTSTRAP_SCRIPT" ]; then
        echo "ERROR: claude-launchd-bootstrap.sh not found or not executable at $BOOTSTRAP_SCRIPT"
        exit 1
    fi
}

is_loaded() {
    launchctl print "$LAUNCHD_DOMAIN/$LABEL" >/dev/null 2>&1
}

write_plist() {
    mkdir -p "$PLIST_DIR"

    {
        printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
        printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
        printf '%s\n' '<plist version="1.0">'
        printf '%s\n' '<dict>'
        printf '  <key>Label</key>\n'
        printf '  <string>%s</string>\n' "$(xml_escape "$LABEL")"
        printf '\n'
        printf '  <key>ProgramArguments</key>\n'
        printf '  <array>\n'
        printf '    <string>%s</string>\n' "$(xml_escape "$BOOTSTRAP_SCRIPT")"

        if [ ${#EXTRA_ARGS[@]} -gt 0 ]; then
            for arg in "${EXTRA_ARGS[@]}"; do
                printf '    <string>%s</string>\n' "$(xml_escape "$arg")"
            done
        fi

        printf '  </array>\n'
        printf '\n'
        printf '  <key>WorkingDirectory</key>\n'
        printf '  <string>%s</string>\n' "$(xml_escape "$SCRIPT_DIR")"
        printf '\n'
        printf '  <key>EnvironmentVariables</key>\n'
        printf '  <dict>\n'
        printf '    <key>PATH</key>\n'
        printf '    <string>%s</string>\n' "$(xml_escape "$PATH")"
        printf '  </dict>\n'
        printf '\n'
        printf '  <key>RunAtLoad</key>\n'
        printf '  <true/>\n'
        printf '\n'
        printf '  <key>StandardOutPath</key>\n'
        printf '  <string>%s</string>\n' "$(xml_escape "$STDOUT_LOG")"
        printf '  <key>StandardErrorPath</key>\n'
        printf '  <string>%s</string>\n' "$(xml_escape "$STDERR_LOG")"
        printf '%s\n' '</dict>'
        printf '%s\n' '</plist>'
    } > "$PLIST_PATH"
}

install_launchd() {
    write_plist

    launchctl bootout "$LAUNCHD_DOMAIN" "$PLIST_PATH" >/dev/null 2>&1 || true
    launchctl bootstrap "$LAUNCHD_DOMAIN" "$PLIST_PATH"
    launchctl kickstart -k "$LAUNCHD_DOMAIN/$LABEL" >/dev/null 2>&1 || true

    echo "✅ launchd auto-start installed"
    echo "Plist: $PLIST_PATH"
    echo "The daemon will be started automatically when you log in."
    echo ""
    "$DAEMON_MANAGER" status || true
}

uninstall_launchd() {
    launchctl bootout "$LAUNCHD_DOMAIN" "$PLIST_PATH" >/dev/null 2>&1 || true
    rm -f "$PLIST_PATH"

    echo "✅ launchd auto-start removed"
    echo "The daemon itself is not stopped automatically."
    echo "Use ./claude-daemon-manager.sh stop if you also want to stop the current daemon."
}

status_launchd() {
    if [ -f "$PLIST_PATH" ]; then
        echo "LaunchAgent installed: $PLIST_PATH"
    else
        echo "LaunchAgent installed: no"
    fi

    if is_loaded; then
        echo "LaunchAgent loaded: yes"
    else
        echo "LaunchAgent loaded: no"
    fi

    echo ""
    "$DAEMON_MANAGER" status || true
}

while [ $# -gt 0 ]; do
    case "$1" in
        install|status|uninstall)
            ACTION="$1"
            shift
            ;;
        help|-h|--help)
            ACTION="help"
            shift
            ;;
        --)
            shift
            EXTRA_ARGS=("$@")
            break
            ;;
        *)
            echo "ERROR: Unknown argument: $1"
            echo ""
            print_help
            exit 1
            ;;
    esac
done

if [ "$ACTION" = "help" ]; then
    print_help
    exit 0
fi

ensure_supported

case "$ACTION" in
    install)
        install_launchd
        ;;
    status)
        status_launchd
        ;;
    uninstall)
        uninstall_launchd
        ;;
esac
