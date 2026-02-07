# Recall Capabilities Fixes - Summary

## Issues Fixed

### 1. ✅ Live Transcript When Recall is Speaking

**Problem**: No live transcript was shown when Recall was speaking responses.

**Root Cause**: 
- `pendingTranscript` was only set for answers and follow-ups, not for candidate results or error messages
- `pendingTranscript` was sometimes set AFTER speaking started instead of BEFORE

**Fix**:
- Set `pendingTranscript` BEFORE speaking starts for ALL response types:
  - Answer responses (line 1546)
  - Candidate results (line 1603-1605)
  - Assistant message results (line 1635-1637)
  - Error messages (line 1672-1674)
  - Follow-up questions (line 1578, 1540)
- Set `conversationMode = .speaking` before speaking so transcript view is visible
- The `pendingTranscriptView` now shows `currentSpokenText` in real-time as words are spoken

**Files Modified**:
- `Rockout/ViewModels/RecallViewModel.swift`: Lines 1546, 1578, 1603-1605, 1635-1637, 1672-1674

### 2. ✅ User Voice Note Upload and Transcription

**Problem**: User voice notes were not being uploaded and transcribed properly.

**Root Cause**:
- Transcription might not be returned in edge function response
- User message update with transcription might fail silently
- Transcription might not be displayed even if returned

**Fix**:
- Enhanced error handling in edge function to always update user message with transcription (line 1118-1124)
- Added try-catch around transcription update in ViewModel (line 1485-1494)
- Added logging to track transcription flow
- Edge function now always returns transcription in response (line 2272)
- Edge function updates user message with transcription even if processing fails

**Files Modified**:
- `supabase/functions/recall-resolve/index.ts`: Lines 1118-1124 (enhanced error handling)
- `Rockout/ViewModels/RecallViewModel.swift`: Lines 1485-1494 (better error handling)

### 3. ✅ User Ability to Confirm Response

**Problem**: Users could not confirm responses from Recall after they were spoken.

**Root Cause**:
- `conversationMode` was changed to `.idle` or `.waitingForRefinement` immediately after TTS completed
- Confirm/decline buttons only show when `!voiceResponseService.isSpeaking` AND `pendingTranscript` is set
- Follow-up questions were spoken immediately without waiting for confirmation

**Fix**:
- Keep `conversationMode = .speaking` after TTS completes so confirm buttons remain visible
- Don't change conversation mode until user confirms or declines
- Store pending follow-up questions in `pendingFollowUpQuestion` instead of speaking immediately
- After user confirms, check for pending follow-up and speak it (line 192-210)
- All spoken responses now set `pendingTranscript` before speaking

**Files Modified**:
- `Rockout/ViewModels/RecallViewModel.swift`: 
  - Lines 1541-1551: Answer responses keep conversationMode as .speaking
  - Lines 1582-1588: Follow-up questions keep conversationMode as .speaking
  - Lines 1603-1617: Candidate results set pending transcript and keep .speaking
  - Lines 1635-1658: Assistant messages set pending transcript and keep .speaking
  - Lines 192-210: Confirm function handles pending follow-ups

## Testing Checklist

### Test 1: Live Transcript During Speaking
- [ ] Record a voice note
- [ ] Verify live transcript appears as Recall speaks
- [ ] Verify transcript updates word-by-word in real-time
- [ ] Verify full transcript is shown when speaking completes

### Test 2: Voice Note Upload and Transcription
- [ ] Record a voice note
- [ ] Verify upload succeeds (check logs)
- [ ] Verify transcription appears in user message bubble
- [ ] Verify transcription is returned in response
- [ ] Test with different audio lengths (short, medium, long)

### Test 3: Confirm Response
- [ ] Record a voice note and get a response
- [ ] Verify confirm/decline buttons appear after speaking completes
- [ ] Tap "Confirm" - verify response is saved to chat
- [ ] Tap "Decline" - verify response is not saved
- [ ] Verify follow-up questions wait for confirmation before proceeding

## Key Changes Summary

1. **All spoken responses** now set `pendingTranscript` BEFORE speaking
2. **Transcription** is always returned and displayed for user voice notes
3. **Confirm/Decline buttons** remain visible after speaking completes
4. **Follow-up questions** wait for user confirmation before proceeding
5. **Error handling** improved for transcription updates

## Files Modified

1. `Rockout/ViewModels/RecallViewModel.swift` - Fixed pending transcript setting and conversation mode management
2. `supabase/functions/recall-resolve/index.ts` - Enhanced transcription error handling and always updates user message

## Next Steps

1. Test with real voice inputs
2. Verify transcription appears in UI
3. Test confirm/decline flow
4. Monitor logs for any issues
5. Deploy updated edge function if needed

