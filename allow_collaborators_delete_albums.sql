-- ============================================
-- Allow Collaborators to Delete Albums
-- ============================================
-- This adds an RLS policy to allow collaborators to delete
-- albums they're collaborating on.
-- 
-- Collaborators now have TWO options:
-- 1. Leave Collaboration - Removes themselves (via removeSharedAlbum)
-- 2. Delete Album - Completely deletes the album (requires this policy)
-- 
-- INSTRUCTIONS:
-- 1. Open Supabase Dashboard > SQL Editor
-- 2. Copy and paste this entire script
-- 3. Click "Run" to execute
-- ============================================

-- Drop existing policy if it exists
DO $$ 
BEGIN
    DROP POLICY IF EXISTS "Collaborators can delete albums" ON albums;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- Allow collaborators to delete albums they're collaborating on
-- This enables the "Delete Album" option for collaborators
CREATE POLICY "Collaborators can delete albums"
    ON albums FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM shared_albums
            WHERE CAST(shared_albums.album_id AS text) = CAST(albums.id AS text)
              AND CAST(shared_albums.shared_with AS text) = CAST(auth.uid() AS text)
              AND shared_albums.is_collaboration = true
        )
    );

-- Note: The "Leave Collaboration" option already works via the existing
-- shared_albums DELETE policy, which allows users to delete their own shares.

-- ============================================
-- Verification
-- ============================================
-- Check that the policy was created:
-- SELECT * FROM pg_policies WHERE tablename = 'albums' AND policyname = 'Collaborators can delete albums';

