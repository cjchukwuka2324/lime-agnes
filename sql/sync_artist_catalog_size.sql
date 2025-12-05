-- Sync Artist Catalog Size Function
-- Fetches and caches total track count for an artist from Spotify API
-- Should be called via Edge Function that has Spotify API access

CREATE OR REPLACE FUNCTION sync_artist_catalog_size(
    p_artist_id TEXT,
    p_total_track_count INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Update artist catalog size
    UPDATE artists
    SET 
        total_track_count = p_total_track_count,
        catalog_updated_at = NOW()
    WHERE spotify_id = p_artist_id;
    
    -- If artist doesn't exist, create it (shouldn't happen, but handle gracefully)
    IF NOT FOUND THEN
        INSERT INTO artists (spotify_id, total_track_count, catalog_updated_at)
        VALUES (p_artist_id, p_total_track_count, NOW())
        ON CONFLICT (spotify_id) DO UPDATE SET
            total_track_count = EXCLUDED.total_track_count,
            catalog_updated_at = EXCLUDED.catalog_updated_at;
    END IF;
    
    RETURN jsonb_build_object(
        'success', true,
        'artist_id', p_artist_id,
        'total_track_count', p_total_track_count
    );
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', SQLERRM
        );
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION sync_artist_catalog_size(TEXT, INTEGER) TO authenticated;

