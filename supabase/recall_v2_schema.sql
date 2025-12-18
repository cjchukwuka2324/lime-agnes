-- ============================================
-- Recall v2 Schema
-- ============================================
-- Production-grade schema for Recall v2 with job queue,
-- training system, and proper infrastructure
-- ============================================

-- ============================================
-- 1. Core Recall Tables
-- ============================================

-- Main recalls table (replaces direct thread processing)
CREATE TABLE IF NOT EXISTS public.recalls (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  input_type TEXT NOT NULL CHECK (input_type IN ('text', 'voice', 'image', 'background', 'hum')),
  query_text TEXT,
  image_path TEXT,
  audio_path TEXT,
  status TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'processing', 'done', 'failed')),
  request_id TEXT UNIQUE, -- For idempotency
  top_confidence NUMERIC,
  top_title TEXT,
  top_artist TEXT,
  top_url TEXT,
  result_json JSONB DEFAULT '{}'::jsonb,
  error_message TEXT,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_recalls_user_id ON public.recalls(user_id);
CREATE INDEX IF NOT EXISTS idx_recalls_status ON public.recalls(status);
CREATE INDEX IF NOT EXISTS idx_recalls_request_id ON public.recalls(request_id);
CREATE INDEX IF NOT EXISTS idx_recalls_created_at ON public.recalls(created_at DESC);

-- Sources table for citations
CREATE TABLE IF NOT EXISTS public.recall_sources (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recall_id UUID NOT NULL REFERENCES public.recalls(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  url TEXT NOT NULL,
  snippet TEXT,
  publisher TEXT,
  verified BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_recall_sources_recall_id ON public.recall_sources(recall_id);
CREATE INDEX IF NOT EXISTS idx_recall_sources_url ON public.recall_sources(url);

-- Candidates table for search results
CREATE TABLE IF NOT EXISTS public.recall_candidates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recall_id UUID NOT NULL REFERENCES public.recalls(id) ON DELETE CASCADE,
  rank INTEGER NOT NULL,
  title TEXT NOT NULL,
  artist TEXT NOT NULL,
  confidence NUMERIC NOT NULL,
  url TEXT,
  evidence TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(recall_id, rank)
);

CREATE INDEX IF NOT EXISTS idx_recall_candidates_recall_id ON public.recall_candidates(recall_id);
CREATE INDEX IF NOT EXISTS idx_recall_candidates_rank ON public.recall_candidates(recall_id, rank);

-- Saved recalls table
CREATE TABLE IF NOT EXISTS public.saved_recalls (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  recall_id UUID NOT NULL REFERENCES public.recalls(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, recall_id)
);

CREATE INDEX IF NOT EXISTS idx_saved_recalls_user_id ON public.saved_recalls(user_id);
CREATE INDEX IF NOT EXISTS idx_saved_recalls_recall_id ON public.saved_recalls(recall_id);

-- ============================================
-- 2. Job Queue Infrastructure
-- ============================================

CREATE TABLE IF NOT EXISTS public.recall_jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recall_id UUID NOT NULL REFERENCES public.recalls(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  job_type TEXT NOT NULL CHECK (job_type IN ('identify', 'knowledge', 'recommend')),
  status TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'processing', 'done', 'failed', 'retrying')),
  retry_count INTEGER DEFAULT 0,
  max_retries INTEGER DEFAULT 3,
  scheduled_at TIMESTAMPTZ DEFAULT NOW(),
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  error_message TEXT,
  request_id TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_recall_jobs_status ON public.recall_jobs(status, scheduled_at);
CREATE INDEX IF NOT EXISTS idx_recall_jobs_recall_id ON public.recall_jobs(recall_id);
CREATE INDEX IF NOT EXISTS idx_recall_jobs_user_id ON public.recall_jobs(user_id);
CREATE INDEX IF NOT EXISTS idx_recall_jobs_request_id ON public.recall_jobs(request_id);

-- ============================================
-- 3. Training System Tables
-- ============================================

