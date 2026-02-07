-- ============================================
-- Recall Conversational Schema (V1)
-- ============================================
-- Creates thread-based conversational recall system
-- Migrates existing recall_events to new structure
-- ============================================

-- ============================================
-- 1. Create recall_threads table
-- ============================================

CREATE TABLE IF NOT EXISTS public.recall_threads (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  last_message_at TIMESTAMPTZ DEFAULT NOW(),
  title TEXT
);

CREATE INDEX IF NOT EXISTS idx_recall_threads_user_id ON public.recall_threads(user_id);
CREATE INDEX IF NOT EXISTS idx_recall_threads_last_message_at ON public.recall_threads(last_message_at DESC);

-- ============================================
-- 2. Create recall_messages table
-- ============================================

CREATE TABLE IF NOT EXISTS public.recall_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  thread_id UUID NOT NULL REFERENCES public.recall_threads(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  role TEXT NOT NULL CHECK (role IN ('user', 'assistant', 'system')),
  message_type TEXT NOT NULL CHECK (message_type IN ('text', 'voice', 'image', 'candidate', 'status', 'follow_up', 'answer')),
  text TEXT,
  raw_transcript TEXT,
  edited_transcript TEXT,
  media_path TEXT,
  candidate_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  sources_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  confidence NUMERIC,
  song_url TEXT,
  song_title TEXT,
  song_artist TEXT
);

CREATE INDEX IF NOT EXISTS idx_recall_messages_thread_id ON public.recall_messages(thread_id);
CREATE INDEX IF NOT EXISTS idx_recall_messages_user_id ON public.recall_messages(user_id);
CREATE INDEX IF NOT EXISTS idx_recall_messages_created_at ON public.recall_messages(created_at);

-- ============================================
-- 3. Create recall_stash table
-- ============================================

