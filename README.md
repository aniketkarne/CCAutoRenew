# CC AutoRenew 🚀

> Never miss a Claude Code renewal window again! Automatically maintains your 5-hour usage blocks with optional scheduled start times.

## 🎯 Problem

Claude Code operates on a 5-hour subscription model that renews from your first message. If you:
- Start coding at 5pm (block runs 5pm-10pm)
- Don't use Claude again until 11:01pm
- Your next block runs 11pm-4am (missing an hour!)

**Session Burning Problem:** Starting the daemon at random times can waste precious hours of your block. If you want to code from 9am-2pm but start the daemon at 6am, you've burned 3 hours!

**Solution:** CC AutoRenew prevents both gaps AND session burning:
- 🚫 **Prevents Gaps** - Automatically starts new sessions when blocks expire
- ⏰ **Prevents Session Burning** - Schedule when monitoring begins (`--at "09:00"`) 
- 🎯 **Perfect Timing** - Start your 5-hour block exactly when you need it

## ✨ Features

- 🔄 **Automatic Renewal** - Starts Claude sessions exactly when needed
- ⏰ **Scheduled Start Times** - Set when daemon begins monitoring (`--at "09:00"`)
- 🛑 **Scheduled Stop Times** - Set when daemon stops monitoring (`--stop "17:00"`)
- 🌅 **Daily Auto-Restart** - Automatically resumes next day at start time
- 📊 **Smart Monitoring** - Integrates with [ccusage](https://github.com/ryoppippi/ccusage) for accurate timing
- 🎯 **Intelligent Scheduling** - Checks more frequently as renewal approaches
- 📝 **Detailed Logging** - Track all renewal activities with WAITING/ACTIVE/STOPPED states
- 📊 **Live Dashboard** - Real-time monitoring with progress bars and renewal schedules
- 💬 **Custom Messages** - Use `--message` to send contextual renewal messages instead of generic greetings
- 🛡️ **Failsafe Design** - Multiple fallback mechanisms and prevents renewals near stop time
- 🖥️ **Cross-platform** - Works on macOS and Linux
- ⚡ **Clock-only Mode** - Use `--disableccusage` flag to bypass ccusage entirely

## 🚀 Quick Start

```bash
# Clone the repository
git clone https://github.com/aniketkarne/CCAutoRenew.git
cd CCAutoRenew

# Make scripts executable
chmod +x *.sh

# Interactive setup (recommended)
./setup-claude-cron.sh

# macOS auto-start on login (launchd)
./setup-claude-launchd.sh install

# OR manual daemon start
./claude-daemon-manager.sh start
./claude-daemon-manager.sh start --at "09:00"  # with start time
./claude-daemon-manager.sh start --at "09:00" --stop "17:00"  # with start/stop times
./claude-daemon-manager.sh start --message "continue working on my project"  # with custom message
./claude-daemon-manager.sh start --at "09:00" --stop "17:00" --disableccusage  # clock-only mode
```

That's it! The daemon will now run in the background and automatically renew your Claude sessions.

## 📋 Prerequisites

- [Claude CLI](https://www.anthropic.com/claude-code) installed and authenticated
- Bash 4.0+ (pre-installed on macOS/Linux)
- (Optional) [ccusage](https://github.com/ryoppippi/ccusage) for precise timing

## 🔧 Installation

### 1. Install Claude CLI

First, ensure you have Claude Code installed:
```bash
# Follow the official installation guide
    # https://www.anthropic.com/claude-code
```

### 2. Install ccusage (Optional but Recommended)

For accurate renewal timing:
```bash
# Option 1: Global install
npm install -g ccusage

# Option 2: Use without installing
npx ccusage@latest
bunx ccusage
```

### 3. Setup CC AutoRenew

```bash
# Clone this repository
git clone https://github.com/aniketkarne/CCAutoRenew.git
cd cc-autorenew

# Make all scripts executable
chmod +x *.sh

# Test your setup
./test-claude-renewal.sh
```

## 📖 Usage

### Managing the Daemon

```bash
# Start the auto-renewal daemon
./claude-daemon-manager.sh start

# Start with scheduled activation time
./claude-daemon-manager.sh start --at "09:00"
./claude-daemon-manager.sh start --at "2025-01-28 14:30"

# Start with both start and stop times
./claude-daemon-manager.sh start --at "09:00" --stop "17:00"
./claude-daemon-manager.sh start --at "2025-01-28 09:00" --stop "2025-01-28 17:00"

# Start with clock-only mode (bypass ccusage entirely)
./claude-daemon-manager.sh start --at "09:00" --stop "17:00" --disableccusage

# Start with custom renewal message (useful for context continuity)
./claude-daemon-manager.sh start --message "continue working on the React feature"
./claude-daemon-manager.sh start --at "09:00" --message "resume our Python project"

# Check daemon status
./claude-daemon-manager.sh status

# Live dashboard with real-time updates
./claude-daemon-manager.sh dash

# View logs
./claude-daemon-manager.sh logs

# Follow logs in real-time
./claude-daemon-manager.sh logs -f

# Stop the daemon
./claude-daemon-manager.sh stop

# Restart the daemon (with same start/stop times if previously set)
./claude-daemon-manager.sh restart
./claude-daemon-manager.sh restart --at "10:00"  # new start time
./claude-daemon-manager.sh restart --at "09:00" --stop "17:00"  # new schedule
```

### macOS Auto-Start With launchd

For macOS users who want the daemon to start automatically at login:

```bash
# Install auto-start using your current shell PATH
./setup-claude-launchd.sh install

# Install auto-start with daemon start arguments
./setup-claude-launchd.sh install -- --at "09:00" --stop "17:00"
./setup-claude-launchd.sh install -- --disableccusage

# Check launchd + daemon status
./setup-claude-launchd.sh status

# Remove auto-start
./setup-claude-launchd.sh uninstall
```

Notes:
- The launch agent triggers `./claude-daemon-manager.sh start` when you log in.
- It uses the current shell `PATH` when generating the plist, so `claude`, `ccusage`, `npx`, or `bunx` can still be found by launchd.
- If you move those commands to a different location later, run the install command again to refresh the LaunchAgent.

### Live Dashboard 📊

The new live dashboard provides real-time monitoring of your Claude renewal status:

```bash
# Launch the interactive dashboard
./claude-daemon-manager.sh dash
```

**Dashboard Features:**
- 🔧 **Daemon Status** - Current state (WAITING/ACTIVE/STOPPED) with PID and timing details
- ⏱️ **Progress Bar** - Visual progress showing time until next renewal reset (color-coded)
- 📅 **Today's Plan** - Estimated renewal trigger times throughout the day
- 📝 **Live Activity** - Real-time log entries and recent daemon actions
- 🔄 **Auto-Updates** - Refreshes every minute automatically
- 🎯 **Smart Layout** - Clean interface with clear sections and formatting

**Progress Bar Colors:**
- 🟢 **Green** - More than 1 hour remaining
- 🟡 **Yellow** - 30-60 minutes remaining  
- 🔴 **Red** - Less than 30 minutes remaining

**Usage:**
- Press **Ctrl+C** to exit the dashboard
- Dashboard updates automatically every 60 seconds
- Works only when daemon is running
- Shows "No renewal tracking" when no activity file exists

Example dashboard output:
```
╔══════════════════════════════════════════════════════════════════════════════╗
║                    Claude Auto-Renewal Dashboard                            ║
║                   Wednesday, August 06, 2025 - 16:54:07                   ║
╚══════════════════════════════════════════════════════════════════════════════╝

🔧 DAEMON STATUS:
  PID: 12345
  Status: ✅ ACTIVE - Auto-renewal monitoring enabled

⏱️  TIME TO NEXT RESET:
  ████████████████████████░░░░░░░░░░░░░░░░ 60% (1h 59m remaining)
  Next renewal at: 18:53

📅 TODAY'S RENEWAL PLAN:
  • 18:53 (NEXT)
  • 23:53

📝 RECENT ACTIVITY:
  [2025-08-06 16:53:20] Renewal successful!
  [2025-08-06 16:53:10] Starting Claude session for renewal...
```

### How It Works

1. **Monitors** your Claude usage using ccusage (or time-based fallback)
2. **Detects** when your 5-hour block is about to expire
3. **Waits** until just after expiration (within scheduled hours)
4. **Starts** a minimal Claude session (custom message or random greeting)
5. **Stops** monitoring at configured stop time
6. **Automatically restarts** the next day at start time
7. **Logs** all activities for transparency

### Custom Renewal Messages 💬

**Default Behavior (without --message):** The daemon automatically sends random greetings ("hi", "hello", "hey there", "good day", "greetings", "howdy", "what's up", "salutations") when renewing sessions. This is the original behavior and requires no configuration.

**Custom Messages (with --message):** You can optionally specify a custom message to maintain context when resuming work after rate limits:

```bash
# Use custom message for renewals
./claude-daemon-manager.sh start --message "continue working on the React feature"

# Combine with other options
./claude-daemon-manager.sh start --at "09:00" --stop "17:00" --message "resume our database optimization"

# The message persists across daemon restarts
./claude-daemon-manager.sh restart  # Still uses the previous custom message

# Clear custom message (return to random greetings)
./claude-daemon-manager.sh restart  # Without --message flag
```

**Why use custom messages?**
- **Context Continuity**: When rate-limited mid-task, resume with relevant context
- **Project Tracking**: Include project name for better session organization
- **Task Resumption**: Specify what you were working on before the limit
- **Better History**: More meaningful renewal entries in your Claude history

**Example scenarios:**
- Working on a feature: `--message "continue implementing the auth system"`
- Debugging session: `--message "resume debugging the memory leak issue"`
- Learning session: `--message "continue the Python tutorial"`
- Code review: `--message "resume reviewing the pull request"`

### Clock-only Mode

By default, the daemon uses [ccusage](https://github.com/ryoppippi/ccusage) for accurate timing information.
However, you can bypass ccusage entirely and rely solely on clock-based timing:

```bash
# Start with clock-only mode
./claude-daemon-manager.sh start --at "09:00" --stop "17:00" --disableccusage
```

When `--disableccusage` is used:
- 🚫 **No ccusage dependency** - Works without ccusage installed
- ⏰ **Clock-based timing** - Relies on 5-hour intervals from last activity
- 📝 **Clear logging** - Shows "⚠️ ccusage DISABLED - Using clock-based timing only"
- 🎯 **Same functionality** - All scheduling features still work

This mode is useful when:
- You don't want to install ccusage
- ccusage is causing issues on your system
- You prefer simpler time-based renewal checking
- You're in a restricted environment where ccusage can't run

### 💡 Avoid Session Burning

**Problem:** Starting daemon at wrong time wastes your 5-hour block
```bash
# BAD: Start daemon at 6am but want to code 9am-2pm = 3 hours wasted!
./claude-daemon-manager.sh start

# GOOD: Schedule daemon to start monitoring at 9am
./claude-daemon-manager.sh start --at "09:00"
# Your 5-hour block: 9am-2pm (perfect timing!)

# BETTER: Schedule both start and stop times for daily work schedule
./claude-daemon-manager.sh start --at "09:00" --stop "17:00"
# Monitors 9am-5pm, stops automatically, resumes next day at 9am
```

**Use Cases:**
- 🌅 **Morning Coder**: `--at "09:00"` for 9am-2pm coding sessions
- 🌙 **Night Owl**: `--at "18:00"` for 6pm-11pm evening coding
- 🏢 **Work Schedule**: `--at "09:00" --stop "17:00"` for 9am-5pm daily monitoring
- 🎯 **Focused Sessions**: `--at "14:00" --stop "19:00"` for afternoon coding blocks
- 📅 **Planned Session**: `--at "2025-01-28 14:30"` for specific date/time
- 💬 **Context Preservation**: `--message "continue React feature"` to maintain work context
- ⚡ **Clock-only Mode**: `--at "09:00" --stop "17:00" --disableccusage` to bypass ccusage

### Monitoring Schedule

The daemon adjusts its checking frequency based on time remaining:
- **Normal**: Every 10 minutes
- **< 30 minutes**: Every 2 minutes  
- **< 5 minutes**: Every 30 seconds
- **After renewal**: 5-minute cooldown

## 🧪 Testing

Run the test suite to verify everything is working:

```bash
# Quick test (< 1 minute)
./test-quick.sh

# Comprehensive test suite (includes start-time feature)
./test-start-time-feature.sh

# Legacy comprehensive test
./test-claude-renewal.sh
```

The new comprehensive test includes:
- ✅ Start-time functionality validation
- ✅ Daemon status with scheduling
- ✅ File management and cleanup
- ✅ Integration tests with real timing
- ✅ All existing functionality tests

## 📁 Project Structure

```
cc-autorenew/
├── claude-daemon-manager.sh      # Main control script
├── claude-auto-renew-daemon.sh   # Core daemon process
├── claude-auto-renew-advanced.sh # Standalone renewal script
├── claude-auto-renew.sh          # Basic renewal script
├── claude-launchd-bootstrap.sh   # launchd helper to start the daemon once per login
├── setup-claude-cron.sh          # Interactive setup (daemon/cron)
├── setup-claude-launchd.sh       # macOS launchd auto-start installer
├── test-start-time-feature.sh    # New comprehensive test suite
├── reddit.md                     # Reddit post about the project
└── README.md                     # This file
```

## 🔍 Logs and Debugging

Logs are stored in your home directory:
- `~/.claude-auto-renew-daemon.log` - Main daemon activity
- `~/.claude-last-activity` - Timestamp of last renewal

View recent activity:
```bash
# Last 50 log entries
tail -50 ~/.claude-auto-renew-daemon.log

# Follow logs in real-time
tail -f ~/.claude-auto-renew-daemon.log
```

## ⚙️ Configuration

The daemon uses smart defaults, but you can modify behavior by editing `claude-auto-renew-daemon.sh`:

```bash
# Adjust check intervals (in seconds)
- Normal: 600 (10 minutes)
- Approaching: 120 (2 minutes)  
- Imminent: 30 (30 seconds)
```

## 🐛 Troubleshooting

### Daemon won't start
```bash
# Check if already running
./claude-daemon-manager.sh status

# Check logs for errors
tail -20 ~/.claude-auto-renew-daemon.log
```

### launchd auto-start not working (macOS)
```bash
# Check launchd + daemon status
./setup-claude-launchd.sh status

# Reinstall the LaunchAgent using your current shell PATH
./setup-claude-launchd.sh install

# Check launchd bootstrap logs
tail -20 ~/.claude-auto-renew-launchd.err.log
```

### ccusage not working
```bash
# Test ccusage directly
ccusage blocks

# The daemon will fall back to time-based checking automatically
# Or use --disableccusage flag to bypass ccusage entirely
```

### Clock-only mode verification
```bash
# Check logs for clock-only mode confirmation
grep "ccusage DISABLED" ~/.claude-auto-renew-daemon.log

# Should show: "⚠️ ccusage DISABLED - Using clock-based timing only"
```

### Claude command fails
```bash
# Verify Claude CLI is installed
which claude

# Test Claude directly
echo "hi" | claude
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

### 📄 Attribution Guidelines

When forking or redistributing this project, please:
- Keep original attribution in README acknowledgments
- Maintain the MIT License and copyright notice
- Add your own contributions to the acknowledgments section
- Follow standard open source attribution practices

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

### 👨‍💻 Original Author
- **Aniket Karne** - [@aniketkarne](https://github.com/aniketkarne) - Original concept, core development, and start-time scheduling feature

### 🛠️ Dependencies & Tools
- [ccusage](https://github.com/ryoppippi/ccusage) by @ryoppippi for accurate usage tracking
- Claude Code team for the amazing coding assistant

### 🌟 Community
- Community feedback and contributions
- Open source contributors and testers

## 💡 Tips

- Use `claude-daemon-manager.sh dash` for real-time monitoring with visual progress
- Run `claude-daemon-manager.sh status` regularly to ensure the daemon is active
- Check logs after updates to verify renewals are working
- The dashboard shows estimated renewal times for the entire day
- Progress bar changes color as renewal approaches (green → yellow → red)
- The daemon is lightweight - uses minimal resources while running
- Can be added to system startup for automatic launch

---
## Buy me a coffee if you like my work: 

<a href="https://www.buymeacoffee.com/aniketkarne" target="_blank"><img src="https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png" alt="Buy Me A Coffee" style="height: 41px !important;width: 174px !important;box-shadow: 0px 3px 2px 0px rgba(190, 190, 190, 0.5) !important;-webkit-box-shadow: 0px 3px 2px 0px rgba(190, 190, 190, 0.5) !important;" ></a>
--

Made with ❤️ for the Claude Code community
