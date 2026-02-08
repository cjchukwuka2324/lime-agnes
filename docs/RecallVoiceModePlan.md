# Recall Voice Mode Implementation Plan

> Uplift Recall to match ChatGPT mobile Voice Mode: tap-to-start (no long-press), VAD-based speech detection, auto end-of-utterance, live transcripts, waveform visualization, Mute/Exit controls (bottom-left/right), barge-in interruption, and production-ready orchestration—while preserving existing features.

---

## Step 0 — Discovery Summary

### Files Inventory

**Recall Core:**
- `Rockout/Views/Recall/RecallHomeView.swift` — Main entry, long-press gesture (1.5s min), Messages + Composer
- `Rockout/ViewModels/RecallViewModel.swift` — Orb state, messages, voice flow, GreenRoom handling
- `Rockout/Services/Recall/RecallStateMachine.swift` — States: idle, armed, listening, processing, responding, error; events: longPressBegan/Ended, scroll, silenceTimeout; **long-press gated**
- `Rockout/Services/Recall/VoiceRecorder.swift` — AVAudioRecorder, meter level, 2.5s silence auto-stop; **no streaming**
- `Rockout/Services/Recall/VoiceResponseService.swift` — AVSpeechSynthesizer, live currentSpokenText, stopSpeaking (cancelable)
- `Rockout/Services/Recall/TTSManager.swift` — Wraps VoiceResponseService, speak/stopSpeaking
- `Rockout/Services/Recall/AudioSessionManager.swift` — AVAudioSession, permissions, interruptions, route changes
- `Rockout/Services/Recall/RecallService.swift` — resolveRecall (edge function), insertMessage, uploadMedia, createThread, fetchMessages, askCrowd
- `Rockout/Services/Recall/RecallThreadStore.swift` — Thread CRUD, fetchStashedThreads
- `Rockout/Services/Recall/RecallActionsService.swift` — postToGreenRoom, share
- `Rockout/Models/Recall/RecallModels.swift` — RecallThread, RecallMessage, RecallOrbState, RecallCandidateData, RecallResolveResponse
- `Rockout/Views/Recall/RecallOrbView.swift` — Long-press gesture (3s), scale by state
- `Rockout/Views/Recall/RecallMessageBubble.swift` — User/assistant bubbles, transcript, pending transcript
- `Rockout/Views/Recall/RecallCandidateCard.swift` — Title, artist, confidence bar, reason, sources, "Ask GreenRoom", Open/Share/Confirm
- `Rockout/Views/Recall/RecallComposerBar.swift` — Text input, photo attach, send
- `Rockout/Views/Recall/RecallLiveTranscriptView.swift` — Displays live transcript
- `Rockout/Views/Recall/RecallTranscriptComposer.swift` — Edit raw transcript before send
- `Rockout/Views/Recall/GreenRoomPromptSheet.swift` — "Ask GreenRoom?" sheet, Post/Cancel
- `Rockout/Utils/Logger.swift` — Logger.recall, OSLog, Crashlytics

**Backend:**
- `supabase/functions/recall-resolve/index.ts` — Whisper transcription, analyzeVoiceIntent, ACRCloud + Shazam, GPT-4o, should_ask_crowd
- `supabase/functions/recall_ask_crowd/index.ts` — Creates GreenRoom post from recall
- `supabase/recall.sql` — recall_threads, recall_messages, recall_stash

**Tests:**
- `RockoutTests/RecallServiceTests.swift`, `RockoutTests/RecallViewModelTests.swift`

### Architecture Patterns
- MVVM with `@StateObject` ViewModels
- Combine for publishers
- async/await for service calls
- `@MainActor` on ViewModels and key services

### What Exists vs Missing

| Component | Exists | Notes |
|-----------|--------|-------|
| State machine | Yes | Long-press gated; needs tap-to-start + new states |
| Voice recording | Yes | AVAudioRecorder, file-based; no streaming |
| Live user transcript | No | SFSpeechRecognizer not implemented; transcription is server-side Whisper |
| TTS with live transcript | Yes | VoiceResponseService uses willSpeakRangeOfSpeechString |
| Barge-in | No | TTS can be stopped but no VAD during speak |
| VAD (end-of-utterance) | Partial | VoiceRecorder has 2.5s silence auto-stop; no pre-roll |
| Audio type classifier | No | Server infers from Whisper output |
| Song fingerprint | Server | ACRCloud + Shazam APIs in recall-resolve |
| Hum match | Server | ACRCloud in recall-resolve |
| Threads + persistence | Yes | recall_threads, recall_messages, RecallThreadStore |
| GreenRoom fallback | Yes | GreenRoomPromptSheet, RecallActionsService, recall_ask_crowd |
| ShazamKit (iOS) | No | Shazam via RapidAPI on server only |
| STT streaming | No | No SFSpeechRecognizer; upload then Whisper |
| playAndRecord audio session | Partial | VoiceRecorder uses .record; TTS uses .playback |