CREATE TABLE IF NOT EXISTS public.recall_stash (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  thread_id UUID NOT NULL REFERENCES public.recall_threads(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  top_song_title TEXT,
  top_song_artist TEXT,
  top_confidence NUMERIC,
  top_song_url TEXT,
  UNIQUE(user_id, thread_id)
);

CREATE INDEX IF NOT EXISTS idx_recall_stash_user_id ON public.recall_stash(user_id);
CREATE INDEX IF NOT EXISTS idx_recall_stash_thread_id ON public.recall_stash(thread_id);
CREATE INDEX IF NOT EXISTS idx_recall_stash_created_at ON public.recall_stash(created_at DESC);

-- ============================================
-- 4. Enable RLS on all tables
-- ============================================

ALTER TABLE public.recall_threads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recall_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recall_stash ENABLE ROW LEVEL SECURITY;

-- ============================================
-- 5. RLS Policies for recall_threads
-- ============================================

DROP POLICY IF EXISTS "Users can view their own threads" ON public.recall_threads;
CREATE POLICY "Users can view their own threads" ON public.recall_threads
  FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own threads" ON public.recall_threads;
CREATE POLICY "Users can insert their own threads" ON public.recall_threads
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own threads" ON public.recall_threads;
CREATE POLICY "Users can update their own threads" ON public.recall_threads
  FOR UPDATE
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete their own threads" ON public.recall_threads;
CREATE POLICY "Users can delete their own threads" ON public.recall_threads
  FOR DELETE
  USING (auth.uid() = user_id);

-- ============================================
-- 6. RLS Policies for recall_messages
-- ============================================

DROP POLICY IF EXISTS "Users can view their own messages" ON public.recall_messages;
CREATE POLICY "Users can view their own messages" ON public.recall_messages
  FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own messages" ON public.recall_messages;
-- Simplified policy: Just check user_id matches
-- The foreign key constraint ensures thread exists
-- We rely on the fact that threads are user-scoped
CREATE POLICY "Users can insert their own messages" ON public.recall_messages
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own messages" ON public.recall_messages;
CREATE POLICY "Users can update their own messages" ON public.recall_messages
  FOR UPDATE
  USING (auth.uid() = user_id);

-- ============================================
-- Helper function to insert messages (bypasses RLS for FK check)
-- ============================================

-- Drop old version if it exists (to avoid ambiguity)
DROP FUNCTION IF EXISTS public.insert_recall_message(UUID, UUID, TEXT, TEXT, TEXT, TEXT, JSONB, JSONB, NUMERIC, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.insert_recall_message(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, JSONB, NUMERIC, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.insert_recall_message(
  p_thread_id UUID,
  p_user_id UUID,
  p_role TEXT,
  p_message_type TEXT,
  p_text TEXT DEFAULT NULL,
  p_raw_transcript TEXT DEFAULT NULL,
  p_edited_transcript TEXT DEFAULT NULL,
  p_media_path TEXT DEFAULT NULL,
  p_candidate_json JSONB DEFAULT '{}'::jsonb,
  p_sources_json JSONB DEFAULT '[]'::jsonb,
  p_confidence NUMERIC DEFAULT NULL,
  p_song_url TEXT DEFAULT NULL,
  p_song_title TEXT DEFAULT NULL,
  p_song_artist TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_message_id UUID;
  v_current_user_id UUID;
BEGIN
  -- Get current user
  v_current_user_id := auth.uid();
  
  -- Verify user is authenticated
  IF v_current_user_id IS NULL THEN
    RAISE EXCEPTION 'User must be authenticated';
  END IF;
  
  -- Verify user_id matches authenticated user
  IF p_user_id != v_current_user_id THEN
    RAISE EXCEPTION 'user_id must match authenticated user';
  END IF;
  
  -- Verify thread exists and belongs to user (bypasses RLS due to SECURITY DEFINER)
  IF NOT EXISTS (
    SELECT 1 FROM public.recall_threads
    WHERE id = p_thread_id AND user_id = v_current_user_id
  ) THEN
    RAISE EXCEPTION 'Thread not found or access denied';
  END IF;
  
  -- Insert message (bypasses RLS due to SECURITY DEFINER)
  INSERT INTO public.recall_messages (
    thread_id,
    user_id,
    role,
    message_type,
    text,
    raw_transcript,
    edited_transcript,
    media_path,
    candidate_json,
    sources_json,
    confidence,
    song_url,
    song_title,
    song_artist
  ) VALUES (
    p_thread_id,
    p_user_id,
    p_role,
    p_message_type,
    p_text,
    p_raw_transcript,
    p_edited_transcript,
    p_media_path,
    COALESCE(p_candidate_json, '{}'::jsonb),
    COALESCE(p_sources_json, '[]'::jsonb),
    p_confidence,
    p_song_url,
    p_song_title,
    p_song_artist
  )
  RETURNING id INTO v_message_id;
  
  -- Update thread last_message_at
  UPDATE public.recall_threads
  SET last_message_at = NOW()
  WHERE id = p_thread_id;
  
  RETURN v_message_id;
END;
$$;

-- ============================================
-- 7. RLS Policies for recall_stash
-- ============================================

DROP POLICY IF EXISTS "Users can view their own stash" ON public.recall_stash;
CREATE POLICY "Users can view their own stash" ON public.recall_stash
  FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own stash" ON public.recall_stash;
CREATE POLICY "Users can insert their own stash" ON public.recall_stash
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own stash" ON public.recall_stash;
CREATE POLICY "Users can update their own stash" ON public.recall_stash
  FOR UPDATE
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete their own stash" ON public.recall_stash;
CREATE POLICY "Users can delete their own stash" ON public.recall_stash
  FOR DELETE
  USING (auth.uid() = user_id);

-- ============================================
-- 8. Storage Buckets Setup
-- ============================================
-- Note: These need to be created via Supabase Dashboard or CLI
-- Buckets: recall-images, recall-audio (both private)
-- Storage policies will be set via dashboard or separate migration

-- Storage Policies for recall-images bucket
-- Note: These policies assume the bucket exists. Create the bucket first via Dashboard or CLI:
-- supabase storage create recall-images --public false
-- supabase storage create recall-audio --public false

-- Policy: Users can upload their own images
DROP POLICY IF EXISTS "Users can upload their own images" ON storage.objects;
CREATE POLICY "Users can upload their own images" ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'recall-images' AND
    (storage.foldername(name))[1] = auth.uid()::text
  );

-- Policy: Users can read their own images
DROP POLICY IF EXISTS "Users can read their own images" ON storage.objects;
CREATE POLICY "Users can read their own images" ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'recall-images' AND
    (storage.foldername(name))[1] = auth.uid()::text
  );

-- Policy: Users can delete their own images
DROP POLICY IF EXISTS "Users can delete their own images" ON storage.objects;
CREATE POLICY "Users can delete their own images" ON storage.objects
  FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'recall-images' AND
    (storage.foldername(name))[1] = auth.uid()::text
  );

-- Storage Policies for recall-audio bucket
-- Policy: Users can upload their own audio
DROP POLICY IF EXISTS "Users can upload their own audio" ON storage.objects;
CREATE POLICY "Users can upload their own audio" ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'recall-audio' AND
    (storage.foldername(name))[1] = auth.uid()::text
  );

