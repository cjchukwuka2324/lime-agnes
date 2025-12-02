-- ============================================
-- Follower/Following System RPC Functions
-- ============================================
-- This file contains PostgreSQL functions for managing
-- follower relationships and maintaining follower/following counts
-- ============================================

-- Ensure profiles table has follower/following count columns
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'profiles' AND column_name = 'followers_count'
    ) THEN
        ALTER TABLE profiles ADD COLUMN followers_count INTEGER DEFAULT 0 NOT NULL;
    END IF;
    
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'profiles' AND column_name = 'following_count'
    ) THEN
        ALTER TABLE profiles ADD COLUMN following_count INTEGER DEFAULT 0 NOT NULL;
    END IF;
END $$;

-- Initialize counts for existing profiles
UPDATE profiles p
SET 
    followers_count = COALESCE((
        SELECT COUNT(*)::INTEGER
        FROM user_follows uf
        WHERE uf.following_id = p.id
    ), 0),
    following_count = COALESCE((
        SELECT COUNT(*)::INTEGER
        FROM user_follows uf
        WHERE uf.follower_id = p.id
    ), 0)
WHERE followers_count = 0 AND following_count = 0;

-- ============================================
-- Function: follow_user
-- ============================================
-- Follows a user and updates follower/following counts atomically
-- Uses auth.uid() as the follower
-- ============================================

DROP FUNCTION IF EXISTS follow_user(UUID);
CREATE OR REPLACE FUNCTION follow_user(target_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_user_id UUID;
    v_inserted BOOLEAN := false;
BEGIN
    -- Get current user ID
    v_current_user_id := auth.uid();
    
    -- Validate user is authenticated
    IF v_current_user_id IS NULL THEN
        RAISE EXCEPTION 'User must be authenticated';
    END IF;
    
    -- Prevent self-follow
    IF v_current_user_id = target_user_id THEN
        RETURN;
    END IF;
    
    -- Insert follow relationship (on conflict do nothing)
    INSERT INTO user_follows (follower_id, following_id, created_at)
    VALUES (v_current_user_id, target_user_id, NOW())
    ON CONFLICT (follower_id, following_id) DO NOTHING
    RETURNING true INTO v_inserted;
    
    -- Only update counts if a new row was actually inserted
    IF v_inserted THEN
        -- Increment following_count for current user
        UPDATE profiles
        SET following_count = following_count + 1,
            updated_at = NOW()
        WHERE id = v_current_user_id;
        
        -- Increment followers_count for target user
        UPDATE profiles
        SET followers_count = followers_count + 1,
            updated_at = NOW()
        WHERE id = target_user_id;
    END IF;
END;
$$;

-- ============================================
-- Function: unfollow_user
-- ============================================
-- Unfollows a user and updates follower/following counts atomically
-- Uses auth.uid() as the follower
-- ============================================

DROP FUNCTION IF EXISTS unfollow_user(UUID);
CREATE OR REPLACE FUNCTION unfollow_user(target_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_user_id UUID;
    v_deleted BOOLEAN := false;
BEGIN
    -- Get current user ID
    v_current_user_id := auth.uid();
    
    -- Validate user is authenticated
    IF v_current_user_id IS NULL THEN
        RAISE EXCEPTION 'User must be authenticated';
    END IF;
    
    -- Prevent self-unfollow (shouldn't happen, but safe check)
    IF v_current_user_id = target_user_id THEN
        RETURN;
    END IF;
    
    -- Delete follow relationship
    DELETE FROM user_follows
    WHERE follower_id = v_current_user_id
      AND following_id = target_user_id
    RETURNING true INTO v_deleted;
    
    -- Only update counts if a row was actually deleted
    IF v_deleted THEN
        -- Decrement following_count for current user (ensure it doesn't go below 0)
        UPDATE profiles
        SET following_count = GREATEST(following_count - 1, 0),
            updated_at = NOW()
        WHERE id = v_current_user_id;
        
        -- Decrement followers_count for target user (ensure it doesn't go below 0)
        UPDATE profiles
        SET followers_count = GREATEST(followers_count - 1, 0),
            updated_at = NOW()
        WHERE id = target_user_id;
    END IF;
END;
$$;

-- ============================================
-- Grant execute permissions
-- ============================================

GRANT EXECUTE ON FUNCTION follow_user(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION unfollow_user(UUID) TO authenticated;

-- ============================================
-- Create indexes for better performance
-- ============================================

CREATE INDEX IF NOT EXISTS idx_profiles_followers_count ON profiles(followers_count);
CREATE INDEX IF NOT EXISTS idx_profiles_following_count ON profiles(following_count);

