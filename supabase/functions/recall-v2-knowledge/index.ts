// Supabase Edge Function: recall-v2-knowledge
// Answers music-related questions with web search and citations
// Deploy with: supabase functions deploy recall-v2-knowledge
// Requires: OPENAI_API_KEY secret

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface KnowledgeRequest {
  job_id: string;
  recall_id: string;
  query_text: string;
  user_preferences?: {
    question_styles?: string[];
  };
}

interface Source {
  title: string;
  url: string;
  snippet?: string;
  publisher?: string;
  verified: boolean;
}

interface Answer {
  text: string;
  sources: Source[];
  related_songs?: Array<{title: string; artist: string}>;
  confidence: number;
  uncertainty_noted: boolean;
}

// Reputable source domains whitelist
const REPUTABLE_DOMAINS = [
  "spotify.com",
  "music.apple.com",
  "youtube.com",
  "youtu.be",
  "wikipedia.org",
  "genius.com",
  "allmusic.com",
  "billboard.com",
  "pitchfork.com",
  "rollingstone.com",
  "nme.com",
  "theguardian.com",
  "bbc.com",
  "npr.org",
  "nytimes.com"
];

// Validate source URL is accessible and extract metadata
async function validateSource(url: string): Promise<Source | null> {
  try {
    // Check if domain is reputable
    const urlObj = new URL(url);
    const domain = urlObj.hostname.replace("www.", "");
    const isReputable = REPUTABLE_DOMAINS.some(rd => domain.includes(rd));

    // Try HEAD request first (faster)
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 5000); // 5s timeout

    const headResponse = await fetch(url, {
      method: "HEAD",
      signal: controller.signal,
      headers: {
        "User-Agent": "Mozilla/5.0 (compatible; RecallBot/1.0)"
      }
    });

    clearTimeout(timeoutId);

    if (!headResponse.ok && headResponse.status !== 405) {
      // If HEAD not allowed, try GET
      const getController = new AbortController();
      const getTimeoutId = setTimeout(() => getController.abort(), 5000);
      
      const getResponse = await fetch(url, {
        method: "GET",
        signal: getController.signal,
        headers: {
          "User-Agent": "Mozilla/5.0 (compatible; RecallBot/1.0)"
        }
      });

      clearTimeout(getTimeoutId);

      if (!getResponse.ok) {
        return null;
      }
    }

    // Extract title from URL or use domain as fallback
    let title = domain;
    try {
      // For Wikipedia, try to extract article title
      if (domain.includes("wikipedia.org")) {
        const pathParts = urlObj.pathname.split("/");
        if (pathParts.length >= 3) {
          title = decodeURIComponent(pathParts[2].replace(/_/g, " "));
        }
      } else {
        // For other sites, use domain + path
        title = domain + urlObj.pathname;
      }
    } catch (e) {
      // Keep domain as title
    }

    return {
      title,
      url,
      publisher: domain,
      verified: isReputable && (headResponse.ok || headResponse.status === 405)
    };
  } catch (error) {
    if (error.name === "AbortError") {
      console.error(`Source validation timeout: ${url}`);
    } else {
      console.error(`Source validation error for ${url}:`, error);
    }
    return null;
  }
}

// Search web using GPT-4o's browsing capability
async function searchWebWithGPT(
  query: string,
  openaiApiKey: string
): Promise<Source[]> {
  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 60000); // 60s timeout

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
            content: `You are a music research assistant. Search the web for accurate, current information about music. 
            Return a JSON array of sources with: title, url, snippet, publisher.
            Prioritize reputable sources: official artist pages, major music publications, Wikipedia, streaming platforms.
            Return at least 3 sources. Never invent URLs - only return sources you actually found.`
          },
          {
            role: "user",
            content: `Search for: ${query}`
          }
        ],
        response_format: { type: "json_object" },
        temperature: 0.3,
        max_tokens: 2000
      }),
      signal: controller.signal
    });

    clearTimeout(timeoutId);

    if (!response.ok) {
      console.error("GPT-4o web search error:", response.status);
      return [];
    }

    const data = await response.json();
    const content = data.choices[0]?.message?.content;
    
    if (!content) {
      return [];
    }

    const result = JSON.parse(content);
    const sources = result.sources || [];

    // Validate all sources
    const validatedSources: Source[] = [];
    for (const source of sources.slice(0, 5)) { // Limit to 5 sources
      if (source.url) {
        const validated = await validateSource(source.url);
        if (validated) {
          validatedSources.push({
            ...validated,
            snippet: source.snippet || undefined
          });
        }
      }
    }

    return validatedSources;
  } catch (error) {
    if (error.name === "AbortError") {
      console.error("Web search timeout");
    } else {
      console.error("Web search error:", error);
    }
    return [];
  }
}

