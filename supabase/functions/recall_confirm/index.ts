// Supabase Edge Function: recall_confirm
// Confirms a candidate as the correct match
// Deploy with: supabase functions deploy recall_confirm

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface RecallConfirmRequest {
  recall_id: string;
  confirmed_title: string;
  confirmed_artist: string;
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
    const body: RecallConfirmRequest = await req.json();
    const { recall_id, confirmed_title, confirmed_artist } = body;

    if (!recall_id || !confirmed_title || !confirmed_artist) {
      return new Response(
        JSON.stringify({ error: "recall_id, confirmed_title, and confirmed_artist are required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Verify recall event exists and belongs to user
    const { data: recallEvent, error: fetchError } = await supabase
      .from("recall_events")
      .select("user_id")
      .eq("id", recall_id)
      .single();

    if (fetchError || !recallEvent) {
      return new Response(
        JSON.stringify({ error: "Recall event not found" }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (recallEvent.user_id !== user.id) {
      return new Response(
        JSON.stringify({ error: "Unauthorized: Recall event does not belong to user" }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Insert confirmation
    const { data: confirmation, error: insertError } = await supabase
      .from("recall_confirmations")
      .insert({
        recall_id,
        user_id: user.id,
        confirmed_title: confirmed_title.trim(),
        confirmed_artist: confirmed_artist.trim(),
      })
      .select()
      .single();

    if (insertError) {
      console.error("Error creating confirmation:", insertError);
      return new Response(
        JSON.stringify({ error: "Failed to create confirmation", details: insertError.message }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Update recall event status to done
    await supabase
      .from("recall_events")
      .update({ status: "done" })
      .eq("id", recall_id);

    return new Response(
      JSON.stringify({
        success: true,
        confirmation_id: confirmation.id,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (error) {
    console.error("Error in recall_confirm:", error);
    return new Response(
      JSON.stringify({ error: "Internal server error", details: error.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

