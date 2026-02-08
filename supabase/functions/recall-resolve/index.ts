// Supabase Edge Function: recall-resolve
// Intelligent voice-first conversational music assistant with smart intent detection
// Deploy with: supabase functions deploy recall-resolve
// Requires: OPENAI_API_KEY, ACRCLOUD_ACCESS_KEY, ACRCLOUD_ACCESS_SECRET, SHAZAM_API_KEY

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// Rate limiting configuration
interface RateLimitConfig {
  maxRequestsPerMinute: number;
  maxRequestsPerHour: number;
  maxConcurrentRequests: number;
}

const RATE_LIMITS: RateLimitConfig = {
  maxRequestsPerMinute: 10,
  maxRequestsPerHour: 100,
  maxConcurrentRequests: 5
};

// In-memory rate limiter (use Redis in production for distributed systems)
const rateLimitStore = new Map<string, {
  requests: number[];
  concurrent: number;
}>();

// Circuit breaker for external APIs
class CircuitBreaker {
  private failures = 0;
  private lastFailureTime = 0;
  private state: 'closed' | 'open' | 'half-open' = 'closed';
  private readonly threshold = 5;
  private readonly timeout = 60000; // 1 minute
  
  async execute<T>(operation: () => Promise<T>): Promise<T> {
    if (this.state === 'open') {
      if (Date.now() - this.lastFailureTime > this.timeout) {
        this.state = 'half-open';
      } else {
        throw new Error('Circuit breaker is open');
      }
    }
    
    try {
      const result = await operation();
      this.onSuccess();
      return result;
    } catch (error) {
      this.onFailure();
      throw error;
    }
  }
  
  private onSuccess() {
    this.failures = 0;
    this.state = 'closed';
  }
  
  private onFailure() {
    this.failures++;
    this.lastFailureTime = Date.now();
    
    if (this.failures >= this.threshold) {
      this.state = 'open';
    }
  }
}

const whisperCircuitBreaker = new CircuitBreaker();
const openAICircuitBreaker = new CircuitBreaker();
const acrCloudCircuitBreaker = new CircuitBreaker();
const shazamCircuitBreaker = new CircuitBreaker();

// Rate limiting functions
async function checkRateLimit(
  userId: string,
  supabase: any
): Promise<{ allowed: boolean; retryAfter?: number }> {
  const now = Date.now();
  const key = `rate_limit:${userId}`;
  
  let userLimits = rateLimitStore.get(key) || {
    requests: [],
    concurrent: 0
  };
  
  // Clean old requests (older than 1 hour)
  userLimits.requests = userLimits.requests.filter(
    timestamp => now - timestamp < 3600000
  );
  
  // Check per-minute limit
  const recentRequests = userLimits.requests.filter(
    timestamp => now - timestamp < 60000
  );
  
  if (recentRequests.length >= RATE_LIMITS.maxRequestsPerMinute) {
    const oldestRequest = Math.min(...recentRequests);
    const retryAfter = Math.ceil((60000 - (now - oldestRequest)) / 1000);
    return { allowed: false, retryAfter };
  }
  
  // Check per-hour limit
  if (userLimits.requests.length >= RATE_LIMITS.maxRequestsPerHour) {
    const oldestRequest = Math.min(...userLimits.requests);
    const retryAfter = Math.ceil((3600000 - (now - oldestRequest)) / 1000);
    return { allowed: false, retryAfter };
  }
  
  // Check concurrent limit
  if (userLimits.concurrent >= RATE_LIMITS.maxConcurrentRequests) {
    return { allowed: false, retryAfter: 10 };
  }
  
  // Update limits
  userLimits.requests.push(now);
  userLimits.concurrent++;
  rateLimitStore.set(key, userLimits);
  
  return { allowed: true };
}

async function releaseRateLimit(userId: string) {
  const key = `rate_limit:${userId}`;
  const userLimits = rateLimitStore.get(key);
  if (userLimits) {
    userLimits.concurrent = Math.max(0, userLimits.concurrent - 1);
    rateLimitStore.set(key, userLimits);
  }
}

interface RecallResolveRequest {
  thread_id: string;
  message_id: string;
  input_type: "text" | "voice" | "image";
  text?: string;
  media_path?: string;
  audio_path?: string;
  video_path?: string;
}

interface VoiceIntent {
  type: "conversation" | "information" | "find_song" | "generate_song" | "humming" | "background_audio" | "unclear";
  confidence: number;
  reasoning: string;
}

interface Candidate {
  title: string;
  artist: string;
  confidence: number;
  reason: string;
  background?: string;
  highlight_snippet?: string;
  source_urls: string[];
}

interface OpenAIResponse {
  response_type?: "search" | "answer" | "both";
  overall_confidence: number;
  candidates: Candidate[];
  answer?: {
    text: string;
    sources: string[];
    related_songs?: Array<{title: string; artist: string}>;
  };
  should_ask_crowd: boolean;
  crowd_prompt?: string;
  follow_up_question?: string;
  conversation_state?: string;
}

interface AssistantMessage {
  message_type: "candidate";
  song_title: string;
  song_artist: string;
  confidence: number;
  reason: string;
  lyric_snippet?: string;
  sources: Array<{ title: string; url: string; snippet?: string }>;
  song_url?: string;
  all_candidates?: Array<{
    title: string;
    artist: string;
    confidence: number;
    reason: string;
    lyric_snippet?: string;
    source_urls: string[];
  }>;
}

interface AudioRecognitionResult {
  success: boolean;
  title?: string;
  artist?: string;
  confidence: number;
  service: "acrcloud" | "shazam" | "whisper";
  reason?: string;
  album?: string;
  releaseDate?: string;
  spotifyUrl?: string;
  appleMusicUrl?: string;
}

// NEW: Analyze voice intent to determine if user is conversing or identifying music
async function analyzeVoiceIntent(
  transcription: string,
  openaiApiKey: string
): Promise<VoiceIntent> {
  try {
    console.log(`🧠 Analyzing intent for: "${transcription.substring(0, 100)}..."`);
    
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 10000); // 10s timeout

    const response = await openAICircuitBreaker.execute(() =>
      fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${openaiApiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: "gpt-4o-mini", // Fast and cheap for intent detection
          messages: [
            {
              role: "system",
              content: `Analyze voice transcription to determine user intent. Return JSON with:
{
  "type": "conversation" | "information" | "find_song" | "generate_song" | "humming" | "background_audio" | "unclear",
  "confidence": 0.0-1.0,
  "reasoning": "brief explanation"
}

Intent Types:
- "conversation": Casual chat, greetings, small talk, general conversation (e.g., "How are you?", "Tell me about your day", "What's up", "Thanks", "Hello")
- "information": Information questions about music (e.g., "Who wrote this?", "When was this released?", "What genre is this?", "Tell me about The Beatles", "Explain jazz")
- "find_song": Song identification/search requests (e.g., "What song is this?", "Find this song", "Name that song", "Identify this", "I'm looking for a song")
- "generate_song": Song generation/creation requests (e.g., "Create a song", "Generate music", "Make a beat", "Compose a melody", "Write a song")
- "humming": User is humming, singing, or vocalizing a melody without clear words. Characterized by repetitive sounds, vowel sounds, or musical vocalizations.
- "background_audio": Transcription is unclear, garbled, or contains [inaudible]/[music] tags, suggesting background music playing rather than speech.
- "unclear": Cannot determine with confidence (mixed signals, ambiguous content, or very short unclear input).

Key Detection Rules (apply in order):

1. CONVERSATION (casual chat):
   - Greetings: "hi", "hello", "hey", "how are you", "what's up", "how's it going"
   - Small talk: "thanks", "thank you", "cool", "nice", "awesome", "that's great"
   - Casual responses: "okay", "sure", "yeah", "yep", "nope", "maybe"
   - General conversation without specific music questions
   - Pattern: Friendly, conversational tone without specific information requests

2. INFORMATION QUESTIONS (→ information):
   - Question words + music context: "who wrote", "when was", "what album", "what genre", "where is", "why did"
   - Information requests: "tell me about", "explain", "describe", "what is", "how does"
   - History/facts: "history", "biography", "facts", "story", "background"
   - Comparison: "compare", "difference", "better", "best", "top", "favorite"
   - Recommendation requests: "recommend", "suggest", "similar to", "like", "playlist"
   - Pattern: Asking for factual information about music, artists, songs, genres

3. SONG IDENTIFICATION REQUESTS (→ find_song):
   - Search keywords: "find", "search", "identify", "what song", "name that song", "who sings"
   - Looking for: "I'm looking for", "I need to find", "Can you find", "Help me find"
   - Recognition: "recognize", "remember", "what's this song", "what song is this"
   - Pattern: User wants to identify or find a specific song

4. SONG GENERATION REQUESTS (→ generate_song):
   - Creation keywords: "create", "generate", "make", "compose", "write a song", "produce", "build"
   - Music creation: "make music", "create music", "generate music", "make a beat", "create a melody"
   - Pattern: User wants to create or generate new music

5. HUMMING PATTERNS (→ humming):
   - Repetitive sounds: "hmm", "la", "da", "mm", "ah", "na", "oh", "doo", "dum", "bum", "ba", "pa"
   - Vowel-only sounds: "aa", "ee", "oo", "ii", "uu"
   - Musical syllables: "do re mi", "fa sol la", "ti do"
   - Pattern: <5 words + repetitive sounds = likely humming
   - Pattern: Same sound repeated 3+ times = likely humming
   - Pattern: No recognizable words, only sounds = humming

6. BACKGROUND AUDIO (→ background_audio):
   - Transcription artifacts: [music], [inaudible], [background noise], [unintelligible], [garbled]
   - Very short unclear text: <3 words that don't form sentences
   - Mixed signals: Contains both speech and [music] tags

7. CONFIDENCE THRESHOLDS:
   - conversation: confidence >= 0.7 if clear casual chat
   - information: confidence >= 0.8 if clear information question
   - find_song: confidence >= 0.8 if clear search/identification request
   - generate_song: confidence >= 0.8 if clear generation request
   - humming: confidence >= 0.8 if repetitive sounds pattern is clear
   - background_audio: confidence >= 0.7 if transcription artifacts present
   - unclear: confidence < 0.6 for any type

Examples:
- "How are you?" → conversation (0.95) - casual chat
- "Thanks for your help" → conversation (0.9) - casual response
- "Tell me about The Beatles" → information (0.95) - information question
- "Who wrote Bohemian Rhapsody?" → information (0.95) - information question
- "What song is this?" → find_song (0.9) - song identification request
- "I'm looking for a song" → find_song (0.85) - search request
- "Create a song for me" → generate_song (0.9) - generation request
- "Make a beat" → generate_song (0.85) - generation request
- "hmm hmm hmm da da da" → humming (0.9) - repetitive sounds pattern
- "la la la la la la" → humming (0.95) - clear humming pattern
- "[inaudible] [music] [background noise]" → background_audio (0.9) - transcription artifacts
- "um" or "uh" → unclear (0.5) - too short, ambiguous
- "the" → unclear (0.3) - single word, no context`
          },
          {
            role: "user",
            content: `Transcription: "${transcription}"`
          }
        ],
        response_format: { type: "json_object" },
        temperature: 0.1,
        max_tokens: 150
      }),
      signal: controller.signal
      })
    );

    clearTimeout(timeoutId);

    if (!response.ok) {
      console.warn(`⚠️ Intent analysis API error: ${response.status}`);
      return { type: "unclear", confidence: 0.5, reasoning: "API error" };
    }

    const data = await response.json();
    const content = data.choices[0]?.message?.content;
    
    if (content) {
      const result = JSON.parse(content);
      console.log(`🎯 Intent: ${result.type} (${result.confidence}) - ${result.reasoning}`);
      return {
        type: result.type || "unclear",
        confidence: result.confidence || 0.5,
        reasoning: result.reasoning || "No reasoning provided"
      };
    }

    return { type: "unclear", confidence: 0.5, reasoning: "Empty response" };
  } catch (error) {
    if (error.name === "AbortError") {
      console.error("⚠️ Intent analysis timeout");
    } else {
      console.error("❌ Intent analysis error:", error);
    }
    return { type: "unclear", confidence: 0.5, reasoning: "Error occurred" };
  }
}

