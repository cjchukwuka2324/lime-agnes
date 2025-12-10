-- Notifications table for RockOut app
-- Stores all in-app notifications for users

CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    actor_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    type TEXT NOT NULL CHECK (type IN ('new_follower', 'post_like', 'post_reply', 'rocklist_rank', 'new_post', 'post_echo', 'post_mention')),
    post_id UUID NULL,
    rocklist_id TEXT NULL,
    old_rank INT NULL,
    new_rank INT NULL,
    message TEXT NOT NULL,
    read_at TIMESTAMPTZ NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for efficient querying
CREATE INDEX IF NOT EXISTS idx_notifications_user_created_at ON notifications(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_user_unread ON notifications(user_id, read_at) WHERE read_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_notifications_actor ON notifications(actor_id);
CREATE INDEX IF NOT EXISTS idx_notifications_post ON notifications(post_id);

-- Add notify_on_posts column to user_follows table
ALTER TABLE user_follows 
ADD COLUMN IF NOT EXISTS notify_on_posts BOOLEAN NOT NULL DEFAULT false;

-- Row Level Security (RLS) Policies
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Users can view their own notifications" ON notifications;
DROP POLICY IF EXISTS "System can insert notifications" ON notifications;
DROP POLICY IF EXISTS "Users can update their own notifications" ON notifications;
DROP POLICY IF EXISTS "Users can delete their own notifications" ON notifications;

-- Users can only read their own notifications
CREATE POLICY "Users can view their own notifications"
    ON notifications FOR SELECT
    USING (auth.uid() = user_id);

-- System can insert notifications (for triggers)
CREATE POLICY "System can insert notifications"
    ON notifications FOR INSERT
    WITH CHECK (true);

-- Users can update their own notifications (mark as read)
CREATE POLICY "Users can update their own notifications"
    ON notifications FOR UPDATE
    USING (auth.uid() = user_id);

-- Users can delete their own notifications
CREATE POLICY "Users can delete their own notifications"
    ON notifications FOR DELETE
    USING (auth.uid() = user_id);

COMMENT ON TABLE notifications IS 'Stores all user notifications for the RockOut app';
COMMENT ON COLUMN notifications.type IS 'Type of notification: new_follower, post_like, post_reply, rocklist_rank, new_post, post_echo, post_mention';
COMMENT ON COLUMN notifications.message IS 'Human-readable notification message';
COMMENT ON COLUMN notifications.read_at IS 'Timestamp when notification was marked as read, NULL if unread';

