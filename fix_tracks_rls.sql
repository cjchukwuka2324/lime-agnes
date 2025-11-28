-- ============================================
-- RLS POLICIES FOR TRACKS TABLE
-- ============================================

ALTER TABLE tracks ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DO $$ 
BEGIN
    DROP POLICY IF EXISTS "Users can view tracks in own albums" ON tracks;
    DROP POLICY IF EXISTS "Users can view tracks in shared albums" ON tracks;
    DROP POLICY IF EXISTS "Users can create tracks in own albums" ON tracks;
    DROP POLICY IF EXISTS "Users can create tracks in collaborative albums" ON tracks;
    DROP POLICY IF EXISTS "Users can update own tracks" ON tracks;
    DROP POLICY IF EXISTS "Users can update tracks in own albums" ON tracks;
    DROP POLICY IF EXISTS "Users can update tracks in collaborative albums" ON tracks;
    DROP POLICY IF EXISTS "Users can delete own tracks" ON tracks;
    DROP POLICY IF EXISTS "Users can delete tracks in own albums" ON tracks;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- Users can view tracks in albums they own
CREATE POLICY "Users can view tracks in own albums"
    ON tracks FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM albums
            WHERE CAST(albums.id AS text) = CAST(tracks.album_id AS text)
              AND CAST(albums.artist_id AS text) = CAST(auth.uid() AS text)
        )
    );

-- Users can view tracks in albums shared with them
CREATE POLICY "Users can view tracks in shared albums"
    ON tracks FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM shared_albums
            WHERE CAST(shared_albums.album_id AS text) = CAST(tracks.album_id AS text)
              AND CAST(shared_albums.shared_with AS text) = CAST(auth.uid() AS text)
        )
    );

-- Users can create tracks in albums they own
CREATE POLICY "Users can create tracks in own albums"
    ON tracks FOR INSERT
    WITH CHECK (
        CAST(artist_id AS text) = CAST(auth.uid() AS text)
        AND EXISTS (
            SELECT 1 FROM albums
            WHERE CAST(albums.id AS text) = CAST(tracks.album_id AS text)
              AND CAST(albums.artist_id AS text) = CAST(auth.uid() AS text)
        )
    );

-- Users can create tracks in collaborative albums
CREATE POLICY "Users can create tracks in collaborative albums"
    ON tracks FOR INSERT
    WITH CHECK (
        CAST(artist_id AS text) = CAST(auth.uid() AS text)
        AND EXISTS (
            SELECT 1 FROM shared_albums
            WHERE CAST(shared_albums.album_id AS text) = CAST(tracks.album_id AS text)
              AND CAST(shared_albums.shared_with AS text) = CAST(auth.uid() AS text)
              AND shared_albums.is_collaboration = true
        )
    );

-- Users can update tracks they created
CREATE POLICY "Users can update own tracks"
    ON tracks FOR UPDATE
    USING (CAST(artist_id AS text) = CAST(auth.uid() AS text))
    WITH CHECK (CAST(artist_id AS text) = CAST(auth.uid() AS text));

-- Users can update tracks in albums they own
CREATE POLICY "Users can update tracks in own albums"
    ON tracks FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM albums
            WHERE CAST(albums.id AS text) = CAST(tracks.album_id AS text)
              AND CAST(albums.artist_id AS text) = CAST(auth.uid() AS text)
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM albums
            WHERE CAST(albums.id AS text) = CAST(tracks.album_id AS text)
              AND CAST(albums.artist_id AS text) = CAST(auth.uid() AS text)
        )
    );

-- Users can update tracks in collaborative albums
CREATE POLICY "Users can update tracks in collaborative albums"
    ON tracks FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM shared_albums
            WHERE CAST(shared_albums.album_id AS text) = CAST(tracks.album_id AS text)
              AND CAST(shared_albums.shared_with AS text) = CAST(auth.uid() AS text)
              AND shared_albums.is_collaboration = true
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM shared_albums
            WHERE CAST(shared_albums.album_id AS text) = CAST(tracks.album_id AS text)
              AND CAST(shared_albums.shared_with AS text) = CAST(auth.uid() AS text)
              AND shared_albums.is_collaboration = true
        )
    );

-- Users can delete tracks they created
CREATE POLICY "Users can delete own tracks"
    ON tracks FOR DELETE
    USING (CAST(artist_id AS text) = CAST(auth.uid() AS text));

-- Users can delete tracks in albums they own
CREATE POLICY "Users can delete tracks in own albums"
    ON tracks FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM albums
            WHERE CAST(albums.id AS text) = CAST(tracks.album_id AS text)
              AND CAST(albums.artist_id AS text) = CAST(auth.uid() AS text)
        )
    );

