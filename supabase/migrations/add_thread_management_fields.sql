-- ============================================
-- Add Thread Management Fields to Recall Tables
-- ============================================
-- Adds fields for thread management (pin, archive, delete, summary)
-- and message status tracking
-- ============================================

-- Add missing fields to recall_threads
ALTER TABLE public.recall_threads
ADD COLUMN IF NOT EXISTS pinned BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS archived BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS summary TEXT; -- For GPT context summarization

-- Add status field to recall_messages for sending/sent/failed states
ALTER TABLE public.recall_messages
ADD COLUMN IF NOT EXISTS status TEXT CHECK (status IN ('sending', 'sent', 'failed')) DEFAULT 'sent',
ADD COLUMN IF NOT EXISTS response_text TEXT; -- For assistant responses (separate from text field)

-- Add indices for performance
CREATE INDEX IF NOT EXISTS idx_recall_threads_pinned ON public.recall_threads(pinned) WHERE pinned = TRUE;
CREATE INDEX IF NOT EXISTS idx_recall_threads_archived ON public.recall_threads(archived) WHERE archived = FALSE;
CREATE INDEX IF NOT EXISTS idx_recall_threads_deleted_at ON public.recall_threads(deleted_at) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_recall_messages_status ON public.recall_messages(status);

-- Add comments for documentation
COMMENT ON COLUMN public.recall_threads.pinned IS 'Whether the thread is pinned to the top of the threads list';
COMMENT ON COLUMN public.recall_threads.archived IS 'Whether the thread is archived (hidden from main view)';
COMMENT ON COLUMN public.recall_threads.deleted_at IS 'Soft delete timestamp. NULL means not deleted.';
COMMENT ON COLUMN public.recall_threads.summary IS 'GPT-generated summary of thread conversation for context in subsequent messages';
COMMENT ON COLUMN public.recall_messages.status IS 'Message delivery status: sending, sent, or failed';
COMMENT ON COLUMN public.recall_messages.response_text IS 'Assistant response text (separate from text field which may contain user input)';






