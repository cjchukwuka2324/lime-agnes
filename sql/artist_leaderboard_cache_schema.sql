-- Artist Leaderboard Cache Table
-- Caches top listeners per artist for fast leaderboard queries
-- Refreshed periodically by scheduled job

CREATE TABLE IF NOT EXISTS artist_leaderboard_cache (
    artist_id TEXT NOT NULL,
    user_id UUID NOT NULL,
    listener_score NUMERIC NOT NULL,
    rank BIGINT NOT NULL,
    cached_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (artist_id, user_id)
);

-- Indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_cache_artist_rank 
ON artist_leaderboard_cache(artist_id, rank);

CREATE INDEX IF NOT EXISTS idx_cache_artist_score 
ON artist_leaderboard_cache(artist_id, listener_score DESC);

CREATE INDEX IF NOT EXISTS idx_cache_cached_at 
ON artist_leaderboard_cache(cached_at);

-- Enable RLS
ALTER TABLE artist_leaderboard_cache ENABLE ROW LEVEL SECURITY;

-- RLS Policies - allow all authenticated users to read cache
CREATE POLICY "Users can view leaderboard cache"
    ON artist_leaderboard_cache FOR SELECT
    USING (true);

-- Comments
COMMENT ON TABLE artist_leaderboard_cache IS 'Cached leaderboard data for fast queries. Refreshed periodically.';
COMMENT ON COLUMN artist_leaderboard_cache.rank IS 'User rank for this artist (1 = top listener)';
COMMENT ON COLUMN artist_leaderboard_cache.cached_at IS 'Timestamp when this cache entry was created';

