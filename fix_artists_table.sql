-- Add updated_at column to artists table if it doesn't exist
-- This is optional but useful for tracking when artist names are updated

ALTER TABLE artists 
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

-- Create a trigger to automatically update updated_at on changes
CREATE OR REPLACE FUNCTION update_artists_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS artists_updated_at_trigger ON artists;

CREATE TRIGGER artists_updated_at_trigger
    BEFORE UPDATE ON artists
    FOR EACH ROW
    EXECUTE FUNCTION update_artists_updated_at();

