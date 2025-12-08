-- Extend artists table with catalog size caching
-- Used for FanSpreadIndex calculation (unique_tracks_listened / total_tracks_in_catalog)

ALTER TABLE artists 
ADD COLUMN IF NOT EXISTS total_track_count INTEGER,
ADD COLUMN IF NOT EXISTS catalog_updated_at TIMESTAMPTZ;

-- Add index for catalog_updated_at to track which artists need catalog refresh
CREATE INDEX IF NOT EXISTS idx_artists_catalog_updated 
ON artists(catalog_updated_at);

-- Comments
COMMENT ON COLUMN artists.total_track_count IS 'Total number of tracks in artist catalog (cached from Spotify API)';
COMMENT ON COLUMN artists.catalog_updated_at IS 'Timestamp when catalog size was last fetched from Spotify API';








