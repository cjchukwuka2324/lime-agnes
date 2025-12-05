-- RockList Ingestion Function
-- Processes play events from Spotify and updates rocklist_stats table
-- Also updates artist records and tracks last ingestion timestamp

-- Drop existing function if it exists (in case return type changed)
DROP FUNCTION IF EXISTS rocklist_ingest_plays(JSONB);

CREATE OR REPLACE FUNCTION rocklist_ingest_plays(
    p_events JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_user_id UUID;
    v_event JSONB;
    v_artist_id TEXT;
    v_artist_name TEXT;
    v_track_id TEXT;
    v_track_name TEXT;
    v_played_at TIMESTAMPTZ;
    v_duration_ms BIGINT;
    v_region TEXT;
    v_max_played_at TIMESTAMPTZ := NULL;
    v_processed_count INTEGER := 0;
    v_error_count INTEGER := 0;
    v_errors TEXT[] := ARRAY[]::TEXT[];
BEGIN
    -- Get current authenticated user
    v_current_user_id := auth.uid();
    
    IF v_current_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'User not authenticated'
        );
    END IF;
    
    -- Validate input
    IF p_events IS NULL OR jsonb_array_length(p_events) = 0 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'No events provided'
        );
    END IF;
    
    -- Loop through each event
    FOR v_event IN SELECT * FROM jsonb_array_elements(p_events)
    LOOP
        BEGIN
            -- Extract event fields (handle both camelCase and snake_case)
            v_artist_id := COALESCE(
                v_event->>'artistId',
                v_event->>'artist_id'
            );
            v_artist_name := COALESCE(
                v_event->>'artistName',
                v_event->>'artist_name'
            );
            v_track_id := COALESCE(
                v_event->>'trackId',
                v_event->>'track_id'
            );
            v_track_name := COALESCE(
                v_event->>'trackName',
                v_event->>'track_name'
            );
            v_played_at := (v_event->>'playedAt')::TIMESTAMPTZ;
            v_duration_ms := (v_event->>'durationMs')::BIGINT;
            v_region := COALESCE(
                v_event->>'region',
                'GLOBAL'
            );
            
            -- Validate required fields
            IF v_artist_id IS NULL OR v_artist_name IS NULL OR v_played_at IS NULL THEN
                v_error_count := v_error_count + 1;
                v_errors := array_append(v_errors, format('Missing required fields in event: %s', v_event::TEXT));
                CONTINUE;
            END IF;
            
            -- Default duration_ms if not provided
            IF v_duration_ms IS NULL THEN
                v_duration_ms := 180000; -- Default 3 minutes
            END IF;
            
            -- Track maximum played_at timestamp
            IF v_max_played_at IS NULL OR v_played_at > v_max_played_at THEN
                v_max_played_at := v_played_at;
            END IF;
            
            -- Upsert artist record
            INSERT INTO artists (spotify_id, name, created_at)
            VALUES (v_artist_id, v_artist_name, NOW())
            ON CONFLICT (spotify_id) 
            DO UPDATE SET 
                name = EXCLUDED.name,
                updated_at = NOW();
            
            -- Upsert rocklist_stats record
            -- Aggregate play_count, total_ms_played, and update last_played_at
            INSERT INTO rocklist_stats (
                user_id,
                artist_id,
                region,
                play_count,
                total_ms_played,
                score,
                last_played_at,
                updated_at
            )
            VALUES (
                v_current_user_id,
                v_artist_id,
                v_region,
                1,
                v_duration_ms,
                v_duration_ms::NUMERIC, -- Score = total_ms_played (can be adjusted)
                v_played_at,
                NOW()
            )
            ON CONFLICT (user_id, artist_id, region)
            DO UPDATE SET
                play_count = rocklist_stats.play_count + 1,
                total_ms_played = rocklist_stats.total_ms_played + v_duration_ms,
                score = (rocklist_stats.total_ms_played + v_duration_ms)::NUMERIC, -- Recalculate score
                last_played_at = GREATEST(rocklist_stats.last_played_at, v_played_at),
                updated_at = NOW();
            
            v_processed_count := v_processed_count + 1;
            
        EXCEPTION
            WHEN OTHERS THEN
                v_error_count := v_error_count + 1;
                v_errors := array_append(v_errors, format('Error processing event: %s - %s', v_event::TEXT, SQLERRM));
        END;
    END LOOP;
    
    -- Update user's last_ingested_played_at timestamp if we processed any events
    IF v_max_played_at IS NOT NULL THEN
        UPDATE profiles
        SET last_ingested_played_at = v_max_played_at
        WHERE id = v_current_user_id;
        
        -- Ensure profile exists
        IF NOT FOUND THEN
            INSERT INTO profiles (id, last_ingested_played_at, created_at, updated_at)
            VALUES (v_current_user_id, v_max_played_at, NOW(), NOW())
            ON CONFLICT (id) 
            DO UPDATE SET 
                last_ingested_played_at = v_max_played_at,
                updated_at = NOW();
        END IF;
    END IF;
    
    -- Return result
    RETURN jsonb_build_object(
        'success', true,
        'processed', v_processed_count,
        'errors', v_error_count,
        'error_details', v_errors,
        'last_ingested_played_at', v_max_played_at
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

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION rocklist_ingest_plays(JSONB) TO authenticated;

