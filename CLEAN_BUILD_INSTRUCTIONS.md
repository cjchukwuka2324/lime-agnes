# Xcode Build Path Issues - Clean Build Instructions

## Problem
Xcode is looking for files at paths with duplicate directory segments like:
- `/Rockout/Services/Notifications/Services/Notifications/DeviceTokenService.swift`

But the actual files are at:
- `/Rockout/Services/Notifications/DeviceTokenService.swift`

## Solution

This is typically a **build system cache issue**. The project file is correct, but Xcode's build system has cached incorrect paths.

### Steps to Fix:

1. **Clean Build Folder**
   - In Xcode: Press `⌘+Shift+K` (Product → Clean Build Folder)
   - Or use menu: Product → Clean Build Folder

2. **Close Xcode Completely**
   - Press `⌘+Q` to quit Xcode

3. **Delete Derived Data** (Recommended)
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData/Rockout-*
   ```

4. **Delete Module Cache** (Optional but thorough)
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex
   ```

5. **Reopen Xcode**
   - Open `Rockout.xcodeproj`

6. **Wait for Indexing**
   - Watch the progress bar in the top-right corner
   - Wait until indexing completes (can take a few minutes)

7. **Build Again**
   - Press `⌘+B` to build

## If Issues Persist

If the problem continues after cleaning:

1. Check that all files exist at their expected locations
2. Verify no duplicate file references in the project
3. Consider restarting your Mac (sometimes Xcode's build system needs a full reset)

## Verification

After cleaning, verify the build succeeds without "Build input files cannot be found" errors.
