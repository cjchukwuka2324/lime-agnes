// Supabase Edge Function: recall-v2-identify
// Identifies songs from audio (background, voice notes, humming)
// Deploy with: supabase functions deploy recall-v2-identify
// Requires: ACRCLOUD_ACCESS_KEY, ACRCLOUD_ACCESS_SECRET, SHAZAM_API_KEY, OPENAI_API_KEY

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface IdentifyRequest {
  job_id: string;
  recall_id: string;
  audio_path: string;
  input_type: "voice" | "background" | "hum";
  user_preferences?: {
    genre_preferences?: string[];
    artist_preferences?: string[];
    rejected_artists?: string[];
  };
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

interface Candidate {
  title: string;
  artist: string;
  confidence: number;
  reason: string;
  background?: string;
  highlight_snippet?: string;
  source_urls: string[];
  album?: string;
  release_date?: string;
  spotify_url?: string;
  apple_music_url?: string;
}

// ACRCloud audio identification (best for humming)
async function identifyAudioWithACRCloud(audioBuffer: ArrayBuffer): Promise<AudioRecognitionResult> {
  const accessKey = Deno.env.get("ACRCLOUD_ACCESS_KEY");
  const accessSecret = Deno.env.get("ACRCLOUD_ACCESS_SECRET");
  const host = Deno.env.get("ACRCLOUD_HOST") || "identify-us-west-2.acrcloud.com";

  if (!accessKey || !accessSecret) {
    console.log("ACRCloud credentials not configured, skipping");
    return { success: false, confidence: 0, service: "acrcloud" };
  }

  try {
    const formData = new FormData();
    formData.append("sample", new Blob([audioBuffer], { type: "audio/m4a" }));
    formData.append("sample_bytes", audioBuffer.byteLength.toString());
    formData.append("access_key", accessKey);
    formData.append("data_type", "audio");
    formData.append("format", "m4a");

    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 30000); // 30s timeout

    const response = await fetch(`https://${host}/v1/identify`, {
      method: "POST",
      headers: {
        "access-key": accessKey,
        "access-secret": accessSecret,
      },
      body: formData,
      signal: controller.signal
    });

    clearTimeout(timeoutId);

    if (!response.ok) {
      console.error("ACRCloud API error:", response.status);
      return { success: false, confidence: 0, service: "acrcloud" };
    }

    const data = await response.json();
    
    if (data.status?.code === 0 && data.metadata?.music && data.metadata.music.length > 0) {
      const track = data.metadata.music[0];
      const confidence = track.score ? track.score / 100 : 0.8;
      
      return {
        success: true,
        title: track.title,
        artist: track.artists?.[0]?.name || track.artists?.[0],
        confidence: Math.min(confidence, 1.0),
        service: "acrcloud",
        reason: `Identified via ACRCloud audio fingerprinting`,
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

    return { success: false, confidence: 0, service: "acrcloud" };
  } catch (error) {
    if (error.name === "AbortError") {
      console.error("ACRCloud request timeout");
    } else {
      console.error("ACRCloud identification error:", error);
    }
    return { success: false, confidence: 0, service: "acrcloud" };
  }
}

// Shazam audio identification (best for full songs)
async function identifyAudioWithShazam(audioBuffer: ArrayBuffer): Promise<AudioRecognitionResult> {
  const apiKey = Deno.env.get("SHAZAM_API_KEY");

  if (!apiKey) {
    console.log("Shazam API key not configured, skipping");
    return { success: false, confidence: 0, service: "shazam" };
  }

  try {
    const audioBase64 = btoa(String.fromCharCode(...new Uint8Array(audioBuffer)));
    
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 30000); // 30s timeout

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
      signal: controller.signal
    });

    clearTimeout(timeoutId);

    if (!response.ok) {
      console.error("Shazam API error:", response.status);
      return { success: false, confidence: 0, service: "shazam" };
    }

    const data = await response.json();
    
    if (data.track) {
      const track = data.track;
      const confidence = data.match ? 0.9 : 0.7;
      
      return {
        success: true,
        title: track.title,
        artist: track.subtitle || track.artists?.[0]?.name,
        confidence,
        service: "shazam",
        reason: `Identified via Shazam audio fingerprinting`,
        album: track.sections?.[0]?.metadata?.find((m: any) => m.title === "Album")?.text,
        spotifyUrl: track.hub?.actions?.[0]?.uri,
        appleMusicUrl: track.hub?.options?.[0]?.actions?.[0]?.uri,
      };
    }

    return { success: false, confidence: 0, service: "shazam" };
  } catch (error) {
    if (error.name === "AbortError") {
      console.error("Shazam request timeout");
    } else {
      console.error("Shazam identification error:", error);
    }
    return { success: false, confidence: 0, service: "shazam" };
  }
}

