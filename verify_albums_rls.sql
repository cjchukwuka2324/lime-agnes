-- Verify and fix albums RLS policies
-- Run this to ensure albums can be updated

-- First, make sure RLS is enabled
ALTER TABLE albums ENABLE ROW LEVEL SECURITY;

-- Drop and recreate update policies to ensure they're correct
DO $$ 
BEGIN
    DROP POLICY IF EXISTS "Users can update own albums" ON albums;
    DROP POLICY IF EXISTS "Collaborators can update albums" ON albums;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- Users can update their own albums (including cover_art_url)
CREATE POLICY "Users can update own albums"
    ON albums FOR UPDATE
    USING (
        CAST(artist_id AS text) = CAST(auth.uid() AS text)
    )
    WITH CHECK (
        CAST(artist_id AS text) = CAST(auth.uid() AS text)
    );

-- Collaborators can update albums they're collaborating on
CREATE POLICY "Collaborators can update albums"
    ON albums FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM shared_albums
            WHERE CAST(shared_albums.album_id AS text) = CAST(albums.id AS text)
              AND CAST(shared_albums.shared_with AS text) = CAST(auth.uid() AS text)
              AND shared_albums.is_collaboration = true
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM shared_albums
            WHERE CAST(shared_albums.album_id AS text) = CAST(albums.id AS text)
              AND CAST(shared_albums.shared_with AS text) = CAST(auth.uid() AS text)
              AND shared_albums.is_collaboration = true
        )
    );