// ACRCloud audio identification - Best for humming and partial audio
async function identifyAudioWithACRCloud(audioBuffer: ArrayBuffer): Promise<AudioRecognitionResult> {
  const accessKey = Deno.env.get("ACRCLOUD_ACCESS_KEY");
  const accessSecret = Deno.env.get("ACRCLOUD_ACCESS_SECRET");
  const host = Deno.env.get("ACRCLOUD_HOST") || "identify-us-west-2.acrcloud.com";

  if (!accessKey || !accessSecret) {
    console.log("⚠️ ACRCloud credentials not configured - skipping ACRCloud identification");
    return { success: false, confidence: 0, service: "acrcloud" };
  }

  try {
    console.log(`🔍 Calling ACRCloud API (host: ${host}, audio size: ${audioBuffer.byteLength} bytes)...`);
    
    // ACRCloud accepts raw audio data via FormData
    const formData = new FormData();
    formData.append("sample", new Blob([audioBuffer], { type: "audio/m4a" }));
    formData.append("sample_bytes", audioBuffer.byteLength.toString());
    formData.append("access_key", accessKey);
    formData.append("data_type", "audio");
    formData.append("format", "m4a");

    const response = await fetch(`https://${host}/v1/identify`, {
      method: "POST",
      headers: {
        "access-key": accessKey,
        "access-secret": accessSecret,
      },
      body: formData,
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error(`❌ ACRCloud API error (${response.status}):`, errorText);
      return { success: false, confidence: 0, service: "acrcloud" };
    }

    const data = await response.json();
    console.log("📥 ACRCloud response:", JSON.stringify(data).substring(0, 500));
    
    if (data.status?.code === 0 && data.metadata?.music && data.metadata.music.length > 0) {
      const track = data.metadata.music[0];
      const confidence = track.score ? track.score / 100 : 0.8; // ACRCloud score is 0-100
      
      console.log(`✅ ACRCloud match: "${track.title}" by ${track.artists?.[0]?.name || track.artists?.[0]} (score: ${track.score || 'N/A'})`);
      
      return {
        success: true,
        title: track.title,
        artist: track.artists?.[0]?.name || track.artists?.[0],
        confidence: Math.min(confidence, 1.0),
        service: "acrcloud",
        reason: `Identified via ACRCloud audio fingerprinting (best for humming/partial audio)`,
        album: track.album?.name,
        releaseDate: track.release_date,
        spotifyUrl: track.external_metadata?.spotify?.track?.id 
          ? `https://open.spotify.com/track/${track.external_metadata.spotify.track.id}`
          : undefined,
        appleMusicUrl: track.external_metadata?.apple_music?.track?.id
          ? `https://music.apple.com/track/${track.external_metadata.apple_music.track.id}`
          : undefined,
      };
    }

    console.log("❌ ACRCloud: No music match found");
    return { success: false, confidence: 0, service: "acrcloud" };
  } catch (error) {
    console.error("❌ ACRCloud identification error:", error);
    return { success: false, confidence: 0, service: "acrcloud" };
  }
}

// Shazam audio identification - Best for full songs and background audio
async function identifyAudioWithShazam(audioBuffer: ArrayBuffer): Promise<AudioRecognitionResult> {
  const apiKey = Deno.env.get("SHAZAM_API_KEY");

  if (!apiKey) {
    console.log("⚠️ Shazam API key not configured - skipping Shazam identification");
    return { success: false, confidence: 0, service: "shazam" };
  }

  try {
    console.log(`🔍 Calling Shazam API (audio size: ${audioBuffer.byteLength} bytes)...`);
    
    // Convert audio to base64
    const audioBase64 = btoa(String.fromCharCode(...new Uint8Array(audioBuffer)));
    
    // Shazam API endpoint (using RapidAPI)
    const response = await fetch("https://shazam-api7.p.rapidapi.com/songs/detect", {
      method: "POST",
      headers: {
        "X-RapidAPI-Key": apiKey,
        "X-RapidAPI-Host": "shazam-api7.p.rapidapi.com",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        audio_base64: audioBase64,
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error(`❌ Shazam API error (${response.status}):`, errorText);
      return { success: false, confidence: 0, service: "shazam" };
    }

    const data = await response.json();
    console.log("📥 Shazam response:", JSON.stringify(data).substring(0, 500));
    
    if (data.track) {
      const track = data.track;
      const confidence = data.match ? 0.9 : 0.7; // High confidence if matched
      
      console.log(`✅ Shazam match: "${track.title}" by ${track.subtitle || track.artists?.[0]?.name} (match: ${data.match ? 'yes' : 'no'})`);
      
      return {
        success: true,
        title: track.title,
        artist: track.subtitle || track.artists?.[0]?.name,
        confidence,
        service: "shazam",
        reason: `Identified via Shazam audio fingerprinting (best for full songs)`,
        album: track.sections?.[0]?.metadata?.find((m: any) => m.title === "Album")?.text,
        spotifyUrl: track.hub?.actions?.[0]?.uri,
        appleMusicUrl: track.hub?.options?.[0]?.actions?.[0]?.uri,
      };
    }

    console.log("❌ Shazam: No track match found");
    return { success: false, confidence: 0, service: "shazam" };
  } catch (error) {
    console.error("❌ Shazam identification error:", error);
    return { success: false, confidence: 0, service: "shazam" };
  }
}

// Lyrics fetching from lyrics.ovh API (free, no API key required)
interface LyricsResult {
  success: boolean;
  lyrics?: string;
  language?: string;
  sourceUrl?: string;
  error?: string;
}

// In-memory cache for lyrics to avoid repeated API calls
const lyricsCache = new Map<string, LyricsResult>();

async function fetchLyricsFromGenius(songTitle: string, artistName: string): Promise<LyricsResult> {
  // Check cache first
  const cacheKey = `${songTitle.toLowerCase()}_${artistName.toLowerCase()}`;
  if (lyricsCache.has(cacheKey)) {
    console.log(`📦 [LYRICS] Using cached lyrics for "${songTitle}" by ${artistName}`);
    return lyricsCache.get(cacheKey)!;
  }

  try {
    console.log(`🎵 [LYRICS] Fetching lyrics from lyrics.ovh for "${songTitle}" by ${artistName}...`);
    
    // lyrics.ovh API format: https://api.lyrics.ovh/v1/{artist}/{title}
    // Note: Artist and title should be URL-encoded
    const lyricsOvhUrl = `https://api.lyrics.ovh/v1/${encodeURIComponent(artistName)}/${encodeURIComponent(songTitle)}`;
    
    const lyricsResponse = await fetch(lyricsOvhUrl);
    
    if (!lyricsResponse.ok) {
      if (lyricsResponse.status === 404) {
        console.log(`❌ [LYRICS] Song not found in lyrics.ovh database`);
        const result = { success: false, error: "Song not found in lyrics database" };
        lyricsCache.set(cacheKey, result);
        return result;
      }
      
      const errorText = await lyricsResponse.text();
      console.error(`❌ [LYRICS] lyrics.ovh API error (${lyricsResponse.status}):`, errorText);
      const result = { success: false, error: `Lyrics API error: ${lyricsResponse.status}` };
      lyricsCache.set(cacheKey, result);
      return result;
    }

    const lyricsData = await lyricsResponse.json();
    
    if (lyricsData.lyrics) {
      const lyrics = lyricsData.lyrics.trim();
      console.log(`✅ [LYRICS] Successfully fetched lyrics (${lyrics.length} chars)`);
      
      const result: LyricsResult = {
        success: true,
        lyrics: lyrics,
        sourceUrl: `https://lyrics.ovh/${encodeURIComponent(artistName)}/${encodeURIComponent(songTitle)}`,
      };
      
      // Cache the result
      lyricsCache.set(cacheKey, result);
      return result;
    } else {
      console.log(`❌ [LYRICS] No lyrics found in response`);
      const result = { success: false, error: "No lyrics in response" };
      lyricsCache.set(cacheKey, result);
      return result;
    }

  } catch (error) {
    console.error("❌ [LYRICS] Lyrics fetch error:", error);
    const result = { success: false, error: `Error: ${error instanceof Error ? error.message : String(error)}` };
    lyricsCache.set(cacheKey, result);
    return result;
  }
}

// Language detection for lyrics
async function detectLanguage(text: string, openaiApiKey: string): Promise<string> {
  try {
    // Simple heuristic first - check for common non-English patterns
    const nonEnglishPatterns = [
      { pattern: /[àáâãäåæçèéêëìíîïñòóôõöùúûüýÿ]/i, lang: "Spanish/French/Italian" },
      { pattern: /[äöüß]/i, lang: "German" },
      { pattern: /[àáâãäåæçèéêëìíîïñòóôõöùúûüýÿ]/i, lang: "Romance" },
      { pattern: /[一-龯]/i, lang: "Chinese" },
      { pattern: /[ひらがなカタカナ]/i, lang: "Japanese" },
      { pattern: /[가-힣]/i, lang: "Korean" },
      { pattern: /[а-яё]/i, lang: "Russian" },
      { pattern: /[α-ωάέήίόύώ]/i, lang: "Greek" },
      { pattern: /[א-ת]/i, lang: "Hebrew" },
      { pattern: /[ا-ي]/i, lang: "Arabic" },
    ];

    for (const { pattern, lang } of nonEnglishPatterns) {
      if (pattern.test(text)) {
        console.log(`🌍 [LANG] Detected language via pattern: ${lang}`);
        return lang;
      }
    }

    // If no pattern matches, use GPT-4o-mini for detection
    console.log(`🌍 [LANG] Using GPT-4o-mini to detect language...`);
    
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 5000);

    const response = await openAICircuitBreaker.execute(() =>
      fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${openaiApiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: "gpt-4o-mini",
        messages: [
          {
            role: "system",
            content: "You are a language detection assistant. Analyze the text and return ONLY the language name in English (e.g., 'English', 'Spanish', 'French', 'German', 'Italian', 'Portuguese', 'Chinese', 'Japanese', 'Korean', 'Russian', etc.). Return just the language name, nothing else."
          },
          {
            role: "user",
            content: `What language is this text in? Return only the language name.\n\nText:\n${text.substring(0, 500)}`
          }
        ],
        temperature: 0.1,
        max_tokens: 10,
      }),
      signal: controller.signal
      })
    );

    clearTimeout(timeoutId);

    if (!response.ok) {
      console.log(`⚠️ [LANG] GPT language detection failed, defaulting to English`);
      return "English";
    }

    const data = await response.json();
    const detectedLang = data.choices?.[0]?.message?.content?.trim() || "English";
    console.log(`🌍 [LANG] Detected language: ${detectedLang}`);
    return detectedLang;

  } catch (error) {
    if (error.name === "AbortError") {
      console.log("⚠️ [LANG] Language detection timeout, defaulting to English");
    } else {
      console.error("❌ [LANG] Language detection error:", error);
    }
    return "English";
  }
}

// Summarize song message
interface SongSummary {
  summary: string;
  language: string;
  englishTranslation?: string;
}

async function summarizeSongMessage(
  lyrics: string,
  language: string,
  openaiApiKey: string
): Promise<SongSummary> {
  try {
    console.log(`📝 [SUMMARY] Generating summary for ${language} lyrics...`);
    
    const isEnglish = language.toLowerCase().includes("english");
    const lyricsPreview = lyrics.substring(0, 2000); // Limit to avoid token limits
    
    let systemPrompt: string;
    let userPrompt: string;

    if (isEnglish) {
      systemPrompt = `You are a music analysis assistant. Analyze song lyrics and provide a concise summary (2-3 sentences) of the song's main message, themes, and meaning. Focus on what the song is trying to communicate to listeners. Be clear and insightful.`;
      userPrompt = `Analyze these song lyrics and provide a concise summary (2-3 sentences) of the song's main message, themes, and meaning:\n\n${lyricsPreview}`;
    } else {
      // For foreign languages, generate summary in original language first
      systemPrompt = `You are a music analysis assistant. Analyze song lyrics in ${language} and provide a concise summary (2-3 sentences) in ${language} of the song's main message, themes, and meaning. Focus on what the song is trying to communicate to listeners. Write the summary in ${language}, not English.`;
      userPrompt = `Analyze these ${language} song lyrics and provide a concise summary (2-3 sentences) in ${language} of the song's main message, themes, and meaning:\n\n${lyricsPreview}`;
    }

    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 30000);

    const response = await openAICircuitBreaker.execute(() =>
      fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${openaiApiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: "gpt-4o",
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userPrompt },
        ],
        temperature: 0.3,
        max_tokens: 300,
      }),
      signal: controller.signal
      })
    );

    clearTimeout(timeoutId);

    if (!response.ok) {
      const errorText = await response.text();
      console.error(`❌ [SUMMARY] GPT summary generation failed: ${errorText}`);
      throw new Error(`Summary generation failed: ${response.status}`);
    }

    const data = await response.json();
    const summary = data.choices?.[0]?.message?.content?.trim() || "";

    if (!summary) {
      throw new Error("Empty summary received");
    }

    console.log(`✅ [SUMMARY] Generated summary in ${language} (${summary.length} chars)`);

    const result: SongSummary = {
      summary: summary,
      language: language,
    };

    // If not English, translate the summary to English
    if (!isEnglish) {
      console.log(`🌐 [TRANSLATE] Translating summary to English...`);
      
      const translateController = new AbortController();
      const translateTimeoutId = setTimeout(() => translateController.abort(), 20000);

      const translateResponse = await openAICircuitBreaker.execute(() =>
        fetch("https://api.openai.com/v1/chat/completions", {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${openaiApiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: "gpt-4o-mini",
          messages: [
            {
              role: "system",
              content: `You are a translation assistant. Translate the following ${language} text to English. Preserve the meaning and tone. Return only the translation, nothing else.`
            },
            {
              role: "user",
              content: `Translate this ${language} text to English:\n\n${summary}`
            }
          ],
          temperature: 0.2,
          max_tokens: 200,
        }),
        signal: translateController.signal
        })
      );

      clearTimeout(translateTimeoutId);

      if (translateResponse.ok) {
        const translateData = await translateResponse.json();
        const englishTranslation = translateData.choices?.[0]?.message?.content?.trim() || "";
        if (englishTranslation) {
          result.englishTranslation = englishTranslation;
          console.log(`✅ [TRANSLATE] Translation complete (${englishTranslation.length} chars)`);
        }
      } else {
        console.log(`⚠️ [TRANSLATE] Translation failed, summary available only in ${language}`);
      }
    }

    return result;

  } catch (error) {
    if (error.name === "AbortError") {
      console.error("❌ [SUMMARY] Summary generation timeout");
    } else {
      console.error("❌ [SUMMARY] Summary generation error:", error);
    }
    throw error;
  }
}

// Detect if user is asking about song meaning/message
interface SongMeaningQuery {
  isSongMeaningQuery: boolean;
  songTitle?: string;
  artistName?: string;
}

