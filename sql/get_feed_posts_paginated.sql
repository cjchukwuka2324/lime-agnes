-- Cursor-based paginated feed query for production scalability
-- Replaces the 1000-post limit with efficient cursor-based pagination

-- Drop existing function first to allow return type changes
DROP FUNCTION IF EXISTS get_feed_posts_paginated(TEXT, TEXT, INT, TIMESTAMPTZ);

CREATE OR REPLACE FUNCTION get_feed_posts_paginated(
    p_feed_type TEXT,
    p_region TEXT DEFAULT NULL,
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
    echo_count BIGINT,
    is_echoed_by_current_user BOOLEAN,
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
    background_music_data JSONB,
    algorithm_score NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_user_id UUID;
    v_user_region TEXT;
BEGIN
    -- Get current user ID
    v_current_user_id := auth.uid();
    
    IF v_current_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    
    -- Use provided region or fetch from user profile
    v_user_region := p_region;
    IF v_user_region IS NULL AND p_feed_type = 'for_you' THEN
        SELECT prof.region INTO v_user_region
        FROM profiles prof
        WHERE prof.id = v_current_user_id;
    END IF;
    
    RETURN QUERY
    WITH following_users AS (
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
            COALESCE(ec.echo_count, 0)::BIGINT as echo_count,
            (echo_post.id IS NOT NULL) as is_echoed_by_current_user,
            COALESCE(prof.display_name, u.email, 'User') as author_display_name,
            COALESCE(
                CASE 
                    WHEN prof.username IS NOT NULL AND prof.username != '' THEN '@' || prof.username
                    ELSE NULL
                END,
                '@' || SPLIT_PART(u.email, '@', 1),
                '@user'
            ) as author_handle,
            NULLIF(prof.profile_picture_url, '') as author_profile_picture_url,
            CASE 
                WHEN prof.first_name IS NOT NULL AND prof.last_name IS NOT NULL THEN
                    UPPER(LEFT(prof.first_name, 1) || LEFT(prof.last_name, 1))
                WHEN prof.display_name IS NOT NULL AND prof.display_name != '' THEN
                    UPPER(LEFT(prof.display_name, 2))
                ELSE
                    UPPER(LEFT(COALESCE(u.email, 'User'), 2))
            END as author_avatar_initials,
            prof.instagram as author_instagram_handle,
            prof.twitter as author_twitter_handle,
            prof.tiktok as author_tiktok_handle,
            -- Algorithm score for "For You" feed
            CASE 
                WHEN p_feed_type = 'for_you' AND v_user_region IS NOT NULL AND prof.region = v_user_region THEN
                    -- Same region: prioritize by engagement and recency
                    EXTRACT(EPOCH FROM (NOW() - p.created_at)) / 3600.0 +
                    (COALESCE(plc.like_count, 0) * 0.5) +
                    (COALESCE(prc.reply_count, 0) * 0.3)
                WHEN p_feed_type = 'for_you' THEN
                    -- Different region: lower priority
                    EXTRACT(EPOCH FROM (NOW() - p.created_at)) / 3600.0 +
                    (COALESCE(plc.like_count, 0) * 0.5) +
                    (COALESCE(prc.reply_count, 0) * 0.3) + 1000.0
                ELSE
                    0 -- For following feed, score doesn't matter
            END as algorithm_score
        FROM posts p
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
        LEFT JOIN (
            SELECT pe.reshared_post_id, COUNT(*)::BIGINT as echo_count
            FROM posts pe
            WHERE pe.reshared_post_id IS NOT NULL AND pe.deleted_at IS NULL
            GROUP BY pe.reshared_post_id
        ) ec ON ec.reshared_post_id = p.id
        LEFT JOIN post_likes ul ON ul.post_id = p.id AND ul.user_id = v_current_user_id
        LEFT JOIN posts echo_post ON echo_post.reshared_post_id = p.id AND echo_post.user_id = v_current_user_id AND echo_post.deleted_at IS NULL
        LEFT JOIN posts original_post ON original_post.id = p.reshared_post_id -- Join to check if original post exists and is not deleted
        LEFT JOIN auth.users u ON u.id = p.user_id
        LEFT JOIN profiles prof ON prof.id = p.user_id
        WHERE p.deleted_at IS NULL
            AND (p.reshared_post_id IS NULL OR original_post.deleted_at IS NULL) -- Filter out echo posts where original post is deleted
            AND (p_cursor IS NULL OR p.created_at < p_cursor) -- CURSOR FILTERING
            AND (
                CASE p_feed_type
                    WHEN 'following' THEN
                        -- Following feed: ONLY posts from followed users (not current user's own posts)
                        p.user_id IN (SELECT following_id FROM following_users)
                    ELSE
                        -- For You feed: all posts
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
        pws.echo_count,
        pws.is_echoed_by_current_user,
        pws.author_display_name,
        pws.author_handle,
        pws.author_profile_picture_url,
        pws.author_avatar_initials,
        pws.author_instagram_handle,
        pws.author_twitter_handle,
        pws.author_tiktok_handle,
        pws.spotify_link_url,
        pws.spotify_link_type,
        pws.spotify_link_data,
        pws.poll_question,
        pws.poll_type,
        pws.poll_options,
        pws.background_music_spotify_id,
        pws.background_music_data,
        pws.algorithm_score
    FROM posts_with_scores pws
    ORDER BY 
        CASE 
            WHEN p_feed_type = 'for_you' THEN pws.algorithm_score
            ELSE 0
        END ASC,
        pws.created_at DESC
    LIMIT p_limit;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION get_feed_posts_paginated(TEXT, TEXT, INT, TIMESTAMPTZ) TO authenticated;

-- Add comment for documentation
COMMENT ON FUNCTION get_feed_posts_paginated IS 'Cursor-based paginated feed query for production scalability. Use created_at of last post as cursor for next page.';


GRANT EXECUTE ON FUNCTION get_feed_posts_paginated(TEXT, TEXT, INT, TIMESTAMPTZ) TO authenticated;

-- Add comment for documentation
COMMENT ON FUNCTION get_feed_posts_paginated IS 'Cursor-based paginated feed query for production scalability. Use created_at of last post as cursor for next page.';


GRANT EXECUTE ON FUNCTION get_feed_posts_paginated(TEXT, TEXT, INT, TIMESTAMPTZ) TO authenticated;

-- Add comment for documentation
COMMENT ON FUNCTION get_feed_posts_paginated IS 'Cursor-based paginated feed query for production scalability. Use created_at of last post as cursor for next page.';