// Whisper transcription + GPT-4o search (fallback)
async function identifyWithWhisperAndGPT(
  audioBuffer: ArrayBuffer,
  supabase: any,
  recallId: string,
  userPreferences?: any
): Promise<AudioRecognitionResult> {
  const openaiApiKey = Deno.env.get("OPENAI_API_KEY");
  
  if (!openaiApiKey) {
    console.log("OpenAI API key not configured, cannot use Whisper fallback");
    return { success: false, confidence: 0, service: "whisper" };
  }

  try {
    // Transcribe audio with Whisper
    const audioBlob = new Blob([audioBuffer], { type: "audio/m4a" });
    const formData = new FormData();
    formData.append("file", audioBlob, "audio.m4a");
    formData.append("model", "whisper-1");

    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 60000); // 60s timeout

    const transcriptResponse = await fetch("https://api.openai.com/v1/audio/transcriptions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${openaiApiKey}`,
      },
      body: formData,
      signal: controller.signal
    });

    clearTimeout(timeoutId);

    if (!transcriptResponse.ok) {
      console.error("Whisper API error:", transcriptResponse.status);
      return { success: false, confidence: 0, service: "whisper" };
    }

    const transcriptData = await transcriptResponse.json();
    const transcription = transcriptData.text;

    if (!transcription || transcription.trim().length === 0) {
      return { success: false, confidence: 0, service: "whisper" };
    }

    // Use GPT-4o to search for song based on transcription
    const userContext = userPreferences ? 
      `User preferences: ${JSON.stringify(userPreferences)}. ` : "";

    const gptResponse = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${openaiApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "gpt-4o",
        messages: [
          {
            role: "system",
            content: `You are a music identification expert. Based on the audio transcription, identify the song. ${userContext}Return JSON: {title: string, artist: string, confidence: 0.0-1.0, reason: string}`
          },
          {
            role: "user",
            content: `Transcribed audio: "${transcription}". Identify this song.`
          }
        ],
        response_format: { type: "json_object" },
        temperature: 0.3,
        max_tokens: 200
      }),
    });

    if (!gptResponse.ok) {
      return { success: false, confidence: 0, service: "whisper" };
    }

    const gptData = await gptResponse.json();
    const content = gptData.choices[0]?.message?.content;
    
    if (content) {
      const result = JSON.parse(content);
      return {
        success: true,
        title: result.title,
        artist: result.artist,
        confidence: Math.min(result.confidence || 0.5, 1.0),
        service: "whisper",
        reason: result.reason || `Identified via Whisper transcription: "${transcription}"`
      };
    }

    return { success: false, confidence: 0, service: "whisper" };
  } catch (error) {
    if (error.name === "AbortError") {
      console.error("Whisper/GPT request timeout");
    } else {
      console.error("Whisper identification error:", error);
    }
    return { success: false, confidence: 0, service: "whisper" };
  }
}

