-- Quick script to calculate listener scores for all existing data
-- Run this after deploying the schema and functions to populate listener_score

-- Calculate scores for all users with listening data
DO $$
DECLARE
    v_user_record RECORD;
    v_artist_record RECORD;
    v_processed INTEGER := 0;
BEGIN
    FOR v_user_record IN 
        SELECT DISTINCT user_id, artist_id, region
        FROM rocklist_stats
        WHERE play_count > 0
        ORDER BY user_id, artist_id
    LOOP
        BEGIN
            PERFORM calculate_listener_score(
                v_user_record.user_id,
                v_user_record.artist_id,
                v_user_record.region
            );
            
            v_processed := v_processed + 1;
            
            IF v_processed % 100 = 0 THEN
                RAISE NOTICE 'Processed % records...', v_processed;
            END IF;
            
        EXCEPTION
            WHEN OTHERS THEN
                RAISE NOTICE 'Error processing user % artist %: %', 
                    v_user_record.user_id, v_user_record.artist_id, SQLERRM;
        END;
    END LOOP;
    
    RAISE NOTICE 'Completed. Processed % records.', v_processed;
END $$;

-- Refresh leaderboard cache for all artists
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

