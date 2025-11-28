#!/bin/bash

# Convenience script to start the file watcher in the background
# Usage: ./auto_watch.sh [start|stop|status]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WATCH_SCRIPT="$SCRIPT_DIR/watch_and_add.sh"
PID_FILE="$SCRIPT_DIR/.watch_pid"
LOG_FILE="$SCRIPT_DIR/.watch.log"

case "${1:-start}" in
    start)
        if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo "⚠️  Watcher is already running (PID: $(cat "$PID_FILE"))"
            echo "   Use: $0 stop  to stop it first"
            exit 1
        fi
        
        echo "🚀 Starting file watcher..."
        nohup bash "$WATCH_SCRIPT" > "$LOG_FILE" 2>&1 &
        echo $! > "$PID_FILE"
        echo "✓ Watcher started (PID: $(cat "$PID_FILE"))"
        echo "📄 Logs: $LOG_FILE"
        echo ""
        echo "To stop: $0 stop"
        echo "To view logs: tail -f $LOG_FILE"
        ;;
        
    stop)
        if [ ! -f "$PID_FILE" ]; then
            echo "⚠️  No watcher process found"
            exit 1
        fi
        
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            kill "$PID"
            rm -f "$PID_FILE"
            echo "✓ Watcher stopped"
        else
            echo "⚠️  Watcher process not running"
            rm -f "$PID_FILE"
        fi
        ;;
        
    status)
        if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo "✓ Watcher is running (PID: $(cat "$PID_FILE"))"
            echo "📄 Logs: $LOG_FILE"
        else
            echo "⚠️  Watcher is not running"
            [ -f "$PID_FILE" ] && rm -f "$PID_FILE"
        fi
        ;;
        
    logs)
        if [ -f "$LOG_FILE" ]; then
            tail -f "$LOG_FILE"
        else
            echo "⚠️  No log file found"
        fi
        ;;
        
    *)
        echo "Usage: $0 [start|stop|status|logs]"
        echo ""
        echo "  start  - Start the file watcher in background"
        echo "  stop   - Stop the running watcher"
        echo "  status - Check if watcher is running"
        echo "  logs   - View watcher logs (tail -f)"
        exit 1
        ;;
esac

