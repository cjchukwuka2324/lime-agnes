// Supabase Edge Function: recall-v2-learning-processor
// Background job for continuous learning and pattern analysis
// Deploy with: supabase functions deploy recall-v2-learning-processor
// Can be triggered via cron

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

    // Get all users with recent feedback (last 24 hours)
    const oneDayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();

    const { data: usersWithFeedback } = await supabase
      .from("recall_feedback")
      .select("user_id")
      .gte("created_at", oneDayAgo)
      .not("user_id", "is", null);

    if (!usersWithFeedback || usersWithFeedback.length === 0) {
      return new Response(
        JSON.stringify({ status: "no_users", processed: 0 }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Get unique user IDs
    const uniqueUserIds = [...new Set(usersWithFeedback.map(f => f.user_id))];

    // Process each user's preferences
    const functionUrl = `${supabaseUrl}/functions/v1/recall-v2-learning`;
    let processed = 0;

    for (const userId of uniqueUserIds.slice(0, 100)) { // Limit to 100 users per run
      try {
        const response = await fetch(functionUrl, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "Authorization": `Bearer ${supabaseKey}`
          },
          body: JSON.stringify({ user_id: userId })
        });

        if (response.ok) {
          processed++;
        }
      } catch (error) {
        console.error(`Error processing user ${userId}:`, error);
      }
    }

    return new Response(
      JSON.stringify({
        status: "processed",
        users_processed: processed,
        total_users: uniqueUserIds.length
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

















