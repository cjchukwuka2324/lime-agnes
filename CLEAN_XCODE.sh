#!/bin/bash

echo "=== Cleaning Xcode Cache and Build Artifacts ==="
echo ""

# Close Xcode if running
echo "Step 1: Checking if Xcode is running..."
if pgrep -x "Xcode" > /dev/null; then
    echo "⚠️  Xcode is running. Please quit Xcode (⌘Q) and run this script again."
    exit 1
fi
echo "✅ Xcode is not running"
echo ""

# Clean Derived Data
echo "Step 2: Cleaning Derived Data..."
rm -rf ~/Library/Developer/Xcode/DerivedData/*
echo "✅ Derived Data cleaned"
echo ""

# Clean Module Cache
echo "Step 3: Cleaning Module Cache..."
rm -rf ~/Library/Caches/com.apple.dt.Xcode/*
echo "✅ Module Cache cleaned"
echo ""

# Clean Project Build artifacts
echo "Step 4: Cleaning project build artifacts..."
cd /Users/chukwudiebube/Downloads/RockOut-main
rm -rf Rockout.xcodeproj/xcuserdata
rm -rf Rockout.xcodeproj/project.xcworkspace/xcuserdata
rm -rf .build
echo "✅ Project build artifacts cleaned"
echo ""

echo "=== All Done! ==="
echo ""
echo "Now do the following:"
echo "1. Open Xcode"
echo "2. Wait for 'Indexing...' to complete (watch the progress bar at top)"
echo "3. Press ⇧⌘K (Shift + Command + K) to Clean Build Folder"
echo "4. Go to File → Packages → Reset Package Caches"
echo "5. Press ⌘B to Build"
echo ""
echo "You should see 0 errors! 🎉"

