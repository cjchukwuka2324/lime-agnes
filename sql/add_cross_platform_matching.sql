-- Cross-Platform Matching Migration
-- Adds support for Apple Music and cross-platform artist matching
-- This migration enables unified leaderboards across Spotify and Apple Music

-- ============================================
-- 1. Create Unified Music Platform Connections Table
-- ============================================

-- Create unified connection table to replace/enhance spotify_connections
CREATE TABLE IF NOT EXISTS music_platform_connections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    platform TEXT NOT NULL CHECK (platform IN ('spotify', 'apple_music')),
    -- Spotify-specific fields
    spotify_user_id TEXT,
    access_token TEXT,
    refresh_token TEXT,
    -- Apple Music-specific fields
    apple_music_user_id TEXT,
    user_token TEXT, -- MusicKit user token
    -- Common fields
    expires_at TIMESTAMPTZ,
    connected_at TIMESTAMPTZ DEFAULT NOW(),
    display_name TEXT,
    email TEXT,
    -- Constraints
    CHECK (
        (platform = 'spotify' AND spotify_user_id IS NOT NULL AND access_token IS NOT NULL) OR
        (platform = 'apple_music' AND apple_music_user_id IS NOT NULL AND user_token IS NOT NULL)
    )
);

CREATE INDEX IF NOT EXISTS idx_music_platform_connections_user ON music_platform_connections(user_id);
CREATE INDEX IF NOT EXISTS idx_music_platform_connections_platform ON music_platform_connections(platform);

-- Enable RLS
ALTER TABLE music_platform_connections ENABLE ROW LEVEL SECURITY;

-- RLS Policies for music_platform_connections
DROP POLICY IF EXISTS "Users can view own connections" ON music_platform_connections;
CREATE POLICY "Users can view own connections"
    ON music_platform_connections FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can create own connections" ON music_platform_connections;
CREATE POLICY "Users can create own connections"
    ON music_platform_connections FOR INSERT
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own connections" ON music_platform_connections;
CREATE POLICY "Users can update own connections"
    ON music_platform_connections FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Note: No DELETE policy - connections are permanent (binding)

-- Migrate existing spotify_connections to music_platform_connections
INSERT INTO music_platform_connections (
    user_id,
    platform,
    spotify_user_id,
    access_token,
    refresh_token,
    expires_at,
    connected_at,
    display_name,
    email
)
SELECT 
    user_id,
    'spotify'::TEXT,
    spotify_user_id,
    access_token,
    refresh_token,
    expires_at,
    connected_at,
    display_name,
    email
FROM spotify_connections
ON CONFLICT (user_id) DO NOTHING;

-- ============================================
-- 2. Update Artists Table
-- ============================================

ALTER TABLE artists 
ADD COLUMN IF NOT EXISTS apple_music_id TEXT,
ADD COLUMN IF NOT EXISTS normalized_name TEXT,
ADD COLUMN IF NOT EXISTS isrc TEXT;

-- Create indexes for efficient matching
CREATE INDEX IF NOT EXISTS idx_artists_spotify_id ON artists(spotify_id) WHERE spotify_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_artists_apple_music_id ON artists(apple_music_id) WHERE apple_music_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_artists_normalized_name ON artists(normalized_name) WHERE normalized_name IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_artists_isrc ON artists(isrc) WHERE isrc IS NOT NULL;

-- ============================================
-- 3. Create Cross-Platform Artist Matches Cache Table
-- ============================================

