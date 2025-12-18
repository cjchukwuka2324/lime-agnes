# Recall Feature Implementation Summary

## Overview

The Recall feature has been fully implemented to replace SoundPrint and RockList. Recall allows users to find songs from memory using text, voice notes, or images (with OCR).

## What Was Implemented

### 1. Database Schema ✅
- **File**: `sql/recall_schema.sql`
- Tables: `tracks`, `recall_events`, `recall_candidates`, `recall_confirmations`, `recall_crowd_posts`
- RLS policies configured
- Enum type: `recall_input_type`

### 2. Supabase Edge Functions ✅
- **recall_create** (`supabase/functions/recall_create/index.ts`)
- **recall_process** (`supabase/functions/recall_process/index.ts`) - Uses OpenAI with web search
- **recall_confirm** (`supabase/functions/recall_confirm/index.ts`)
- **recall_ask_crowd** (`supabase/functions/recall_ask_crowd/index.ts`)
- Documentation: `supabase/functions/README.md`

### 3. Swift Models ✅
- **File**: `Rockout/Models/Recall/RecallModels.swift`
- Models: `RecallEvent`, `RecallCandidate`, `RecallConfirmation`, `RecallCrowdPost`
- Enums: `RecallInputType`, `RecallStatus`

### 4. Swift Service ✅
- **File**: `Rockout/Services/Recall/RecallService.swift`
- Methods: `createRecall`, `processRecall`, `fetchRecall`, `fetchCandidates`, `confirmRecall`, `askCrowd`, `uploadMedia`
- Uses direct HTTP requests to Edge Functions

### 5. SwiftUI Views ✅
- **RecallHomeView** - Main home screen with input type selector
- **RecallTextInputView** - Text input for song descriptions
- **RecallVoiceInputView** - Voice recording and upload
- **RecallImageInputView** - Image picker with on-device OCR
- **RecallResultsView** - Results display with candidates, confidence, sources
- Supporting views: `CandidateCard`, `SourcesView`, `RecentRecallCard`

### 6. Tab Bar Integration ✅
- **File**: `Rockout/Views/Main/MainTabView.swift`
- SoundPrint tab removed
- Recall tab added with `sparkles.magnifyingglass` icon
- Tab order: GreenRoom (0), Recall (1), StudioSessions (2), Profile (3)

### 7. Navigation Cleanup ✅
- Removed RockList navigation from `FeedView.swift`
- Removed `onNavigateToRockList` from `FeedCardView.swift`
- Removed SoundPrint/RockList from onboarding (`OnboardingFlowView.swift`)

### 8. Documentation ✅
- Implementation notes: `docs/recall-implementation-notes.md`
- Storage setup: `docs/supabase/recall_storage_setup.md`
- QA guide: `docs/recall-qa.md`

## What Still Needs to Be Done

### 1. File Deletions (Manual)
The following files/directories should be deleted:
- `Rockout/Views/SoundPrint/` (entire directory)
- `Rockout/Views/RockList/` (entire directory)
- `Rockout/Services/RockList/` (entire directory)
- `Rockout/ViewModels/RockList/` (entire directory)
- `Rockout/Models/RockList/` (entire directory)
- `Rockout/Views/Onboarding/Slides/SoundPrintSlide.swift`
- `Rockout/Views/Onboarding/Slides/RockListsSlide.swift`
- `Assets/OnboardingVideos/soundprint_onboarding.mp4`
- `Assets/OnboardingVideos/rocklist_onboarding2.mp4`

### 2. Xcode Project File Updates
- Remove deleted file references from `Rockout.xcodeproj/project.pbxproj`
- Add new Recall files to project:
  - `Rockout/Models/Recall/RecallModels.swift`
  - `Rockout/Services/Recall/RecallService.swift`
  - `Rockout/Views/Recall/RecallHomeView.swift`
  - `Rockout/Views/Recall/RecallTextInputView.swift`
  - `Rockout/Views/Recall/RecallVoiceInputView.swift`
  - `Rockout/Views/Recall/RecallImageInputView.swift`
  - `Rockout/Views/Recall/RecallResultsView.swift`

### 3. Database Migration
Run in Supabase SQL Editor:
```sql
-- Execute: sql/recall_schema.sql
```

### 4. Storage Bucket Setup
1. Create `recall-media` bucket (private)
2. Apply RLS policies (see `docs/supabase/recall_storage_setup.md`)

### 5. Edge Function Deployment
```bash
supabase functions deploy recall_create
supabase functions deploy recall_process
supabase functions deploy recall_confirm
supabase functions deploy recall_ask_crowd
```

### 6. Environment Variables
```bash
supabase secrets set OPENAI_API_KEY="your-openai-api-key"
```

## Key Features

### Input Methods
1. **Text**: User types description of song
2. **Voice**: User records voice note, transcribed via OpenAI Whisper
3. **Image**: User uploads image, OCR extracts text on-device

### Processing Flow
1. Create recall event → `recall_create`
2. Process with OpenAI web search → `recall_process`
3. Store candidates in database
4. Auto-create GreenRoom post if confidence < 0.65

### Results Display
- Ranked candidates with confidence scores
- Reason for each match
- Highlight snippets (lyrics/memorable lines)
- Source URLs
- Actions: Confirm, Post to GreenRoom, View Sources

### Integration
- Posts to GreenRoom when sharing results
- Auto-creates "Ask the Crowd" post when confidence is low
- Links recall events to GreenRoom posts

## Testing

See `docs/recall-qa.md` for comprehensive testing guide.

## Known Limitations

1. Voice/image upload requires two-step process (create recall, then update with media_path)
2. Polling-based status updates (2-second interval, not realtime)
3. OCR is on-device only (no cloud fallback)
4. Edge Functions use service role for some operations

## Next Steps

1. Delete SoundPrint/RockList files
2. Update Xcode project file
3. Run database migration
4. Create storage bucket
5. Deploy Edge Functions
6. Set OpenAI API key
7. Test end-to-end
8. Build and run app