function detectSongMeaningQuery(
  queryText: string,
  candidates?: Candidate[],
  previousMessages?: any[]
): SongMeaningQuery {
  const queryLower = queryText.toLowerCase();
  
  // Keywords that indicate user wants to know about song meaning
  const meaningKeywords = [
    "what is this song about",
    "what does this song mean",
    "what is the message",
    "what is it talking about",
    "song meaning",
    "lyrics meaning",
    "what is the song about",
    "what does the song mean",
    "what's this song about",
    "what's the song about",
    "what does it mean",
    "what is about",
    "explain the song",
    "explain this song",
    "tell me about this song",
    "what is the meaning",
    "what message",
    "what's the message",
  ];

  const hasMeaningKeyword = meaningKeywords.some(keyword => queryLower.includes(keyword));
  
  if (!hasMeaningKeyword) {
    return { isSongMeaningQuery: false };
  }

  // Try to extract song title and artist from query or context
  let songTitle: string | undefined;
  let artistName: string | undefined;

  // Check if there are candidates from a previous search
  if (candidates && candidates.length > 0) {
    songTitle = candidates[0].title;
    artistName = candidates[0].artist;
    console.log(`🎵 [MEANING] Detected song meaning query, using candidate: "${songTitle}" by ${artistName}`);
    return {
      isSongMeaningQuery: true,
      songTitle,
      artistName,
    };
  }

  // Try to extract from query text (look for "song X" or "X by Y" patterns)
  const songPatterns = [
    /(?:song|track)\s+["']?([^"']+)["']?/i,
    /["']([^"']+)["']\s+(?:by|from)\s+([^,\.]+)/i,
    /(?:about|meaning of|explain)\s+["']?([^"']+)["']?/i,
  ];

  for (const pattern of songPatterns) {
    const match = queryText.match(pattern);
    if (match) {
      songTitle = match[1]?.trim();
      if (match[2]) {
        artistName = match[2]?.trim();
      }
      if (songTitle) {
        console.log(`🎵 [MEANING] Extracted song from query: "${songTitle}"${artistName ? ` by ${artistName}` : ""}`);
        return {
          isSongMeaningQuery: true,
          songTitle,
          artistName,
        };
      }
    }
  }

  // Check previous messages for song mentions
  if (previousMessages) {
    for (const msg of previousMessages.reverse()) {
      if (msg.message_type === "candidate" && msg.song_title) {
        songTitle = msg.song_title;
        artistName = msg.song_artist;
        console.log(`🎵 [MEANING] Found song in previous messages: "${songTitle}" by ${artistName}`);
        return {
          isSongMeaningQuery: true,
          songTitle,
          artistName,
        };
      }
    }
  }

  // If we detected meaning query but couldn't extract song, still return true
  // The integration logic will try to use context
  console.log(`🎵 [MEANING] Detected song meaning query but couldn't extract song details`);
  return {
    isSongMeaningQuery: true,
  };
}

