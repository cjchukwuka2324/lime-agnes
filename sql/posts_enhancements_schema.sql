-- ============================================
-- Posts Enhancements Schema
-- ============================================
-- Adds support for Spotify links, polls, and background music
-- Run this after supabase_posts_schema.sql
-- ============================================

-- Add new columns to posts table
ALTER TABLE posts 
ADD COLUMN IF NOT EXISTS spotify_link_url TEXT,
ADD COLUMN IF NOT EXISTS spotify_link_type TEXT CHECK (spotify_link_type IN ('track', 'playlist') OR spotify_link_type IS NULL),
ADD COLUMN IF NOT EXISTS spotify_link_data JSONB,
ADD COLUMN IF NOT EXISTS poll_question TEXT,
ADD COLUMN IF NOT EXISTS poll_type TEXT CHECK (poll_type IN ('single', 'multiple') OR poll_type IS NULL),
ADD COLUMN IF NOT EXISTS poll_options JSONB,
ADD COLUMN IF NOT EXISTS background_music_spotify_id TEXT,
ADD COLUMN IF NOT EXISTS background_music_data JSONB;

-- Create post_poll_votes table
CREATE TABLE IF NOT EXISTS post_poll_votes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    option_index INT NOT NULL CHECK (option_index >= 0),
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    UNIQUE(post_id, user_id, option_index)
);

CREATE INDEX IF NOT EXISTS idx_post_poll_votes_post_id ON post_poll_votes(post_id);
CREATE INDEX IF NOT EXISTS idx_post_poll_votes_user_id ON post_poll_votes(user_id);

-- Enable RLS on post_poll_votes
ALTER TABLE post_poll_votes ENABLE ROW LEVEL SECURITY;

-- RLS Policies for post_poll_votes
DROP POLICY IF EXISTS "Users can view all poll votes" ON post_poll_votes;
CREATE POLICY "Users can view all poll votes" ON post_poll_votes
    FOR SELECT
    USING (true);

DROP POLICY IF EXISTS "Users can vote on polls" ON post_poll_votes;
CREATE POLICY "Users can vote on polls" ON post_poll_votes
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete their own votes" ON post_poll_votes;
CREATE POLICY "Users can delete their own votes" ON post_poll_votes
    FOR DELETE
    USING (auth.uid() = user_id);

-- ============================================
-- Update create_post RPC function
-- ============================================

-- Drop existing create_post function(s) to avoid ambiguity
-- The original function has 11 parameters (without the new Spotify/poll/background music params)
DROP FUNCTION IF EXISTS create_post(
    TEXT,      -- p_text
    TEXT[],    -- p_image_urls
    TEXT,      -- p_video_url
    TEXT,      -- p_audio_url
    UUID,      -- p_parent_post_id
    TEXT,      -- p_leaderboard_entry_id
    TEXT,      -- p_leaderboard_artist_name
    INT,       -- p_leaderboard_rank
    TEXT,      -- p_leaderboard_percentile_label
    INT,       -- p_leaderboard_minutes_listened
    UUID       -- p_reshared_post_id
) CASCADE;

