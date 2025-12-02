-- ============================================
-- Update get_feed_posts to include Spotify link columns
-- ============================================
-- This script updates the get_feed_posts function to return Spotify link, poll, and background music data
-- Run this if Spotify links are not appearing in the feed
-- ============================================

-- Drop existing function(s) to avoid ambiguity
-- Drop all possible signatures of get_feed_posts
DROP FUNCTION IF EXISTS get_feed_posts() CASCADE;
DROP FUNCTION IF EXISTS get_feed_posts(TEXT) CASCADE;
DROP FUNCTION IF EXISTS get_feed_posts(TEXT, INT) CASCADE;
DROP FUNCTION IF EXISTS get_feed_posts(TEXT, INT, INT) CASCADE;
DROP FUNCTION IF EXISTS get_feed_posts(TEXT, TEXT) CASCADE;
DROP FUNCTION IF EXISTS get_feed_posts(TEXT, TEXT, INT) CASCADE;
DROP FUNCTION IF EXISTS get_feed_posts(TEXT, TEXT, INT, INT) CASCADE;

-- Recreate the function with Spotify link columns
CREATE OR REPLACE FUNCTION get_feed_posts(
    p_feed_type TEXT DEFAULT 'for_you',
    p_region TEXT DEFAULT NULL,
    p_limit INT DEFAULT 50,
    p_offset INT DEFAULT 0
)
RETURNS TABLE (
    id UUID,
    user_id UUID,
    text TEXT,
    image_urls TEXT[],
    video_url TEXT,
    audio_url TEXT,
    parent_post_id UUID,
    leaderboard_entry_id TEXT,
    leaderboard_artist_name TEXT,
    leaderboard_rank INT,
    leaderboard_percentile_label TEXT,
    leaderboard_minutes_listened INT,
    reshared_post_id UUID,
    created_at TIMESTAMPTZ,
    like_count BIGINT,
    is_liked_by_current_user BOOLEAN,
    reply_count BIGINT,
    author_display_name TEXT,
    author_handle TEXT,
    author_profile_picture_url TEXT,
    author_avatar_initials TEXT,
    spotify_link_url TEXT,
    spotify_link_type TEXT,
    spotify_link_data JSONB,
    poll_question TEXT,
    poll_type TEXT,
    poll_options JSONB,
    background_music_spotify_id TEXT,
    background_music_data JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_user_id UUID;
    v_user_region TEXT;
BEGIN
    v_current_user_id := auth.uid();
    
    IF v_current_user_id IS NULL THEN
        RAISE EXCEPTION 'User must be authenticated';
    END IF;
    
    -- Get current user's region from profile, or use provided region parameter
    -- Handle case where profile might not exist
    BEGIN
        SELECT COALESCE(p_region, prof.region) INTO v_user_region
        FROM profiles prof
        WHERE prof.id = v_current_user_id;
    EXCEPTION WHEN OTHERS THEN
        -- If profile doesn't exist or region lookup fails, use provided region or NULL
        v_user_region := p_region;
    END;
    
    RETURN QUERY
    WITH post_like_counts AS (
        SELECT 
            post_id,
            COUNT(*) as like_count
        FROM post_likes
        GROUP BY post_id
    ),
    post_reply_counts AS (
        SELECT 
            p2.parent_post_id,
            COUNT(*) as reply_count
        FROM posts p2
        WHERE p2.parent_post_id IS NOT NULL AND p2.deleted_at IS NULL
        GROUP BY p2.parent_post_id
    ),
    user_likes AS (
        SELECT pl.post_id
        FROM post_likes pl
        WHERE pl.user_id = v_current_user_id
    ),
    following_users AS (
        SELECT following_id
        FROM user_follows
        WHERE follower_id = v_current_user_id
    ),
    posts_with_scores AS (
        SELECT 
            p.id,
            p.user_id,
            p.text,
            p.image_urls,
            p.video_url,
            p.audio_url,
            p.parent_post_id,
            p.leaderboard_entry_id,
            p.leaderboard_artist_name,
            p.leaderboard_rank,
            p.leaderboard_percentile_label,
            p.leaderboard_minutes_listened,
            p.reshared_post_id,
            p.created_at,
            p.spotify_link_url,
            p.spotify_link_type,
            p.spotify_link_data,
            p.poll_question,
            p.poll_type,
            p.poll_options,
            p.background_music_spotify_id,
            p.background_music_data,
            COALESCE(plc.like_count, 0)::BIGINT as like_count,
            (ul.post_id IS NOT NULL) as is_liked_by_current_user,
            COALESCE(prc.reply_count, 0)::BIGINT as reply_count,
            COALESCE(
                NULLIF(prof.display_name, ''),
                NULLIF(u.email, ''),
                'User'
            ) as author_display_name,
            COALESCE(
                CASE 
                    WHEN prof.username IS NOT NULL AND prof.username != '' THEN '@' || prof.username
                    ELSE NULL
                END,
                CASE 
                    WHEN u.email IS NOT NULL AND u.email != '' THEN '@' || SPLIT_PART(u.email, '@', 1)
                    ELSE NULL
                END,
                '@user'
            ) as author_handle,
            NULLIF(prof.profile_picture_url, '') as author_profile_picture_url,
            CASE 
                WHEN prof.first_name IS NOT NULL AND prof.first_name != '' AND prof.last_name IS NOT NULL AND prof.last_name != '' THEN
                    UPPER(SUBSTRING(prof.first_name, 1, 1) || SUBSTRING(prof.last_name, 1, 1))
                WHEN prof.display_name IS NOT NULL AND prof.display_name != '' AND LENGTH(prof.display_name) >= 2 THEN
                    UPPER(SUBSTRING(prof.display_name, 1, 2))
                WHEN u.email IS NOT NULL AND u.email != '' THEN
                    UPPER(SUBSTRING(SPLIT_PART(u.email, '@', 1), 1, 2))
                ELSE
                    'U'
            END as author_avatar_initials,
            -- Algorithm score for "For You" feed: prioritize same region, then by engagement
            CASE 
                WHEN p_feed_type = 'for_you' AND v_user_region IS NOT NULL AND prof.region = v_user_region THEN
                    -- Same region: boost score based on recency and engagement
                    EXTRACT(EPOCH FROM (NOW() - p.created_at)) / 3600.0 + -- Hours since post (lower is better)
                    (COALESCE(plc.like_count, 0) * 0.5) + -- Engagement boost
                    (COALESCE(prc.reply_count, 0) * 0.3)
                WHEN p_feed_type = 'for_you' THEN
                    -- Different region: lower score but still included
                    EXTRACT(EPOCH FROM (NOW() - p.created_at)) / 3600.0 + -- Hours since post
                    (COALESCE(plc.like_count, 0) * 0.5) + -- Engagement boost
                    (COALESCE(prc.reply_count, 0) * 0.3) + 1000.0 -- Penalty for different region
                ELSE
                    0 -- For following feed, score doesn't matter
            END as algorithm_score
        FROM posts p
        LEFT JOIN post_like_counts plc ON plc.post_id = p.id
        LEFT JOIN post_reply_counts prc ON prc.parent_post_id = p.id
        LEFT JOIN user_likes ul ON ul.post_id = p.id
        LEFT JOIN auth.users u ON u.id = p.user_id
        LEFT JOIN profiles prof ON prof.id = p.user_id
        WHERE p.deleted_at IS NULL
            AND (
                CASE p_feed_type
                    WHEN 'following' THEN
                        -- Following feed: current user + followed users
                        (p.user_id = v_current_user_id OR p.user_id IN (SELECT following_id FROM following_users))
                    ELSE
                        -- For You feed: all posts (algorithm will prioritize by region)
                        TRUE
                END
            )
    )
    SELECT 
        pws.id,
        pws.user_id,
        pws.text,
        pws.image_urls,
        pws.video_url,
        pws.audio_url,
        pws.parent_post_id,
        pws.leaderboard_entry_id,
        pws.leaderboard_artist_name,
        pws.leaderboard_rank,
        pws.leaderboard_percentile_label,
        pws.leaderboard_minutes_listened,
        pws.reshared_post_id,
        pws.created_at,
        pws.like_count,
        pws.is_liked_by_current_user,
        pws.reply_count,
        pws.author_display_name,
        pws.author_handle,
        pws.author_profile_picture_url,
        pws.author_avatar_initials,
        pws.spotify_link_url,
        pws.spotify_link_type,
        pws.spotify_link_data,
        pws.poll_question,
        pws.poll_type,
        pws.poll_options,
        pws.background_music_spotify_id,
        pws.background_music_data
    FROM posts_with_scores pws
    ORDER BY 
        CASE 
            WHEN p_feed_type = 'for_you' THEN pws.algorithm_score
            ELSE 0
        END ASC,
        pws.created_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$;


-- ============================================
-- This script updates the get_feed_posts function to return Spotify link, poll, and background music data
-- Run this if Spotify links are not appearing in the feed
-- ============================================

-- Drop existing function(s) to avoid ambiguity
-- Drop all possible signatures of get_feed_posts
DROP FUNCTION IF EXISTS get_feed_posts() CASCADE;
DROP FUNCTION IF EXISTS get_feed_posts(TEXT) CASCADE;
DROP FUNCTION IF EXISTS get_feed_posts(TEXT, INT) CASCADE;
DROP FUNCTION IF EXISTS get_feed_posts(TEXT, INT, INT) CASCADE;
DROP FUNCTION IF EXISTS get_feed_posts(TEXT, TEXT) CASCADE;
DROP FUNCTION IF EXISTS get_feed_posts(TEXT, TEXT, INT) CASCADE;
DROP FUNCTION IF EXISTS get_feed_posts(TEXT, TEXT, INT, INT) CASCADE;

-- Recreate the function with Spotify link columns
CREATE OR REPLACE FUNCTION get_feed_posts(
    p_feed_type TEXT DEFAULT 'for_you',
    p_region TEXT DEFAULT NULL,
    p_limit INT DEFAULT 50,
    p_offset INT DEFAULT 0
)
RETURNS TABLE (
    id UUID,
    user_id UUID,
    text TEXT,
    image_urls TEXT[],
    video_url TEXT,
    audio_url TEXT,
    parent_post_id UUID,
    leaderboard_entry_id TEXT,
    leaderboard_artist_name TEXT,
    leaderboard_rank INT,
    leaderboard_percentile_label TEXT,
    leaderboard_minutes_listened INT,
    reshared_post_id UUID,
    created_at TIMESTAMPTZ,
    like_count BIGINT,
    is_liked_by_current_user BOOLEAN,
    reply_count BIGINT,
    author_display_name TEXT,
    author_handle TEXT,
    author_profile_picture_url TEXT,
    author_avatar_initials TEXT,
    spotify_link_url TEXT,
    spotify_link_type TEXT,
    spotify_link_data JSONB,
    poll_question TEXT,
    poll_type TEXT,
    poll_options JSONB,
    background_music_spotify_id TEXT,
    background_music_data JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_user_id UUID;
    v_user_region TEXT;
BEGIN
    v_current_user_id := auth.uid();
    
    IF v_current_user_id IS NULL THEN
        RAISE EXCEPTION 'User must be authenticated';
    END IF;
    
    -- Get current user's region from profile, or use provided region parameter
    -- Handle case where profile might not exist
    BEGIN
        SELECT COALESCE(p_region, prof.region) INTO v_user_region
        FROM profiles prof
        WHERE prof.id = v_current_user_id;
    EXCEPTION WHEN OTHERS THEN
        -- If profile doesn't exist or region lookup fails, use provided region or NULL
        v_user_region := p_region;
    END;
    
    RETURN QUERY
    WITH post_like_counts AS (
        SELECT 
            post_id,
            COUNT(*) as like_count
        FROM post_likes
        GROUP BY post_id
    ),
    post_reply_counts AS (
        SELECT 
            p2.parent_post_id,
            COUNT(*) as reply_count
        FROM posts p2
        WHERE p2.parent_post_id IS NOT NULL AND p2.deleted_at IS NULL
        GROUP BY p2.parent_post_id
    ),
    user_likes AS (
        SELECT pl.post_id
        FROM post_likes pl
        WHERE pl.user_id = v_current_user_id
    ),
    following_users AS (
        SELECT following_id
        FROM user_follows
        WHERE follower_id = v_current_user_id
    ),
    posts_with_scores AS (
        SELECT 
            p.id,
            p.user_id,
            p.text,
            p.image_urls,
            p.video_url,
            p.audio_url,
            p.parent_post_id,
            p.leaderboard_entry_id,
            p.leaderboard_artist_name,
            p.leaderboard_rank,
            p.leaderboard_percentile_label,
            p.leaderboard_minutes_listened,
            p.reshared_post_id,
            p.created_at,
            p.spotify_link_url,
            p.spotify_link_type,
            p.spotify_link_data,
            p.poll_question,
            p.poll_type,
            p.poll_options,
            p.background_music_spotify_id,
            p.background_music_data,
            COALESCE(plc.like_count, 0)::BIGINT as like_count,
            (ul.post_id IS NOT NULL) as is_liked_by_current_user,
            COALESCE(prc.reply_count, 0)::BIGINT as reply_count,
            COALESCE(
                NULLIF(prof.display_name, ''),
                NULLIF(u.email, ''),
                'User'
            ) as author_display_name,
            COALESCE(
                CASE 
                    WHEN prof.username IS NOT NULL AND prof.username != '' THEN '@' || prof.username
                    ELSE NULL
                END,
                CASE 
                    WHEN u.email IS NOT NULL AND u.email != '' THEN '@' || SPLIT_PART(u.email, '@', 1)
                    ELSE NULL
                END,
                '@user'
            ) as author_handle,
            NULLIF(prof.profile_picture_url, '') as author_profile_picture_url,
            CASE 
                WHEN prof.first_name IS NOT NULL AND prof.first_name != '' AND prof.last_name IS NOT NULL AND prof.last_name != '' THEN
                    UPPER(SUBSTRING(prof.first_name, 1, 1) || SUBSTRING(prof.last_name, 1, 1))
                WHEN prof.display_name IS NOT NULL AND prof.display_name != '' AND LENGTH(prof.display_name) >= 2 THEN
                    UPPER(SUBSTRING(prof.display_name, 1, 2))
                WHEN u.email IS NOT NULL AND u.email != '' THEN
                    UPPER(SUBSTRING(SPLIT_PART(u.email, '@', 1), 1, 2))
                ELSE
                    'U'
            END as author_avatar_initials,
            -- Algorithm score for "For You" feed: prioritize same region, then by engagement
            CASE 
                WHEN p_feed_type = 'for_you' AND v_user_region IS NOT NULL AND prof.region = v_user_region THEN
                    -- Same region: boost score based on recency and engagement
                    EXTRACT(EPOCH FROM (NOW() - p.created_at)) / 3600.0 + -- Hours since post (lower is better)
                    (COALESCE(plc.like_count, 0) * 0.5) + -- Engagement boost
                    (COALESCE(prc.reply_count, 0) * 0.3)
                WHEN p_feed_type = 'for_you' THEN
                    -- Different region: lower score but still included
                    EXTRACT(EPOCH FROM (NOW() - p.created_at)) / 3600.0 + -- Hours since post
                    (COALESCE(plc.like_count, 0) * 0.5) + -- Engagement boost
                    (COALESCE(prc.reply_count, 0) * 0.3) + 1000.0 -- Penalty for different region
                ELSE
                    0 -- For following feed, score doesn't matter
            END as algorithm_score
        FROM posts p
        LEFT JOIN post_like_counts plc ON plc.post_id = p.id
        LEFT JOIN post_reply_counts prc ON prc.parent_post_id = p.id
        LEFT JOIN user_likes ul ON ul.post_id = p.id
        LEFT JOIN auth.users u ON u.id = p.user_id
        LEFT JOIN profiles prof ON prof.id = p.user_id
        WHERE p.deleted_at IS NULL
            AND (
                CASE p_feed_type
                    WHEN 'following' THEN
                        -- Following feed: current user + followed users
                        (p.user_id = v_current_user_id OR p.user_id IN (SELECT following_id FROM following_users))
                    ELSE
                        -- For You feed: all posts (algorithm will prioritize by region)
                        TRUE
                END
            )
    )
    SELECT 
        pws.id,
        pws.user_id,
        pws.text,
        pws.image_urls,
        pws.video_url,
        pws.audio_url,
        pws.parent_post_id,
        pws.leaderboard_entry_id,
        pws.leaderboard_artist_name,
        pws.leaderboard_rank,
        pws.leaderboard_percentile_label,
        pws.leaderboard_minutes_listened,
        pws.reshared_post_id,
        pws.created_at,
        pws.like_count,
        pws.is_liked_by_current_user,
        pws.reply_count,
        pws.author_display_name,
        pws.author_handle,
        pws.author_profile_picture_url,
        pws.author_avatar_initials,
        pws.spotify_link_url,
        pws.spotify_link_type,
        pws.spotify_link_data,
        pws.poll_question,
        pws.poll_type,
        pws.poll_options,
        pws.background_music_spotify_id,
        pws.background_music_data
    FROM posts_with_scores pws
    ORDER BY 
        CASE 
            WHEN p_feed_type = 'for_you' THEN pws.algorithm_score
            ELSE 0
        END ASC,
        pws.created_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$;




-- ============================================
-- This script updates the get_feed_posts function to return Spotify link, poll, and background music data
-- Run this if Spotify links are not appearing in the feed
-- ============================================

-- Drop existing function(s) to avoid ambiguity
-- Drop all possible signatures of get_feed_posts
DROP FUNCTION IF EXISTS get_feed_posts() CASCADE;
DROP FUNCTION IF EXISTS get_feed_posts(TEXT) CASCADE;
DROP FUNCTION IF EXISTS get_feed_posts(TEXT, INT) CASCADE;
DROP FUNCTION IF EXISTS get_feed_posts(TEXT, INT, INT) CASCADE;
DROP FUNCTION IF EXISTS get_feed_posts(TEXT, TEXT) CASCADE;
DROP FUNCTION IF EXISTS get_feed_posts(TEXT, TEXT, INT) CASCADE;
DROP FUNCTION IF EXISTS get_feed_posts(TEXT, TEXT, INT, INT) CASCADE;

-- Recreate the function with Spotify link columns
CREATE OR REPLACE FUNCTION get_feed_posts(
    p_feed_type TEXT DEFAULT 'for_you',
    p_region TEXT DEFAULT NULL,
    p_limit INT DEFAULT 50,
    p_offset INT DEFAULT 0
)
RETURNS TABLE (
    id UUID,
    user_id UUID,
    text TEXT,
    image_urls TEXT[],
    video_url TEXT,
    audio_url TEXT,
    parent_post_id UUID,
    leaderboard_entry_id TEXT,
    leaderboard_artist_name TEXT,
    leaderboard_rank INT,
    leaderboard_percentile_label TEXT,
    leaderboard_minutes_listened INT,
    reshared_post_id UUID,
    created_at TIMESTAMPTZ,
    like_count BIGINT,
    is_liked_by_current_user BOOLEAN,
    reply_count BIGINT,
    author_display_name TEXT,
    author_handle TEXT,
    author_profile_picture_url TEXT,
    author_avatar_initials TEXT,
    spotify_link_url TEXT,
    spotify_link_type TEXT,
    spotify_link_data JSONB,
    poll_question TEXT,
    poll_type TEXT,
    poll_options JSONB,
    background_music_spotify_id TEXT,
    background_music_data JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_user_id UUID;
    v_user_region TEXT;
BEGIN
    v_current_user_id := auth.uid();
    
    IF v_current_user_id IS NULL THEN
        RAISE EXCEPTION 'User must be authenticated';
    END IF;
    
    -- Get current user's region from profile, or use provided region parameter
    -- Handle case where profile might not exist
    BEGIN
        SELECT COALESCE(p_region, prof.region) INTO v_user_region
        FROM profiles prof
        WHERE prof.id = v_current_user_id;
    EXCEPTION WHEN OTHERS THEN
        -- If profile doesn't exist or region lookup fails, use provided region or NULL
        v_user_region := p_region;
    END;
    
    RETURN QUERY
    WITH post_like_counts AS (
        SELECT 
            post_id,
            COUNT(*) as like_count
        FROM post_likes
        GROUP BY post_id
    ),
    post_reply_counts AS (
        SELECT 
            p2.parent_post_id,
            COUNT(*) as reply_count
        FROM posts p2
        WHERE p2.parent_post_id IS NOT NULL AND p2.deleted_at IS NULL
        GROUP BY p2.parent_post_id
    ),
    user_likes AS (
        SELECT pl.post_id
        FROM post_likes pl
        WHERE pl.user_id = v_current_user_id
    ),
    following_users AS (
        SELECT following_id
        FROM user_follows
        WHERE follower_id = v_current_user_id
    ),
    posts_with_scores AS (
        SELECT 
            p.id,
            p.user_id,
            p.text,
            p.image_urls,
            p.video_url,
            p.audio_url,
            p.parent_post_id,
            p.leaderboard_entry_id,
            p.leaderboard_artist_name,
            p.leaderboard_rank,
            p.leaderboard_percentile_label,
            p.leaderboard_minutes_listened,
            p.reshared_post_id,
            p.created_at,
            p.spotify_link_url,
            p.spotify_link_type,
            p.spotify_link_data,
            p.poll_question,
            p.poll_type,
            p.poll_options,
            p.background_music_spotify_id,
            p.background_music_data,
            COALESCE(plc.like_count, 0)::BIGINT as like_count,
            (ul.post_id IS NOT NULL) as is_liked_by_current_user,
            COALESCE(prc.reply_count, 0)::BIGINT as reply_count,
            COALESCE(
                NULLIF(prof.display_name, ''),
                NULLIF(u.email, ''),
                'User'
            ) as author_display_name,
            COALESCE(
                CASE 
                    WHEN prof.username IS NOT NULL AND prof.username != '' THEN '@' || prof.username
                    ELSE NULL
                END,
                CASE 
                    WHEN u.email IS NOT NULL AND u.email != '' THEN '@' || SPLIT_PART(u.email, '@', 1)
                    ELSE NULL
                END,
                '@user'
            ) as author_handle,
            NULLIF(prof.profile_picture_url, '') as author_profile_picture_url,
            CASE 
                WHEN prof.first_name IS NOT NULL AND prof.first_name != '' AND prof.last_name IS NOT NULL AND prof.last_name != '' THEN
                    UPPER(SUBSTRING(prof.first_name, 1, 1) || SUBSTRING(prof.last_name, 1, 1))
                WHEN prof.display_name IS NOT NULL AND prof.display_name != '' AND LENGTH(prof.display_name) >= 2 THEN
                    UPPER(SUBSTRING(prof.display_name, 1, 2))
                WHEN u.email IS NOT NULL AND u.email != '' THEN
                    UPPER(SUBSTRING(SPLIT_PART(u.email, '@', 1), 1, 2))
                ELSE
                    'U'
            END as author_avatar_initials,
            -- Algorithm score for "For You" feed: prioritize same region, then by engagement
            CASE 
                WHEN p_feed_type = 'for_you' AND v_user_region IS NOT NULL AND prof.region = v_user_region THEN
                    -- Same region: boost score based on recency and engagement
                    EXTRACT(EPOCH FROM (NOW() - p.created_at)) / 3600.0 + -- Hours since post (lower is better)
                    (COALESCE(plc.like_count, 0) * 0.5) + -- Engagement boost
                    (COALESCE(prc.reply_count, 0) * 0.3)
                WHEN p_feed_type = 'for_you' THEN
                    -- Different region: lower score but still included
                    EXTRACT(EPOCH FROM (NOW() - p.created_at)) / 3600.0 + -- Hours since post
                    (COALESCE(plc.like_count, 0) * 0.5) + -- Engagement boost
                    (COALESCE(prc.reply_count, 0) * 0.3) + 1000.0 -- Penalty for different region
                ELSE
                    0 -- For following feed, score doesn't matter
            END as algorithm_score
        FROM posts p
        LEFT JOIN post_like_counts plc ON plc.post_id = p.id
        LEFT JOIN post_reply_counts prc ON prc.parent_post_id = p.id
        LEFT JOIN user_likes ul ON ul.post_id = p.id
        LEFT JOIN auth.users u ON u.id = p.user_id
        LEFT JOIN profiles prof ON prof.id = p.user_id
        WHERE p.deleted_at IS NULL
            AND (
                CASE p_feed_type
                    WHEN 'following' THEN
                        -- Following feed: current user + followed users
                        (p.user_id = v_current_user_id OR p.user_id IN (SELECT following_id FROM following_users))
                    ELSE
                        -- For You feed: all posts (algorithm will prioritize by region)
                        TRUE
                END
            )
    )
    SELECT 
        pws.id,
        pws.user_id,
        pws.text,
        pws.image_urls,
        pws.video_url,
        pws.audio_url,
        pws.parent_post_id,
        pws.leaderboard_entry_id,
        pws.leaderboard_artist_name,
        pws.leaderboard_rank,
        pws.leaderboard_percentile_label,
        pws.leaderboard_minutes_listened,
        pws.reshared_post_id,
        pws.created_at,
        pws.like_count,
        pws.is_liked_by_current_user,
        pws.reply_count,
        pws.author_display_name,
        pws.author_handle,
        pws.author_profile_picture_url,
        pws.author_avatar_initials,
        pws.spotify_link_url,
        pws.spotify_link_type,
        pws.spotify_link_data,
        pws.poll_question,
        pws.poll_type,
        pws.poll_options,
        pws.background_music_spotify_id,
        pws.background_music_data
    FROM posts_with_scores pws
    ORDER BY 
        CASE 
            WHEN p_feed_type = 'for_you' THEN pws.algorithm_score
            ELSE 0
        END ASC,
        pws.created_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$;


-- ============================================
-- This script updates the get_feed_posts function to return Spotify link, poll, and background music data
-- Run this if Spotify links are not appearing in the feed
-- ============================================

-- Drop existing function(s) to avoid ambiguity
-- Drop all possible signatures of get_feed_posts
DROP FUNCTION IF EXISTS get_feed_posts() CASCADE;
DROP FUNCTION IF EXISTS get_feed_posts(TEXT) CASCADE;
DROP FUNCTION IF EXISTS get_feed_posts(TEXT, INT) CASCADE;
DROP FUNCTION IF EXISTS get_feed_posts(TEXT, INT, INT) CASCADE;
DROP FUNCTION IF EXISTS get_feed_posts(TEXT, TEXT) CASCADE;
DROP FUNCTION IF EXISTS get_feed_posts(TEXT, TEXT, INT) CASCADE;
DROP FUNCTION IF EXISTS get_feed_posts(TEXT, TEXT, INT, INT) CASCADE;

-- Recreate the function with Spotify link columns
CREATE OR REPLACE FUNCTION get_feed_posts(
    p_feed_type TEXT DEFAULT 'for_you',
    p_region TEXT DEFAULT NULL,
    p_limit INT DEFAULT 50,
    p_offset INT DEFAULT 0
)
RETURNS TABLE (
    id UUID,
    user_id UUID,
    text TEXT,
    image_urls TEXT[],
    video_url TEXT,
    audio_url TEXT,
    parent_post_id UUID,
    leaderboard_entry_id TEXT,
    leaderboard_artist_name TEXT,
    leaderboard_rank INT,
    leaderboard_percentile_label TEXT,
    leaderboard_minutes_listened INT,
    reshared_post_id UUID,
    created_at TIMESTAMPTZ,
    like_count BIGINT,
    is_liked_by_current_user BOOLEAN,
    reply_count BIGINT,
    author_display_name TEXT,
    author_handle TEXT,
    author_profile_picture_url TEXT,
    author_avatar_initials TEXT,
    spotify_link_url TEXT,
    spotify_link_type TEXT,
    spotify_link_data JSONB,
    poll_question TEXT,
    poll_type TEXT,
    poll_options JSONB,
    background_music_spotify_id TEXT,
    background_music_data JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_user_id UUID;
    v_user_region TEXT;
BEGIN
    v_current_user_id := auth.uid();
    
    IF v_current_user_id IS NULL THEN
        RAISE EXCEPTION 'User must be authenticated';
    END IF;
    
    -- Get current user's region from profile, or use provided region parameter
    -- Handle case where profile might not exist
    BEGIN
        SELECT COALESCE(p_region, prof.region) INTO v_user_region
        FROM profiles prof
        WHERE prof.id = v_current_user_id;
    EXCEPTION WHEN OTHERS THEN
        -- If profile doesn't exist or region lookup fails, use provided region or NULL
        v_user_region := p_region;
    END;
    
    RETURN QUERY
    WITH post_like_counts AS (
        SELECT 
            post_id,
            COUNT(*) as like_count
        FROM post_likes
        GROUP BY post_id
    ),
    post_reply_counts AS (
        SELECT 
            p2.parent_post_id,
            COUNT(*) as reply_count
        FROM posts p2
        WHERE p2.parent_post_id IS NOT NULL AND p2.deleted_at IS NULL
        GROUP BY p2.parent_post_id
    ),
    user_likes AS (
        SELECT pl.post_id
        FROM post_likes pl
        WHERE pl.user_id = v_current_user_id
    ),
    following_users AS (
        SELECT following_id
        FROM user_follows
        WHERE follower_id = v_current_user_id
    ),
    posts_with_scores AS (
        SELECT 
            p.id,
            p.user_id,
            p.text,
            p.image_urls,
            p.video_url,
            p.audio_url,
            p.parent_post_id,
            p.leaderboard_entry_id,
            p.leaderboard_artist_name,
            p.leaderboard_rank,
            p.leaderboard_percentile_label,
            p.leaderboard_minutes_listened,
            p.reshared_post_id,
            p.created_at,
            p.spotify_link_url,
            p.spotify_link_type,
            p.spotify_link_data,
            p.poll_question,
            p.poll_type,
            p.poll_options,
            p.background_music_spotify_id,
            p.background_music_data,
            COALESCE(plc.like_count, 0)::BIGINT as like_count,
            (ul.post_id IS NOT NULL) as is_liked_by_current_user,
            COALESCE(prc.reply_count, 0)::BIGINT as reply_count,
            COALESCE(
                NULLIF(prof.display_name, ''),
                NULLIF(u.email, ''),
                'User'
            ) as author_display_name,
            COALESCE(
                CASE 
                    WHEN prof.username IS NOT NULL AND prof.username != '' THEN '@' || prof.username
                    ELSE NULL
                END,
                CASE 
                    WHEN u.email IS NOT NULL AND u.email != '' THEN '@' || SPLIT_PART(u.email, '@', 1)
                    ELSE NULL
                END,
                '@user'
            ) as author_handle,
            NULLIF(prof.profile_picture_url, '') as author_profile_picture_url,
            CASE 
                WHEN prof.first_name IS NOT NULL AND prof.first_name != '' AND prof.last_name IS NOT NULL AND prof.last_name != '' THEN
                    UPPER(SUBSTRING(prof.first_name, 1, 1) || SUBSTRING(prof.last_name, 1, 1))
                WHEN prof.display_name IS NOT NULL AND prof.display_name != '' AND LENGTH(prof.display_name) >= 2 THEN
                    UPPER(SUBSTRING(prof.display_name, 1, 2))
                WHEN u.email IS NOT NULL AND u.email != '' THEN
                    UPPER(SUBSTRING(SPLIT_PART(u.email, '@', 1), 1, 2))
                ELSE
                    'U'
            END as author_avatar_initials,
            -- Algorithm score for "For You" feed: prioritize same region, then by engagement
            CASE 
                WHEN p_feed_type = 'for_you' AND v_user_region IS NOT NULL AND prof.region = v_user_region THEN
                    -- Same region: boost score based on recency and engagement
                    EXTRACT(EPOCH FROM (NOW() - p.created_at)) / 3600.0 + -- Hours since post (lower is better)
                    (COALESCE(plc.like_count, 0) * 0.5) + -- Engagement boost
                    (COALESCE(prc.reply_count, 0) * 0.3)
                WHEN p_feed_type = 'for_you' THEN
                    -- Different region: lower score but still included
                    EXTRACT(EPOCH FROM (NOW() - p.created_at)) / 3600.0 + -- Hours since post
                    (COALESCE(plc.like_count, 0) * 0.5) + -- Engagement boost
                    (COALESCE(prc.reply_count, 0) * 0.3) + 1000.0 -- Penalty for different region
                ELSE
                    0 -- For following feed, score doesn't matter
            END as algorithm_score
        FROM posts p
        LEFT JOIN post_like_counts plc ON plc.post_id = p.id
        LEFT JOIN post_reply_counts prc ON prc.parent_post_id = p.id
        LEFT JOIN user_likes ul ON ul.post_id = p.id
        LEFT JOIN auth.users u ON u.id = p.user_id
        LEFT JOIN profiles prof ON prof.id = p.user_id
        WHERE p.deleted_at IS NULL
            AND (
                CASE p_feed_type
                    WHEN 'following' THEN
                        -- Following feed: current user + followed users
                        (p.user_id = v_current_user_id OR p.user_id IN (SELECT following_id FROM following_users))
                    ELSE
                        -- For You feed: all posts (algorithm will prioritize by region)
                        TRUE
                END
            )
    )
    SELECT 
        pws.id,
        pws.user_id,
        pws.text,
        pws.image_urls,
        pws.video_url,
        pws.audio_url,
        pws.parent_post_id,
        pws.leaderboard_entry_id,
        pws.leaderboard_artist_name,
        pws.leaderboard_rank,
        pws.leaderboard_percentile_label,
        pws.leaderboard_minutes_listened,
        pws.reshared_post_id,
        pws.created_at,
        pws.like_count,
        pws.is_liked_by_current_user,
        pws.reply_count,
        pws.author_display_name,
        pws.author_handle,
        pws.author_profile_picture_url,
        pws.author_avatar_initials,
        pws.spotify_link_url,
        pws.spotify_link_type,
        pws.spotify_link_data,
        pws.poll_question,
        pws.poll_type,
        pws.poll_options,
        pws.background_music_spotify_id,
        pws.background_music_data
    FROM posts_with_scores pws
    ORDER BY 
        CASE 
            WHEN p_feed_type = 'for_you' THEN pws.algorithm_score
            ELSE 0
        END ASC,
        pws.created_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$;

