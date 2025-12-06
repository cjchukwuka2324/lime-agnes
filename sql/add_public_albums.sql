-- ============================================
-- Add Public Albums Functionality
-- Adds is_public column to albums and search functionality
-- ============================================

-- Step 1: Add is_public column to albums table
ALTER TABLE albums 
ADD COLUMN IF NOT EXISTS is_public BOOLEAN NOT NULL DEFAULT FALSE;

-- Add index for efficient public album queries
CREATE INDEX IF NOT EXISTS idx_albums_is_public ON albums(is_public) WHERE is_public = true;
CREATE INDEX IF NOT EXISTS idx_albums_artist_public ON albums(artist_id, is_public) WHERE is_public = true;

-- Step 2: Create RPC function to search public albums by user email/username
CREATE OR REPLACE FUNCTION search_public_albums_by_user(
    p_search_query TEXT,
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
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ,
    is_public BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_search_query TEXT;
    v_matching_user_ids UUID[];
BEGIN
    -- Get current user ID (optional - for future use)
    -- v_current_user_id := auth.uid();
    
    -- Normalize search query
    v_search_query := LOWER(TRIM(p_search_query));
    
    -- Remove @ if present
    IF v_search_query LIKE '@%' THEN
        v_search_query := SUBSTRING(v_search_query FROM 2);
    END IF;
    
    -- Find matching user IDs by email or username
    WITH matched_users AS (
        SELECT DISTINCT p.id
        FROM profiles p
        LEFT JOIN auth.users u ON u.id = p.id
        WHERE 
            -- Search by username
            (p.username IS NOT NULL AND LOWER(p.username) LIKE '%' || v_search_query || '%')
            OR
            -- Search by email (if query contains @)
            (v_search_query LIKE '%@%' AND u.email IS NOT NULL AND LOWER(u.email) LIKE '%' || v_search_query || '%')
        LIMIT 20  -- Limit to 20 matching users for performance
    )
    SELECT ARRAY_AGG(id) INTO v_matching_user_ids
    FROM matched_users;
    
    -- If no matching users found, return empty
    IF v_matching_user_ids IS NULL OR array_length(v_matching_user_ids, 1) IS NULL THEN
        RETURN;
    END IF;
    
    -- Return public albums for matching users
    RETURN QUERY
    SELECT 
        a.id,
        a.artist_id,
        a.title,
        a.cover_art_url,
        a.release_status,
        a.release_date,
        a.artist_name,
        a.created_at,
        a.updated_at,
        a.is_public
    FROM albums a
    WHERE 
        a.artist_id = ANY(v_matching_user_ids)
        AND a.is_public = true
    ORDER BY a.created_at DESC
    LIMIT p_limit;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION search_public_albums_by_user(TEXT, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION search_public_albums_by_user(TEXT, INT) TO anon;

-- Add comment for documentation
COMMENT ON FUNCTION search_public_albums_by_user IS 'Searches for public albums owned by users matching the given email or username query';

-- Step 3: Update RLS policies to allow viewing public albums
-- Note: Existing RLS policies should already handle this, but we ensure public albums are viewable
-- The current user can view public albums even if they don't own them

-- Step 4: Create a view for easier querying (optional but useful)
CREATE OR REPLACE VIEW public_albums_view AS
SELECT 
    a.*,
    p.username,
    u.email,
    sa.name as studio_artist_name
FROM albums a
INNER JOIN studio_artists sa ON sa.id = a.artist_id
LEFT JOIN profiles p ON p.id = a.artist_id
LEFT JOIN auth.users u ON u.id = a.artist_id
WHERE a.is_public = true;

-- Grant select on view
GRANT SELECT ON public_albums_view TO authenticated;
GRANT SELECT ON public_albums_view TO anon;

COMMENT ON VIEW public_albums_view IS 'View of all public albums with user information for easy querying';

