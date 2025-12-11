-- Notification Triggers for RockOut
-- Automatically create notifications when specific events occur

-- ============================================================================
-- TRIGGER 1: New Follower Notification
-- ============================================================================

-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS trg_new_follower_notification ON user_follows;

CREATE OR REPLACE FUNCTION notify_new_follower()
RETURNS TRIGGER AS $$
DECLARE
    actor_name TEXT;
BEGIN
    -- Get the follower's display name
    SELECT COALESCE(p.display_name, CONCAT(p.first_name, ' ', p.last_name), u.email)
    INTO actor_name
    FROM profiles p
    LEFT JOIN auth.users u ON u.id = p.id
    WHERE p.id = NEW.follower_id;
    
    -- Create notification for the user being followed
    INSERT INTO notifications (user_id, actor_id, type, message)
    VALUES (
        NEW.following_id,
        NEW.follower_id,
        'new_follower',
        actor_name || ' started following you'
    );
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_new_follower_notification
    AFTER INSERT ON user_follows
    FOR EACH ROW
    EXECUTE FUNCTION notify_new_follower();

-- ============================================================================
-- TRIGGER 2: Post Like Notification
-- ============================================================================

-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS trg_post_like_notification ON post_likes;

CREATE OR REPLACE FUNCTION notify_post_like()
RETURNS TRIGGER AS $$
DECLARE
    post_author_id UUID;
    actor_name TEXT;
BEGIN
    -- Get the post author's ID
    SELECT user_id INTO post_author_id
    FROM posts
    WHERE id = NEW.post_id;
    
    -- Don't notify if user likes their own post
    IF post_author_id = NEW.user_id THEN
        RETURN NEW;
    END IF;
    
    -- Get the liker's display name
    SELECT COALESCE(p.display_name, CONCAT(p.first_name, ' ', p.last_name), u.email)
    INTO actor_name
    FROM profiles p
    LEFT JOIN auth.users u ON u.id = p.id
    WHERE p.id = NEW.user_id;
    
    -- Create notification for post author
    INSERT INTO notifications (user_id, actor_id, type, post_id, message)
    VALUES (
        post_author_id,
        NEW.user_id,
        'post_like',
        NEW.post_id,
        actor_name || ' liked your post'
    );
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_post_like_notification
    AFTER INSERT ON post_likes
    FOR EACH ROW
    EXECUTE FUNCTION notify_post_like();

-- ============================================================================
-- TRIGGER 3: Post Reply Notification
-- ============================================================================

-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS trg_post_reply_notification ON posts;

CREATE OR REPLACE FUNCTION notify_post_reply()
RETURNS TRIGGER AS $$
DECLARE
    parent_author_id UUID;
    actor_name TEXT;
    post_preview TEXT;
BEGIN
    -- Only process if this is a reply (has parent_post_id)
    IF NEW.parent_post_id IS NULL THEN
        RETURN NEW;
    END IF;
    
    -- Get the parent post author's ID
    SELECT user_id INTO parent_author_id
    FROM posts
    WHERE id = NEW.parent_post_id;
    
    -- Don't notify if user replies to their own post
    IF parent_author_id = NEW.user_id THEN
        RETURN NEW;
    END IF;
    
    -- Get the replier's display name
    SELECT COALESCE(p.display_name, CONCAT(p.first_name, ' ', p.last_name), u.email)
    INTO actor_name
    FROM profiles p
    LEFT JOIN auth.users u ON u.id = p.id
    WHERE p.id = NEW.user_id;
    
    -- Create post preview (first 50 chars)
    post_preview := SUBSTRING(NEW.text FROM 1 FOR 50);
    IF LENGTH(NEW.text) > 50 THEN
        post_preview := post_preview || '...';
    END IF;
    
    -- Create notification for parent post author
    INSERT INTO notifications (user_id, actor_id, type, post_id, message)
    VALUES (
        parent_author_id,
        NEW.user_id,
        'post_reply',
        NEW.parent_post_id,
        actor_name || ' replied to your post'
    );
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_post_reply_notification
    AFTER INSERT ON posts
    FOR EACH ROW
    EXECUTE FUNCTION notify_post_reply();

-- ============================================================================
-- TRIGGER 4: RockList Rank Improvement Notification
-- ============================================================================

-- Drop existing trigger if it exists (commented out until rocklist_stats table exists)
-- DROP TRIGGER IF EXISTS trg_rocklist_rank_notification ON rocklist_stats;

