// Supabase Edge Function for sending APNs push notifications
// Deploy with: supabase functions deploy send_push_notification

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface NotificationPayload {
  user_id: string;
  title: string;
  body: string;
  data?: Record<string, any>;
}

interface DeviceToken {
  token: string;
  platform: string;
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Parse request body
    const payload: NotificationPayload = await req.json();
    const { user_id, title, body, data } = payload;

    console.log(`📱 Sending push notification to user: ${user_id}`);
    console.log(`   Title: ${title}`);
    console.log(`   Body: ${body}`);

    // Initialize Supabase client
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    // Fetch device tokens for user
    const { data: tokens, error: tokensError } = await supabase
      .from("device_tokens")
      .select("token, platform")
      .eq("user_id", user_id);

    if (tokensError) {
      console.error("❌ Error fetching device tokens:", tokensError);
      throw tokensError;
    }

    if (!tokens || tokens.length === 0) {
      console.log("⚠️ No device tokens found for user");
      return new Response(
        JSON.stringify({ message: "No device tokens found", sent: 0 }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 200,
        }
      );
    }

    console.log(`📱 Found ${tokens.length} device token(s)`);

    // Get APNs credentials from environment
    const apnsKeyId = Deno.env.get("APNS_KEY_ID");
    const apnsTeamId = Deno.env.get("APNS_TEAM_ID");
    const apnsBundleId = Deno.env.get("APNS_BUNDLE_ID") || "com.rockout.app";
    const apnsKey = Deno.env.get("APNS_AUTH_KEY");
    const apnsProduction = Deno.env.get("APNS_PRODUCTION") === "true";

    // Check if APNs is configured
    if (!apnsKeyId || !apnsTeamId || !apnsKey) {
      console.warn("⚠️ APNs not configured - skipping push notification");
      console.warn("   Required env vars: APNS_KEY_ID, APNS_TEAM_ID, APNS_AUTH_KEY");
      return new Response(
        JSON.stringify({
          message: "APNs not configured",
          sent: 0,
          note: "Set APNS_KEY_ID, APNS_TEAM_ID, and APNS_AUTH_KEY environment variables",
        }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 200,
        }
      );
    }

    // Send to each device token
    let successCount = 0;
    let failCount = 0;

    for (const deviceToken of tokens as DeviceToken[]) {
      if (deviceToken.platform !== "ios") {
        console.log(`⏭️ Skipping non-iOS token: ${deviceToken.platform}`);
        continue;
      }

      try {
        await sendAPNsNotification({
          deviceToken: deviceToken.token,
          title,
          body,
          data: data || {},
          apnsKeyId,
          apnsTeamId,
          apnsBundleId,
          apnsKey,
          production: apnsProduction,
        });
        successCount++;
        console.log(`✅ Sent to device token: ${deviceToken.token.substring(0, 8)}...`);
      } catch (error) {
        failCount++;
        console.error(`❌ Failed to send to token: ${deviceToken.token.substring(0, 8)}...`, error);
      }
    }

    console.log(`📊 Results: ${successCount} sent, ${failCount} failed`);

    return new Response(
      JSON.stringify({
        message: "Push notifications sent",
        sent: successCount,
        failed: failCount,
        total: tokens.length,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      }
    );
  } catch (error) {
    console.error("❌ Error in send_push_notification:", error);
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 500,
      }
    );
  }
});

// ============================================================================
// APNs Notification Sending
// ============================================================================

interface APNsOptions {
  deviceToken: string;
  title: string;
  body: string;
  data: Record<string, any>;
  apnsKeyId: string;
  apnsTeamId: string;
  apnsBundleId: string;
  apnsKey: string;
  production: boolean;
}

