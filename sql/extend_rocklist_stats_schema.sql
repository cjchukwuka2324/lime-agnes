-- Extend rocklist_stats table with new columns for Listener Score system
-- Adds support for unique track tracking, completion rate, engagement, and listener score

-- Add new columns to rocklist_stats
ALTER TABLE rocklist_stats 
ADD COLUMN IF NOT EXISTS unique_track_count INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS avg_completion_rate NUMERIC DEFAULT 0,
ADD COLUMN IF NOT EXISTS engagement_score NUMERIC DEFAULT 0,
ADD COLUMN IF NOT EXISTS listener_score NUMERIC DEFAULT 0,
ADD COLUMN IF NOT EXISTS score_updated_at TIMESTAMPTZ;

-- Add index for listener_score for efficient leaderboard queries
CREATE INDEX IF NOT EXISTS idx_rocklist_stats_listener_score 
ON rocklist_stats(artist_id, region, listener_score DESC);

-- Add index for score_updated_at to track when scores were last calculated
CREATE INDEX IF NOT EXISTS idx_rocklist_stats_score_updated 
ON rocklist_stats(score_updated_at);

-- Add comment explaining the new columns
COMMENT ON COLUMN rocklist_stats.unique_track_count IS 'Number of unique tracks listened to for this artist';
COMMENT ON COLUMN rocklist_stats.avg_completion_rate IS 'Average completion rate (0-1) for tracks played';
COMMENT ON COLUMN rocklist_stats.engagement_score IS 'Raw engagement score (album saves * 3 + track likes * 1 + playlist adds * 2)';
COMMENT ON COLUMN rocklist_stats.listener_score IS 'Unified Listener Score (0-100) calculated from weighted formula';
COMMENT ON COLUMN rocklist_stats.score_updated_at IS 'Timestamp when listener_score was last calculated';

