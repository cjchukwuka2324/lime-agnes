-- ============================================
-- Recall Schema Fix
-- ============================================
-- This script checks and fixes any issues with the recall schema
-- Run this if you get "column artist does not exist" errors
-- ============================================

-- First, check if tables exist and have correct columns
DO $$
BEGIN
  -- Check if recall_candidates table exists and has artist column
  IF EXISTS (
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'public' 
    AND table_name = 'recall_candidates'
  ) THEN
    -- Check if artist column exists
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns 
      WHERE table_schema = 'public' 
      AND table_name = 'recall_candidates' 
      AND column_name = 'artist'
    ) THEN
      -- Add artist column if missing
      ALTER TABLE public.recall_candidates 
      ADD COLUMN artist TEXT NOT NULL DEFAULT '';
      
      RAISE NOTICE 'Added missing artist column to recall_candidates table';
    END IF;
  END IF;
  
  -- Check if recall_confirmations table exists and has confirmed_artist column
  IF EXISTS (
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'public' 
    AND table_name = 'recall_confirmations'
  ) THEN
    -- Check if confirmed_artist column exists
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns 
      WHERE table_schema = 'public' 
      AND table_name = 'recall_confirmations' 
      AND column_name = 'confirmed_artist'
    ) THEN
      -- Add confirmed_artist column if missing
      ALTER TABLE public.recall_confirmations 
      ADD COLUMN confirmed_artist TEXT NOT NULL DEFAULT '';
      
      RAISE NOTICE 'Added missing confirmed_artist column to recall_confirmations table';
    END IF;
  END IF;
  
  -- Check if tracks table exists and has required columns
  IF EXISTS (
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'public' 
    AND table_name = 'tracks'
  ) THEN
    -- Check if artist column exists
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns 
      WHERE table_schema = 'public' 
      AND table_name = 'tracks' 
      AND column_name = 'artist'
    ) THEN
      -- Add artist column if missing
      ALTER TABLE public.tracks 
      ADD COLUMN artist TEXT NOT NULL DEFAULT '';
      
      RAISE NOTICE 'Added missing artist column to tracks table';
    END IF;
    
    -- Check if created_by column exists
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns 
      WHERE table_schema = 'public' 
      AND table_name = 'tracks' 
      AND column_name = 'created_by'
    ) THEN
      -- Add created_by column if missing
      ALTER TABLE public.tracks 
      ADD COLUMN created_by UUID REFERENCES auth.users(id);
      
      RAISE NOTICE 'Added missing created_by column to tracks table';
    END IF;
  END IF;
END $$;

-- Now run the full schema if tables don't exist
-- This is idempotent (safe to run multiple times)

-- ============================================
-- 1. Create recall_input_type enum
-- ============================================

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'recall_input_type') THEN
    CREATE TYPE recall_input_type AS ENUM ('text', 'voice', 'image');
  END IF;
END $$;

-- ============================================
-- 2. Create tracks table (optional internal catalog)
-- ============================================

CREATE TABLE IF NOT EXISTS public.tracks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  artist TEXT NOT NULL,
  album TEXT,
  year INT,
  tags TEXT[] DEFAULT '{}',
  vibe_description TEXT,
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Ensure artist and created_by columns exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'tracks' 
    AND column_name = 'artist'
  ) THEN
    ALTER TABLE public.tracks ADD COLUMN artist TEXT NOT NULL DEFAULT '';
  END IF;
  
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'tracks' 
    AND column_name = 'created_by'
  ) THEN
    ALTER TABLE public.tracks ADD COLUMN created_by UUID REFERENCES auth.users(id);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_tracks_title_artist ON public.tracks(title, artist);
CREATE INDEX IF NOT EXISTS idx_tracks_created_by ON public.tracks(created_by);

-- ============================================
-- 3. Create recall_events table
-- ============================================

CREATE TABLE IF NOT EXISTS public.recall_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  input_type recall_input_type NOT NULL,
  raw_text TEXT,
  media_path TEXT,
  transcript TEXT,
  status TEXT NOT NULL DEFAULT 'queued', -- queued|processing|done|needs_crowd|failed
  confidence NUMERIC,
  error_message TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_recall_events_user_id ON public.recall_events(user_id);
CREATE INDEX IF NOT EXISTS idx_recall_events_status ON public.recall_events(status);
CREATE INDEX IF NOT EXISTS idx_recall_events_created_at ON public.recall_events(created_at DESC);

-- ============================================
-- 4. Create recall_candidates table
-- ============================================

