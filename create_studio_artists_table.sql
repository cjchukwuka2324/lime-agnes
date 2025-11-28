-- ============================================
-- Create Studio Artists Table
-- ============================================
-- This table is specifically for Studio Sessions artists (user-created albums)
-- Separate from the 'artists' table which stores Spotify artist data
-- 
-- INSTRUCTIONS:
-- 1. Open Supabase Dashboard > SQL Editor
-- 2. Copy and paste this entire script
-- 3. Click "Run" to execute
-- ============================================

-- Create studio_artists table
CREATE TABLE IF NOT EXISTS studio_artists (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create index for faster lookups
CREATE INDEX IF NOT EXISTS idx_studio_artists_id ON studio_artists(id);

-- Enable Row Level Security
ALTER TABLE studio_artists ENABLE ROW LEVEL SECURITY;

-- RLS Policies for studio_artists

-- Policy: Users can view all studio artists (needed for displaying album artist names)
CREATE POLICY "Users can view studio artists"
ON studio_artists
FOR SELECT
TO authenticated
USING (true);

-- Policy: Users can insert their own artist record
CREATE POLICY "Users can create their own artist record"
ON studio_artists
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = id);

-- Policy: Users can update their own artist record
CREATE POLICY "Users can update their own artist record"
ON studio_artists
FOR UPDATE
TO authenticated
USING (auth.uid() = id)
WITH CHECK (auth.uid() = id);

-- Policy: Users can delete their own artist record
CREATE POLICY "Users can delete their own artist record"
ON studio_artists
FOR DELETE
TO authenticated
USING (auth.uid() = id);

-- ============================================
-- Migration: Update existing albums to use studio_artists
-- ============================================
-- If you have existing albums, you may need to migrate data
-- This assumes albums.artist_id currently references user IDs

-- Note: The albums table should already have artist_id as UUID
-- We just need to ensure studio_artists records exist for existing artist_ids

-- Function to ensure studio_artists record exists for a user
CREATE OR REPLACE FUNCTION ensure_studio_artist_exists(p_user_id UUID, p_name TEXT DEFAULT NULL)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_artist_name TEXT;
BEGIN
    -- Check if artist already exists
    IF EXISTS (SELECT 1 FROM studio_artists WHERE id = p_user_id) THEN
        -- Update name if provided
        IF p_name IS NOT NULL THEN
            UPDATE studio_artists 
            SET name = p_name, updated_at = NOW()
            WHERE id = p_user_id;
        END IF;
        RETURN p_user_id;
    END IF;
    
    -- Get name from user_profiles if not provided
    IF p_name IS NULL THEN
        SELECT COALESCE(
            (SELECT full_name FROM user_profiles WHERE id = p_user_id),
            (SELECT first_name || ' ' || last_name FROM user_profiles WHERE id = p_user_id),
            (SELECT email FROM auth.users WHERE id = p_user_id),
            'Unknown Artist'
        ) INTO v_artist_name;
    ELSE
        v_artist_name := p_name;
    END IF;
    
    -- Create artist record
    INSERT INTO studio_artists (id, name, created_at, updated_at)
    VALUES (p_user_id, v_artist_name, NOW(), NOW())
    ON CONFLICT (id) DO UPDATE
    SET name = EXCLUDED.name, updated_at = NOW();
    
    RETURN p_user_id;
END;
$$;

-- ============================================
-- Verification
-- ============================================
-- Run these queries to verify the setup:

-- Check table exists
-- SELECT * FROM information_schema.tables WHERE table_name = 'studio_artists';

-- Check RLS is enabled
-- SELECT tablename, rowsecurity FROM pg_tables WHERE tablename = 'studio_artists';

-- Check policies
-- SELECT * FROM pg_policies WHERE tablename = 'studio_artists';

