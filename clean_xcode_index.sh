#!/bin/bash
# Clean Xcode derived data and rebuild index

echo "🧹 Cleaning Xcode derived data..."
rm -rf ~/Library/Developer/Xcode/DerivedData/Rockout-*

echo "✅ Derived data cleaned"
echo ""
echo "📝 Next steps:"
echo "1. Close Xcode if it's open"
echo "2. Reopen Xcode"
echo "3. Wait for indexing to complete (watch the progress bar)"
echo "4. Build the project (⌘B)"
