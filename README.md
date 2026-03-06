# Claude Usage Tracker (Swift)

A lightweight native macOS menu bar app that displays your Claude usage limits and reset times.

![macOS](https://img.shields.io/badge/macOS-13.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9+-orange)
![Memory](https://img.shields.io/badge/RAM-~50MB-green)

## Features

- **Live usage percentage** in menu bar (5-hour session)
- **Hidden when inactive** - the menu bar item disappears when there's no data, keeping your menu bar clean
- **Configurable global hotkey** - press `Cmd+Shift+C` (customizable in Settings) to open the menu from anywhere
- **Keyboard shortcuts** - `c` to copy usage, `r` to refresh, `x` to close while the menu is open
- **Color-coded severity** - optional 5-level coloring based on usage pace relative to session time elapsed
- **5-hour session** usage with reset countdown
- **Weekly limits** with reset date
- **Sonnet-specific** weekly limit tracking
- **Extra usage** spending ($X/$Y format)
- **Auto-refresh** every 1, 5, 30, or 60 minutes
- **Open at Login** - toggle in Settings to start automatically
- **Native Swift** - no Python, no dependencies
- **Lightweight** - ~50 MB RAM

## Screenshot

![Claude Usage Tracker](screenshot.png)

### Demos

**Keyboard Shortcuts** - use `Cmd+Shift+C` to open the menu, then use `c`, `r`, and `x` for quick actions:

![Keyboard Shortcuts Demo](hover-demo.gif)

**Mouse Navigation** - click the menu bar item to navigate with your mouse:

![Mouse Click Demo](click-demo.gif)

## Requirements

- macOS 13.0+
- [Claude Code](https://claude.ai/code) installed and logged in
- Claude Pro or Max subscription

## Installation

### Build from Source

```bash
git clone https://github.com/asboyer/claude-usage-swift.git
cd claude-usage-swift
./build.sh
open ClaudeUsage.app
```

To keep the app in your Applications folder (optional):

```bash
cp -r ClaudeUsage.app /Applications/
open /Applications/ClaudeUsage.app
```

## How It Works

The app reads Claude Code's OAuth credentials from macOS Keychain and queries the Anthropic usage API:

1. Reads token from Keychain (`Claude Code-credentials`)
2. Calls `api.anthropic.com/api/oauth/usage`
3. Displays utilization percentages and reset times

The usage API is free - no tokens consumed.

**Important**: You must have **Claude Code running** in order for usage to start being tracked. The app reads your credentials from Claude Code's keychain entry, so Claude Code needs to be installed and logged in.

## Settings

All settings are accessible from the **Settings** submenu:

- **Refresh Interval** - choose between 1 minute, 5 minutes, 30 minutes, or 1 hour
- **Colors** - toggle color-coded usage items with 5 severity levels:
  - **Green** (≤0.75) - on pace with your session budget
  - **Yellow** (0.75-1.0) - moderate usage pace
  - **Light Orange** (1.0-1.5) - elevated usage
  - **Dark Orange** (1.5-2.5) - heavy usage
  - **Red** (≥2.5) - very heavy usage relative to time elapsed
- **Keyboard Shortcut** - customize the global hotkey to open the menu (default: `Cmd+Shift+C`)
- **Open at Login** - register the app as a login item
- **Notifications** - configure 100% alerts, usage limit alerts, reset alarms, and notification sounds
- **More** - pin or unpin usage categories (5-hour, Weekly, Opus, Sonnet, OAuth Apps, Cowork, Extra)

## Troubleshooting

### Menu bar item not showing
The app hides from the menu bar when there's no data. Press `Cmd+Shift+C` to open the menu, or ensure Claude Code is installed and logged in by running `claude` in your terminal.

### Usage shows 0% or doesn't update
- Make sure Claude Code is installed and logged in: run `claude` in terminal
- **For Pro/Max users**: Your OAuth token may have expired. Follow these steps:
  1. Open terminal and run: `claude setup-token`
  2. This opens a browser to re-authenticate with your Claude subscription
  3. After authenticating, restart the app
- **API key users**: This app requires a Pro or Max subscription. API credits cannot be used to track subscription usage limits.

### Getting "OAuth token has expired" error
The OAuth token in your Keychain has expired. To fix:
1. Delete old credentials: `security delete-generic-password -s "Claude Code-credentials"`
2. Run `claude setup-token` to get a fresh token
3. Restart Claude Usage app

### App won't open (macOS security)
- Go to **System Settings > Privacy & Security**
- Find "ClaudeUsage was blocked" and click **Open Anyway**

### Building fails
- Ensure Xcode Command Line Tools: `xcode-select --install`

## Credits

This project is a fork of [claude-usage-swift](https://github.com/pbnchase/claude-usage-swift) by [pbnchase](https://github.com/pbnchase). The original Python version is available at [claude-usage-tracker](https://github.com/cfranci/claude-usage-tracker) by [cfranci](https://github.com/cfranci).

## License

MIT
