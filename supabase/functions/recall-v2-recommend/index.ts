// Supabase Edge Function: recall-v2-recommend
// Mood DJ: Recommends songs based on user mood and preferences
// Deploy with: supabase functions deploy recall-v2-recommend
// Requires: OPENAI_API_KEY secret

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface RecommendRequest {
  job_id: string;
  recall_id: string;
  query_text: string;
  user_preferences?: {
    genre_preferences?: string[];
    artist_preferences?: string[];
    confirmed_songs?: Array<{title: string; artist: string}>;
  };
}

interface Recommendation {
  title: string;
  artist: string;
  confidence: number;
  vibe_tags: string[];
  why_it_fits: string;
  spotify_url?: string;
  apple_music_url?: string;
}

interface MoodAnalysis {
  mood: string;
  energy_level: "low" | "medium" | "high";
  vibe_tags: string[];
  context?: string;
}

// Parse mood from user query
async function parseMood(
  queryText: string,
  openaiApiKey: string
): Promise<MoodAnalysis> {
  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 30000);

    const response = await fetch("https://api.openai.com/v1/chat/completions", {
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
            content: `Parse the user's mood and context from their query. Return JSON:
{
  "mood": "sad" | "happy" | "energetic" | "chill" | "focused" | "romantic" | "nostalgic" | "motivated" | "relaxed" | "party",
  "energy_level": "low" | "medium" | "high",
  "vibe_tags": ["tag1", "tag2", ...],
  "context": "optional context like 'workout', 'study', 'driving', etc."
}`
          },
          {
            role: "user",
            content: queryText
          }
        ],
        response_format: { type: "json_object" },
        temperature: 0.3,
        max_tokens: 200
      }),
      signal: controller.signal
    });

    clearTimeout(timeoutId);

    if (!response.ok) {
      throw new Error(`GPT API error: ${response.status}`);
    }

    const data = await response.json();
    const content = data.choices[0]?.message?.content;
    
    if (content) {
      return JSON.parse(content);
    }

    // Fallback
    return {
      mood: "chill",
      energy_level: "medium",
      vibe_tags: ["relaxed"]
    };
  } catch (error) {
    console.error("Mood parsing error:", error);
    return {
      mood: "chill",
      energy_level: "medium",
      vibe_tags: ["relaxed"]
    };
  }
}

// Get user's confirmed songs from recall_stash
async function getUserConfirmedSongs(
  userId: string,
  supabase: any,
  limit: number = 20
): Promise<Array<{title: string; artist: string}>> {
  try {
    const { data, error } = await supabase
      .from("recall_stash")
      .select("song_title, song_artist")
      .eq("user_id", userId)
      .not("song_title", "is", null)
      .not("song_artist", "is", null)
      .order("created_at", { ascending: false })
      .limit(limit);

    if (error || !data) {
      return [];
    }

    return data
      .filter(item => item.song_title && item.song_artist)
      .map(item => ({
        title: item.song_title,
        artist: item.song_artist
      }));
  } catch (error) {
    console.error("Error fetching confirmed songs:", error);
    return [];
  }
}

