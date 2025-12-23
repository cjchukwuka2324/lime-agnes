-- ============================================
-- Add RLS Policy for Public Albums
-- Allows anyone to view albums where is_public = true
-- ============================================
-- This ensures that when querying albums for a user's public profile,
-- all public albums are accessible regardless of who is making the query

-- Ensure RLS is enabled on albums table
ALTER TABLE albums ENABLE ROW LEVEL SECURITY;

-- Drop existing policy if it exists (to allow re-running this migration)
DROP POLICY IF EXISTS "Anyone can view public albums" ON albums;

-- Create policy to allow viewing public albums
-- This policy works alongside existing owner-based policies
-- Users can view albums if:
--   1. They own the album (handled by existing policies)
--   2. The album is public (handled by this policy)
-- Note: Policies are combined with OR, so this works alongside owner policies
CREATE POLICY "Anyone can view public albums"
    ON albums FOR SELECT
    TO authenticated, anon
    USING (COALESCE(is_public, false) = true);

-- Grant necessary permissions (if not already granted)
GRANT SELECT ON albums TO authenticated;
GRANT SELECT ON albums TO anon;

-- Add comment for documentation
COMMENT ON POLICY "Anyone can view public albums" ON albums IS 
    'Allows anyone (authenticated or anonymous) to view albums where is_public = true, regardless of ownership';
