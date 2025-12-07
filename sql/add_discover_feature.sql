-- ============================================
-- Discover Feature Schema - FRESH MIGRATION
-- ============================================

-- Step 1: Create discovered_albums table
CREATE TABLE IF NOT EXISTS discovered_albums (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    album_id UUID NOT NULL REFERENCES albums(id) ON DELETE CASCADE,
    saved_from_discover BOOLEAN DEFAULT true,
    discovered_at TIMESTAMPTZ DEFAULT NOW(),
    completed_listen BOOLEAN DEFAULT false,
    replay_count INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, album_id)
);

CREATE INDEX IF NOT EXISTS idx_discovered_albums_user_id ON discovered_albums(user_id);
CREATE INDEX IF NOT EXISTS idx_discovered_albums_album_id ON discovered_albums(album_id);
CREATE INDEX IF NOT EXISTS idx_discovered_albums_discovered_at ON discovered_albums(discovered_at DESC);

ALTER TABLE discovered_albums ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own discovered albums" ON discovered_albums;
CREATE POLICY "Users can view own discovered albums"
    ON discovered_albums FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own discovered albums" ON discovered_albums;
CREATE POLICY "Users can insert own discovered albums"
    ON discovered_albums FOR INSERT
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own discovered albums" ON discovered_albums;
CREATE POLICY "Users can update own discovered albums"
    ON discovered_albums FOR UPDATE
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own discovered albums" ON discovered_albums;
CREATE POLICY "Users can delete own discovered albums"
    ON discovered_albums FOR DELETE
    USING (auth.uid() = user_id);

-- Step 2: Drop and recreate engagement signals view
DROP VIEW IF EXISTS album_engagement_signals CASCADE;

CREATE VIEW album_engagement_signals AS
SELECT 
    a.id as album_id,
    COUNT(DISTINCT da.user_id) as total_saves,
    COUNT(DISTINCT CASE WHEN da.completed_listen = true THEN da.user_id END)::DECIMAL / NULLIF(COUNT(DISTINCT da.user_id), 0) as completion_rate,
    COUNT(DISTINCT da.user_id)::DECIMAL / NULLIF(COUNT(DISTINCT CASE WHEN a.is_public = true THEN 1 END), 0) as save_rate,
    COUNT(DISTINCT tpc.track_id)::DECIMAL / NULLIF(COUNT(DISTINCT da.user_id), 0) as plays_per_viewer,
    AVG(da.replay_count) as avg_replay_count,
    CASE 
        WHEN COUNT(DISTINCT CASE WHEN da.discovered_at >= NOW() - INTERVAL '1 day' THEN da.user_id END) > 0 
        THEN COUNT(DISTINCT CASE WHEN da.discovered_at >= NOW() - INTERVAL '2 days' THEN da.user_id END)::DECIMAL / 
             NULLIF(COUNT(DISTINCT CASE WHEN da.discovered_at >= NOW() - INTERVAL '1 day' THEN da.user_id END), 0)
        ELSE 0
    END as daily_play_growth
FROM albums a
LEFT JOIN discovered_albums da ON da.album_id = a.id
LEFT JOIN track_play_counts tpc ON tpc.album_id = a.id
WHERE a.is_public = true
GROUP BY a.id;

GRANT SELECT ON album_engagement_signals TO authenticated;
GRANT SELECT ON album_engagement_signals TO anon;

-- Step 3: Drop and recreate get_discover_feed_albums - SIMPLIFIED
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
        COALESCE(sa.name, '')::TEXT as artist_name,
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

-- Step 4: Drop and recreate get_user_discovered_albums - SIMPLIFIED
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
        COALESCE(sa.name, '')::TEXT as artist_name,
        a.created_at::TEXT as created_at,
        a.updated_at::TEXT as updated_at,
        COALESCE(a.is_public, false)::BOOLEAN as is_public,
        da.discovered_at::TEXT as discovered_at
    FROM albums a
    INNER JOIN discovered_albums da ON da.album_id = a.id
    LEFT JOIN studio_artists sa ON sa.id = a.artist_id
    WHERE 
        da.user_id = p_user_id
        AND da.saved_from_discover = true
    ORDER BY da.discovered_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION get_user_discovered_albums(UUID) TO authenticated;

-- Step 5: Create RPC function for getting users who saved an album
DROP FUNCTION IF EXISTS get_users_who_saved_album(UUID) CASCADE;

CREATE FUNCTION get_users_who_saved_album(p_album_id UUID)
RETURNS TABLE (
    user_id UUID,
    username TEXT,
    display_name TEXT,
    first_name TEXT,
    last_name TEXT,
    profile_picture_url TEXT,
    discovered_at TIMESTAMPTZ,
    completed_listen BOOLEAN,
    replay_count INT
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        da.user_id,
        p.username,
        p.display_name,
        p.first_name,
        p.last_name,
        p.profile_picture_url,
        da.discovered_at,
        da.completed_listen,
        da.replay_count
    FROM discovered_albums da
    INNER JOIN profiles p ON p.id = da.user_id
    WHERE 
        da.album_id = p_album_id
        AND da.saved_from_discover = true
    ORDER BY da.discovered_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION get_users_who_saved_album(UUID) TO authenticated;

-- Step 6: Create RPC function for saving discovered album
DROP FUNCTION IF EXISTS save_discovered_album(UUID, UUID) CASCADE;

CREATE FUNCTION save_discovered_album(p_album_id UUID, p_user_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO discovered_albums (user_id, album_id, saved_from_discover)
    VALUES (p_user_id, p_album_id, true)
    ON CONFLICT (user_id, album_id) DO UPDATE
    SET saved_from_discover = true, discovered_at = NOW();
END;
$$;

GRANT EXECUTE ON FUNCTION save_discovered_album(UUID, UUID) TO authenticated;

-- Step 7: Create RPC function for removing discovered album
DROP FUNCTION IF EXISTS remove_discovered_album(UUID, UUID) CASCADE;

CREATE FUNCTION remove_discovered_album(p_album_id UUID, p_user_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    DELETE FROM discovered_albums
    WHERE user_id = p_user_id AND album_id = p_album_id;
END;
$$;

GRANT EXECUTE ON FUNCTION remove_discovered_album(UUID, UUID) TO authenticated;

-- Step 8: Create RPC function for incrementing replay count
DROP FUNCTION IF EXISTS increment_discovered_album_replay_count(UUID, UUID) CASCADE;

CREATE FUNCTION increment_discovered_album_replay_count(p_album_id UUID, p_user_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE discovered_albums
    SET replay_count = replay_count + 1
    WHERE user_id = p_user_id AND album_id = p_album_id;
END;
$$;

GRANT EXECUTE ON FUNCTION increment_discovered_album_replay_count(UUID, UUID) TO authenticated;

-- Comments for documentation
COMMENT ON TABLE discovered_albums IS 'Tracks albums users have saved from the Discover feed';
COMMENT ON FUNCTION get_discover_feed_albums IS 'Returns ranked public albums for discover feed';
COMMENT ON FUNCTION get_user_discovered_albums IS 'Returns albums the user has saved from Discover feed';
COMMENT ON FUNCTION get_users_who_saved_album IS 'Returns users who saved a specific album';
