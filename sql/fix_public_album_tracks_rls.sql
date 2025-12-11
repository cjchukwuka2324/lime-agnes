-- ============================================
-- Fix Public Album Tracks Visibility
-- Allows viewing tracks for public albums
-- ============================================

-- Ensure RLS is enabled on tracks table
ALTER TABLE tracks ENABLE ROW LEVEL SECURITY;

-- Drop existing policy if it exists (to allow re-running this migration)
DROP POLICY IF EXISTS "Anyone can view tracks for public albums" ON tracks;

-- Create a helper function that bypasses RLS to check if an album is public
-- This is necessary because RLS policies on albums might prevent the subquery from working
CREATE OR REPLACE FUNCTION is_album_public(p_album_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
DECLARE
    v_is_public BOOLEAN;
BEGIN
    SELECT COALESCE(is_public, false) INTO v_is_public
    FROM albums
    WHERE id = p_album_id;
    
    RETURN COALESCE(v_is_public, false);
END;
$$;

-- Grant execute permission on the function
GRANT EXECUTE ON FUNCTION is_album_public(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION is_album_public(UUID) TO anon;

-- Create policy to allow viewing tracks for public albums
-- This policy works alongside existing owner-based policies
-- Users can view tracks if:
--   1. They own the album (handled by existing policies)
--   2. The album is public (handled by this policy)
CREATE POLICY "Anyone can view tracks for public albums"
    ON tracks FOR SELECT
    USING (is_album_public(album_id) = true);

-- Add comment for documentation
COMMENT ON POLICY "Anyone can view tracks for public albums" ON tracks IS 
    'Allows anyone (authenticated or anonymous) to view tracks that belong to public albums';
COMMENT ON FUNCTION is_album_public(UUID) IS 
    'Helper function to check if an album is public, bypassing RLS for the check';

