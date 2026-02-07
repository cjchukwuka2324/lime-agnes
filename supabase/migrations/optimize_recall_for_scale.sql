-- ============================================
-- Optimize Recall for 10K Concurrent Users
-- ============================================
-- Adds indexes and optimizations for scalability
-- ============================================

-- Composite index for common query pattern (thread + created_at)
CREATE INDEX IF NOT EXISTS idx_recall_messages_thread_created 
ON public.recall_messages(thread_id, created_at DESC);

-- Index for user's recent threads
CREATE INDEX IF NOT EXISTS idx_recall_threads_user_last_message 
ON public.recall_threads(user_id, last_message_at DESC) 
WHERE deleted_at IS NULL;

-- Partial index for active threads only (better performance)
CREATE INDEX IF NOT EXISTS idx_recall_threads_active 
ON public.recall_threads(user_id, last_message_at DESC) 
WHERE deleted_at IS NULL AND archived = false;

-- Index for message type filtering
CREATE INDEX IF NOT EXISTS idx_recall_messages_type 
ON public.recall_messages(thread_id, message_type, created_at DESC);

-- GIN index for JSONB searches (if needed for candidate_json queries)
CREATE INDEX IF NOT EXISTS idx_recall_messages_candidate_json 
ON public.recall_messages USING GIN (candidate_json);

-- Index for status queries (if status column exists)
-- Note: This will be created if status column exists from migration
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'recall_messages' AND column_name = 'status'
  ) THEN
    CREATE INDEX IF NOT EXISTS idx_recall_messages_status 
    ON public.recall_messages(thread_id, status, created_at DESC);
  END IF;
END $$;

-- Optimized function for fetching messages with pagination
CREATE OR REPLACE FUNCTION get_recall_messages_paginated(
  p_thread_id UUID,
  p_cursor TIMESTAMPTZ DEFAULT NULL,
  p_limit INT DEFAULT 50
)
RETURNS TABLE (
  id UUID,
  thread_id UUID,
  user_id UUID,
  role TEXT,
  message_type TEXT,
  text TEXT,
  raw_transcript TEXT,
  edited_transcript TEXT,
  media_path TEXT,
  candidate_json JSONB,
  sources_json JSONB,
  confidence NUMERIC,
  song_url TEXT,
  song_title TEXT,
  song_artist TEXT,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    m.id,
    m.thread_id,
    m.user_id,
    m.role,
    m.message_type,
    m.text,
    m.raw_transcript,
    m.edited_transcript,
    m.media_path,
    m.candidate_json,
    m.sources_json,
    m.confidence,
    m.song_url,
    m.song_title,
    m.song_artist,
    m.created_at
  FROM public.recall_messages m
  WHERE m.thread_id = p_thread_id
    AND (p_cursor IS NULL OR m.created_at > p_cursor)
  ORDER BY m.created_at ASC
  LIMIT p_limit;
END;
$$;

-- Batch insert function for recall_messages (for future use)
CREATE OR REPLACE FUNCTION insert_recall_messages_batch(
  p_messages JSONB[]
)
RETURNS UUID[]
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_message_ids UUID[] := ARRAY[]::UUID[];
  v_msg JSONB;
BEGIN
  FOREACH v_msg IN ARRAY p_messages
  LOOP
    INSERT INTO public.recall_messages (
      thread_id, user_id, role, message_type, text,
      raw_transcript, edited_transcript, media_path,
      candidate_json, sources_json, confidence,
      song_url, song_title, song_artist
    )
    VALUES (
      (v_msg->>'thread_id')::UUID,
      (v_msg->>'user_id')::UUID,
      v_msg->>'role',
      v_msg->>'message_type',
      v_msg->>'text',
      v_msg->>'raw_transcript',
      v_msg->>'edited_transcript',
      v_msg->>'media_path',
      COALESCE((v_msg->>'candidate_json')::JSONB, '{}'::JSONB),
      COALESCE((v_msg->>'sources_json')::JSONB, '[]'::JSONB),
      (v_msg->>'confidence')::NUMERIC,
      v_msg->>'song_url',
      v_msg->>'song_title',
      v_msg->>'song_artist'
    )
    RETURNING id INTO v_message_ids[array_length(v_message_ids, 1) + 1];
  END LOOP;
  
  RETURN v_message_ids;
END;
$$;

-- Add comments for documentation
COMMENT ON INDEX idx_recall_messages_thread_created IS 'Composite index for efficient message pagination by thread';
COMMENT ON INDEX idx_recall_threads_user_last_message IS 'Index for fetching user threads ordered by last message';
COMMENT ON INDEX idx_recall_threads_active IS 'Partial index for active threads only (excludes deleted/archived)';
COMMENT ON INDEX idx_recall_messages_type IS 'Index for filtering messages by type within a thread';
COMMENT ON FUNCTION get_recall_messages_paginated IS 'Optimized pagination function for recall messages';
COMMENT ON FUNCTION insert_recall_messages_batch IS 'Batch insert function for multiple recall messages (for future scalability)';






