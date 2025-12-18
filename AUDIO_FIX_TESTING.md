# 🎯 Audio Fix Testing Checklist

## 🔧 What Was Fixed

Fixed audio session conflicts that prevented Recall from speaking responses. The issue occurred when transitioning from recording (voice input) to playback (TTS output).

## ✅ Pre-Testing Setup

1. **Rebuild the app** in Xcode
2. **Test on a physical iPhone** (not simulator)
3. **Enable microphone permissions** if prompted
4. **Have a quiet environment** for voice testing

## 🧪 Test Cases

### Test 1: Simple Conversational Query ✅
**Expected**: Recall should understand and respond with voice

1. Open Recall
2. Long press the orb
3. Say: **"What is the weather like?"**
4. Release the orb
5. **Expected Result**: 
   - ✅ Orb transitions to thinking state
   - ✅ You hear a voice response about weather
   - ✅ No audio buffer errors in logs

**Watch for**:
```
✅ Audio session deactivated after recording
✅ Audio session transition delay complete
✅ Audio session configured for TTS playback
🗣️ Speaking: [response about weather]
✅ TTS finished speaking
```

---

### Test 2: Song Recognition Query ✅
**Expected**: Recall should identify a song and speak the result

1. Long press the orb
2. Say: **"What song goes like 'never gonna give you up'?"**
3. Release the orb
4. **Expected Result**:
   - ✅ You hear: "I found Never Gonna Give You Up by Rick Astley."
   - ✅ Orb shows green success state
   - ✅ Song card appears in UI

---

### Test 3: Incomplete Query with Follow-up ✅
**Expected**: Recall should ask a clarifying question with voice

1. Long press the orb
2. Say: **"You"** (just that single word)
3. Release the orb
4. **Expected Result**:
   - ✅ You hear a follow-up question like: "Do you remember any specific lyrics or the melody?"
   - ✅ Orb stays in idle state, waiting for your response

5. Respond to follow-up:
   - Long press again
   - Say: **"It has drums and guitar"**
   - Release
6. **Expected Result**:
   - ✅ You hear another response or get song results

---

### Test 4: Humming Recognition 🎵
**Expected**: Recall should recognize hummed melodies

1. Long press the orb
2. **Hum a recognizable tune** (e.g., Happy Birthday)
3. Release the orb
4. **Expected Result**:
   - ✅ ACRCloud/Shazam attempts recognition
   - ✅ You hear either:
     - Song identification if recognized
     - Follow-up question if not clear

---

### Test 5: New Thread Animation ✨
**Expected**: New thread shows animation and speaks welcome

1. Have an existing conversation (send a few queries)
2. Tap the **green "+" button** in top-right
3. **Expected Result**:
   - ✅ Orb animates to "thinking" state
   - ✅ Messages clear from screen
   - ✅ You hear: "Hi! I'm Recall. I can help you find songs..."
   - ✅ Orb returns to idle state
   - ✅ Ready for new conversation

---

### Test 6: Multiple Back-to-Back Queries ⚡
**Expected**: Audio session handles rapid transitions

1. Long press → say "Tell me about jazz" → release
2. Wait for response
3. Immediately long press → say "Now tell me about rock" → release
4. **Expected Result**:
   - ✅ Both responses are spoken clearly
   - ✅ No audio overlap or cutting off
   - ✅ Smooth transitions between recording and playback

---

## 🐛 What to Watch For

### ✅ Good Signs:
- Clear voice responses for all queries
- No silent responses (text appears but no voice)
- Smooth orb animations
- Clean logs without buffer errors

### ❌ Bad Signs (Report These):
- TTS plays but no sound
- Audio buffer errors: `mBuffers[0].mDataByteSize (0)`
- Swift concurrency warnings
- Responses appear as text but don't speak
- App crashes when speaking

---

## 📊 Debug Logs to Check

When testing, look for these logs in Xcode console:

### ✅ Successful Flow:
```
🛑 Stopping recording...
✅ Audio session deactivated after recording
📁 Recording saved to: voice_1734457200.m4a
✅ Audio session transition delay complete
🔍 Calling resolveRecall...
✅ [RECALL-SERVICE] resolveRecall completed in 3.5s
✅ Audio session configured for TTS playback
🗣️ Speaking: I found Never Gonna Give You Up by Rick Astley.
✅ TTS finished speaking
✅ Audio session deactivated after TTS
```

### ❌ Problematic Flow (Old Issue):
```
❌ Failed to configure audio session for TTS: Error...
AVAudioBuffer.mm:281 mBuffers[0].mDataByteSize (0) should be non-zero
Task <XXX> finished with error [-1004]
```

---

## 🚀 Final Verification

After all tests pass:

1. ✅ Voice responses work for conversational queries
2. ✅ Voice responses work for song identification
3. ✅ Follow-up questions are spoken aloud
4. ✅ New thread feature speaks welcome message
5. ✅ Multiple queries in a row work smoothly
6. ✅ No audio buffer errors in logs
7. ✅ No Swift concurrency warnings

---

## 📝 Report Results

If you encounter issues, share:
1. Which test case failed
2. What you said to Recall
3. What happened (or didn't happen)
4. Any error logs from Xcode console
5. iOS version and device model

---

**Testing Date**: __________  
**Tester**: __________  
**Device**: __________  
**iOS Version**: __________  

**Overall Status**: ⬜ Pass | ⬜ Fail | ⬜ Partial

**Notes**:
```
[Your notes here]
```


