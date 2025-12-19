// Supabase Edge Function: recall-v2-router
// Routes recall requests to appropriate engine (identify/knowledge/recommend)
// Deploy with: supabase functions deploy recall-v2-router
// Requires: OPENAI_API_KEY secret (for intent detection)

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface RouterRequest {
  recall_id: string;
  input_type: "text" | "voice" | "image" | "background" | "hum";
  query_text?: string;
  image_path?: string;
  audio_path?: string;
  thread_id?: string; // Optional: for conversational context
}

interface UserPreferences {
  genre_preferences?: string[];
  artist_preferences?: string[];
  search_patterns?: string[];
  question_styles?: string[];
  rejected_artists?: string[];
  corrections?: Array<{original: string; corrected: string}>;
}

interface IntentDetection {
  intent: "identify" | "knowledge" | "recommend" | "conversation" | "generate";
  confidence: number;
  reasoning: string;
}

// Detect user intent from query
async function detectIntent(
  queryText: string | null,
  inputType: string,
  userPreferences: UserPreferences | null,
  supabase: any
): Promise<IntentDetection> {
  // If audio/voice/hum input, likely identify
  if (inputType === "voice" || inputType === "background" || inputType === "hum") {
    return {
      intent: "identify",
      confidence: 0.9,
      reasoning: "Audio input detected"
    };
  }

  // If no query text, default to identify
  if (!queryText || queryText.trim().length === 0) {
    return {
      intent: "identify",
      confidence: 0.7,
      reasoning: "No query text provided"
    };
  }

  const queryLower = queryText.toLowerCase();

  // Mood DJ keywords
  const moodKeywords = [
    "feeling", "mood", "vibe", "recommend", "suggest", "playlist",
    "workout", "sad", "happy", "energetic", "chill", "relax", "party",
    "study", "focus", "sleep", "motivated", "depressed", "excited"
  ];
  const hasMoodIntent = moodKeywords.some(kw => queryLower.includes(kw));

  // Knowledge/question keywords
  const questionKeywords = [
    "who wrote", "when was", "what album", "tell me about", "explain",
    "how", "why", "what is", "who is", "where", "history", "news",
    "facts", "information", "about"
  ];
  const hasQuestionIntent = questionKeywords.some(kw => queryLower.includes(kw));

  // Search/identify keywords
  const searchKeywords = [
    "find", "search", "identify", "what song", "name that song",
    "who sings", "recognize", "remember", "lyrics", "melody", "hum"
  ];
  const hasSearchIntent = searchKeywords.some(kw => queryLower.includes(kw));

  // Conversation keywords (casual chat)
  const conversationKeywords = [
    "hi", "hello", "hey", "how are you", "what's up", "thanks", "thank you",
    "cool", "nice", "awesome", "okay", "sure", "yeah", "yep", "nope"
  ];
  const hasConversationIntent = conversationKeywords.some(kw => queryLower.includes(kw));

  // Generation keywords
  const generateKeywords = [
    "create", "generate", "make", "compose", "write a song", "produce", "build",
    "make music", "create music", "generate music", "make a beat", "create a melody"
  ];
  const hasGenerateIntent = generateKeywords.some(kw => queryLower.includes(kw));

  // Use OpenAI for more sophisticated intent detection if available
  const openaiApiKey = Deno.env.get("OPENAI_API_KEY");
  if (openaiApiKey && queryText.length > 10) {
    try {
      const response = await fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${openaiApiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: "gpt-4o-mini", // Use cheaper model for intent detection
          messages: [
            {
              role: "system",
              content: `Determine the user's intent for this music query. Return JSON with:
- intent: "identify" (finding a song), "knowledge" (asking a question), "recommend" (wanting recommendations), "conversation" (casual chat), or "generate" (creating music)
- confidence: 0.0-1.0
- reasoning: brief explanation

Examples:
- "what song has the lyrics 'hello darkness my old friend'" → identify
- "who wrote bohemian rhapsody" → knowledge
- "I'm feeling sad, recommend some songs" → recommend
- "how are you" or "thanks" → conversation
- "create a song" or "make a beat" → generate`
            },
            {
              role: "user",
              content: queryText
            }
          ],
          response_format: { type: "json_object" },
          temperature: 0.1,
          max_tokens: 100
        }),
      });

      if (response.ok) {
        const data = await response.json();
        const content = data.choices[0]?.message?.content;
        if (content) {
          const result = JSON.parse(content);
          return {
            intent: result.intent || "identify",
            confidence: result.confidence || 0.7,
            reasoning: result.reasoning || "AI detected intent"
          };
        }
      }
    } catch (error) {
      console.error("OpenAI intent detection error:", error);
    }
  }

  // Fallback to keyword-based detection
  if (hasGenerateIntent) {
    return {
      intent: "generate",
      confidence: 0.8,
      reasoning: "Generation keywords detected"
    };
  }

  if (hasConversationIntent && !hasQuestionIntent && !hasSearchIntent) {
    return {
      intent: "conversation",
      confidence: 0.8,
      reasoning: "Conversation keywords detected"
    };
  }

  if (hasMoodIntent && !hasQuestionIntent) {
    return {
      intent: "recommend",
      confidence: 0.8,
      reasoning: "Mood/recommendation keywords detected"
    };
  }

  if (hasQuestionIntent && !hasSearchIntent) {
    return {
      intent: "knowledge",
      confidence: 0.8,
      reasoning: "Question keywords detected"
    };
  }

  if (hasSearchIntent) {
    return {
      intent: "identify",
      confidence: 0.8,
      reasoning: "Search/identify keywords detected"
    };
  }

  // Default to identify
  return {
    intent: "identify",
    confidence: 0.6,
    reasoning: "Default fallback"
  };
}

