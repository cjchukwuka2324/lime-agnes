-- Push Notification Trigger for RockOut
-- Automatically sends push notifications when notifications are created
-- Uses pg_net extension to call the Supabase Edge Function

-- ============================================================================
-- Enable pg_net extension (if not already enabled)
-- ============================================================================
CREATE EXTENSION IF NOT EXISTS pg_net;

-- ============================================================================
-- Function to trigger push notification via Edge Function
-- ============================================================================

CREATE OR REPLACE FUNCTION trigger_push_notification()
RETURNS TRIGGER AS $$
DECLARE
    edge_function_url TEXT;
    supabase_anon_key TEXT;
    notification_title TEXT;
    notification_body TEXT;
    payload JSONB;
    response_id BIGINT;
BEGIN
    -- Get Supabase project URL and anon key from current_setting
    -- These should be set as database configuration or use environment variables
    -- For now, we'll construct from the current database connection
    -- Note: In Supabase, you can get these from the project settings
    
    -- Construct edge function URL
    -- Format: https://{project_ref}.supabase.co/functions/v1/send_push_notification
    -- We'll use a placeholder that needs to be replaced with actual project ref
    -- Or use current_setting if configured
    edge_function_url := COALESCE(
        current_setting('app.supabase_functions_url', true),
        'https://wklzogrfdrqluwchoqsp.supabase.co/functions/v1/send_push_notification'
    );
    
    -- Get anon key (should be set as database configuration)
    supabase_anon_key := COALESCE(
        current_setting('app.supabase_anon_key', true),
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndrbHpvZ3JmZHJxbHV3Y2hvcXNwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjMxMjAzNDcsImV4cCI6MjA3ODY5NjM0N30.HPrlq9hi2ab0YPsE5B8OibheLOmmNqmHKG2qRjt_3jY'
    );
    
    -- Format notification title based on type
    CASE NEW.type
        WHEN 'new_follower' THEN
            notification_title := 'New Follower';
        WHEN 'post_like' THEN
            notification_title := 'Post Liked';
        WHEN 'post_reply' THEN
            notification_title := 'New Reply';
        WHEN 'rocklist_rank' THEN
            notification_title := 'Rank Improved';
        WHEN 'new_post' THEN
            notification_title := 'New Post';
        ELSE
            notification_title := 'Notification';
    END CASE;
    
    -- Use the message as the body
    notification_body := NEW.message;
    
    -- Build payload for edge function
    payload := jsonb_build_object(
        'user_id', NEW.user_id::text,
        'title', notification_title,
        'body', notification_body,
        'data', jsonb_build_object(
            'type', NEW.type,
            'notification_id', NEW.id::text,
            'actor_id', COALESCE(NEW.actor_id::text, NULL),
            'post_id', COALESCE(NEW.post_id::text, NULL),
            'rocklist_id', COALESCE(NEW.rocklist_id, NULL)
        )
    );
    
    -- Call edge function via pg_net (async, non-blocking)
    SELECT net.http_post(
        url := edge_function_url,
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || supabase_anon_key
        ),
        body := payload::text
    ) INTO response_id;
    
    -- Log the request (optional, for debugging)
    RAISE LOG 'Push notification triggered for user %: type=%, notification_id=%, http_request_id=%',
        NEW.user_id, NEW.type, NEW.id, response_id;
    
    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        -- Log error but don't fail the notification creation
        RAISE WARNING 'Failed to trigger push notification for notification %: %', NEW.id, SQLERRM;
        RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- Create trigger on notifications table
-- ============================================================================

-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS trg_send_push_notification ON notifications;

CREATE TRIGGER trg_send_push_notification
    AFTER INSERT ON notifications
    FOR EACH ROW
    EXECUTE FUNCTION trigger_push_notification();

-- ============================================================================
-- Comments
-- ============================================================================

COMMENT ON FUNCTION trigger_push_notification() IS 'Triggers push notification via Edge Function when a notification is created';
COMMENT ON TRIGGER trg_send_push_notification ON notifications IS 'Automatically sends push notifications when notifications are inserted';


