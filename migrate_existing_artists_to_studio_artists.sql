-- ============================================
-- Migrate Existing Artists to studio_artists
-- ============================================
-- This script ensures that any existing albums have corresponding
-- studio_artists records. Run this AFTER creating the studio_artists table.
-- 
-- INSTRUCTIONS:
-- 1. Make sure you've run create_studio_artists_table.sql first
-- 2. Open Supabase Dashboard > SQL Editor
-- 3. Copy and paste this entire script
-- 4. Click "Run" to execute
-- ============================================

-- Insert studio_artists records for all users who have albums but no studio_artists record
INSERT INTO studio_artists (id, name, created_at, updated_at)
SELECT DISTINCT
    albums.artist_id AS id,
    COALESCE(
        user_profiles.full_name,
        user_profiles.first_name || ' ' || user_profiles.last_name,
        auth.users.email,
        'Unknown Artist'
    ) AS name,
    MIN(albums.created_at) AS created_at,
    NOW() AS updated_at
FROM albums
LEFT JOIN studio_artists ON studio_artists.id = albums.artist_id
LEFT JOIN user_profiles ON user_profiles.id = albums.artist_id
LEFT JOIN auth.users ON auth.users.id = albums.artist_id
WHERE studio_artists.id IS NULL
GROUP BY albums.artist_id, user_profiles.full_name, user_profiles.first_name, user_profiles.last_name, auth.users.email
ON CONFLICT (id) DO NOTHING;

-- Verify the migration
SELECT 
    COUNT(*) AS total_albums,
    COUNT(DISTINCT albums.artist_id) AS unique_artists,
    COUNT(DISTINCT studio_artists.id) AS studio_artists_records
FROM albums
LEFT JOIN studio_artists ON studio_artists.id = albums.artist_id;

