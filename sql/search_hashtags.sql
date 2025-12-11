-- Function to search hashtags by prefix for autocomplete
-- Returns hashtags that start with the query, ordered by popularity

CREATE OR REPLACE FUNCTION search_hashtags(
    p_query TEXT,
    p_limit INT DEFAULT 10
)
RETURNS TABLE (
    tag TEXT,
    post_count BIGINT,
    engagement_score NUMERIC,
    latest_post_at TIMESTAMPTZ
) AS $$
BEGIN
    -- If query is empty, return trending hashtags including defaults
    IF p_query IS NULL OR TRIM(p_query) = '' THEN
        RETURN QUERY
        WITH default_hashtags AS (
            SELECT 
                h.tag,
                COALESCE(h.post_count, 0)::BIGINT as post_count,
                0::NUMERIC as engagement_score,
                COALESCE(MAX(ph.created_at), NOW()) as latest_post_at
            FROM hashtags h
            LEFT JOIN post_hashtags ph ON ph.hashtag_id = h.id
            WHERE h.tag IN ('baroftheday', 'songoftheday', 'concertpov')
            GROUP BY h.id, h.tag, h.post_count
        ),
        trending_hashtags AS (
            SELECT 
                h.tag,
                COALESCE(h.post_count, 0)::BIGINT as post_count,
                0::NUMERIC as engagement_score,
                COALESCE(MAX(ph.created_at), NOW()) as latest_post_at
            FROM hashtags h
            LEFT JOIN post_hashtags ph ON ph.hashtag_id = h.id
            WHERE h.post_count > 0
            GROUP BY h.id, h.tag, h.post_count
            ORDER BY h.post_count DESC, MAX(ph.created_at) DESC NULLS LAST
            LIMIT p_limit
        )
        SELECT * FROM default_hashtags
        UNION
        SELECT * FROM trending_hashtags
        ORDER BY post_count DESC, latest_post_at DESC
        LIMIT p_limit;
    ELSE
        -- Search hashtags that start with query
        RETURN QUERY
        SELECT 
            h.tag,
            COALESCE(h.post_count, 0)::BIGINT as post_count,
            0::NUMERIC as engagement_score,
            COALESCE(MAX(ph.created_at), NOW()) as latest_post_at
        FROM hashtags h
        LEFT JOIN post_hashtags ph ON ph.hashtag_id = h.id
        WHERE LOWER(h.tag) LIKE LOWER(p_query || '%')
        GROUP BY h.id, h.tag, h.post_count
        ORDER BY 
            -- Prioritize exact matches
            CASE WHEN LOWER(h.tag) = LOWER(p_query) THEN 0 ELSE 1 END,
            -- Then by post count
            h.post_count DESC,
            -- Then by recency
            MAX(ph.created_at) DESC NULLS LAST
        LIMIT p_limit;
    END IF;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION search_hashtags(TEXT, INT) TO authenticated;

-- Add comment for documentation
COMMENT ON FUNCTION search_hashtags IS 'Searches hashtags by prefix for autocomplete, returns trending hashtags if query is empty';