// Generate recommendations using GPT-4o
async function generateRecommendations(
  moodAnalysis: MoodAnalysis,
  userPreferences: any,
  confirmedSongs: Array<{title: string; artist: string}>,
  openaiApiKey: string
): Promise<Recommendation[]> {
  try {
    const confirmedSongsText = confirmedSongs.length > 0
      ? `User's confirmed songs: ${confirmedSongs.slice(0, 10).map(s => `${s.title} by ${s.artist}`).join(", ")}`
      : "No previous song history";

    const preferencesText = userPreferences?.genre_preferences?.length > 0
      ? `User prefers: ${userPreferences.genre_preferences.join(", ")}`
      : "";

    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 60000);

    const response = await fetch("https://api.openai.com/v1/chat/completions", {
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
            content: `You are a music recommendation expert. Generate 5-10 diverse song recommendations based on:
- User's mood: ${moodAnalysis.mood}
- Energy level: ${moodAnalysis.energy_level}
- Vibe tags: ${moodAnalysis.vibe_tags.join(", ")}
- Context: ${moodAnalysis.context || "general listening"}
${confirmedSongsText}
${preferencesText}

Return JSON array of recommendations:
[
  {
    "title": "Song Title",
    "artist": "Artist Name",
    "confidence": 0.0-1.0,
    "vibe_tags": ["tag1", "tag2"],
    "why_it_fits": "Brief explanation (1-2 sentences)",
    "spotify_url": "optional spotify link",
    "apple_music_url": "optional apple music link"
  },
  ...
]

Rules:
- Diversity: Don't recommend 10 similar songs
- Mix genres and eras
- Include both popular and lesser-known tracks
- Match the mood and energy level
- If user has confirmed songs, recommend similar vibes but different artists
- Confidence should reflect how well it matches the mood`
          },
          {
            role: "user",
            content: `Generate recommendations for: ${moodAnalysis.mood} mood, ${moodAnalysis.energy_level} energy`
          }
        ],
        response_format: { type: "json_object" },
        temperature: 0.7, // Higher temperature for diversity
        max_tokens: 2000
      }),
      signal: controller.signal
    });

    clearTimeout(timeoutId);

    if (!response.ok) {
      throw new Error(`GPT API error: ${response.status}`);
    }

    const data = await response.json();
    const content = data.choices[0]?.message?.content;
    
    if (!content) {
      throw new Error("Empty response from GPT");
    }

    const result = JSON.parse(content);
    const recommendations = result.recommendations || result.songs || [];

    // Ensure we have at least 5 recommendations
    if (recommendations.length < 5) {
      // Generate more if needed
      const additionalNeeded = 5 - recommendations.length;
      // For now, just return what we have
    }

    return recommendations.slice(0, 10); // Max 10 recommendations
  } catch (error) {
    console.error("Recommendation generation error:", error);
    // Return fallback recommendations
    return [
      {
        title: "Unknown",
        artist: "Unknown",
        confidence: 0.3,
        vibe_tags: [moodAnalysis.mood],
        why_it_fits: "Error generating recommendations"
      }
    ];
  }
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
    const body: RecommendRequest = await req.json();
    const { job_id, recall_id, query_text, user_preferences } = body;

    if (!job_id || !recall_id || !query_text) {
      return new Response(
        JSON.stringify({ error: "Missing required fields: job_id, recall_id, query_text" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const openaiApiKey = Deno.env.get("OPENAI_API_KEY");
    if (!openaiApiKey) {
      throw new Error("OPENAI_API_KEY not configured");
    }

    // Get user_id from recall
    const { data: recall, error: recallError } = await supabase
      .from("recalls")
      .select("user_id")
      .eq("id", recall_id)
      .single();

    if (recallError || !recall) {
      throw new Error("Recall not found");
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
        operation: "recommend_start",
        status: "processing",
        metadata: { job_id, query: query_text.substring(0, 100) }
      });

    // Parse mood from query
    console.log("Parsing mood from query...");
    const moodAnalysis = await parseMood(query_text, openaiApiKey);

    // Get user's confirmed songs
    const confirmedSongs = await getUserConfirmedSongs(recall.user_id, supabase);
    
    // Merge with user_preferences if provided
    const mergedPreferences = {
      ...user_preferences,
      confirmed_songs: confirmedSongs
    };

    // Generate recommendations
    console.log("Generating recommendations...");
    const recommendations = await generateRecommendations(
      moodAnalysis,
      mergedPreferences,
      confirmedSongs,
      openaiApiKey
    );

    // Write recommendations to recall_candidates
    for (let i = 0; i < recommendations.length; i++) {
      const rec = recommendations[i];
      await supabase
        .from("recall_candidates")
        .insert({
          recall_id: recall_id,
          rank: i + 1,
          title: rec.title,
          artist: rec.artist,
          confidence: rec.confidence,
          url: rec.spotify_url || rec.apple_music_url,
          evidence: rec.why_it_fits
        });

      // Write sources if URLs provided
      if (rec.spotify_url) {
        await supabase
          .from("recall_sources")
          .insert({
            recall_id: recall_id,
            title: `${rec.title} by ${rec.artist}`,
            url: rec.spotify_url,
            publisher: "Spotify",
            verified: true
          });
      }
      if (rec.apple_music_url) {
        await supabase
          .from("recall_sources")
          .insert({
            recall_id: recall_id,
            title: `${rec.title} by ${rec.artist}`,
            url: rec.apple_music_url,
            publisher: "Apple Music",
            verified: true
          });
      }
    }

    // Update recall with recommendations
    await supabase
      .from("recalls")
      .update({
        status: "done",
        result_json: {
          mood: moodAnalysis,
          recommendations: recommendations,
          count: recommendations.length
        }
      })
      .eq("id", recall_id);

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
        operation: "recommend_complete",
        duration_ms: duration,
        status: "success",
        metadata: {
          job_id,
          recommendations_count: recommendations.length,
          mood: moodAnalysis.mood,
          energy_level: moodAnalysis.energy_level
        }
      });

    return new Response(
      JSON.stringify({
        status: "done",
        request_id: requestId,
        mood: moodAnalysis,
        recommendations: recommendations
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" }
      }
    );

  } catch (error) {
    console.error("Error in recall-v2-recommend:", error);
    
    const duration = Date.now() - startTime;
    const errorMessage = error instanceof Error ? error.message : String(error);

    // Try to update job and recall status
    try {
      const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
      const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
      const supabase = createClient(supabaseUrl, supabaseKey);
      
      const body: RecommendRequest = await req.json();
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
          operation: "recommend_error",
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

















