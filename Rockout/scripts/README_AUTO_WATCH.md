# Automatic File Watcher for Xcode

This script automatically monitors your `Rockout/` directory and adds new Swift files to your Xcode project as soon as they're created or modified.

## Quick Start

### Option 1: Run in Background (Recommended)

```bash
cd /Users/suinoikhioda/Documents/lime-agnes
./Rockout/scripts/auto_watch.sh start
```

This starts the watcher in the background. It will continue running even if you close the terminal.

### Option 2: Run in Foreground

```bash
cd /Users/suinoikhioda/Documents/lime-agnes
./Rockout/scripts/watch_and_add.sh
```

This runs the watcher in the current terminal. Press `Ctrl+C` to stop.

## Managing the Watcher

### Check Status
```bash
./Rockout/scripts/auto_watch.sh status
```

### View Logs
```bash
./Rockout/scripts/auto_watch.sh logs
```

### Stop Watcher
```bash
./Rockout/scripts/auto_watch.sh stop
```

## How It Works

1. **Monitors** the `Rockout/` directory for `.swift` file changes
2. **Debounces** events (waits 2 seconds after last change to avoid multiple runs)
3. **Automatically adds** new files to Xcode project using `auto_add_to_xcode.rb`
4. **Organizes** files into correct Xcode groups based on directory structure

## Requirements

- **fswatch**: File system watcher (installed automatically via Homebrew if needed)
- **xcodeproj gem**: Ruby gem for Xcode project manipulation (installed automatically if needed)

## Features

- ✅ Automatic detection of new Swift files
- ✅ Automatic addition to Xcode project
- ✅ Correct group organization
- ✅ Build phase integration
- ✅ Debouncing to avoid excessive runs
- ✅ Background operation support
- ✅ Logging for debugging

## Example Workflow

1. Create a new Swift file: `Rockout/Views/NewView.swift`
2. The watcher detects it within 2 seconds
3. File is automatically added to Xcode project
4. File appears in the correct group (`Views/`)
5. File is added to build phases automatically

## Troubleshooting

### Watcher not detecting files?

1. Check if watcher is running:
   ```bash
   ./Rockout/scripts/auto_watch.sh status
   ```

2. Check logs for errors:
   ```bash
   ./Rockout/scripts/auto_watch.sh logs
   ```

3. Make sure fswatch is installed:
   ```bash
   brew install fswatch
   ```

### Files not being added to Xcode?

1. Make sure Xcode project is not locked (close Xcode)
2. Check if xcodeproj gem is installed:
   ```bash
   gem list xcodeproj
   ```

3. Run the add script manually to see errors:
   ```bash
   ruby Rockout/scripts/auto_add_to_xcode.rb
   ```

### Start on System Boot

To automatically start the watcher when your system boots, add this to your `~/.zshrc` or `~/.bash_profile`:

```bash
# Auto-start Xcode file watcher
if [ -f "/Users/suinoikhioda/Documents/lime-agnes/Rockout/scripts/auto_watch.sh" ]; then
    /Users/suinoikhioda/Documents/lime-agnes/Rockout/scripts/auto_watch.sh start
fi
```

## Manual Alternative

If you prefer to manually add files, you can still use:

```bash
./Rockout/scripts/clean_and_add_files.sh  # Check for new files
ruby Rockout/scripts/auto_add_to_xcode.rb  # Add them
```

