-- ============================================
-- Recall Feature Schema
-- ============================================
-- Creates tables and RLS policies for the Recall feature
-- Recall allows users to find songs from memory using text, voice, or images
-- ============================================

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

CREATE INDEX IF NOT EXISTS idx_recall_confirmations_recall_id ON public.recall_confirmations(recall_id);
CREATE INDEX IF NOT EXISTS idx_recall_confirmations_user_id ON public.recall_confirmations(user_id);

-- ============================================
-- 6. Create recall_crowd_posts table (links recall to GreenRoom post)
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
-- 8. RLS Policies for tracks
-- ============================================

DROP POLICY IF EXISTS "Authenticated users can view tracks" ON public.tracks;
CREATE POLICY "Authenticated users can view tracks" ON public.tracks
  FOR SELECT
  USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "Authenticated users can insert tracks" ON public.tracks;
CREATE POLICY "Authenticated users can insert tracks" ON public.tracks
  FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

-- ============================================
-- 9. RLS Policies for recall_events
-- ============================================

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

-- ============================================
-- 10. RLS Policies for recall_candidates
-- ============================================

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

-- Note: Insert/update handled by Edge Functions with service role

-- ============================================
-- 11. RLS Policies for recall_confirmations
-- ============================================

DROP POLICY IF EXISTS "Users can view their own confirmations" ON public.recall_confirmations;
CREATE POLICY "Users can view their own confirmations" ON public.recall_confirmations
  FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own confirmations" ON public.recall_confirmations;
CREATE POLICY "Users can insert their own confirmations" ON public.recall_confirmations
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- ============================================
-- 12. RLS Policies for recall_crowd_posts
-- ============================================

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
-- 13. Comments
-- ============================================

COMMENT ON TABLE public.tracks IS 'Internal catalog of tracks (optional, for future use)';
COMMENT ON TABLE public.recall_events IS 'Main table for recall requests (text, voice, or image input)';
COMMENT ON TABLE public.recall_candidates IS 'Web-discovered song candidates for each recall event';
COMMENT ON TABLE public.recall_confirmations IS 'User confirmations of correct song matches';
COMMENT ON TABLE public.recall_crowd_posts IS 'Links recall events to GreenRoom posts when asking the crowd for help';

