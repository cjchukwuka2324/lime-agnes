# Recall Feature Documentation

## Overview

Recall is a voice-first AI music assistant that helps users identify songs, get music recommendations, and answer music-related questions through natural conversation. The feature supports multi-thread conversations, live transcription, editable voice input, and full chat history.

## Architecture

### Current Architecture (As-Is)

```
┌─────────────────────────────────────────────────────────┐
│                    RecallHomeView                       │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
│  │ RecallOrbView │  │ Messages     │  │ ComposerBar  │ │
│  │               │  │ ScrollView   │  │              │ │
│  └──────────────┘  └──────────────┘  └──────────────┘ │
└─────────────────────────────────────────────────────────┘
                        │
                        ▼
              ┌──────────────────┐
              │ RecallViewModel   │
              └──────────────────┘
                        │
        ┌───────────────┼───────────────┐
        ▼               ▼               ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│ VoiceRecorder │ │ StateMachine │ │ RecallService │
└──────────────┘ └──────────────┘ └──────────────┘
                                              │
                                              ▼
                                    ┌──────────────────┐
                                    │ Supabase Backend │
                                    │ recall-resolve   │
                                    └──────────────────┘
```

### Enhanced Architecture (To-Be)

```
┌─────────────────────────────────────────────────────────┐
│              RecallHomeView (Orb View)                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
│  │ RecallOrbView │  │ Messages     │  │ LiveTranscript│ │
│  │               │  │ (Infinite    │  │ Transcript    │ │
│  │               │  │  Scroll)     │  │ Composer      │ │
│  └──────────────┘  └──────────────┘  └──────────────┘ │
└─────────────────────────────────────────────────────────┘
                        │
                        ▼
              ┌──────────────────┐
              │ RecallViewModel   │
              └──────────────────┘
                        │
        ┌───────────────┼───────────────┐
        ▼               ▼               ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│ VoiceRecorder │ │ StateMachine │ │ RecallService │
│ AudioSession  │ │ (Gate Cond.) │ │ RecallAI     │
│ SpeechTrans   │ │              │ │ ThreadStore  │
└──────────────┘ └──────────────┘ └──────────────┘
                                              │
                                              ▼
                                    ┌──────────────────┐
                                    │ Supabase Backend │
                                    │ recall-resolve   │
                                    │ (GPT-4o Intent)  │
                                    └──────────────────┘
```

## Data Flow

### Voice Input Flow

1. User long-presses orb → `RecallStateMachine` checks gate conditions
2. If allowed → `VoiceRecorder` starts recording
3. `SpeechTranscriber` (future) provides live transcription
4. User releases → Recording stops
5. `RecallTranscriptComposer` appears with raw transcript
6. User can edit → `TranscriptDraftStore` manages state
7. User sends → `RecallService.insertMessage()` with raw + edited transcripts
8. `RecallService.resolveRecall()` → Backend edge function
9. Backend returns response → `RecallViewModel.handleVoiceResponse()`
10. Assistant message inserted → TTS plays → Live captions shown

### Thread Management Flow

1. User opens Recall tab → `RecallHomeView` (orb view) shown
2. User taps "Stashed Threads" → `RecallStashedThreadsView` shown
3. `RecallThreadStore.fetchStashedThreads()` → Loads threads with messages
4. User taps thread → `RecallViewModel.openThread()` → Loads messages
5. Messages displayed with infinite scroll → `loadOlderMessages()` on scroll to top

## State Machine

### States

- `.idle` - Default state, orb visible
- `.armed` - Long press detected, ready to listen
- `.listening` - Recording audio
- `.processing` - Sending to backend
- `.responding` - Assistant speaking
- `.error` - Error occurred

### Gate Conditions

Listening can only start when:
- Not currently scrolling (`!isScrolling`)
- Has microphone permission (`hasAudioPermission`)
- Audio session ready (`isAudioSessionReady`)
- Not already listening/processing
- Long press began on orb (`longPressBeganOnOrb`)

## Database Schema

### recall_threads

```sql
CREATE TABLE recall_threads (
  id UUID PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  last_message_at TIMESTAMPTZ DEFAULT NOW(),
  title TEXT,
  pinned BOOLEAN DEFAULT FALSE,
  archived BOOLEAN DEFAULT FALSE,
  deleted_at TIMESTAMPTZ,
  summary TEXT
);
```

### recall_messages

