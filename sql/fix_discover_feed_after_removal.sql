-- ============================================
-- Fix Discover Feed After Album Removal
-- ============================================
-- This migration updates get_discover_feed_albums to explicitly check
-- saved_from_discover = true, ensuring albums that were saved and removed
-- can appear again in the discover feed

-- Step 1: Drop and recreate get_discover_feed_albums with explicit saved_from_discover check
DROP FUNCTION IF EXISTS get_discover_feed_albums(UUID, INT) CASCADE;

CREATE FUNCTION get_discover_feed_albums(
    p_user_id UUID,
    p_limit INT DEFAULT 50
)
RETURNS TABLE (
    id UUID,
    artist_id UUID,
    title TEXT,
    cover_art_url TEXT,
    release_status TEXT,
    release_date TEXT,
    artist_name TEXT,
    created_at TEXT,
    updated_at TEXT,
    is_public BOOLEAN,
    discover_score NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
DECLARE
    v_seven_days_ago TIMESTAMPTZ := NOW() - INTERVAL '7 days';
    v_fourteen_days_ago TIMESTAMPTZ := NOW() - INTERVAL '14 days';
    v_one_week_ago TIMESTAMPTZ := NOW() - INTERVAL '7 days';
    v_user_following UUID[];
    v_high_follower_threshold INT := 10000;
BEGIN
    SELECT COALESCE(ARRAY_AGG(following_id), ARRAY[]::UUID[]) INTO v_user_following
    FROM user_follows
    WHERE follower_id = p_user_id;

    RETURN QUERY
    SELECT 
        a.id::UUID,
        a.artist_id::UUID,
        a.title::TEXT,
        a.cover_art_url::TEXT,
        a.release_status::TEXT,
        a.release_date::TEXT,
        COALESCE(a.artist_name, sa.name, '')::TEXT as artist_name,
        a.created_at::TEXT as created_at,
        a.updated_at::TEXT as updated_at,
        COALESCE(a.is_public, false)::BOOLEAN as is_public,
        (
            CASE WHEN a.created_at >= v_seven_days_ago THEN 100 ELSE 50 END
            + CASE 
                WHEN COALESCE(p.followers_count, 0) = 0 THEN 100
                WHEN COALESCE(p.followers_count, 0) < 100 THEN 80
                WHEN COALESCE(p.followers_count, 0) < 500 THEN 60
                WHEN COALESCE(p.followers_count, 0) < 1000 THEN 40
                WHEN COALESCE(p.followers_count, 0) < 5000 THEN 20
                ELSE 0
            END
            - CASE 
                WHEN COALESCE(p.followers_count, 0) >= v_high_follower_threshold 
                     AND NOT (a.artist_id = ANY(COALESCE(v_user_following, ARRAY[]::UUID[]))) 
                THEN 50
                ELSE 0
            END
            + COALESCE(e.completion_rate * 30, 0)
            + COALESCE(e.save_rate * 40, 0)
            + COALESCE(e.total_saves * 0.5, 0)
            + COALESCE(e.plays_per_viewer * 5, 0)
            + CASE 
                WHEN COALESCE(e.daily_play_growth, 0) > 1.2 THEN 30
                WHEN COALESCE(e.daily_play_growth, 0) > 1.0 THEN 15
                ELSE 0
            END
            + COALESCE(e.avg_replay_count * 10, 0)
            - COALESCE((
                SELECT COUNT(*)::INT
                FROM discovered_albums da 
                WHERE da.album_id = a.id 
                AND da.user_id = p_user_id
                AND da.saved_from_discover = true  -- Only count active saves
                AND da.discovered_at >= v_one_week_ago
            ), 0) * 20
            + (random() * 50)
        )::NUMERIC as discover_score
    FROM albums a
    INNER JOIN profiles p ON p.id = a.artist_id
    LEFT JOIN studio_artists sa ON sa.id = a.artist_id
    LEFT JOIN album_engagement_signals e ON e.album_id = a.id
    WHERE 
        a.is_public = true
        AND a.created_at >= v_fourteen_days_ago
        AND a.created_at <= NOW() - INTERVAL '1 day'
        AND a.artist_id != p_user_id
        AND COALESCE((
            SELECT COUNT(*)::INT
            FROM discovered_albums da 
            WHERE da.album_id = a.id 
            AND da.user_id = p_user_id
            AND da.saved_from_discover = true  -- Only count currently saved albums (excludes removed ones)
            AND da.discovered_at >= v_one_week_ago
        ), 0) < 2
    ORDER BY (
        CASE WHEN a.created_at >= v_seven_days_ago THEN 100 ELSE 50 END
        + CASE 
            WHEN COALESCE(p.followers_count, 0) = 0 THEN 100
            WHEN COALESCE(p.followers_count, 0) < 100 THEN 80
            WHEN COALESCE(p.followers_count, 0) < 500 THEN 60
            WHEN COALESCE(p.followers_count, 0) < 1000 THEN 40
            WHEN COALESCE(p.followers_count, 0) < 5000 THEN 20
            ELSE 0
        END
        - CASE 
            WHEN COALESCE(p.followers_count, 0) >= v_high_follower_threshold 
                 AND NOT (a.artist_id = ANY(COALESCE(v_user_following, ARRAY[]::UUID[]))) 
            THEN 50
            ELSE 0
        END
        + COALESCE(e.completion_rate * 30, 0)
        + COALESCE(e.save_rate * 40, 0)
        + COALESCE(e.total_saves * 0.5, 0)
        + COALESCE(e.plays_per_viewer * 5, 0)
        + CASE 
            WHEN COALESCE(e.daily_play_growth, 0) > 1.2 THEN 30
            WHEN COALESCE(e.daily_play_growth, 0) > 1.0 THEN 15
            ELSE 0
        END
        + COALESCE(e.avg_replay_count * 10, 0)
        - COALESCE((
            SELECT COUNT(*)::INT
            FROM discovered_albums da 
            WHERE da.album_id = a.id 
            AND da.user_id = p_user_id
            AND da.saved_from_discover = true  -- Only count active saves
            AND da.discovered_at >= v_one_week_ago
        ), 0) * 20
        + (random() * 50)
    ) DESC, a.created_at DESC
    LIMIT p_limit;
END;
$$;

-- Step 2: Grant execute permissions
GRANT EXECUTE ON FUNCTION get_discover_feed_albums(UUID, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_discover_feed_albums(UUID, INT) TO anon;

-- Comments for documentation
COMMENT ON FUNCTION get_discover_feed_albums IS 'Returns ranked public albums for discover feed, excluding albums currently saved by the user (allows albums that were previously saved and removed to reappear)';
