# Listener Score System Documentation

## Overview

The Listener Score system provides a unified, weighted scoring mechanism to rank users per artist in the RockList feature. The score ranges from 0-100 and is calculated using six normalized indices that measure different aspects of user engagement with an artist.

## Formula

```
ListenerScore = 
  (0.40 * StreamIndex) +
  (0.25 * DurationIndex) +
  (0.15 * CompletionIndex) +
  (0.10 * RecencyIndex) +
  (0.05 * EngagementIndex) +
  (0.05 * FanSpreadIndex)
```

All indices are normalized to 0-1 range, and the final score is scaled to 0-100.

## Index Definitions

### 1. StreamIndex (40% weight)
- **Formula**: `user_stream_count / max_stream_count_for_this_artist`
- **Description**: Measures how many times the user has streamed tracks by the artist, normalized against the top listener
- **Penalty**: If average completion rate < 20%, StreamIndex is reduced by 30% to discourage spammy skipping

### 2. DurationIndex (25% weight)
- **Formula**: `user_listen_minutes / max_listen_minutes_for_this_artist`
- **Description**: Measures total listening time, normalized against the top listener
- **Unit**: Minutes (converted from milliseconds)

### 3. CompletionIndex (15% weight)
- **Formula**: `total_listened_time / total_playable_time_for_artist_tracks_user_played`
- **Description**: Measures how completely users listen to tracks (not just skipping)
- **Range**: 0-1 (0 = always skipped, 1 = always completed)

### 4. RecencyIndex (10% weight)
- **Formula**: `exp(-λ * days_since_last_listen)` where λ ≈ 0.05
- **Description**: Exponential decay based on days since last listen
- **Behavior**: 
  - Recent listens (0-7 days): High score (0.7-1.0)
  - Medium recency (7-30 days): Medium score (0.2-0.7)
  - Old listens (30+ days): Low score (0.0-0.2)

### 5. EngagementIndex (5% weight)
- **Formula**: `engagement_raw / max_engagement_raw_for_this_artist`
- **Raw Engagement**: `(album_saves * 3) + (track_likes * 1) + (playlist_adds * 2)`
- **Description**: Measures explicit user engagement (saves, likes, playlist additions)

### 6. FanSpreadIndex (5% weight)
- **Formula**: `unique_tracks_listened_by_user_for_artist / total_tracks_in_artist_catalog`
- **Description**: Measures how broadly the user listens across the artist's catalog
- **Capped**: Maximum value is 1.0 (even if user listened to more tracks than catalog size)

## Database Schema

### Core Tables

#### `rocklist_stats` (Extended)
- `unique_track_count` - Number of unique tracks listened to
- `avg_completion_rate` - Average completion rate (0-1)
- `engagement_score` - Raw engagement score
- `listener_score` - Calculated unified score (0-100)
- `score_updated_at` - Timestamp when score was last calculated

#### `rocklist_play_events`
- Stores detailed play events with `played_duration_ms` and `track_duration_ms`
- Used for calculating completion rates and tracking unique tracks

#### `user_artist_engagement`
- `album_saves` - Number of albums saved
- `track_likes` - Number of tracks liked
- `playlist_adds` - Number of playlist additions

#### `artists` (Extended)
- `total_track_count` - Cached catalog size
- `catalog_updated_at` - When catalog was last fetched

#### `listener_score_config`
- Singleton table with configurable weights and parameters
- Allows tuning the formula without code changes

## Calculation Flow

1. **Data Ingestion**: `rocklist_ingest_plays()` stores play events and updates aggregates
2. **Score Calculation**: `calculate_listener_score(user_id, artist_id, region)` computes score
3. **Batch Recalculation**: `recalculate_artist_listener_scores(artist_id, region)` processes all users
4. **Cache Refresh**: `refresh_artist_leaderboard_cache()` updates cached leaderboard
5. **Scheduled Job**: Edge Function runs every 15 minutes to recalculate scores

## API Functions

### `calculate_listener_score(p_user_id, p_artist_id, p_region)`
- Calculates and updates listener score for a single user-artist pair
- Returns the calculated score (0-100)

### `recalculate_artist_listener_scores(p_artist_id, p_region)`
- Recalculates scores for all users of an artist
- Returns processing statistics

### `refresh_artist_leaderboard_cache(p_artist_id, p_region)`
- Clears and rebuilds leaderboard cache with top 100 users
- Should be called after score recalculation

### `get_rocklist_for_artist(...)`
- Returns leaderboard sorted by `listener_score` (not legacy `score`)
- Filters by `last_played_at` (not `updated_at`) for time ranges

## Scheduled Jobs

### Recalculate Listener Scores (Every 15 minutes)
- Edge Function: `recalculate_listener_scores`
- Processes artists with active listeners (last 30 days)
- Recalculates scores and refreshes cache

### Sync Artist Engagement (On-demand or periodic)
- Edge Function: `sync_artist_engagement`
- Fetches engagement data from Spotify API
- Updates `user_artist_engagement` table

## Configuration

Weights and parameters can be adjusted in `listener_score_config` table:

- `stream_weight`: 0.40 (default)
- `duration_weight`: 0.25 (default)
- `completion_weight`: 0.15 (default)
- `recency_weight`: 0.10 (default)
- `engagement_weight`: 0.05 (default)
- `fan_spread_weight`: 0.05 (default)
- `recency_decay_lambda`: 0.05 (default)
- `low_completion_threshold`: 0.20 (default)
- `low_completion_penalty`: 0.30 (default)

## Performance Considerations

- **Indexes**: All query paths are indexed for efficient leaderboard access
- **Caching**: Leaderboard cache stores top 100 users per artist
- **Batch Processing**: Scores are recalculated in batches to avoid overwhelming the database
- **Incremental Updates**: Only artists with recent activity are processed

## Migration Notes

- Existing `score` field is kept for backward compatibility
- New `listener_score` field is calculated and used for ranking
- Legacy scores are gradually replaced as recalculation runs
- iOS app uses `activeScore` computed property (prefers `listenerScore`, falls back to `score`)

## Future Enhancements

- Real-time score updates when new play events are ingested
- Per-region score normalization
- Time-weighted scoring (recent activity weighted more)
- Genre-specific scoring adjustments

