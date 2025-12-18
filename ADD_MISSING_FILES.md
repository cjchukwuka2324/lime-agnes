# Add Missing Files to Xcode Project

## ⚠️ CRITICAL: Required Files for Compilation

**One file MUST be added to your Xcode project to fix compilation errors:**

1. **`Rockout/Views/Recall/RecallCandidateDetailView.swift`** ⚠️ **REQUIRED**

> Note: `RecallTabBarIconHelper.swift` is no longer needed as its functionality has been moved inline to `MainTabView.swift`

## Steps to Add Files

### Option 1: Drag and Drop (Easiest)

1. Open Xcode
2. In Project Navigator, locate:
   - `Rockout/Views/Recall/` folder
   - `Rockout/Features/Recall/UI/` folder (create if it doesn't exist)
3. Drag this file from Finder into the appropriate folder in Xcode:
   - `RecallCandidateDetailView.swift` → `Rockout/Views/Recall/`
4. When prompted, ensure "Copy items if needed" is **unchecked**
5. Ensure "Add to targets: Rockout" is **checked**
6. Click "Finish"

### Option 2: Add Files Menu

1. In Xcode Project Navigator, right-click on `Rockout/Views/Recall/`
2. Select "Add Files to 'Rockout'..."
3. Navigate to and select `RecallCandidateDetailView.swift`
4. Ensure "Copy items if needed" is **unchecked**
5. Ensure "Add to targets: Rockout" is **checked**
6. Click "Add"

### Option 3: Verify Target Membership

If files are already in the project but still showing errors:

1. Select the file in Project Navigator
2. Open File Inspector (⌘⌥1)
3. Under "Target Membership", ensure "Rockout" is **checked**

## After Adding Files

1. Clean Build Folder: Product → Clean Build Folder (⇧⌘K)
2. Build: Product → Build (⌘B)
3. Errors should be resolved

## Verification

After adding, this error should disappear:
- ✅ `Cannot find 'RecallCandidateDetailView' in scope`

## Additional Files That May Be Needed

If you encounter other "Cannot find in scope" errors, also check:
- `Rockout/Views/Recall/RecallRepromptSheet.swift` (used by RecallCandidateDetailView)
- `Rockout/Views/Recall/RecallSourcesSheet.swift` (used by RecallCandidateCard)

