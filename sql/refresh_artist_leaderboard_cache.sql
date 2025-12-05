-- Refresh Artist Leaderboard Cache Function
-- Clears old cache entries for an artist and rebuilds with top 100 users
-- Should be called after recalculating listener scores

CREATE OR REPLACE FUNCTION refresh_artist_leaderboard_cache(
    p_artist_id TEXT,
    p_region TEXT DEFAULT 'GLOBAL'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_cached_count INTEGER;
BEGIN
    -- Clear old cache entries for this artist
    DELETE FROM artist_leaderboard_cache
    WHERE artist_id = p_artist_id;
    
    -- Insert top 100 users into cache
    INSERT INTO artist_leaderboard_cache (
        artist_id,
        user_id,
        listener_score,
        rank,
        cached_at
    )
    SELECT 
        rls.artist_id,
        rls.user_id,
        rls.listener_score,
        RANK() OVER (ORDER BY rls.listener_score DESC) AS rank,
        NOW()
    FROM rocklist_stats rls
    WHERE rls.artist_id = p_artist_id
        AND rls.region = p_region
        AND rls.listener_score > 0
    ORDER BY rls.listener_score DESC
    LIMIT 100;
    
    GET DIAGNOSTICS v_cached_count = ROW_COUNT;
    
    RETURN jsonb_build_object(
        'success', true,
        'artist_id', p_artist_id,
        'region', p_region,
        'cached_count', v_cached_count
    );
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', SQLERRM
        );
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION refresh_artist_leaderboard_cache(TEXT, TEXT) TO authenticated;

