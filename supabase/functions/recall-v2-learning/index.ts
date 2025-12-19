// Supabase Edge Function: recall-v2-learning
// Builds user preference profiles from feedback
// Deploy with: supabase functions deploy recall-v2-learning

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    const body = await req.json();
    const { user_id } = body;

    if (!user_id) {
      return new Response(
        JSON.stringify({ error: "user_id is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Get confirmed songs from feedback
    const { data: confirmations } = await supabase
      .from("recall_feedback")
      .select("context_json")
      .eq("user_id", user_id)
      .eq("feedback_type", "confirm")
      .order("created_at", { ascending: false })
      .limit(50);

    // Get rejected songs
    const { data: rejections } = await supabase
      .from("recall_feedback")
      .select("context_json")
      .eq("user_id", user_id)
      .eq("feedback_type", "reject")
      .order("created_at", { ascending: false })
      .limit(50);

    // Get corrections
    const { data: corrections } = await supabase
      .from("recall_feedback")
      .select("correction_text, context_json")
      .eq("user_id", user_id)
      .eq("feedback_type", "correct")
      .order("created_at", { ascending: false })
      .limit(20);

    // Analyze confirmed songs for genre/artist preferences
    const artistCounts = new Map<string, number>();
    const genreCounts = new Map<string, number>();

    confirmations?.forEach(f => {
      const artist = f.context_json?.candidate_artist;
      if (artist) {
        artistCounts.set(artist, (artistCounts.get(artist) || 0) + 1);
      }
    });

    // Get top artists (simplified - would need genre lookup in production)
    const topArtists = Array.from(artistCounts.entries())
      .sort((a, b) => b[1] - a[1])
      .slice(0, 10)
      .map(([artist]) => artist);

    // Get rejected artists
    const rejectedArtists = new Set<string>();
    rejections?.forEach(f => {
      const artist = f.context_json?.candidate_artist;
      if (artist) {
        rejectedArtists.add(artist);
      }
    });

    // Update user preferences
    if (topArtists.length > 0) {
      await supabase
        .from("recall_user_preferences")
        .upsert({
          user_id: user_id,
          preference_type: "artist_preference",
          preference_data: { artists: topArtists },
          confidence_score: Math.min(topArtists.length / 10, 1.0),
          updated_at: new Date().toISOString()
        }, {
          onConflict: "user_id,preference_type"
        });
    }

    // Store corrections pattern
    if (corrections && corrections.length > 0) {
      const correctionPatterns = corrections.map(c => ({
        original: c.context_json?.original_title || c.context_json?.original_artist,
        corrected: c.correction_text
      }));

      await supabase
        .from("recall_user_preferences")
        .upsert({
          user_id: user_id,
          preference_type: "search_pattern",
          preference_data: { corrections: correctionPatterns },
          confidence_score: Math.min(corrections.length / 10, 1.0),
          updated_at: new Date().toISOString()
        }, {
          onConflict: "user_id,preference_type"
        });
    }

    return new Response(
      JSON.stringify({
        status: "success",
        preferences_updated: {
          artists: topArtists.length,
          rejected: rejectedArtists.size,
          corrections: corrections?.length || 0
        }
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (error) {
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : String(error) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});







