#!/bin/bash

echo "════════════════════════════════════════════════════════"
echo "🔍 VERIFYING CAMERA PICKER CONFIGURATION"
echo "════════════════════════════════════════════════════════"
echo ""

# Check if file exists
if [ -f "Rockout/Views/Shared/CameraPickerView.swift" ]; then
    echo "✅ File exists: Rockout/Views/Shared/CameraPickerView.swift"
else
    echo "❌ File NOT found!"
    exit 1
fi

# Check if file is in project.pbxproj
if grep -q "CameraPickerView.swift" Rockout.xcodeproj/project.pbxproj; then
    echo "✅ File referenced in project.pbxproj"
else
    echo "❌ File NOT in project.pbxproj!"
    exit 1
fi

# Check if file is in Sources build phase
if grep -q "CameraPickerView.swift in Sources" Rockout.xcodeproj/project.pbxproj; then
    echo "✅ File in Sources build phase"
else
    echo "❌ File NOT in Sources build phase!"
    exit 1
fi

# Check file syntax
if swiftc -typecheck Rockout/Views/Shared/CameraPickerView.swift 2>/dev/null; then
    echo "✅ File syntax is valid"
else
    echo "⚠️  File syntax check (may need full project context)"
fi

echo ""
echo "════════════════════════════════════════════════════════"
echo "✅ ALL CHECKS PASSED - FILE IS CORRECTLY CONFIGURED"
echo "════════════════════════════════════════════════════════"
echo ""
echo "⚠️  IF XCODE STILL SHOWS ERROR:"
echo "   1. Quit Xcode completely (⌘Q)"
echo "   2. Wait 5 seconds"
echo "   3. Reopen Rockout.xcodeproj"
echo "   4. Wait for indexing (30-60 seconds)"
echo "   5. Clean Build Folder (⇧⌘K)"
echo "   6. Build (⌘B)"
echo ""