// Fetch user preferences for personalization
async function fetchUserPreferences(
  userId: string,
  supabase: any
): Promise<UserPreferences | null> {
  try {
    const { data, error } = await supabase
      .from("recall_user_preferences")
      .select("preference_type, preference_data, confidence_score")
      .eq("user_id", userId)
      .gt("confidence_score", 0.3); // Only use preferences with decent confidence

    if (error || !data || data.length === 0) {
      return null;
    }

    const preferences: UserPreferences = {};

    for (const pref of data) {
      switch (pref.preference_type) {
        case "genre_preference":
          preferences.genre_preferences = pref.preference_data.genres || [];
          break;
        case "artist_preference":
          preferences.artist_preferences = pref.preference_data.artists || [];
          break;
        case "search_pattern":
          preferences.search_patterns = pref.preference_data.patterns || [];
          break;
        case "question_style":
          preferences.question_styles = pref.preference_data.styles || [];
          break;
      }
    }

    // Fetch rejected artists from feedback
    const { data: feedback } = await supabase
      .from("recall_feedback")
      .select("context_json")
      .eq("user_id", userId)
      .eq("feedback_type", "reject")
      .limit(20);

    if (feedback && feedback.length > 0) {
      const rejectedArtists = new Set<string>();
      feedback.forEach(f => {
        const artists = f.context_json?.rejected_artists || [];
        artists.forEach((a: string) => rejectedArtists.add(a));
      });
      preferences.rejected_artists = Array.from(rejectedArtists);
    }

    return preferences;
  } catch (error) {
    console.error("Error fetching user preferences:", error);
    return null;
  }
}

// Generate request ID for idempotency
function generateRequestId(): string {
  return `req_${Date.now()}_${Math.random().toString(36).substring(2, 15)}`;
}

