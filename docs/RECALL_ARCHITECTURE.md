# Recall Voice-First Assistant Architecture

## Overview

Recall is a voice-first, multimodal AI music assistant that allows users to find songs using voice, text, or images. This document describes the current architecture after the voice-first uplift implementation.

## Architecture Overview (Post-Uplift)

### Component Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    RecallHomeView                          │
│  ┌─────────────────────────────────────────────────────┐  │
│  │              RecallOrbView (Center)                 │  │
│  │  - Long-press gesture (3s) to trigger recording      │  │
│  │  - States: idle, listening, thinking, done, error   │  │
│  └─────────────────────────────────────────────────────┘  │
│  ┌─────────────────────────────────────────────────────┐  │
│  │         Messages ScrollView (Chat UI)               │  │
│  │  - RecallMessageBubble components                   │  │
│  │  - User/Assistant message threads                   │  │
│  └─────────────────────────────────────────────────────┘  │
│  ┌─────────────────────────────────────────────────────┐  │
│  │         RecallComposerBar (Bottom)                  │  │
│  │  - Text input, image picker, send button           │  │
│  └─────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│                  RecallViewModel                             │
│  - @Published orbState: RecallOrbState                     │
│  - @Published conversationMode: ConversationMode         │
│  - @Published messages: [RecallMessage]                    │
│  - @Published pendingTranscript: (text, type, id)?        │
│  - voiceRecorder: VoiceRecorder                            │
│  - voiceResponseService: VoiceResponseService               │
└─────────────────────────────────────────────────────────────┘
                        │
        ┌───────────────┼───────────────┐
        ▼               ▼               ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│VoiceRecorder │ │RecallService │ │VoiceResponse│
│              │ │              │ │Service      │
│- AVAudioRec  │ │- Supabase    │ │- AVSpeechSyn │
│- Records to  │ │- Edge funcs  │ │- TTS with    │
│  file        │ │- Thread mgmt │ │  live trans  │
│- No live     │ │- Message ops │ │              │
│  transcript  │ │              │ │              │
└──────────────┘ └──────────────┘ └──────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│              Supabase Backend                                │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Tables:                                            │    │
│  │  - recall_threads (conversation threads)             │    │
│  │  - recall_messages (user/assistant messages)         │    │
│  │  - recall_stash (saved songs)                        │    │
│  └─────────────────────────────────────────────────────┘    │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Edge Functions:                                     │    │
│  │  - recall-resolve (transcription, AI, recognition)  │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

### Current Data Flow

#### Voice Recording Flow (Current)
```
User long-presses orb (3s)
    ↓
RecallViewModel.orbLongPressed()
    ↓
VoiceRecorder.startRecording()
    ↓
AVAudioRecorder records to file
    ↓
User releases → VoiceRecorder.stopRecording()
    ↓
Upload audio file to Supabase Storage
    ↓
Insert message with media_path
    ↓
Call recall-resolve edge function
    ↓
Edge function transcribes with Whisper (server-side)
    ↓
Edge function processes (intent, recognition, GPT)
    ↓
Update message with transcription
    ↓
Display response in UI
```

#### Current Limitations
1. **No live transcription**: Transcription happens server-side after upload
2. **No editable transcripts**: Server-generated, not user-editable
3. **No scroll protection**: Long-press gesture can conflict with scrolling
4. **No wake word**: Only long-press trigger
5. **No state machine**: State management is ad-hoc in ViewModel

## Planned Architecture (To-Be)

### State Machine Design

```
┌─────────────────────────────────────────────────────────────┐
│              RecallStateMachine                             │
│                                                             │
│  States:                                                    │
│  ┌────────┐  ┌────────┐  ┌──────────┐  ┌──────────┐      │
│  │  Idle  │→ │ Armed  │→ │Listening │→ │Processing│      │
│  └────────┘  └────────┘  └──────────┘  └──────────┘      │
│     ↑                              ↓                       │
│     └──────────────────────────────┘                       │
│                          │                                  │
│                          ▼                                  │
│                   ┌─────────────┐                           │
│                   │ Responding  │                           │
│                   └─────────────┘                           │
│                                                             │
│  Gate Conditions (must ALL pass to enter Listening):       │
│  ✓ Not currently scrolling                                 │
│  ✓ Audio permissions granted                               │
│  ✓ Audio session ready                                     │
│  ✓ Not already in Listening/Processing                    │
│  ✓ Long-press began on orb (not random tap)               │
└─────────────────────────────────────────────────────────────┘
```

