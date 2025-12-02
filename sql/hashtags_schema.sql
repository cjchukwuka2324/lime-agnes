-- Hashtags schema for trending functionality
-- Enables #songoftheday, #concertview, etc. functionality

-- Drop existing tables if they exist (idempotent)
DROP TABLE IF EXISTS post_hashtags CASCADE;
DROP TABLE IF EXISTS hashtags CASCADE;

-- Hashtags table: stores unique normalized hashtags
CREATE TABLE hashtags (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tag TEXT NOT NULL UNIQUE, -- normalized: lowercase, no # symbol
    post_count INT DEFAULT 0, -- cached count for performance
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- Indexes for efficient querying
CREATE INDEX idx_hashtags_tag ON hashtags(tag);
CREATE INDEX idx_hashtags_post_count ON hashtags(post_count DESC);
CREATE INDEX idx_hashtags_created_at ON hashtags(created_at DESC);

-- Post-Hashtag junction table: many-to-many relationship
CREATE TABLE post_hashtags (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    hashtag_id UUID NOT NULL REFERENCES hashtags(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    UNIQUE(post_id, hashtag_id) -- Prevent duplicate associations
);

-- Indexes for efficient joins and queries
CREATE INDEX idx_post_hashtags_post_id ON post_hashtags(post_id);
CREATE INDEX idx_post_hashtags_hashtag_id ON post_hashtags(hashtag_id);
CREATE INDEX idx_post_hashtags_created_at ON post_hashtags(created_at DESC);
CREATE INDEX idx_post_hashtags_hashtag_created ON post_hashtags(hashtag_id, created_at DESC);

-- Row Level Security (RLS)
ALTER TABLE hashtags ENABLE ROW LEVEL SECURITY;
ALTER TABLE post_hashtags ENABLE ROW LEVEL SECURITY;

-- RLS Policies for hashtags
CREATE POLICY "Anyone can view hashtags"
    ON hashtags FOR SELECT
    USING (true);

CREATE POLICY "System can insert hashtags"
    ON hashtags FOR INSERT
    WITH CHECK (true);

CREATE POLICY "System can update hashtags"
    ON hashtags FOR UPDATE
    USING (true);

-- RLS Policies for post_hashtags
CREATE POLICY "Anyone can view post_hashtags"
    ON post_hashtags FOR SELECT
    USING (true);

CREATE POLICY "Authenticated users can insert post_hashtags"
    ON post_hashtags FOR INSERT
    TO authenticated
    WITH CHECK (true);

CREATE POLICY "Users can delete their own post_hashtags"
    ON post_hashtags FOR DELETE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM posts
            WHERE posts.id = post_hashtags.post_id
            AND posts.user_id = auth.uid()
        )
    );

-- Trigger to increment/decrement post_count on hashtags table
CREATE OR REPLACE FUNCTION update_hashtag_post_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE hashtags
        SET post_count = post_count + 1
        WHERE id = NEW.hashtag_id;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE hashtags
        SET post_count = GREATEST(post_count - 1, 0)
        WHERE id = OLD.hashtag_id;
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_hashtag_post_count
AFTER INSERT OR DELETE ON post_hashtags
FOR EACH ROW
EXECUTE FUNCTION update_hashtag_post_count();

-- Helper function to create or get hashtag
CREATE OR REPLACE FUNCTION get_or_create_hashtag(p_tag TEXT)
RETURNS UUID AS $$
DECLARE
    v_hashtag_id UUID;
    v_normalized_tag TEXT;
BEGIN
    -- Normalize: lowercase, trim whitespace, remove # if present
    v_normalized_tag := LOWER(TRIM(BOTH FROM REPLACE(p_tag, '#', '')));
    
    -- Try to get existing hashtag
    SELECT id INTO v_hashtag_id
    FROM hashtags
    WHERE tag = v_normalized_tag;
    
    -- If not found, create it
    IF v_hashtag_id IS NULL THEN
        INSERT INTO hashtags (tag)
        VALUES (v_normalized_tag)
        RETURNING id INTO v_hashtag_id;
    END IF;
    
    RETURN v_hashtag_id;
END;
$$ LANGUAGE plpgsql;

-- Function to link post to hashtags (called after post creation)
CREATE OR REPLACE FUNCTION link_post_to_hashtags(
    p_post_id UUID,
    p_hashtags TEXT[] -- Array of hashtag strings
)
RETURNS void AS $$
DECLARE
    v_tag TEXT;
    v_hashtag_id UUID;
BEGIN
    -- Loop through each hashtag
    FOREACH v_tag IN ARRAY p_hashtags
    LOOP
        -- Get or create the hashtag
        v_hashtag_id := get_or_create_hashtag(v_tag);
        
        -- Link post to hashtag (ignore duplicates)
        INSERT INTO post_hashtags (post_id, hashtag_id)
        VALUES (p_post_id, v_hashtag_id)
        ON CONFLICT (post_id, hashtag_id) DO NOTHING;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION get_or_create_hashtag(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION link_post_to_hashtags(UUID, TEXT[]) TO authenticated;

-- Add comments for documentation
COMMENT ON TABLE hashtags IS 'Stores unique normalized hashtags for trending functionality';
COMMENT ON TABLE post_hashtags IS 'Junction table linking posts to hashtags (many-to-many)';
COMMENT ON COLUMN hashtags.tag IS 'Normalized hashtag: lowercase, no # symbol';
COMMENT ON COLUMN hashtags.post_count IS 'Cached count of posts using this hashtag';
COMMENT ON FUNCTION link_post_to_hashtags IS 'Links a post to multiple hashtags, creating hashtags if needed';

