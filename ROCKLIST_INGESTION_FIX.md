# RockList Ingestion Fix

## Problem
The RockList wasn't being populated with data because ingestion wasn't being triggered automatically when viewing the My RockList tab.

## Changes Made

### 1. Added Automatic Ingestion Trigger
- **File**: `Rockout/ViewModels/RockList/MyRockListViewModel.swift`
- Added `triggerIngestionIfNeeded()` method that:
  - Checks if Spotify is authorized
  - Checks if data has been ingested before
  - Triggers initial ingestion if no data exists
  - Triggers incremental ingestion if data exists but is outdated
  - Automatically reloads data after ingestion completes

### 2. Updated MyRockListView
- **File**: `Rockout/Views/RockList/MyRockListView.swift`
- Added automatic ingestion trigger when view appears
- Added "Sync Spotify Data" button in empty state for manual trigger
- Improved empty state messaging

## How It Works Now

1. **On App Launch**: 
   - Ingestion is triggered in `RootAppView` when authenticated (existing behavior)

2. **When Viewing My RockList Tab**:
   - View automatically loads existing data
   - If no data is found, ingestion is triggered automatically in the background
   - After ingestion, data is automatically reloaded

3. **Manual Trigger**:
   - Users can tap "Sync Spotify Data" button in the empty state
   - Refresh button in navigation bar will reload data

## Testing Checklist

1. **First Time User (No Data)**:
   - ✅ Open My RockList tab
   - ✅ Should see "No Rankings Yet" message
   - ✅ "Sync Spotify Data" button should appear
   - ✅ Tap button - ingestion should run
   - ✅ After completion, rankings should appear

2. **Existing User (Has Data)**:
   - ✅ Open My RockList tab
   - ✅ Rankings should load immediately
   - ✅ Incremental update happens in background

3. **Check Logs**:
   - Look for logs starting with:
     - `🔄 MyRockListViewModel:` - Ingestion triggered
     - `✅ MyRockListViewModel:` - Ingestion completed
     - `⚠️ MyRockListViewModel:` - Ingestion errors

## Troubleshooting

### If RockList Still Shows "No Rankings Yet":

1. **Check Spotify Authorization**:
   - Ensure Spotify is connected (Profile tab)
   - Check Xcode console for Spotify auth errors

2. **Check Database Schema**:
   - Run the `fix_schema_migration.sql` script in Supabase SQL Editor
   - This ensures the `artists` table has the correct schema

3. **Check Ingestion Logs**:
   - Look in Xcode console for:
     - `RockListDataService: Starting initial bootstrap ingestion...`
     - `RockListDataService: Successfully ingested X events`
     - Any error messages

4. **Manual Database Check**:
   - In Supabase SQL Editor, run:
   ```sql
   SELECT COUNT(*) FROM rocklist_stats WHERE user_id = auth.uid();
   SELECT COUNT(*) FROM artists;
   ```
   - This will show if data exists in the database

5. **Verify RPC Function**:
   - Check that `rocklist_ingest_plays` function exists:
   ```sql
   SELECT routine_name 
   FROM information_schema.routines 
   WHERE routine_schema = 'public' 
   AND routine_name = 'rocklist_ingest_plays';
   ```

### Common Issues:

1. **"column a.spotify_id does not exist"**:
   - Run `fix_schema_migration.sql` in Supabase

2. **No data after ingestion**:
   - Check that Spotify API is returning data
   - Check Supabase RLS (Row Level Security) policies
   - Verify user is authenticated in Supabase

3. **Ingestion never completes**:
   - Check network connectivity
   - Check Supabase connection settings
   - Verify Spotify API tokens are valid

## Next Steps

After applying these changes:
1. Rebuild the app
2. Open My RockList tab
3. If empty, tap "Sync Spotify Data" button
4. Wait for ingestion to complete
5. Rankings should appear automatically

If issues persist, check the Xcode console logs for detailed error messages.

