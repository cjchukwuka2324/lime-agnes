-- Update get_rocklist_for_artist function to use listener_score instead of score
-- Also fix time filtering to use last_played_at instead of updated_at
-- Fix profile join to use p.id instead of p.user_id

DROP FUNCTION IF EXISTS get_rocklist_for_artist(TEXT, TIMESTAMPTZ, TIMESTAMPTZ, TEXT);

CREATE OR REPLACE FUNCTION get_rocklist_for_artist(
    p_artist_id TEXT,
    p_start_timestamp TIMESTAMPTZ,
    p_end_timestamp TIMESTAMPTZ,
    p_region TEXT DEFAULT NULL
)
RETURNS TABLE (
    artist_id TEXT,
    artist_name TEXT,
    artist_image_url TEXT,
    user_id UUID,
    display_name TEXT,
    score NUMERIC,
    listener_score NUMERIC,
    rank BIGINT,
    is_current_user BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_user_id UUID;
BEGIN
    -- Get current authenticated user
    v_current_user_id := auth.uid();
    
    RETURN QUERY
    WITH ranked_stats AS (
        SELECT
            rls.artist_id,
            a.name AS artist_name,
            a.image_url AS artist_image_url,
            rls.user_id,
            COALESCE(p.display_name, u.email, 'Anonymous') AS display_name,
            CASE 
                WHEN rls.listener_score IS NOT NULL AND rls.listener_score > 0 
                THEN rls.listener_score
                WHEN rls.score > 0 
                THEN LEAST(100.0, (rls.total_ms_played / 60000.0) * 0.1)  -- Convert ms to minutes, then scale (rough estimate)
                ELSE 0
            END AS listener_score,
            RANK() OVER (ORDER BY 
                CASE 
                    WHEN rls.listener_score IS NOT NULL AND rls.listener_score > 0 
                    THEN rls.listener_score
                    WHEN rls.score > 0 
                    THEN LEAST(100.0, (rls.total_ms_played / 60000.0) * 0.1)
                    ELSE 0
                END DESC, 
                rls.total_ms_played DESC, 
                rls.user_id
            ) AS rank,
            (rls.user_id = v_current_user_id) AS is_current_user
        FROM rocklist_stats rls
        INNER JOIN artists a ON a.spotify_id = rls.artist_id
        LEFT JOIN profiles p ON p.id = rls.user_id
        LEFT JOIN auth.users u ON u.id = rls.user_id
        WHERE rls.artist_id = p_artist_id
            AND rls.last_played_at >= p_start_timestamp
            AND rls.last_played_at <= p_end_timestamp
            AND (p_region IS NULL OR rls.region = p_region)
            AND rls.play_count > 0
    ),
    top_20 AS (
        SELECT 
            rs.artist_id,
            rs.artist_name,
            rs.artist_image_url,
            rs.user_id,
            rs.display_name,
            rs.listener_score,
            rs.rank,
            rs.is_current_user
        FROM ranked_stats rs
        ORDER BY rs.rank ASC
        LIMIT 20
    ),
    current_user_entry AS (
        SELECT 
            rs.artist_id,
            rs.artist_name,
            rs.artist_image_url,
            rs.user_id,
            rs.display_name,
            rs.listener_score,
            rs.rank,
            rs.is_current_user
        FROM ranked_stats rs
        WHERE rs.is_current_user = TRUE
        LIMIT 1
    ),
    combined_results AS (
        SELECT 
            t.artist_id,
            t.artist_name,
            t.artist_image_url,
            t.user_id,
            t.display_name,
            t.listener_score,
            t.rank,
            t.is_current_user
        FROM top_20 t
        UNION ALL
        SELECT 
            c.artist_id,
            c.artist_name,
            c.artist_image_url,
            c.user_id,
            c.display_name,
            c.listener_score,
            c.rank,
            c.is_current_user
        FROM current_user_entry c
        WHERE NOT EXISTS (
            SELECT 1 
            FROM top_20 t2 
            WHERE t2.user_id = c.user_id
        )
    )
    SELECT DISTINCT ON (cr.user_id)
        cr.artist_id,
        cr.artist_name,
        cr.artist_image_url,
        cr.user_id,
        cr.display_name,
        cr.listener_score AS score,  -- Legacy field for backward compatibility
        cr.listener_score,
        cr.rank,
        cr.is_current_user
    FROM combined_results cr
    ORDER BY cr.user_id, cr.rank ASC;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION get_rocklist_for_artist(TEXT, TIMESTAMPTZ, TIMESTAMPTZ, TEXT) TO authenticated;

