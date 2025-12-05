// Supabase Edge Function: Sync Artist Engagement
// Fetches engagement data (album saves, track likes, playlist adds) from Spotify API
// Updates user_artist_engagement table
// Should be called periodically or on-demand when user opens artist page

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface SpotifyAlbum {
  id: string
  artists: Array<{ id: string; name: string }>
}

interface SpotifyTrack {
  id: string
  artists: Array<{ id: string; name: string }>
}

interface SpotifyPlaylist {
  id: string
  tracks: {
    items: Array<{
      track: SpotifyTrack | null
    }>
  }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { userId, accessToken } = await req.json()

    if (!userId || !accessToken) {
      throw new Error('userId and accessToken are required')
    }

    // Create Supabase client
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

    const engagementMap = new Map<string, { albumSaves: number; trackLikes: number; playlistAdds: number }>()

    // Fetch saved albums
    try {
      const albumsResponse = await fetch('https://api.spotify.com/v1/me/albums?limit=50', {
        headers: {
          'Authorization': `Bearer ${accessToken}`
        }
      })

      if (albumsResponse.ok) {
        const albumsData = await albumsResponse.json()
        albumsData.items?.forEach((item: { album: SpotifyAlbum }) => {
          item.album.artists?.forEach(artist => {
            const existing = engagementMap.get(artist.id) || { albumSaves: 0, trackLikes: 0, playlistAdds: 0 }
            existing.albumSaves++
            engagementMap.set(artist.id, existing)
          })
        })
      }
    } catch (error) {
      console.error('Error fetching saved albums:', error)
    }

    // Fetch liked tracks
    try {
      const tracksResponse = await fetch('https://api.spotify.com/v1/me/tracks?limit=50', {
        headers: {
          'Authorization': `Bearer ${accessToken}`
        }
      })

      if (tracksResponse.ok) {
        const tracksData = await tracksResponse.json()
        tracksData.items?.forEach((item: { track: SpotifyTrack }) => {
          item.track.artists?.forEach(artist => {
            const existing = engagementMap.get(artist.id) || { albumSaves: 0, trackLikes: 0, playlistAdds: 0 }
            existing.trackLikes++
            engagementMap.set(artist.id, existing)
          })
        })
      }
    } catch (error) {
      console.error('Error fetching liked tracks:', error)
    }

    // Fetch user playlists and count artist tracks
    try {
      const playlistsResponse = await fetch('https://api.spotify.com/v1/me/playlists?limit=50', {
        headers: {
          'Authorization': `Bearer ${accessToken}`
        }
      })

      if (playlistsResponse.ok) {
        const playlistsData = await playlistsResponse.json()
        
        for (const playlist of playlistsData.items || []) {
          const playlistTracksResponse = await fetch(`https://api.spotify.com/v1/playlists/${playlist.id}/tracks`, {
            headers: {
              'Authorization': `Bearer ${accessToken}`
            }
          })

          if (playlistTracksResponse.ok) {
            const playlistTracksData = await playlistTracksResponse.json()
            const artistCounts = new Map<string, number>()
            
            playlistTracksData.items?.forEach((item: { track: SpotifyTrack | null }) => {
              item.track?.artists?.forEach(artist => {
                artistCounts.set(artist.id, (artistCounts.get(artist.id) || 0) + 1)
              })
            })

            artistCounts.forEach((count, artistId) => {
              const existing = engagementMap.get(artistId) || { albumSaves: 0, trackLikes: 0, playlistAdds: 0 }
              existing.playlistAdds += count
              engagementMap.set(artistId, existing)
            })
          }
        }
      }
    } catch (error) {
      console.error('Error fetching playlists:', error)
    }

    // Upsert engagement data
    const upserts = Array.from(engagementMap.entries()).map(([artistId, engagement]) => ({
      user_id: userId,
      artist_id: artistId,
      album_saves: engagement.albumSaves,
      track_likes: engagement.trackLikes,
      playlist_adds: engagement.playlistAdds,
      updated_at: new Date().toISOString()
    }))

    if (upserts.length > 0) {
      const { error: upsertError } = await supabaseClient
        .from('user_artist_engagement')
        .upsert(upserts, { onConflict: 'user_id,artist_id' })

      if (upsertError) {
        throw upsertError
      }
    }

    // Update engagement_score in rocklist_stats
    for (const [artistId, engagement] of engagementMap.entries()) {
      const engagementScore = engagement.albumSaves * 3 + engagement.trackLikes * 1 + engagement.playlistAdds * 2
      
      await supabaseClient
        .from('rocklist_stats')
        .update({ engagement_score: engagementScore })
        .eq('user_id', userId)
        .eq('artist_id', artistId)
    }

    return new Response(
      JSON.stringify({
        success: true,
        processed: upserts.length
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