### Enhanced Audio Pipeline

```
┌─────────────────────────────────────────────────────────────┐
│              AudioSessionManager                             │
│  - Centralized AVAudioSession management                    │
│  - Handles interruptions, route changes                    │
│  - Permission requests                                      │
│  - @Published isReady: Bool                                 │
└─────────────────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│              VoiceRecorder + SpeechTranscriber               │
│                                                             │
│  VoiceRecorder:                                             │
│  - AVAudioRecorder (records to file)                       │
│  - Silence detection (auto-stop after 2.5s)                │
│  - Meter level updates                                      │
│                                                             │
│  SpeechTranscriber:                                         │
│  - SFSpeechRecognizer                                       │
│  - SFSpeechAudioBufferRecognitionRequest                    │
│  - Streams partial results (live transcript)               │
│  - Provides final transcript                                │
│  - @Published partialTranscript: String                    │
│  - @Published finalTranscript: String?                      │
└─────────────────────────────────────────────────────────────┘
```

### Enhanced UI Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    RecallHomeView                           │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Scroll Detection (PreferenceKey)                   │   │
│  │  - Tracks scroll velocity                            │   │
│  │  - Updates isScrolling in ViewModel                  │   │
│  │  - Blocks long-press when scrolling                  │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  RecallOrbView (Enhanced)                            │   │
│  │  - States: idle, armed, listening, responding        │   │
│  │  - Haptic feedback on state changes                  │   │
│  │  - Waveform visualization during listening           │   │
│  │  - VoiceOver labels and accessibility                │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Live Transcript Area                                │   │
│  │  - Shows partialTranscript during recording          │   │
│  │  - Grows/scrolls predictably                          │   │
│  │  - VoiceOver-friendly                                │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  RecallTranscriptComposer (After Recording)         │   │
│  │  - Editable TextField with transcript                │   │
│  │  - Actions: Edit, Retry, Append, Send                │   │
│  │  - Preserves rawTranscript and editedTranscript      │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Messages ScrollView                                 │   │
│  │  - Locked during listening state                     │   │
│  │  - Shows confirmed messages                          │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  RecallComposerBar                                   │   │
│  │  - Text input (always available)                     │   │
│  │  - Image picker                                      │   │
│  │  - "Append to voice" mode                            │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

#### Voice Recording Flow (Enhanced - Implemented)
```
User long-presses orb
    ↓
State Machine: idle → armed (gate checks)
    ↓
Gate conditions checked:
  - Not scrolling ✓
  - Permissions granted ✓
  - Audio session ready ✓
  - Not already listening ✓
  - Long-press on orb ✓
    ↓
State Machine: armed → listening
    ↓
AudioSessionManager.configureForRecording()
    ↓
VoiceRecorder.startRecording() + SpeechTranscriber.start()
    ↓
┌─────────────────────────────────────┐
│  Parallel Processing:                │
│  - AVAudioRecorder records to file  │
│  - SFSpeechRecognizer streams       │
│    partial results                  │
│  - Live transcript updates UI       │
└─────────────────────────────────────┘
    ↓
User releases OR silence detected (2.5s)
    ↓
SpeechTranscriber.finalTranscript received
    ↓
Show RecallTranscriptComposer with editable field
    ↓
User edits (optional) → editedTranscript
    ↓
User taps Send
    ↓
Build RecallRequestContext:
  - rawTranscript
  - editedTranscript (if edited)
  - typedText (if any)
  - attachedImages (if any)
    ↓
Upload audio file (if user opted in)
    ↓
Call recall-resolve with context
    ↓
Display response with live captions
```

## Component Responsibilities

### RecallStateMachine
- **Purpose**: Centralized state management with gate conditions
- **Responsibilities**:
  - Manage state transitions (idle → armed → listening → processing → responding)
  - Enforce gate conditions before entering listening state
  - Handle events (longPressBegan, scrollStarted, etc.)
  - Prevent invalid state transitions
- **Dependencies**: AudioSessionManager, ScrollDetector

