-- ============================================
-- Fix Follower/Following Counts - Run This Now
-- ============================================
-- This script will sync all follower/following counts from the user_follows table
-- to the profiles table. Run this in Supabase SQL Editor to fix mismatches.
-- ============================================

-- Step 1: Update followers_count for each user
UPDATE profiles p
SET followers_count = COALESCE((
    SELECT COUNT(*)::INTEGER
    FROM user_follows f
    WHERE f.following_id = p.id
), 0);

-- Step 2: Update following_count for each user
UPDATE profiles p
SET following_count = COALESCE((
    SELECT COUNT(*)::INTEGER
    FROM user_follows f
    WHERE f.follower_id = p.id
), 0);

-- Step 3: Verify the sync was successful
-- This query shows any mismatches (should return 0 rows if everything is synced)
SELECT 
    p.id,
    p.display_name,
    p.followers_count as stored_followers,
    (SELECT COUNT(*) FROM user_follows f WHERE f.following_id = p.id) as actual_followers,
    p.following_count as stored_following,
    (SELECT COUNT(*) FROM user_follows f WHERE f.follower_id = p.id) as actual_following,
    CASE 
        WHEN p.followers_count != (SELECT COUNT(*) FROM user_follows f WHERE f.following_id = p.id) 
             OR p.following_count != (SELECT COUNT(*) FROM user_follows f WHERE f.follower_id = p.id)
        THEN 'MISMATCH'
        ELSE 'OK'
    END as status
FROM profiles p
WHERE p.followers_count != (SELECT COUNT(*) FROM user_follows f WHERE f.following_id = p.id)
   OR p.following_count != (SELECT COUNT(*) FROM user_follows f WHERE f.follower_id = p.id)
ORDER BY p.display_name;

-- If the above query returns rows, run Steps 1 and 2 again
-- If it returns 0 rows, all counts are synced!




