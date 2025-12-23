-- ============================================
-- Filter Private Albums from Discoveries Library
-- ============================================
-- This migration updates get_user_discovered_albums to filter out private albums
-- When an album owner sets a public album to private, it will disappear from users' discoveries
-- If set back to public, it will reappear in discoveries (if previously saved)

-- Step 1: Drop and recreate get_user_discovered_albums with is_public filter
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
        AND da.saved_from_discover = true
        AND a.is_public = true  -- Filter: only show public albums
    ORDER BY da.discovered_at DESC;
END;
$$;

-- Step 2: Grant execute permissions
GRANT EXECUTE ON FUNCTION get_user_discovered_albums(UUID) TO authenticated;

-- Comments for documentation
COMMENT ON FUNCTION get_user_discovered_albums IS 'Returns albums the user has saved from Discover feed, filtered to only show public albums';
