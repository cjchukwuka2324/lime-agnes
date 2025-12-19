# Recall Conversational Orb Implementation Summary

## Overview

Recall has been redesigned from a segmented input picker to a conversational chat interface with:
- **Orb of stars** as primary control (tap to record voice)
- **Chat thread** showing user/assistant messages
- **Composer bar** always visible (text + photo attach)
- **Stashed view** for history
- **New data model**: threads + messages (migrated from events)

## Files Created/Modified

### Database & Backend

1. **`supabase/recall.sql`** (NEW)
   - Creates `recall_threads`, `recall_messages`, `recall_stash` tables
   - Sets up RLS policies
   - Migrates existing `recall_events` data to new structure
   - Includes storage bucket setup comments

2. **`supabase/functions/recall-resolve/index.ts`** (NEW)
   - Edge function for processing recall messages
   - Handles text, voice (with transcription), and image inputs
   - Returns candidate results with confidence and sources
   - Upserts to stash automatically

### Swift Models

3. **`Rockout/Models/Recall/RecallModels.swift`** (MODIFIED)
   - Added: `RecallOrbState` enum
   - Added: `RecallMessageRole` enum
   - Added: `RecallMessageType` enum
   - Added: `RecallThread` struct
   - Added: `RecallMessage` struct (with JSONB handling)
   - Added: `RecallCandidateData` struct
   - Added: `RecallSource` struct
   - Added: `RecallStashItem` struct
   - Added: `RecallResolveResponse` struct
   - Added: `AssistantMessage` struct
   - Added: `AnyCodable` helper for JSONB decoding
   - Kept: Existing models for backward compatibility

### Services

4. **`Rockout/Services/Recall/RecallService.swift`** (MODIFIED)
   - Added: `createThreadIfNeeded()` - Creates or returns recent thread
   - Added: `fetchThread(threadId:)` - Gets thread by ID
   - Added: `insertMessage(...)` - Inserts message with all types
   - Added: `fetchMessages(threadId:)` - Gets all messages in thread
   - Added: `updateThreadLastMessage(threadId:)` - Updates thread timestamp
   - Added: `uploadMedia(data:threadId:fileName:contentType:)` - Uploads to recall-images/recall-audio buckets
   - Added: `resolveRecall(...)` - Calls edge function or returns mock
   - Added: `fetchStash()` - Gets user's stashed items
   - Added: `deleteFromStash(threadId:)` - Removes from stash
   - Added: `createMockResponse()` - Fallback for testing
   - Kept: Legacy methods for backward compatibility

5. **`Rockout/Services/Recall/VoiceRecorder.swift`** (NEW)
   - `VoiceRecorder` class with `@Published` properties
   - `requestPermission()` - Requests mic permission
   - `startRecording()` - Starts .m4a recording with AVAudioRecorder
   - `stopRecording()` - Stops and provides URL
   - Live meter level updates (~20x per second)
   - Handles audio session setup/teardown

### ViewModels

6. **`Rockout/ViewModels/RecallViewModel.swift`** (NEW)
   - Manages thread, messages, composer text, orb state
   - `startNewThreadIfNeeded()` - Initializes thread
   - `sendText()` - Sends text message and resolves
   - `pickImage(_:)` - Handles image upload and resolution
   - `orbTapped()` - Toggles voice recording
   - `loadMessages()` - Fetches messages for current thread
   - `loadStash()` - Fetches stashed items
   - `openThread(threadId:)` - Opens a specific thread
   - Observes `VoiceRecorder` for state updates

### UI Components

7. **`Rockout/Views/Recall/RecallHomeView.swift`** (REPLACED)
   - New conversational chat UI
   - Shows orb when messages empty
   - Shows message list when messages exist
   - Always shows composer bar at bottom
   - Stashed button in toolbar
   - Auto-scrolls to latest message

8. **`Rockout/Views/Recall/RecallOrbView.swift`** (NEW)
   - Canvas-based particle system (~75 stars)
   - State-driven animations:
     - `idle`: slow twinkle + gentle pulse
     - `listening(level)`: pulse responds to mic, tighter orbit
     - `thinking`: faster orbit, shimmer
     - `done(confidence)`: confidence-based sparkle/wobble
     - `error`: subtle shake
   - Tap gesture to start/stop recording

9. **`Rockout/Views/Recall/RecallComposerBar.swift`** (NEW)
   - Photo attach button (PhotosPicker)
   - Multiline text input
   - Send button (disabled when empty)
   - Always visible at bottom

10. **`Rockout/Views/Recall/RecallMessageBubble.swift`** (NEW)
    - Renders user messages (right-aligned, green)
    - Renders assistant status messages (spinner)
    - Renders assistant candidate messages (embeds card)
    - Shows image thumbnails for image messages
    - Shows voice note indicator for voice messages

11. **`Rockout/Views/Recall/RecallCandidateCard.swift`** (NEW)
    - Displays song title, artist, confidence bar
    - Shows reason and lyric snippet
    - Actions: Open Song, Sources, Share, Confirm, Not it
    - Confidence-based color coding

12. **`Rockout/Views/Recall/RecallSourcesSheet.swift`** (NEW)
    - Lists sources from candidate
    - Each source is tappable (opens URL)
    - Shows title, snippet, URL

13. **`Rockout/Views/Recall/RecallStashedView.swift`** (NEW)
    - Lists all stashed items
    - Shows song title, artist, confidence, time ago
    - Tap to open thread
    - Swipe to remove from stash

## Setup Instructions

### 1. Database Setup

