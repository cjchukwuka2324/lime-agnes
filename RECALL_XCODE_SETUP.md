# Recall Xcode Project Setup

## ⚠️ IMPORTANT: Files to Add to Xcode Project

**These files MUST be manually added to your Xcode project target to fix compilation errors:**

See `ADD_MISSING_FILES.md` for detailed step-by-step instructions.

### Services
- `Rockout/Services/Recall/VoiceRecorder.swift`

### ViewModels
- `Rockout/ViewModels/RecallViewModel.swift`

### Views (⚠️ MUST ADD TO XCODE PROJECT)
- `Rockout/Views/Recall/RecallOrbView.swift`
- `Rockout/Views/Recall/RecallComposerBar.swift`
- `Rockout/Views/Recall/RecallMessageBubble.swift`
- `Rockout/Views/Recall/RecallCandidateCard.swift`
- `Rockout/Views/Recall/RecallCandidateDetailView.swift` ⚠️ **CRITICAL - REQUIRED FOR COMPILATION**
- `Rockout/Views/Recall/RecallRepromptSheet.swift` ⚠️ **REQUIRED** (used by RecallCandidateDetailView)
- `Rockout/Views/Recall/RecallSourcesSheet.swift`
- `Rockout/Views/Recall/RecallStashedView.swift`

### Modified Files (already in project)
- `Rockout/Models/Recall/RecallModels.swift` ✓
- `Rockout/Services/Recall/RecallService.swift` ✓
- `Rockout/Views/Recall/RecallHomeView.swift` ✓

## Target Membership

Ensure all new files are added to the **Rockout** target.

## Build Settings

No special build settings required. All dependencies are standard:
- SwiftUI
- AVFoundation (for VoiceRecorder)
- PhotosUI (for image picker)
- Combine (for reactive updates)

## Testing in Xcode

1. **Build the project** - Should compile without errors
2. **Run on simulator/device** - Navigate to Recall tab
3. **Test orb tap** - Should request mic permission, start recording
4. **Test text input** - Type and send, should show "Searching..." then candidate
5. **Test image upload** - Tap photo button, select image, should upload and resolve
6. **Test stashed view** - Tap bookmark icon, should show history

## Supabase Setup Required

Before testing, ensure:
1. ✅ SQL migration applied (`supabase/recall.sql`)
2. ✅ Storage buckets created (`recall-images`, `recall-audio`)
3. ✅ Edge function deployed (`recall-resolve`) OR mock will be used
4. ✅ OPENAI_API_KEY set (if using edge function)

See `RECALL_IMPLEMENTATION_SUMMARY.md` for detailed setup instructions.