### AudioSessionManager
- **Purpose**: Centralized audio session management
- **Responsibilities**:
  - Configure AVAudioSession for recording/playback
  - Handle interruptions (phone calls, other audio)
  - Handle route changes (AirPods, Bluetooth)
  - Request permissions (microphone, speech recognition)
  - Provide `isReady` state for gate checks
- **Dependencies**: None (uses AVFoundation)

### SpeechTranscriber
- **Purpose**: Live on-device speech recognition
- **Responsibilities**:
  - Wrap SFSpeechRecognizer and SFSpeechAudioBufferRecognitionRequest
  - Stream partial results during recording
  - Provide final transcript
  - Handle errors and permission fallbacks
- **Dependencies**: AudioSessionManager, VoiceRecorder (for audio buffer)

### VoiceRecorder
- **Purpose**: Audio recording to file
- **Responsibilities**:
  - Record audio using AVAudioRecorder
  - Provide meter level for visualization
  - Detect silence (auto-stop after 2.5s)
  - Integrate with SpeechTranscriber for live transcription
- **Dependencies**: AudioSessionManager

### RecallViewModel
- **Purpose**: UI state management and coordination
- **Responsibilities**:
  - Coordinate between state machine, recorder, transcriber, service
  - Manage UI state (messages, transcript composer, etc.)
  - Handle user interactions (long-press, send, edit, etc.)
  - Build RecallRequestContext for backend calls
- **Dependencies**: RecallStateMachine, VoiceRecorder, SpeechTranscriber, RecallService

### RecallService
- **Purpose**: Backend communication
- **Responsibilities**:
  - Upload media files
  - Call edge functions (recall-resolve)
  - Manage threads and messages
  - Handle cancellations
- **Dependencies**: Supabase client

## Database Schema

### Current Schema
- `recall_threads`: Conversation threads
- `recall_messages`: Messages with `text`, `media_path`, `candidate_json`, etc.
- `recall_stash`: Saved songs

### Schema Changes (Implemented)
- `raw_transcript TEXT` column added to `recall_messages` table
- Stores both `raw_transcript` (from SFSpeechRecognizer) and `text` (edited or final)
- Migration script preserves existing data

## Accessibility Guidelines

### VoiceOver
- All controls must have `.accessibilityLabel()` and `.accessibilityHint()`
- State changes must be announced (e.g., "Listening", "Recording stopped")
- Transcript area must be accessible with proper labels

### Dynamic Type
- Use semantic fonts (`.body`, `.headline`) not fixed sizes
- Transcripts must scale with user's text size preference
- Test with largest accessibility text size

### Haptics
- Armed: Light impact
- Start recording: Success notification
- Stop recording: Medium impact
- Response received: Success notification

### Visible States
- Mic state must always be visible when hot
- "Listening" indicator must be prominent
- State changes must be visually clear

## Testing Strategy

### Unit Tests
- **RecallStateMachineTests**: Test all state transitions, gate conditions, error handling
- **RecallTranscriptTests**: Test transcript editing, merge logic, precedence rules

### Integration Tests
- **RecallIntegrationTests**: Test long-press triggers, scroll blocking, transcript flow, Siri Shortcut

### Error Handling Tests
- Microphone permission denied
- Speech permission denied
- Audio interruption (phone call)
- Network failure
- Transcription failure

## Security & Privacy

### Audio Storage
- Audio files only stored if user explicitly opts in
- Audio files stored in user-specific paths with RLS policies
- Audio files can be deleted after processing (configurable)

### Wake Word
- "Hey Recall" via Siri Shortcut (handled by iOS, no audio sent to server)
- No continuous recording for wake word detection
- Privacy-first approach

### Transcription
- Live transcription happens on-device (SFSpeechRecognizer)
- Final transcript sent to server for processing
- User can edit transcript before sending

## Performance Considerations

### Concurrency
- All audio operations on MainActor
- State machine updates on MainActor
- Backend calls are async and cancellable
- UI updates are debounced where appropriate

### Scalability
- Client-side is resilient (handles 10k users overall)
- Backend calls are debounced and cancellable
- UI is state-driven (no polling)
- Efficient state management (no unnecessary re-renders)

## Future Enhancements

1. **On-device wake word** (if Apple APIs become available)
2. **Streaming responses** from backend
3. **Multi-language support** for transcription
4. **Offline mode** with local transcription cache
5. **Voice commands** for navigation and actions

