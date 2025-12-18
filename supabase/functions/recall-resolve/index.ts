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
  type: "conversation" | "humming" | "background_audio" | "unclear";
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

    const response = await fetch("https://api.openai.com/v1/chat/completions", {
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
  "type": "conversation" | "humming" | "background_audio" | "unclear",
  "confidence": 0.0-1.0,
  "reasoning": "brief explanation"
}

Intent Types:
- "conversation": User is speaking naturally, asking questions, or having a conversation about music. Includes information questions, music recommendations, artist queries, song information requests, or any clear verbal communication.
- "humming": User is humming, singing, or vocalizing a melody without clear words. Characterized by repetitive sounds, vowel sounds, or musical vocalizations.
- "background_audio": Transcription is unclear, garbled, or contains [inaudible]/[music] tags, suggesting background music playing rather than speech.
- "unclear": Cannot determine with confidence (mixed signals, ambiguous content, or very short unclear input).

Key Detection Rules (apply in order):

1. INFORMATION QUESTIONS (→ conversation):
   - Question words: "who", "what", "when", "where", "why", "how", "which", "can you", "tell me", "explain", "describe"
   - Information requests: "about", "information", "details", "history", "biography", "facts", "story"
   - Recommendation requests: "recommend", "suggest", "similar to", "like", "playlist", "genre"
   - Comparison requests: "compare", "difference", "better", "best", "top", "favorite"
   - If transcription contains complete sentences with proper grammar → conversation
   - If transcription has >10 words with structure → conversation

2. SONG IDENTIFICATION REQUESTS (→ conversation):
   - "What song is this?", "What's this song?", "Name this song", "Identify this", "Find this song"
   - "I'm looking for", "I need to find", "Can you find", "Help me find"
   - These are still conversation because they're clear verbal requests, even if asking about song identification

3. HUMMING PATTERNS (→ humming):
   - Repetitive sounds: "hmm", "la", "da", "mm", "ah", "na", "oh", "doo", "dum", "bum", "ba", "pa"
   - Vowel-only sounds: "aa", "ee", "oo", "ii", "uu"
   - Musical syllables: "do re mi", "fa sol la", "ti do"
   - Pattern: <5 words + repetitive sounds = likely humming
   - Pattern: Same sound repeated 3+ times = likely humming
   - Pattern: No recognizable words, only sounds = humming

4. BACKGROUND AUDIO (→ background_audio):
   - Transcription artifacts: [music], [inaudible], [background noise], [unintelligible], [garbled]
   - Very short unclear text: <3 words that don't form sentences
   - Mixed signals: Contains both speech and [music] tags

5. CONFIDENCE THRESHOLDS:
   - conversation: confidence >= 0.7 if clear question/information request
   - humming: confidence >= 0.8 if repetitive sounds pattern is clear
   - background_audio: confidence >= 0.7 if transcription artifacts present
   - unclear: confidence < 0.6 for any type

Examples:
- "Tell me about The Beatles" → conversation (0.95) - clear information question
- "Who wrote Bohemian Rhapsody?" → conversation (0.95) - clear information question
- "What song is this?" → conversation (0.9) - clear question asking for identification
- "Can you recommend some jazz music?" → conversation (0.95) - clear recommendation request
- "What's the difference between rock and pop?" → conversation (0.95) - clear comparison question
- "hmm hmm hmm da da da" → humming (0.9) - repetitive sounds pattern
- "la la la la la la" → humming (0.95) - clear humming pattern
- "mm mm ah ah na na" → humming (0.85) - vowel sounds only
- "[inaudible] [music] [background noise]" → background_audio (0.9) - transcription artifacts
- "I'm looking for a song that goes like..." → conversation (0.85) - clear speech pattern with request
- "do re mi fa sol" → humming (0.8) - musical syllables
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
    });

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

