-- Migration: Add 'post_echo' to notifications type check constraint
-- This allows the notifications table to accept 'post_echo' as a valid notification type

-- Drop the existing check constraint
ALTER TABLE notifications 
DROP CONSTRAINT IF EXISTS notifications_type_check;

-- Add the new check constraint with 'post_echo' included
ALTER TABLE notifications 
ADD CONSTRAINT notifications_type_check 
CHECK (type IN ('new_follower', 'post_like', 'post_reply', 'rocklist_rank', 'new_post', 'post_echo'));

-- Update the comment to reflect the new type
COMMENT ON COLUMN notifications.type IS 'Type of notification: new_follower, post_like, post_reply, rocklist_rank, new_post, post_echo';

