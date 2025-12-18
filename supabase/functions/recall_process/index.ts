// Supabase Edge Function: recall_process
// Processes a recall event using OpenAI with web search
// Deploy with: supabase functions deploy recall_process
// Requires: OPENAI_API_KEY secret

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface RecallProcessRequest {
  recall_id: string;
}

interface Candidate {
  title: string;
  artist: string;
  confidence: number;
  reason: string;
  highlight_snippet?: string;
  source_urls: string[];
}

interface OpenAIResponse {
  overall_confidence: number;
  candidates: Candidate[];
  should_ask_crowd: boolean;
  crowd_prompt?: string;
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Get authorization header
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing authorization header" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Initialize Supabase client
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Parse request body
    const body: RecallProcessRequest = await req.json();
    const { recall_id } = body;

    if (!recall_id) {
      return new Response(
        JSON.stringify({ error: "recall_id is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Load recall event
    const { data: recallEvent, error: fetchError } = await supabase
      .from("recall_events")
      .select("*")
      .eq("id", recall_id)
      .single();

    if (fetchError || !recallEvent) {
      return new Response(
        JSON.stringify({ error: "Recall event not found", details: fetchError?.message }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Update status to processing
    await supabase
      .from("recall_events")
      .update({ status: "processing" })
      .eq("id", recall_id);

    let queryText = recallEvent.raw_text || "";

    // If voice input, transcribe audio
    if (recallEvent.input_type === "voice" && recallEvent.media_path) {
      try {
        // Get signed URL for audio file
        const { data: signedUrlData, error: urlError } = await supabase.storage
          .from("recall-media")
          .createSignedUrl(recallEvent.media_path, 3600);

        if (urlError || !signedUrlData) {
          throw new Error("Failed to create signed URL for audio");
        }

        // Download audio file
        const audioResponse = await fetch(signedUrlData.signedUrl);
        const audioBlob = await audioResponse.blob();
        const audioFile = new File([audioBlob], "audio.m4a", { type: "audio/m4a" });

        // Transcribe using OpenAI Whisper API
        const openaiApiKey = Deno.env.get("OPENAI_API_KEY");
        if (!openaiApiKey) {
          throw new Error("OPENAI_API_KEY not configured");
        }

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

        if (!transcriptionResponse.ok) {
          const errorText = await transcriptionResponse.text();
          throw new Error(`OpenAI transcription failed: ${errorText}`);
        }

        const transcriptionData = await transcriptionResponse.json();
        const transcript = transcriptionData.text;

        // Store transcript
        await supabase
          .from("recall_events")
          .update({ transcript })
          .eq("id", recall_id);

        queryText = transcript;
      } catch (transcriptionError) {
        console.error("Transcription error:", transcriptionError);
        await supabase
          .from("recall_events")
          .update({
            status: "failed",
            error_message: `Transcription failed: ${transcriptionError.message}`,
          })
          .eq("id", recall_id);
        throw transcriptionError;
      }
    }

    if (!queryText || queryText.trim().length === 0) {
      await supabase
        .from("recall_events")
        .update({
          status: "failed",
          error_message: "No text available for search (missing raw_text or transcript)",
        })
        .eq("id", recall_id);
      return new Response(
        JSON.stringify({ error: "No text available for search" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Call OpenAI with web search enabled
    const openaiApiKey = Deno.env.get("OPENAI_API_KEY");
    if (!openaiApiKey) {
      await supabase
        .from("recall_events")
        .update({
          status: "failed",
          error_message: "OPENAI_API_KEY not configured",
        })
        .eq("id", recall_id);
      return new Response(
        JSON.stringify({ error: "OpenAI API key not configured" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Build prompt for OpenAI
    const systemPrompt = `You are a music identification assistant. Your task is to find songs based on user descriptions, lyrics, or memories.

Rules:
1. Use web search to find accurate song information
2. Return a JSON object with this exact structure:
{
  "overall_confidence": 0.0-1.0,
  "candidates": [
    {
      "title": "Song Title",
      "artist": "Artist Name",
      "confidence": 0.0-1.0,
      "reason": "Why this matches (brief explanation)",
      "highlight_snippet": "Short lyric or memorable line (max 50 chars)",
      "source_urls": ["url1", "url2"]
    }
  ],
  "should_ask_crowd": false,
  "crowd_prompt": "Optional prompt for asking the crowd"
}

3. Provide up to 10 candidates, ranked by confidence
4. Deduplicate candidates (same title+artist = one entry)
5. highlight_snippet must be short (no long quotes)
6. source_urls should include reputable sources (Wikipedia, Spotify, Apple Music, etc.)
7. If overall_confidence < 0.65, set should_ask_crowd to true and provide a helpful crowd_prompt
8. Be specific and accurate - prefer exact matches over guesses`;

    const userPrompt = `Find songs matching this description: "${queryText}"

Search the web for accurate information and return the best matches as JSON.`;

    const openaiResponse = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${openaiApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "gpt-4o", // Use latest model with web search capability
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userPrompt },
        ],
        response_format: { type: "json_object" },
        temperature: 0.3,
      }),
    });

    if (!openaiResponse.ok) {
      const errorText = await openaiResponse.text();
      console.error("OpenAI API error:", errorText);
      await supabase
        .from("recall_events")
        .update({
          status: "failed",
          error_message: `OpenAI API error: ${errorText}`,
        })
        .eq("id", recall_id);
      return new Response(
        JSON.stringify({ error: "OpenAI API request failed", details: errorText }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const openaiData = await openaiResponse.json();
    const content = openaiData.choices[0]?.message?.content;

    if (!content) {
      await supabase
        .from("recall_events")
        .update({
          status: "failed",
          error_message: "OpenAI returned empty response",
        })
        .eq("id", recall_id);
      return new Response(
        JSON.stringify({ error: "OpenAI returned empty response" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Parse OpenAI response
    let aiResult: OpenAIResponse;
    try {
      aiResult = JSON.parse(content);
    } catch (parseError) {
      await supabase
        .from("recall_events")
        .update({
          status: "failed",
          error_message: `Failed to parse OpenAI response: ${parseError.message}`,
        })
        .eq("id", recall_id);
      return new Response(
        JSON.stringify({ error: "Failed to parse OpenAI response" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Validate and deduplicate candidates
    const candidates = aiResult.candidates || [];
    const uniqueCandidates = new Map<string, Candidate>();
    
    for (const candidate of candidates) {
      const key = `${candidate.title.toLowerCase()}|${candidate.artist.toLowerCase()}`;
      if (!uniqueCandidates.has(key) || uniqueCandidates.get(key)!.confidence < candidate.confidence) {
        uniqueCandidates.set(key, candidate);
      }
    }

    const finalCandidates = Array.from(uniqueCandidates.values())
      .sort((a, b) => b.confidence - a.confidence)
      .slice(0, 10);

    // Insert candidates into database
    if (finalCandidates.length > 0) {
      const candidateRows = finalCandidates.map((candidate, index) => ({
        recall_id,
        title: candidate.title,
        artist: candidate.artist,
        confidence: candidate.confidence,
        reason: candidate.reason || null,
        source_urls: candidate.source_urls || [],
        highlight_snippet: candidate.highlight_snippet || null,
        rank: index + 1,
      }));

      await supabase
        .from("recall_candidates")
        .insert(candidateRows);
    }

    // Determine final status
    const overallConfidence = aiResult.overall_confidence || 0;
    const shouldAskCrowd = aiResult.should_ask_crowd || overallConfidence < 0.65 || finalCandidates.length === 0;
    const finalStatus = shouldAskCrowd ? "needs_crowd" : "done";

    // Update recall event
    await supabase
      .from("recall_events")
      .update({
        status: finalStatus,
        confidence: overallConfidence,
      })
      .eq("id", recall_id);

    // If needs_crowd, automatically create crowd post
    if (finalStatus === "needs_crowd") {
      try {
        // Call recall_ask_crowd internally (or trigger it)
        // For MVP, we'll create the post directly here
        const crowdPrompt = aiResult.crowd_prompt || `Help me find this song: "${queryText}"`;
        
        // Create GreenRoom post using create_post RPC
        const { data: postData, error: postError } = await supabase.rpc("create_post", {
          p_text: `${crowdPrompt}\n\n[Recall: Need help identifying this song]`,
          p_image_urls: recallEvent.input_type === "image" && recallEvent.media_path 
            ? [recallEvent.media_path] 
            : [],
          p_audio_url: recallEvent.input_type === "voice" && recallEvent.media_path 
            ? recallEvent.media_path 
            : null,
        });

        if (!postError && postData) {
          // Link recall to post
          await supabase
            .from("recall_crowd_posts")
            .insert({
              recall_id,
              post_id: postData,
            });
        }
      } catch (crowdError) {
        console.error("Error creating crowd post:", crowdError);
        // Don't fail the whole process if crowd post creation fails
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        recall_id,
        status: finalStatus,
        confidence: overallConfidence,
        candidates_count: finalCandidates.length,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (error) {
    console.error("Error in recall_process:", error);
    return new Response(
      JSON.stringify({ error: "Internal server error", details: error.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

