-- ========================================
-- APPLY ALL FIXES - Run this in Supabase SQL Editor
-- ========================================
-- 
-- NOTE: Social media columns should be named: instagram, twitter, tiktok
--       (without _handle suffix) in the profiles table
--
-- ========================================

-- Fix 0a: Create get_post_by_id function (for notification navigation)
DROP FUNCTION IF EXISTS get_post_by_id(UUID);

CREATE OR REPLACE FUNCTION get_post_by_id(p_post_id UUID)
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
    author_instagram_handle TEXT,
    author_twitter_handle TEXT,
    author_tiktok_handle TEXT,
    spotify_link_url TEXT,
    spotify_link_type TEXT,
    spotify_link_data JSONB,
    poll_question TEXT,
    poll_type TEXT,
    poll_options JSONB,
    background_music_spotify_id TEXT,
    background_music_data JSONB
) AS $$
DECLARE
    v_current_user_id UUID;
BEGIN
    v_current_user_id := auth.uid();
    
    IF v_current_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    
    RETURN QUERY
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
        COALESCE(plc.like_count, 0)::BIGINT as like_count,
        (ul.post_id IS NOT NULL) as is_liked_by_current_user,
        COALESCE(prc.reply_count, 0)::BIGINT as reply_count,
        COALESCE(prof.display_name, 'User') as author_display_name,
        COALESCE(
            CASE 
                WHEN prof.username IS NOT NULL AND prof.username != '' THEN '@' || prof.username
                ELSE NULL
            END,
            '@user'
        ) as author_handle,
        NULLIF(prof.profile_picture_url, '') as author_profile_picture_url,
        CASE 
            WHEN prof.first_name IS NOT NULL AND prof.last_name IS NOT NULL THEN
                UPPER(LEFT(prof.first_name, 1)) || UPPER(LEFT(prof.last_name, 1))
            WHEN prof.display_name IS NOT NULL AND prof.display_name != '' THEN
                UPPER(LEFT(prof.display_name, 2))
            ELSE
                'US'
        END as author_avatar_initials,
        prof.instagram as author_instagram_handle,
        prof.twitter as author_twitter_handle,
        prof.tiktok as author_tiktok_handle,
        p.spotify_link_url,
        p.spotify_link_type,
        p.spotify_link_data,
        p.poll_question,
        p.poll_type,
        p.poll_options,
        p.background_music_spotify_id,
        p.background_music_data
    FROM posts p
    LEFT JOIN (
        SELECT post_id, COUNT(*)::BIGINT as like_count
        FROM post_likes
        GROUP BY post_id
    ) plc ON plc.post_id = p.id
    LEFT JOIN post_likes ul ON ul.post_id = p.id AND ul.user_id = v_current_user_id
    LEFT JOIN (
        SELECT r.parent_post_id, COUNT(*)::BIGINT as reply_count
        FROM posts r
        WHERE r.deleted_at IS NULL AND r.parent_post_id IS NOT NULL
        GROUP BY r.parent_post_id
    ) prc ON prc.parent_post_id = p.id
    LEFT JOIN profiles prof ON prof.id = p.user_id
    WHERE p.id = p_post_id
      AND p.deleted_at IS NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Fix 0b: Create get_all_trending_posts function (for trending feed)
-- Drop existing function first (return type changed from UUID to TEXT for leaderboard_entry_id)
DROP FUNCTION IF EXISTS get_all_trending_posts(INT, INT, TIMESTAMPTZ);

CREATE OR REPLACE FUNCTION get_all_trending_posts(
    p_limit INT DEFAULT 50,
    p_time_window_hours INT DEFAULT 72,
    p_cursor TIMESTAMPTZ DEFAULT NULL
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
    author_instagram_handle TEXT,
    author_twitter_handle TEXT,
    author_tiktok_handle TEXT,
    spotify_link_url TEXT,
    spotify_link_type TEXT,
    spotify_link_data JSONB,
    poll_question TEXT,
    poll_type TEXT,
    poll_options JSONB,
    background_music_spotify_id TEXT,
    background_music_data JSONB
) AS $$
DECLARE
    v_current_user_id UUID;
