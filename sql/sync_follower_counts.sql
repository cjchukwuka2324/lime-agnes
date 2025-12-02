-- Sync follower counts from user_follows table to profiles table
-- Run this SQL in Supabase Dashboard to fix follower/following count mismatches

-- Update followers_count for each user
UPDATE profiles p
SET followers_count = (
    SELECT COUNT(*)
    FROM user_follows f
    WHERE f.following_id = p.id
);

-- Update following_count for each user
UPDATE profiles p
SET following_count = (
    SELECT COUNT(*)
    FROM user_follows f
    WHERE f.follower_id = p.id
);

-- Create a trigger to keep counts in sync automatically
CREATE OR REPLACE FUNCTION update_follow_counts()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        -- Increment follower count for the followed user
        UPDATE profiles SET followers_count = followers_count + 1
        WHERE id = NEW.following_id;
        
        -- Increment following count for the follower
        UPDATE profiles SET following_count = following_count + 1
        WHERE id = NEW.follower_id;
        
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        -- Decrement follower count for the unfollowed user
        UPDATE profiles SET followers_count = GREATEST(followers_count - 1, 0)
        WHERE id = OLD.following_id;
        
        -- Decrement following count for the unfollower
        UPDATE profiles SET following_count = GREATEST(following_count - 1, 0)
        WHERE id = OLD.follower_id;
        
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop existing trigger if exists
DROP TRIGGER IF EXISTS on_follow_change ON user_follows;

-- Create trigger for follow/unfollow actions
CREATE TRIGGER on_follow_change
AFTER INSERT OR DELETE ON user_follows
FOR EACH ROW
EXECUTE FUNCTION update_follow_counts();

-- Verify the sync was successful
SELECT 
    p.id,
    p.display_name,
    p.followers_count,
    p.following_count,
    (SELECT COUNT(*) FROM user_follows f WHERE f.following_id = p.id) as actual_followers,
    (SELECT COUNT(*) FROM user_follows f WHERE f.follower_id = p.id) as actual_following
FROM profiles p
ORDER BY p.display_name;
