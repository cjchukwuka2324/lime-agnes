-- Trending hashtags SQL functions
-- Computes trending hashtags based on recent activity and engagement

-- Function: Get trending hashtags
-- Returns top hashtags based on post count, engagement, and recency
CREATE OR REPLACE FUNCTION get_trending_hashtags(
    p_time_window_hours INT DEFAULT 72,  -- Look back 72 hours
    p_limit INT DEFAULT 10
)
RETURNS TABLE (
    tag TEXT,
    post_count BIGINT,
    engagement_score NUMERIC,
    latest_post_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    WITH recent_posts AS (
        -- Get posts within time window that have hashtags
        SELECT 
            ph.hashtag_id,
            ph.post_id,
            ph.created_at
        FROM post_hashtags ph
        WHERE ph.created_at > NOW() - (p_time_window_hours || ' hours')::INTERVAL
    ),
    hashtag_stats AS (
        -- Calculate stats per hashtag
        SELECT 
            rp.hashtag_id,
            COUNT(DISTINCT rp.post_id)::BIGINT as recent_post_count,
            MAX(rp.created_at) as latest_post_at,
            -- Calculate engagement score
            (
                -- Base: number of posts (weighted highly)
                COUNT(DISTINCT rp.post_id) * 2.0 +
                -- Likes (moderate weight)
                COALESCE(SUM(
                    (SELECT COUNT(*)::NUMERIC FROM post_likes pl 
                     WHERE pl.post_id = rp.post_id)
                ), 0) * 0.5 +
                -- Replies (higher weight - shows discussion)
                COALESCE(SUM(
                    (SELECT COUNT(*)::NUMERIC FROM posts p 
                     WHERE p.parent_post_id = rp.post_id 
                     AND p.deleted_at IS NULL)
                ), 0) * 0.8 +
                -- Recency boost (newer posts score higher)
                SUM(
                    EXTRACT(EPOCH FROM (NOW() - rp.created_at)) / 3600.0 * -0.1
                )
            ) as engagement_score
        FROM recent_posts rp
        GROUP BY rp.hashtag_id
        HAVING COUNT(DISTINCT rp.post_id) >= 2  -- At least 2 posts to be "trending"
    )
    SELECT 
        h.tag,
        hs.recent_post_count as post_count,
        hs.engagement_score,
        hs.latest_post_at
    FROM hashtag_stats hs
    JOIN hashtags h ON h.id = hs.hashtag_id
    ORDER BY hs.engagement_score DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE;

-- Function: Get posts by hashtag (paginated)
-- Returns posts that use a specific hashtag, with pagination support
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
            pwh.hashtag_created_at
        FROM posts_with_hashtag pwh
        JOIN posts p ON p.id = pwh.post_id
        LEFT JOIN (
            SELECT post_id, COUNT(*)::BIGINT as like_count
            FROM post_likes
            GROUP BY post_id
        ) plc ON plc.post_id = p.id
        LEFT JOIN (
            SELECT parent_post_id, COUNT(*)::BIGINT as reply_count
            FROM posts
            WHERE parent_post_id IS NOT NULL AND deleted_at IS NULL
            GROUP BY parent_post_id
        ) prc ON prc.parent_post_id = p.id
        LEFT JOIN post_likes ul ON ul.post_id = p.id AND ul.user_id = v_current_user_id
        LEFT JOIN auth.users u ON u.id = p.user_id
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

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION get_trending_hashtags(INT, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_posts_by_hashtag(TEXT, INT, TIMESTAMPTZ) TO authenticated;

-- Add comments for documentation
COMMENT ON FUNCTION get_trending_hashtags IS 'Returns top trending hashtags based on recent posts, engagement, and recency';
COMMENT ON FUNCTION get_posts_by_hashtag IS 'Returns paginated posts that use a specific hashtag, sorted by when the hashtag was added';