CREATE OR REPLACE FUNCTION create_post(
    p_text TEXT,
    p_image_urls TEXT[] DEFAULT ARRAY[]::TEXT[],
    p_video_url TEXT DEFAULT NULL,
    p_audio_url TEXT DEFAULT NULL,
    p_parent_post_id UUID DEFAULT NULL,
    p_leaderboard_entry_id TEXT DEFAULT NULL,
    p_leaderboard_artist_name TEXT DEFAULT NULL,
    p_leaderboard_rank INT DEFAULT NULL,
    p_leaderboard_percentile_label TEXT DEFAULT NULL,
    p_leaderboard_minutes_listened INT DEFAULT NULL,
    p_reshared_post_id UUID DEFAULT NULL,
    p_spotify_link_url TEXT DEFAULT NULL,
    p_spotify_link_type TEXT DEFAULT NULL,
    p_spotify_link_data JSONB DEFAULT NULL,
    p_poll_question TEXT DEFAULT NULL,
    p_poll_type TEXT DEFAULT NULL,
    p_poll_options JSONB DEFAULT NULL,
    p_background_music_spotify_id TEXT DEFAULT NULL,
    p_background_music_data JSONB DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_post_id UUID;
    v_current_user_id UUID;
BEGIN
    v_current_user_id := auth.uid();
    
    IF v_current_user_id IS NULL THEN
        RAISE EXCEPTION 'User must be authenticated';
    END IF;
    
    INSERT INTO posts (
        user_id,
        text,
        image_urls,
        video_url,
        audio_url,
        parent_post_id,
        leaderboard_entry_id,
        leaderboard_artist_name,
        leaderboard_rank,
        leaderboard_percentile_label,
        leaderboard_minutes_listened,
        reshared_post_id,
        spotify_link_url,
        spotify_link_type,
        spotify_link_data,
        poll_question,
        poll_type,
        poll_options,
        background_music_spotify_id,
        background_music_data,
        created_at,
        updated_at
    ) VALUES (
        v_current_user_id,
        COALESCE(p_text, ''),
        COALESCE(p_image_urls, ARRAY[]::TEXT[]),
        p_video_url,
        p_audio_url,
        p_parent_post_id,
        p_leaderboard_entry_id,
        p_leaderboard_artist_name,
        p_leaderboard_rank,
        p_leaderboard_percentile_label,
        p_leaderboard_minutes_listened,
        p_reshared_post_id,
        p_spotify_link_url,
        p_spotify_link_type,
        p_spotify_link_data,
        p_poll_question,
        p_poll_type,
        p_poll_options,
        p_background_music_spotify_id,
        p_background_music_data,
        NOW(),
        NOW()
    )
    RETURNING id INTO v_post_id;
    
    RETURN v_post_id;
END;
$$;

-- ============================================
-- Create vote_on_poll RPC function
-- ============================================

CREATE OR REPLACE FUNCTION vote_on_poll(
    p_post_id UUID,
    p_option_indices INT[]
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_user_id UUID;
    v_option_index INT;
    v_poll_type TEXT;
    v_existing_votes INT;
    v_option_indices_array INT[];
BEGIN
    v_current_user_id := auth.uid();
    
    IF v_current_user_id IS NULL THEN
        RAISE EXCEPTION 'User must be authenticated';
    END IF;
    
    -- Handle NULL or empty array
    IF p_option_indices IS NULL THEN
        v_option_indices_array := ARRAY[]::INT[];
    ELSE
        v_option_indices_array := p_option_indices;
    END IF;
    
    -- Get poll type
    SELECT poll_type INTO v_poll_type
    FROM posts
    WHERE id = p_post_id AND deleted_at IS NULL;
    
    IF v_poll_type IS NULL THEN
        RAISE EXCEPTION 'Post does not have a poll';
    END IF;
    
    -- For single choice polls, user can only vote once
    IF v_poll_type = 'single' THEN
        -- Delete existing vote for this user
        DELETE FROM post_poll_votes
        WHERE post_id = p_post_id AND user_id = v_current_user_id;
        
        -- Insert new vote (only first option for single choice)
        IF array_length(v_option_indices_array, 1) > 0 THEN
            INSERT INTO post_poll_votes (post_id, user_id, option_index)
            VALUES (p_post_id, v_current_user_id, v_option_indices_array[1])
            ON CONFLICT (post_id, user_id, option_index) DO NOTHING;
        END IF;
    ELSE
        -- For multiple choice, remove existing votes for this user
        DELETE FROM post_poll_votes
        WHERE post_id = p_post_id AND user_id = v_current_user_id;
        
        -- Insert new votes (only if array is not empty)
        IF array_length(v_option_indices_array, 1) > 0 THEN
            FOREACH v_option_index IN ARRAY v_option_indices_array
            LOOP
                INSERT INTO post_poll_votes (post_id, user_id, option_index)
                VALUES (p_post_id, v_current_user_id, v_option_index)
                ON CONFLICT (post_id, user_id, option_index) DO NOTHING;
            END LOOP;
        END IF;
    END IF;
    
    -- Update poll_options JSONB with new vote counts
    -- Handle both array format and object format for poll_options
    UPDATE posts
    SET poll_options = (
        SELECT COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'text', COALESCE(option->>'text', (option->'options'->>(ordinality - 1))->>'text'),
                    'votes', (
                        SELECT COUNT(*)
                        FROM post_poll_votes
                        WHERE post_id = p_post_id 
                        AND option_index = (ordinality - 1)::INT
                    )
                )
            ),
            '[]'::jsonb
        )
        FROM jsonb_array_elements(
            CASE 
                WHEN jsonb_typeof(poll_options) = 'array' THEN poll_options
                WHEN jsonb_typeof(poll_options) = 'object' AND poll_options ? 'options' THEN poll_options->'options'
                ELSE '[]'::jsonb
            END
        ) WITH ORDINALITY AS t(option, ordinality)
    )
    WHERE id = p_post_id;
END;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION create_post TO authenticated;
GRANT EXECUTE ON FUNCTION vote_on_poll TO authenticated;

