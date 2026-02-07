#!/bin/bash

echo "🧹 Cleaning Xcode Derived Data..."
rm -rf ~/Library/Developer/Xcode/DerivedData/Rockout-*

echo "✅ Derived Data cleaned"
echo ""
echo "📝 Next steps in Xcode:"
echo "1. Clean Build Folder: ⌘+Shift+K"
echo "2. Close Xcode completely (⌘+Q)"
echo "3. Reopen Xcode"
echo "4. Wait for indexing to complete (watch progress bar)"
echo "5. Build: ⌘B"
echo ""
echo "The errors should be resolved after Xcode re-indexes the project."
