#!/bin/bash

# Auto-build script for RockOut Xcode project
# Watches for file changes and automatically rebuilds

PROJECT_PATH="/Users/chukwudiebube/Downloads/RockOut-main"
PROJECT_FILE="Rockout.xcodeproj"
SCHEME="Rockout"
DESTINATION="platform=iOS Simulator,name=iPhone 16 Pro"
BUILD_DIR="${PROJECT_PATH}/build"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Auto-build watcher started${NC}"
echo -e "Watching: ${PROJECT_PATH}/Rockout"
echo -e "Press Ctrl+C to stop\n"

# Function to build
build_project() {
    echo -e "\n${YELLOW}📦 Building project...${NC}"
    cd "$PROJECT_PATH"
    
    xcodebuild \
        -project "$PROJECT_FILE" \
        -scheme "$SCHEME" \
        -sdk iphonesimulator \
        -destination "$DESTINATION" \
        -derivedDataPath "$BUILD_DIR" \
        clean build 2>&1 | \
        grep -E "(error:|warning:|BUILD SUCCEEDED|BUILD FAILED)" | \
        head -20
    
    BUILD_STATUS=$?
    
    if [ $BUILD_STATUS -eq 0 ]; then
        echo -e "${GREEN}✅ Build succeeded!${NC}\n"
    else
        echo -e "${RED}❌ Build failed!${NC}\n"
    fi
}

# Check if fswatch is available
if command -v fswatch &> /dev/null; then
    echo -e "${GREEN}Using fswatch for file watching${NC}\n"
    
    # Watch for Swift file changes
    fswatch -o "$PROJECT_PATH/Rockout" --include="\.swift$" | while read f; do
        build_project
    done
else
    echo -e "${YELLOW}fswatch not found. Using polling method...${NC}"
    echo -e "${YELLOW}Install fswatch for better performance: brew install fswatch${NC}\n"
    
    # Fallback: Polling method
    LAST_CHECK=$(find "$PROJECT_PATH/Rockout" -name "*.swift" -type f -exec stat -f "%m" {} \; | sort -n | tail -1)
    
    while true; do
        sleep 2
        CURRENT_CHECK=$(find "$PROJECT_PATH/Rockout" -name "*.swift" -type f -exec stat -f "%m" {} \; | sort -n | tail -1)
        
        if [ "$CURRENT_CHECK" != "$LAST_CHECK" ]; then
            LAST_CHECK=$CURRENT_CHECK
            build_project
        fi
    done
fi

