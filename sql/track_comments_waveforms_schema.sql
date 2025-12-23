-- ============================================================================
-- Track Comments and Waveforms Schema
-- ============================================================================
-- This migration creates tables for SoundCloud-style timestamped comments
-- and pre-computed waveform data for studio session tracks.
-- ============================================================================

-- ============================================================================
-- Table: ss_track_comments
-- ============================================================================
-- Stores timestamped comments on studio session tracks.
-- Users can add comments at specific points in the audio timeline.
-- ============================================================================

CREATE TABLE IF NOT EXISTS ss_track_comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    track_id UUID NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    timestamp DOUBLE PRECISION NOT NULL CHECK (timestamp >= 0),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_ss_track_comments_track_id ON ss_track_comments(track_id);
CREATE INDEX IF NOT EXISTS idx_ss_track_comments_timestamp ON ss_track_comments(track_id, timestamp);
CREATE INDEX IF NOT EXISTS idx_ss_track_comments_user_id ON ss_track_comments(user_id);
CREATE INDEX IF NOT EXISTS idx_ss_track_comments_created_at ON ss_track_comments(created_at DESC);

-- ============================================================================
-- Table: track_waveforms
-- ============================================================================
-- Stores pre-computed waveform data for tracks to enable fast visualization.
-- Waveform data is generated once and cached for performance.
-- ============================================================================

CREATE TABLE IF NOT EXISTS track_waveforms (
    track_id UUID PRIMARY KEY REFERENCES tracks(id) ON DELETE CASCADE,
    samples JSONB NOT NULL, -- Array of normalized amplitude values (0-1)
    sample_rate INTEGER NOT NULL, -- Samples per second
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for waveform lookups (primary key already indexed)
-- Additional index on updated_at for cache management
CREATE INDEX IF NOT EXISTS idx_track_waveforms_updated_at ON track_waveforms(updated_at);

-- ============================================================================
-- RLS Policies: ss_track_comments
-- ============================================================================

ALTER TABLE ss_track_comments ENABLE ROW LEVEL SECURITY;

-- Policy: Anyone authenticated can read all comments
CREATE POLICY "Anyone can read track comments"
    ON ss_track_comments
    FOR SELECT
    TO authenticated
    USING (true);

-- Policy: Authenticated users can create comments
CREATE POLICY "Authenticated users can create comments"
    ON ss_track_comments
    FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

-- Policy: Users can only delete their own comments
CREATE POLICY "Users can delete own comments"
    ON ss_track_comments
    FOR DELETE
    TO authenticated
    USING (auth.uid() = user_id);

-- Policy: Users can only update their own comments
CREATE POLICY "Users can update own comments"
    ON ss_track_comments
    FOR UPDATE
    TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- ============================================================================
-- RLS Policies: track_waveforms
-- ============================================================================

ALTER TABLE track_waveforms ENABLE ROW LEVEL SECURITY;

-- Policy: Anyone authenticated can read waveforms (read-only)
CREATE POLICY "Anyone can read waveforms"
    ON track_waveforms
    FOR SELECT
    TO authenticated
    USING (true);

-- Policy: Service role can insert/update waveforms (for waveform generation)
-- Note: In production, you may want to use a service account or function
CREATE POLICY "Service can manage waveforms"
    ON track_waveforms
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- ============================================================================
-- Function: Update updated_at timestamp for waveforms
-- ============================================================================

CREATE OR REPLACE FUNCTION update_track_waveforms_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER track_waveforms_updated_at
    BEFORE UPDATE ON track_waveforms
    FOR EACH ROW
    EXECUTE FUNCTION update_track_waveforms_updated_at();

-- ============================================================================
-- Comments
-- ============================================================================

COMMENT ON TABLE ss_track_comments IS 'Timestamped comments on studio session tracks';
COMMENT ON TABLE track_waveforms IS 'Pre-computed waveform visualization data for tracks';
COMMENT ON COLUMN ss_track_comments.timestamp IS 'Position in seconds where comment was added';
COMMENT ON COLUMN track_waveforms.samples IS 'JSONB array of normalized amplitude values (0-1)';
COMMENT ON COLUMN track_waveforms.sample_rate IS 'Number of samples per second in the waveform data';