BEGIN
    v_current_user_id := auth.uid();
    
    IF v_current_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    
    RETURN QUERY
    SELECT DISTINCT ON (p.id)
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
        COALESCE(plc.like_count, 0)::BIGINT as like_count,
        (ul.post_id IS NOT NULL) as is_liked_by_current_user,
        COALESCE(prc.reply_count, 0)::BIGINT as reply_count,
        COALESCE(prof.display_name, 'User') as author_display_name,
        COALESCE(
            CASE 
                WHEN prof.username IS NOT NULL AND prof.username != '' THEN '@' || prof.username
                ELSE NULL
            END,
            '@user'
        ) as author_handle,
        NULLIF(prof.profile_picture_url, '') as author_profile_picture_url,
        CASE 
            WHEN prof.first_name IS NOT NULL AND prof.last_name IS NOT NULL THEN
                UPPER(LEFT(prof.first_name, 1)) || UPPER(LEFT(prof.last_name, 1))
            WHEN prof.display_name IS NOT NULL AND prof.display_name != '' THEN
                UPPER(LEFT(prof.display_name, 2))
            ELSE
                'US'
        END as author_avatar_initials,
        prof.instagram as author_instagram_handle,
        prof.twitter as author_twitter_handle,
        prof.tiktok as author_tiktok_handle,
        p.spotify_link_url,
        p.spotify_link_type,
        p.spotify_link_data,
        p.poll_question,
        p.poll_type,
        p.poll_options,
        p.background_music_spotify_id,
        p.background_music_data
    FROM posts p
    INNER JOIN post_hashtags ph ON ph.post_id = p.id
    LEFT JOIN (
        SELECT post_id, COUNT(*)::BIGINT as like_count
        FROM post_likes
        GROUP BY post_id
    ) plc ON plc.post_id = p.id
    LEFT JOIN post_likes ul ON ul.post_id = p.id AND ul.user_id = v_current_user_id
    LEFT JOIN (
        SELECT r.parent_post_id, COUNT(*)::BIGINT as reply_count
        FROM posts r
        WHERE r.deleted_at IS NULL AND r.parent_post_id IS NOT NULL
        GROUP BY r.parent_post_id
    ) prc ON prc.parent_post_id = p.id
    LEFT JOIN profiles prof ON prof.id = p.user_id
    WHERE p.deleted_at IS NULL
      AND p.created_at >= NOW() - (p_time_window_hours || ' hours')::INTERVAL
      AND (p_cursor IS NULL OR p.created_at < p_cursor)
    ORDER BY p.id, COALESCE(plc.like_count, 0) DESC, p.created_at DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Fix 1: Update vote_on_poll function (fixes poll voting error)
