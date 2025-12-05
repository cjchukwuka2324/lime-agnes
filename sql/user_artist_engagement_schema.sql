-- User Artist Engagement Table
-- Stores engagement metrics (album saves, track likes, playlist adds) per user per artist
-- Used for calculating EngagementIndex in Listener Score formula

CREATE TABLE IF NOT EXISTS user_artist_engagement (
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    artist_id TEXT NOT NULL,
    album_saves INTEGER DEFAULT 0,
    track_likes INTEGER DEFAULT 0,
    playlist_adds INTEGER DEFAULT 0,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (user_id, artist_id)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_engagement_artist 
ON user_artist_engagement(artist_id);

CREATE INDEX IF NOT EXISTS idx_engagement_user 
ON user_artist_engagement(user_id);

CREATE INDEX IF NOT EXISTS idx_engagement_updated 
ON user_artist_engagement(updated_at);

-- Enable RLS
ALTER TABLE user_artist_engagement ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users can view their own engagement"
    ON user_artist_engagement FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own engagement"
    ON user_artist_engagement FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Service can insert/update engagement"
    ON user_artist_engagement FOR ALL
    WITH CHECK (true);

-- Comments
COMMENT ON TABLE user_artist_engagement IS 'Tracks user engagement with artist (saves, likes, playlist adds)';
COMMENT ON COLUMN user_artist_engagement.album_saves IS 'Number of albums by this artist saved by user';
COMMENT ON COLUMN user_artist_engagement.track_likes IS 'Number of tracks by this artist liked by user';
COMMENT ON COLUMN user_artist_engagement.playlist_adds IS 'Number of times user added artist tracks to playlists';

