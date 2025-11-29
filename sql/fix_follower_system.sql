-- ============================================
-- FIX: Follower System Complete Setup
-- Run this FIRST before any other scripts
-- ============================================

-- Step 1: Drop existing functions and table (if they exist with wrong structure)
DROP FUNCTION IF EXISTS follow_user(UUID) CASCADE;
DROP FUNCTION IF EXISTS unfollow_user(UUID) CASCADE;
DROP TABLE IF EXISTS user_follows CASCADE;

-- Step 2: Create user_follows table with correct structure
CREATE TABLE user_follows (
    follower_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    following_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    notify_on_posts BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (follower_id, following_id),
    CHECK (follower_id != following_id)
);

-- Step 3: Create indexes
CREATE INDEX idx_user_follows_follower ON user_follows(follower_id);
CREATE INDEX idx_user_follows_following ON user_follows(following_id);
CREATE INDEX idx_user_follows_notify ON user_follows(notify_on_posts) WHERE notify_on_posts = true;

-- Step 4: Enable RLS
ALTER TABLE user_follows ENABLE ROW LEVEL SECURITY;

-- Step 5: Create RLS Policies
DROP POLICY IF EXISTS "Users can view all follows" ON user_follows;
CREATE POLICY "Users can view all follows" ON user_follows
    FOR SELECT
    USING (true);

DROP POLICY IF EXISTS "Users can follow others" ON user_follows;
CREATE POLICY "Users can follow others" ON user_follows
    FOR INSERT
    WITH CHECK (auth.uid() = follower_id);

DROP POLICY IF EXISTS "Users can unfollow" ON user_follows;
CREATE POLICY "Users can unfollow" ON user_follows
    FOR DELETE
    USING (auth.uid() = follower_id);

DROP POLICY IF EXISTS "Users can update their follows" ON user_follows;
CREATE POLICY "Users can update their follows" ON user_follows
    FOR UPDATE
    USING (auth.uid() = follower_id);

-- Step 6: Add count columns to profiles (if they don't exist)
ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS followers_count INTEGER NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS following_count INTEGER NOT NULL DEFAULT 0;

-- Step 7: Create follow_user function
CREATE OR REPLACE FUNCTION follow_user(target_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_id UUID;
    insert_count INT;
BEGIN
    current_user_id := auth.uid();
    
    -- Validation
    IF current_user_id IS NULL THEN
        RAISE EXCEPTION 'User must be authenticated';
    END IF;
    
    IF current_user_id = target_user_id THEN
        RAISE EXCEPTION 'Cannot follow yourself';
    END IF;
    
    -- Insert follow relationship
    INSERT INTO user_follows (follower_id, following_id)
    VALUES (current_user_id, target_user_id)
    ON CONFLICT (follower_id, following_id) DO NOTHING;
    
    -- Check if insert actually happened
    GET DIAGNOSTICS insert_count = ROW_COUNT;
    
    -- Update counts only if we actually inserted a new row
    IF insert_count > 0 THEN
        -- Increment following_count for current user
        UPDATE profiles
        SET following_count = following_count + 1
        WHERE id = current_user_id;
        
        -- Increment followers_count for target user
        UPDATE profiles
        SET followers_count = followers_count + 1
        WHERE id = target_user_id;
        
        RAISE NOTICE 'Successfully followed user %', target_user_id;
    ELSE
        RAISE NOTICE 'Already following user %', target_user_id;
    END IF;
END;
$$;

-- Step 8: Create unfollow_user function
CREATE OR REPLACE FUNCTION unfollow_user(target_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_id UUID;
    delete_count INT;
BEGIN
    current_user_id := auth.uid();
    
    -- Validation
    IF current_user_id IS NULL THEN
        RAISE EXCEPTION 'User must be authenticated';
    END IF;
    
    -- Delete follow relationship
    DELETE FROM user_follows
    WHERE follower_id = current_user_id
      AND following_id = target_user_id;
    
    -- Check if delete actually happened
    GET DIAGNOSTICS delete_count = ROW_COUNT;
    
    -- Update counts only if we actually deleted a row
    IF delete_count > 0 THEN
        -- Decrement following_count for current user
        UPDATE profiles
        SET following_count = GREATEST(following_count - 1, 0)
        WHERE id = current_user_id;
        
        -- Decrement followers_count for target user
        UPDATE profiles
        SET followers_count = GREATEST(followers_count - 1, 0)
        WHERE id = target_user_id;
        
        RAISE NOTICE 'Successfully unfollowed user %', target_user_id;
    ELSE
        RAISE NOTICE 'Was not following user %', target_user_id;
    END IF;
END;
$$;

-- Step 9: Grant permissions
GRANT EXECUTE ON FUNCTION follow_user TO authenticated;
GRANT EXECUTE ON FUNCTION unfollow_user TO authenticated;

-- Step 10: Create helper function to sync counts (in case they get out of sync)
CREATE OR REPLACE FUNCTION sync_follower_counts()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Update followers_count
    UPDATE profiles p
    SET followers_count = (
        SELECT COUNT(*)
        FROM user_follows
        WHERE following_id = p.id
    );
    
    -- Update following_count
    UPDATE profiles p
    SET following_count = (
        SELECT COUNT(*)
        FROM user_follows
        WHERE follower_id = p.id
    );
    
    RAISE NOTICE 'Follower counts synchronized';
END;
$$;

GRANT EXECUTE ON FUNCTION sync_follower_counts TO authenticated;

-- ============================================
-- Verification Queries
-- ============================================

-- Check table structure
DO $$
BEGIN
    RAISE NOTICE 'Verification: Checking user_follows table...';
    
    -- Check if table exists
    IF EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name = 'user_follows'
    ) THEN
        RAISE NOTICE '✓ user_follows table exists';
    ELSE
        RAISE WARNING '✗ user_follows table does NOT exist';
    END IF;
    
    -- Check if functions exist
    IF EXISTS (
        SELECT FROM information_schema.routines 
        WHERE routine_schema = 'public' 
        AND routine_name = 'follow_user'
    ) THEN
        RAISE NOTICE '✓ follow_user function exists';
    ELSE
        RAISE WARNING '✗ follow_user function does NOT exist';
    END IF;
    
    IF EXISTS (
        SELECT FROM information_schema.routines 
        WHERE routine_schema = 'public' 
        AND routine_name = 'unfollow_user'
    ) THEN
        RAISE NOTICE '✓ unfollow_user function exists';
    ELSE
        RAISE WARNING '✗ unfollow_user function does NOT exist';
    END IF;
    
    -- Check if columns exist in profiles
    IF EXISTS (
        SELECT FROM information_schema.columns 
        WHERE table_name = 'profiles' 
        AND column_name = 'followers_count'
    ) THEN
        RAISE NOTICE '✓ profiles.followers_count column exists';
    ELSE
        RAISE WARNING '✗ profiles.followers_count column does NOT exist';
    END IF;
    
    IF EXISTS (
        SELECT FROM information_schema.columns 
        WHERE table_name = 'profiles' 
        AND column_name = 'following_count'
    ) THEN
        RAISE NOTICE '✓ profiles.following_count column exists';
    ELSE
        RAISE WARNING '✗ profiles.following_count column does NOT exist';
    END IF;
    
    RAISE NOTICE 'Setup complete! Check the notices above for verification.';
END $$;

