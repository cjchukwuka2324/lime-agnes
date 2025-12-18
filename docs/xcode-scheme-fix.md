# Fixing "Cannot clean Build Folder without an active scheme" Error

## Quick Fix Steps

### Option 1: Select the Scheme in Xcode
1. Open the project in Xcode
2. In the toolbar at the top, click on the scheme selector (next to the stop/play buttons)
3. Select **"Rockout"** from the dropdown
4. If "Rockout" doesn't appear, select **"Manage Schemes..."**
5. Check the box next to "Rockout" to make it shared
6. Click "Close"
7. Now try cleaning the build folder again

### Option 2: Restart Xcode
1. Quit Xcode completely (⌘Q)
2. Reopen the project
3. The scheme should be automatically selected

### Option 3: Clean Derived Data
1. In Xcode, go to **Xcode → Settings → Locations**
2. Click the arrow next to "Derived Data" path
3. Delete the folder for "Rockout"
4. Restart Xcode
5. Reopen the project

### Option 4: Regenerate Scheme (if above don't work)
1. In Xcode, go to **Product → Scheme → Manage Schemes...**
2. Delete the "Rockout" scheme
3. Click the "+" button to create a new scheme
4. Name it "Rockout"
5. Select the "Rockout" target
6. Check "Shared" to save it to the project
7. Click "OK"

## Verification

The scheme exists and is valid. You can verify by running:
```bash
xcodebuild -list -project Rockout.xcodeproj
```

This should show:
```
Schemes:
    Rockout
```

## Alternative: Clean via Terminal

If Xcode still won't let you clean, you can clean via terminal:
```bash
cd /Users/chukwudiebube/Downloads/RockOut-main
xcodebuild clean -project Rockout.xcodeproj -scheme Rockout
```

## Why This Happens

This error typically occurs when:
- Xcode hasn't fully loaded the project yet
- The scheme selector in the toolbar isn't showing the active scheme
- Xcode's internal state is out of sync with the project file

The project file and scheme are both valid - this is just an Xcode UI/state issue.

