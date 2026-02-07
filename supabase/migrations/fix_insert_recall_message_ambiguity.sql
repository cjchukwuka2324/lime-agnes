-- Migration: Fix insert_recall_message function ambiguity
-- This drops old function versions and creates a new one with p_raw_transcript and p_edited_transcript

-- Drop all existing versions of the function to avoid ambiguity
DROP FUNCTION IF EXISTS public.insert_recall_message(UUID, UUID, TEXT, TEXT, TEXT, TEXT, JSONB, JSONB, NUMERIC, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.insert_recall_message(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, JSONB, NUMERIC, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.insert_recall_message(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, JSONB, NUMERIC, TEXT, TEXT, TEXT);

-- Ensure columns exist
ALTER TABLE public.recall_messages 
ADD COLUMN IF NOT EXISTS raw_transcript TEXT;

ALTER TABLE public.recall_messages 
ADD COLUMN IF NOT EXISTS edited_transcript TEXT;

-- Recreate the function with the correct signature
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






