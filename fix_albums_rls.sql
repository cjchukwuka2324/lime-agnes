-- ============================================
-- STEP 1: Enable RLS & drop policies
-- ============================================

ALTER TABLE albums ENABLE ROW LEVEL SECURITY;
ALTER TABLE shared_albums ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own albums" ON albums;
DROP POLICY IF EXISTS "Users can view shared albums" ON albums;
DROP POLICY IF EXISTS "Users can create own albums" ON albums;
DROP POLICY IF EXISTS "Users can update own albums" ON albums;
DROP POLICY IF EXISTS "Users can delete own albums" ON albums;
DROP POLICY IF EXISTS "Collaborators can update albums" ON albums;
DROP POLICY IF EXISTS "Users can view albums shared with them" ON shared_albums;
DROP POLICY IF EXISTS "Users can view albums they shared" ON shared_albums;
DROP POLICY IF EXISTS "Users can create shares for own albums" ON shared_albums;
DROP POLICY IF EXISTS "Users can accept shares" ON shared_albums;
DROP POLICY IF EXISTS "Users can update shares they received" ON shared_albums;
DROP POLICY IF EXISTS "Users can delete shares they created" ON shared_albums;
DROP POLICY IF EXISTS "Users can remove shares they received" ON shared_albums;

ALTER TABLE shared_albums 
ADD COLUMN IF NOT EXISTS is_collaboration BOOLEAN DEFAULT false;

-- ============================================
-- STEP 2: ALBUMS POLICIES
-- ============================================

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

-- 4. Users can update own albums
CREATE POLICY "Users can update own albums"
    ON albums FOR UPDATE
    USING (
        CAST(artist_id AS text) = CAST(auth.uid() AS text)
    )
    WITH CHECK (
        CAST(artist_id AS text) = CAST(auth.uid() AS text)
    );

-- 5. Users can delete own albums
CREATE POLICY "Users can delete own albums"
    ON albums FOR DELETE
    USING (
        CAST(artist_id AS text) = CAST(auth.uid() AS text)
    );

-- 6. Collaborators can update albums
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

-- ============================================
-- STEP 3: SHARED_ALBUMS POLICIES
-- ============================================

-- 7. Users can see shares where they're recipient
CREATE POLICY "Users can view albums shared with them"
    ON shared_albums FOR SELECT
    USING (
        CAST(shared_with AS text) = CAST(auth.uid() AS text)
    );

-- 8. Users can see shares they sent
CREATE POLICY "Users can view albums they shared"
    ON shared_albums FOR SELECT
    USING (
        CAST(shared_by AS text) = CAST(auth.uid() AS text)
    );

-- 9. Users can share their own albums
CREATE POLICY "Users can create shares for own albums"
    ON shared_albums FOR INSERT
    WITH CHECK (
        CAST(shared_by AS text) = CAST(auth.uid() AS text)
        AND EXISTS (
            SELECT 1 FROM albums
            WHERE CAST(albums.id AS text) = CAST(shared_albums.album_id AS text)
              AND CAST(albums.artist_id AS text) = CAST(auth.uid() AS text)
        )
    );

-- 10. Users can accept shares directed at them
CREATE POLICY "Users can accept shares"
    ON shared_albums FOR INSERT
    WITH CHECK (
        CAST(shared_with AS text) = CAST(auth.uid() AS text)
    );

-- 11. Users can delete shares they created
CREATE POLICY "Users can delete shares they created"
    ON shared_albums FOR DELETE
    USING (
        CAST(shared_by AS text) = CAST(auth.uid() AS text)
    );

-- 12. Users can remove shares they received
CREATE POLICY "Users can remove shares they received"
    ON shared_albums FOR DELETE
    USING (
        CAST(shared_with AS text) = CAST(auth.uid() AS text)
    );
