#!/bin/bash

# File watcher script that automatically adds new files to Xcode project
# Uses fswatch to monitor the Rockout directory for changes

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ROCKOUT_DIR="$PROJECT_DIR/Rockout"
XCODE_PROJECT="$PROJECT_DIR/Rockout.xcodeproj"
ADD_SCRIPT="$SCRIPT_DIR/auto_add_to_xcode.rb"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔍 Xcode Auto-Add File Watcher${NC}"
echo ""

# Check if fswatch is installed
if ! command -v fswatch &> /dev/null; then
    echo -e "${YELLOW}⚠️  fswatch not found. Installing via Homebrew...${NC}"
    if command -v brew &> /dev/null; then
        brew install fswatch
    else
        echo -e "${RED}❌ Homebrew not found. Please install fswatch manually:${NC}"
        echo "   brew install fswatch"
        echo ""
        echo "   Or install Homebrew first: https://brew.sh"
        exit 1
    fi
fi

# Check if xcodeproj gem is installed
if ! gem list xcodeproj -i > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  xcodeproj gem not found. Installing...${NC}"
    gem install xcodeproj || {
        echo -e "${RED}❌ Failed to install xcodeproj gem${NC}"
        echo "   Try: sudo gem install xcodeproj"
        exit 1
    }
fi

# Check if Xcode project exists
if [ ! -d "$XCODE_PROJECT" ]; then
    echo -e "${RED}❌ Xcode project not found at: $XCODE_PROJECT${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Watching: $ROCKOUT_DIR${NC}"
echo -e "${GREEN}✓ Project: $XCODE_PROJECT${NC}"
echo ""
echo -e "${YELLOW}📝 Monitoring for new/changed Swift files...${NC}"
echo -e "${YELLOW}   Press Ctrl+C to stop${NC}"
echo ""

# Debounce timer (wait 2 seconds after last change before processing)
DEBOUNCE_SECONDS=2
LAST_PROCESS_TIME=0

# Function to add files
add_files() {
    local timestamp=$(date +"%H:%M:%S")
    echo -e "\n${BLUE}[$timestamp]${NC} ${GREEN}🔄 Detected changes, adding files...${NC}"
    
    # Run the add script
    if ruby "$ADD_SCRIPT" 2>&1; then
        echo -e "${GREEN}✓ Files processed${NC}"
    else
        echo -e "${YELLOW}⚠️  Some files may not have been added${NC}"
    fi
    
    LAST_PROCESS_TIME=$(date +%s)
}

# Watch for file changes
fswatch -o -r "$ROCKOUT_DIR" --include='\.swift$' | while read -r count; do
    CURRENT_TIME=$(date +%s)
    TIME_SINCE_LAST=$((CURRENT_TIME - LAST_PROCESS_TIME))
    
    # If enough time has passed since last process, add files immediately
    # Otherwise, wait for debounce period
    if [ $TIME_SINCE_LAST -ge $DEBOUNCE_SECONDS ]; then
        sleep $DEBOUNCE_SECONDS
        add_files
    else
        # Wait for remaining debounce time
        REMAINING=$((DEBOUNCE_SECONDS - TIME_SINCE_LAST))
        sleep $REMAINING
        add_files
    fi
done