CREATE TABLE IF NOT EXISTS public.recall_candidates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recall_id UUID NOT NULL REFERENCES public.recall_events(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  artist TEXT NOT NULL,
  confidence NUMERIC NOT NULL,
  reason TEXT,
  source_urls TEXT[] DEFAULT '{}',
  highlight_snippet TEXT, -- short excerpt from web reasoning or lyric line
  rank INT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Ensure artist column exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'recall_candidates' 
    AND column_name = 'artist'
  ) THEN
    ALTER TABLE public.recall_candidates ADD COLUMN artist TEXT NOT NULL DEFAULT '';
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_recall_candidates_recall_id ON public.recall_candidates(recall_id);
CREATE INDEX IF NOT EXISTS idx_recall_candidates_rank ON public.recall_candidates(recall_id, rank);

-- ============================================
-- 5. Create recall_confirmations table
-- ============================================

CREATE TABLE IF NOT EXISTS public.recall_confirmations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recall_id UUID NOT NULL REFERENCES public.recall_events(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  confirmed_title TEXT NOT NULL,
  confirmed_artist TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Ensure confirmed_artist column exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'recall_confirmations' 
    AND column_name = 'confirmed_artist'
  ) THEN
    ALTER TABLE public.recall_confirmations ADD COLUMN confirmed_artist TEXT NOT NULL DEFAULT '';
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_recall_confirmations_recall_id ON public.recall_confirmations(recall_id);
CREATE INDEX IF NOT EXISTS idx_recall_confirmations_user_id ON public.recall_confirmations(user_id);

-- ============================================
-- 6. Create recall_crowd_posts table
-- ============================================

CREATE TABLE IF NOT EXISTS public.recall_crowd_posts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recall_id UUID NOT NULL REFERENCES public.recall_events(id) ON DELETE CASCADE,
  post_id UUID NOT NULL, -- references posts table id
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(recall_id, post_id)
);

CREATE INDEX IF NOT EXISTS idx_recall_crowd_posts_recall_id ON public.recall_crowd_posts(recall_id);
CREATE INDEX IF NOT EXISTS idx_recall_crowd_posts_post_id ON public.recall_crowd_posts(post_id);

-- ============================================
-- 7. Enable RLS on all tables
-- ============================================

ALTER TABLE public.tracks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recall_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recall_candidates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recall_confirmations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recall_crowd_posts ENABLE ROW LEVEL SECURITY;

-- ============================================
-- 8. RLS Policies (idempotent - safe to run multiple times)
-- ============================================

-- Tracks policies
DROP POLICY IF EXISTS "Authenticated users can view tracks" ON public.tracks;
CREATE POLICY "Authenticated users can view tracks" ON public.tracks
  FOR SELECT
  USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "Authenticated users can insert tracks" ON public.tracks;
CREATE POLICY "Authenticated users can insert tracks" ON public.tracks
  FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

-- Recall events policies
DROP POLICY IF EXISTS "Users can view their own recall events" ON public.recall_events;
CREATE POLICY "Users can view their own recall events" ON public.recall_events
  FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own recall events" ON public.recall_events;
CREATE POLICY "Users can insert their own recall events" ON public.recall_events
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own recall events" ON public.recall_events;
CREATE POLICY "Users can update their own recall events" ON public.recall_events
  FOR UPDATE
  USING (auth.uid() = user_id);

-- Recall candidates policies
DROP POLICY IF EXISTS "Users can view candidates for their own recalls" ON public.recall_candidates;
CREATE POLICY "Users can view candidates for their own recalls" ON public.recall_candidates
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.recall_events
      WHERE recall_events.id = recall_candidates.recall_id
      AND recall_events.user_id = auth.uid()
    )
  );

-- Recall confirmations policies
DROP POLICY IF EXISTS "Users can view their own confirmations" ON public.recall_confirmations;
CREATE POLICY "Users can view their own confirmations" ON public.recall_confirmations
  FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own confirmations" ON public.recall_confirmations;
CREATE POLICY "Users can insert their own confirmations" ON public.recall_confirmations
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Recall crowd posts policies
DROP POLICY IF EXISTS "Users can view crowd posts for their own recalls" ON public.recall_crowd_posts;
CREATE POLICY "Users can view crowd posts for their own recalls" ON public.recall_crowd_posts
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.recall_events
      WHERE recall_events.id = recall_crowd_posts.recall_id
      AND recall_events.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Users can insert crowd posts for their own recalls" ON public.recall_crowd_posts;
CREATE POLICY "Users can insert crowd posts for their own recalls" ON public.recall_crowd_posts
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.recall_events
      WHERE recall_events.id = recall_crowd_posts.recall_id
      AND recall_events.user_id = auth.uid()
    )
  );

-- ============================================
-- Verification Query
-- ============================================

-- Run this to verify all columns exist:
-- SELECT 
--   table_name, 
--   column_name 
-- FROM information_schema.columns 
-- WHERE table_schema = 'public' 
--   AND table_name IN ('recall_candidates', 'recall_confirmations', 'tracks')
--   AND column_name LIKE '%artist%'
-- ORDER BY table_name, column_name;