```sql
CREATE TABLE recall_messages (
  id UUID PRIMARY KEY,
  thread_id UUID REFERENCES recall_threads(id),
  user_id UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  role TEXT CHECK (role IN ('user', 'assistant', 'system')),
  message_type TEXT CHECK (message_type IN ('text', 'voice', 'image', 'candidate', 'status', 'follow_up', 'answer')),
  text TEXT,
  raw_transcript TEXT,
  edited_transcript TEXT,
  media_path TEXT,
  status TEXT CHECK (status IN ('sending', 'sent', 'failed')) DEFAULT 'sent',
  response_text TEXT,
  candidate_json JSONB DEFAULT '{}',
  sources_json JSONB DEFAULT '[]',
  confidence NUMERIC,
  song_url TEXT,
  song_title TEXT,
  song_artist TEXT
);
```

## GPT Response Schema

The backend `recall-resolve` edge function returns:

```typescript
{
  status: "done" | "refining" | "failed",
  response_type: "search" | "answer" | "both",
  transcription: string | null,
  title_suggestion: string | null, // For thread title generation
  assistant_message: {
    message_type: "candidate",
    song_title: string,
    song_artist: string,
    confidence: number,
    reason: string,
    lyric_snippet?: string,
    sources: Array<{title: string, url: string, snippet?: string}>,
    song_url?: string
  },
  candidates: Array<{
    title: string,
    artist: string,
    confidence: number,
    reason: string,
    background?: string,
    lyric_snippet?: string,
    source_urls: string[]
  }>,
  answer: {
    text: string,
    sources: string[],
    related_songs?: Array<{title: string, artist: string}>
  } | null,
  follow_up_question: string | null,
  conversation_state: string
}
```

## Permissions

### Required Info.plist Keys

```xml
<key>NSMicrophoneUsageDescription</key>
<string>RockOut needs access to your microphone to record voice queries for Recall, our AI music assistant. Your audio is processed on-device for transcription and sent to our servers only when you submit a query.</string>

<key>NSSpeechRecognitionUsageDescription</key>
<string>RockOut uses speech recognition to provide live transcription of your voice queries in Recall. This allows you to see and edit what you said before sending your query. All transcription happens on your device for privacy.</string>
```

## Privacy

1. **No Continuous Recording**: Audio only recorded during explicit long-press gesture
2. **On-Device Transcription**: `SFSpeechRecognizer` processes audio locally (when implemented)
3. **Audio Storage**: Opt-in only, audio files deleted after processing
4. **Wake Word**: Siri Shortcut integration (no always-listening background service)
5. **Transcript Storage**: Raw and edited transcripts stored in database for conversation history

## Accessibility

### VoiceOver Support

- All interactive elements have `accessibilityLabel` and `accessibilityHint`
- Thread list rows are accessible
- Message bubbles announce role and content
- Live transcript area is accessible
- Orb states are announced

### Dynamic Type

- All text uses semantic fonts (`.body`, `.headline`, `.caption`)
- Transcript composer supports Dynamic Type
- Message bubbles scale with text size

### Haptics

- State transitions provide haptic feedback:
  - `.idle` → `.armed`: Light impact
  - `.armed` → `.listening`: Medium impact
  - `.listening` → `.processing`: Light impact
  - `.processing` → `.responding`: Success notification

### Visible States

- "Listening" indicator always visible when mic is hot
- "Speaking" indicator always visible when TTS is playing
- High contrast support for mic/speaking states

## Testing Strategy

### Unit Tests

- `RecallStateMachineTests`: Test state transitions, gate conditions, scroll blocking
- `TranscriptDraftStoreTests`: Test transcript merge (append without overwrite), edited transcript override
- `RecallThreadStoreTests`: Test thread CRUD operations, soft delete, pin/archive

### Integration Tests

- Thread creation → message → title generation flow
- Infinite scroll pagination
- Draft → send → persist flow
- Voice recording → transcription → editing → send flow

### Error Handling

- Permissions denied (microphone, speech recognition)
- Network failures
- Audio interruptions
- Backend errors

## Performance Considerations

### Concurrency

- `RequestCoalescer` for request deduplication
- `RetryPolicy` for transient failures
- `ProfileCache` for user profiles

### Scalability

- Pagination for messages (50 per page)
- Thread summary generation every ~12 messages
- Database indices on frequently queried fields
- Image caching with `CachedAsyncImage`

## Future Enhancements

1. **On-Device Speech Recognition**: Full `SFSpeechRecognizer` integration for live transcription
2. **Intent Routing**: Structured GPT responses with explicit intent classification
3. **Thread Search**: Full-text search across thread messages
4. **Export Conversations**: Share or export thread history
5. **Multi-Language Support**: Transcription and responses in multiple languages






