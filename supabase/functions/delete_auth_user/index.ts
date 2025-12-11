// Supabase Edge Function for deleting auth user
// This function uses the Admin API to delete a user from auth.users
// Deploy with: supabase functions deploy delete_auth_user

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Initialize Supabase Admin client
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    });

    // Get the authenticated user from the Authorization header
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing authorization header" }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 401,
        }
      );
    }

    // Extract token from "Bearer <token>"
    const token = authHeader.replace("Bearer ", "");
    
    // Verify the token and get user info
    const {
      data: { user },
      error: userError,
    } = await supabaseAdmin.auth.getUser(token);

    if (userError || !user) {
      console.error("❌ Error getting user:", userError);
      return new Response(
        JSON.stringify({ error: "Invalid or expired token" }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 401,
        }
      );
    }

    const userId = user.id;
    console.log(`🗑️ Deleting auth user: ${userId}`);

    // Delete the user from auth.users using Admin API
    const { error: deleteError } = await supabaseAdmin.auth.admin.deleteUser(
      userId
    );

    if (deleteError) {
      console.error("❌ Error deleting auth user:", deleteError);
      return new Response(
        JSON.stringify({ 
          error: "Failed to delete auth user",
          details: deleteError.message 
        }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 500,
        }
      );
    }

    console.log(`✅ Successfully deleted auth user: ${userId}`);

    return new Response(
      JSON.stringify({
        success: true,
        message: "Auth user deleted successfully",
        user_id: userId,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      }
    );
  } catch (error) {
    console.error("❌ Error in delete_auth_user:", error);
    return new Response(
      JSON.stringify({ 
        error: "Internal server error",
        details: error.message 
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 500,
      }
    );
  }
});

/*
DEPLOYMENT INSTRUCTIONS:

1. Deploy the function:
   supabase functions deploy delete_auth_user

2. The function requires the SUPABASE_SERVICE_ROLE_KEY environment variable
   This should already be set automatically by Supabase

3. Test the function:
   curl -X POST 'https://YOUR_PROJECT.supabase.co/functions/v1/delete_auth_user' \
     -H 'Authorization: Bearer USER_ACCESS_TOKEN' \
     -H 'apikey: YOUR_ANON_KEY'

4. Note: This function should only be called AFTER the delete_user_account RPC
   has successfully deleted all user data from public tables
*/