// Rate limiting: Check if user/IP has exceeded limits
async function checkRateLimit(
  userId: string,
  clientIp: string | null,
  supabase: any
): Promise<{ allowed: boolean; retryAfter?: number }> {
  const now = new Date();
  const oneMinuteAgo = new Date(now.getTime() - 60 * 1000);

  // Per-user limit: 10 recalls/minute
  const { count: userCount } = await supabase
    .from("recalls")
    .select("*", { count: "exact", head: true })
    .eq("user_id", userId)
    .gte("created_at", oneMinuteAgo.toISOString());

  if (userCount && userCount >= 10) {
    return { allowed: false, retryAfter: 60 };
  }

  // Per-IP limit: 20 recalls/minute (if IP available)
  if (clientIp) {
    const { count: ipCount } = await supabase
      .from("recall_logs")
      .select("*", { count: "exact", head: true })
      .eq("metadata->>ip", clientIp)
      .gte("created_at", oneMinuteAgo.toISOString());

    if (ipCount && ipCount >= 20) {
      return { allowed: false, retryAfter: 60 };
    }
  }

  return { allowed: true };
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
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
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false
      }
    });

    // Verify user
    const { data: { user }, error: authError } = await supabase.auth.getUser(
      authHeader.replace("Bearer ", "")
    );

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: "Invalid authentication" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Get client IP for rate limiting
    const clientIp = req.headers.get("x-forwarded-for") || 
                     req.headers.get("x-real-ip") || 
                     null;

    // Check rate limits
    const rateLimit = await checkRateLimit(user.id, clientIp, supabase);
    if (!rateLimit.allowed) {
      return new Response(
        JSON.stringify({
          error: "Rate limit exceeded",
          retry_after: rateLimit.retryAfter
        }),
        {
          status: 429,
          headers: {
            ...corsHeaders,
            "Content-Type": "application/json",
            "Retry-After": String(rateLimit.retryAfter || 60)
          }
        }
      );
    }

    // Parse request body
    const body: RouterRequest = await req.json();
    const { recall_id, input_type, query_text, image_path, audio_path, thread_id } = body;

    if (!recall_id) {
      return new Response(
        JSON.stringify({ error: "recall_id is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Check if recall exists and belongs to user
    const { data: recall, error: recallError } = await supabase
      .from("recalls")
      .select("*")
      .eq("id", recall_id)
      .eq("user_id", user.id)
      .single();

    if (recallError || !recall) {
      return new Response(
        JSON.stringify({ error: "Recall not found or access denied" }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Idempotency check: if already processing, return existing request_id
    if (recall.status === "processing" || recall.status === "queued") {
      return new Response(
        JSON.stringify({
          status: "already_queued",
          request_id: recall.request_id,
          message: "Recall is already being processed"
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Generate request ID
    const requestId = generateRequestId();

    // Fetch user preferences for personalization
    const userPreferences = await fetchUserPreferences(user.id, supabase);

    // Detect intent
    const intentDetection = await detectIntent(
      query_text || recall.query_text,
      input_type,
      userPreferences,
      supabase
    );

    console.log(`Intent detected: ${intentDetection.intent} (confidence: ${intentDetection.confidence})`);

    // Determine job type
    let jobType: "identify" | "knowledge" | "recommend";
    if (intentDetection.intent === "identify") {
      jobType = "identify";
    } else if (intentDetection.intent === "knowledge" || intentDetection.intent === "conversation") {
      jobType = "knowledge";
    } else if (intentDetection.intent === "generate") {
      jobType = "recommend"; // Map generate to recommend for now (could add new job type later)
    } else {
      jobType = "recommend";
    }

    // Create job in queue
    const { data: job, error: jobError } = await supabase
      .from("recall_jobs")
      .insert({
        recall_id: recall_id,
        user_id: user.id,
        job_type: jobType,
        status: "queued",
        request_id: requestId,
        scheduled_at: new Date().toISOString()
      })
      .select()
      .single();

    if (jobError || !job) {
      console.error("Error creating job:", jobError);
      return new Response(
        JSON.stringify({ error: "Failed to create job", details: jobError?.message }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Update recall status
    await supabase
      .from("recalls")
      .update({
        status: "queued",
        request_id: requestId
      })
      .eq("id", recall_id);

    // Log the routing decision
    await supabase
      .from("recall_logs")
      .insert({
        request_id: requestId,
        user_id: user.id,
        recall_id: recall_id,
        operation: "router",
        status: "success",
        metadata: {
          intent: intentDetection.intent,
          confidence: intentDetection.confidence,
          reasoning: intentDetection.reasoning,
          job_type: jobType,
          job_id: job.id,
          ip: clientIp
        }
      });

    return new Response(
      JSON.stringify({
        status: "queued",
        request_id: requestId,
        job_id: job.id,
        job_type: jobType,
        intent: intentDetection.intent,
        confidence: intentDetection.confidence,
        reasoning: intentDetection.reasoning
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" }
      }
    );

  } catch (error) {
    console.error("Error in recall-v2-router:", error);
    return new Response(
      JSON.stringify({
        error: "Internal server error",
        details: error instanceof Error ? error.message : String(error)
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" }
      }
    );
  }
});