serve(async (req) => {
  const requestStartTime = Date.now();
  console.log(`\n🚀 [RECALL-RESOLVE] Request started at ${new Date().toISOString()}`);
  
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const step1Time = Date.now();
    // Get authorization header
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      console.log("❌ [RECALL-RESOLVE] Missing authorization header");
      return new Response(
        JSON.stringify({ error: "Missing authorization header" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Initialize Supabase client
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);
    console.log(`⏱️ [RECALL-RESOLVE] Step 1 - Initialization: ${Date.now() - step1Time}ms`);

    const step2Time = Date.now();
    // Parse request body
    const body: RecallResolveRequest = await req.json();
    const { thread_id, message_id, input_type, text, media_path, audio_path, video_path } = body;
    console.log(`⏱️ [RECALL-RESOLVE] Step 2 - Parse body: ${Date.now() - step2Time}ms`);
    console.log(`📋 [RECALL-RESOLVE] Input: type=${input_type}, text="${text?.substring(0, 50)}...", has_media=${!!media_path}`);

    if (!thread_id || !message_id || !input_type) {
      return new Response(
        JSON.stringify({ error: "thread_id, message_id, and input_type are required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Load user message
    const { data: userMessage, error: messageError } = await supabase
      .from("recall_messages")
      .select("*")
      .eq("id", message_id)
      .eq("thread_id", thread_id)
      .single();

    if (messageError || !userMessage) {
      return new Response(
        JSON.stringify({ error: "Message not found", details: messageError?.message }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Insert "Searching..." status message
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
      return new Response(
        JSON.stringify({ error: "Failed to create status message", details: statusError?.message }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    let queryText = text || userMessage.text || "";
    let audioTranscription = "";
    const openaiApiKey = Deno.env.get("OPENAI_API_KEY");
    const mediaPathToUse = video_path || media_path;
    let shouldUseAudioRecognition = false;
    let audioRecognitionResult: AudioRecognitionResult | null = null;

    // ============================================
    // NEW INTELLIGENT VOICE PROCESSING FLOW
    // ============================================
    
    if (input_type === "voice" && mediaPathToUse) {
      try {
        console.log("🎤 [VOICE-PROCESSING] Starting intelligent voice processing...");
        
        // Get audio file
        const bucket = video_path ? "recall-images" : "recall-audio";
        const { data: signedUrlData, error: urlError } = await supabase.storage
          .from(bucket)
          .createSignedUrl(mediaPathToUse, 3600);

        if (urlError || !signedUrlData) {
          throw new Error("Failed to create signed URL for audio");
        }

        const audioResponse = await fetch(signedUrlData.signedUrl);
        const audioBlob = await audioResponse.blob();
        const audioArrayBuffer = await audioBlob.arrayBuffer();

        // STEP 1: ALWAYS transcribe first to understand user intent
        console.log("📝 [STEP 1] Transcribing with Whisper...");
        
        if (openaiApiKey) {
          const audioFile = new File([audioBlob], "audio.m4a", { type: "audio/m4a" });
          const formData = new FormData();
          formData.append("file", audioFile);
          formData.append("model", "whisper-1");

          const transcriptionResponse = await fetch("https://api.openai.com/v1/audio/transcriptions", {
            method: "POST",
            headers: {
              "Authorization": `Bearer ${openaiApiKey}`,
            },
            body: formData,
          });

          if (transcriptionResponse.ok) {
            const transcriptionData = await transcriptionResponse.json();
            audioTranscription = transcriptionData.text || "";
            console.log(`✅ Transcription: "${audioTranscription}"`);
            
            // Update status
            await supabase
              .from("recall_messages")
              .update({ text: "Understanding..." })
              .eq("id", statusMessage.id);
          }
        }

        // STEP 2: Analyze intent - conversation or song identification?
        if (audioTranscription && audioTranscription.trim().length > 0) {
          console.log("🧠 [STEP 2] Analyzing intent...");
          
          const intent = await analyzeVoiceIntent(audioTranscription, openaiApiKey!);
          
          if (intent.type === "humming" || intent.type === "background_audio") {
            shouldUseAudioRecognition = true;
            console.log(`🎵 Intent: ${intent.type} → Using audio recognition`);
            
            await supabase
              .from("recall_messages")
              .update({ text: "Identifying song..." })
              .eq("id", statusMessage.id);
              
          } else if (intent.type === "conversation") {
            shouldUseAudioRecognition = false;
            queryText = audioTranscription;
            console.log(`💬 Intent: conversation → Using conversational response`);
            
            await supabase
              .from("recall_messages")
              .update({ text: "Thinking..." })
              .eq("id", statusMessage.id);
              
          } else {
            // Unclear - use heuristics
            const wordCount = audioTranscription.split(/\s+/).length;
            const hasRepetitiveSounds = /\b(hmm|la|da|mm|ah|na|oh)\b/gi.test(audioTranscription);
            const repetitiveCount = (audioTranscription.match(/\b(hmm|la|da|mm|ah|na|oh)\b/gi) || []).length;
            
            if (wordCount < 5 || (hasRepetitiveSounds && repetitiveCount > 3)) {
              shouldUseAudioRecognition = true;
              console.log(`🤔 Unclear intent, but heuristics suggest audio recognition (words:${wordCount}, repetitive:${repetitiveCount})`);
              
              await supabase
                .from("recall_messages")
                .update({ text: "Identifying song..." })
                .eq("id", statusMessage.id);
            } else {
              queryText = audioTranscription;
              console.log(`🤔 Unclear intent, treating as conversation (words:${wordCount})`);
              
              await supabase
                .from("recall_messages")
                .update({ text: "Thinking..." })
                .eq("id", statusMessage.id);
            }
          }
        } else {
          // No transcription - likely background music or humming
          shouldUseAudioRecognition = true;
          console.log("⚠️ No transcription, defaulting to audio recognition");
          
          await supabase
            .from("recall_messages")
            .update({ text: "Identifying song..." })
            .eq("id", statusMessage.id);
        }

        // STEP 3: Use audio recognition if needed
        if (shouldUseAudioRecognition) {
          console.log("🎵 [STEP 3] Running audio recognition (ACRCloud + Shazam in parallel)...");
          
          const [acrCloudResult, shazamResult] = await Promise.allSettled([
            identifyAudioWithACRCloud(audioArrayBuffer),
            identifyAudioWithShazam(audioArrayBuffer),
          ]);

          // Choose best result
          let bestResult: AudioRecognitionResult | null = null;

          if (acrCloudResult.status === "fulfilled" && acrCloudResult.value.success) {
            bestResult = acrCloudResult.value;
            console.log(`✅ ACRCloud: ${bestResult.title} by ${bestResult.artist} (${bestResult.confidence})`);
          }

          if (shazamResult.status === "fulfilled" && shazamResult.value.success) {
            const shazamBest = shazamResult.value;
            console.log(`✅ Shazam: ${shazamBest.title} by ${shazamBest.artist} (${shazamBest.confidence})`);
            if (!bestResult || shazamBest.confidence > bestResult.confidence) {
              bestResult = shazamBest;
            }
          }

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

        // Update user message with transcription
        if (audioTranscription) {
          await supabase
            .from("recall_messages")
            .update({ text: audioTranscription })
            .eq("id", message_id);
        }

      } catch (error) {
        console.error("❌ Voice processing error:", error);
        queryText = "I had trouble processing the audio. Could you try again or describe what you're looking for?";
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
          }
        }
      } catch (error) {
        console.error("Error transcribing video audio:", error);
        // Continue without transcription if it fails
      }
    }

    // If image input, extract text (OCR would go here - simplified for now)
    if (input_type === "image" && !queryText && !audioTranscription) {
      queryText = "Image uploaded - searching for matching songs";
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
3. **Music Theory**: Explain music concepts, terminology, and theory
4. **Comparisons**: Compare songs, artists, albums, or genres
5. **Recommendations**: Suggest similar songs, artists, or playlists
6. **Contextual Understanding**: Understand when users want to search vs. ask questions, and respond appropriately

CRITICAL RULES FOR MAXIMUM ACCURACY:
1. **INTENT DETECTION**: First, determine the user's intent:
   - "search" - User wants to find/identify a song (keywords: "find", "search", "identify", "what song", "name that song", "who sings")
   - "question" - User wants information about music (keywords: "who wrote", "when was", "what album", "tell me about", "explain", "how", "why")
   - "both" - User wants both search and information (e.g., "find that song and tell me about the artist")

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
  "follow_up_question": "Natural conversational question to help refine search or continue conversation (only if overall_confidence < 0.7 or conversation needs continuation)",
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
   - Provide comprehensive, accurate answers based on web search
   - Include relevant facts, dates, and context
   - Cite sources in the sources array
   - If relevant, suggest related songs in related_songs array
   - Be conversational and natural in tone - write as if speaking to the user directly
   - Use first person ("I found...", "Based on...") to make it feel like a real conversation
   - Keep answers concise but informative (2-4 sentences for most questions)
   - For complex topics, break into digestible chunks
   - Always respond with voice-friendly text (avoid complex formatting, use natural pauses)

9. Provide up to 5 candidates for search queries, ranked by confidence (highest first)
10. Deduplicate candidates (same title+artist = one entry, keep highest confidence)
11. highlight_snippet must be an exact lyric quote or memorable line (not a description)
12. source_urls must include at least 3 verified sources from reputable music platforms
13. background field is REQUIRED for all candidates - provide meaningful context
14. If overall_confidence < 0.65, set should_ask_crowd to true and provide a helpful crowd_prompt
15. If overall_confidence < 0.7 and candidates are weak, set follow_up_question and conversation_state to "refining_search"
16. Be extremely specific and accurate - verify all information via web search before returning
17. If the user query is vague, search for multiple interpretations and return the most likely matches
18. Consider alternative spellings, common misheard lyrics, and similar-sounding artists
19. Include confidence scores that reflect actual certainty based on available information and search results
20. Track conversation context to avoid repeating follow-up questions
21. For general music questions, provide detailed, informative answers with proper citations`;

    // Get conversation context for better accuracy
    const { data: previousMessages } = await supabase
      .from("recall_messages")
      .select("text, role, message_type, song_title, song_artist, confidence, created_at")
      .eq("thread_id", thread_id)
      .order("created_at", { ascending: false })
      .limit(20);
    
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
    
    let detectedIntent: 'search' | 'question' | 'both' = 'search';
    if (hasQuestionIntent && !hasSearchIntent) {
      detectedIntent = 'question';
    } else if (hasSearchIntent && hasQuestionIntent) {
      detectedIntent = 'both';
    } else if (hasQuestionIntent && isSearchContinuation) {
      // If asking about something mentioned in search, it's a question
      detectedIntent = 'question';
    } else if (!hasSearchIntent && !hasQuestionIntent && isSearchContinuation) {
      // Ambiguous but in search context, assume search
      detectedIntent = 'search';
    } else if (!hasSearchIntent && !hasQuestionIntent) {
      // Completely ambiguous, try to infer from context
      detectedIntent = previousQueries.length > 0 ? 'search' : 'question';
    }
    
    let userPrompt = "";
    if (detectedIntent === 'search') {
      userPrompt = `Find songs matching this description: "${queryText}"${audioTranscription ? `\n\nBackground audio from video transcribed as: "${audioTranscription}"` : ""}${contextText}

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
    } else if (detectedIntent === 'question') {
      userPrompt = `Answer this music-related question: "${queryText}"${contextText}

INSTRUCTIONS:
- Search the web thoroughly to find accurate, current information
- Provide a comprehensive, detailed answer
- Cite your sources in the sources array
- If relevant, suggest related songs in related_songs array
- Be conversational and natural in tone
- Set response_type to "answer"
- Include answer object with text, sources, and optionally related_songs

Return your answer as JSON.`;
    } else {
      // both
      userPrompt = `The user wants both to search for songs and get information. Query: "${queryText}"${audioTranscription ? `\n\nBackground audio from video transcribed as: "${audioTranscription}"` : ""}${contextText}

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
    console.log(`📝 [RECALL-RESOLVE] Detected intent: ${detectedIntent}`);
    console.log(`📝 [RECALL-RESOLVE] User prompt length: ${userPrompt.length} chars`);
    console.log(`📝 [RECALL-RESOLVE] System prompt length: ${systemPrompt.length} chars`);
    
    console.log(`🤖 [GPT-4o] Calling OpenAI GPT-4o API for ${detectedIntent} response...`);
    console.log(`📝 [GPT-4o] User prompt length: ${userPrompt.length} chars`);
    const openaiResponse = await fetch("https://api.openai.com/v1/chat/completions", {
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
      }),
    });

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
    console.log(`⏱️ [RECALL-RESOLVE] Parse OpenAI response: ${Date.now() - parseStepTime}ms`);
    console.log(`📄 [RECALL-RESOLVE] Response content length: ${content?.length || 0} chars`);
    console.log(`📄 [RECALL-RESOLVE] Response preview: ${content?.substring(0, 200)}...`);

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
      console.log(`📊 [RECALL-RESOLVE] Parsed result: type=${aiResult.response_type}, confidence=${aiResult.overall_confidence}, candidates=${aiResult.candidates?.length || 0}, has_answer=${!!aiResult.answer}`);
      
      // Validate response structure
      if (!aiResult.response_type) {
        console.warn(`⚠️ [RECALL-RESOLVE] Missing response_type, defaulting to 'search'`);
        aiResult.response_type = 'search';
      }
      
      if (aiResult.overall_confidence === undefined || aiResult.overall_confidence === null) {
        console.warn(`⚠️ [RECALL-RESOLVE] Missing overall_confidence, calculating from candidates`);
        if (aiResult.candidates && aiResult.candidates.length > 0) {
          aiResult.overall_confidence = aiResult.candidates[0].confidence;
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

    // Only fail if we have NO candidates AND NO answer (conversational responses have answers, not candidates)
    if (finalCandidates.length === 0 && (!aiResult.answer || !aiResult.answer.text)) {
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

    // Insert all candidates as separate messages (deduplicated)
    // First, check existing candidates in this thread to avoid duplicates
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

    // Insert only new candidates (not already in thread)
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

    // Handle answer-type responses
    const insertAnswerTime = Date.now();
    let answerMessageId: string | null = null;
    if (aiResult.answer && (aiResult.response_type === "answer" || aiResult.response_type === "both")) {
      console.log(`📝 [RECALL-RESOLVE] Inserting answer message...`);
      // Build sources array for answer
      const answerSources = aiResult.answer.sources.map((url, index) => ({
        title: `Source ${index + 1}`,
        url,
        snippet: undefined,
      }));

      // Insert answer as assistant message
      const { data: answerMessage, error: answerError } = await supabase
        .from("recall_messages")
        .insert({
          thread_id,
          user_id: userMessage.user_id,
          role: "assistant",
          message_type: "answer", // Use answer type for answers
          text: aiResult.answer.text,
          sources_json: answerSources,
        })
        .select("id")
        .single();

      if (!answerError && answerMessage) {
        answerMessageId = answerMessage.id;
        console.log(`✅ [RECALL-RESOLVE] Inserted answer message (${aiResult.answer.text.length} chars)`);
      } else {
        console.error(`❌ [RECALL-RESOLVE] Failed to insert answer:`, answerError);
      }
    }
    console.log(`⏱️ [RECALL-RESOLVE] Insert answer: ${Date.now() - insertAnswerTime}ms`);

    // Handle follow-up question if confidence is low or conversation needs continuation
    const insertFollowUpTime = Date.now();
    let followUpQuestionId: string | null = null;
    if (aiResult.follow_up_question && (aiResult.overall_confidence < 0.7 || aiResult.response_type === "answer")) {
      console.log(`💬 [RECALL-RESOLVE] Inserting follow-up question: "${aiResult.follow_up_question}"`);
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
        console.log(`✅ [RECALL-RESOLVE] Inserted follow-up question`);
      } else {
        console.error(`❌ [RECALL-RESOLVE] Failed to insert follow-up:`, followUpError);
      }
    }
    console.log(`⏱️ [RECALL-RESOLVE] Insert follow-up: ${Date.now() - insertFollowUpTime}ms`);

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
    console.log(`📊 [RECALL-RESOLVE] Service calls summary:`);
    const acrCloudStatus = audioRecognitionResult?.service === "acrcloud" ? "✅ Called and matched" : "⏭️ Skipped or no match";
    console.log(`   - ACRCloud: ${acrCloudStatus}`);
    console.log(`   - Shazam: ${audioRecognitionResult?.service === "shazam" ? "✅ Called and matched" : "⏭️ Called but no match or skipped"}`);
    console.log(`   - Whisper Transcription: ${audioTranscription ? `✅ Transcribed: "${audioTranscription.substring(0, 50)}..."` : "⏭️ Not used"}`);
    console.log(`   - GPT-4o: ✅ Called for ${aiResult.response_type || "search"} response`);
    console.log(`   - Final candidates: ${finalCandidates.length}`);
    if (aiResult.answer) {
      console.log(`   - Answer provided: ${aiResult.answer.text.length} chars`);
    }
    
    return new Response(
      JSON.stringify({
        status: aiResult.follow_up_question ? "refining" : "done",
        response_type: aiResult.response_type || "search",
        transcription: audioTranscription || null, // Include transcription in response
        assistant_message: assistantMessage,
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
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (error) {
    console.error("Error in recall-resolve:", error);
    return new Response(
      JSON.stringify({ error: "Internal server error", details: error.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