// Re-rank candidates based on user preferences
function reRankCandidates(
  candidates: Candidate[],
  userPreferences?: any
): Candidate[] {
  if (!userPreferences || candidates.length === 0) {
    return candidates;
  }

  return candidates.map(candidate => {
    let adjustedConfidence = candidate.confidence;

    // Boost if matches user's preferred genres
    if (userPreferences.genre_preferences && userPreferences.genre_preferences.length > 0) {
      // This would require genre lookup - simplified for now
    }

    // Penalize if matches rejected artists
    if (userPreferences.rejected_artists && 
        userPreferences.rejected_artists.some((a: string) => 
          candidate.artist.toLowerCase().includes(a.toLowerCase())
        )) {
      adjustedConfidence *= 0.5; // Halve confidence
    }

    // Boost if matches preferred artists
    if (userPreferences.artist_preferences && 
        userPreferences.artist_preferences.some((a: string) => 
          candidate.artist.toLowerCase().includes(a.toLowerCase())
        )) {
      adjustedConfidence = Math.min(adjustedConfidence * 1.2, 1.0); // Boost by 20%
    }

    return {
      ...candidate,
      confidence: adjustedConfidence
    };
  }).sort((a, b) => b.confidence - a.confidence);
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  const requestId = `req_${Date.now()}_${Math.random().toString(36).substring(2, 15)}`;
  const startTime = Date.now();

  try {
    // Initialize Supabase client
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false
      }
    });

    // Parse request body
    const body: IdentifyRequest = await req.json();
    const { job_id, recall_id, audio_path, input_type, user_preferences } = body;

    if (!job_id || !recall_id || !audio_path) {
      return new Response(
        JSON.stringify({ error: "Missing required fields: job_id, recall_id, audio_path" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Update job status to processing
    await supabase
      .from("recall_jobs")
      .update({
        status: "processing",
        started_at: new Date().toISOString()
      })
      .eq("id", job_id);

    await supabase
      .from("recalls")
      .update({ status: "processing" })
      .eq("id", recall_id);

    // Log start
    await supabase
      .from("recall_logs")
      .insert({
        request_id: requestId,
        recall_id: recall_id,
        operation: "identify_start",
        status: "processing",
        metadata: { job_id, input_type }
      });

    // Get signed URL for audio file
    const bucket = "recall-audio";
    const { data: signedUrlData, error: urlError } = await supabase.storage
      .from(bucket)
      .createSignedUrl(audio_path, 3600);

    if (urlError || !signedUrlData) {
      throw new Error("Failed to create signed URL for audio");
    }

    // Download audio file
    const audioResponse = await fetch(signedUrlData.signedUrl);
    if (!audioResponse.ok) {
      throw new Error("Failed to download audio file");
    }
    const audioBlob = await audioResponse.blob();
    const audioArrayBuffer = await audioBlob.arrayBuffer();

    // Try audio recognition services in order: ACRCloud → Shazam → Whisper
    let recognitionResult: AudioRecognitionResult | null = null;
    
    console.log("Attempting ACRCloud audio identification...");
    recognitionResult = await identifyAudioWithACRCloud(audioArrayBuffer);
    
    if (!recognitionResult.success || recognitionResult.confidence < 0.7) {
      console.log("ACRCloud failed or low confidence, trying Shazam...");
      const shazamResult = await identifyAudioWithShazam(audioArrayBuffer);
      if (shazamResult.success && shazamResult.confidence >= 0.7) {
        recognitionResult = shazamResult;
      } else if (!recognitionResult.success) {
        // Only use Shazam if ACRCloud completely failed
        recognitionResult = shazamResult;
      }
    }

    // Fallback to Whisper if both fail or confidence is low
    if (!recognitionResult.success || recognitionResult.confidence < 0.6) {
      console.log("Audio recognition failed or low confidence, trying Whisper transcription...");
      const whisperResult = await identifyWithWhisperAndGPT(
        audioArrayBuffer,
        supabase,
        recall_id,
        user_preferences
      );
      if (whisperResult.success) {
        recognitionResult = whisperResult;
      }
    }

    // Build candidates from recognition result
    const candidates: Candidate[] = [];
    
    if (recognitionResult.success && recognitionResult.title && recognitionResult.artist) {
      const sourceUrls: string[] = [];
      if (recognitionResult.spotifyUrl) sourceUrls.push(recognitionResult.spotifyUrl);
      if (recognitionResult.appleMusicUrl) sourceUrls.push(recognitionResult.appleMusicUrl);
      
      candidates.push({
        title: recognitionResult.title,
        artist: recognitionResult.artist,
        confidence: recognitionResult.confidence,
        reason: recognitionResult.reason || `Identified via ${recognitionResult.service}`,
        source_urls: sourceUrls,
        album: recognitionResult.album,
        release_date: recognitionResult.releaseDate,
        spotify_url: recognitionResult.spotifyUrl,
        apple_music_url: recognitionResult.appleMusicUrl
      });
    }

    // Re-rank based on user preferences
    const rankedCandidates = reRankCandidates(candidates, user_preferences);

    // Write candidates to database
    for (let i = 0; i < Math.min(rankedCandidates.length, 3); i++) {
      const candidate = rankedCandidates[i];
      await supabase
        .from("recall_candidates")
        .insert({
          recall_id: recall_id,
          rank: i + 1,
          title: candidate.title,
          artist: candidate.artist,
          confidence: candidate.confidence,
          url: candidate.spotify_url || candidate.apple_music_url,
          evidence: candidate.reason
        });

      // Write sources
      for (const url of candidate.source_urls) {
        await supabase
          .from("recall_sources")
          .insert({
            recall_id: recall_id,
            title: `${candidate.title} by ${candidate.artist}`,
            url: url,
            publisher: url.includes("spotify") ? "Spotify" : url.includes("apple") ? "Apple Music" : "Unknown",
            verified: true
          });
      }
    }

    // Update recall with top result
    const topCandidate = rankedCandidates[0];
    if (topCandidate) {
      await supabase
        .from("recalls")
        .update({
          status: "done",
          top_confidence: topCandidate.confidence,
          top_title: topCandidate.title,
          top_artist: topCandidate.artist,
          top_url: topCandidate.spotify_url || topCandidate.apple_music_url,
          result_json: {
            candidates: rankedCandidates,
            service_used: recognitionResult.service
          }
        })
        .eq("id", recall_id);
    } else {
      await supabase
        .from("recalls")
        .update({
          status: "done",
          error_message: "No candidates found"
        })
        .eq("id", recall_id);
    }

    // Update job status
    await supabase
      .from("recall_jobs")
      .update({
        status: "done",
        completed_at: new Date().toISOString()
      })
      .eq("id", job_id);

    // Log completion
    const duration = Date.now() - startTime;
    await supabase
      .from("recall_logs")
      .insert({
        request_id: requestId,
        recall_id: recall_id,
        operation: "identify_complete",
        duration_ms: duration,
        status: topCandidate ? "success" : "no_results",
        metadata: {
          job_id,
          candidates_found: rankedCandidates.length,
          service_used: recognitionResult.service,
          top_confidence: topCandidate?.confidence
        }
      });

    return new Response(
      JSON.stringify({
        status: "done",
        request_id: requestId,
        candidates: rankedCandidates,
        top_candidate: topCandidate || null
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" }
      }
    );

  } catch (error) {
    console.error("Error in recall-v2-identify:", error);
    
    const duration = Date.now() - startTime;
    const errorMessage = error instanceof Error ? error.message : String(error);

    // Try to update job and recall status
    try {
      const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
      const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
      const supabase = createClient(supabaseUrl, supabaseKey);
      
      const body: IdentifyRequest = await req.json();
      const { job_id, recall_id } = body;

      if (job_id) {
        await supabase
          .from("recall_jobs")
          .update({
            status: "failed",
            error_message: errorMessage,
            completed_at: new Date().toISOString()
          })
          .eq("id", job_id);
      }

      if (recall_id) {
        await supabase
          .from("recalls")
          .update({
            status: "failed",
            error_message: errorMessage
          })
          .eq("id", recall_id);
      }

      await supabase
        .from("recall_logs")
        .insert({
          request_id: requestId,
          recall_id: recall_id || null,
          operation: "identify_error",
          duration_ms: duration,
          status: "error",
          error_message: errorMessage
        });
    } catch (logError) {
      console.error("Error logging failure:", logError);
    }

    return new Response(
      JSON.stringify({
        error: "Internal server error",
        details: errorMessage,
        request_id: requestId
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" }
      }
    );
  }
});