-- Policy: Users can read their own audio
DROP POLICY IF EXISTS "Users can read their own audio" ON storage.objects;
CREATE POLICY "Users can read their own audio" ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'recall-audio' AND
    (storage.foldername(name))[1] = auth.uid()::text
  );

-- Policy: Users can delete their own audio
DROP POLICY IF EXISTS "Users can delete their own audio" ON storage.objects;
CREATE POLICY "Users can delete their own audio" ON storage.objects
  FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'recall-audio' AND
    (storage.foldername(name))[1] = auth.uid()::text
  );

-- ============================================
-- 9. Migration: Convert recall_events to threads/messages
-- ============================================

DO $$
DECLARE
  event_record RECORD;
  new_thread_id UUID;
  new_message_id UUID;
  top_candidate RECORD;
BEGIN
  -- Loop through all existing recall_events
  FOR event_record IN 
    SELECT * FROM public.recall_events
    ORDER BY created_at
  LOOP
    -- Create a thread for this event
    INSERT INTO public.recall_threads (id, user_id, created_at, last_message_at)
    VALUES (gen_random_uuid(), event_record.user_id, event_record.created_at, event_record.created_at)
    RETURNING id INTO new_thread_id;
    
    -- Create user message from the event
    INSERT INTO public.recall_messages (
      thread_id,
      user_id,
      created_at,
      role,
      message_type,
      text,
      media_path
    ) VALUES (
      new_thread_id,
      event_record.user_id,
      event_record.created_at,
      'user',
      event_record.input_type::text,
      COALESCE(event_record.raw_text, event_record.transcript),
      event_record.media_path
    )
    RETURNING id INTO new_message_id;
    
    -- If there are candidates, create assistant candidate message
    SELECT * INTO top_candidate
    FROM public.recall_candidates
    WHERE recall_id = event_record.id
    ORDER BY rank ASC
    LIMIT 1;
    
    IF FOUND THEN
      INSERT INTO public.recall_messages (
        thread_id,
        user_id,
        created_at,
        role,
        message_type,
        candidate_json,
        sources_json,
        confidence,
        song_title,
        song_artist,
        song_url
      ) VALUES (
        new_thread_id,
        event_record.user_id,
        event_record.created_at + INTERVAL '1 second',
        'assistant',
        'candidate',
        jsonb_build_object(
          'title', top_candidate.title,
          'artist', top_candidate.artist,
          'confidence', top_candidate.confidence,
          'reason', top_candidate.reason,
          'lyric_snippet', top_candidate.highlight_snippet
        ),
        COALESCE(
          (SELECT jsonb_agg(jsonb_build_object('url', unnest))
           FROM unnest(top_candidate.source_urls)),
          '[]'::jsonb
        ),
        top_candidate.confidence,
        top_candidate.title,
        top_candidate.artist,
        NULL -- song_url not in old schema
      );
      
      -- Create stash entry
      INSERT INTO public.recall_stash (
        user_id,
        thread_id,
        created_at,
        top_song_title,
        top_song_artist,
        top_confidence,
        top_song_url
      ) VALUES (
        event_record.user_id,
        new_thread_id,
        event_record.created_at,
        top_candidate.title,
        top_candidate.artist,
        top_candidate.confidence,
        NULL
      )
      ON CONFLICT (user_id, thread_id) DO NOTHING;
    END IF;
    
    -- Update thread last_message_at
    UPDATE public.recall_threads
    SET last_message_at = event_record.created_at
    WHERE id = new_thread_id;
  END LOOP;
END $$;

-- ============================================
-- 10. Comments
-- ============================================

COMMENT ON TABLE public.recall_threads IS 'Conversational threads for recall - one per conversation';
COMMENT ON TABLE public.recall_messages IS 'All messages in a recall thread (user, assistant, system)';
COMMENT ON TABLE public.recall_stash IS 'Quick access to top results per thread for history view';

