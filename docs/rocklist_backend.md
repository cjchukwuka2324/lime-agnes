# RockList Backend RPC Contracts

This document describes the Supabase Postgres RPC functions required for the RockOut RockList feature.

## Architecture Overview

### Data Flow
1. **Spotify API** → iOS app fetches listening data (recently played, top tracks/artists)
2. **RockListDataService** → Normalizes Spotify data into `RockListPlayEvent` format
3. **rocklist_ingest_plays() RPC** → Processes play events and stores in database
4. **rocklist_stats table** → Aggregates listening statistics per (user, artist, region)
5. **Listener Score Calculation** → Computes unified score (0-100) using weighted formula
6. **Leaderboard Queries** → Returns ranked users sorted by listener_score
7. **iOS UI** → Displays RockList with rankings and scores

### Key Components
- **Ingestion**: `rocklist_ingest_plays()` processes play events from Spotify
- **Storage**: `rocklist_stats` table stores aggregated stats, `rocklist_play_events` stores detailed events
- **Scoring**: `calculate_listener_score()` computes unified Listener Score (0-100)
- **Ranking**: `get_rocklist_for_artist()` returns leaderboard sorted by listener_score
- **Scheduling**: Edge Function recalculates scores periodically (every 15 minutes)

## Database Schema

### Table: `rocklist_stats`

Stores user listening statistics per artist.

```sql
CREATE TABLE rocklist_stats (
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

CREATE INDEX idx_rocklist_stats_artist_region ON rocklist_stats(artist_id, region);
CREATE INDEX idx_rocklist_stats_score ON rocklist_stats(artist_id, region, score DESC);
CREATE INDEX idx_rocklist_stats_updated ON rocklist_stats(updated_at);
```

### Table: `user_comments`

Stores comments from users on RockList and StudioSessions (extensible).

```sql
CREATE TABLE user_comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id),
    artist_id TEXT, -- Used for RockList comments
    studio_session_id UUID, -- Used for StudioSessions comments (future)
    content TEXT NOT NULL,
    region TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_user_comments_artist ON user_comments(artist_id, created_at DESC);
CREATE INDEX idx_user_comments_studio_session ON user_comments(studio_session_id, created_at DESC);
CREATE INDEX idx_user_comments_user ON user_comments(user_id);
```

### Table: `user_follows`

Stores user follow relationships.

```sql
CREATE TABLE user_follows (
    follower_id UUID NOT NULL REFERENCES auth.users(id),
    followed_id UUID NOT NULL REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (follower_id, followed_id),
    CHECK (follower_id != followed_id)
);

CREATE INDEX idx_user_follows_follower ON user_follows(follower_id);
CREATE INDEX idx_user_follows_followed ON user_follows(followed_id);
```

## RPC Functions

### 1. `rocklist_ingest_plays`

Ingests play events from Spotify and updates the `rocklist_stats` table. This is the core function that processes listening data.

**Input Parameters:**
- `p_events JSONB` - Array of play events, each containing:
  - `artistId` (or `artist_id`) TEXT - Spotify artist ID
  - `artistName` (or `artist_name`) TEXT - Artist name
  - `trackId` (or `track_id`) TEXT - Spotify track ID
  - `trackName` (or `track_name`) TEXT - Track name
  - `playedAt` TEXT - ISO8601 timestamp string
  - `durationMs` INTEGER - Duration in milliseconds
  - `region` TEXT - Region code (defaults to "GLOBAL")

**Output:**
- Returns JSONB with:
  - `success` BOOLEAN - Whether ingestion succeeded
  - `processed` INTEGER - Number of events processed
  - `errors` INTEGER - Number of errors encountered
  - `error_details` TEXT[] - Array of error messages
  - `last_ingested_played_at` TIMESTAMPTZ - Latest playedAt timestamp

**Behavior:**
- Processes each event in the array
- Upserts artist records into `artists` table
- Upserts/updates stats in `rocklist_stats` table:
  - Aggregates `play_count` (increments by 1)
  - Aggregates `total_ms_played` (adds durationMs)
  - Updates `last_played_at` to most recent timestamp
  - Calculates `score` as `total_ms_played` (milliseconds)
- Updates user's `last_ingested_played_at` in `profiles` table
- Handles errors gracefully, continuing with remaining events