CREATE TABLE IF NOT EXISTS cross_platform_artist_matches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    spotify_artist_id TEXT,
    apple_music_artist_id TEXT,
    unified_artist_id TEXT NOT NULL,
    match_confidence TEXT NOT NULL CHECK (match_confidence IN ('high', 'medium', 'low')),
    match_method TEXT NOT NULL CHECK (match_method IN ('isrc', 'name_fuzzy', 'track_name', 'manual')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CHECK (spotify_artist_id IS NOT NULL OR apple_music_artist_id IS NOT NULL)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_cross_matches_spotify ON cross_platform_artist_matches(spotify_artist_id) WHERE spotify_artist_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_cross_matches_apple ON cross_platform_artist_matches(apple_music_artist_id) WHERE apple_music_artist_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_cross_matches_unified ON cross_platform_artist_matches(unified_artist_id);

-- ============================================
-- 4. Update RockList Play Events Table
-- ============================================

ALTER TABLE rocklist_play_events
ADD COLUMN IF NOT EXISTS platform TEXT CHECK (platform IN ('spotify', 'apple_music')),
ADD COLUMN IF NOT EXISTS isrc TEXT,
ADD COLUMN IF NOT EXISTS platform_artist_id TEXT,
ADD COLUMN IF NOT EXISTS platform_track_id TEXT;

-- Set default platform to 'spotify' for existing records
UPDATE rocklist_play_events
SET platform = 'spotify'
WHERE platform IS NULL;

-- Make platform NOT NULL after backfill
ALTER TABLE rocklist_play_events
ALTER COLUMN platform SET NOT NULL;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_play_events_platform ON rocklist_play_events(platform);
CREATE INDEX IF NOT EXISTS idx_play_events_isrc ON rocklist_play_events(isrc) WHERE isrc IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_play_events_platform_artist ON rocklist_play_events(platform, platform_artist_id);

-- ============================================
-- 5. Enable pg_trgm Extension for Fuzzy Matching
-- ============================================

CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- ============================================
-- 6. Create Artist Name Normalization Function
-- ============================================

CREATE OR REPLACE FUNCTION normalize_artist_name(name TEXT) 
RETURNS TEXT AS $$
BEGIN
    IF name IS NULL OR name = '' THEN
        RETURN NULL;
    END IF;
    
    RETURN lower(
        trim(
            regexp_replace(
                regexp_replace(
                    regexp_replace(
                        regexp_replace(
                            regexp_replace(name, '[^a-zA-Z0-9\s]', '', 'g'), -- Remove special chars
                            '''', '', 'g' -- Remove apostrophes
                        ),
                        '\s+', '', 'g' -- Remove all whitespace
                    ),
                    '^(the|a|an)', '', 'i' -- Remove "The", "A", "An" prefix
                ),
                '^\s*', '', 'g' -- Trim leading spaces
            )
        )
    );
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ============================================
-- 7. Create Track Name Normalization Function
-- ============================================

CREATE OR REPLACE FUNCTION normalize_track_name(track_name TEXT) 
RETURNS TEXT AS $$
BEGIN
    IF track_name IS NULL THEN
        RETURN NULL;
    END IF;
    
    RETURN lower(
        trim(
            regexp_replace(
                regexp_replace(
                    regexp_replace(
                        regexp_replace(
                            regexp_replace(track_name, '[^a-zA-Z0-9\s]', '', 'g'), -- Remove special chars
                            '''', '', 'g' -- Remove apostrophes
                        ),
                        '\s+', '', 'g' -- Remove all whitespace
                    ),
                    '(remix|feat|ft|featuring|feat\.|ft\.)', '', 'i' -- Remove remix/feat indicators
                ),
                '^', '', 'g'
            )
        )
    );
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ============================================
-- 8. Create Unified Artist Matching Function
-- ============================================

CREATE OR REPLACE FUNCTION match_or_create_unified_artist(
    p_platform TEXT,
    p_platform_artist_id TEXT,
    p_artist_name TEXT,
    p_isrc TEXT DEFAULT NULL,
    p_platform_track_id TEXT DEFAULT NULL,
    p_track_name TEXT DEFAULT NULL
) RETURNS TEXT AS $$
DECLARE
    v_unified_artist_id TEXT;
    v_normalized_name TEXT;
    v_similarity_score NUMERIC;
    v_match_confidence TEXT;
    v_match_method TEXT;
    v_existing_spotify_id TEXT;
    v_existing_normalized_name TEXT;
BEGIN
    -- Validate inputs
    IF p_platform NOT IN ('spotify', 'apple_music') THEN
        RAISE EXCEPTION 'Invalid platform: %', p_platform;
    END IF;
    
    IF p_platform_artist_id IS NULL OR p_artist_name IS NULL THEN
        RAISE EXCEPTION 'platform_artist_id and artist_name are required';
    END IF;
    
    -- Normalize artist name
    v_normalized_name := normalize_artist_name(p_artist_name);
    
    -- Step 1: Check cache first
    IF p_platform = 'spotify' THEN
        SELECT unified_artist_id INTO v_unified_artist_id
        FROM cross_platform_artist_matches
        WHERE spotify_artist_id = p_platform_artist_id
        LIMIT 1;
    ELSE
        SELECT unified_artist_id INTO v_unified_artist_id
        FROM cross_platform_artist_matches
        WHERE apple_music_artist_id = p_platform_artist_id
        LIMIT 1;
    END IF;
    
    IF v_unified_artist_id IS NOT NULL THEN
        RETURN v_unified_artist_id;
    END IF;
    
    -- Step 2: ISRC-based matching (highest confidence)
    IF p_isrc IS NOT NULL AND p_isrc != '' THEN
        -- Look for existing artist with this ISRC
        SELECT a.spotify_id INTO v_unified_artist_id
        FROM artists a
        WHERE a.isrc = p_isrc
        LIMIT 1;
        
        IF v_unified_artist_id IS NOT NULL THEN
            -- Update artist with platform-specific ID if missing
            IF p_platform = 'spotify' THEN
                UPDATE artists 
                SET spotify_id = COALESCE(spotify_id, p_platform_artist_id),
                    name = COALESCE(name, p_artist_name),
                    normalized_name = COALESCE(normalized_name, v_normalized_name)
                WHERE spotify_id = v_unified_artist_id;
            ELSE
                UPDATE artists 
                SET apple_music_id = COALESCE(apple_music_id, p_platform_artist_id),
                    name = COALESCE(name, p_artist_name),
                    normalized_name = COALESCE(normalized_name, v_normalized_name)
                WHERE spotify_id = v_unified_artist_id;
            END IF;
            
            -- Cache the match
            INSERT INTO cross_platform_artist_matches (
                spotify_artist_id, 
                apple_music_artist_id, 
                unified_artist_id, 
                match_confidence, 
                match_method
            )
            VALUES (
                CASE WHEN p_platform = 'spotify' THEN p_platform_artist_id ELSE NULL END,
                CASE WHEN p_platform = 'apple_music' THEN p_platform_artist_id ELSE NULL END,
                v_unified_artist_id,
                'high',
                'isrc'
            )
            ON CONFLICT DO NOTHING;
            
            RETURN v_unified_artist_id;
        END IF;
    END IF;
    
    -- Step 3: Check if artist already exists with this platform ID
    IF p_platform = 'spotify' THEN
        SELECT spotify_id, normalized_name INTO v_existing_spotify_id, v_existing_normalized_name
        FROM artists
        WHERE spotify_id = p_platform_artist_id
        LIMIT 1;
    ELSE
        -- For Apple Music, check both apple_music_id and spotify_id with 'am:' prefix
        SELECT spotify_id, normalized_name INTO v_existing_spotify_id, v_existing_normalized_name
        FROM artists
        WHERE apple_music_id = p_platform_artist_id
           OR spotify_id = 'am:' || p_platform_artist_id
        LIMIT 1;
    END IF;
    
    IF v_existing_spotify_id IS NOT NULL THEN
        -- Update normalized name if missing
        IF v_existing_normalized_name IS NULL THEN
            UPDATE artists 
            SET normalized_name = v_normalized_name
            WHERE spotify_id = v_existing_spotify_id;
        END IF;
        
        -- Update platform-specific ID if missing
        IF p_platform = 'spotify' THEN
            UPDATE artists
            SET spotify_id = COALESCE(spotify_id, p_platform_artist_id)
            WHERE spotify_id = v_existing_spotify_id;
        ELSE
            UPDATE artists
            SET apple_music_id = COALESCE(apple_music_id, p_platform_artist_id)
            WHERE spotify_id = v_existing_spotify_id;
        END IF;
        
        RETURN v_existing_spotify_id;
    END IF;
    
    -- Step 4: Fuzzy name matching using normalized name
    SELECT 
        a.spotify_id,
        similarity(a.normalized_name, v_normalized_name)
    INTO v_existing_spotify_id, v_similarity_score
    FROM artists a
    WHERE a.normalized_name IS NOT NULL
      AND similarity(a.normalized_name, v_normalized_name) > 0.85
    ORDER BY similarity(a.normalized_name, v_normalized_name) DESC
    LIMIT 1;
    
    IF v_existing_spotify_id IS NOT NULL THEN
        v_unified_artist_id := v_existing_spotify_id;
        
        -- Determine confidence based on similarity
        IF v_similarity_score >= 0.95 THEN
            v_match_confidence := 'high';
        ELSIF v_similarity_score >= 0.90 THEN
            v_match_confidence := 'medium';
        ELSE
            v_match_confidence := 'low';
        END IF;
        
        v_match_method := 'name_fuzzy';
        
        -- Update artist with platform-specific ID
        IF p_platform = 'spotify' THEN
            UPDATE artists 
            SET spotify_id = COALESCE(spotify_id, p_platform_artist_id),
                name = COALESCE(name, p_artist_name),
                normalized_name = COALESCE(normalized_name, v_normalized_name)
            WHERE spotify_id = v_unified_artist_id;
        ELSE
            UPDATE artists 
            SET apple_music_id = COALESCE(apple_music_id, p_platform_artist_id),
                name = COALESCE(name, p_artist_name),
                normalized_name = COALESCE(normalized_name, v_normalized_name)
            WHERE spotify_id = v_unified_artist_id;
        END IF;
        
        -- Cache the match
        INSERT INTO cross_platform_artist_matches (
            spotify_artist_id, 
            apple_music_artist_id, 
            unified_artist_id, 
            match_confidence, 
            match_method
        )
        VALUES (
            CASE WHEN p_platform = 'spotify' THEN p_platform_artist_id ELSE NULL END,
            CASE WHEN p_platform = 'apple_music' THEN p_platform_artist_id ELSE NULL END,
            v_unified_artist_id,
            v_match_confidence,
            v_match_method
        )
        ON CONFLICT DO NOTHING;
        
        RETURN v_unified_artist_id;
    END IF;
    
    -- Step 5: Fallback - Track name + artist name matching
    IF p_track_name IS NOT NULL AND p_track_name != '' THEN
        SELECT DISTINCT rpe.artist_id INTO v_unified_artist_id
        FROM rocklist_play_events rpe
        INNER JOIN artists a ON a.spotify_id = rpe.artist_id
        WHERE normalize_artist_name(rpe.track_name) = normalize_track_name(p_track_name)
          AND a.normalized_name = v_normalized_name
        LIMIT 1;
        
        IF v_unified_artist_id IS NOT NULL THEN
            -- Update artist with platform-specific ID
            IF p_platform = 'spotify' THEN
                UPDATE artists 
                SET spotify_id = COALESCE(spotify_id, p_platform_artist_id),
                    name = COALESCE(name, p_artist_name),
                    normalized_name = COALESCE(normalized_name, v_normalized_name)
                WHERE spotify_id = v_unified_artist_id;
            ELSE
                UPDATE artists 
                SET apple_music_id = COALESCE(apple_music_id, p_platform_artist_id),
                    name = COALESCE(name, p_artist_name),
                    normalized_name = COALESCE(normalized_name, v_normalized_name)
                WHERE spotify_id = v_unified_artist_id;
            END IF;
            
            -- Cache the match
            INSERT INTO cross_platform_artist_matches (
                spotify_artist_id, 
                apple_music_artist_id, 
                unified_artist_id, 
                match_confidence, 
                match_method
            )
            VALUES (
                CASE WHEN p_platform = 'spotify' THEN p_platform_artist_id ELSE NULL END,
                CASE WHEN p_platform = 'apple_music' THEN p_platform_artist_id ELSE NULL END,
                v_unified_artist_id,
                'medium',
                'track_name'
            )
            ON CONFLICT DO NOTHING;
            
            RETURN v_unified_artist_id;
        END IF;
    END IF;
    
    -- Step 6: Create new artist (no match found)
    -- For Spotify: use spotify_id directly as the unified artist_id
    -- For Apple Music: use 'am:' prefix + apple_music_id as spotify_id (since spotify_id is the primary key)
    IF p_platform = 'spotify' THEN
        v_unified_artist_id := p_platform_artist_id;
    ELSE
        -- For Apple Music, prefix the ID to avoid conflicts with Spotify IDs
        -- Use 'am:' prefix (Apple Music)
        v_unified_artist_id := 'am:' || p_platform_artist_id;
    END IF;
    
    INSERT INTO artists (
        spotify_id,
        apple_music_id,
        name,
        normalized_name,
        isrc,
        created_at
    )
    VALUES (
        v_unified_artist_id,
        CASE WHEN p_platform = 'apple_music' THEN p_platform_artist_id ELSE NULL END,
        p_artist_name,
        v_normalized_name,
        p_isrc,
        NOW()
    )
    ON CONFLICT (spotify_id) DO UPDATE SET
        apple_music_id = COALESCE(artists.apple_music_id, EXCLUDED.apple_music_id),
        name = COALESCE(artists.name, EXCLUDED.name),
        normalized_name = COALESCE(artists.normalized_name, EXCLUDED.normalized_name),
        isrc = COALESCE(artists.isrc, EXCLUDED.isrc);
    
    RETURN v_unified_artist_id;
    
EXCEPTION
    WHEN OTHERS THEN
        -- Log error and return platform_artist_id as fallback
        RAISE WARNING 'Error in match_or_create_unified_artist: %', SQLERRM;
        RETURN p_platform_artist_id;
END;
$$ LANGUAGE plpgsql;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION match_or_create_unified_artist(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;

-- ============================================
-- 9. Update rocklist_ingest_plays to use matching function
-- ============================================

-- This will be done in a separate migration to update the existing function
-- See update_rocklist_ingest_plays_for_cross_platform.sql

-- ============================================
-- 10. Backfill normalized names for existing artists
-- ============================================

UPDATE artists
SET normalized_name = normalize_artist_name(name)
WHERE normalized_name IS NULL;

-- ============================================
-- 11. Create GIN index for fast fuzzy matching
-- ============================================

CREATE INDEX IF NOT EXISTS idx_artists_normalized_name_trgm ON artists USING GIN (normalized_name gin_trgm_ops);

-- Comments
COMMENT ON TABLE music_platform_connections IS 'Unified table for music platform connections (Spotify or Apple Music), one per user (binding)';
COMMENT ON TABLE cross_platform_artist_matches IS 'Cache of verified cross-platform artist matches to avoid repeated fuzzy matching';
COMMENT ON FUNCTION normalize_artist_name IS 'Normalizes artist name for cross-platform matching (removes special chars, apostrophes, "The" prefix)';
COMMENT ON FUNCTION match_or_create_unified_artist IS 'Matches or creates unified artist ID for cross-platform leaderboard aggregation';

