# Automatic RockList Ingestion Restored

## Summary

Automatic RockList data ingestion has been restored to ensure that listening data is continuously synchronized with the Supabase backend tables.

## Changes Made

### 1. RootAppView - Automatic Ingestion on Authentication
**File**: `Rockout/Views/RootAppView.swift`

- Added `.task` modifier to `MainTabView` that triggers ingestion when authenticated view appears
- Added ingestion trigger in `.onChange(of: scenePhase)` when app becomes active (periodic updates)
- Added ingestion trigger in `.onChange(of: authVM.authState)` when transitioning to authenticated state
- Created `triggerRockListIngestionIfNeeded()` helper method

### 2. RockOutApp - Ingestion After Spotify OAuth
**File**: `Rockout/App/RockOutApp.swift`

- Added automatic ingestion trigger after successful Spotify OAuth callback in `.onOpenURL`
- Ensures data ingestion starts immediately after user connects Spotify

### 3. SpotifyAuthService - Ingestion After Connection Save
**File**: `Rockout/Services/Spotify/SpotifyAuthService.swift`

- Added automatic ingestion trigger in `saveToDatabase()` method after successful connection save
- Triggers ingestion as soon as Spotify connection is established in the database

## How Automatic Ingestion Works

### Ingestion Triggers

1. **On App Launch (Authenticated Users)**
   - When app loads and user is authenticated, ingestion is triggered automatically

2. **When App Becomes Active**
   - Every time the app returns to foreground (e.g., after backgrounding or unlocking phone)
   - Triggers incremental ingestion to sync latest listening data

3. **After Spotify Connection**
   - Immediately after successful Spotify OAuth connection
   - Immediately after saving Spotify connection to database

4. **When Authenticating**
   - When transitioning from unauthenticated to authenticated state

### Ingestion Logic

The `checkAndTriggerInitialIngestionIfNeeded()` method in `RockListDataService` handles:

- **First-Time Users**: Performs initial bootstrap ingestion with:
  - Recently played tracks (last 50)
  - Top artists (long-term) with weighted virtual events
  - User profile and region data

- **Existing Users**: Performs incremental ingestion with:
  - Only tracks played since last ingestion
  - Updates existing stats without duplicating data

## Tables Populated

The ingestion populates these Supabase tables:

1. **`rocklist_stats`** - User listening statistics per artist
   - `user_id`, `artist_id`, `region`
   - `play_count`, `total_ms_played`, `score`
   - `updated_at`, `created_at`

2. **`artists`** - Artist metadata
   - `spotify_id` (primary key)
   - `name`, `image_url`
   - `created_at`

3. **`rocklist_user_state`** - Ingestion tracking
   - `user_id`, `last_ingested_played_at`
   - `updated_at`

## RPC Function Used

**`rocklist_ingest_plays`** - Supabase RPC function that:
- Accepts array of play events (JSONB)
- Upserts artist records
- Updates/creates rocklist_stats records
- Updates rocklist_user_state
- Handles region-based scoring

## Background Operation

All ingestion operations run in the background:
- Non-blocking UI operations
- Silent failures (logged but don't crash app)
- Automatic retries on next trigger
- Efficient incremental updates

## Logging

Watch for these log messages in Xcode console:

- `🔄 RockListDataService: Starting initial bootstrap ingestion...`
- `🔄 RockListDataService: Previous ingestion found, doing incremental update...`
- `✅ RockListDataService: Successfully ingested X events`
- `✅ RockListDataService: Initial bootstrap ingestion completed successfully`
- `✅ RockListDataService: Incremental ingestion completed`

## Testing Checklist

1. **First Time User**
   - ✅ Connect Spotify account
   - ✅ Ingestion should trigger automatically
   - ✅ Check logs for "initial bootstrap ingestion"
   - ✅ Verify data appears in RockList views

2. **Existing User**
   - ✅ Open app (already authenticated)
   - ✅ Ingestion should trigger on app launch
   - ✅ Check logs for "incremental update"
   - ✅ Verify new listening data is synced

3. **Periodic Updates**
   - ✅ Background the app
   - ✅ Play music on Spotify
   - ✅ Return to app
   - ✅ Ingestion should trigger automatically
   - ✅ New plays should appear in RockList

4. **Spotify Connection**
   - ✅ Connect Spotify from Profile tab
   - ✅ Ingestion should trigger immediately after connection
   - ✅ Data should be available shortly after

## Troubleshooting

### If Ingestion Doesn't Trigger

1. **Check Spotify Authorization**
   ```swift
   SpotifyAuthService.shared.isAuthorized() // Should return true
   ```

2. **Check Logs**
   - Look for error messages in Xcode console
   - Verify "Spotify not authorized" messages

3. **Verify Database Connection**
   - Check Supabase connection settings
   - Verify RPC function exists: `rocklist_ingest_plays`

4. **Manual Trigger**
   - Use "Sync Spotify Data" button in MyRockListView
   - Or call directly: `RockListDataService.shared.checkAndTriggerInitialIngestionIfNeeded()`

### Common Issues

- **"Spotify not authorized"**: User needs to connect Spotify first
- **No events ingested**: User may not have recent listening data
- **Database errors**: Check Supabase RLS policies and function permissions

## Next Steps

After restoring automatic ingestion:

1. ✅ Rebuild the app
2. ✅ Connect Spotify account (if not already connected)
3. ✅ Wait for automatic ingestion to complete (check logs)
4. ✅ Verify data appears in RockList views
5. ✅ Test periodic updates by backgrounding/foregrounding app

## Implementation Details

### Thread Safety
- All ingestion operations are marked `@MainActor`
- Async/await used for all network operations
- Background tasks don't block UI

### Error Handling
- Failures are logged but don't crash the app
- Retries happen automatically on next trigger
- User-facing errors are shown in UI where appropriate

### Performance
- Incremental ingestion only fetches new data
- Batch processing of events
- Efficient database upserts