**SQL Implementation:**

See `sql/rocklist_ingest_plays.sql` for full implementation.

### 2. `get_rocklist_user_state`

Returns the current user's last ingestion timestamp.

**Input Parameters:**
- None (uses `auth.uid()` to identify current user)

**Output Columns:**
- `last_ingested_played_at TIMESTAMPTZ` - Last ingested timestamp, or NULL if never ingested

**SQL Implementation:**

See `sql/get_rocklist_user_state.sql` for full implementation.

### 3. `get_rocklist_for_artist`

Returns the RockList for a specific artist with filtering by time range and region.

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
CREATE OR REPLACE FUNCTION get_rocklist_for_artist(
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
            rls.artist_id,
            a.name AS artist_name,
            a.image_url AS artist_image_url,
            rls.user_id,
            COALESCE(p.display_name, u.email, 'Anonymous') AS display_name,
            rls.score,
            RANK() OVER (ORDER BY rls.score DESC) AS rank,
            (rls.user_id = v_current_user_id) AS is_current_user
        FROM rocklist_stats rls
        INNER JOIN artists a ON a.spotify_id = rls.artist_id
        LEFT JOIN profiles p ON p.user_id = rls.user_id
        LEFT JOIN auth.users u ON u.id = rls.user_id
        WHERE rls.artist_id = p_artist_id
            AND rls.updated_at >= p_start_timestamp
            AND rls.updated_at <= p_end_timestamp
            AND (p_region IS NULL OR rls.region = p_region)
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

### 4. `get_my_rocklist_summary`

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
CREATE OR REPLACE FUNCTION get_my_rocklist_summary(
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
            rls.artist_id,
            rls.score,
            RANK() OVER (
                PARTITION BY rls.artist_id, COALESCE(rls.region, 'GLOBAL')
                ORDER BY rls.score DESC
            ) AS rank
        FROM rocklist_stats rls
        WHERE rls.user_id = v_current_user_id
            AND rls.updated_at >= p_start_timestamp
            AND rls.updated_at <= p_end_timestamp
            AND (p_region IS NULL OR rls.region = p_region)
    ),
    artist_info AS (
        SELECT DISTINCT
            rls.artist_id,
            a.name AS artist_name,
            a.image_url AS artist_image_url
        FROM rocklist_stats rls
        INNER JOIN artists a ON a.spotify_id = rls.artist_id
        WHERE rls.user_id = v_current_user_id
            AND rls.updated_at >= p_start_timestamp
            AND rls.updated_at <= p_end_timestamp
            AND (p_region IS NULL OR rls.region = p_region)
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

### 5. `post_rocklist_comment`

Inserts a comment for a RockList artist.

**Input Parameters:**
- `p_artist_id TEXT` - Spotify artist ID
- `p_content TEXT` - Comment content
- `p_region TEXT` - Region (nullable)

**Output:**
- Returns the created comment with all fields

**SQL Implementation:**

```sql
CREATE OR REPLACE FUNCTION post_rocklist_comment(
    p_artist_id TEXT,
    p_content TEXT,
    p_region TEXT DEFAULT NULL
)
RETURNS TABLE (
    id UUID,
    user_id UUID,
    display_name TEXT,
    content TEXT,
    created_at TIMESTAMPTZ,
    artist_id TEXT,
    studio_session_id UUID,
    comment_type TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_user_id UUID;
    v_comment_id UUID;
BEGIN
    v_current_user_id := auth.uid();
    v_comment_id := gen_random_uuid();
    
    INSERT INTO user_comments (id, user_id, artist_id, content, region)
    VALUES (v_comment_id, v_current_user_id, p_artist_id, p_content, p_region);
    
    RETURN QUERY
    SELECT
        uc.id,
        uc.user_id,
        COALESCE(p.display_name, u.email, 'Anonymous') AS display_name,
        uc.content,
        uc.created_at,
        uc.artist_id,
        uc.studio_session_id,
        'rocklist' AS comment_type
    FROM user_comments uc
    LEFT JOIN profiles p ON p.user_id = uc.user_id
    LEFT JOIN auth.users u ON u.id = uc.user_id
    WHERE uc.id = v_comment_id;
END;
$$;
```

### 6. `get_rocklist_comments_for_artist`

Returns comments for a specific artist's RockList.

**Input Parameters:**
- `p_artist_id TEXT` - Spotify artist ID
- `p_start_timestamp TIMESTAMPTZ` - Start of time range (for filtering)
- `p_end_timestamp TIMESTAMPTZ` - End of time range

**Output Columns:**
- `id UUID`
- `user_id UUID`
- `display_name TEXT`
- `content TEXT`
- `created_at TIMESTAMPTZ`

**SQL Implementation:**

```sql
CREATE OR REPLACE FUNCTION get_rocklist_comments_for_artist(
    p_artist_id TEXT,
    p_start_timestamp TIMESTAMPTZ,
    p_end_timestamp TIMESTAMPTZ
)
RETURNS TABLE (
    id UUID,
    user_id UUID,
    display_name TEXT,
    content TEXT,
    created_at TIMESTAMPTZ,
    artist_id TEXT,
    studio_session_id UUID,
    comment_type TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        uc.id,
        uc.user_id,
        COALESCE(p.display_name, u.email, 'Anonymous') AS display_name,
        uc.content,
        uc.created_at,
        uc.artist_id,
        uc.studio_session_id,
        'rocklist' AS comment_type
    FROM user_comments uc
    LEFT JOIN profiles p ON p.user_id = uc.user_id
    LEFT JOIN auth.users u ON u.id = uc.user_id
    WHERE uc.artist_id = p_artist_id
        AND uc.created_at >= p_start_timestamp
        AND uc.created_at <= p_end_timestamp
    ORDER BY uc.created_at DESC;
END;
$$;
```

### 7. `get_following_feed`

Returns comments from users the current user follows, across RockList and StudioSessions.

**Input Parameters:**
- `p_start_timestamp TIMESTAMPTZ` - Start of time range
- `p_end_timestamp TIMESTAMPTZ` - End of time range

**Output Columns:**
- `comment_id UUID`
- `user_id UUID`
- `display_name TEXT`
- `content TEXT`
- `created_at TIMESTAMPTZ`
- `artist_id TEXT` (nullable)
- `studio_session_id UUID` (nullable)
- `comment_type TEXT` - "rocklist" or "studio_session"

**SQL Implementation:**

```sql
CREATE OR REPLACE FUNCTION get_following_feed(
    p_start_timestamp TIMESTAMPTZ,
    p_end_timestamp TIMESTAMPTZ
)
RETURNS TABLE (
    comment_id UUID,
    user_id UUID,
    display_name TEXT,
    content TEXT,
    created_at TIMESTAMPTZ,
    artist_id TEXT,
    studio_session_id UUID,
    comment_type TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_user_id UUID;
BEGIN
    v_current_user_id := auth.uid();
    
    RETURN QUERY
    SELECT
        uc.id AS comment_id,
        uc.user_id,
        COALESCE(p.display_name, u.email, 'Anonymous') AS display_name,
        uc.content,
        uc.created_at,
        uc.artist_id,
        uc.studio_session_id,
        CASE
            WHEN uc.artist_id IS NOT NULL THEN 'rocklist'
            WHEN uc.studio_session_id IS NOT NULL THEN 'studio_session'
            ELSE 'unknown'
        END AS comment_type
    FROM user_comments uc
    INNER JOIN user_follows uf ON uf.followed_id = uc.user_id
    LEFT JOIN profiles p ON p.user_id = uc.user_id
    LEFT JOIN auth.users u ON u.id = uc.user_id
    WHERE uf.follower_id = v_current_user_id
        AND uc.created_at >= p_start_timestamp
        AND uc.created_at <= p_end_timestamp
    ORDER BY uc.created_at DESC;
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
    last_ingested_played_at TIMESTAMPTZ, -- Tracks last RockList ingestion timestamp
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_profiles_last_ingested ON profiles(last_ingested_played_at);
```

## Notes

- All RPCs use `SECURITY DEFINER` to ensure proper access control
- The functions automatically use `auth.uid()` to identify the current user
- Region filtering: NULL means Global, otherwise use ISO country codes
- Rankings use `RANK()` window function which handles ties correctly
- The RockList always includes top 20 + current user's entry if outside top 20
- Comments are extensible for both RockList and StudioSessions
- Feed aggregates comments from followed users across all comment types

