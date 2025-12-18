// Supabase Edge Function: recall_ask_crowd
// Creates a GreenRoom post asking the crowd for help finding a song
// Deploy with: supabase functions deploy recall_ask_crowd

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface RecallAskCrowdRequest {
  recall_id: string;
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
    const body: RecallAskCrowdRequest = await req.json();
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
        JSON.stringify({ error: "Recall event not found" }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Check if crowd post already exists
    const { data: existingPost } = await supabase
      .from("recall_crowd_posts")
      .select("post_id")
      .eq("recall_id", recall_id)
      .single();

    if (existingPost) {
      return new Response(
        JSON.stringify({
          success: true,
          post_id: existingPost.post_id,
          already_exists: true,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Build post text
    const queryText = recallEvent.transcript || recallEvent.raw_text || "Help me find this song";
    const postText = `🎵 Help me find this song!\n\n"${queryText}"\n\n[Recall: Need help identifying this song from memory]`;

    // Prepare media attachments
    let imageUrls: string[] = [];
    let audioUrl: string | null = null;

    if (recallEvent.input_type === "image" && recallEvent.media_path) {
      // For images, we need to create a public URL or signed URL
      // For MVP, store the storage path - client will handle display
      imageUrls = [recallEvent.media_path];
    } else if (recallEvent.input_type === "voice" && recallEvent.media_path) {
      audioUrl = recallEvent.media_path;
    }

    // Create GreenRoom post using create_post RPC
    const { data: postId, error: postError } = await supabase.rpc("create_post", {
      p_text: postText,
      p_image_urls: imageUrls,
      p_audio_url: audioUrl,
    });

    if (postError || !postId) {
      console.error("Error creating post:", postError);
      return new Response(
        JSON.stringify({ 
          error: "Failed to create GreenRoom post", 
          details: postError?.message 
        }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Link recall to post
    const { error: linkError } = await supabase
      .from("recall_crowd_posts")
      .insert({
        recall_id,
        post_id: postId,
      });

    if (linkError) {
      console.error("Error linking recall to post:", linkError);
      // Don't fail - post was created successfully
    }

    return new Response(
      JSON.stringify({
        success: true,
        post_id: postId,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (error) {
    console.error("Error in recall_ask_crowd:", error);
    return new Response(
      JSON.stringify({ error: "Internal server error", details: error.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

