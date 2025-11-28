-- Alternative approach: Use subqueries to force type conversion
-- Run this if the main fix_albums_rls.sql still fails

-- ============================================
-- ALBUMS TABLE POLICIES (Alternative)
-- ============================================

ALTER TABLE albums ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view shared albums" ON albums;
DROP POLICY IF EXISTS "Collaborators can update albums" ON albums;

-- Users can view albums that have been shared with them
-- Use subquery to force type conversion
CREATE POLICY "Users can view shared albums"
    ON albums FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM (
                SELECT 
                    album_id::text as album_id_text,
                    shared_with::text as shared_with_text
                FROM shared_albums
            ) sa
            WHERE sa.album_id_text = albums.id::text
            AND sa.shared_with_text = auth.uid()::text
        )
    );

-- Collaborators can update albums
CREATE POLICY "Collaborators can update albums"
    ON albums FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM (
                SELECT 
                    album_id::text as album_id_text,
                    shared_with::text as shared_with_text
                FROM shared_albums
                WHERE is_collaboration = true
            ) sa
            WHERE sa.album_id_text = albums.id::text
            AND sa.shared_with_text = auth.uid()::text
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM (
                SELECT 
                    album_id::text as album_id_text,
                    shared_with::text as shared_with_text
                FROM shared_albums
                WHERE is_collaboration = true
            ) sa
            WHERE sa.album_id_text = albums.id::text
            AND sa.shared_with_text = auth.uid()::text
        )
    );

