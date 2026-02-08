-- Migration: Allow 'answer' in recall_messages.message_type (fixes constraint violation from app)
-- If the constraint was previously updated to omit 'answer', this restores the full set the app sends.

ALTER TABLE public.recall_messages
DROP CONSTRAINT IF EXISTS recall_messages_message_type_check;

ALTER TABLE public.recall_messages
ADD CONSTRAINT recall_messages_message_type_check
CHECK (message_type IN ('text', 'voice', 'image', 'candidate', 'status', 'follow_up', 'answer'));
