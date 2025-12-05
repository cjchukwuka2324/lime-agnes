-- Migration Script: Backfill Listener Scores for Existing Data
-- This script calculates initial listener scores for all existing rocklist_stats records
-- Run this after deploying the new schema and functions

-- Step 1: Ensure all required data exists
-- Update unique_track_count from play_events (if play_events table has data)
UPDATE rocklist_stats rls
SET unique_track_count = (
    SELECT COUNT(DISTINCT track_id)
    FROM rocklist_play_events
    WHERE user_id = rls.user_id
        AND artist_id = rls.artist_id
)
WHERE EXISTS (
    SELECT 1 FROM rocklist_play_events
    WHERE user_id = rls.user_id
        AND artist_id = rls.artist_id
);

-- Step 2: Calculate average completion rates from play_events
UPDATE rocklist_stats rls
SET avg_completion_rate = (
    SELECT 
        CASE 
            WHEN SUM(track_duration_ms) > 0 
            THEN SUM(played_duration_ms)::NUMERIC / SUM(track_duration_ms)::NUMERIC
            ELSE 0
        END
    FROM rocklist_play_events
    WHERE user_id = rls.user_id
        AND artist_id = rls.artist_id
)
WHERE EXISTS (
    SELECT 1 FROM rocklist_play_events
    WHERE user_id = rls.user_id
        AND artist_id = rls.artist_id
);

-- Step 3: Set default completion rate for records without play_events
-- Assume 80% completion for historical data
UPDATE rocklist_stats
SET avg_completion_rate = 0.80
WHERE avg_completion_rate = 0
    AND play_count > 0;

-- Step 4: Set default unique_track_count for records without play_events
-- Estimate based on play_count (assume at least 1 unique track per 10 plays)
UPDATE rocklist_stats
SET unique_track_count = GREATEST(1, play_count / 10)
WHERE unique_track_count = 0
    AND play_count > 0;

-- Step 5: Calculate listener scores for all existing records
-- Process in batches to avoid long-running transactions
DO $$
DECLARE
    v_user_record RECORD;
    v_artist_record RECORD;
    v_processed INTEGER := 0;
    v_total INTEGER;
BEGIN
    -- Get total count
    SELECT COUNT(*) INTO v_total
    FROM rocklist_stats
    WHERE listener_score = 0 OR listener_score IS NULL;
    
    RAISE NOTICE 'Processing % records...', v_total;
    
    -- Process each user-artist-region combination
    FOR v_user_record IN 
        SELECT DISTINCT user_id, artist_id, region
        FROM rocklist_stats
        WHERE listener_score = 0 OR listener_score IS NULL
        ORDER BY user_id, artist_id
    LOOP
        BEGIN
            PERFORM calculate_listener_score(
                v_user_record.user_id,
                v_user_record.artist_id,
                v_user_record.region
            );
            
            v_processed := v_processed + 1;
            
            -- Log progress every 100 records
            IF v_processed % 100 = 0 THEN
                RAISE NOTICE 'Processed % of % records...', v_processed, v_total;
            END IF;
            
        EXCEPTION
            WHEN OTHERS THEN
                RAISE NOTICE 'Error processing user % artist %: %', 
                    v_user_record.user_id, v_user_record.artist_id, SQLERRM;
        END;
    END LOOP;
    
    RAISE NOTICE 'Migration complete. Processed % records.', v_processed;
END $$;

-- Step 6: Refresh leaderboard cache for all artists
DO $$
DECLARE
    v_artist_record RECORD;
BEGIN
    FOR v_artist_record IN 
        SELECT DISTINCT artist_id, region
        FROM rocklist_stats
        WHERE listener_score > 0
    LOOP
        BEGIN
            PERFORM refresh_artist_leaderboard_cache(
                v_artist_record.artist_id,
                v_artist_record.region
            );
        EXCEPTION
            WHEN OTHERS THEN
                RAISE NOTICE 'Error refreshing cache for artist %: %', 
                    v_artist_record.artist_id, SQLERRM;
        END;
    END LOOP;
END $$;

-- Step 7: Verify migration
SELECT 
    COUNT(*) AS total_records,
    COUNT(listener_score) AS records_with_score,
    AVG(listener_score) AS avg_score,
    MIN(listener_score) AS min_score,
    MAX(listener_score) AS max_score
FROM rocklist_stats
WHERE play_count > 0;





