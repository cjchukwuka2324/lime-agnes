-- Migration: Add raw_transcript and edited_transcript columns to recall_messages table
-- This stores the original transcription from SFSpeechRecognizer before user edits
-- and the user-edited version if they make changes

-- Add raw_transcript column
ALTER TABLE public.recall_messages 
ADD COLUMN IF NOT EXISTS raw_transcript TEXT;

-- Add edited_transcript column
ALTER TABLE public.recall_messages 
ADD COLUMN IF NOT EXISTS edited_transcript TEXT;

-- Add comments explaining the columns
COMMENT ON COLUMN public.recall_messages.raw_transcript IS 'Original transcription from on-device speech recognition (SFSpeechRecognizer) before user edits.';
COMMENT ON COLUMN public.recall_messages.edited_transcript IS 'User-edited version of the transcript. If present, this is the final transcript used for processing.';

-- Create indexes for queries that might filter by transcripts
CREATE INDEX IF NOT EXISTS idx_recall_messages_raw_transcript ON public.recall_messages(raw_transcript) WHERE raw_transcript IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_recall_messages_edited_transcript ON public.recall_messages(edited_transcript) WHERE edited_transcript IS NOT NULL;