-- User feedback table
CREATE TABLE IF NOT EXISTS public.recall_feedback (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recall_id UUID NOT NULL REFERENCES public.recalls(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  message_id UUID, -- References recall_messages.id if applicable
  feedback_type TEXT NOT NULL CHECK (feedback_type IN ('confirm', 'reject', 'correct', 'rate')),
  rating INTEGER CHECK (rating >= 1 AND rating <= 5), -- For 'rate' type
  correction_text TEXT, -- For 'correct' type
  context_json JSONB DEFAULT '{}'::jsonb, -- Store query, candidates shown, etc.
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_recall_feedback_user_id ON public.recall_feedback(user_id);
CREATE INDEX IF NOT EXISTS idx_recall_feedback_recall_id ON public.recall_feedback(recall_id);
CREATE INDEX IF NOT EXISTS idx_recall_feedback_type ON public.recall_feedback(feedback_type);
CREATE INDEX IF NOT EXISTS idx_recall_feedback_created_at ON public.recall_feedback(created_at DESC);

-- User preferences table
CREATE TABLE IF NOT EXISTS public.recall_user_preferences (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  preference_type TEXT NOT NULL CHECK (preference_type IN ('genre_preference', 'artist_preference', 'search_pattern', 'question_style')),
  preference_data JSONB NOT NULL DEFAULT '{}'::jsonb,
  confidence_score NUMERIC DEFAULT 0.0 CHECK (confidence_score >= 0.0 AND confidence_score <= 1.0),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, preference_type)
);

CREATE INDEX IF NOT EXISTS idx_recall_user_preferences_user_id ON public.recall_user_preferences(user_id);
CREATE INDEX IF NOT EXISTS idx_recall_user_preferences_type ON public.recall_user_preferences(user_id, preference_type);

-- Learning data table
CREATE TABLE IF NOT EXISTS public.recall_learning_data (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  query_pattern TEXT NOT NULL,
  successful_candidates JSONB DEFAULT '[]'::jsonb,
  rejected_candidates JSONB DEFAULT '[]'::jsonb,
  user_corrections JSONB DEFAULT '[]'::jsonb,
  context_features JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_recall_learning_data_user_id ON public.recall_learning_data(user_id);
CREATE INDEX IF NOT EXISTS idx_recall_learning_data_created_at ON public.recall_learning_data(created_at DESC);

-- ============================================
-- 4. Observability Tables
-- ============================================

-- Logs table for structured logging
CREATE TABLE IF NOT EXISTS public.recall_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id TEXT NOT NULL,
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  recall_id UUID REFERENCES public.recalls(id) ON DELETE SET NULL,
  operation TEXT NOT NULL,
  duration_ms INTEGER,
  status TEXT NOT NULL,
  error_message TEXT,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_recall_logs_request_id ON public.recall_logs(request_id);
CREATE INDEX IF NOT EXISTS idx_recall_logs_user_id ON public.recall_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_recall_logs_recall_id ON public.recall_logs(recall_id);
CREATE INDEX IF NOT EXISTS idx_recall_logs_created_at ON public.recall_logs(created_at DESC);

-- ============================================
-- 5. Enable RLS on all tables
-- ============================================

ALTER TABLE public.recalls ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recall_sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recall_candidates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.saved_recalls ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recall_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recall_feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recall_user_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recall_learning_data ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recall_logs ENABLE ROW LEVEL SECURITY;

-- ============================================
-- 6. RLS Policies for recalls
-- ============================================

-- Users can view their own recalls
DROP POLICY IF EXISTS "Users can view their own recalls" ON public.recalls;
CREATE POLICY "Users can view their own recalls" ON public.recalls
  FOR SELECT
  USING (auth.uid() = user_id);

-- Users can insert their own recalls
DROP POLICY IF EXISTS "Users can insert their own recalls" ON public.recalls;
CREATE POLICY "Users can insert their own recalls" ON public.recalls
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Users can update their own recalls
DROP POLICY IF EXISTS "Users can update their own recalls" ON public.recalls;
CREATE POLICY "Users can update their own recalls" ON public.recalls
  FOR UPDATE
  USING (auth.uid() = user_id);

-- Users can delete their own recalls
DROP POLICY IF EXISTS "Users can delete their own recalls" ON public.recalls;
CREATE POLICY "Users can delete their own recalls" ON public.recalls
  FOR DELETE
  USING (auth.uid() = user_id);

-- ============================================
-- 7. RLS Policies for recall_sources
-- ============================================

DROP POLICY IF EXISTS "Users can view sources for their recalls" ON public.recall_sources;
CREATE POLICY "Users can view sources for their recalls" ON public.recall_sources
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.recalls
      WHERE recalls.id = recall_sources.recall_id
      AND recalls.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Service role can manage sources" ON public.recall_sources;
CREATE POLICY "Service role can manage sources" ON public.recall_sources
  FOR ALL
  USING (auth.jwt() ->> 'role' = 'service_role');

-- ============================================
-- 8. RLS Policies for recall_candidates
-- ============================================

DROP POLICY IF EXISTS "Users can view candidates for their recalls" ON public.recall_candidates;
CREATE POLICY "Users can view candidates for their recalls" ON public.recall_candidates
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.recalls
      WHERE recalls.id = recall_candidates.recall_id
      AND recalls.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Service role can manage candidates" ON public.recall_candidates;
CREATE POLICY "Service role can manage candidates" ON public.recall_candidates
  FOR ALL
  USING (auth.jwt() ->> 'role' = 'service_role');

-- ============================================
-- 9. RLS Policies for saved_recalls
-- ============================================

DROP POLICY IF EXISTS "Users can manage their saved recalls" ON public.saved_recalls;
CREATE POLICY "Users can manage their saved recalls" ON public.saved_recalls
  FOR ALL
  USING (auth.uid() = user_id);

-- ============================================
-- 10. RLS Policies for recall_jobs
-- ============================================

DROP POLICY IF EXISTS "Users can view their own jobs" ON public.recall_jobs;
CREATE POLICY "Users can view their own jobs" ON public.recall_jobs
  FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Service role can manage jobs" ON public.recall_jobs;
CREATE POLICY "Service role can manage jobs" ON public.recall_jobs
  FOR ALL
  USING (auth.jwt() ->> 'role' = 'service_role');

-- ============================================
-- 11. RLS Policies for recall_feedback
-- ============================================

DROP POLICY IF EXISTS "Users can manage their own feedback" ON public.recall_feedback;
CREATE POLICY "Users can manage their own feedback" ON public.recall_feedback
  FOR ALL
  USING (auth.uid() = user_id);

-- ============================================
-- 12. RLS Policies for recall_user_preferences
-- ============================================

DROP POLICY IF EXISTS "Users can manage their own preferences" ON public.recall_user_preferences;
CREATE POLICY "Users can manage their own preferences" ON public.recall_user_preferences
  FOR ALL
  USING (auth.uid() = user_id);

-- ============================================
-- 13. RLS Policies for recall_learning_data
-- ============================================

DROP POLICY IF EXISTS "Users can view their own learning data" ON public.recall_learning_data;
CREATE POLICY "Users can view their own learning data" ON public.recall_learning_data
  FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Service role can manage learning data" ON public.recall_learning_data;
CREATE POLICY "Service role can manage learning data" ON public.recall_learning_data
  FOR ALL
  USING (auth.jwt() ->> 'role' = 'service_role');

-- ============================================
-- 14. RLS Policies for recall_logs
-- ============================================

DROP POLICY IF EXISTS "Users can view their own logs" ON public.recall_logs;
CREATE POLICY "Users can view their own logs" ON public.recall_logs
  FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Service role can manage logs" ON public.recall_logs;
CREATE POLICY "Service role can manage logs" ON public.recall_logs
  FOR ALL
  USING (auth.jwt() ->> 'role' = 'service_role');

-- ============================================
-- 15. Functions and Triggers
-- ============================================

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for recalls table
DROP TRIGGER IF EXISTS update_recalls_updated_at ON public.recalls;
CREATE TRIGGER update_recalls_updated_at
  BEFORE UPDATE ON public.recalls
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Trigger for recall_user_preferences table
DROP TRIGGER IF EXISTS update_preferences_updated_at ON public.recall_user_preferences;
CREATE TRIGGER update_preferences_updated_at
  BEFORE UPDATE ON public.recall_user_preferences
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- 16. Helper Functions
-- ============================================

-- Function to generate request_id
CREATE OR REPLACE FUNCTION generate_request_id()
RETURNS TEXT AS $$
BEGIN
  RETURN 'req_' || encode(gen_random_bytes(16), 'hex');
END;
$$ LANGUAGE plpgsql;

-- Function to check if recall is already processing (for idempotency)
CREATE OR REPLACE FUNCTION is_recall_processing(p_recall_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.recalls
    WHERE id = p_recall_id
    AND status IN ('queued', 'processing')
  );
END;
$$ LANGUAGE plpgsql;