// Synthesize answer from sources
async function synthesizeAnswer(
  query: string,
  sources: Source[],
  openaiApiKey: string,
  userPreferences?: any
): Promise<Answer> {
  if (sources.length === 0) {
    return {
      text: "I couldn't find reliable sources to answer your question. Could you rephrase it or provide more context?",
      sources: [],
      confidence: 0.0,
      uncertainty_noted: true
    };
  }

  try {
    const sourcesText = sources.map((s, i) => 
      `[${i + 1}] ${s.title} (${s.publisher}): ${s.snippet || s.url}`
    ).join("\n");

    const userContext = userPreferences?.question_styles ? 
      `User prefers: ${userPreferences.question_styles.join(", ")}. ` : "";

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
            content: `You are a music knowledge assistant. Answer questions based ONLY on the provided sources.
            ${userContext}
            Rules:
            1. Base your answer ONLY on the sources provided
            2. If sources conflict, mention the conflict and present both sides
            3. If sources are insufficient, say "I'm not sure" and explain why
            4. Cite sources using [1], [2], etc.
            5. Be concise but comprehensive (2-3 paragraphs max)
            6. If relevant, suggest related songs in related_songs array
            7. Return JSON: {text: string, confidence: 0.0-1.0, uncertainty_noted: boolean, related_songs?: []}`
          },
          {
            role: "user",
            content: `Question: ${query}\n\nSources:\n${sourcesText}\n\nAnswer the question based on these sources.`
          }
        ],
        response_format: { type: "json_object" },
        temperature: 0.3,
        max_tokens: 1000
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
    
    return {
      text: result.text || "I couldn't generate an answer from the sources.",
      sources: sources,
      related_songs: result.related_songs || [],
      confidence: result.confidence || 0.5,
      uncertainty_noted: result.uncertainty_noted || false
    };
  } catch (error) {
    console.error("Answer synthesis error:", error);
    return {
      text: "I encountered an error while generating an answer. Please try again.",
      sources: sources,
      confidence: 0.3,
      uncertainty_noted: true
    };
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
    const body: KnowledgeRequest = await req.json();
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
        operation: "knowledge_start",
        status: "processing",
        metadata: { job_id, query: query_text.substring(0, 100) }
      });

    // Search web for sources
    console.log("Searching web for sources...");
    const sources = await searchWebWithGPT(query_text, openaiApiKey);

    if (sources.length === 0) {
      // No sources found
      await supabase
        .from("recalls")
        .update({
          status: "done",
          error_message: "No sources found"
        })
        .eq("id", recall_id);

      await supabase
        .from("recall_jobs")
        .update({
          status: "done",
          completed_at: new Date().toISOString()
        })
        .eq("id", job_id);

      return new Response(
        JSON.stringify({
          status: "done",
          request_id: requestId,
          answer: {
            text: "I couldn't find reliable sources to answer your question. Could you rephrase it or provide more context?",
            sources: [],
            confidence: 0.0,
            uncertainty_noted: true
          }
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" }
        }
      );
    }

    // Synthesize answer from sources
    console.log(`Synthesizing answer from ${sources.length} sources...`);
    const answer = await synthesizeAnswer(query_text, sources, openaiApiKey, user_preferences);

    // Write answer to recall_messages (if thread_id exists)
    const { data: recall } = await supabase
      .from("recalls")
      .select("thread_id")
      .eq("id", recall_id)
      .single();

    if (recall?.thread_id) {
      const { data: user } = await supabase
        .from("recalls")
        .select("user_id")
        .eq("id", recall_id)
        .single();

      if (user) {
        await supabase
          .from("recall_messages")
          .insert({
            thread_id: recall.thread_id,
            user_id: user.user_id,
            role: "assistant",
            message_type: "text",
            text: answer.text,
            sources_json: sources.map(s => ({
              title: s.title,
              url: s.url,
              snippet: s.snippet,
              publisher: s.publisher
            }))
          });
      }
    }

    // Write sources to database
    for (const source of sources) {
      await supabase
        .from("recall_sources")
        .insert({
          recall_id: recall_id,
          title: source.title,
          url: source.url,
          snippet: source.snippet,
          publisher: source.publisher,
          verified: source.verified
        });
    }

    // Update recall with answer
    await supabase
      .from("recalls")
      .update({
        status: "done",
        result_json: {
          answer: answer.text,
          sources: sources,
          related_songs: answer.related_songs,
          confidence: answer.confidence,
          uncertainty_noted: answer.uncertainty_noted
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
        operation: "knowledge_complete",
        duration_ms: duration,
        status: "success",
        metadata: {
          job_id,
          sources_found: sources.length,
          confidence: answer.confidence,
          uncertainty_noted: answer.uncertainty_noted
        }
      });

    return new Response(
      JSON.stringify({
        status: "done",
        request_id: requestId,
        answer: answer
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" }
      }
    );

  } catch (error) {
    console.error("Error in recall-v2-knowledge:", error);
    
    const duration = Date.now() - startTime;
    const errorMessage = error instanceof Error ? error.message : String(error);

    // Try to update job and recall status
    try {
      const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
      const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
      const supabase = createClient(supabaseUrl, supabaseKey);
      
      const body: KnowledgeRequest = await req.json();
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
          operation: "knowledge_error",
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

















