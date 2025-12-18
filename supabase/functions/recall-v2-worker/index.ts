// Supabase Edge Function: recall-v2-worker
// Processes jobs from recall_jobs queue with retries and timeouts
// Deploy with: supabase functions deploy recall-v2-worker
// Can be triggered via cron or manually

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface Job {
  id: string;
  recall_id: string;
  user_id: string;
  job_type: "identify" | "knowledge" | "recommend";
  status: string;
  retry_count: number;
  max_retries: number;
  request_id?: string;
}

// Circuit breaker state
const circuitBreakers = new Map<string, { failures: number; lastFailure: number; open: boolean }>();

// Check circuit breaker
function isCircuitOpen(service: string): boolean {
  const breaker = circuitBreakers.get(service);
  if (!breaker) return false;
  
  if (breaker.open) {
    // Check if we should try again (5 minutes cooldown)
    if (Date.now() - breaker.lastFailure > 5 * 60 * 1000) {
      breaker.open = false;
      breaker.failures = 0;
      return false;
    }
    return true;
  }
  
  return false;
}

// Record circuit breaker failure
function recordFailure(service: string) {
  const breaker = circuitBreakers.get(service) || { failures: 0, lastFailure: 0, open: false };
  breaker.failures++;
  breaker.lastFailure = Date.now();
  
  // Open circuit after 5 consecutive failures
  if (breaker.failures >= 5) {
    breaker.open = true;
    console.log(`Circuit breaker opened for ${service}`);
  }
  
  circuitBreakers.set(service, breaker);
}

// Record circuit breaker success
function recordSuccess(service: string) {
  const breaker = circuitBreakers.get(service);
  if (breaker) {
    breaker.failures = 0;
    breaker.open = false;
    circuitBreakers.set(service, breaker);
  }
}