CREATE OR REPLACE FUNCTION vote_on_poll(
    p_post_id UUID,
    p_option_indices INT[]
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_user_id UUID;
    v_option_index INT;
    v_poll_type TEXT;
    v_existing_votes INT;
    v_option_indices_array INT[];
BEGIN
    v_current_user_id := auth.uid();
    
    IF v_current_user_id IS NULL THEN
        RAISE EXCEPTION 'User must be authenticated';
    END IF;
    
    -- Handle NULL or empty array
    IF p_option_indices IS NULL THEN
        v_option_indices_array := ARRAY[]::INT[];
    ELSE
        v_option_indices_array := p_option_indices;
    END IF;
    
    -- Get poll type
    SELECT poll_type INTO v_poll_type
    FROM posts
    WHERE id = p_post_id AND deleted_at IS NULL;
    
    IF v_poll_type IS NULL THEN
        RAISE EXCEPTION 'Post does not have a poll';
    END IF;
    
    -- For single choice polls, user can only vote once
    IF v_poll_type = 'single' THEN
        -- Delete existing vote for this user
        DELETE FROM post_poll_votes
        WHERE post_id = p_post_id AND user_id = v_current_user_id;
        
        -- Insert new vote (only first option for single choice)
        IF array_length(v_option_indices_array, 1) > 0 THEN
            INSERT INTO post_poll_votes (post_id, user_id, option_index)
            VALUES (p_post_id, v_current_user_id, v_option_indices_array[1])
            ON CONFLICT (post_id, user_id, option_index) DO NOTHING;
        END IF;
    ELSE
        -- For multiple choice, remove existing votes for this user
        DELETE FROM post_poll_votes
        WHERE post_id = p_post_id AND user_id = v_current_user_id;
        
        -- Insert new votes (only if array is not empty)
        IF array_length(v_option_indices_array, 1) > 0 THEN
            FOREACH v_option_index IN ARRAY v_option_indices_array
            LOOP
                INSERT INTO post_poll_votes (post_id, user_id, option_index)
                VALUES (p_post_id, v_current_user_id, v_option_index)
                ON CONFLICT (post_id, user_id, option_index) DO NOTHING;
            END LOOP;
        END IF;
    END IF;
    
    -- Update poll_options JSONB with new vote counts
    -- Handle both array format and object format for poll_options
    UPDATE posts
    SET poll_options = (
        SELECT COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'text', COALESCE(option->>'text', option->'options'->((ordinality - 1)::int)->>'text'),
                    'votes', (
                        SELECT COUNT(*)::INT
                        FROM post_poll_votes ppv
                        WHERE ppv.post_id = p_post_id 
                        AND ppv.option_index = (ordinality - 1)::INT
                    )
                )
            ),
            '[]'::jsonb
        )
        FROM jsonb_array_elements(
            CASE 
                WHEN jsonb_typeof(poll_options) = 'array' THEN poll_options
                WHEN jsonb_typeof(poll_options) = 'object' AND poll_options ? 'options' THEN poll_options->'options'
                ELSE '[]'::jsonb
            END
        ) WITH ORDINALITY AS t(option, ordinality)
    )
    WHERE id = p_post_id;
END;
$$;

-- Fix 2: Update get_posts_by_hashtag function (fixes hashtag posts not displaying)
-- Drop existing function first (return type changed - added social media columns)
DROP FUNCTION IF EXISTS get_posts_by_hashtag(TEXT, INT, TIMESTAMPTZ);

CREATE OR REPLACE FUNCTION get_posts_by_hashtag(
    p_tag TEXT,
    p_limit INT DEFAULT 20,
    p_cursor TIMESTAMPTZ DEFAULT NULL
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
    author_instagram_handle TEXT,
    author_twitter_handle TEXT,
    author_tiktok_handle TEXT,
    spotify_link_url TEXT,
    spotify_link_type TEXT,
    spotify_link_data JSONB,
    poll_question TEXT,
    poll_type TEXT,
    poll_options JSONB,
    background_music_spotify_id TEXT,
    background_music_data JSONB
) AS $$
DECLARE
    v_current_user_id UUID;
    v_hashtag_id UUID;
    v_normalized_tag TEXT;
