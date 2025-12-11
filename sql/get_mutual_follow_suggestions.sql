-- Function to get mutual follow suggestions
-- Returns users who are followed by people the current user follows, but the current user doesn't follow
-- Ordered by number of mutual connections

CREATE OR REPLACE FUNCTION get_mutual_follow_suggestions(
    p_user_id UUID,
    p_limit INT DEFAULT 20
)
RETURNS TABLE (
    user_id UUID,
    display_name TEXT,
    first_name TEXT,
    last_name TEXT,
    username TEXT,
    profile_picture_url TEXT,
    region TEXT,
    followers_count INT,
    following_count INT,
    mutual_count BIGINT
) AS $$
BEGIN
    RETURN QUERY
    WITH user_following AS (
        -- Get users that the current user follows
        SELECT following_id
        FROM user_follows
        WHERE follower_id = p_user_id
    ),
    suggested_users AS (
        -- Get users followed by people the current user follows
        SELECT 
            uf.following_id as suggested_user_id,
            COUNT(DISTINCT uf.follower_id)::BIGINT as mutual_count
        FROM user_follows uf
        INNER JOIN user_following uf2 ON uf.follower_id = uf2.following_id
        WHERE uf.following_id != p_user_id
          -- Exclude users already followed by current user
          AND uf.following_id NOT IN (SELECT following_id FROM user_following)
          -- Exclude self
          AND uf.following_id != p_user_id
        GROUP BY uf.following_id
        HAVING COUNT(DISTINCT uf.follower_id) > 0
    )
    SELECT 
        p.id as user_id,
        p.display_name,
        p.first_name,
        p.last_name,
        p.username,
        p.profile_picture_url,
        p.region,
        COALESCE(p.followers_count, 0) as followers_count,
        COALESCE(p.following_count, 0) as following_count,
        su.mutual_count
    FROM suggested_users su
    INNER JOIN profiles p ON p.id = su.suggested_user_id
    WHERE p.deleted_at IS NULL
    ORDER BY su.mutual_count DESC, p.followers_count DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION get_mutual_follow_suggestions(UUID, INT) TO authenticated;

-- Add comment for documentation
COMMENT ON FUNCTION get_mutual_follow_suggestions IS 'Returns users who are followed by people the current user follows, ordered by mutual connection count';

