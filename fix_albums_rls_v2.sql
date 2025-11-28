-- Alternative approach: Use subqueries to force type conversion
-- This ensures casts happen before comparisons

-- ============================================
-- ALBUMS TABLE POLICIES
-- ============================================

ALTER TABLE albums ENABLE ROW LEVEL SECURITY;

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

CREATE POLICY "Users can view own albums"
    ON albums FOR SELECT
    USING (artist_id = CAST(auth.uid() AS TEXT));

-- Use subquery to force type conversion
CREATE POLICY "Users can view shared albums"
    ON albums FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM (
                SELECT 
                    CAST(album_id AS TEXT) as album_id_text,
                    CAST(shared_with AS TEXT) as shared_with_text
                FROM shared_albums
            ) sa
            WHERE sa.album_id_text = CAST(albums.id AS TEXT)
            AND sa.shared_with_text = CAST(auth.uid() AS TEXT)
        )
    );

CREATE POLICY "Users can create own albums"
    ON albums FOR INSERT
    WITH CHECK (artist_id = CAST(auth.uid() AS TEXT));

CREATE POLICY "Users can update own albums"
    ON albums FOR UPDATE
    USING (artist_id = CAST(auth.uid() AS TEXT))
    WITH CHECK (artist_id = CAST(auth.uid() AS TEXT));

CREATE POLICY "Users can delete own albums"
    ON albums FOR DELETE
    USING (artist_id = CAST(auth.uid() AS TEXT));

CREATE POLICY "Collaborators can update albums"
    ON albums FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM (
                SELECT 
                    CAST(album_id AS TEXT) as album_id_text,
                    CAST(shared_with AS TEXT) as shared_with_text
                FROM shared_albums
                WHERE is_collaboration = true
            ) sa
            WHERE sa.album_id_text = CAST(albums.id AS TEXT)
            AND sa.shared_with_text = CAST(auth.uid() AS TEXT)
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM (
                SELECT 
                    CAST(album_id AS TEXT) as album_id_text,
                    CAST(shared_with AS TEXT) as shared_with_text
                FROM shared_albums
                WHERE is_collaboration = true
            ) sa
            WHERE sa.album_id_text = CAST(albums.id AS TEXT)
            AND sa.shared_with_text = CAST(auth.uid() AS TEXT)
        )
    );

-- ============================================
-- SHARED_ALBUMS TABLE POLICIES
-- ============================================

ALTER TABLE shared_albums 
ADD COLUMN IF NOT EXISTS is_collaboration BOOLEAN DEFAULT false;

ALTER TABLE shared_albums ENABLE ROW LEVEL SECURITY;

DO $$ 
BEGIN
    DROP POLICY IF EXISTS "Users can view albums shared with them" ON shared_albums;
    DROP POLICY IF EXISTS "Users can view albums they shared" ON shared_albums;
    DROP POLICY IF EXISTS "Users can create shares for own albums" ON shared_albums;
    DROP POLICY IF EXISTS "Users can accept shares" ON shared_albums;
    DROP POLICY IF EXISTS "Users can update shares they received" ON shared_albums;
    DROP POLICY IF EXISTS "Users can delete shares they created" ON shared_albums;
    DROP POLICY IF EXISTS "Users can remove shares they received" ON shared_albums;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

CREATE POLICY "Users can view albums shared with them"
    ON shared_albums FOR SELECT
    USING (CAST(shared_with AS TEXT) = CAST(auth.uid() AS TEXT));

CREATE POLICY "Users can view albums they shared"
    ON shared_albums FOR SELECT
    USING (CAST(shared_by AS TEXT) = CAST(auth.uid() AS TEXT));

CREATE POLICY "Users can create shares for own albums"
    ON shared_albums FOR INSERT
    WITH CHECK (
        CAST(shared_by AS TEXT) = CAST(auth.uid() AS TEXT)
        AND EXISTS (
            SELECT 1 FROM albums
            WHERE CAST(albums.id AS TEXT) = CAST(shared_albums.album_id AS TEXT)
            AND albums.artist_id = CAST(auth.uid() AS TEXT)
        )
    );

CREATE POLICY "Users can accept shares"
    ON shared_albums FOR INSERT
    WITH CHECK (CAST(shared_with AS TEXT) = CAST(auth.uid() AS TEXT));

CREATE POLICY "Users can delete shares they created"
    ON shared_albums FOR DELETE
    USING (CAST(shared_by AS TEXT) = CAST(auth.uid() AS TEXT));

CREATE POLICY "Users can remove shares they received"
    ON shared_albums FOR DELETE
    USING (CAST(shared_with AS TEXT) = CAST(auth.uid() AS TEXT));

