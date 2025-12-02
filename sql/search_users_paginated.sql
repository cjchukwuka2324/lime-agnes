-- Paginated user search for production scalability
-- Supports searching by display name, username, first/last name, email

CREATE OR REPLACE FUNCTION search_users_paginated(
    p_search_query TEXT,
    p_limit INT DEFAULT 20,
    p_offset INT DEFAULT 0
)
RETURNS TABLE (
    id UUID,
    display_name TEXT,
    first_name TEXT,
    last_name TEXT,
    username TEXT,
    email TEXT,
    profile_picture_url TEXT,
    region TEXT,
    followers_count INT,
    following_count INT,
    is_following BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_user_id UUID;
BEGIN
    -- Get current user ID
    v_current_user_id := auth.uid();
    
    IF v_current_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    
    -- Normalize search query
    p_search_query := LOWER(TRIM(p_search_query));
    
    RETURN QUERY
    SELECT
        p.id,
        p.display_name,
        p.first_name,
        p.last_name,
        p.username,
        u.email::TEXT,
        p.profile_picture_url,
        p.region,
        COALESCE(p.followers_count, 0)::INT,
        COALESCE(p.following_count, 0)::INT,
        (
            EXISTS (
                SELECT 1 FROM user_follows uf
                WHERE uf.follower_id = v_current_user_id
                AND uf.following_id = p.id
            )
        ) as is_following
    FROM profiles p
    LEFT JOIN auth.users u ON u.id = p.id
    WHERE p.id != v_current_user_id
        AND (
            -- Search in email
            (u.email IS NOT NULL AND LOWER(u.email) LIKE '%' || p_search_query || '%') OR
            -- Search in username (handle)
            (p.username IS NOT NULL AND LOWER(p.username) LIKE '%' || p_search_query || '%') OR
            -- Search in display name
            (p.display_name IS NOT NULL AND LOWER(p.display_name) LIKE '%' || p_search_query || '%') OR
            -- Search in first name
            (p.first_name IS NOT NULL AND LOWER(p.first_name) LIKE '%' || p_search_query || '%') OR
            -- Search in last name
            (p.last_name IS NOT NULL AND LOWER(p.last_name) LIKE '%' || p_search_query || '%')
        )
    ORDER BY 
        -- Prioritize exact username matches
        CASE WHEN p.username = p_search_query THEN 0 ELSE 1 END,
        -- Then by followers count (more popular users first)
        COALESCE(p.followers_count, 0) DESC,
        -- Then by display name
        p.display_name NULLS LAST,
        p.first_name NULLS LAST
    LIMIT p_limit
    OFFSET p_offset;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION search_users_paginated(TEXT, INT, INT) TO authenticated;

-- Add comment for documentation
COMMENT ON FUNCTION search_users_paginated IS 'Paginated user search supporting email, username, display name, and first/last name queries with popularity ranking';

