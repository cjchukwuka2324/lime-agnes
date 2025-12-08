-- Get Listener Score Breakdown Function
-- Returns detailed breakdown of all Listener Score components for a user-artist pair
-- This function returns all intermediate values used in the calculation

CREATE OR REPLACE FUNCTION get_listener_score_breakdown(
    p_user_id UUID,
    p_artist_id TEXT,
    p_region TEXT DEFAULT 'GLOBAL'
)
RETURNS JSONB
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
    v_album_saves INTEGER;
    v_track_likes INTEGER;
    v_playlist_adds INTEGER;
    
    -- Normalized indices (0-1)
    v_stream_index NUMERIC;
    v_duration_index NUMERIC;
    v_completion_index NUMERIC;
    v_recency_index NUMERIC;
    v_engagement_index NUMERIC;
    v_fan_spread_index NUMERIC;
    
    -- Weighted contributions
    v_stream_contribution NUMERIC;
    v_duration_contribution NUMERIC;
    v_completion_contribution NUMERIC;
    v_recency_contribution NUMERIC;
    v_engagement_contribution NUMERIC;
    v_fan_spread_contribution NUMERIC;
    
    -- Final score
    v_listener_score NUMERIC;
    
    -- Result JSON
    v_result JSONB;
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
    
    -- If no stats exist, return empty breakdown
    IF v_stats IS NULL THEN
        RETURN jsonb_build_object(
            'error', 'No stats found for this user-artist pair'
        );
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
    
    -- Get engagement breakdown
    IF v_engagement IS NOT NULL THEN
        v_album_saves := COALESCE(v_engagement.album_saves, 0);
        v_track_likes := COALESCE(v_engagement.track_likes, 0);
        v_playlist_adds := COALESCE(v_engagement.playlist_adds, 0);
        v_engagement_raw := v_album_saves * 3 + v_track_likes * 1 + v_playlist_adds * 2;
    ELSE
        v_album_saves := 0;
        v_track_likes := 0;
        v_playlist_adds := 0;
        v_engagement_raw := COALESCE(v_stats.engagement_score, 0);
    END IF;
    
    -- Calculate days since last listen
    IF v_stats.last_played_at IS NOT NULL THEN
        v_days_since_last_listen := EXTRACT(EPOCH FROM (NOW() - v_stats.last_played_at)) / 86400.0;
    ELSE
        v_days_since_last_listen := 999; -- Very old if never listened
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
    
    -- Calculate weighted contributions
    v_stream_contribution := v_config.stream_weight * v_stream_index * 100.0;
    v_duration_contribution := v_config.duration_weight * v_duration_index * 100.0;
    v_completion_contribution := v_config.completion_weight * v_completion_index * 100.0;
    v_recency_contribution := v_config.recency_weight * v_recency_index * 100.0;
    v_engagement_contribution := v_config.engagement_weight * v_engagement_index * 100.0;
    v_fan_spread_contribution := v_config.fan_spread_weight * v_fan_spread_index * 100.0;
    
    -- Calculate final Listener Score (0-100)
    v_listener_score := 
        v_stream_contribution +
        v_duration_contribution +
        v_completion_contribution +
        v_recency_contribution +
        v_engagement_contribution +
        v_fan_spread_contribution;
    
    v_listener_score := LEAST(100.0, GREATEST(0.0, v_listener_score));
    
    -- Build result JSON
    v_result := jsonb_build_object(
        'listener_score', ROUND(v_listener_score::NUMERIC, 2),
        'stream_index', jsonb_build_object(
            'value', ROUND(v_stream_index::NUMERIC, 4),
            'weight', v_config.stream_weight,
            'contribution', ROUND(v_stream_contribution::NUMERIC, 2),
            'raw', jsonb_build_object(
                'stream_count', v_stream_count,
                'max_stream_count', COALESCE(v_max_stats.max_stream_count, 0)
            )
        ),
        'duration_index', jsonb_build_object(
            'value', ROUND(v_duration_index::NUMERIC, 4),
            'weight', v_config.duration_weight,
            'contribution', ROUND(v_duration_contribution::NUMERIC, 2),
            'raw', jsonb_build_object(
                'total_minutes', ROUND(v_total_minutes::NUMERIC, 2),
                'max_minutes', ROUND((COALESCE(v_max_stats.max_total_ms, 0) / 60000.0)::NUMERIC, 2)
            )
        ),
        'completion_index', jsonb_build_object(
            'value', ROUND(v_completion_index::NUMERIC, 4),
            'weight', v_config.completion_weight,
            'contribution', ROUND(v_completion_contribution::NUMERIC, 2),
            'raw', jsonb_build_object(
                'avg_completion_rate', ROUND(v_avg_completion::NUMERIC, 4)
            )
        ),
        'recency_index', jsonb_build_object(
            'value', ROUND(v_recency_index::NUMERIC, 4),
            'weight', v_config.recency_weight,
            'contribution', ROUND(v_recency_contribution::NUMERIC, 2),
            'raw', jsonb_build_object(
                'days_since_last_listen', ROUND(v_days_since_last_listen::NUMERIC, 1)
            )
        ),
        'engagement_index', jsonb_build_object(
            'value', ROUND(v_engagement_index::NUMERIC, 4),
            'weight', v_config.engagement_weight,
            'contribution', ROUND(v_engagement_contribution::NUMERIC, 2),
            'raw', jsonb_build_object(
                'engagement_raw', v_engagement_raw,
                'max_engagement_raw', COALESCE(v_max_stats.max_engagement_raw, 0),
                'album_saves', v_album_saves,
                'track_likes', v_track_likes,
                'playlist_adds', v_playlist_adds
            )
        ),
        'fan_spread_index', jsonb_build_object(
            'value', ROUND(v_fan_spread_index::NUMERIC, 4),
            'weight', v_config.fan_spread_weight,
            'contribution', ROUND(v_fan_spread_contribution::NUMERIC, 2),
            'raw', jsonb_build_object(
                'unique_tracks', v_unique_tracks,
                'total_tracks', v_total_tracks
            )
        )
    );
    
    RETURN v_result;
    
EXCEPTION
    WHEN OTHERS THEN
        -- Return error in JSON format
        RETURN jsonb_build_object(
            'error', SQLERRM
        );
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION get_listener_score_breakdown(UUID, TEXT, TEXT) TO authenticated;








