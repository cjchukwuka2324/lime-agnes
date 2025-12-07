-- ============================================
-- Track Play Counting Schema
-- Adds play count tracking for individual tracks in albums
-- ============================================

-- Create track_plays table
CREATE TABLE IF NOT EXISTS track_plays (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    track_id UUID NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
    album_id UUID NOT NULL REFERENCES albums(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    played_at TIMESTAMPTZ DEFAULT NOW(),
    duration_listened DOUBLE PRECISION NOT NULL, -- How long they listened in seconds
    track_duration DOUBLE PRECISION NOT NULL, -- Full track duration at time of play
    threshold_reached BOOLEAN DEFAULT FALSE, -- Whether 30sec or 80% threshold was reached
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_track_plays_track_id ON track_plays(track_id);
CREATE INDEX IF NOT EXISTS idx_track_plays_album_id ON track_plays(album_id);
CREATE INDEX IF NOT EXISTS idx_track_plays_user_id ON track_plays(user_id);
CREATE INDEX IF NOT EXISTS idx_track_plays_track_user ON track_plays(track_id, user_id);
CREATE INDEX IF NOT EXISTS idx_track_plays_album_track ON track_plays(album_id, track_id);
CREATE INDEX IF NOT EXISTS idx_track_plays_threshold ON track_plays(track_id, threshold_reached) WHERE threshold_reached = true;

-- Aggregation view for efficient play count queries
CREATE OR REPLACE VIEW track_play_counts AS
SELECT 
    track_id,
    album_id,
    COUNT(*) FILTER (WHERE threshold_reached = true) as play_count,
    COUNT(DISTINCT user_id) FILTER (WHERE threshold_reached = true) as unique_listeners
FROM track_plays
GROUP BY track_id, album_id;

-- Enable RLS
ALTER TABLE track_plays ENABLE ROW LEVEL SECURITY;

-- RLS Policies

-- Users can record their own track plays
DROP POLICY IF EXISTS "Users can record own track plays" ON track_plays;
CREATE POLICY "Users can record own track plays"
    ON track_plays FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Album owners and collaborators can view play counts
DROP POLICY IF EXISTS "Owners and collaborators can view play counts" ON track_plays;
CREATE POLICY "Owners and collaborators can view play counts"
    ON track_plays FOR SELECT
    USING (
        -- User is owner of the album
        EXISTS (
            SELECT 1 FROM albums 
            WHERE albums.id = track_plays.album_id 
            AND albums.artist_id = auth.uid()
        )
        OR
        -- User is collaborator on the album
        EXISTS (
            SELECT 1 FROM shared_albums
            WHERE shared_albums.album_id = track_plays.album_id
            AND shared_albums.shared_with = auth.uid()
            AND shared_albums.is_collaboration = true
        )
    );

-- Users can view their own play records (for deduplication checks)
DROP POLICY IF EXISTS "Users can view own play records" ON track_plays;
CREATE POLICY "Users can view own play records"
    ON track_plays FOR SELECT
    USING (auth.uid() = user_id);

-- Comments for documentation
COMMENT ON TABLE track_plays IS 'Tracks individual track plays by users. Records when threshold (30 sec or 80% for short tracks) is reached.';
COMMENT ON COLUMN track_plays.threshold_reached IS 'Whether the play threshold was met (30 seconds for long tracks, 80% for tracks ≤30 sec)';
COMMENT ON COLUMN track_plays.duration_listened IS 'How long the user listened in seconds when the record was created';
COMMENT ON VIEW track_play_counts IS 'Aggregated play counts per track, counting only plays where threshold_reached = true';

