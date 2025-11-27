#!/bin/bash

# Script to automatically add new files to Xcode project
# This script scans for files not in the Xcode project and adds them

PROJECT_DIR="/Users/suinoikhioda/Documents/RockOut/Rockout"
PROJECT_FILE="$PROJECT_DIR/Rockout.xcodeproj/project.pbxproj"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Scanning for new files to add to Xcode project...${NC}"

# Find all Swift files
find "$PROJECT_DIR" -name "*.swift" -type f | while read -r file; do
    # Get relative path from project directory
    rel_path="${file#$PROJECT_DIR/}"
    
    # Check if file is already in project.pbxproj
    if ! grep -q "$rel_path" "$PROJECT_FILE" 2>/dev/null; then
        echo -e "${YELLOW}Found new file: $rel_path${NC}"
        echo "  → This file needs to be manually added to Xcode"
        echo "  → Right-click in Xcode → Add Files to 'Rockout'..."
    fi
done

echo -e "${GREEN}Scan complete!${NC}"
echo ""
echo "Note: This script only detects files. To automatically add them,"
echo "you can use Xcode's 'Add Files to Rockout...' feature or"
echo "run: open -a Xcode $PROJECT_DIR/Rockout.xcodeproj"

