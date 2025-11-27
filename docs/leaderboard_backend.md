# Leaderboard Backend RPC Contracts

This document describes the Supabase Postgres RPC functions required for the RockOut leaderboard feature.

## Database Schema

### Table: `user_artist_stats`

Stores user listening statistics per artist.

```sql
CREATE TABLE user_artist_stats (
    user_id UUID NOT NULL REFERENCES auth.users(id),
    artist_id TEXT NOT NULL,
    region TEXT NOT NULL, -- Country code (e.g., 'US', 'NG', 'GB')
    play_count BIGINT NOT NULL DEFAULT 0,
    total_ms_played BIGINT NOT NULL DEFAULT 0,
    score NUMERIC NOT NULL DEFAULT 0,
    last_played_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (user_id, artist_id, region)
);

CREATE INDEX idx_user_artist_stats_artist_region ON user_artist_stats(artist_id, region);
CREATE INDEX idx_user_artist_stats_score ON user_artist_stats(artist_id, region, score DESC);
CREATE INDEX idx_user_artist_stats_updated ON user_artist_stats(updated_at);
```

## RPC Functions

### 1. `get_artist_leaderboard`

Returns the leaderboard for a specific artist with filtering by time range and region.

**Input Parameters:**
- `p_artist_id TEXT` - Spotify artist ID
- `p_start_timestamp TIMESTAMPTZ` - Start of time range
- `p_end_timestamp TIMESTAMPTZ` - End of time range
- `p_region TEXT` - Region filter (NULL for Global)

**Output Columns:**
- `artist_id TEXT`
- `artist_name TEXT`
- `artist_image_url TEXT`
- `user_id UUID`
- `display_name TEXT` - User's display name from profiles table
- `score NUMERIC`
- `rank BIGINT` - Window function rank
- `is_current_user BOOLEAN`

**SQL Implementation:**

```sql
CREATE OR REPLACE FUNCTION get_artist_leaderboard(
    p_artist_id TEXT,
    p_start_timestamp TIMESTAMPTZ,
    p_end_timestamp TIMESTAMPTZ,
    p_region TEXT DEFAULT NULL
)
RETURNS TABLE (
    artist_id TEXT,
    artist_name TEXT,
    artist_image_url TEXT,
    user_id UUID,
    display_name TEXT,
    score NUMERIC,
    rank BIGINT,
    is_current_user BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_user_id UUID;
BEGIN
    -- Get current authenticated user
    v_current_user_id := auth.uid();
    
    RETURN QUERY
    WITH ranked_stats AS (
        SELECT
            uas.artist_id,
            a.name AS artist_name,
            a.image_url AS artist_image_url,
            uas.user_id,
            COALESCE(p.display_name, u.email, 'Anonymous') AS display_name,
            uas.score,
            RANK() OVER (ORDER BY uas.score DESC) AS rank,
            (uas.user_id = v_current_user_id) AS is_current_user
        FROM user_artist_stats uas
        INNER JOIN artists a ON a.spotify_id = uas.artist_id
        LEFT JOIN profiles p ON p.user_id = uas.user_id
        LEFT JOIN auth.users u ON u.id = uas.user_id
        WHERE uas.artist_id = p_artist_id
            AND uas.updated_at >= p_start_timestamp
            AND uas.updated_at <= p_end_timestamp
            AND (p_region IS NULL OR uas.region = p_region)
    ),
    top_20 AS (
        SELECT * FROM ranked_stats
        ORDER BY rank ASC
        LIMIT 20
    ),
    current_user_entry AS (
        SELECT * FROM ranked_stats
        WHERE is_current_user = TRUE
        LIMIT 1
    )
    SELECT DISTINCT ON (user_id)
        artist_id,
        artist_name,
        artist_image_url,
        user_id,
        display_name,
        score,
        rank,
        is_current_user
    FROM (
        SELECT * FROM top_20
        UNION ALL
        SELECT * FROM current_user_entry
        WHERE NOT EXISTS (
            SELECT 1 FROM top_20 WHERE top_20.user_id = current_user_entry.user_id
        )
    ) combined
    ORDER BY rank ASC;
END;
$$;
```

### 2. `get_my_followed_artists_ranks`

Returns the current user's rank for all artists they have stats for.

**Input Parameters:**
- `p_start_timestamp TIMESTAMPTZ` - Start of time range
- `p_end_timestamp TIMESTAMPTZ` - End of time range
- `p_region TEXT` - Region filter (NULL for Global)

**Output Columns:**
- `artist_id TEXT`
- `artist_name TEXT`
- `artist_image_url TEXT`
- `my_rank BIGINT` - User's rank (NULL if not ranked)
- `my_score NUMERIC` - User's score (NULL if no stats)

**SQL Implementation:**

```sql
CREATE OR REPLACE FUNCTION get_my_followed_artists_ranks(
    p_start_timestamp TIMESTAMPTZ,
    p_end_timestamp TIMESTAMPTZ,
    p_region TEXT DEFAULT NULL
)
RETURNS TABLE (
    artist_id TEXT,
    artist_name TEXT,
    artist_image_url TEXT,
    my_rank BIGINT,
    my_score NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_user_id UUID;
BEGIN
    v_current_user_id := auth.uid();
    
    RETURN QUERY
    WITH user_stats AS (
        SELECT
            uas.artist_id,
            uas.score,
            RANK() OVER (
                PARTITION BY uas.artist_id, COALESCE(uas.region, 'GLOBAL')
                ORDER BY uas.score DESC
            ) AS rank
        FROM user_artist_stats uas
        WHERE uas.user_id = v_current_user_id
            AND uas.updated_at >= p_start_timestamp
            AND uas.updated_at <= p_end_timestamp
            AND (p_region IS NULL OR uas.region = p_region)
    ),
    artist_info AS (
        SELECT DISTINCT
            uas.artist_id,
            a.name AS artist_name,
            a.image_url AS artist_image_url
        FROM user_artist_stats uas
        INNER JOIN artists a ON a.spotify_id = uas.artist_id
        WHERE uas.user_id = v_current_user_id
            AND uas.updated_at >= p_start_timestamp
            AND uas.updated_at <= p_end_timestamp
            AND (p_region IS NULL OR uas.region = p_region)
    )
    SELECT
        ai.artist_id,
        ai.artist_name,
        ai.artist_image_url,
        us.rank AS my_rank,
        us.score AS my_score
    FROM artist_info ai
    LEFT JOIN user_stats us ON us.artist_id = ai.artist_id
    WHERE us.score > 0 OR us.score IS NULL
    ORDER BY us.rank ASC NULLS LAST;
END;
$$;
```

## Supporting Tables

### Table: `artists`

Stores artist metadata from Spotify.

```sql
CREATE TABLE artists (
    spotify_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    image_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

### Table: `profiles`

User profile information (if not already exists).

```sql
CREATE TABLE profiles (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id),
    display_name TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

## Notes

- All RPCs use `SECURITY DEFINER` to ensure proper access control
- The functions automatically use `auth.uid()` to identify the current user
- Region filtering: NULL means Global, otherwise use ISO country codes
- Rankings use `RANK()` window function which handles ties correctly
- The leaderboard always includes top 20 + current user's entry if outside top 20

