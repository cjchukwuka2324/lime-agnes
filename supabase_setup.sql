-- ============================================
-- RockList Backend Setup for Supabase (Corrected)
-- ============================================
-- Copy and paste this entire file into Supabase SQL Editor
-- Run it to create all required tables and RPC functions
-- ============================================

-- ============================================
-- 1. CREATE TABLES
-- ============================================

-- Table: rocklist_stats
CREATE TABLE IF NOT EXISTS rocklist_stats (
    user_id UUID NOT NULL REFERENCES auth.users(id),
    artist_id TEXT NOT NULL,
    region TEXT NOT NULL, -- Country code (e.g., 'US', 'NG', 'GB')
    play_count BIGINT NOT NULL DEFAULT 0,
    total_ms_played BIGINT NOT NULL DEFAULT 0,
    score NUMERIC NOT NULL DEFAULT 0,
    last_played_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (user_id, artist_id, region)
);

CREATE INDEX IF NOT EXISTS idx_rocklist_stats_artist_region ON rocklist_stats(artist_id, region);
CREATE INDEX IF NOT EXISTS idx_rocklist_stats_score ON rocklist_stats(artist_id, region, score DESC);
CREATE INDEX IF NOT EXISTS idx_rocklist_stats_updated ON rocklist_stats(updated_at);