---

## ChatGPT Voice Mode Reference (Target UX)

Recall Voice Mode should match the ChatGPT mobile app experience:

| ChatGPT behavior | Recall implementation |
|------------------|------------------------|
| Tap voice icon (bottom-right) to start | Tap orb to start; no long-press |
| Fluid animation (blue orb / waveform on gradient) | Orb animates by state; waveform reacts to mic level |
| Auto end-of-speech — detects when user stops | VAD ~700–900ms silence after speech |
| Mute mic (bottom-left) — pause listening without ending | Mute button: stops listening, stays in session; tap again to resume |
| Exit (bottom-right) — end conversation | Exit/Stop button: end session, return to idle |
| Interrupt anytime — barge-in while assistant speaks | VAD detects speech during TTS → stop TTS, resume listening |
| Transcript visible | Live user transcript + assistant transcript (captions) |
| Waveform on blue gradient when listening | Waveform or pulse tied to mic amplitude |
| Tap voice again in same chat to continue | Tap orb to start new turn in same thread |

**Key controls:**
- **Mute** — Pause listening; unmute to resume
- **Exit** — End the voice session entirely
- **Tap orb** — Start listening or stop listening

---

## Core UX Requirements (Non-Negotiable)

**Long-press is removed.** The app must:

1. **Detect when the user is speaking** — Use VAD (Voice Activity Detection) to recognize speech start and end. No button hold required.
2. **Tap-to-start only** — User taps the orb once; Recall enters listening mode and stays there until the user stops speaking.
3. **Automatic end-of-utterance** — When the user pauses (e.g., 700–900ms of silence after speech), Recall automatically treats that as "user finished" and processes the request.
4. **No long-press gesture** — Remove the existing long-press gesture in RecallHomeView and RecallOrbView; replace with a simple tap.
5. **User can deactivate listening** (ChatGPT-style controls):
   - **Mute button** (bottom-left): Pause listening; tap again to unmute and resume. Session stays active.
   - **Exit button** (bottom-right): End voice session, return to idle. Discard in-progress capture.
   - **Tap orb again** (optional): While listening, tap orb to stop; no processing.

**Flow:** Tap orb → auto-listen → user speaks (VAD detects start) → user stops (VAD detects end) → process → respond.

---

## Proposed Architecture

### RecallVoiceOrchestrator

**States:** idle, listening, capturingUtterance, classifyingAudio, transcribing, thinking, speaking, interrupted, error

**Events:** userTappedStart, userTappedStop (exit/end session), userTappedMute / userTappedUnmute (pause/resume listening), vadSpeechStart, vadSpeechEnd, audioClassified(speech|music|hum|noise), sttPartial, sttFinal, llmResponseReady, ttsStarted, ttsFinished, bargeInDetected, errorOccurred, recovered

**Key change:** Tap once → enter listening; VAD detects when user is speaking (start/end); no long-press. Mute = pause listening; Exit = end session.

### VADService — "Tell When User Is Speaking"

The VADService replaces long-press. It continuously analyzes the audio stream and:

- **Detects speech start** — When energy/spectral features indicate the user began talking, emit `vadSpeechStart`.
- **Detects speech end** — When ~700–900ms of silence follows detected speech, emit `vadSpeechEnd`. Triggers processing (no user action needed).
- **Handles barge-in** — When Recall is speaking (TTS) and VAD detects new speech, emit `bargeInDetected` → stop TTS, resume listening.

Implementation: energy threshold + silence timer, or lightweight on-device model. Must run in real time on the mic stream.

---

## Implementation Phases

### Phase 1 — Foundations
- Add RecallVoiceOrchestrator with full state machine
- Add AudioIOManager (AVAudioSession, playAndRecord, buffer capture, level metering)
- Add VADService (speech start/end, pre-roll 300–500ms, barge-in)
- Remove long-press; replace with tap gesture (tap to start, tap again to deactivate)
- Unit tests for RecallVoiceOrchestrator

