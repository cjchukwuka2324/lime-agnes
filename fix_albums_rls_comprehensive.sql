-- Comprehensive fix for albums RLS policies
-- This ensures all policies are correctly set up

-- Enable RLS
ALTER TABLE albums ENABLE ROW LEVEL SECURITY;

-- Drop ALL existing policies to start fresh
DO $$ 
BEGIN
    DROP POLICY IF EXISTS "Users can view own albums" ON albums;
    DROP POLICY IF EXISTS "Users can view shared albums" ON albums;
    DROP POLICY IF EXISTS "Users can create own albums" ON albums;
    DROP POLICY IF EXISTS "Users can update own albums" ON albums;
    DROP POLICY IF EXISTS "Users can delete own albums" ON albums;
    DROP POLICY IF EXISTS "Collaborators can update albums" ON albums;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- 1. Users can view their own albums
CREATE POLICY "Users can view own albums"
    ON albums FOR SELECT
    USING (
        CAST(artist_id AS text) = CAST(auth.uid() AS text)
    );

-- 2. Users can view albums shared with them
CREATE POLICY "Users can view shared albums"
    ON albums FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM shared_albums
            WHERE CAST(shared_albums.album_id AS text) = CAST(albums.id AS text)
              AND CAST(shared_albums.shared_with AS text) = CAST(auth.uid() AS text)
        )
    );

-- 3. Users can create albums
CREATE POLICY "Users can create own albums"
    ON albums FOR INSERT
    WITH CHECK (
        CAST(artist_id AS text) = CAST(auth.uid() AS text)
    );

-- 4. Users can update their own albums (including cover_art_url, title, etc.)
-- This is the critical one for your error
CREATE POLICY "Users can update own albums"
    ON albums FOR UPDATE
    USING (
        CAST(artist_id AS text) = CAST(auth.uid() AS text)
    )
    WITH CHECK (
        CAST(artist_id AS text) = CAST(auth.uid() AS text)
    );

-- 5. Users can delete their own albums
CREATE POLICY "Users can delete own albums"
    ON albums FOR DELETE
    USING (
        CAST(artist_id AS text) = CAST(auth.uid() AS text)
    );

-- 6. Collaborators can update albums they're collaborating on
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

-- Verify policies were created
SELECT 
    policyname,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE tablename = 'albums'
ORDER BY policyname;

