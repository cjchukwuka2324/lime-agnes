# ✨ New Thread Feature - Start Fresh Conversations

## 🎯 What Was Added

A "New Thread" button that allows users to start a fresh conversation with Recall, showing the recall orb animation during the transition.

---

## 📝 Changes Made

### **1. RecallHomeView.swift** (UI)
Added a **green plus button** (`+`) in the navigation bar that:
- ✅ Appears only when there are messages in the current thread
- ✅ Shows in the top-right corner (next to the bookmark button)
- ✅ Uses Spotify green (#1ED760) to match the Recall theme
- ✅ Triggers `startNewSession()` when tapped

**Location:** Top navigation bar, trailing edge

### **2. RecallViewModel.swift** (Logic)
Enhanced the `startNewSession()` function to:
- ✅ Show the **thinking orb animation** during transition (0.5 seconds)
- ✅ Terminate the current session cleanly
- ✅ Clear all messages
- ✅ Create a brand new thread
- ✅ Speak a **welcome message** with voice output
- ✅ Set conversation mode to properly track state

---

## 🎬 User Experience Flow

### **Before (Without New Thread Button)**
```
User has conversation with Recall
→ Conversation continues in same thread
→ No easy way to start fresh
→ User has to restart app or manually clear
```

### **After (With New Thread Button)**
```
User has conversation with Recall
→ Taps green + button in top right
→ Orb shows thinking animation (0.5s)
→ Messages clear
→ Recall says: "Hi! I'm Recall..."
→ Fresh conversation ready!
```

---

## 🎨 Visual Design

### **Button Appearance:**
```
┌─────────────────────────┐
│  Recall        [+] [📖] │  ← Green + appears when messages exist
├─────────────────────────┤
│                         │
│         🌐 Orb         │  ← Shows animation
│                         │
└─────────────────────────┘
```

### **Button States:**
- **Hidden** - No messages in thread (clean slate)
- **Visible** - Messages exist, show green + button
- **Active** - Button tapped, orb animates

---

## 🎤 Welcome Message

When starting a new session, Recall speaks:

> "Hi! I'm Recall. I can help you find songs, answer music questions, or recommend music based on your mood. What would you like to know?"

This sets expectations for users about what Recall can do.

---

## 🔄 Animation Sequence

1. **User taps + button**
2. **Orb → Thinking state** (pulsing animation)
3. **Messages clear** (fade out)
4. **Brief pause** (0.5 seconds for visual feedback)
5. **Thread created** (backend)
6. **Orb → Idle state** (ready for input)
7. **Welcome message plays** (voice output)
8. **Orb → Speaking state** (while speaking)
9. **Orb → Idle state** (ready for next query)

---

## 🧪 Testing Checklist

- [ ] Button appears when messages exist
- [ ] Button hidden when no messages
- [ ] Tapping button clears messages
- [ ] Orb shows thinking animation
- [ ] New thread is created
- [ ] Welcome message plays with voice
- [ ] Can start new conversation after
- [ ] Previous thread is preserved in database

---

## 💡 Why This Feature?

### **User Benefits:**
1. **Fresh Start** - Clear context when switching topics
2. **Organized** - Keep different music searches separate
3. **Intuitive** - Familiar "+" pattern for "new"
4. **Feedback** - Visual animation confirms action
5. **Guided** - Welcome message reminds capabilities

### **Technical Benefits:**
1. **Clean State** - No conversation context pollution
2. **Performance** - Fresh thread = faster queries
3. **History** - Old threads preserved for stash feature
4. **Debugging** - Easier to track separate sessions

---

## 🎯 Use Cases

### **Scenario 1: Topic Switch**
```
User: "Tell me about The Beatles"
Recall: [Answers about The Beatles]
User: Taps + button
Recall: "Hi! I'm Recall..."
User: "Who wrote Bohemian Rhapsody?"
Recall: [Fresh context, new search]
```

### **Scenario 2: After Song Identification**
```
User: *hums melody*
Recall: "That's Hey Jude by The Beatles"
User: Confirms and taps + button
Recall: "Hi! I'm Recall..."
User: Ready for next search
```

### **Scenario 3: Multiple Searches**
```
User: Searches for multiple songs
Thread gets long
User: Taps + button
Recall: Fresh start
User: Continues with new searches
```

---

## 🔧 Technical Implementation

### **Button Code:**
```swift
if !viewModel.messages.isEmpty {
    Button {
        Task {
            await viewModel.startNewSession()
        }
    } label: {
        Image(systemName: "plus.circle.fill")
            .foregroundColor(Color(hex: "#1ED760"))
            .font(.system(size: 20))
    }
}
```

### **Session Logic:**
```swift
func startNewSession() async {
    terminateSession()              // Clean up current session
    orbState = .thinking            // Show animation
    currentThreadId = nil           // Clear thread
    messages = []                   // Clear messages
    try? await Task.sleep(...)      // Brief pause
    await startNewThreadIfNeeded()  // Create new thread
    orbState = .idle                // Ready
    voiceResponseService.speak(...)  // Welcome
}
```

---

## 📱 Integration Points

### **Works With:**
- ✅ Voice recording (can start fresh after voice session)
- ✅ Text queries (can start fresh after text)
- ✅ Song identification (clear after finding song)
- ✅ Stash feature (old thread preserved)
- ✅ Conversation mode (properly tracks states)
- ✅ Cancel/Stop button (works alongside)

### **Doesn't Interfere With:**
- ✅ Active recording (button only shows after messages)
- ✅ Processing (can cancel first if needed)
- ✅ Stashed threads (old data preserved)

---

## 🎨 Design Rationale

### **Why Green + Icon?**
- Green (#1ED760) - Matches Spotify and Recall brand
- Plus (+) - Universal symbol for "new"
- Circle fill - Matches orb aesthetic
- Size 20 - Consistent with other toolbar icons

### **Why Top Right?**
- Natural location for "new" actions
- Doesn't interfere with cancel (left side)
- Next to bookmark (related functionality)
- Easy thumb reach on mobile

### **Why Only Show With Messages?**
- Reduces clutter when not needed
- Clear indication: "This thread has content"
- Prevents accidental taps on empty state

---

## 🚀 Future Enhancements (Optional)

1. **Thread History** - View past conversations
2. **Thread Names** - Auto-name based on first query
3. **Swipe Gesture** - Swipe left on orb to start new
4. **Confirmation** - Ask "Start new conversation?" for long threads
5. **Quick Actions** - Long press for additional options

---

## ✅ Success Metrics

**Feature is successful if:**
- Users can easily start new conversations
- Orb animation provides clear feedback
- No confusion about button purpose
- Welcome message sets proper expectations
- Old threads are preserved properly

---

**Implementation Date:** December 17, 2025  
**Files Modified:** 2  
**Lines Changed:** ~30  
**Status:** ✅ Complete and Ready to Test

---

## 🎉 How to Use

1. **Have a conversation** with Recall
2. **Look for green + button** in top right
3. **Tap the + button**
4. **Watch the orb animation**
5. **Listen to welcome message**
6. **Start fresh conversation!**

Simple, intuitive, and delightful! 🎸


