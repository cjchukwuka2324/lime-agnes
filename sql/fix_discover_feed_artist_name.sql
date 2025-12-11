-- ============================================
-- Fix Artist Name in Discover Feed Functions
-- ============================================
-- This migration updates get_discover_feed_albums and get_user_discovered_albums
-- to prioritize the album's local artist_name field over studio_artists.name

-- Step 1: Update get_discover_feed_albums function
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
            AND da.discovered_at >= v_one_week_ago
        ), 0) * 20
        + (random() * 50)
    ) DESC, a.created_at DESC
    LIMIT p_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION get_discover_feed_albums(UUID, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_discover_feed_albums(UUID, INT) TO anon;

-- Step 2: Update get_user_discovered_albums function
DROP FUNCTION IF EXISTS get_user_discovered_albums(UUID) CASCADE;

CREATE FUNCTION get_user_discovered_albums(p_user_id UUID)
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
    discovered_at TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
BEGIN
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
        da.discovered_at::TEXT as discovered_at
    FROM albums a
    INNER JOIN discovered_albums da ON da.album_id = a.id
    LEFT JOIN studio_artists sa ON sa.id = a.artist_id
    WHERE 
        da.user_id = p_user_id
    ORDER BY da.discovered_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION get_user_discovered_albums(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_user_discovered_albums(UUID) TO anon;


