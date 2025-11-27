-- ============================================
-- Schema Fix Migration for Artists Table
-- ============================================
-- Run this in Supabase SQL Editor to fix the "column a.spotify_id does not exist" error
-- 
-- INSTRUCTIONS:
-- 1. Open Supabase Dashboard > SQL Editor
-- 2. Copy and paste this entire script
-- 3. Click "Run" to execute
-- ============================================

-- Step 1: Ensure artists table has correct schema
-- This will create the table if it doesn't exist, or fix it if it has wrong columns

-- Drop table if it exists with wrong schema (only if missing spotify_id column)
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name = 'artists'
    ) AND NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'artists' 
        AND column_name = 'spotify_id'
    ) THEN
        -- Table exists but missing spotify_id column - drop it
        DROP TABLE IF EXISTS artists CASCADE;
    END IF;
END $$;

-- Step 2: Create artists table with correct schema
CREATE TABLE IF NOT EXISTS artists (
    spotify_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    image_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Step 3: Create index if it doesn't exist
CREATE INDEX IF NOT EXISTS idx_artists_spotify_id ON artists(spotify_id);

-- Step 4: Recreate the function to ensure it works with correct schema
CREATE OR REPLACE FUNCTION get_my_rocklist_summary(
    p_start_timestamp TIMESTAMPTZ,
    p_end_timestamp TIMESTAMPTZ,
    p_region TEXT DEFAULT NULL
)
RETURNS TABLE (
    artist_id TEXT,
    artist_name TEXT,
    artist_image_url TEXT,
    my_rank BIGINT,
    my_score NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_user_id UUID;
BEGIN
    v_current_user_id := (SELECT auth.uid());
    
    RETURN QUERY
    WITH all_ranked_stats AS (
        SELECT
            rls.artist_id,
            rls.user_id,
            rls.score,
            RANK() OVER (
                PARTITION BY rls.artist_id, COALESCE(rls.region, 'GLOBAL')
                ORDER BY rls.score DESC
            ) AS rank
        FROM rocklist_stats rls
        WHERE rls.updated_at >= p_start_timestamp
            AND rls.updated_at <= p_end_timestamp
            AND (p_region IS NULL OR rls.region = p_region)
    ),
    user_stats AS (
        SELECT
            ars.artist_id,
            ars.score AS my_score,
            ars.rank AS my_rank
        FROM all_ranked_stats ars
        WHERE ars.user_id = v_current_user_id
    ),
    artist_info AS (
        SELECT DISTINCT
            us.artist_id,
            a.name AS artist_name,
            a.image_url AS artist_image_url,
            us.my_rank,
            us.my_score
        FROM user_stats us
        INNER JOIN artists a ON a.spotify_id = us.artist_id
        WHERE us.artist_id IS NOT NULL
    )
    SELECT
        ai.artist_id,
        ai.artist_name,
        ai.artist_image_url,
        ai.my_rank,
        ai.my_score
    FROM artist_info ai
    ORDER BY ai.my_rank ASC NULLS LAST, ai.artist_name ASC;
END;
$$;

-- Step 5: Grant permissions
GRANT EXECUTE ON FUNCTION get_my_rocklist_summary TO authenticated;

-- ============================================
-- Verification Query
-- ============================================
-- Run this to verify the schema is correct:
-- SELECT column_name, data_type, is_nullable 
-- FROM information_schema.columns 
-- WHERE table_schema = 'public' 
-- AND table_name = 'artists'
-- ORDER BY ordinal_position;

