-- Listener Score Configuration Table
-- Stores configurable weights and parameters for Listener Score calculation
-- Singleton table (only one row with id=1)

CREATE TABLE IF NOT EXISTS listener_score_config (
    id INTEGER PRIMARY KEY DEFAULT 1,
    stream_weight NUMERIC DEFAULT 0.40,
    duration_weight NUMERIC DEFAULT 0.25,
    completion_weight NUMERIC DEFAULT 0.15,
    recency_weight NUMERIC DEFAULT 0.10,
    engagement_weight NUMERIC DEFAULT 0.05,
    fan_spread_weight NUMERIC DEFAULT 0.05,
    recency_decay_lambda NUMERIC DEFAULT 0.05,
    low_completion_threshold NUMERIC DEFAULT 0.20,
    low_completion_penalty NUMERIC DEFAULT 0.30,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CHECK (id = 1) -- Singleton table
);

-- Insert default configuration if not exists
INSERT INTO listener_score_config (
    id,
    stream_weight,
    duration_weight,
    completion_weight,
    recency_weight,
    engagement_weight,
    fan_spread_weight,
    recency_decay_lambda,
    low_completion_threshold,
    low_completion_penalty
) VALUES (
    1,
    0.40,
    0.25,
    0.15,
    0.10,
    0.05,
    0.05,
    0.05,
    0.20,
    0.30
) ON CONFLICT (id) DO NOTHING;

-- Comments
COMMENT ON TABLE listener_score_config IS 'Configuration for Listener Score calculation formula';
COMMENT ON COLUMN listener_score_config.stream_weight IS 'Weight for StreamIndex (0-1)';
COMMENT ON COLUMN listener_score_config.duration_weight IS 'Weight for DurationIndex (0-1)';
COMMENT ON COLUMN listener_score_config.completion_weight IS 'Weight for CompletionIndex (0-1)';
COMMENT ON COLUMN listener_score_config.recency_weight IS 'Weight for RecencyIndex (0-1)';
COMMENT ON COLUMN listener_score_config.engagement_weight IS 'Weight for EngagementIndex (0-1)';
COMMENT ON COLUMN listener_score_config.fan_spread_weight IS 'Weight for FanSpreadIndex (0-1)';
COMMENT ON COLUMN listener_score_config.recency_decay_lambda IS 'Exponential decay parameter for RecencyIndex (λ ≈ 0.05)';
COMMENT ON COLUMN listener_score_config.low_completion_threshold IS 'Completion rate threshold below which StreamIndex is penalized (0-1)';
COMMENT ON COLUMN listener_score_config.low_completion_penalty IS 'Penalty multiplier for StreamIndex when completion is low (0-1)';

