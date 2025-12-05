// Supabase Edge Function: Recalculate Listener Scores
// Scheduled job that periodically recalculates listener scores for all artists
// Runs every 15 minutes via Supabase cron

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Create Supabase client with service role
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      {
        auth: {
          autoRefreshToken: false,
          persistSession: false
        }
      }
    )

    // Get list of artists with active listeners (artists with stats in last 30 days)
    const thirtyDaysAgo = new Date()
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30)

    const { data: activeArtists, error: artistsError } = await supabaseClient
      .from('rocklist_stats')
      .select('artist_id, region')
      .gte('last_played_at', thirtyDaysAgo.toISOString())
      .order('last_played_at', { ascending: false })

    if (artistsError) {
      throw artistsError
    }

    // Get unique artist-region pairs
    const artistRegionPairs = new Set<string>()
    activeArtists?.forEach(stat => {
      artistRegionPairs.add(`${stat.artist_id}|${stat.region || 'GLOBAL'}`)
    })

    const pairs = Array.from(artistRegionPairs)
    console.log(`Processing ${pairs.length} artist-region pairs`)

    let processed = 0
    let errors = 0
    const errorDetails: string[] = []

    // Process in batches to avoid overwhelming the database
    const batchSize = 10
    for (let i = 0; i < pairs.length; i += batchSize) {
      const batch = pairs.slice(i, i + batchSize)
      
      await Promise.all(batch.map(async (pair) => {
        const [artistId, region] = pair.split('|')
        
        try {
          // Recalculate scores for this artist-region
          const { data, error } = await supabaseClient.rpc(
            'recalculate_artist_listener_scores',
            {
              p_artist_id: artistId,
              p_region: region || 'GLOBAL'
            }
          )

          if (error) {
            throw error
          }

          // Refresh cache for this artist
          const { error: cacheError } = await supabaseClient.rpc(
            'refresh_artist_leaderboard_cache',
            {
              p_artist_id: artistId,
              p_region: region || 'GLOBAL'
            }
          )

          if (cacheError) {
            console.error(`Cache refresh error for ${artistId}:`, cacheError)
            // Don't fail the whole job if cache refresh fails
          }

          processed++
        } catch (error) {
          errors++
          errorDetails.push(`${artistId} (${region}): ${error.message}`)
          console.error(`Error processing ${artistId}:`, error)
        }
      }))

      // Small delay between batches to avoid rate limiting
      if (i + batchSize < pairs.length) {
        await new Promise(resolve => setTimeout(resolve, 1000))
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        processed,
        errors,
        error_details: errorDetails,
        total_pairs: pairs.length
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      },
    )
  } catch (error) {
    return new Response(
      JSON.stringify({
        success: false,
        error: error.message
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500,
      },
    )
  }
})