async function sendAPNsNotification(options: APNsOptions): Promise<void> {
  const {
    deviceToken,
    title,
    body,
    data,
    apnsKeyId,
    apnsTeamId,
    apnsBundleId,
    apnsKey,
    production,
  } = options;

  // APNs server
  const apnsServer = production
    ? "https://api.push.apple.com"
    : "https://api.sandbox.push.apple.com";

  // Build APNs payload
  const payload = {
    aps: {
      alert: {
        title,
        body,
      },
      sound: "default",
      badge: 1,
    },
    ...data, // Custom data
  };

  // Generate JWT token for authentication
  const jwtToken = await generateAPNsJWT(apnsKeyId, apnsTeamId, apnsKey);

  // Send request to APNs
  const response = await fetch(
    `${apnsServer}/3/device/${deviceToken}`,
    {
      method: "POST",
      headers: {
        "authorization": `bearer ${jwtToken}`,
        "apns-topic": apnsBundleId,
        "apns-push-type": "alert",
        "apns-priority": "10",
      },
      body: JSON.stringify(payload),
    }
  );

  if (!response.ok) {
    const errorBody = await response.text();
    throw new Error(`APNs request failed: ${response.status} ${errorBody}`);
  }
}

// ============================================================================
// JWT Token Generation for APNs
// ============================================================================

async function generateAPNsJWT(
  keyId: string,
  teamId: string,
  privateKey: string
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);

  // JWT Header
  const header = {
    alg: "ES256",
    kid: keyId,
  };

  // JWT Claims
  const claims = {
    iss: teamId,
    iat: now,
  };

  // Encode header and claims
  const encodedHeader = base64UrlEncode(JSON.stringify(header));
  const encodedClaims = base64UrlEncode(JSON.stringify(claims));

  // Create signature input
  const signatureInput = `${encodedHeader}.${encodedClaims}`;

  // Import the private key
  const keyData = pemToArrayBuffer(privateKey);
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    keyData,
    {
      name: "ECDSA",
      namedCurve: "P-256",
    },
    false,
    ["sign"]
  );

  // Sign the JWT
  const signatureBuffer = await crypto.subtle.sign(
    {
      name: "ECDSA",
      hash: "SHA-256",
    },
    cryptoKey,
    new TextEncoder().encode(signatureInput)
  );

  // Encode signature
  const signature = base64UrlEncode(signatureBuffer);

  // Return complete JWT
  return `${signatureInput}.${signature}`;
}

// ============================================================================
// Utility Functions
// ============================================================================

function base64UrlEncode(data: string | ArrayBuffer): string {
  let base64: string;
  
  if (typeof data === "string") {
    base64 = btoa(data);
  } else {
    const bytes = new Uint8Array(data);
    const binary = Array.from(bytes)
      .map((b) => String.fromCharCode(b))
      .join("");
    base64 = btoa(binary);
  }
  
  return base64
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=/g, "");
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  // Remove PEM header/footer and whitespace
  const pemContents = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s/g, "");

  // Decode base64
  const binaryString = atob(pemContents);
  const bytes = new Uint8Array(binaryString.length);
  for (let i = 0; i < binaryString.length; i++) {
    bytes[i] = binaryString.charCodeAt(i);
  }
  return bytes.buffer;
}

/* 
DEPLOYMENT INSTRUCTIONS:

1. Get APNs credentials from Apple Developer:
   - Log in to https://developer.apple.com
   - Go to Certificates, Identifiers & Profiles
   - Create an APNs Key (or use existing)
   - Download the .p8 file and note the Key ID and Team ID

2. Set environment variables in Supabase:
   supabase secrets set APNS_KEY_ID="YOUR_KEY_ID"
   supabase secrets set APNS_TEAM_ID="YOUR_TEAM_ID"
   supabase secrets set APNS_BUNDLE_ID="com.rockout.app"
   supabase secrets set APNS_AUTH_KEY="-----BEGIN PRIVATE KEY-----\nYOUR_KEY_CONTENT\n-----END PRIVATE KEY-----"
   supabase secrets set APNS_PRODUCTION="false"  # Set to "true" for production

3. Deploy the function:
   supabase functions deploy send_push_notification

4. Test the function:
   curl -X POST 'https://YOUR_PROJECT.supabase.co/functions/v1/send_push_notification' \
     -H 'Authorization: Bearer YOUR_ANON_KEY' \
     -H 'Content-Type: application/json' \
     -d '{"user_id":"USER_UUID","title":"Test","body":"This is a test notification"}'

5. Set up database trigger to call this function when notifications are created
   (see notification_triggers.sql for trigger setup)
*/