CREATE OR REPLACE FUNCTION notify_rocklist_rank_improvement()
RETURNS TRIGGER AS $$
DECLARE
    artist_name TEXT;
BEGIN
    -- Only notify if rank improved (lower number = better rank)
    IF NEW.rank IS NULL OR OLD.rank IS NULL OR NEW.rank >= OLD.rank THEN
        RETURN NEW;
    END IF;
    
    -- Get artist name (assuming artist_id is stored and there's an artists table or we use the ID)
    artist_name := NEW.artist_id;
    
    -- Create notification for user
    INSERT INTO notifications (user_id, type, rocklist_id, old_rank, new_rank, message)
    VALUES (
        NEW.user_id,
        'rocklist_rank',
        NEW.artist_id,
        OLD.rank,
        NEW.rank,
        'You moved up to rank ' || NEW.rank || ' for ' || artist_name
    );
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Note: This trigger assumes a rocklist_stats table exists
-- Uncomment when ready to use:
-- DROP TRIGGER IF EXISTS trg_rocklist_rank_notification ON rocklist_stats;
-- CREATE TRIGGER trg_rocklist_rank_notification
--     AFTER UPDATE ON rocklist_stats
--     FOR EACH ROW
--     EXECUTE FUNCTION notify_rocklist_rank_improvement();

-- ============================================================================
-- TRIGGER 5: New Post from Followed User (with notifications enabled)
-- ============================================================================

-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS trg_new_post_notification ON posts;

CREATE OR REPLACE FUNCTION notify_new_post_from_followed()
RETURNS TRIGGER AS $$
DECLARE
    follower_record RECORD;
    actor_name TEXT;
    post_preview TEXT;
BEGIN
    -- Only process top-level posts (not replies)
    IF NEW.parent_post_id IS NOT NULL THEN
        RETURN NEW;
    END IF;
    
    -- Get the poster's display name
    SELECT COALESCE(p.display_name, CONCAT(p.first_name, ' ', p.last_name), u.email)
    INTO actor_name
    FROM profiles p
    LEFT JOIN auth.users u ON u.id = p.id
    WHERE p.id = NEW.user_id;
    
    -- Create post preview (first 50 chars)
    post_preview := SUBSTRING(NEW.text FROM 1 FOR 50);
    IF LENGTH(NEW.text) > 50 THEN
        post_preview := post_preview || '...';
    END IF;
    
    -- Create notifications for all followers who have post notifications enabled
    FOR follower_record IN
        SELECT follower_id
        FROM user_follows
        WHERE following_id = NEW.user_id
          AND notify_on_posts = true
    LOOP
        INSERT INTO notifications (user_id, actor_id, type, post_id, message)
        VALUES (
            follower_record.follower_id,
            NEW.user_id,
            'new_post',
            NEW.id,
            actor_name || ' posted: ' || post_preview
        );
    END LOOP;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_new_post_notification
    AFTER INSERT ON posts
    FOR EACH ROW
    EXECUTE FUNCTION notify_new_post_from_followed();

-- ============================================================================
-- TRIGGER 6: Post Echo Notification
-- ============================================================================

-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS trg_post_echo_notification ON posts;

CREATE OR REPLACE FUNCTION notify_post_echo()
RETURNS TRIGGER AS $$
DECLARE
    original_author_id UUID;
    actor_name TEXT;
BEGIN
    -- Only process if this is an echo (has reshared_post_id)
    IF NEW.reshared_post_id IS NULL THEN
        RETURN NEW;
    END IF;
    
    -- Get the original post author's ID
    SELECT user_id INTO original_author_id
    FROM posts
    WHERE id = NEW.reshared_post_id;
    
    -- Don't notify if user echoes their own post
    IF original_author_id = NEW.user_id THEN
        RETURN NEW;
    END IF;
    
    -- Get the echoer's display name
    SELECT COALESCE(p.display_name, CONCAT(p.first_name, ' ', p.last_name), u.email)
    INTO actor_name
    FROM profiles p
    LEFT JOIN auth.users u ON u.id = p.id
    WHERE p.id = NEW.user_id;
    
    -- Create notification for original post author
    INSERT INTO notifications (user_id, actor_id, type, post_id, message)
    VALUES (
        original_author_id,
        NEW.user_id,
        'post_echo',
        NEW.reshared_post_id,
        actor_name || ' echoed your Bar'
    );
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_post_echo_notification
    AFTER INSERT ON posts
    FOR EACH ROW
    EXECUTE FUNCTION notify_post_echo();

-- ============================================================================
-- TRIGGER 7: Post Mention Notification
-- ============================================================================

-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS trg_post_mention_notification ON posts;

CREATE OR REPLACE FUNCTION notify_post_mention()
RETURNS TRIGGER AS $$
DECLARE
    mentioned_user_id UUID;
    actor_name TEXT;
    post_preview TEXT;
BEGIN
    -- Only process if there are mentioned users
    IF NEW.mentioned_user_ids IS NULL OR array_length(NEW.mentioned_user_ids, 1) IS NULL THEN
        RETURN NEW;
    END IF;
    
    -- Get the mentioner's display name
    SELECT COALESCE(p.display_name, CONCAT(p.first_name, ' ', p.last_name), u.email)
    INTO actor_name
    FROM profiles p
    LEFT JOIN auth.users u ON u.id = p.id
    WHERE p.id = NEW.user_id;
    
    -- Create post preview (first 50 chars)
    post_preview := SUBSTRING(NEW.text FROM 1 FOR 50);
    IF LENGTH(NEW.text) > 50 THEN
        post_preview := post_preview || '...';
    END IF;
    
    -- Create notification for each mentioned user (except the post author)
    FOREACH mentioned_user_id IN ARRAY NEW.mentioned_user_ids
    LOOP
        -- Skip if user mentions themselves
        IF mentioned_user_id = NEW.user_id THEN
            CONTINUE;
        END IF;
        
        -- Create notification for mentioned user
        INSERT INTO notifications (user_id, actor_id, type, post_id, message)
        VALUES (
            mentioned_user_id,
            NEW.user_id,
            'post_mention',
            NEW.id,
            actor_name || ' mentioned you in a Bar'
        );
    END LOOP;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_post_mention_notification
    AFTER INSERT ON posts
    FOR EACH ROW
    WHEN (NEW.mentioned_user_ids IS NOT NULL)
    EXECUTE FUNCTION notify_post_mention();

-- ============================================================================
-- Utility Functions
-- ============================================================================

-- Function to mark all notifications as read for a user
CREATE OR REPLACE FUNCTION mark_all_notifications_read(target_user_id UUID)
RETURNS void AS $$
BEGIN
    UPDATE notifications
    SET read_at = NOW()
    WHERE user_id = target_user_id
      AND read_at IS NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get unread notification count
CREATE OR REPLACE FUNCTION get_unread_notification_count(target_user_id UUID)
RETURNS INTEGER AS $$
DECLARE
    count INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO count
    FROM notifications
    WHERE user_id = target_user_id
      AND read_at IS NULL;
    
    RETURN count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- TRIGGER 7: Cascade Delete Echoes When Post is Deleted
-- ============================================================================

-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS trg_cascade_delete_echoes ON posts;

CREATE OR REPLACE FUNCTION cascade_delete_echoes()
RETURNS TRIGGER AS $$
BEGIN
    -- When a post is deleted (deleted_at is set), mark all echo posts as deleted
    IF NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL THEN
        UPDATE posts
        SET deleted_at = NEW.deleted_at
        WHERE reshared_post_id = NEW.id
          AND deleted_at IS NULL;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_cascade_delete_echoes
    AFTER UPDATE ON posts
    FOR EACH ROW
    WHEN (NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL)
    EXECUTE FUNCTION cascade_delete_echoes();

COMMENT ON FUNCTION notify_new_follower() IS 'Creates notification when a user gains a new follower';
COMMENT ON FUNCTION notify_post_like() IS 'Creates notification when a post is liked';
COMMENT ON FUNCTION notify_post_reply() IS 'Creates notification when someone replies to a post';
COMMENT ON FUNCTION notify_rocklist_rank_improvement() IS 'Creates notification when user rank improves';
COMMENT ON FUNCTION notify_new_post_from_followed() IS 'Creates notification when followed user posts (if enabled)';
COMMENT ON FUNCTION notify_post_echo() IS 'Creates notification when someone echoes (reposts) a post';
COMMENT ON FUNCTION notify_post_mention() IS 'Creates notification when a user is mentioned in a post';
COMMENT ON FUNCTION cascade_delete_echoes() IS 'Cascades deletion to all echo posts when original post is deleted';

