# Xcode Project File Update Guide

This guide helps you update the Xcode project file to remove SoundPrint/RockList references and add Recall files.

## Quick Method (Recommended)

### In Xcode:

1. **Remove Deleted Files:**
   - Open Project Navigator (⌘1)
   - Find these folders/files and delete them (right-click → Delete → Move to Trash):
     - `Rockout/Views/SoundPrint/`
     - `Rockout/Views/RockList/`
     - `Rockout/Services/RockList/`
     - `Rockout/ViewModels/RockList/`
     - `Rockout/Models/RockList/`
     - `Rockout/Views/Onboarding/Slides/SoundPrintSlide.swift`
     - `Rockout/Views/Onboarding/Slides/RockListsSlide.swift`
     - `RockoutTests/RockListServiceTests.swift`
     - `RockoutTests/RockListViewModelTests.swift`

2. **Add New Recall Files:**
   - Right-click `Rockout/Models/` → Add Files to "Rockout"
   - Select `Rockout/Models/Recall/RecallModels.swift`
   - Check "Copy items if needed" (unchecked)
   - Check "Add to targets: Rockout" (checked)
   - Repeat for:
     - `Rockout/Services/Recall/RecallService.swift`
     - `Rockout/Views/Recall/RecallHomeView.swift`
     - `Rockout/Views/Recall/RecallTextInputView.swift`
     - `Rockout/Views/Recall/RecallVoiceInputView.swift`
     - `Rockout/Views/Recall/RecallImageInputView.swift`
     - `Rockout/Views/Recall/RecallResultsView.swift`

3. **Clean Build Folder:**
   - Product → Clean Build Folder (⇧⌘K)

4. **Build:**
   - Product → Build (⌘B)
   - Fix any import errors if they appear

## Verification

After updating, search the project for any remaining references:

1. In Xcode: Edit → Find → Find in Project (⇧⌘F)
2. Search for: `SoundPrint` (should find 0 results)
3. Search for: `RockList` (should find 0 results, except in comments/docs)

## If Build Fails

**Common Issues:**

1. **"Cannot find type 'RecallHomeView'"**
   - Verify file is added to target
   - Check file is in correct folder structure
   - Clean build folder and rebuild

2. **"No such module 'Supabase'"**
   - Update Swift Package Manager dependencies
   - File → Packages → Update to Latest Package Versions

3. **Missing imports**
   - Add `import SwiftUI` to new view files if needed
   - Add `import Supabase` to service files if needed

## Alternative: Script-Based Update

If you prefer automation, you can use a script to update the pbxproj file, but this is risky and not recommended. The Xcode GUI method is safer.

