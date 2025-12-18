# Recall Feature QA Testing Guide

## Prerequisites

1. Run SQL migration: `sql/recall_schema.sql`
2. Create storage bucket: `recall-media` (see `docs/supabase/recall_storage_setup.md`)
3. Deploy Edge Functions:
   ```bash
   supabase functions deploy recall_create
   supabase functions deploy recall_process
   supabase functions deploy recall_confirm
   supabase functions deploy recall_ask_crowd
   ```
4. Set environment variable:
   ```bash
   supabase secrets set OPENAI_API_KEY="your-key"
   ```

## Test Cases

### 1. Text Recall - Basic Flow

**Steps:**
1. Open Recall tab
2. Select "Text" input type
3. Enter: "I heard this song in a TikTok, it goes 'dun dun dun'"
4. Tap "Find Song"
5. Wait for processing

**Expected:**
- Recall created with status "queued"
- Status changes to "processing"
- Results show candidates with confidence scores
- Each candidate shows title, artist, reason, confidence bar
- Sources button works
- Confirm button works
- Post to GreenRoom button works

### 2. Voice Recall - Transcription

**Steps:**
1. Select "Voice" input type
2. Tap record button
3. Record: "Find the song that goes 'I want it that way'"
4. Stop recording
5. Tap "Find Song"
6. Wait for processing

**Expected:**
- Audio uploaded to storage
- Transcript appears in recall_event
- Processing uses transcript for search
- Results show candidates

### 3. Image Recall - OCR

**Steps:**
1. Select "Image" input type
2. Pick an image with text (lyrics, song title, etc.)
3. Wait for OCR to extract text
4. Edit text if needed
5. Tap "Find Song"
6. Wait for processing

**Expected:**
- OCR extracts text from image
- Text is editable
- Image uploaded to storage (optional)
- Processing uses OCR text for search
- Results show candidates

### 4. Low Confidence - Ask the Crowd

**Steps:**
1. Create a recall with vague description: "a song I heard once"
2. Wait for processing

**Expected:**
- Status becomes "needs_crowd"
- GreenRoom post automatically created
- Post visible in "View in GreenRoom" button
- Post includes transcript/raw_text
- Post includes media if available (voice/image)
- Candidates still shown (even if low confidence)

### 5. Confirm Candidate

**Steps:**
1. View results with candidates
2. Tap "Confirm" on a candidate
3. Check database

**Expected:**
- Confirmation saved to `recall_confirmations` table
- Recall status updated to "done"
- UI updates to show confirmation

### 6. Post to GreenRoom

**Steps:**
1. View results with candidates
2. Tap "Post to GreenRoom" on a candidate
3. Navigate to GreenRoom

**Expected:**
- Post created in GreenRoom
- Post text: "🎵 Found this song: [title] by [artist]"
- Post includes "[Recall: Identified via AI search]"
- Navigation to post works
- Post visible in feed

### 7. Recent Recalls

**Steps:**
1. Create multiple recalls
2. Return to Recall home
3. Scroll to "Recent Recalls"

**Expected:**
- Shows last 20 recalls
- Each shows input type icon
- Status indicator (queued, processing, done, etc.)
- Confidence shown for done recalls
- Tapping navigates to results

### 8. Error Handling

**Test Cases:**
- Network error during creation
- OpenAI API failure
- Invalid input (empty text)
- Storage upload failure

**Expected:**
- Error messages displayed
- App doesn't crash
- User can retry

### 9. Polling and Status Updates

**Steps:**
1. Create a recall
2. Watch status updates
3. Don't navigate away

**Expected:**
- Status updates automatically (every 2 seconds)
- "Queued" → "Processing" → "Done" or "needs_crowd"
- Candidates appear when ready
- Polling stops when done/failed

### 10. Sources View

**Steps:**
1. View results with candidates
2. Tap "Sources" button
3. View sources list

**Expected:**
- Sheet shows list of source URLs
- URLs are clickable links
- Opens in browser
- "Done" button dismisses sheet

## Edge Cases

### Empty Results
- Create recall with very obscure description
- Should show "No matches found" or low confidence candidates

### Very Long Text
- Enter very long description (500+ words)
- Should still process (may be truncated by OpenAI)

### Multiple Rapid Recalls
- Create 5 recalls quickly
- All should process independently
- No conflicts or errors

### Offline Mode
- Create recall while offline
- Should show error
- Should allow retry when online

## Performance

- Text recall: < 5 seconds
- Voice recall: < 30 seconds (includes transcription)
- Image recall: < 10 seconds (includes OCR)
- Status polling: Updates every 2 seconds

## Database Verification

After each test, verify in Supabase:

1. `recall_events` table has new row
2. `recall_candidates` table has candidates (if processing succeeded)
3. `recall_confirmations` table has confirmation (if confirmed)
4. `recall_crowd_posts` table has link (if needs_crowd)
5. `posts` table has new post (if posted to GreenRoom or asked crowd)

## Known Limitations

1. Voice/image upload requires creating recall first, then updating with media_path
2. Edge Functions use service role key (no user context in some operations)
3. Polling uses 2-second interval (not realtime)
4. OCR is on-device only (no cloud OCR fallback)

