# Recall V2 Testing Guide

## 🧪 Quick Testing Checklist

Use these test cases to verify the new intelligent voice processing is working correctly.

---

## ✅ Test Cases

### **1. Conversational Questions** (Should NOT use audio recognition)

Test these voice inputs - they should go directly to GPT without audio recognition:

```
✓ "Tell me about The Beatles"
✓ "Who wrote Bohemian Rhapsody?"
✓ "What's your favorite music genre?"
✓ "When was this album released?"
✓ "How did this artist become famous?"
✓ "What song is playing?" (yes, even this!)
```

**Expected Behavior:**
- Status: "Listening..." → "Understanding..." → "Thinking..."
- No audio recognition APIs called
- Fast response (~5 seconds)
- Natural conversational answer from GPT

**Check Logs For:**
```
🧠 Analyzing intent for: "[transcription]"
🎯 Intent: conversation (0.9+ confidence)
💬 Intent: conversation → Using conversational response
```

---

### **2. Humming Detection** (Should use audio recognition)

Test these by humming or singing:

```
✓ Hum a melody (la la la)
✓ Sing da da da
✓ Make hmm hmm sounds
✓ Vocalize a tune without words
```

**Expected Behavior:**
- Status: "Listening..." → "Understanding..." → "Identifying song..."
- ACRCloud + Shazam called in parallel
- Conversational result: "Great! I identified that from your humming..."
- Response time: ~8 seconds

**Check Logs For:**
```
🧠 Analyzing intent for: "hmm hmm da da da"
🎯 Intent: humming (0.9+ confidence)
🎵 Intent: humming → Using audio recognition
🔍 [STEP 3] Running audio recognition (ACRCloud + Shazam in parallel)...
✅ ACRCloud: [Song Title] by [Artist] (0.85)
✅ High confidence: [Song Title] by [Artist] (0.85)
```

---

### **3. Background Music** (Should use audio recognition)

Test by playing music from another device:

```
✓ Play a popular song on Spotify
✓ Play music from YouTube
✓ TV show theme song playing
✓ Radio in the background
```

**Expected Behavior:**
- Status: "Listening..." → "Understanding..." → "Identifying song..."
- Transcription shows [music] or garbled text
- Shazam likely matches (better for full songs)
- Response: "Great! I identified that song..."
- Response time: ~7 seconds

**Check Logs For:**
```
🧠 Analyzing intent for: "[music] [inaudible]"
🎯 Intent: background_audio (0.9+ confidence)
🎵 Intent: background_audio → Using audio recognition
✅ Shazam: [Song Title] by [Artist] (0.93)
```

---

### **4. Unclear Cases** (Should use heuristics)

Test edge cases:

```
✓ Very short phrases ("rock music")
✓ Mixed content (talking + humming)
✓ Unclear audio quality
✓ Background noise
```

**Expected Behavior:**
- Intent detection returns "unclear"
- Falls back to heuristics (word count, repetitive sounds)
- May try audio recognition OR treat as conversation
- GPT provides helpful response

**Check Logs For:**
```
🎯 Intent: unclear (0.5-0.7 confidence)
🤔 Unclear intent, but heuristics suggest [audio recognition/conversation]
```

---

## 📊 Performance Benchmarks

| Test Case | Expected Time | Status Updates |
|-----------|--------------|----------------|
| Conversation | ~5 sec | Listening → Understanding → Thinking |
| Humming | ~8 sec | Listening → Understanding → Identifying |
| Background Music | ~7 sec | Listening → Understanding → Identifying |
| Unclear | ~10 sec | Varies based on heuristics |

---

## 🔍 How to Monitor

### **1. Supabase Function Logs**
```bash
supabase functions logs recall-resolve --follow
```

Look for:
- `🧠 Analyzing intent for:` - Intent analysis started
- `🎯 Intent:` - Intent detected
- `💬` or `🎵` - Route chosen (conversation or audio recognition)
- `✅ High confidence:` - Successful match

### **2. App Status Messages**
Watch the UI status messages:
- "Listening..." - Recording
- "Understanding..." - Transcription complete
- "Thinking..." - Conversational response
- "Identifying song..." - Audio recognition

### **3. Response Quality**
- Conversational responses should be natural and context-aware
- Song identifications should include conversational wrappers
- Moderate confidence should ask for verification

---

## ❌ Troubleshooting

### **Problem: All queries use audio recognition**
**Fix:** Check if intent analysis is working:
1. Verify OpenAI API key is set
2. Check logs for intent analysis errors
3. Ensure GPT-4o-mini is accessible

### **Problem: Conversations are slow**
**Check:** Should be ~5 seconds
1. Verify Whisper transcription is fast (<3 sec)
2. Check GPT-4o-mini intent analysis (<1 sec)
3. Verify GPT-4o response is normal (<2 sec)

### **Problem: Humming not detected**
**Check Transcription:** Should show repetitive sounds
1. Look for "hmm", "la", "da" in transcription
2. Verify intent detection sees pattern
3. Check heuristics (word count < 5, repetitive > 3)

### **Problem: Background music not recognized**
**Check Services:**
1. Verify Shazam API key is set
2. Check ACRCloud credentials
3. Audio quality may be too low

---

## 🎯 Success Criteria

- [ ] Conversational queries bypass audio recognition
- [ ] Humming triggers audio recognition
- [ ] Background music triggers audio recognition
- [ ] Status messages are contextual
- [ ] Responses are conversational and natural
- [ ] Performance meets benchmarks
- [ ] Edge cases handled gracefully

---

## 📝 Test Log Template

Use this template to document your testing:

```
Date: _______
Tester: _______

Test Case: [Conversation/Humming/Background/Unclear]
Input: "[what you said/did]"
Transcription: "[what Whisper captured]"
Intent Detected: [conversation/humming/background_audio/unclear]
Confidence: [0.0-1.0]
Route Taken: [GPT only / Audio Recognition]
Response Time: [seconds]
Result: [Pass/Fail]
Notes: [any observations]
```

---

## 🚀 Quick Test Script

Run these in sequence:

1. **Conversation Test**
   - Say: "Tell me about The Beatles"
   - Expected: Direct GPT response, no audio recognition

2. **Humming Test**
   - Hum: "Happy Birthday" melody
   - Expected: Audio recognition → Song found

3. **Background Test**
   - Play: Any popular song
   - Expected: Shazam/ACRCloud → Song identified

4. **Edge Case Test**
   - Say: "mm mm rock music la la"
   - Expected: Heuristics kick in, intelligent routing

---

## 📞 Support

If you encounter issues:
1. Check Supabase function logs
2. Verify API keys are set correctly
3. Review the implementation documentation
4. Test with different audio quality

---

**Testing Version:** 2.0.0  
**Last Updated:** December 17, 2025















