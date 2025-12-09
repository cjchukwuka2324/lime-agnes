-- Function to delete user account and all associated data
-- This function deletes user data from public tables
-- Note: Auth user deletion should be handled separately through Supabase admin API

CREATE OR REPLACE FUNCTION delete_user_account()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
BEGIN
    -- Get current user ID
    v_user_id := auth.uid();
    
    -- Validate user is authenticated
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'User must be authenticated';
    END IF;
    
    -- Delete user data from various tables (order matters due to foreign key constraints)
    -- Delete follows (both as follower and following)
    DELETE FROM user_follows WHERE follower_id = v_user_id OR following_id = v_user_id;
    
    -- Delete notifications
    DELETE FROM notifications WHERE user_id = v_user_id OR actor_id = v_user_id;
    
    -- Delete device tokens
    DELETE FROM device_tokens WHERE user_id = v_user_id;
    
    -- Delete comments
    DELETE FROM user_comments WHERE user_id = v_user_id;
    
    -- Delete posts
    DELETE FROM posts WHERE user_id = v_user_id;
    
    -- Delete shared albums and collaborations (where user is the one shared with)
    -- Note: This removes the user from shared albums but doesn't delete albums they don't own
    DELETE FROM shared_albums WHERE shared_with = v_user_id;
    
    -- Delete albums owned by user (this will cascade to tracks and related data if foreign keys are set up)
    DELETE FROM albums WHERE artist_id = v_user_id;
    
    -- Delete discovered albums
    DELETE FROM discovered_albums WHERE user_id = v_user_id;
    
    -- Delete track plays
    DELETE FROM track_plays WHERE user_id = v_user_id;
    
    -- Delete music platform connection
    DELETE FROM music_platform_connections WHERE user_id = v_user_id;
    
    -- Delete rocklist stats (if user has any)
    DELETE FROM rocklist_stats WHERE user_id = v_user_id;
    
    -- Delete profile (should be last as it might be referenced)
    DELETE FROM profiles WHERE id = v_user_id;
    
    -- Note: Auth user deletion should be done via Supabase Admin API or dashboard
    -- The client will handle this separately if needed
    
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION delete_user_account() TO authenticated;

-- Comment
COMMENT ON FUNCTION delete_user_account() IS 'Deletes all user data from public tables. Auth user deletion must be handled separately.';