Run the SQL migration:

```bash
# Connect to your Supabase project
supabase db reset  # Or apply manually via dashboard

# Or apply via Supabase Dashboard:
# 1. Go to SQL Editor
# 2. Paste contents of supabase/recall.sql
# 3. Run the query
```

### 2. Storage Buckets

Create two private buckets in Supabase Dashboard:

1. **`recall-images`** (private)
   - Storage policies: Users can read/write only their own files
   - Path format: `{user_id}/{thread_id}/image_{timestamp}.jpg`

2. **`recall-audio`** (private)
   - Storage policies: Users can read/write only their own files
   - Path format: `{user_id}/{thread_id}/voice_{timestamp}.m4a`

**Storage Policy Example:**
```sql
-- Allow users to upload their own files
CREATE POLICY "Users can upload own files"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id IN ('recall-images', 'recall-audio')
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Allow users to read their own files
CREATE POLICY "Users can read own files"
ON storage.objects FOR SELECT
USING (
  bucket_id IN ('recall-images', 'recall-audio')
  AND (storage.foldername(name))[1] = auth.uid()::text
);
```

### 3. Edge Function Deployment

Deploy the `recall-resolve` function:

```bash
cd supabase/functions/recall-resolve
supabase functions deploy recall-resolve

# Set environment variable:
supabase secrets set OPENAI_API_KEY=your_key_here
```

**Or via Supabase Dashboard:**
1. Go to Edge Functions
2. Create new function: `recall-resolve`
3. Paste contents of `supabase/functions/recall-resolve/index.ts`
4. Set `OPENAI_API_KEY` secret

### 4. Xcode Project Setup

**Add new files to Xcode project:**

1. **Services:**
   - `Rockout/Services/Recall/VoiceRecorder.swift`

2. **ViewModels:**
   - `Rockout/ViewModels/RecallViewModel.swift`

3. **Views:**
   - `Rockout/Views/Recall/RecallOrbView.swift`
   - `Rockout/Views/Recall/RecallComposerBar.swift`
   - `Rockout/Views/Recall/RecallMessageBubble.swift`
   - `Rockout/Views/Recall/RecallCandidateCard.swift`
   - `Rockout/Views/Recall/RecallSourcesSheet.swift`
   - `Rockout/Views/Recall/RecallStashedView.swift`

**Update existing files:**
- `Rockout/Models/Recall/RecallModels.swift` (already modified)
- `Rockout/Services/Recall/RecallService.swift` (already modified)
- `Rockout/Views/Recall/RecallHomeView.swift` (already replaced)

**Info.plist:**
- Microphone permission already set (can update text if desired):
  - Current: "RockOut needs microphone access to record voice messages for your posts"
  - Suggested: "Recall uses your microphone to identify songs from voice notes."

### 5. Testing Checklist

- [ ] Orb tap starts/stops recording
- [ ] Mic permission requested on first tap
- [ ] Meter level updates during recording (orb pulse)
- [ ] Text input + send works
- [ ] Photo upload + send works
- [ ] Voice recording uploads and resolves
- [ ] Candidate cards display correctly
- [ ] Confidence bar shows correct color
- [ ] Sources sheet opens and links work
- [ ] Stashed view shows history
- [ ] Tap stashed item opens thread
- [ ] Swipe to remove from stash works
- [ ] Edge function mock works if not deployed
- [ ] Migration preserved existing recall_events data

## Architecture Notes

### Data Flow

```
User Action (tap orb / send text / upload image)
  ↓
RecallViewModel
  ↓
RecallService (insert message, upload media, call edge function)
  ↓
Supabase (DB insert, Storage upload, Edge Function)
  ↓
Edge Function (transcribe if voice, call OpenAI, return candidate)
  ↓
RecallService (update message, upsert stash)
  ↓
RecallViewModel (update state, reload messages)
  ↓
UI Refresh (new message appears, orb state changes)
```

### Thread Management

- One thread per user (reuses if recent, creates new if >1 hour old)
- All messages in a thread are loaded and displayed
- Thread `last_message_at` updated on each message
- Stash entry created/updated when candidate found

### Orb State Machine

```
idle → tap → listening(level) → tap → thinking → done(confidence) → (2s) → idle
                                                      ↓
                                                   error
```

### Message Types

- **user**: `text`, `voice`, `image`
- **assistant**: `status` (Searching...), `candidate` (song result)
- **system**: (reserved for future use)

## Migration Notes

- Existing `recall_events` are converted to threads (1:1)
- Each event becomes a user message
- Top candidate becomes an assistant candidate message
- Stash entry created for each migrated thread with candidate
- Old tables (`recall_events`, `recall_candidates`) remain for reference
- New UI only uses new tables

## Known Limitations

1. **Edge Function Mock**: If `recall-resolve` not deployed, uses mock response (always returns "Example Song" with 85% confidence)
2. **Image OCR**: Image input currently sends placeholder text; OCR integration can be added later
3. **Message Updates**: Status messages are replaced by inserting new candidate messages (could be optimized to update existing)
4. **Thread Title**: Not yet auto-generated from first message
5. **Song URL**: Not yet populated (can be added by querying music services)

## Next Steps (Optional Enhancements)

1. Add OCR for image inputs (Tesseract or Vision framework)
2. Integrate with Spotify/Apple Music APIs for song URLs
3. Add "Ask GreenRoom" button to candidate cards
4. Auto-generate thread titles from first message
5. Add message search/filter
6. Add thread deletion
7. Optimize message updates (update instead of insert for status→candidate)