// Call appropriate engine function
async function processJob(job: Job, supabase: any): Promise<{ success: boolean; error?: string }> {
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const functionUrl = `${supabaseUrl}/functions/v1/recall-v2-${job.job_type}`;
  
  // Check circuit breaker
  if (isCircuitOpen(job.job_type)) {
    console.log(`Circuit breaker is open for ${job.job_type}, skipping job ${job.id}`);
    return { success: false, error: "Circuit breaker is open" };
  }

  try {
    // Get recall data
    const { data: recall, error: recallError } = await supabase
      .from("recalls")
      .select("*")
      .eq("id", job.recall_id)
      .single();

    if (recallError || !recall) {
      throw new Error("Recall not found");
    }

    // Build request body based on job type
    let requestBody: any = {
      job_id: job.id,
      recall_id: job.recall_id
    };

    if (job.job_type === "identify") {
      if (!recall.audio_path) {
        throw new Error("Audio path missing for identify job");
      }
      requestBody.audio_path = recall.audio_path;
      requestBody.input_type = recall.input_type || "voice";
    } else if (job.job_type === "knowledge" || job.job_type === "recommend") {
      if (!recall.query_text) {
        throw new Error("Query text missing for knowledge/recommend job");
      }
      requestBody.query_text = recall.query_text;
    }

    // Fetch user preferences if available
    const { data: preferences } = await supabase
      .from("recall_user_preferences")
      .select("preference_type, preference_data")
      .eq("user_id", job.user_id)
      .gt("confidence_score", 0.3);

    if (preferences && preferences.length > 0) {
      const prefs: any = {};
      preferences.forEach((p: any) => {
        if (p.preference_type === "genre_preference") {
          prefs.genre_preferences = p.preference_data.genres || [];
        } else if (p.preference_type === "artist_preference") {
          prefs.artist_preferences = p.preference_data.artists || [];
        } else if (p.preference_type === "search_pattern") {
          prefs.search_patterns = p.preference_data.patterns || [];
        } else if (p.preference_type === "question_style") {
          prefs.question_styles = p.preference_data.styles || [];
        }
      });
      requestBody.user_preferences = prefs;
    }

    // Call engine function
    const controller = new AbortController();
    const timeoutDuration = job.job_type === "identify" ? 120000 : 60000; // 2min for identify, 1min for others
    const timeoutId = setTimeout(() => controller.abort(), timeoutDuration);

    const response = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`
      },
      body: JSON.stringify(requestBody),
      signal: controller.signal
    });

    clearTimeout(timeoutId);

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`Engine function error: ${response.status} - ${errorText}`);
    }

    const result = await response.json();
    
    if (result.error) {
      throw new Error(result.error);
    }

    // Success
    recordSuccess(job.job_type);
    return { success: true };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    console.error(`Error processing job ${job.id}:`, errorMessage);
    
    // Record failure for circuit breaker
    recordFailure(job.job_type);
    
    return { success: false, error: errorMessage };
  }
}

// Process a single job
async function processSingleJob(job: Job, supabase: any): Promise<void> {
  const startTime = Date.now();
  
  try {
    // Mark job as processing
    await supabase
      .from("recall_jobs")
      .update({
        status: "processing",
        started_at: new Date().toISOString()
      })
      .eq("id", job.id);

    // Process the job
    const result = await processJob(job, supabase);

    const duration = Date.now() - startTime;

    if (result.success) {
      // Job completed successfully
      await supabase
        .from("recall_jobs")
        .update({
          status: "done",
          completed_at: new Date().toISOString()
        })
        .eq("id", job.id);

      await supabase
        .from("recall_logs")
        .insert({
          request_id: job.request_id || `req_${job.id}`,
          user_id: job.user_id,
          recall_id: job.recall_id,
          operation: `worker_${job.job_type}`,
          duration_ms: duration,
          status: "success",
          metadata: { job_id: job.id, job_type: job.job_type }
        });
    } else {
      // Job failed - check if we should retry
      const shouldRetry = job.retry_count < job.max_retries;
      
      if (shouldRetry) {
        const newRetryCount = job.retry_count + 1;
        const backoffSeconds = Math.pow(2, newRetryCount) * 5; // Exponential backoff: 10s, 20s, 40s
        const scheduledAt = new Date(Date.now() + backoffSeconds * 1000);

        await supabase
          .from("recall_jobs")
          .update({
            status: "retrying",
            retry_count: newRetryCount,
            scheduled_at: scheduledAt.toISOString(),
            error_message: result.error
          })
          .eq("id", job.id);

        await supabase
          .from("recall_logs")
          .insert({
            request_id: job.request_id || `req_${job.id}`,
            user_id: job.user_id,
            recall_id: job.recall_id,
            operation: `worker_${job.job_type}_retry`,
            duration_ms: duration,
            status: "retrying",
            error_message: result.error,
            metadata: { job_id: job.id, retry_count: newRetryCount }
          });
      } else {
        // Max retries reached - mark as failed
        await supabase
          .from("recall_jobs")
          .update({
            status: "failed",
            completed_at: new Date().toISOString(),
            error_message: result.error || "Max retries reached"
          })
          .eq("id", job.id);

        await supabase
          .from("recalls")
          .update({
            status: "failed",
            error_message: result.error || "Max retries reached"
          })
          .eq("id", job.recall_id);

        await supabase
          .from("recall_logs")
          .insert({
            request_id: job.request_id || `req_${job.id}`,
            user_id: job.user_id,
            recall_id: job.recall_id,
            operation: `worker_${job.job_type}_failed`,
            duration_ms: duration,
            status: "error",
            error_message: result.error || "Max retries reached",
            metadata: { job_id: job.id, retry_count: job.retry_count }
          });
      }
    }
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    console.error(`Unexpected error processing job ${job.id}:`, errorMessage);

    await supabase
      .from("recall_jobs")
      .update({
        status: "failed",
        error_message: errorMessage,
        completed_at: new Date().toISOString()
      })
      .eq("id", job.id);
  }
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

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

    // Parse request body (optional - can be triggered via cron)
    const body = req.method === "POST" ? await req.json().catch(() => ({})) : {};
    const { job_id, max_jobs = 10 } = body;

    if (job_id) {
      // Process specific job
      const { data: job, error } = await supabase
        .from("recall_jobs")
        .select("*")
        .eq("id", job_id)
        .single();

      if (error || !job) {
        return new Response(
          JSON.stringify({ error: "Job not found" }),
          { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      await processSingleJob(job as Job, supabase);

      return new Response(
        JSON.stringify({ status: "processed", job_id: job.id }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Process queued jobs (up to max_jobs)
    const { data: jobs, error: jobsError } = await supabase
      .from("recall_jobs")
      .select("*")
      .in("status", ["queued", "retrying"])
      .lte("scheduled_at", new Date().toISOString())
      .order("scheduled_at", { ascending: true })
      .limit(max_jobs);

    if (jobsError) {
      throw jobsError;
    }

    if (!jobs || jobs.length === 0) {
      return new Response(
        JSON.stringify({ status: "no_jobs", processed: 0 }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Process jobs in parallel (but limit concurrency)
    const concurrency = 3; // Process 3 jobs at a time
    const results = [];

    for (let i = 0; i < jobs.length; i += concurrency) {
      const batch = jobs.slice(i, i + concurrency);
      const batchPromises = batch.map(job => processSingleJob(job as Job, supabase));
      await Promise.all(batchPromises);
      results.push(...batch.map(j => ({ id: j.id, status: "processed" })));
    }

    return new Response(
      JSON.stringify({
        status: "processed",
        processed: results.length,
        jobs: results
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (error) {
    console.error("Error in recall-v2-worker:", error);
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




