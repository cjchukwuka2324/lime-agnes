-- ============================================
-- Add artist_name column to albums table
-- ============================================
-- This allows each album to have its own artist name
-- instead of sharing a single artist name from studio_artists
-- ============================================

-- Add artist_name column if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'albums' 
        AND column_name = 'artist_name'
    ) THEN
        ALTER TABLE albums ADD COLUMN artist_name TEXT;
        RAISE NOTICE '✅ Added artist_name column to albums table';
    ELSE
        RAISE NOTICE 'ℹ️ artist_name column already exists in albums table';
    END IF;
END $$;

-- Update existing albums to have artist_name from studio_artists
UPDATE albums a
SET artist_name = sa.name
FROM studio_artists sa
WHERE a.artist_id = sa.id::uuid
  AND a.artist_name IS NULL;

DO $$
BEGIN
    RAISE NOTICE '✅ Updated existing albums with artist names from studio_artists';
END $$;

