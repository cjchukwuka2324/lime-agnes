# Conversational Voice Music Recall Agent - Implementation Summary

## Overview

Recall has been transformed into a conversational voice-based musical library agent that can:
- Identify songs from humming using ACRCloud
- Identify songs from background audio using Shazam
- Engage in multi-turn voice conversations to refine searches
- Respond with text-to-speech (TTS) for follow-up questions
- Continue conversation until song is found

## What Was Implemented

### 1. Audio Recognition Services ✅

**File: `supabase/functions/recall-resolve/index.ts`**

- Added `identifyAudioWithACRCloud()` function for humming/partial audio recognition
- Added `identifyAudioWithShazam()` function for full song recognition
- Implemented fallback chain: ACRCloud → Shazam → Whisper+GPT-4o
- Services gracefully fail if credentials not configured

### 2. Conversational Flow Logic ✅

**File: `supabase/functions/recall-resolve/index.ts`**

- Enhanced system prompt to generate follow-up questions when confidence < 0.7
- Added `follow_up_question` and `conversation_state` to response structure
- Follow-up questions are stored as assistant messages with type `follow_up`
- Conversation context tracks:
  - Previous queries
  - Rejected candidates
  - Previous questions asked
  - User clarifications

### 3. Text-to-Speech Integration ✅

**New File: `Rockout/Services/Recall/VoiceResponseService.swift`**

- Created TTS service using `AVSpeechSynthesizer`
- Supports play/pause/stop
- Handles interruptions when user starts recording
- Observable `isSpeaking` state

**File: `Rockout/ViewModels/RecallViewModel.swift`**

- Integrated TTS service
- Auto-plays follow-up questions
- Auto-plays high-confidence results (optional)
- Stops TTS when user starts recording
- Added `conversationMode` state tracking

### 4. Continuous Voice Conversation UI ✅

**File: `Rockout/Views/Recall/RecallMessageBubble.swift`**

- Added `follow_up` message type support
- TTS playback controls for assistant messages
- Auto-play follow-up questions on appear
- Visual indicator for follow-up messages

**File: `Rockout/Views/Recall/RecallOrbView.swift`**

- Added conversation mode visual indicators
- Pulsing animation when waiting for refinement
- Visual feedback for speaking state

**File: `Rockout/Views/Recall/RecallHomeView.swift`**

- Added conversation mode overlays
- "Ready for your response" indicator
- "AI is speaking..." indicator

### 5. Database Schema Updates ✅

**File: `supabase/recall.sql`**

- Added `follow_up` to `message_type` CHECK constraint

**File: `Rockout/Models/Recall/RecallModels.swift`**

- Added `follow_up` case to `RecallMessageType` enum
- Added `followUpQuestion` and `conversationState` to `RecallResolveResponse`

## Configuration Required

### 1. Deploy Database Schema Update

Run this SQL in Supabase SQL Editor:

```sql
ALTER TABLE public.recall_messages 
DROP CONSTRAINT IF EXISTS recall_messages_message_type_check;

ALTER TABLE public.recall_messages 
ADD CONSTRAINT recall_messages_message_type_check 
CHECK (message_type IN ('text', 'voice', 'image', 'candidate', 'status', 'follow_up'));
```

### 2. Set Up Audio Recognition API Keys

**ACRCloud (Recommended for humming):**
```bash
supabase secrets set ACRCLOUD_ACCESS_KEY=your_access_key
supabase secrets set ACRCLOUD_ACCESS_SECRET=your_access_secret
supabase secrets set ACRCLOUD_HOST=identify-us-west-2.acrcloud.com
```

**Shazam (Optional, for full songs):**
```bash
supabase secrets set SHAZAM_API_KEY=your_api_key
```

**Note:** If API keys are not set, the system will gracefully fall back to Whisper transcription + GPT-4o search.

### 3. Deploy Edge Function

```bash
cd supabase/functions/recall-resolve
supabase functions deploy recall-resolve
```

## How It Works

### Voice Input Flow

1. **User long-presses orb** → Recording starts
2. **User releases** → Audio uploaded to storage
3. **Audio Recognition Pipeline:**
   - Try ACRCloud (humming/partial audio)
   - If fails/low confidence → Try Shazam (full songs)
   - If fails → Fallback to Whisper transcription + GPT-4o search
4. **If high confidence match found:**
   - Return candidate immediately
   - Speak result via TTS (optional)
5. **If low confidence:**
   - Generate follow-up question
   - Insert as `follow_up` message
   - Speak question via TTS
   - Wait for user's next voice input
6. **User speaks again** → Process with conversation context
7. **Repeat until found or user confirms**

### Conversation Context

The system tracks:
- Previous user queries
- Rejected candidates (don't suggest again)
- Previously asked questions (avoid repetition)
- User clarifications (build on these)

This context is passed to GPT-4o to refine searches and generate better follow-up questions.

## Testing

1. **Test Humming Recognition:**
   - Long-press orb and hum a song
   - Should try ACRCloud first
   - If configured correctly, should identify song

2. **Test Background Audio:**
   - Record audio with music playing in background
   - Should try Shazam for recognition
   - Should fallback to transcription if needed

3. **Test Conversational Flow:**
   - Ask vague question (e.g., "that song with the beat")
   - Should receive follow-up question via TTS
   - Respond with voice
   - Should refine search based on conversation

4. **Test TTS:**
   - Verify follow-up questions are spoken
   - Verify TTS stops when user starts recording
   - Verify play/pause controls work

## Known Limitations

1. **ACRCloud API Implementation:**
   - Current implementation uses simplified authentication
   - May need HMAC-SHA1 signature for production
   - Refer to ACRCloud documentation for exact API format

2. **Shazam API:**
   - Implementation uses RapidAPI format
   - May need adjustment based on actual Shazam API
   - Consider using ShazamKit for iOS native recognition (future enhancement)

3. **TTS Voice:**
   - Currently uses default iOS voice
   - Can be customized in `VoiceResponseService.swift`

## Future Enhancements

1. **iOS Native ShazamKit:**
   - Use ShazamKit framework for on-device recognition
   - Faster, no API calls needed
   - Better privacy

2. **Voice Selection:**
   - Allow user to choose TTS voice (male/female)
   - Support multiple languages

3. **Conversation History:**
   - Show full conversation thread
   - Allow user to review previous exchanges

4. **Smart Follow-ups:**
   - Use audio analysis to generate better questions
   - Detect genre, tempo, era from audio

## Files Modified

1. `supabase/functions/recall-resolve/index.ts` - Audio recognition, conversation logic
2. `Rockout/Services/Recall/VoiceResponseService.swift` - New TTS service
3. `Rockout/ViewModels/RecallViewModel.swift` - TTS integration, conversation flow
4. `Rockout/Views/Recall/RecallMessageBubble.swift` - TTS controls, follow-up UI
5. `Rockout/Views/Recall/RecallOrbView.swift` - Conversation state visuals
6. `Rockout/Views/Recall/RecallHomeView.swift` - Conversation mode indicators
7. `Rockout/Models/Recall/RecallModels.swift` - Added follow_up type, response fields
8. `supabase/recall.sql` - Added follow_up to message_type constraint

## Next Steps

1. **Deploy database schema update** (run SQL above)
2. **Configure API keys** (ACRCloud and/or Shazam)
3. **Deploy edge function** (`supabase functions deploy recall-resolve`)
4. **Test on device** with actual audio recordings
5. **Refine API implementations** based on actual service responses

















