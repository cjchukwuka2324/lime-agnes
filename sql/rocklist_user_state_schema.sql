-- Add last_ingested_played_at column to profiles table for tracking RockList ingestion
-- This column stores the timestamp of the most recent play event that was ingested
-- Used for incremental ingestion to know where to start fetching from Spotify

-- Add column if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_name = 'profiles' 
        AND column_name = 'last_ingested_played_at'
    ) THEN
        ALTER TABLE profiles 
        ADD COLUMN last_ingested_played_at TIMESTAMPTZ;
        
        -- Add index for efficient queries
        CREATE INDEX IF NOT EXISTS idx_profiles_last_ingested 
        ON profiles(last_ingested_played_at);
        
        RAISE NOTICE 'Added last_ingested_played_at column to profiles table';
    ELSE
        RAISE NOTICE 'Column last_ingested_played_at already exists in profiles table';
    END IF;
END $$;





