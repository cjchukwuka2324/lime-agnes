-- Update get_my_rocklist_summary function to use listener_score and fix time filtering

DROP FUNCTION IF EXISTS get_my_rocklist_summary(TIMESTAMPTZ, TIMESTAMPTZ, TEXT);

CREATE OR REPLACE FUNCTION get_my_rocklist_summary(
    p_start_timestamp TIMESTAMPTZ,
    p_end_timestamp TIMESTAMPTZ,
    p_region TEXT DEFAULT NULL
)
RETURNS TABLE (
    artist_id TEXT,
    artist_name TEXT,
    artist_image_url TEXT,
    my_rank BIGINT,
    my_listener_score NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_user_id UUID;
BEGIN
    v_current_user_id := auth.uid();
    
    RETURN QUERY
    WITH user_stats AS (
        SELECT
            rls.artist_id,
            rls.listener_score,
            RANK() OVER (
                PARTITION BY rls.artist_id, COALESCE(rls.region, 'GLOBAL')
                ORDER BY COALESCE(rls.listener_score, 0) DESC, rls.total_ms_played DESC, rls.user_id
            ) AS rank
        FROM rocklist_stats rls
        WHERE rls.user_id = v_current_user_id
            AND rls.last_played_at >= p_start_timestamp  -- Fixed: use last_played_at instead of updated_at
            AND rls.last_played_at <= p_end_timestamp
            AND (p_region IS NULL OR rls.region = p_region)
    ),
    artist_info AS (
        SELECT DISTINCT
            rls.artist_id,
            a.name AS artist_name,
            a.image_url AS artist_image_url
        FROM rocklist_stats rls
        INNER JOIN artists a ON a.spotify_id = rls.artist_id
        WHERE rls.user_id = v_current_user_id
            AND rls.last_played_at >= p_start_timestamp  -- Fixed: use last_played_at instead of updated_at
            AND rls.last_played_at <= p_end_timestamp
            AND (p_region IS NULL OR rls.region = p_region)
    )
    SELECT
        ai.artist_id,
        ai.artist_name,
        ai.artist_image_url,
        us.rank AS my_rank,
        us.listener_score AS my_listener_score
    FROM artist_info ai
    LEFT JOIN user_stats us ON us.artist_id = ai.artist_id
    WHERE COALESCE(us.listener_score, 0) > 0 OR us.listener_score IS NULL
    ORDER BY us.rank ASC NULLS LAST;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION get_my_rocklist_summary(TIMESTAMPTZ, TIMESTAMPTZ, TEXT) TO authenticated;