serve(async (req) => {
  const requestId = crypto.randomUUID().substring(0, 8);
  const requestStartTime = Date.now();
  console.log(`\n🚀 [RECALL-RESOLVE] [${requestId}] Request started at ${new Date().toISOString()}`);
  
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  let userId: string | null = null;

  try {
    const step1Time = Date.now();
    // Get authorization header
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      console.log(`❌ [RECALL-RESOLVE] [${requestId}] Missing authorization header`);
      return new Response(
        JSON.stringify({ error: "Missing authorization header" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Initialize Supabase client
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);
    console.log(`⏱️ [RECALL-RESOLVE] [${requestId}] Step 1 - Initialization: ${Date.now() - step1Time}ms`);

    const step2Time = Date.now();
    // Get user from auth for rate limiting
    const { data: { user }, error: authError } = await supabase.auth.getUser(
      authHeader.replace("Bearer ", "")
    );
    
    if (authError || !user) {
      console.log(`❌ [RECALL-RESOLVE] [${requestId}] Authentication failed: ${authError?.message || "No user"}`);
      return new Response(
        JSON.stringify({ error: "Unauthorized" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }
    
    userId = user.id;
    console.log(`✅ [RECALL-RESOLVE] [${requestId}] Authenticated user: ${user.id}`);
    
    // Check rate limit
    const rateLimitCheck = await checkRateLimit(user.id, supabase);
    if (!rateLimitCheck.allowed) {
      console.log(`⛔ [RECALL-RESOLVE] [${requestId}] Rate limit exceeded for user ${user.id}, retry after: ${rateLimitCheck.retryAfter}s`);
      return new Response(
        JSON.stringify({
          error: "Rate limit exceeded",
          retryAfter: rateLimitCheck.retryAfter
        }),
        {
          status: 429,
          headers: {
            ...corsHeaders,
            "Content-Type": "application/json",
            "Retry-After": String(rateLimitCheck.retryAfter || 60)
          }
        }
      );
    }
    
    // Parse request body
    const body: RecallResolveRequest = await req.json();
    const { thread_id, message_id, input_type, text, media_path, audio_path, video_path } = body;
    console.log(`⏱️ [RECALL-RESOLVE] [${requestId}] Step 2 - Parse body: ${Date.now() - step2Time}ms`);
    console.log(`📋 [RECALL-RESOLVE] [${requestId}] Request body:`);
    console.log(`   thread_id: ${thread_id}`);
    console.log(`   message_id: ${message_id}`);
    console.log(`   input_type: ${input_type}`);
    console.log(`   text: ${text ? `"${text.substring(0, 100)}${text.length > 100 ? "..." : ""}"` : "nil"}`);
    console.log(`   media_path: ${media_path || "nil"}`);
    console.log(`   audio_path: ${audio_path || "nil"}`);
    console.log(`   video_path: ${video_path || "nil"}`);

    if (!thread_id || !message_id || !input_type) {
      console.log(`❌ [RECALL-RESOLVE] [${requestId}] Missing required parameters: thread_id=${!!thread_id}, message_id=${!!message_id}, input_type=${!!input_type}`);
      return new Response(
        JSON.stringify({ error: "thread_id, message_id, and input_type are required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Load user message
    const messageLoadStartTime = Date.now();
    const { data: userMessage, error: messageError } = await supabase
      .from("recall_messages")
      .select("*")
      .eq("id", message_id)
      .eq("thread_id", thread_id)
      .single();

    if (messageError || !userMessage) {
      console.log(`❌ [RECALL-RESOLVE] [${requestId}] Message not found: ${messageError?.message || "No data"}`);
      return new Response(
        JSON.stringify({ error: "Message not found", details: messageError?.message }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }
    console.log(`⏱️ [RECALL-RESOLVE] [${requestId}] Message loaded in ${Date.now() - messageLoadStartTime}ms`);
    console.log(`📊 [RECALL-RESOLVE] [${requestId}] User message: type=${userMessage.message_type}, text="${userMessage.text?.substring(0, 100) || "nil"}..."`);

    // Insert "Searching..." status message
    const statusInsertStartTime = Date.now();
    const { data: statusMessage, error: statusError } = await supabase
      .from("recall_messages")
      .insert({
        thread_id,
        user_id: userMessage.user_id,
        role: "assistant",
        message_type: "status",
        text: "Searching...",
      })
      .select()
      .single();

    if (statusError || !statusMessage) {
      console.log(`❌ [RECALL-RESOLVE] [${requestId}] Failed to create status message: ${statusError?.message || "No data"}`);
      return new Response(
        JSON.stringify({ error: "Failed to create status message", details: statusError?.message }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }
    console.log(`⏱️ [RECALL-RESOLVE] [${requestId}] Status message created in ${Date.now() - statusInsertStartTime}ms: ${statusMessage.id}`);

    let queryText = text || userMessage.text || "";
    let audioTranscription = "";
    const openaiApiKey = Deno.env.get("OPENAI_API_KEY");
    const mediaPathToUse = video_path || media_path;
    let shouldUseAudioRecognition = false;
    let audioRecognitionResult: AudioRecognitionResult | null = null;
    let detectedIntent: VoiceIntent | null = null; // Track intent for audio recognition prioritization

    // ============================================
    // NEW INTELLIGENT VOICE PROCESSING FLOW
    // ============================================
    
    if (input_type === "voice" && mediaPathToUse) {
      try {
        const voiceProcessingStartTime = Date.now();
        console.log(`🎤 [RECALL-RESOLVE] [${requestId}] Starting intelligent voice processing...`);
        console.log(`📊 [RECALL-RESOLVE] [${requestId}] Audio path: ${mediaPathToUse}, video_path=${!!video_path}`);
        
        // Get audio file
        const bucket = video_path ? "recall-images" : "recall-audio";
        const urlStartTime = Date.now();
        const { data: signedUrlData, error: urlError } = await supabase.storage
          .from(bucket)
          .createSignedUrl(mediaPathToUse, 3600);

        if (urlError || !signedUrlData) {
          console.log(`❌ [RECALL-RESOLVE] [${requestId}] Failed to create signed URL: ${urlError?.message || "No data"}`);
          throw new Error("Failed to create signed URL for audio");
        }
        console.log(`⏱️ [RECALL-RESOLVE] [${requestId}] Signed URL created in ${Date.now() - urlStartTime}ms`);

        const downloadStartTime = Date.now();
        const audioResponse = await fetch(signedUrlData.signedUrl);
        const audioBlob = await audioResponse.blob();
        const audioArrayBuffer = await audioBlob.arrayBuffer();
        const downloadDuration = Date.now() - downloadStartTime;
        console.log(`⏱️ [RECALL-RESOLVE] [${requestId}] Audio downloaded in ${downloadDuration}ms: ${audioArrayBuffer.byteLength} bytes`);

        // STEP 1: ALWAYS transcribe first to understand user intent
        const transcriptionStartTime = Date.now();
        console.log(`📝 [RECALL-RESOLVE] [${requestId}] [STEP 1] Transcribing with Whisper...`);
        
        if (openaiApiKey) {
          try {
            const audioFile = new File([audioBlob], "audio.m4a", { type: "audio/m4a" });
            const formData = new FormData();
            formData.append("file", audioFile);
            formData.append("model", "whisper-1");

            const transcriptionResponse = await whisperCircuitBreaker.execute(() =>
              fetch("https://api.openai.com/v1/audio/transcriptions", {
                method: "POST",
                headers: {
                  "Authorization": `Bearer ${openaiApiKey}`,
                },
                body: formData,
              })
            );

            if (transcriptionResponse.ok) {
              const transcriptionData = await transcriptionResponse.json();
              audioTranscription = transcriptionData.text || "";
              const transcriptionDuration = Date.now() - transcriptionStartTime;
              console.log(`✅ [RECALL-RESOLVE] [${requestId}] Transcription completed in ${transcriptionDuration}ms`);
              console.log(`📝 [RECALL-RESOLVE] [${requestId}] Transcription: "${audioTranscription}"`);
              
              // Update status
              await supabase
                .from("recall_messages")
                .update({ text: "Understanding..." })
                .eq("id", statusMessage.id);
            } else {
              const errorText = await transcriptionResponse.text();
              const transcriptionDuration = Date.now() - transcriptionStartTime;
              console.error(`❌ [RECALL-RESOLVE] [${requestId}] Transcription failed after ${transcriptionDuration}ms: ${transcriptionResponse.status} - ${errorText}`);
              // Continue without transcription - will use audio recognition
            }
          } catch (transcriptionError) {
            const transcriptionDuration = Date.now() - transcriptionStartTime;
            console.error(`❌ [RECALL-RESOLVE] [${requestId}] Transcription error after ${transcriptionDuration}ms:`, transcriptionError);
            // Continue without transcription - will use audio recognition
          }
        } else {
          console.warn(`⚠️ [RECALL-RESOLVE] [${requestId}] OPENAI_API_KEY not configured, skipping transcription`);
        }

        // STEP 2: Analyze intent - conversation or song identification?
        if (audioTranscription && audioTranscription.trim().length > 0) {
          const intentStartTime = Date.now();
          console.log(`🧠 [RECALL-RESOLVE] [${requestId}] [STEP 2] Analyzing intent...`);
          
          const intent = await analyzeVoiceIntent(audioTranscription, openaiApiKey!);
          detectedIntent = intent; // Store for later use in audio recognition
          const intentDuration = Date.now() - intentStartTime;
          console.log(`⏱️ [RECALL-RESOLVE] [${requestId}] Intent analysis completed in ${intentDuration}ms`);
          console.log(`🎯 [RECALL-RESOLVE] [${requestId}] Detected intent: ${intent.type} (confidence: ${intent.confidence})`);
          console.log(`   Reasoning: ${intent.reasoning}`);
          
          if (intent.type === "humming" || intent.type === "background_audio") {
            shouldUseAudioRecognition = true;
            console.log(`🎵 [RECALL-RESOLVE] [${requestId}] Intent: ${intent.type} → Using audio recognition`);
            
            await supabase
              .from("recall_messages")
              .update({ text: "Identifying song..." })
              .eq("id", statusMessage.id);
              
          } else if (intent.type === "conversation" || intent.type === "information" || intent.type === "generate_song") {
            shouldUseAudioRecognition = false;
            queryText = audioTranscription;
            console.log(`💬 [RECALL-RESOLVE] [${requestId}] Intent: ${intent.type} → Using conversational/informational response`);
            console.log(`📝 [RECALL-RESOLVE] [${requestId}] Query text set to transcription: "${queryText}"`);
            
            await supabase
              .from("recall_messages")
              .update({ text: "Thinking..." })
              .eq("id", statusMessage.id);
              
          } else if (intent.type === "find_song") {
            // For find_song, try audio recognition first, but also use transcription for search
            shouldUseAudioRecognition = true;
            queryText = audioTranscription; // Also use transcription for search
            console.log(`🔍 [RECALL-RESOLVE] [${requestId}] Intent: find_song → Using audio recognition + search`);
            console.log(`📝 [RECALL-RESOLVE] [${requestId}] Query text set to transcription: "${queryText}"`);
            
            await supabase
              .from("recall_messages")
              .update({ text: "Searching for song..." })
              .eq("id", statusMessage.id);
              
          } else {
            // Unclear - use heuristics
            const wordCount = audioTranscription.split(/\s+/).length;
            const hasRepetitiveSounds = /\b(hmm|la|da|mm|ah|na|oh)\b/gi.test(audioTranscription);
            const repetitiveCount = (audioTranscription.match(/\b(hmm|la|da|mm|ah|na|oh)\b/gi) || []).length;
            
            if (wordCount < 5 || (hasRepetitiveSounds && repetitiveCount > 3)) {
              shouldUseAudioRecognition = true;
              console.log(`🤔 [RECALL-RESOLVE] [${requestId}] Unclear intent, but heuristics suggest audio recognition (words:${wordCount}, repetitive:${repetitiveCount})`);
              
              await supabase
                .from("recall_messages")
                .update({ text: "Identifying song..." })
                .eq("id", statusMessage.id);
            } else {
              queryText = audioTranscription;
              console.log(`🤔 [RECALL-RESOLVE] [${requestId}] Unclear intent, treating as conversation (words:${wordCount})`);
              console.log(`📝 [RECALL-RESOLVE] [${requestId}] Query text set to transcription: "${queryText}"`);
              
              await supabase
                .from("recall_messages")
                .update({ text: "Thinking..." })
                .eq("id", statusMessage.id);
            }
          }
        } else {
          // No transcription - likely background music or humming
          shouldUseAudioRecognition = true;
          console.log(`⚠️ [RECALL-RESOLVE] [${requestId}] No transcription, defaulting to audio recognition`);
          
          await supabase
            .from("recall_messages")
            .update({ text: "Identifying song..." })
            .eq("id", statusMessage.id);
        }
        
        const voiceProcessingDuration = Date.now() - voiceProcessingStartTime;
        console.log(`⏱️ [RECALL-RESOLVE] [${requestId}] Voice processing completed in ${voiceProcessingDuration}ms`);
        console.log(`📊 [RECALL-RESOLVE] [${requestId}] Voice processing summary:`);
        console.log(`   transcription: "${audioTranscription || "none"}"`);
        console.log(`   intent: ${detectedIntent?.type || "none"} (${detectedIntent?.confidence || 0})`);
        console.log(`   shouldUseAudioRecognition: ${shouldUseAudioRecognition}`);
        console.log(`   queryText: "${queryText || "none"}"`);

        // STEP 3: Use audio recognition if needed
        if (shouldUseAudioRecognition) {
          const audioRecognitionStartTime = Date.now();
          // Determine if this is a full song identification (find_song intent or longer audio)
          const isFullSong = detectedIntent?.type === "find_song" || audioArrayBuffer.byteLength > 50000; // >50KB suggests longer audio
          const audioDurationHint = audioArrayBuffer.byteLength > 100000 ? "full song" : "audio clip";
          
          console.log(`🎵 [RECALL-RESOLVE] [${requestId}] [STEP 3] Running audio recognition for ${audioDurationHint} (${audioArrayBuffer.byteLength} bytes)...`);
          console.log(`   - Intent: ${detectedIntent?.type || "unknown"}, Full song: ${isFullSong}`);
          console.log(`   - ACRCloud: Best for humming/partial audio`);
          console.log(`   - Shazam: Best for full songs - ${isFullSong ? "PRIORITIZING" : "running in parallel"}`);
          
          // For full songs, prioritize Shazam; for humming/partial, prioritize ACRCloud
          // Always send FULL audio buffer to both services
          const recognitionStartTime = Date.now();
          const [acrCloudResult, shazamResult] = await Promise.allSettled([
            acrCloudCircuitBreaker.execute(() => identifyAudioWithACRCloud(audioArrayBuffer)),
            shazamCircuitBreaker.execute(() => identifyAudioWithShazam(audioArrayBuffer)), // Always call Shazam with full audio buffer
          ]);
          const recognitionDuration = Date.now() - recognitionStartTime;
          console.log(`⏱️ [RECALL-RESOLVE] [${requestId}] Audio recognition completed in ${recognitionDuration}ms`);

          // Choose best result - prioritize Shazam for full songs
          let bestResult: AudioRecognitionResult | null = null;

          // For full songs, check Shazam first (it's better for complete songs)
          if (isFullSong) {
            if (shazamResult.status === "fulfilled" && shazamResult.value.success) {
              bestResult = shazamResult.value;
              console.log(`✅ [RECALL-RESOLVE] [${requestId}] Shazam (PRIORITIZED for full song): ${bestResult.title} by ${bestResult.artist} (${bestResult.confidence})`);
            } else if (shazamResult.status === "rejected") {
              console.log(`❌ [RECALL-RESOLVE] [${requestId}] Shazam failed: ${shazamResult.reason}`);
            }
            
            // Still check ACRCloud as fallback
            if (acrCloudResult.status === "fulfilled" && acrCloudResult.value.success) {
              const acrBest = acrCloudResult.value;
              console.log(`✅ [RECALL-RESOLVE] [${requestId}] ACRCloud: ${acrBest.title} by ${acrBest.artist} (${acrBest.confidence})`);
              // Use ACRCloud only if Shazam failed or has lower confidence
              if (!bestResult || (acrBest.confidence > bestResult.confidence && acrBest.confidence >= 0.8)) {
                bestResult = acrBest;
                console.log(`   → [RECALL-RESOLVE] [${requestId}] Using ACRCloud result (higher confidence)`);
              }
            } else if (acrCloudResult.status === "rejected") {
              console.log(`❌ [RECALL-RESOLVE] [${requestId}] ACRCloud failed: ${acrCloudResult.reason}`);
            }
          } else {
            // For humming/partial audio, check ACRCloud first (it's better for short clips)
            if (acrCloudResult.status === "fulfilled" && acrCloudResult.value.success) {
              bestResult = acrCloudResult.value;
              console.log(`✅ [RECALL-RESOLVE] [${requestId}] ACRCloud (PRIORITIZED for humming/partial): ${bestResult.title} by ${bestResult.artist} (${bestResult.confidence})`);
            } else if (acrCloudResult.status === "rejected") {
              console.log(`❌ [RECALL-RESOLVE] [${requestId}] ACRCloud failed: ${acrCloudResult.reason}`);
            }
            
            // Still check Shazam as fallback
            if (shazamResult.status === "fulfilled" && shazamResult.value.success) {
              const shazamBest = shazamResult.value;
              console.log(`✅ [RECALL-RESOLVE] [${requestId}] Shazam: ${shazamBest.title} by ${shazamBest.artist} (${shazamBest.confidence})`);
              // Use Shazam only if ACRCloud failed or Shazam has significantly higher confidence
              if (!bestResult || (shazamBest.confidence > bestResult.confidence + 0.1)) {
                bestResult = shazamBest;
                console.log(`   → [RECALL-RESOLVE] [${requestId}] Using Shazam result (higher confidence)`);
              }
            } else if (shazamResult.status === "rejected") {
              console.log(`❌ [RECALL-RESOLVE] [${requestId}] Shazam failed: ${shazamResult.reason}`);
            }
          }
          
          // Log final selection
          if (bestResult) {
            console.log(`🎯 [RECALL-RESOLVE] [${requestId}] Final selection: ${bestResult.service} - "${bestResult.title}" by ${bestResult.artist} (confidence: ${bestResult.confidence})`);
            audioRecognitionResult = bestResult;
          } else {
            console.log(`❌ [RECALL-RESOLVE] [${requestId}] Both audio recognition services failed or returned no results`);
          }
          
          const audioRecognitionDuration = Date.now() - audioRecognitionStartTime;
          console.log(`⏱️ [RECALL-RESOLVE] [${requestId}] Audio recognition step completed in ${audioRecognitionDuration}ms`);

          if (bestResult && bestResult.success && bestResult.confidence >= 0.7) {
            // High confidence - return immediately with conversational response
            console.log(`✅ High confidence: ${bestResult.title} by ${bestResult.artist} (${bestResult.confidence})`);
            
            const conversationalReason = `Great! I identified that ${bestResult.service === "acrcloud" ? "from your humming" : "song"}. It's "${bestResult.title}" by ${bestResult.artist}. ${bestResult.album ? `It's from the album "${bestResult.album}".` : ""}`;
            
            const candidate: Candidate = {
              title: bestResult.title!,
              artist: bestResult.artist!,
              confidence: bestResult.confidence,
              reason: conversationalReason,
              source_urls: [bestResult.spotifyUrl, bestResult.appleMusicUrl].filter(Boolean) as string[],
            };

            await supabase
              .from("recall_messages")
              .insert({
                thread_id,
                user_id: userMessage.user_id,
                role: "assistant",
                message_type: "candidate",
                song_title: candidate.title,
                song_artist: candidate.artist,
                confidence: candidate.confidence,
                text: conversationalReason,
                song_url: candidate.source_urls[0],
              });

            await supabase
              .from("recall_messages")
              .delete()
              .eq("id", statusMessage.id);

            if (audioTranscription) {
              await supabase
                .from("recall_messages")
                .update({ text: audioTranscription })
                .eq("id", message_id);
            }

            return new Response(
              JSON.stringify({
                status: "done",
                transcription: audioTranscription,
                candidates: [candidate],
                assistantMessage: {
                  message_type: "candidate",
                  song_title: candidate.title,
                  song_artist: candidate.artist,
                  confidence: candidate.confidence,
                  reason: conversationalReason,
                  sources: candidate.source_urls.map(url => ({ 
                    title: "Music Platform", 
                    url, 
                    snippet: undefined 
                  })),
                  song_url: candidate.source_urls[0],
                },
              }),
              { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
            );
          } else if (bestResult && bestResult.success) {
            // Moderate confidence - enhance query for GPT
            console.log(`⚠️ Moderate confidence (${bestResult.confidence}), enhancing query for GPT`);
            queryText = audioTranscription 
              ? `I think you're asking about "${bestResult.title}" by ${bestResult.artist}. You said: "${audioTranscription}". Is this the song you're looking for?`
              : `Audio recognition found "${bestResult.title}" by ${bestResult.artist} with ${Math.round(bestResult.confidence * 100)}% confidence. Can you verify if this is correct?`;
            
            audioRecognitionResult = bestResult;
          } else {
            // Failed - use transcription or ask for clarification
            console.log("❌ Audio recognition failed");
            queryText = audioTranscription 
              ? audioTranscription
              : "I couldn't identify the audio clearly. Could you try again, or describe what you're looking for?";
          }
        }

        // Update user message with transcription (always update, even if empty, to show status)
        try {
          await supabase
            .from("recall_messages")
            .update({ text: audioTranscription || "Processing audio..." })
            .eq("id", message_id);
          console.log(`✅ Updated user message with transcription: "${audioTranscription || 'Processing...'}"`);
        } catch (updateError) {
          console.error("❌ Failed to update user message with transcription:", updateError);
          // Continue processing even if update fails
        }

      } catch (error) {
        console.error("❌ Voice processing error:", error);
        // Preserve transcription if we have it, even on error
        if (!audioTranscription) {
          queryText = "I had trouble processing the audio. Could you try again or describe what you're looking for?";
        } else {
          // Use transcription even if processing failed
          queryText = audioTranscription;
        }
      }
    }

    // Continue with existing GPT processing for text/low-confidence cases
    console.log("📝 Continuing to GPT processing...");

    // If video with separate audio path, transcribe that audio
    if (audio_path && !audioTranscription && openaiApiKey) {
      try {
        // Get signed URL for audio file
        const { data: signedUrlData, error: urlError } = await supabase.storage
          .from("recall-audio")
          .createSignedUrl(audio_path, 3600);

        if (!urlError && signedUrlData) {
          // Download audio file
          const audioResponse = await fetch(signedUrlData.signedUrl);
          const audioBlob = await audioResponse.blob();
          const audioFile = new File([audioBlob], "audio.m4a", { type: "audio/m4a" });
          
          // Transcribe using OpenAI Whisper
          const whisperFormData = new FormData();
          whisperFormData.append("file", audioFile);
          whisperFormData.append("model", "whisper-1");
          
          const whisperResponse = await fetch("https://api.openai.com/v1/audio/transcriptions", {
            method: "POST",
            headers: {
              "Authorization": `Bearer ${openaiApiKey}`,
            },
            body: whisperFormData,
          });
          
          if (whisperResponse.ok) {
            const whisperData = await whisperResponse.json();
            audioTranscription = whisperData.text || "";
            console.log(`✅ Video audio transcription: "${audioTranscription}"`);
          } else {
            const errorText = await whisperResponse.text();
            console.error(`❌ Video audio transcription failed: ${whisperResponse.status} - ${errorText}`);
          }
        }
      } catch (error) {
        console.error("Error transcribing video audio:", error);
        // Continue without transcription if it fails
      }
    }

    // If image input, use GPT vision (OCR/description) when no query text provided
    if (input_type === "image") {
      if (queryText && queryText.trim().length > 0) {
        // Client provided OCR or caption
        console.log(`📷 [RECALL-RESOLVE] [${requestId}] Using provided text from image: "${queryText.substring(0, 100)}..."`);
      } else if (media_path && openaiApiKey && !audioTranscription) {
        // Run GPT vision to describe image and extract text (OCR)
        try {
          await supabase
            .from("recall_messages")
            .update({ text: "Reading image..." })
            .eq("id", statusMessage.id);

          const imageBucket = "recall-images";
          const { data: signedUrlData, error: urlError } = await supabase.storage
            .from(imageBucket)
            .createSignedUrl(media_path, 3600);

          if (urlError || !signedUrlData?.signedUrl) {
            console.log(`❌ [RECALL-RESOLVE] [${requestId}] Failed to get signed URL for image: ${urlError?.message || "No data"}`);
            queryText = "Image uploaded - searching for matching songs";
          } else {
            const imageResponse = await fetch(signedUrlData.signedUrl);
            const imageBlob = await imageResponse.blob();
            const imageArrayBuffer = await imageBlob.arrayBuffer();
            const bytes = new Uint8Array(imageArrayBuffer);
            let binary = "";
            for (let i = 0; i < bytes.length; i++) {
              binary += String.fromCharCode(bytes[i]);
            }
            const base64Image = btoa(binary);

            const visionPrompt = `Describe this image and extract all visible text (OCR). If it shows album art, lyrics, a playlist, song title, artist name, or anything music-related, include every word you can see. Output only the description and extracted text in one block, nothing else.`;

            const visionResponse = await openAICircuitBreaker.execute(() =>
              fetch("https://api.openai.com/v1/chat/completions", {
                method: "POST",
                headers: {
                  "Authorization": `Bearer ${openaiApiKey}`,
                  "Content-Type": "application/json",
                },
                body: JSON.stringify({
                  model: "gpt-4o",
                  messages: [
                    {
                      role: "user",
                      content: [
                        { type: "text", text: visionPrompt },
                        {
                          type: "image_url",
                          image_url: { url: `data:image/jpeg;base64,${base64Image}` },
                        },
                      ],
                    },
                  ],
                  max_tokens: 1024,
                }),
              })
            );

            if (visionResponse.ok) {
              const visionData = await visionResponse.json();
              const visionText = (visionData.choices?.[0]?.message?.content || "").trim();
              if (visionText.length > 0) {
                queryText = visionText;
                console.log(`📷 [RECALL-RESOLVE] [${requestId}] GPT vision OCR/description: "${queryText.substring(0, 120)}..."`);
              } else {
                queryText = "Image uploaded - searching for matching songs";
              }
            } else {
              const errText = await visionResponse.text();
              console.error(`❌ [RECALL-RESOLVE] [${requestId}] GPT vision failed: ${visionResponse.status} - ${errText}`);
              queryText = "Image uploaded - searching for matching songs";
            }
          }
        } catch (visionError) {
          console.error(`❌ [RECALL-RESOLVE] [${requestId}] Image vision error:`, visionError);
          queryText = "Image uploaded - searching for matching songs";
        }
      } else if (!audioTranscription) {
        queryText = "Image uploaded - searching for matching songs";
      }
    }

    if ((!queryText || queryText.trim().length === 0) && !audioTranscription) {
      await supabase
        .from("recall_messages")
        .update({
          message_type: "status",
          text: "No text available for search",
        })
        .eq("id", statusMessage.id);
      return new Response(
        JSON.stringify({ error: "No text available for search" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Use audio transcription if no query text
    if (!queryText && audioTranscription) {
      queryText = audioTranscription;
    }

    // Call OpenAI with web search enabled
    if (!openaiApiKey) {
      await supabase
        .from("recall_messages")
        .update({
          message_type: "status",
          text: "OpenAI API key not configured",
        })
        .eq("id", statusMessage.id);
      return new Response(
        JSON.stringify({ error: "OpenAI API key not configured" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Build enhanced prompt for OpenAI with web search emphasis and conversational flow
    const systemPrompt = `You are Recall, a friendly and conversational music knowledge assistant. You speak naturally, like a helpful friend who knows a lot about music. You have access to extensive music databases and REAL-TIME WEB SEARCH capabilities via GPT-4o's browsing feature. Your capabilities include:

1. **Song Identification**: Find songs based on descriptions, lyrics, memories, partial information, humming, or background audio
2. **Music Questions**: Answer questions about songs, artists, albums, genres, music history, trivia, and facts
3. **Song Meaning & Lyrics Analysis**: When users ask about what a song is about, what it means, or what message it conveys, the system automatically fetches lyrics from lyrics.ovh and provides summaries. For foreign language songs, summaries are provided in both the original language and English translation.
4. **Music Theory**: Explain music concepts, terminology, and theory
5. **Comparisons**: Compare songs, artists, albums, or genres
6. **Recommendations**: Suggest similar songs, artists, or playlists
7. **Contextual Understanding**: Understand when users want to search vs. ask questions, and respond appropriately

CRITICAL RULES FOR MAXIMUM ACCURACY:
1. **INTENT DETECTION**: First, determine the user's intent based on the detected intent type:
   - "conversation" - Casual chat, greetings, small talk. Respond naturally and conversationally, no search needed.
   - "information" - User wants information about music (keywords: "who wrote", "when was", "what album", "tell me about", "explain", "how", "why"). Use web search to answer questions, return answer object.
   - "find_song" - User wants to find/identify a song (keywords: "find", "search", "identify", "what song", "name that song", "who sings"). Use audio recognition or search, return candidates.
   - "generate_song" - User wants to create/generate music (keywords: "create", "generate", "make", "compose"). Provide guidance or route to generation service if available.
   - "humming" - User is humming/singing. Use audio recognition services.
   - "background_audio" - Background music detected. Use audio recognition services.
   
   Response type mapping:
   - "conversation" → response_type: "answer" (conversational response)
   - "information" → response_type: "answer" (information answer)
   - "find_song" → response_type: "search" (return candidates)
   - "generate_song" → response_type: "answer" (provide guidance)
   - "humming" or "background_audio" → response_type: "search" (audio recognition results)

2. **MANDATORY WEB SEARCH**: You MUST use web search to verify every song candidate and answer. Do not rely solely on training data - actively search the web for current, accurate information.

3. **INTELLIGENT DYNAMIC FOLLOW-UP QUESTIONS**: When overall_confidence < 0.7 and no strong matches are found, you MUST generate a highly context-aware, intelligent follow-up question. The question should be:
   - **DYNAMIC**: Adapt in real-time based on what information is already known vs. what's missing
   - **CONTEXT-INTELLIGENT**: Analyze the conversation history to understand what's been asked, what's been answered, and what gaps remain
   - **PROGRESSIVE**: Build systematically on previous information - if genre is known, ask about lyrics or melody; if era is known, ask about tempo or style
   - **NATURAL & CONVERSATIONAL**: Sound like a helpful friend, not a robot (use contractions, natural phrasing, friendly tone)
   - **NON-REPETITIVE**: Never repeat questions already asked - check conversation context carefully
   - **STRATEGIC**: Ask for the MOST VALUABLE missing piece of information that will narrow the search most effectively
   - **VOICE-OPTIMIZED**: Be concise and easy to answer via voice (one clear question, not multiple)
   - **CONFIDENCE-ADAPTIVE**: 
     * If confidence < 0.3: Ask broad foundational questions (genre, era, mood)
     * If confidence 0.3-0.5: Ask medium-specific questions (lyrics snippets, artist hints, tempo)
     * If confidence 0.5-0.7: Ask very specific questions (exact lyrics, melody description, instruments)
   - **INFORMATION-GAP ANALYSIS**: Identify what's missing and ask for the highest-impact missing piece:
     * If genre missing → ask genre (most important filter)
     * If genre known but lyrics missing → ask lyrics (most specific identifier)
     * If genre + era known but lyrics missing → ask lyrics or melody
     * If multiple details known → ask for the most distinguishing detail (unique lyrics, specific instrument, distinctive feature)
   - **CONTEXTUAL REFERENCING**: Naturally reference previous answers (e.g., "You mentioned it was pop from the 80s - do you remember any lyrics?")
   - **INTELLIGENT PRIORITIZATION**: Prioritize questions that will eliminate the most candidates:
     * Lyrics > Genre > Era > Tempo > Artist hints > Instruments
   - Examples of excellent dynamic questions:
     * "You said it was pop - do you remember any lyrics or the melody?"
     * "Since it was from the 80s, was it a popular hit or more obscure?"
     * "You mentioned it was upbeat - can you describe the instruments or style?"
     * "What about the artist's voice - was it male or female?"
     * "Do you remember any specific words from the chorus?"
   
   **Information Tracking (extract and remember):**
   - Genre: pop, rock, hip-hop, country, jazz, classical, electronic, etc.
   - Era/Decade: 60s, 70s, 80s, 90s, 2000s, 2010s, recent, old, classic
   - Tempo/Mood: upbeat, slow, ballad, fast, energetic, mellow, sad, happy
   - Artist hints: gender (male/female), solo/band, famous/obscure, style
   - Lyrics: any words or phrases remembered
   - Instruments: guitar, piano, drums, strings, electronic, etc.
   - Context: where heard (radio, movie, commercial, party, etc.)
   
   **Smart Question Progression (broad → specific):**
   
   **Level 1 - No Information Yet:**
   - "What genre was it - pop, rock, hip-hop, or something else?"
   - "Do you remember roughly when it came out - was it recent or older?"
   - "Can you describe the mood - was it upbeat or more mellow?"
   
   **Level 2 - Genre/Era Known:**
   - "Do you remember any lyrics from that song?"
   - "What about the artist's voice - was it male or female?"
   - "Was it upbeat or more of a ballad?"
   
   **Level 3 - Some Details Known:**
   - "Can you describe the melody or beat?"
   - "What instruments stood out - guitar, piano, electronic?"
   - "Was it a popular hit or more of a deep cut?"
   
   **Level 4 - Multiple Details Known:**
   - "Do you remember any specific words or phrases from the chorus?"
   - "What about the tempo - was it fast or slow?"
   - "Can you hum or describe the main melody?"
   
   **Context-Aware Examples:**
   - If genre extracted: "You mentioned it was pop - do you remember any lyrics or the melody?"
   - If era extracted: "Since it was from the 80s, was it a popular hit or more of a deep cut?"
   - If tempo mentioned: "You said it was upbeat - can you describe the instruments or style?"
   - If previous question about lyrics: "What about the artist's voice - was it male or female?"
   - If user mentioned artist hint: "Do you remember any lyrics from that song?"
   - If genre + era known: "Do you remember any lyrics or the main melody?"
   - If multiple details known: "Can you describe the beat or rhythm?"
   
   **Bad Question Examples (avoid these):**
   - "What song?" (too vague, doesn't build on context)
   - Repeating a question already asked in conversation history
   - Asking for information already provided (e.g., asking genre when user already said "pop")
   - Multiple questions in one (e.g., "What genre and when was it?")
   - Generic questions when specific context exists (e.g., "What song?" when genre/era already known)

4. **Multi-Source Verification**: Cross-reference information from at least 3 of these sources:
   - Spotify (official artist pages, verified releases)
   - Apple Music (official catalog)
   - YouTube (official music videos, verified channels)
   - Wikipedia (song articles, artist pages)
   - Genius (lyrics database, annotations)
   - AllMusic (comprehensive music database)
   - Billboard (chart history, release dates)
   - Official artist websites and social media
   - Music streaming platform APIs when available

5. **Return a JSON object with this exact structure**:
{
  "response_type": "search" | "answer" | "both",
  "overall_confidence": 0.0-1.0,
  "candidates": [
    {
      "title": "Exact Song Title",
      "artist": "Primary Artist (feat. Featured Artist if applicable)",
      "confidence": 0.0-1.0,
      "reason": "Detailed explanation of why this matches - include specific details from lyrics, melody, genre, release date, or other distinguishing features",
      "background": "Comprehensive background: release date, album, genre, cultural significance, chart performance, notable facts. 2-3 sentences minimum.",
      "highlight_snippet": "Exact lyric line or memorable phrase (max 50 chars)",
      "source_urls": ["verified_url1", "verified_url2", "verified_url3"]
    }
  ],
  "answer": {
    "text": "Comprehensive answer to the user's question (only if response_type is 'answer' or 'both')",
    "sources": ["source_url1", "source_url2", "source_url3"],
    "related_songs": [{"title": "Song Title", "artist": "Artist Name"}]
  },
  "should_ask_crowd": false,
  "crowd_prompt": "Optional prompt for asking the crowd",
  "follow_up_question": "Optional. Only after you have fully answered the user's question or request. Natural follow-up to refine or continue (only if overall_confidence < 0.7 or conversation needs continuation). Never lead with a question—always answer first.",
  "conversation_state": "searching" | "refining_search" | "found" | "needs_clarification" | "answering" | "general_question"
}

6. **Response Type Guidelines**:
   - If user asks "find", "search", "identify", "what song" → response_type: "search", return candidates
   - If user asks "who wrote", "when was", "what album", "tell me about" → response_type: "answer", return answer object
   - If user asks both → response_type: "both", return both candidates and answer
   - For search queries: Always return candidates array (even if empty)
   - For questions: Always return answer object with text, sources, and optionally related_songs

7. **Search Strategy**:
   - If user provides lyrics: Search for exact lyric matches across multiple platforms
   - If user describes melody/beat: Search for songs with similar musical characteristics
   - If user mentions artist/style: Search artist discography and similar artists
   - If background audio from video: Use audio transcription clues to search for matching songs
   - If previous conversation context exists: Use it to narrow search and avoid repeating questions
   - Always verify song exists and information is current

8. **Answer Strategy** (for questions):
   - ALWAYS answer the user's question or request first in the "answer" object. Never lead with a follow-up question.
   - Provide comprehensive, accurate answers based on web search
   - Include relevant facts, dates, and context
   - Cite sources in the sources array
   - If relevant, suggest related songs in related_songs array
   - Be conversational and natural in tone - write as if speaking to the user directly
   - Use first person ("I found...", "Based on...") to make it feel like a real conversation
   - Keep answers concise but informative (2-4 sentences for most questions)
   - For complex topics, break into digestible chunks
   - Always respond with voice-friendly text (avoid complex formatting, use natural pauses)
   - Only add follow_up_question after the answer is complete—as an optional next step, not instead of answering
   - **SONG MEANING QUERIES**: When user asks about what a song is about, what it means, or what message it conveys:
     * The system will automatically fetch lyrics from lyrics.ovh API
     * Lyrics will be analyzed to generate a summary of the song's message
     * For foreign language songs, summaries will be provided in both the original language and English translation
     * Include the lyrics summary naturally in your answer
     * Cite lyrics.ovh as a source when lyrics are used
     * Format: For foreign songs, present summary in original language first, then English translation
     * Example: "This song is about [original language summary]. In English, it means [English translation]."

9. Provide up to 5 candidates for search queries, ranked by confidence (highest first)
10. Deduplicate candidates (same title+artist = one entry, keep highest confidence)
11. highlight_snippet must be an exact lyric quote or memorable line (not a description)
12. source_urls must include at least 3 verified sources from reputable music platforms
13. background field is REQUIRED for all candidates - provide meaningful context
14. If overall_confidence < 0.65, set should_ask_crowd to true and provide a helpful crowd_prompt
15. If overall_confidence < 0.7 and candidates are weak, set follow_up_question (after the answer/candidates) and conversation_state to "refining_search"
16. Be extremely specific and accurate - verify all information via web search before returning
17. If the user query is vague, search for multiple interpretations and return the most likely matches
18. Consider alternative spellings, common misheard lyrics, and similar-sounding artists
19. Include confidence scores that reflect actual certainty based on available information and search results
20. Track conversation context to avoid repeating follow-up questions
21. For general music questions, provide detailed, informative answers with proper citations`;

    // Get conversation context for better accuracy
    const contextStartTime = Date.now();
    console.log(`🔍 [RECALL-RESOLVE] [${requestId}] Building conversation context...`);
    const { data: previousMessages } = await supabase
      .from("recall_messages")
      .select("text, role, message_type, song_title, song_artist, confidence, created_at")
      .eq("thread_id", thread_id)
      .order("created_at", { ascending: false })
      .limit(20);
    const contextLoadDuration = Date.now() - contextStartTime;
    console.log(`⏱️ [RECALL-RESOLVE] [${requestId}] Context loaded in ${contextLoadDuration}ms: ${previousMessages?.length || 0} messages`);
    
    let contextText = "";
    const rejectedCandidates: Array<{title: string, artist: string}> = [];
    const previousQueries: string[] = [];
    const previousQuestions: string[] = [];
    const userClarifications: string[] = [];
    const userAnswers: Array<{question: string, answer: string}> = [];
    const extractedInfo: {
      genre?: string, 
      era?: string, 
      tempo?: string, 
      mood?: string,
      artist?: string, 
      artistGender?: string,
      artistType?: string,
      lyrics?: string,
      instruments?: string[],
      context?: string
    } = {};
    const successfulIdentifications: Array<{title: string, artist: string}> = [];
    let conversationFlow: 'initial' | 'refining' | 'found' | 'general_question' = 'initial';
    
    if (previousMessages && previousMessages.length > 1) {
      const contextBuildStartTime = Date.now();
      // Sort messages chronologically for proper context building
      const sortedMessages = [...previousMessages].sort((a, b) => 
        new Date(a.created_at).getTime() - new Date(b.created_at).getTime()
      );
      
      // Process messages to extract context
      const contextMessages = sortedMessages
        .filter(m => 
          (m.role === "user" && m.text) || 
          (m.message_type === "candidate") ||
          (m.message_type === "follow_up" && m.text)
        );
      
      // Track question-answer pairs
      let lastFollowUpQuestion: string | null = null;
      
      contextMessages.forEach((m, index) => {
        if (m.role === "user" && m.text) {
          previousQueries.push(m.text);
          
          // If this user message comes after a follow-up question, it's an answer
          if (lastFollowUpQuestion) {
            userAnswers.push({
              question: lastFollowUpQuestion,
              answer: m.text
            });
            lastFollowUpQuestion = null;
            
            // Intelligent information extraction from user answers
            const answerLower = m.text.toLowerCase();
            const answerText = m.text;
            
            // Extract genre (more comprehensive)
            const genres = ['pop', 'rock', 'hip-hop', 'hip hop', 'rap', 'country', 'jazz', 'blues', 'classical', 'electronic', 'r&b', 'r and b', 'reggae', 'metal', 'folk', 'indie', 'alternative', 'punk', 'soul', 'funk', 'disco', 'edm', 'house', 'techno', 'dubstep', 'trap', 'latin', 'k-pop', 'country', 'bluegrass'];
            for (const genre of genres) {
              if (answerLower.includes(genre)) {
                extractedInfo.genre = genre.replace(/\s+/g, '-'); // Normalize
                break;
              }
            }
            
            // Extract era/decade (more comprehensive)
            const eraPatterns = [
              { pattern: /\b(19)?60s?\b/i, era: '60s' },
              { pattern: /\b(19)?70s?\b/i, era: '70s' },
              { pattern: /\b(19)?80s?\b/i, era: '80s' },
              { pattern: /\b(19)?90s?\b/i, era: '90s' },
              { pattern: /\b2000s?\b/i, era: '2000s' },
              { pattern: /\b2010s?\b/i, era: '2010s' },
              { pattern: /\b2020s?\b/i, era: '2020s' },
              { pattern: /\b(sixties|sixty)\b/i, era: '60s' },
              { pattern: /\b(seventies|seventy)\b/i, era: '70s' },
              { pattern: /\b(eighties|eighty)\b/i, era: '80s' },
              { pattern: /\b(nineties|ninety)\b/i, era: '90s' },
              { pattern: /\b(recent|new|latest|current)\b/i, era: 'recent' },
              { pattern: /\b(old|classic|vintage|retro)\b/i, era: 'classic' }
            ];
            for (const { pattern, era } of eraPatterns) {
              if (pattern.test(answerText)) {
                extractedInfo.era = era;
                break;
              }
            }
            
            // Extract tempo/mood (more comprehensive)
            if (answerLower.match(/\b(fast|upbeat|quick|energetic|bouncy|dance|dancing|party)\b/)) {
              extractedInfo.tempo = 'fast';
            } else if (answerLower.match(/\b(slow|ballad|calm|mellow|relaxing|chill|soft|gentle)\b/)) {
              extractedInfo.tempo = 'slow';
            } else if (answerLower.match(/\b(medium|moderate|mid-tempo)\b/)) {
              extractedInfo.tempo = 'medium';
            }
            
            // Extract mood/emotion
            if (answerLower.match(/\b(happy|joyful|cheerful|upbeat|positive)\b/)) {
              extractedInfo.mood = 'happy';
            } else if (answerLower.match(/\b(sad|melancholic|emotional|depressing|somber)\b/)) {
              extractedInfo.mood = 'sad';
            } else if (answerLower.match(/\b(romantic|love|romantic|intimate)\b/)) {
              extractedInfo.mood = 'romantic';
            }
            
            // Extract artist mentions (improved pattern)
            const artistPatterns = [
              /(?:artist|singer|band|by|performed by|sung by)\s+(?:is|was|named|called|called|the)?\s*([A-Z][a-zA-Z]+(?:\s+[A-Z][a-zA-Z]+)*)/i,
              /(?:it'?s|it is|it was)\s+(?:by|from)\s+([A-Z][a-zA-Z]+(?:\s+[A-Z][a-zA-Z]+)*)/i,
              /^([A-Z][a-zA-Z]+(?:\s+[A-Z][a-zA-Z]+)*)\s+(?:sings|sang|performed|did)/i
            ];
            for (const pattern of artistPatterns) {
              const artistMatch = answerText.match(pattern);
              if (artistMatch && artistMatch[1] && artistMatch[1].length > 2) {
                extractedInfo.artist = artistMatch[1].trim();
                break;
              }
            }
            
            // Extract artist characteristics
            if (answerLower.match(/\b(male|man|guy|his|he)\b/)) {
              extractedInfo.artistGender = 'male';
            } else if (answerLower.match(/\b(female|woman|girl|her|she)\b/)) {
              extractedInfo.artistGender = 'female';
            }
            if (answerLower.match(/\b(solo|single|one person)\b/)) {
              extractedInfo.artistType = 'solo';
            } else if (answerLower.match(/\b(band|group|duo|trio)\b/)) {
              extractedInfo.artistType = 'band';
            }
            
            // Extract lyrics (improved extraction)
            const lyricPatterns = [
              /"([^"]{5,50})"/,  // Quoted text
              /(?:lyrics?|says?|sings?|goes?|words?)\s+(?:are|is|was|were)?\s*["']([^"']{5,50})["']/i,  // After "lyrics are"
              /(?:it|the song|chorus|verse)\s+(?:says?|sings?|goes?)\s*["']([^"']{5,50})["']/i,  // "it says"
              /(?:remember|recall|think)\s+(?:the|it|that)\s+(?:lyrics?|words?|says?)\s*["']([^"']{5,50})["']/i  // "remember it says"
            ];
            for (const pattern of lyricPatterns) {
              const lyricMatch = answerText.match(pattern);
              if (lyricMatch && lyricMatch[1] && lyricMatch[1].length >= 5) {
                extractedInfo.lyrics = lyricMatch[1].trim();
                break;
              }
            }
            
            // Extract instruments
            const instruments = ['guitar', 'piano', 'drums', 'bass', 'violin', 'viola', 'cello', 'trumpet', 'saxophone', 'sax', 'flute', 'organ', 'synthesizer', 'synth', 'electronic', 'strings', 'brass', 'percussion'];
            for (const instrument of instruments) {
              if (answerLower.includes(instrument)) {
                if (!extractedInfo.instruments) extractedInfo.instruments = [];
                extractedInfo.instruments.push(instrument);
              }
            }
            
            // Extract context (where heard)
            if (answerLower.match(/\b(radio|fm|am|station)\b/)) {
              extractedInfo.context = 'radio';
            } else if (answerLower.match(/\b(movie|film|cinema|screen)\b/)) {
              extractedInfo.context = 'movie';
            } else if (answerLower.match(/\b(commercial|ad|advertisement)\b/)) {
              extractedInfo.context = 'commercial';
            } else if (answerLower.match(/\b(party|club|bar|restaurant)\b/)) {
              extractedInfo.context = 'party';
            } else if (answerLower.match(/\b(tiktok|instagram|youtube|social media)\b/)) {
              extractedInfo.context = 'social media';
            }
          }
          
          // If this is a refinement after a candidate, it's likely a clarification
          const nextMessage = sortedMessages.find(pm => 
            new Date(pm.created_at).getTime() > new Date(m.created_at).getTime() && 
            pm.message_type === "candidate"
          );
          if (nextMessage) {
            userClarifications.push(m.text);
          }
        } else if (m.message_type === "candidate" && m.song_title && m.song_artist) {
          // Check if this candidate was rejected (low confidence or user continued searching)
          if (m.confidence && m.confidence < 0.6) {
            rejectedCandidates.push({ title: m.song_title, artist: m.song_artist });
          } else if (m.confidence && m.confidence >= 0.8) {
            // Track successful identifications
            successfulIdentifications.push({ title: m.song_title, artist: m.song_artist });
            conversationFlow = 'found';
          }
        } else if (m.message_type === "follow_up" && m.text) {
          previousQuestions.push(m.text);
          lastFollowUpQuestion = m.text;
          conversationFlow = 'refining';
        }
      });
      
      // Determine conversation flow if not already set
      if (conversationFlow === 'initial' && previousQueries.length > 1) {
        conversationFlow = 'refining';
      }
      
      // Build context text
      const contextParts: string[] = [];
      
      if (previousQueries.length > 0) {
        contextParts.push(`Previous user queries: ${previousQueries.slice(-3).map(q => `"${q}"`).join(", ")}`);
      }
      
      if (rejectedCandidates.length > 0) {
        contextParts.push(`Rejected candidates (don't suggest these again): ${rejectedCandidates.map(c => `"${c.title}" by ${c.artist}`).join(", ")}`);
      }
      
      if (previousQuestions.length > 0) {
        contextParts.push(`Previously asked questions (avoid repeating): ${previousQuestions.slice(-2).map(q => `"${q}"`).join(", ")}`);
      }
      
      if (userAnswers.length > 0) {
        contextParts.push(`User answers to previous questions: ${userAnswers.slice(-3).map(qa => `Q: "${qa.question}" A: "${qa.answer}"`).join("; ")}`);
      }
      
      if (Object.keys(extractedInfo).length > 0) {
        const infoParts: string[] = [];
        if (extractedInfo.genre) infoParts.push(`genre: ${extractedInfo.genre}`);
        if (extractedInfo.era) infoParts.push(`era: ${extractedInfo.era}`);
        if (extractedInfo.tempo) infoParts.push(`tempo: ${extractedInfo.tempo}`);
        if (extractedInfo.mood) infoParts.push(`mood: ${extractedInfo.mood}`);
        if (extractedInfo.artist) infoParts.push(`artist hint: ${extractedInfo.artist}`);
        if (extractedInfo.artistGender) infoParts.push(`artist gender: ${extractedInfo.artistGender}`);
        if (extractedInfo.artistType) infoParts.push(`artist type: ${extractedInfo.artistType}`);
        if (extractedInfo.lyrics) infoParts.push(`lyrics hint: "${extractedInfo.lyrics}"`);
        if (extractedInfo.instruments && extractedInfo.instruments.length > 0) {
          infoParts.push(`instruments: ${extractedInfo.instruments.join(", ")}`);
        }
        if (extractedInfo.context) infoParts.push(`context: ${extractedInfo.context}`);
        if (infoParts.length > 0) {
          contextParts.push(`Extracted information: ${infoParts.join(", ")}`);
        }
      }
      
      if (userClarifications.length > 0) {
        contextParts.push(`User clarifications: ${userClarifications.slice(-2).map(c => `"${c}"`).join(", ")}`);
      }
      
      if (successfulIdentifications.length > 0) {
        contextParts.push(`Successfully identified songs (user preferences): ${successfulIdentifications.slice(-2).map(s => `"${s.title}" by ${s.artist}`).join(", ")}`);
      }
      
      contextParts.push(`Conversation flow: ${conversationFlow}`);
      
      if (contextParts.length > 0) {
        // Build intelligent follow-up question guidance based on extracted information
        const missingInfo: string[] = [];
        const knownInfo: string[] = [];
        
        if (!extractedInfo.genre) missingInfo.push("genre");
        else knownInfo.push(`genre: ${extractedInfo.genre}`);
        
        if (!extractedInfo.era) missingInfo.push("era/decade");
        else knownInfo.push(`era: ${extractedInfo.era}`);
        
        if (!extractedInfo.tempo) missingInfo.push("tempo/mood");
        else knownInfo.push(`tempo: ${extractedInfo.tempo}`);
        
        if (!extractedInfo.artist) missingInfo.push("artist hints");
        else knownInfo.push(`artist hint: ${extractedInfo.artist}`);
        
        if (!extractedInfo.lyrics) missingInfo.push("lyrics");
        else knownInfo.push(`lyrics hint: "${extractedInfo.lyrics}"`);
        
        // Determine the most valuable missing piece to ask about (intelligent prioritization)
        let priorityQuestion = "";
        const hasGenre = extractedInfo.genre;
        const hasEra = extractedInfo.era;
        const hasLyrics = extractedInfo.lyrics;
        const hasTempo = extractedInfo.tempo;
        const hasArtist = extractedInfo.artist || extractedInfo.artistGender;
        
        // Intelligent priority: Lyrics > Genre > Era > Tempo > Artist > Instruments
        if (!hasLyrics && hasGenre && hasEra) {
          priorityQuestion = "Ask about lyrics or melody (most specific identifier - genre and era already known)";
        } else if (!hasGenre && !hasLyrics) {
          priorityQuestion = "Ask about genre first (most important filter), then lyrics";
        } else if (!hasLyrics) {
          priorityQuestion = "Ask about lyrics or melody (most specific identifier)";
        } else if (!hasGenre) {
          priorityQuestion = "Ask about genre (critical filter to narrow search)";
        } else if (!hasEra && hasGenre) {
          priorityQuestion = "Ask about era/decade (helps narrow time period - genre already known)";
        } else if (!hasTempo && hasGenre && hasEra) {
          priorityQuestion = "Ask about tempo or mood (helps distinguish similar songs - genre and era known)";
        } else if (!hasArtist && hasGenre) {
          priorityQuestion = "Ask about artist characteristics (voice gender, solo/band, style - genre known)";
        } else if (hasGenre && hasEra && hasTempo && !hasLyrics) {
          priorityQuestion = "Ask about lyrics or distinctive features (very specific - most other info known)";
        } else {
          priorityQuestion = "Ask for more specific details (exact lyrics, distinctive features, instruments, or unique characteristics)";
        }
        
        contextText = `\n\nConversation context:\n${contextParts.join("\n")}\n\nINTELLIGENT FOLLOW-UP QUESTION GENERATION RULES:
${knownInfo.length > 0 ? `✅ KNOWN INFORMATION: ${knownInfo.join(", ")}` : "❌ NO INFORMATION EXTRACTED YET"}
${missingInfo.length > 0 ? `❌ MISSING INFORMATION: ${missingInfo.join(", ")}` : "✅ ALL KEY INFORMATION COLLECTED"}

🎯 PRIORITY STRATEGY: ${priorityQuestion}

CRITICAL INSTRUCTIONS FOR FOLLOW-UP QUESTIONS:
1. **DYNAMIC ADAPTATION**: Analyze what's known vs. missing and ask for the HIGHEST-VALUE missing piece
2. **NO REPETITION**: Never repeat questions from "Previously asked questions" - check carefully
3. **PROGRESSIVE BUILDING**: 
   - If genre known → ask lyrics or melody (most specific)
   - If genre + era known → ask lyrics, tempo, or artist hints
   - If genre + era + tempo known → ask lyrics or distinctive features
   - If multiple details known → ask for the most distinguishing detail
4. **CONTEXTUAL REFERENCING**: Naturally reference known info (e.g., "You mentioned it was ${extractedInfo.genre || 'pop'} - do you remember any lyrics?")
5. **CONFIDENCE-BASED DEPTH**:
   - Low confidence (<0.3): Ask broad questions (genre, era, mood)
   - Medium confidence (0.3-0.5): Ask medium-specific (lyrics snippets, tempo, artist hints)
   - Higher confidence (0.5-0.7): Ask very specific (exact lyrics, melody, instruments)
6. **INTELLIGENT PRIORITIZATION**: Ask for information in this order of impact:
   - Lyrics (most specific identifier) > Genre (best filter) > Era (time filter) > Tempo (distinguisher) > Artist hints > Instruments
7. **NATURAL LANGUAGE**: Make questions sound conversational and friendly, not robotic
8. **SINGLE FOCUS**: One clear question, not multiple questions
9. **VOICE-FRIENDLY**: Easy to answer via voice (avoid complex multi-part questions)
10. **GAP-FILLING**: Focus on the most critical missing piece that will narrow search most effectively

${rejectedCandidates.length > 0 ? `⚠️ DO NOT suggest these rejected candidates: ${rejectedCandidates.map(c => `"${c.title}" by ${c.artist}`).join(", ")}` : ""}
${previousQuestions.length > 0 ? `⚠️ DO NOT repeat these questions: ${previousQuestions.slice(-2).map(q => `"${q}"`).join(", ")}` : ""}

Generate a follow-up question that is:
- Dynamic and adaptive to current context
- Intelligent about what information is most valuable
- Context-aware and references previous answers naturally
- Non-repetitive and progressive
- Optimized for the current confidence level and information gaps`;
        const contextBuildDuration = Date.now() - contextBuildStartTime;
        console.log(`⏱️ [RECALL-RESOLVE] [${requestId}] Context built in ${contextBuildDuration}ms: ${contextText.length} chars`);
        console.log(`📊 [RECALL-RESOLVE] [${requestId}] Context summary: ${contextParts.length} parts, extractedInfo keys: ${Object.keys(extractedInfo).length}`);
      }
    }

    // Detect user intent
    const queryLower = queryText.toLowerCase();
    const searchKeywords = ['find', 'search', 'identify', 'what song', 'name that song', 'who sings', 'what is this song', 'recognize'];
    const questionKeywords = ['who wrote', 'when was', 'what album', 'tell me about', 'explain', 'how', 'why', 'what is', 'who is', 'where'];
    
    const hasSearchIntent = searchKeywords.some(kw => queryLower.includes(kw));
    const hasQuestionIntent = questionKeywords.some(kw => queryLower.includes(kw));
    
    // Context-based intent: if previous messages were searches, likely continuation
    const isSearchContinuation = conversationFlow !== 'initial' || previousQueries.length > 0;
    
    let queryIntent: 'search' | 'question' | 'both' = 'search';
    if (hasQuestionIntent && !hasSearchIntent) {
      queryIntent = 'question';
    } else if (hasSearchIntent && hasQuestionIntent) {
      queryIntent = 'both';
    } else if (hasQuestionIntent && isSearchContinuation) {
      // If asking about something mentioned in search, it's a question
      queryIntent = 'question';
    } else if (!hasSearchIntent && !hasQuestionIntent && isSearchContinuation) {
      // Ambiguous but in search context, assume search
      queryIntent = 'search';
    } else if (!hasSearchIntent && !hasQuestionIntent) {
      // Completely ambiguous, try to infer from context
      queryIntent = previousQueries.length > 0 ? 'search' : 'question';
    }
    
    let userPrompt = "";
    if (queryIntent === 'search') {
      userPrompt = `Find songs matching this description: "${queryText}"${audioTranscription ? `\n\nBackground audio from video transcribed as: "${audioTranscription}"` : ""}

${contextText ? `\n\nCONVERSATION CONTEXT:\n${contextText}\n` : ""}

INSTRUCTIONS:
- Search the web thoroughly using multiple sources
- Verify song titles, artist names, and lyrics from official sources
- ${audioTranscription ? "Use the audio transcription as additional context to identify the song playing in the background." : ""}
- Return the most accurate matches with high confidence scores
- Include exact lyric snippets when available
- Provide detailed reasons for each match
- Rank by confidence (most likely first)
- Set response_type to "search"

Return the best matches as JSON.`;
    } else if (queryIntent === 'question') {
      userPrompt = `Answer this music-related question: "${queryText}"

${contextText ? `\n\nCONVERSATION CONTEXT:\n${contextText}\n` : ""}

INSTRUCTIONS:
- Search the web thoroughly to find accurate, current information
- Provide a comprehensive, detailed answer
- Cite your sources in the sources array
- If relevant, suggest related songs in related_songs array
- Be conversational and natural in tone
- Set response_type to "answer"
- Include answer object with text, sources, and optionally related_songs

Return your answer as JSON.`;
    } else if (queryIntent === 'both') {
      // both
      userPrompt = `The user wants both to search for songs and get information. Query: "${queryText}"${audioTranscription ? `\n\nBackground audio from video transcribed as: "${audioTranscription}"` : ""}

${contextText ? `\n\nCONVERSATION CONTEXT:\n${contextText}\n` : ""}

INSTRUCTIONS:
- First, search for songs matching the description
- Then, answer any questions about the songs, artists, or related topics
- Return both candidates array (for search) and answer object (for questions)
- Set response_type to "both"
- Provide comprehensive information in both candidates and answer

Return both search results and answers as JSON.`;
    }

    const openaiStepTime = Date.now();
    console.log(`🔍 [RECALL-RESOLVE] Calling OpenAI API...`);
    console.log(`📝 [RECALL-RESOLVE] Detected query intent: ${queryIntent}`);
    console.log(`📝 [RECALL-RESOLVE] User prompt length: ${userPrompt.length} chars`);
    console.log(`📝 [RECALL-RESOLVE] System prompt length: ${systemPrompt.length} chars`);
    
    console.log(`🤖 [GPT-4o] Calling OpenAI GPT-4o API for ${queryIntent} response...`);
    console.log(`📝 [GPT-4o] User prompt length: ${userPrompt.length} chars`);
    const openaiResponse = await openAICircuitBreaker.execute(() =>
      fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${openaiApiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: "gpt-4o",
          messages: [
            { role: "system", content: systemPrompt },
            { role: "user", content: userPrompt },
          ],
          response_format: { type: "json_object" },
          temperature: 0.3,
        })
      })
    );

    const openaiResponseTime = Date.now() - openaiStepTime;
    console.log(`⏱️ [RECALL-RESOLVE] OpenAI API call took: ${openaiResponseTime}ms`);

    if (!openaiResponse.ok) {
      const errorText = await openaiResponse.text();
      console.error(`❌ [RECALL-RESOLVE] OpenAI API error (${openaiResponse.status}):`, errorText);
      await supabase
        .from("recall_messages")
        .update({
          message_type: "status",
          text: `Error: ${errorText}`,
        })
        .eq("id", statusMessage.id);
      return new Response(
        JSON.stringify({ error: "OpenAI API request failed", details: errorText }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const parseStepTime = Date.now();
    const openaiData = await openaiResponse.json();
    const content = openaiData.choices[0]?.message?.content;
    const parseDuration = Date.now() - parseStepTime;
    console.log(`⏱️ [RECALL-RESOLVE] [${requestId}] Parse OpenAI response: ${parseDuration}ms`);
    console.log(`📄 [RECALL-RESOLVE] [${requestId}] Response content length: ${content?.length || 0} chars`);
    console.log(`📄 [RECALL-RESOLVE] [${requestId}] Response preview: ${content?.substring(0, 200)}...`);
    if (openaiData.usage) {
      console.log(`📊 [RECALL-RESOLVE] [${requestId}] Token usage: prompt=${openaiData.usage.prompt_tokens}, completion=${openaiData.usage.completion_tokens}, total=${openaiData.usage.total_tokens}`);
    }

    if (!content) {
      await supabase
        .from("recall_messages")
        .update({
          message_type: "status",
          text: "OpenAI returned empty response",
        })
        .eq("id", statusMessage.id);
      return new Response(
        JSON.stringify({ error: "OpenAI returned empty response" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Parse OpenAI response
    const parseJsonTime = Date.now();
    let aiResult: OpenAIResponse;
    try {
      // Try to extract JSON from markdown code blocks if present
      let jsonContent = content;
      const jsonMatch = content.match(/```(?:json)?\s*([\s\S]*?)\s*```/);
      if (jsonMatch && jsonMatch[1]) {
        jsonContent = jsonMatch[1].trim();
        console.log(`📝 [RECALL-RESOLVE] Extracted JSON from code block`);
      }
      
      aiResult = JSON.parse(jsonContent);
      console.log(`⏱️ [RECALL-RESOLVE] Parse JSON: ${Date.now() - parseJsonTime}ms`);
      console.log(`📊 [RECALL-RESOLVE] [${requestId}] Parsed result: type=${aiResult.response_type}, confidence=${aiResult.overall_confidence}, candidates=${aiResult.candidates?.length || 0}, has_answer=${!!aiResult.answer}`);
      
      // Validate response structure
      if (!aiResult.response_type) {
        // If intent was information, default to answer; otherwise search
        if (detectedIntent?.type === "information") {
          console.warn(`⚠️ [RECALL-RESOLVE] Missing response_type, defaulting to 'answer' for information intent`);
          aiResult.response_type = 'answer';
        } else {
          console.warn(`⚠️ [RECALL-RESOLVE] Missing response_type, defaulting to 'search'`);
          aiResult.response_type = 'search';
        }
      }
      
      // Ensure information intents always have answer object
      if (detectedIntent?.type === "information" && aiResult.response_type === "answer") {
        if (!aiResult.answer || !aiResult.answer.text || aiResult.answer.text.trim().length === 0) {
          console.warn(`⚠️ [RECALL-RESOLVE] Information intent but no answer provided, creating fallback answer`);
          aiResult.answer = {
            text: "I'm processing your question. Please wait a moment while I search for the information.",
            sources: [],
            related_songs: []
          };
        }
      }
      
      if (aiResult.overall_confidence === undefined || aiResult.overall_confidence === null) {
        console.warn(`⚠️ [RECALL-RESOLVE] Missing overall_confidence, calculating from candidates`);
        if (aiResult.candidates && aiResult.candidates.length > 0) {
          aiResult.overall_confidence = aiResult.candidates[0].confidence;
        } else if (aiResult.answer && aiResult.answer.text) {
          // For answer responses, use high confidence if answer exists
          aiResult.overall_confidence = 0.8;
        } else {
          aiResult.overall_confidence = 0.5;
        }
      }
      
      // Log detailed candidate info
      if (aiResult.candidates && aiResult.candidates.length > 0) {
        console.log(`🎵 [RECALL-RESOLVE] Top candidate: "${aiResult.candidates[0].title}" by ${aiResult.candidates[0].artist} (confidence: ${aiResult.candidates[0].confidence})`);
        // Validate candidate structure
        aiResult.candidates = aiResult.candidates.filter(c => {
          const isValid = c.title && c.artist && typeof c.confidence === 'number';
          if (!isValid) {
            console.warn(`⚠️ [RECALL-RESOLVE] Invalid candidate filtered out:`, c);
          }
          return isValid;
        });
        console.log(`✅ [RECALL-RESOLVE] Valid candidates after filtering: ${aiResult.candidates.length}`);
      }
      
      // Log answer info
      if (aiResult.answer) {
        console.log(`📝 [RECALL-RESOLVE] Answer length: ${aiResult.answer.text.length} chars, sources: ${aiResult.answer.sources.length}`);
        if (!aiResult.answer.text || aiResult.answer.text.trim().length === 0) {
          console.warn(`⚠️ [RECALL-RESOLVE] Answer text is empty, removing answer`);
          aiResult.answer = undefined;
        }
      }
    } catch (parseError) {
      console.error(`❌ [RECALL-RESOLVE] Failed to parse OpenAI response:`, parseError);
      console.error(`❌ [RECALL-RESOLVE] Response content (first 1000 chars):`, content?.substring(0, 1000));
      await supabase
        .from("recall_messages")
        .update({
          message_type: "status",
          text: `Failed to parse AI response: ${parseError.message}`,
        })
        .eq("id", statusMessage.id);
      return new Response(
        JSON.stringify({ error: "Failed to parse OpenAI response", details: parseError.message }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Validate and deduplicate candidates
    const validateTime = Date.now();
    const candidates = aiResult.candidates || [];
    console.log(`🔍 [RECALL-RESOLVE] Validating ${candidates.length} candidates...`);
    
    // Log raw candidates for debugging
    if (candidates.length > 0) {
      console.log(`📋 [RECALL-RESOLVE] Raw candidates from AI:`);
      candidates.forEach((c, i) => {
        console.log(`   ${i + 1}. "${c.title}" by ${c.artist} (confidence: ${c.confidence})`);
      });
    }
    
    const uniqueCandidates = new Map<string, Candidate>();
    
    for (const candidate of candidates) {
      // Validate candidate has required fields
      if (!candidate.title || !candidate.artist) {
        console.log(`⚠️ [RECALL-RESOLVE] Skipping invalid candidate: missing title or artist`);
        continue;
      }
      
      const key = `${candidate.title.toLowerCase().trim()}|${candidate.artist.toLowerCase().trim()}`;
      if (!uniqueCandidates.has(key) || uniqueCandidates.get(key)!.confidence < candidate.confidence) {
        uniqueCandidates.set(key, candidate);
      }
    }

    const finalCandidates = Array.from(uniqueCandidates.values())
      .sort((a, b) => b.confidence - a.confidence)
      .slice(0, 5); // Top 5 candidates
    
    console.log(`⏱️ [RECALL-RESOLVE] Validation: ${Date.now() - validateTime}ms`);
    console.log(`📊 [RECALL-RESOLVE] Final candidates: ${finalCandidates.length} (from ${candidates.length} original)`);
    
    if (finalCandidates.length > 0) {
      console.log(`🎵 [RECALL-RESOLVE] Top candidate: "${finalCandidates[0].title}" by ${finalCandidates[0].artist} (confidence: ${finalCandidates[0].confidence})`);
      if (finalCandidates[0].reason) {
        console.log(`   Reason: ${finalCandidates[0].reason.substring(0, 100)}...`);
      }
    }

    // Only fail if we have NO candidates AND NO answer
    // Exception: For information intents, we should always have an answer
    if (finalCandidates.length === 0 && (!aiResult.answer || !aiResult.answer.text)) {
      // If this was an information intent, try to generate a basic answer
      if (detectedIntent?.type === "information") {
        console.log(`⚠️ [RECALL-RESOLVE] Information intent but no answer found, creating fallback`);
        aiResult.answer = {
          text: "I couldn't find specific information about that. Could you provide more details or rephrase your question?",
          sources: [],
          related_songs: []
        };
        aiResult.response_type = "answer";
        aiResult.overall_confidence = 0.3;
      } else {
        console.log(`⚠️ [RECALL-RESOLVE] No valid candidates or answer found`);
        await supabase
          .from("recall_messages")
          .update({
            message_type: "status",
            text: "No matches found",
          })
          .eq("id", statusMessage.id);
        return new Response(
          JSON.stringify({ status: "failed", error: "No candidates or answer found" }),
          { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    }

    // Build assistant message only if we have candidates (for song identification)
    // For conversational queries, we'll have an answer instead
    let assistantMessage: AssistantMessage | undefined;
    
    if (finalCandidates.length > 0) {
      // Get top candidate for response (for backward compatibility)
      const topCandidate = finalCandidates[0];

      // Build sources array for top candidate
      const sources = topCandidate.source_urls.map((url, index) => ({
        title: `Source ${index + 1}`,
        url,
        snippet: undefined,
      }));

      // Build assistant message with all candidates
      assistantMessage = {
        message_type: "candidate",
        song_title: topCandidate.title,
        song_artist: topCandidate.artist,
        confidence: topCandidate.confidence,
        reason: topCandidate.reason || "Matched based on description",
        lyric_snippet: topCandidate.highlight_snippet,
        sources,
        all_candidates: finalCandidates.map(c => ({
          title: c.title,
          artist: c.artist,
          confidence: c.confidence,
          reason: c.reason || "",
          background: c.background || "",
          lyric_snippet: c.highlight_snippet,
          source_urls: c.source_urls,
        })),
      };
    }

    // 1. Insert ANSWER first so the user sees the response to their question before suggestions or follow-up
    const insertAnswerTime = Date.now();
    let answerMessageId: string | null = null;
    if (aiResult.answer && (aiResult.response_type === "answer" || aiResult.response_type === "both")) {
      console.log(`📝 [RECALL-RESOLVE] Inserting answer message (first)...`);
      
      let enhancedAnswerText = aiResult.answer.text;
      let enhancedSources = [...aiResult.answer.sources];
      
      const meaningQuery = detectSongMeaningQuery(queryText, finalCandidates, previousMessages);
      
      if (meaningQuery.isSongMeaningQuery) {
        const songTitle = meaningQuery.songTitle || (finalCandidates.length > 0 ? finalCandidates[0].title : undefined);
        const artistName = meaningQuery.artistName || (finalCandidates.length > 0 ? finalCandidates[0].artist : undefined);
        
        if (songTitle && artistName) {
          console.log(`🎵 [LYRICS] Detected song meaning query for "${songTitle}" by ${artistName}, fetching lyrics from lyrics.ovh...`);
          
          try {
            const lyricsResult = await fetchLyricsFromGenius(songTitle, artistName);
            
            if (lyricsResult.success && lyricsResult.lyrics) {
              console.log(`✅ [LYRICS] Successfully fetched lyrics (${lyricsResult.lyrics.length} chars)`);
              
              const detectedLanguage = await detectLanguage(lyricsResult.lyrics, openaiApiKey);
              console.log(`🌍 [LANG] Detected language: ${detectedLanguage}`);
              
              const summary = await summarizeSongMessage(lyricsResult.lyrics, detectedLanguage, openaiApiKey);
              
              const isEnglish = detectedLanguage.toLowerCase().includes("english");
              
              if (isEnglish) {
                enhancedAnswerText = `${enhancedAnswerText}\n\n**Song Summary:** ${summary.summary}`;
              } else {
                enhancedAnswerText = `${enhancedAnswerText}\n\n**Song Summary (${detectedLanguage}):** ${summary.summary}`;
                if (summary.englishTranslation) {
                  enhancedAnswerText = `${enhancedAnswerText}\n\n**In English:** ${summary.englishTranslation}`;
                }
              }
              
              if (lyricsResult.sourceUrl) {
                enhancedSources.push(lyricsResult.sourceUrl);
              }
              
              console.log(`✅ [LYRICS] Enhanced answer with lyrics summary`);
            } else {
              console.log(`⚠️ [LYRICS] Could not fetch lyrics: ${lyricsResult.error || "Unknown error"}`);
            }
          } catch (lyricsError) {
            console.error(`❌ [LYRICS] Error fetching/processing lyrics:`, lyricsError);
          }
        } else {
          console.log(`⚠️ [LYRICS] Song meaning query detected but couldn't determine song title/artist`);
        }
      }
      
      const answerSources = enhancedSources.map((url, index) => ({
        title: `Source ${index + 1}`,
        url,
        snippet: undefined,
      }));

      const { data: answerMessage, error: answerError } = await supabase
        .from("recall_messages")
        .insert({
          thread_id,
          user_id: userMessage.user_id,
          role: "assistant",
          message_type: "answer",
          text: enhancedAnswerText,
          sources_json: answerSources,
        })
        .select("id")
        .single();

      if (!answerError && answerMessage) {
        answerMessageId = answerMessage.id;
        console.log(`✅ [RECALL-RESOLVE] [${requestId}] Inserted answer message (${aiResult.answer.text.length} chars)`);
      } else {
        console.error(`❌ [RECALL-RESOLVE] [${requestId}] Failed to insert answer:`, answerError);
      }
    }
    console.log(`⏱️ [RECALL-RESOLVE] [${requestId}] Insert answer: ${Date.now() - insertAnswerTime}ms`);

    // 2. Insert candidates (song suggestion cards) after the answer
    const { data: existingCandidates } = await supabase
      .from("recall_messages")
      .select("song_title, song_artist")
      .eq("thread_id", thread_id)
      .eq("message_type", "candidate");

    const existingKeys = new Set(
      (existingCandidates || [])
        .filter(c => c.song_title && c.song_artist)
        .map(c => `${c.song_title.toLowerCase()}|${c.song_artist.toLowerCase()}`)
    );

    const insertCandidatesTime = Date.now();
    let insertedCount = 0;
    for (const candidate of finalCandidates) {
      const candidateKey = `${candidate.title.toLowerCase()}|${candidate.artist.toLowerCase()}`;
      if (!existingKeys.has(candidateKey)) {
        const candidateSources = candidate.source_urls.map((url, index) => ({
          title: `Source ${index + 1}`,
          url,
          snippet: undefined,
        }));

        await supabase
          .from("recall_messages")
          .insert({
            thread_id,
            user_id: userMessage.user_id,
            role: "assistant",
            message_type: "candidate",
            text: `${candidate.title} by ${candidate.artist}`,
            candidate_json: {
              title: candidate.title,
              artist: candidate.artist,
              confidence: candidate.confidence,
              reason: candidate.reason,
              background: candidate.background,
              lyric_snippet: candidate.highlight_snippet,
            },
            sources_json: candidateSources,
            confidence: candidate.confidence,
            song_title: candidate.title,
            song_artist: candidate.artist,
          });
        insertedCount++;
      }
    }
    console.log(`⏱️ [RECALL-RESOLVE] Insert candidates: ${Date.now() - insertCandidatesTime}ms (inserted: ${insertedCount})`);

    // Handle follow-up question if confidence is low or conversation needs continuation
    const insertFollowUpTime = Date.now();
    let followUpQuestionId: string | null = null;
    if (aiResult.follow_up_question && (aiResult.overall_confidence < 0.7 || aiResult.response_type === "answer")) {
      console.log(`💬 [RECALL-RESOLVE] [${requestId}] Inserting follow-up question: "${aiResult.follow_up_question}"`);
      // Insert follow-up question as assistant message
      const { data: followUpMessage, error: followUpError } = await supabase
        .from("recall_messages")
        .insert({
          thread_id,
          user_id: userMessage.user_id,
          role: "assistant",
          message_type: "follow_up",
          text: aiResult.follow_up_question,
        })
        .select("id")
        .single();

      if (!followUpError && followUpMessage) {
        followUpQuestionId = followUpMessage.id;
        console.log(`✅ [RECALL-RESOLVE] [${requestId}] Inserted follow-up question`);
      } else {
        console.error(`❌ [RECALL-RESOLVE] [${requestId}] Failed to insert follow-up:`, followUpError);
      }
    }
    console.log(`⏱️ [RECALL-RESOLVE] [${requestId}] Insert follow-up: ${Date.now() - insertFollowUpTime}ms`);

    // Delete status message (replaced by candidate messages, answer, or follow-up question)
    await supabase
      .from("recall_messages")
      .delete()
      .eq("id", statusMessage.id);

    // Update thread last_message_at
    await supabase
      .from("recall_threads")
      .update({ last_message_at: new Date().toISOString() })
      .eq("id", thread_id);

    // Only upsert to stash if we have candidates with high enough confidence
    if (finalCandidates.length > 0 && finalCandidates[0].confidence >= 0.7) {
      const topCandidate = finalCandidates[0];
      await supabase
        .from("recall_stash")
        .upsert({
          user_id: userMessage.user_id,
          thread_id,
          top_song_title: topCandidate.title,
          top_song_artist: topCandidate.artist,
          top_confidence: topCandidate.confidence,
          top_song_url: null,
        }, {
          onConflict: "user_id,thread_id",
        });
    }

    // Log service calls for verification
    const totalDuration = Date.now() - requestStartTime;
    console.log(`📊 [RECALL-RESOLVE] [${requestId}] Service calls summary:`);
    const acrCloudStatus = audioRecognitionResult?.service === "acrcloud" ? "✅ Called and matched" : "⏭️ Skipped or no match";
    console.log(`   - ACRCloud: ${acrCloudStatus}`);
    console.log(`   - Shazam: ${audioRecognitionResult?.service === "shazam" ? "✅ Called and matched" : "⏭️ Called but no match or skipped"}`);
    console.log(`   - Whisper Transcription: ${audioTranscription ? "✅ Transcribed: \"" + audioTranscription.substring(0, 50) + "...\"" : "⏭️ Not used"}`);
    console.log(`   - GPT-4o: ✅ Called for ${aiResult.response_type || "search"} response`);
    console.log(`   - Final candidates: ${finalCandidates.length}`);
    if (aiResult.answer) {
      console.log(`   - Answer provided: ${aiResult.answer.text.length} chars`);
    }
    console.log(`⏱️ [RECALL-RESOLVE] [${requestId}] Total processing time: ${totalDuration}ms`);
    
    const responseBody = {
      status: aiResult.follow_up_question ? "refining" : "done",
      response_type: aiResult.response_type || "search",
      transcription: audioTranscription || null, // Include transcription in response
      overall_confidence: aiResult.overall_confidence,
      candidates: finalCandidates.map(c => ({
        title: c.title,
        artist: c.artist,
        confidence: c.confidence,
        reason: c.reason,
        background: c.background || "",
        lyric_snippet: c.highlight_snippet,
        source_urls: c.source_urls,
      })),
      answer: aiResult.answer ? {
        text: aiResult.answer.text,
        sources: aiResult.answer.sources,
        related_songs: aiResult.answer.related_songs || [],
      } : null,
      follow_up_question: aiResult.follow_up_question || null,
      conversation_state: aiResult.conversation_state || (aiResult.follow_up_question ? "refining_search" : (aiResult.response_type === "answer" ? "answering" : "searching")),
      error: null,
    };
    
    const responseSize = JSON.stringify(responseBody).length;
    console.log(`📤 [RECALL-RESOLVE] [${requestId}] Returning response: ${responseSize} bytes`);
    console.log(`   status: ${responseBody.status}`);
    console.log(`   response_type: ${responseBody.response_type}`);
    console.log(`   candidates: ${responseBody.candidates.length}`);
    console.log(`   has_answer: ${responseBody.answer != null}`);
    console.log(`   has_follow_up: ${responseBody.follow_up_question != null}`);

    const responseBodyStr = JSON.stringify(responseBody);
    const responseInit = { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } };
    return new Response(responseBodyStr, responseInit);
  } catch (error) {
    console.error("Error in recall-resolve:", error);
    
    // Try to return transcription even on error if we have it
    let errorTranscription = "";
    try {
      // If we have audioTranscription from earlier processing, include it
      if (typeof audioTranscription !== "undefined" && audioTranscription) {
        errorTranscription = audioTranscription;
      }
    } catch (e) {
      // Ignore errors accessing audioTranscription
    }
    
    return new Response(
      JSON.stringify({ 
        error: "Internal server error", 
        details: error.message,
        transcription: errorTranscription || null,
        status: "failed"
      }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } finally {
    // Release rate limit in finally block to ensure it's always released
    if (userId) {
      await releaseRateLimit(userId);
    }
  }
});