-- Table: user_comments
CREATE TABLE IF NOT EXISTS user_comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id),
    artist_id TEXT, -- Used for RockList comments
    studio_session_id UUID, -- Used for StudioSessions comments (future)
    content TEXT NOT NULL,
    region TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_comments_artist ON user_comments(artist_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_comments_studio_session ON user_comments(studio_session_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_comments_user ON user_comments(user_id);

-- Table: user_follows
CREATE TABLE IF NOT EXISTS user_follows (
    follower_id UUID NOT NULL REFERENCES auth.users(id),
    followed_id UUID NOT NULL REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (follower_id, followed_id),
    CHECK (follower_id != followed_id)
);

CREATE INDEX IF NOT EXISTS idx_user_follows_follower ON user_follows(follower_id);
CREATE INDEX IF NOT EXISTS idx_user_follows_followed ON user_follows(followed_id);

-- Table: artists
-- Stores artist metadata from Spotify
CREATE TABLE IF NOT EXISTS artists (
    spotify_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    image_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_artists_spotify_id ON artists(spotify_id);

-- Table: profiles
-- User profile information
CREATE TABLE IF NOT EXISTS profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id),
    display_name TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_profiles_id ON profiles(id);

-- Table: rocklist_user_state
-- Tracks last ingestion timestamp per user for incremental updates
CREATE TABLE IF NOT EXISTS rocklist_user_state (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    last_ingested_played_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_rocklist_user_state_user ON rocklist_user_state(user_id);

-- ============================================
-- 2. CREATE RPC FUNCTIONS (explicit columns / hardened)
-- ============================================

-- Function: get_rocklist_for_artist
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
    rank BIGINT,
    is_current_user BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_user_id UUID;
BEGIN
    v_current_user_id := (SELECT auth.uid());
    
    RETURN QUERY
    WITH ranked_stats AS (
        SELECT
            rls.artist_id,
            a.name AS artist_name,
            a.image_url AS artist_image_url,
            rls.user_id,
            COALESCE(p.display_name, u.email, 'Anonymous') AS display_name,
            rls.score,
            RANK() OVER (ORDER BY rls.score DESC) AS rank,
            (rls.user_id = v_current_user_id) AS is_current_user
        FROM rocklist_stats rls
        INNER JOIN artists a ON a.spotify_id = rls.artist_id
        LEFT JOIN profiles p ON p.id = rls.user_id
        LEFT JOIN auth.users u ON u.id = rls.user_id
        WHERE rls.artist_id = p_artist_id
            AND rls.updated_at >= p_start_timestamp
            AND rls.updated_at <= p_end_timestamp
            AND (p_region IS NULL OR rls.region = p_region)
    ),
    top_20 AS (
        SELECT
            rs.artist_id,
            rs.artist_name,
            rs.artist_image_url,
            rs.user_id,
            rs.display_name,
            rs.score,
            rs.rank,
            rs.is_current_user
        FROM ranked_stats rs
        WHERE rs.rank <= 20
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
            rs.score,
            rs.rank,
            rs.is_current_user
        FROM ranked_stats rs
        WHERE rs.is_current_user = TRUE
        LIMIT 1
    ),
    combined_results AS (
        SELECT
            t20.artist_id,
            t20.artist_name,
            t20.artist_image_url,
            t20.user_id,
            t20.display_name,
            t20.score,
            t20.rank,
            t20.is_current_user
        FROM top_20 t20
        UNION ALL
        SELECT
            cue.artist_id,
            cue.artist_name,
            cue.artist_image_url,
            cue.user_id,
            cue.display_name,
            cue.score,
            cue.rank,
            cue.is_current_user
        FROM current_user_entry cue
        WHERE NOT EXISTS (
            SELECT 1 FROM top_20 t20_inner WHERE t20_inner.user_id = cue.user_id
        )
    )
    SELECT DISTINCT ON (cr.user_id)
        cr.artist_id,
        cr.artist_name,
        cr.artist_image_url,
        cr.user_id,
        cr.display_name,
        cr.score,
        cr.rank,
        cr.is_current_user
    FROM combined_results cr
    ORDER BY cr.user_id, cr.rank ASC;
END;
$$;

-- Function: get_my_rocklist_summary
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
    my_score NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_user_id UUID;
BEGIN
    v_current_user_id := (SELECT auth.uid());
    
    RETURN QUERY
    WITH all_ranked_stats AS (
        SELECT
            rls.artist_id,
            rls.user_id,
            rls.score,
            RANK() OVER (
                PARTITION BY rls.artist_id, COALESCE(rls.region, 'GLOBAL')
                ORDER BY rls.score DESC
            ) AS rank
        FROM rocklist_stats rls
        WHERE rls.updated_at >= p_start_timestamp
            AND rls.updated_at <= p_end_timestamp
            AND (p_region IS NULL OR rls.region = p_region)
    ),
    user_stats AS (
        SELECT
            ars.artist_id,
            ars.score AS my_score,
            ars.rank AS my_rank
        FROM all_ranked_stats ars
        WHERE ars.user_id = v_current_user_id
    ),
    artist_info AS (
        SELECT DISTINCT
            us.artist_id,
            a.name AS artist_name,
            a.image_url AS artist_image_url,
            us.my_rank,
            us.my_score
        FROM user_stats us
        INNER JOIN artists a ON a.spotify_id = us.artist_id
        WHERE us.artist_id IS NOT NULL
    )
    SELECT
        ai.artist_id,
        ai.artist_name,
        ai.artist_image_url,
        ai.my_rank,
        ai.my_score
    FROM artist_info ai
    ORDER BY ai.my_rank ASC NULLS LAST, ai.artist_name ASC;
END;
$$;

-- Function: post_rocklist_comment
-- Drop existing function first to allow structure changes
DROP FUNCTION IF EXISTS post_rocklist_comment(TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION post_rocklist_comment(
    p_artist_id TEXT,
    p_content TEXT,
    p_region TEXT DEFAULT NULL
)
RETURNS TABLE (
    id UUID,
    user_id UUID,
    display_name TEXT,
    content TEXT,
    created_at TIMESTAMPTZ,
    artist_id TEXT,
    studio_session_id UUID,
    comment_type TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_user_id UUID;
    v_comment_id UUID;
BEGIN
    v_current_user_id := (SELECT auth.uid());
    
    IF v_current_user_id IS NULL THEN
        RAISE EXCEPTION 'User must be authenticated';
    END IF;
    
    -- Insert comment first, then query it back
    -- This completely separates INSERT from SELECT to avoid any ambiguity
    INSERT INTO user_comments (user_id, artist_id, content, region)
    VALUES (v_current_user_id, p_artist_id, p_content, p_region);
    
    -- Get the ID of the just-inserted comment
    SELECT user_comments.id INTO STRICT v_comment_id
    FROM user_comments
    WHERE user_comments.user_id = v_current_user_id
      AND user_comments.artist_id = p_artist_id
      AND user_comments.content = p_content
      AND (user_comments.region = p_region OR (user_comments.region IS NULL AND p_region IS NULL))
    ORDER BY user_comments.created_at DESC
    LIMIT 1;
    
    -- Return the created comment with user info
    RETURN QUERY
    SELECT
        uc.id,
        uc.user_id,
        COALESCE(p.display_name, u.email, 'Anonymous') AS display_name,
        uc.content,
        uc.created_at,
        uc.artist_id,
        uc.studio_session_id,
        CASE
            WHEN uc.artist_id IS NOT NULL THEN 'rocklist'
            WHEN uc.studio_session_id IS NOT NULL THEN 'studio_session'
            ELSE 'unknown'
        END AS comment_type
    FROM user_comments uc
    LEFT JOIN profiles p ON p.id = uc.user_id
    LEFT JOIN auth.users u ON u.id = uc.user_id
    WHERE uc.id = v_comment_id;
END;
$$;

-- Function: get_rocklist_comments_for_artist
CREATE OR REPLACE FUNCTION get_rocklist_comments_for_artist(
    p_artist_id TEXT,
    p_start_timestamp TIMESTAMPTZ,
    p_end_timestamp TIMESTAMPTZ
)
RETURNS TABLE (
    id UUID,
    user_id UUID,
    display_name TEXT,
    content TEXT,
    created_at TIMESTAMPTZ,
    artist_id TEXT,
    studio_session_id UUID,
    comment_type TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        uc.id,
        uc.user_id,
        COALESCE(p.display_name, u.email, 'Anonymous') AS display_name,
        uc.content,
        uc.created_at,
        uc.artist_id,
        uc.studio_session_id,
        CASE
            WHEN uc.artist_id IS NOT NULL THEN 'rocklist'
            WHEN uc.studio_session_id IS NOT NULL THEN 'studio_session'
            ELSE 'unknown'
        END AS comment_type
    FROM user_comments uc
    LEFT JOIN profiles p ON p.id = uc.user_id
    LEFT JOIN auth.users u ON u.id = uc.user_id
    WHERE uc.artist_id = p_artist_id
        AND uc.created_at >= p_start_timestamp
        AND uc.created_at <= p_end_timestamp
    ORDER BY uc.created_at DESC;
END;
$$;

-- Function: get_following_feed
-- Drop existing function first to allow return type change
DROP FUNCTION IF EXISTS get_following_feed(TIMESTAMPTZ, TIMESTAMPTZ);

CREATE OR REPLACE FUNCTION get_following_feed(
    p_start_timestamp TIMESTAMPTZ,
    p_end_timestamp TIMESTAMPTZ
)
RETURNS TABLE (
    comment_id UUID,
    user_id UUID,
    display_name TEXT,
    content TEXT,
    created_at TIMESTAMPTZ,
    artist_id TEXT,
    artist_name TEXT,
    artist_image_url TEXT,
    studio_session_id UUID,
    comment_type TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_user_id UUID;
BEGIN
    v_current_user_id := (SELECT auth.uid());
    
    IF v_current_user_id IS NULL THEN
        RAISE EXCEPTION 'User must be authenticated';
    END IF;
    
    RETURN QUERY
    SELECT
        uc.id AS comment_id,
        uc.user_id,
        COALESCE(p.display_name, u.email, 'Anonymous') AS display_name,
        uc.content,
        uc.created_at,
        uc.artist_id,
        a.name AS artist_name,
        a.image_url AS artist_image_url,
        uc.studio_session_id,
        CASE
            WHEN uc.artist_id IS NOT NULL THEN 'rocklist'
            WHEN uc.studio_session_id IS NOT NULL THEN 'studio_session'
            ELSE 'unknown'
        END AS comment_type
    FROM user_comments uc
    LEFT JOIN profiles p ON p.id = uc.user_id
    LEFT JOIN auth.users u ON u.id = uc.user_id
    LEFT JOIN artists a ON a.spotify_id = uc.artist_id
    WHERE (
        -- Include comments from users the current user follows
        EXISTS (
            SELECT 1 FROM user_follows uf
            WHERE uf.follower_id = v_current_user_id
            AND uf.followed_id = uc.user_id
        )
        -- OR include the current user's own comments
        OR uc.user_id = v_current_user_id
    )
    AND uc.created_at >= p_start_timestamp
    AND uc.created_at <= p_end_timestamp
    ORDER BY uc.created_at DESC;
END;
$$;

-- ============================================
-- 3. GRANT PERMISSIONS (if needed)
-- ============================================

-- Function: rocklist_ingest_plays
-- Ingests play events from Spotify and updates rocklist_stats
CREATE OR REPLACE FUNCTION rocklist_ingest_plays(p_events JSONB)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := (SELECT auth.uid());
    v_event JSONB;
    v_artist_id TEXT;
    v_artist_name TEXT;
    v_track_id TEXT;
    v_track_name TEXT;
    v_played_at TIMESTAMPTZ;
    v_duration_ms INT;
    v_region TEXT;
    v_max_played_at TIMESTAMPTZ := NULL;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'rocklist_ingest_plays must be called by an authenticated user';
    END IF;

    -- Process each event
    FOR v_event IN
        SELECT * FROM jsonb_array_elements(p_events)
    LOOP
        v_artist_id   := v_event->>'artistId';
        v_artist_name := v_event->>'artistName';
        v_track_id    := v_event->>'trackId';
        v_track_name  := v_event->>'trackName';
        v_played_at   := (v_event->>'playedAt')::TIMESTAMPTZ;
        v_duration_ms := (v_event->>'durationMs')::INT;
        v_region      := COALESCE(v_event->>'region', 'GLOBAL');

        IF v_artist_id IS NULL OR v_played_at IS NULL THEN
            CONTINUE;
        END IF;

        -- Upsert into rocklist_stats
        INSERT INTO rocklist_stats (
            user_id, 
            artist_id, 
            region, 
            play_count, 
            total_ms_played, 
            last_played_at, 
            score, 
            updated_at
        )
        VALUES (
            v_user_id, 
            v_artist_id, 
            v_region, 
            1, 
            COALESCE(v_duration_ms, 0), 
            v_played_at, 
            0, 
            NOW()
        )
        ON CONFLICT (user_id, artist_id, region) DO UPDATE
        SET 
            play_count = rocklist_stats.play_count + 1,
            total_ms_played = rocklist_stats.total_ms_played + COALESCE(EXCLUDED.total_ms_played, 0),
            last_played_at = GREATEST(rocklist_stats.last_played_at, EXCLUDED.last_played_at),
            updated_at = NOW();

        -- Track max played_at for user state update
        IF v_max_played_at IS NULL OR v_played_at > v_max_played_at THEN
            v_max_played_at := v_played_at;
        END IF;

        -- Upsert artist metadata if not exists
        INSERT INTO artists (spotify_id, name, created_at)
        VALUES (v_artist_id, COALESCE(v_artist_name, 'Unknown Artist'), NOW())
        ON CONFLICT (spotify_id) DO NOTHING;
    END LOOP;

    -- Update user state with latest played_at
    IF v_max_played_at IS NOT NULL THEN
        INSERT INTO rocklist_user_state (user_id, last_ingested_played_at, updated_at)
        VALUES (v_user_id, v_max_played_at, NOW())
        ON CONFLICT (user_id) DO UPDATE
        SET 
            last_ingested_played_at = GREATEST(
                COALESCE(rocklist_user_state.last_ingested_played_at, '1970-01-01'::TIMESTAMPTZ),
                EXCLUDED.last_ingested_played_at
            ),
            updated_at = NOW();
    END IF;

    -- Recalculate scores for all affected artists for this user
    UPDATE rocklist_stats
    SET 
        score = play_count::NUMERIC + (total_ms_played::NUMERIC / 1000000.0),
        updated_at = NOW()
    WHERE user_id = v_user_id;
END;
$$;

-- Function: get_rocklist_user_state
-- Returns the last ingested timestamp for the current user
CREATE OR REPLACE FUNCTION get_rocklist_user_state()
RETURNS TABLE (
    last_ingested_played_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID;
BEGIN
    v_user_id := (SELECT auth.uid());
    
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'User must be authenticated';
    END IF;
    
    RETURN QUERY
    SELECT rus.last_ingested_played_at
    FROM rocklist_user_state rus
    WHERE rus.user_id = v_user_id;
END;
$$;

-- Grant execute permissions on functions to authenticated users
GRANT EXECUTE ON FUNCTION get_rocklist_for_artist TO authenticated;
GRANT EXECUTE ON FUNCTION get_my_rocklist_summary TO authenticated;
GRANT EXECUTE ON FUNCTION post_rocklist_comment TO authenticated;
GRANT EXECUTE ON FUNCTION get_rocklist_comments_for_artist TO authenticated;
GRANT EXECUTE ON FUNCTION get_following_feed TO authenticated;
GRANT EXECUTE ON FUNCTION rocklist_ingest_plays TO authenticated;
GRANT EXECUTE ON FUNCTION get_rocklist_user_state TO authenticated;

-- ============================================
-- Setup Complete!
-- ============================================
-- All tables and RPC functions have been created/updated.
-- You can now use the RockList feature in your iOS app.
-- ============================================