BEGIN
    -- Get current user ID
    v_current_user_id := auth.uid();
    
    IF v_current_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    
    -- Normalize tag
    v_normalized_tag := LOWER(TRIM(BOTH FROM REPLACE(p_tag, '#', '')));
    
    -- Get hashtag ID
    SELECT h.id INTO v_hashtag_id
    FROM hashtags h
    WHERE h.tag = v_normalized_tag;
    
    IF v_hashtag_id IS NULL THEN
        -- Hashtag doesn't exist, return empty result
        RETURN;
    END IF;
    
    -- Return posts that use this hashtag
    RETURN QUERY
    WITH posts_with_hashtag AS (
        SELECT ph.post_id, ph.created_at as hashtag_created_at
        FROM post_hashtags ph
        WHERE ph.hashtag_id = v_hashtag_id
        AND (p_cursor IS NULL OR ph.created_at < p_cursor)
        ORDER BY ph.created_at DESC
        LIMIT p_limit
    ),
    posts_with_details AS (
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
            COALESCE(prof.display_name, 'User') as author_display_name,
            COALESCE(
                CASE 
                    WHEN prof.username IS NOT NULL AND prof.username != '' THEN '@' || prof.username
                    ELSE NULL
                END,
                '@user'
            ) as author_handle,
            NULLIF(prof.profile_picture_url, '') as author_profile_picture_url,
            CASE 
                WHEN prof.first_name IS NOT NULL AND prof.last_name IS NOT NULL THEN
                    UPPER(LEFT(prof.first_name, 1) || LEFT(prof.last_name, 1))
                WHEN prof.display_name IS NOT NULL AND prof.display_name != '' THEN
                    UPPER(LEFT(prof.display_name, 2))
                ELSE
                    'US'
            END as author_avatar_initials,
            prof.instagram as author_instagram_handle,
            prof.twitter as author_twitter_handle,
            prof.tiktok as author_tiktok_handle,
            pwh.hashtag_created_at
        FROM posts_with_hashtag pwh
        JOIN posts p ON p.id = pwh.post_id
        LEFT JOIN (
            SELECT post_id, COUNT(*)::BIGINT as like_count
            FROM post_likes
            GROUP BY post_id
        ) plc ON plc.post_id = p.id
        LEFT JOIN (
            SELECT pr.parent_post_id, COUNT(*)::BIGINT as reply_count
            FROM posts pr
            WHERE pr.parent_post_id IS NOT NULL AND pr.deleted_at IS NULL
            GROUP BY pr.parent_post_id
        ) prc ON prc.parent_post_id = p.id
        LEFT JOIN post_likes ul ON ul.post_id = p.id AND ul.user_id = v_current_user_id
        LEFT JOIN profiles prof ON prof.id = p.user_id
        WHERE p.deleted_at IS NULL
    )
    SELECT 
        pwd.id,
        pwd.user_id,
        pwd.text,
        pwd.image_urls,
        pwd.video_url,
        pwd.audio_url,
        pwd.parent_post_id,
        pwd.leaderboard_entry_id,
        pwd.leaderboard_artist_name,
        pwd.leaderboard_rank,
        pwd.leaderboard_percentile_label,
        pwd.leaderboard_minutes_listened,
        pwd.reshared_post_id,
        pwd.created_at,
        pwd.like_count,
        pwd.is_liked_by_current_user,
        pwd.reply_count,
        pwd.author_display_name,
        pwd.author_handle,
        pwd.author_profile_picture_url,
        pwd.author_avatar_initials,
        pwd.author_instagram_handle,
        pwd.author_twitter_handle,
        pwd.author_tiktok_handle,
        pwd.spotify_link_url,
        pwd.spotify_link_type,
        pwd.spotify_link_data,
        pwd.poll_question,
        pwd.poll_type,
        pwd.poll_options,
        pwd.background_music_spotify_id,
        pwd.background_music_data
    FROM posts_with_details pwd
    ORDER BY pwd.hashtag_created_at DESC;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- Grant permissions
GRANT EXECUTE ON FUNCTION vote_on_poll TO authenticated;
GRANT EXECUTE ON FUNCTION get_posts_by_hashtag(TEXT, INT, TIMESTAMPTZ) TO authenticated;
GRANT EXECUTE ON FUNCTION get_all_trending_posts(INT, INT, TIMESTAMPTZ) TO authenticated;

-- Fix 3: Sync follower counts to fix UI/database mismatch
UPDATE profiles
SET followers_count = COALESCE((
    SELECT COUNT(*)::INTEGER
    FROM user_follows
    WHERE following_id = profiles.id
), 0);

UPDATE profiles
SET following_count = COALESCE((
    SELECT COUNT(*)::INTEGER
    FROM user_follows
    WHERE follower_id = profiles.id
), 0);

-- Verification
SELECT 'SQL fixes applied successfully!' as status;

