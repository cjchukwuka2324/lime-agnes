#!/bin/bash

# Clean script that accurately detects and adds only NEW files to Xcode
# This avoids duplicates and only shows files that truly need to be added

set -e

# Find project directory (script location)
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Find Xcode project
XCODE_PROJECT=$(find "$PROJECT_DIR" -maxdepth 1 -name "*.xcodeproj" -type d 2>/dev/null | head -1)

if [ -z "$XCODE_PROJECT" ]; then
    echo "❌ Xcode project not found!"
    echo "   Looking in: $PROJECT_DIR"
    exit 1
fi

PROJECT_FILE="$XCODE_PROJECT/project.pbxproj"

if [ ! -f "$PROJECT_FILE" ]; then
    echo "❌ Project file not found: $PROJECT_FILE"
    exit 1
fi

echo "📦 Xcode Project: $XCODE_PROJECT"
echo "🔍 Scanning for new Swift files..."
echo ""

# Extract all Swift filenames from project.pbxproj
# Xcode stores files as: path = Filename.swift;
TEMP_PROJECT_FILES=$(mktemp)
grep -o 'path = [^;]*\.swift' "$PROJECT_FILE" | sed 's/path = //' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//' | sort -u > "$TEMP_PROJECT_FILES"

# Temporary file for new files
TEMP_NEW_FILES=$(mktemp)
NEW_COUNT=0

# Find all Swift files in Rockout directory
find "$SCRIPT_DIR" -name "*.swift" -type f | while read -r file; do
    # Skip unwanted directories
    if [[ "$file" == *"/.build/"* ]] || \
       [[ "$file" == *"/DerivedData/"* ]] || \
       [[ "$file" == *"/.git/"* ]] || \
       [[ "$file" == *"/Pods/"* ]] || \
       [[ "$file" == *"/.swiftpm/"* ]] || \
       [[ "$file" == *"/build/"* ]] || \
       [[ "$file" == *"/scripts/"* ]]; then
        continue
    fi
    
    # Get just the filename
    filename=$(basename "$file")
    
    # Get relative path from Rockout directory
    rel_path="${file#$SCRIPT_DIR/}"
    rel_path="${rel_path#./}"
    
    # Check if filename exists in project (Xcode stores by filename)
    if grep -qF "$filename" "$TEMP_PROJECT_FILES" 2>/dev/null; then
        # File is already in project
        continue
    fi
    
    # Also check if full path exists (some files might be stored with path)
    if grep -qF "$rel_path" "$PROJECT_FILE" 2>/dev/null; then
        continue
    fi
    
    # File is new - add to list
    echo "$rel_path" >> "$TEMP_NEW_FILES"
    ((NEW_COUNT++)) || true
    echo "  ➕ $rel_path"
done

# Count actual new files
ACTUAL_COUNT=$(wc -l < "$TEMP_NEW_FILES" 2>/dev/null | tr -d ' ' || echo "0")

# Cleanup temp file
rm -f "$TEMP_PROJECT_FILES"

if [ "$ACTUAL_COUNT" -gt 0 ]; then
    echo ""
    echo "📋 Found $ACTUAL_COUNT new file(s) that need to be added"
    echo ""
    echo "Files:"
    cat "$TEMP_NEW_FILES"
    echo ""
    echo "💡 To add them automatically, run:"
    echo "   cd $PROJECT_DIR && ruby Rockout/scripts/auto_add_to_xcode.rb"
    echo ""
    echo "   Or manually in Xcode:"
    echo "   1. Right-click appropriate group"
    echo "   2. Add Files to 'Rockout'..."
    echo "   3. Select the files above"
    
    # Save to file
    mv "$TEMP_NEW_FILES" "$SCRIPT_DIR/new_files_to_add.txt"
    echo ""
    echo "📄 Full list saved to: Rockout/new_files_to_add.txt"
else
    echo "✅ All Swift files are already in the Xcode project!"
    rm -f "$TEMP_NEW_FILES"
    rm -f "$SCRIPT_DIR/new_files_to_add.txt"
fi