### Phase 2 — Speech Conversation (GPT-like)
- Add STTService with SFSpeechRecognizer streaming
- Integrate STT; emit sttPartial/sttFinal
- Barge-in: VAD during TTS → stop TTS, resume listening
- Wire RecallToolRouter to RecallService.resolveRecall

### Phase 3 — Music + Hum Detection
- Add AudioTypeClassifier (speech, music, hum, noise)
- Add RecallToolRouter (music/hum → audio recognition; speech → LLM)
- RecallCandidateCard: artwork, source label
- HumMatchService stub + UI fallback

### Phase 4 — Threads + Persistence
- Confirm recall_threads / recall_messages schema
- New Thread, End Session in RecallHomeView
- Thread list + resume with full history

### Phase 5 — Reliability + Polish
- Error handling: mic denied, network, STT, audio interruptions
- Unit tests: state machine, router
- Accessibility: VoiceOver, Dynamic Type, high contrast
- Logger.recall at key transitions

---

## UI Requirements (ChatGPT-Style Layout)

- **Orb / center**: Fluid animation; reacts to mic level (listening) or TTS level (speaking)
- **Waveform**: Waveform or pulse tied to mic amplitude when listening
- **Transcript area**: Live user transcript; assistant transcript/captions while responding
- **Mute button** (bottom-left): Mic icon; tap to mute, tap again to unmute
- **Exit button** (bottom-right): X or exit icon; end voice session
- **Optional**: 'cc' button (top-right) to toggle captions
- **Conversation list**: Scrollable chat thread above; tap orb again in same thread to continue

---

## File-Level Change Map

| File | Action |
|------|--------|
| `Rockout/Services/Recall/RecallVoiceOrchestrator.swift` | Create — Core state machine (tap + VAD; no long-press) |
| `Rockout/Services/Recall/RecallStateMachine.swift` | Modify — Replace long-press with tap + VAD |
| `Rockout/Services/Recall/AudioIOManager.swift` | Create — AVAudioSession + buffer capture + level metering |
| `Rockout/Services/Recall/VADService.swift` | Create — Speech start/end; pre-roll; end-of-utterance; barge-in |
| `Rockout/Services/Recall/STTService.swift` | Create — SFSpeechRecognizer streaming |
| `Rockout/Services/Recall/AudioTypeClassifier.swift` | Create — Heuristic classifier |
| `Rockout/Services/Recall/RecallToolRouter.swift` | Create — Route speech/music/hum |
| `Rockout/ViewModels/RecallViewModel.swift` | Modify — Wire orchestrator, barge-in |
| `Rockout/Views/Recall/RecallHomeView.swift` | Modify — ChatGPT layout: tap orb; Mute (bottom-left), Exit (bottom-right); waveform; remove long-press |
| `Rockout/Views/Recall/RecallOrbView.swift` | Modify — Tap to start/stop; orb animation for speaking |
| `Rockout/Services/Recall/VoiceResponseService.swift` | Modify — stopSpeaking on barge-in |
| `Rockout/Services/Recall/VoiceRecorder.swift` | Refactor — Optionally use AudioIOManager |
| `Rockout/Views/Recall/RecallCandidateCard.swift` | Modify — Artwork placeholder, source label |
| `Rockout/Services/Recall/AudioSessionManager.swift` | Modify — configureForPlayAndRecord |
| `RockoutTests/RecallVoiceOrchestratorTests.swift` | Create — State machine tests |

---

## Non-Negotiable Constraints

- Long-press is removed — Tap-only activation; VAD detects when user is speaking
- User can deactivate listening — Mute (pause), Exit (end), tap orb to stop; ChatGPT layout (mute bottom-left, exit bottom-right)
- Preserve text composer, image input, stashed threads, GreenRoom integration
- Keep RecallService.resolveRecall API unchanged
- No deletion of existing features; additive/refactor only
- All new code must compile and run
- Use Logger.recall, Combine, async/await patterns
- VoiceOver labels and Dynamic Type on new UI

---

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| SFSpeechRecognizer latency/availability | Fallback: upload+Whisper path |
| VAD false triggers | Tune thresholds; minimum utterance length |
| Audio session conflicts | Reuse VoiceRecorder pause logic; AudioIOManager coordinates |
| ShazamKit not in repo | Keep server-side Shazam/ACRCloud |
