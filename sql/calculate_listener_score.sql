-- Calculate Listener Score Function
-- Computes unified Listener Score (0-100) for a user-artist pair using weighted formula
-- Formula: ListenerScore = (0.40 * StreamIndex) + (0.25 * DurationIndex) + 
--          (0.15 * CompletionIndex) + (0.10 * RecencyIndex) + 
--          (0.05 * EngagementIndex) + (0.05 * FanSpreadIndex)

CREATE OR REPLACE FUNCTION calculate_listener_score(
    p_user_id UUID,
    p_artist_id TEXT,
    p_region TEXT DEFAULT 'GLOBAL'
)
RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_config RECORD;
    v_stats RECORD;
    v_engagement RECORD;
    v_artist RECORD;
    v_max_stats RECORD;
    
    -- Raw values
    v_stream_count BIGINT;
    v_total_minutes NUMERIC;
    v_avg_completion NUMERIC;
    v_days_since_last_listen NUMERIC;
    v_engagement_raw NUMERIC;
    v_unique_tracks INTEGER;
    v_total_tracks INTEGER;
    
    -- Normalized indices (0-1)
    v_stream_index NUMERIC;
    v_duration_index NUMERIC;
    v_completion_index NUMERIC;
    v_recency_index NUMERIC;
    v_engagement_index NUMERIC;
    v_fan_spread_index NUMERIC;
    
    -- Final score
    v_listener_score NUMERIC;
BEGIN
    -- Get configuration
    SELECT * INTO v_config FROM listener_score_config WHERE id = 1;
    
    -- Get user stats for this artist
    SELECT 
        play_count,
        total_ms_played,
        avg_completion_rate,
        last_played_at,
        unique_track_count,
        engagement_score
    INTO v_stats
    FROM rocklist_stats
    WHERE user_id = p_user_id
        AND artist_id = p_artist_id
        AND region = p_region;
    
    -- If no stats exist, return 0
    IF v_stats IS NULL THEN
        RETURN 0;
    END IF;
    
    -- Get engagement data
    SELECT 
        COALESCE(album_saves, 0) AS album_saves,
        COALESCE(track_likes, 0) AS track_likes,
        COALESCE(playlist_adds, 0) AS playlist_adds
    INTO v_engagement
    FROM user_artist_engagement
    WHERE user_id = p_user_id
        AND artist_id = p_artist_id;
    
    -- Get artist catalog size
    SELECT COALESCE(total_track_count, 0) INTO v_total_tracks
    FROM artists
    WHERE spotify_id = p_artist_id;
    
    -- Get max values for normalization (across all users for this artist)
    SELECT 
        MAX(play_count) AS max_stream_count,
        MAX(total_ms_played) AS max_total_ms,
        MAX(engagement_score) AS max_engagement_raw
    INTO v_max_stats
    FROM rocklist_stats rls
    LEFT JOIN user_artist_engagement uae ON uae.user_id = rls.user_id AND uae.artist_id = rls.artist_id
    WHERE rls.artist_id = p_artist_id
        AND rls.region = p_region;
    
    -- Calculate raw values
    v_stream_count := COALESCE(v_stats.play_count, 0);
    v_total_minutes := COALESCE(v_stats.total_ms_played, 0) / 60000.0; -- Convert ms to minutes
    v_avg_completion := COALESCE(v_stats.avg_completion_rate, 0);
    v_unique_tracks := COALESCE(v_stats.unique_track_count, 0);
    
    -- Calculate days since last listen
    IF v_stats.last_played_at IS NOT NULL THEN
        v_days_since_last_listen := EXTRACT(EPOCH FROM (NOW() - v_stats.last_played_at)) / 86400.0;
    ELSE
        v_days_since_last_listen := 999; -- Very old if never listened
    END IF;
    
    -- Calculate engagement raw score
    -- First try from engagement table, fallback to engagement_score in rocklist_stats
    IF v_engagement IS NOT NULL THEN
        v_engagement_raw := COALESCE(v_engagement.album_saves, 0) * 3 +
                           COALESCE(v_engagement.track_likes, 0) * 1 +
                           COALESCE(v_engagement.playlist_adds, 0) * 2;
    ELSE
        -- Fallback to engagement_score from rocklist_stats if engagement table doesn't have data
        v_engagement_raw := COALESCE(v_stats.engagement_score, 0);
    END IF;
    
    -- Calculate normalized indices (0-1)
    
    -- StreamIndex: user_stream_count / max_stream_count
    IF COALESCE(v_max_stats.max_stream_count, 0) > 0 THEN
        v_stream_index := LEAST(1.0, v_stream_count::NUMERIC / v_max_stats.max_stream_count::NUMERIC);
    ELSE
        v_stream_index := 0;
    END IF;
    
    -- Apply low completion penalty if completion rate is very low
    IF v_avg_completion < v_config.low_completion_threshold THEN
        v_stream_index := v_stream_index * (1.0 - v_config.low_completion_penalty);
    END IF;
    
    -- DurationIndex: user_listen_minutes / max_listen_minutes
    IF COALESCE(v_max_stats.max_total_ms, 0) > 0 THEN
        v_duration_index := LEAST(1.0, (v_stats.total_ms_played::NUMERIC / 60000.0) / (v_max_stats.max_total_ms::NUMERIC / 60000.0));
    ELSE
        v_duration_index := 0;
    END IF;
    
    -- CompletionIndex: avg_completion_rate (already 0-1)
    v_completion_index := LEAST(1.0, v_avg_completion);
    
    -- RecencyIndex: exp(-λ * days_since_last_listen)
    v_recency_index := EXP(-v_config.recency_decay_lambda * v_days_since_last_listen);
    v_recency_index := LEAST(1.0, GREATEST(0.0, v_recency_index));
    
    -- EngagementIndex: engagement_raw / max_engagement_raw
    IF COALESCE(v_max_stats.max_engagement_raw, 0) > 0 THEN
        v_engagement_index := LEAST(1.0, v_engagement_raw::NUMERIC / v_max_stats.max_engagement_raw::NUMERIC);
    ELSE
        v_engagement_index := 0;
    END IF;
    
    -- FanSpreadIndex: unique_tracks / total_tracks_in_catalog
    IF v_total_tracks > 0 THEN
        v_fan_spread_index := LEAST(1.0, v_unique_tracks::NUMERIC / v_total_tracks::NUMERIC);
    ELSE
        v_fan_spread_index := 0;
    END IF;
    
    -- Calculate final Listener Score (0-100)
    v_listener_score := 
        (v_config.stream_weight * v_stream_index) +
        (v_config.duration_weight * v_duration_index) +
        (v_config.completion_weight * v_completion_index) +
        (v_config.recency_weight * v_recency_index) +
        (v_config.engagement_weight * v_engagement_index) +
        (v_config.fan_spread_weight * v_fan_spread_index);
    
    -- Scale to 0-100
    v_listener_score := v_listener_score * 100.0;
    v_listener_score := LEAST(100.0, GREATEST(0.0, v_listener_score));
    
    -- Update rocklist_stats with calculated score
    UPDATE rocklist_stats
    SET 
        listener_score = v_listener_score,
        score_updated_at = NOW()
    WHERE user_id = p_user_id
        AND artist_id = p_artist_id
        AND region = p_region;
    
    RETURN v_listener_score;
    
EXCEPTION
    WHEN OTHERS THEN
        -- Return 0 on error
        RETURN 0;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION calculate_listener_score(UUID, TEXT, TEXT) TO authenticated;

