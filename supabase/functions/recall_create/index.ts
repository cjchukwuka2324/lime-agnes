// Supabase Edge Function: recall_create
// Creates a new recall event and triggers processing
// Deploy with: supabase functions deploy recall_create

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface RecallCreateRequest {
  input_type: "text" | "voice" | "image";
  raw_text?: string;
  media_path?: string;
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
    const supabaseKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey, {
      global: { headers: { Authorization: authHeader } },
    });

    // Get current user
    const { data: { user }, error: userError } = await supabase.auth.getUser();
    if (userError || !user) {
      return new Response(
        JSON.stringify({ error: "Unauthorized" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Parse request body
    const body: RecallCreateRequest = await req.json();
    const { input_type, raw_text, media_path } = body;

    if (!input_type || !["text", "voice", "image"].includes(input_type)) {
      return new Response(
        JSON.stringify({ error: "Invalid input_type. Must be 'text', 'voice', or 'image'" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Validate input based on type
    if (input_type === "text" && !raw_text) {
      return new Response(
        JSON.stringify({ error: "raw_text is required for text input_type" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (input_type === "voice" && !media_path) {
      return new Response(
        JSON.stringify({ error: "media_path is required for voice input_type" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (input_type === "image" && !raw_text && !media_path) {
      return new Response(
        JSON.stringify({ error: "Either raw_text (OCR) or media_path is required for image input_type" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Insert recall event
    const { data: recallEvent, error: insertError } = await supabase
      .from("recall_events")
      .insert({
        user_id: user.id,
        input_type,
        raw_text: raw_text || null,
        media_path: media_path || null,
        status: "queued",
      })
      .select()
      .single();

    if (insertError || !recallEvent) {
      console.error("Error creating recall event:", insertError);
      return new Response(
        JSON.stringify({ error: "Failed to create recall event", details: insertError?.message }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Immediately trigger processing (client will call recall_process)
    // For MVP, we return the recall_id and let the client call recall_process
    // This allows better error handling and status updates

    return new Response(
      JSON.stringify({
        recall_id: recallEvent.id,
        status: "queued",
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (error) {
    console.error("Error in recall_create:", error);
    return new Response(
      JSON.stringify({ error: "Internal server error", details: error.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

