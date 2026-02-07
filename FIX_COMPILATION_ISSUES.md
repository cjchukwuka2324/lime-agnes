# Fix Compilation Issues - RecallStateMachine, SpeechTranscriber, AudioSessionManager

## Status
✅ Files exist in filesystem
✅ Files are in Xcode project
✅ Files are in build phase
✅ File paths are correct

## Issue
Xcode compiler cannot find the types even though files are properly configured.

## Solution Steps

### Step 1: Clean Build Folder
1. In Xcode: Product → Clean Build Folder (Cmd+Shift+K)
2. Wait for cleaning to complete

### Step 2: Close and Reopen Xcode
1. Quit Xcode completely (Cmd+Q)
2. Reopen the project
3. Wait for indexing to complete (watch the progress bar at top)

### Step 3: Rebuild
1. Product → Build (Cmd+B)
2. If errors persist, continue to Step 4

### Step 4: Verify File Target Membership
1. Select `RecallStateMachine.swift` in Project Navigator
2. Open File Inspector (right panel)
3. Under "Target Membership", ensure "Rockout" is checked
4. Repeat for `SpeechTranscriber.swift` and `AudioSessionManager.swift`

### Step 5: Derived Data Clean (if needed)
If still not working:
1. Xcode → Settings → Locations
2. Note the Derived Data path
3. Quit Xcode
4. Delete Derived Data folder
5. Reopen Xcode and rebuild

## Files Verified
- ✅ `Rockout/Services/Recall/RecallStateMachine.swift` (exists, in project, in build phase)
- ✅ `Rockout/Services/Recall/SpeechTranscriber.swift` (exists, in project, in build phase)
- ✅ `Rockout/Services/Recall/AudioSessionManager.swift` (exists, in project, in build phase)

## Types Defined
- `RecallStateMachine` class (line 7)
- `RecallState` enum (line 215)
- `RecallEvent` enum (line 224)
- `SpeechTranscriber` class
- `AudioSessionManager` class

All types are in the same module (Rockout) and should be accessible without imports.
