-- ========================================
-- GET SINGLE POST BY ID
-- Used for notification navigation and direct post access
-- ========================================

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
    -- Get current user ID
    v_current_user_id := auth.uid();
    
    IF v_current_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    
    -- Return the post with all necessary fields
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
    -- Get like count
    LEFT JOIN (
        SELECT post_id, COUNT(*)::BIGINT as like_count
        FROM post_likes
        GROUP BY post_id
    ) plc ON plc.post_id = p.id
    -- Check if current user liked
    LEFT JOIN post_likes ul ON ul.post_id = p.id AND ul.user_id = v_current_user_id
    -- Get reply count
    LEFT JOIN (
        SELECT r.parent_post_id, COUNT(*)::BIGINT as reply_count
        FROM posts r
        WHERE r.deleted_at IS NULL AND r.parent_post_id IS NOT NULL
        GROUP BY r.parent_post_id
    ) prc ON prc.parent_post_id = p.id
    -- Get author info
    LEFT JOIN profiles prof ON prof.id = p.user_id
    WHERE p.id = p_post_id
      AND p.deleted_at IS NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

