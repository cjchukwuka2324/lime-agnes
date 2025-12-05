-- RockList Play Events Table
-- Stores detailed play events for completion rate calculation
-- Each event tracks how much of a track was actually played vs. track duration

CREATE TABLE IF NOT EXISTS rocklist_play_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    artist_id TEXT NOT NULL,
    track_id TEXT NOT NULL,
    track_name TEXT,
    played_duration_ms BIGINT NOT NULL,
    track_duration_ms BIGINT NOT NULL,
    played_at TIMESTAMPTZ NOT NULL,
    region TEXT NOT NULL DEFAULT 'GLOBAL',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_play_events_user_artist 
ON rocklist_play_events(user_id, artist_id);

CREATE INDEX IF NOT EXISTS idx_play_events_played_at 
ON rocklist_play_events(played_at);

CREATE INDEX IF NOT EXISTS idx_play_events_artist_track 
ON rocklist_play_events(artist_id, track_id);

CREATE INDEX IF NOT EXISTS idx_play_events_user_artist_played 
ON rocklist_play_events(user_id, artist_id, played_at DESC);

-- Enable RLS
ALTER TABLE rocklist_play_events ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users can view their own play events"
    ON rocklist_play_events FOR SELECT
    USING (auth.uid() = user_id);

-- Service role can insert (for ingestion function)
CREATE POLICY "Service can insert play events"
    ON rocklist_play_events FOR INSERT
    WITH CHECK (true);

-- Comments
COMMENT ON TABLE rocklist_play_events IS 'Detailed play events for calculating completion rates and tracking unique tracks';
COMMENT ON COLUMN rocklist_play_events.played_duration_ms IS 'How long the user actually listened (may be less than track_duration_ms)';
COMMENT ON COLUMN rocklist_play_events.track_duration_ms IS 'Total duration of the track';





