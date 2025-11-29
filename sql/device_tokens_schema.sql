-- Device tokens table for push notifications
-- Stores APNs device tokens for iOS devices

CREATE TABLE IF NOT EXISTS device_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    token TEXT NOT NULL,
    platform TEXT NOT NULL DEFAULT 'ios' CHECK (platform IN ('ios', 'android')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Unique index to prevent duplicate tokens per user
CREATE UNIQUE INDEX IF NOT EXISTS idx_device_tokens_user_token 
    ON device_tokens(user_id, token);

-- Index for efficient token lookup
CREATE INDEX IF NOT EXISTS idx_device_tokens_user 
    ON device_tokens(user_id);

-- Row Level Security (RLS) Policies
ALTER TABLE device_tokens ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Users can view their own device tokens" ON device_tokens;
DROP POLICY IF EXISTS "Users can insert their own device tokens" ON device_tokens;
DROP POLICY IF EXISTS "Users can update their own device tokens" ON device_tokens;
DROP POLICY IF EXISTS "Users can delete their own device tokens" ON device_tokens;

-- Users can only manage their own device tokens
CREATE POLICY "Users can view their own device tokens"
    ON device_tokens FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own device tokens"
    ON device_tokens FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own device tokens"
    ON device_tokens FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own device tokens"
    ON device_tokens FOR DELETE
    USING (auth.uid() = user_id);

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_device_tokens_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to automatically update updated_at
DROP TRIGGER IF EXISTS trg_device_tokens_updated_at ON device_tokens;
CREATE TRIGGER trg_device_tokens_updated_at
    BEFORE UPDATE ON device_tokens
    FOR EACH ROW
    EXECUTE FUNCTION update_device_tokens_updated_at();

COMMENT ON TABLE device_tokens IS 'Stores device tokens for push notifications';
COMMENT ON COLUMN device_tokens.token IS 'APNs device token (hex string)';
COMMENT ON COLUMN device_tokens.platform IS 'Device platform: ios or android';

