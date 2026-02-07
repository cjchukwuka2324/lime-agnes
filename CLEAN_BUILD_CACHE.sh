#!/bin/bash
echo "🧹 Cleaning Xcode build cache..."
echo ""

# Clean Derived Data
echo "1. Removing Derived Data..."
rm -rf ~/Library/Developer/Xcode/DerivedData/Rockout-*
echo "   ✅ Derived Data cleaned"

# Clean Module Cache
echo "2. Removing Module Cache..."
rm -rf ~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex
echo "   ✅ Module Cache cleaned"

# Clean build folder in project
echo "3. Cleaning project build folder..."
cd "$(dirname "$0")"
xcodebuild clean -project Rockout.xcodeproj -scheme Rockout 2>&1 | grep -v "warning:" || true
echo "   ✅ Project cleaned"

echo ""
echo "✅ Build cache cleaned!"
echo ""
echo "Next steps:"
echo "1. Quit Xcode completely (⌘+Q)"
echo "2. Reopen Rockout.xcodeproj"
echo "3. Wait for indexing to complete"
echo "4. Build (⌘+B)"
