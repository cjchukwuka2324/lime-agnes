-- Recalculate Listener Scores for All Users of an Artist
-- Batch function to recalculate scores for all users who have stats for a specific artist
-- Updates listener_score and score_updated_at in rocklist_stats

CREATE OR REPLACE FUNCTION recalculate_artist_listener_scores(
    p_artist_id TEXT,
    p_region TEXT DEFAULT 'GLOBAL'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_record RECORD;
    v_processed_count INTEGER := 0;
    v_error_count INTEGER := 0;
    v_errors TEXT[] := ARRAY[]::TEXT[];
    v_score NUMERIC;
BEGIN
    -- Loop through all users with stats for this artist
    FOR v_user_record IN 
        SELECT DISTINCT user_id
        FROM rocklist_stats
        WHERE artist_id = p_artist_id
            AND region = p_region
    LOOP
        BEGIN
            -- Calculate listener score for this user
            v_score := calculate_listener_score(
                v_user_record.user_id,
                p_artist_id,
                p_region
            );
            
            v_processed_count := v_processed_count + 1;
            
        EXCEPTION
            WHEN OTHERS THEN
                v_error_count := v_error_count + 1;
                v_errors := array_append(v_errors, format('Error calculating score for user %s: %s', v_user_record.user_id, SQLERRM));
        END;
    END LOOP;
    
    RETURN jsonb_build_object(
        'success', true,
        'artist_id', p_artist_id,
        'region', p_region,
        'processed', v_processed_count,
        'errors', v_error_count,
        'error_details', v_errors
    );
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', SQLERRM,
            'processed', v_processed_count
        );
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION recalculate_artist_listener_scores(TEXT, TEXT) TO authenticated;





