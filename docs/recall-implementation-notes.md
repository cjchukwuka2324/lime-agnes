# Recall Implementation Notes

## Phase 0: Repository Analysis

### Tab Bar Structure
- **File**: `Rockout/Views/Main/MainTabView.swift`
- **Framework**: SwiftUI `TabView`
- **Current Tabs**:
  - Tag 0: GreenRoom (FeedView)
  - Tag 1: SoundPrint (SoundPrintView) - **TO REMOVE**
  - Tag 2: StudioSessions (StudioSessionsView)
  - Tag 3: Profile (ProfileView)
- **Swipe Gesture**: Custom edge drag gesture for tab navigation (max tab = 3, needs update to 2)

### SoundPrint/RockList File Locations

#### SoundPrint Files to Delete:
- `Rockout/Views/SoundPrint/` (entire directory)
  - `SoundPrintView.swift`
  - `SoundPrintCard.swift`
  - ` SoundPrintExportCard.swift`
  - `Features/` subdirectory (6 feature views)
  - `Components/` subdirectory
  - Other supporting files
- `Rockout/Views/Onboarding/Slides/SoundPrintSlide.swift`
- `Assets/OnboardingVideos/soundprint_onboarding.mp4`
- Onboarding screen reference in `OnboardingFlowView.swift` (screen 2)

#### RockList Files to Delete:
- `Rockout/Views/RockList/` (entire directory)
  - `RockListView.swift`
  - `MyRockListView.swift`
  - `ScoreBreakdownView.swift`
- `Rockout/Services/RockList/` (entire directory)
  - `RockListService.swift`
  - `RockListDataService.swift`
- `Rockout/ViewModels/RockList/` (entire directory)
  - `RockListViewModel.swift`
  - `MyRockListViewModel.swift`
- `Rockout/Models/RockList/` (entire directory)
  - `RockListModels.swift`
  - `RockListFilters.swift`
  - `ListenerScoreBreakdown.swift`
- `Rockout/Views/Onboarding/Slides/RockListsSlide.swift`
- `Assets/OnboardingVideos/rocklist_onboarding2.mp4`
- Onboarding screen reference in `OnboardingFlowView.swift` (screen 3)
- Navigation references in `FeedView.swift` and `FeedCardView.swift`

### GreenRoom Post Creation Flow

**Table**: `posts`
**RPC Function**: `create_post`

**Required Parameters** (from `sql/posts_enhancements_schema.sql`):
- `p_text` TEXT
- `p_image_urls` TEXT[] (default: empty array)
- `p_video_url` TEXT (optional)
- `p_audio_url` TEXT (optional)
- `p_parent_post_id` UUID (optional, for replies)
- `p_leaderboard_entry_id` TEXT (optional)
- `p_leaderboard_artist_name` TEXT (optional)
- `p_leaderboard_rank` INT (optional)
- `p_leaderboard_percentile_label` TEXT (optional)
- `p_leaderboard_minutes_listened` INT (optional)
- `p_reshared_post_id` UUID (optional)
- `p_spotify_link_url` TEXT (optional)
- `p_spotify_link_type` TEXT (optional)
- `p_spotify_link_data` JSONB (optional)
- `p_poll_question` TEXT (optional)
- `p_poll_type` TEXT (optional)
- `p_poll_options` JSONB (optional)
- `p_background_music_spotify_id` TEXT (optional)
- `p_background_music_data` JSONB (optional)
- `p_mentioned_user_ids` UUID[] (optional, from `apply_all_changes.sql`)

**Service**: `SupabaseFeedService.createPost()`
**Usage Pattern**: 
```swift
let response = try await supabase
    .rpc("create_post", params: params)
    .execute()
```

**Post Model**: `Rockout/Models/Feed/Post.swift`
- Supports optional `spotifyLink`, `poll`, `backgroundMusic`, `mentionedUserIds`
- For Recall posts, we can use `text` field and optionally add metadata in a future enhancement

### Supabase Edge Function Invocation Pattern

**Current Pattern**: Edge functions are called from database triggers (e.g., `push_notification_trigger.sql` uses `pg_net.http_post`)

**For Client-Side Invocation** (what we need for Recall):
- Use Supabase Swift client: `client.functions.invoke(functionName, options)`
- Pattern not currently used in codebase, but standard Supabase pattern
- Example structure:
```swift
let response = try await supabase.functions.invoke(
    "recall_create",
    options: FunctionInvokeOptions(
        body: requestBody,
        headers: ["Content-Type": "application/json"]
    )
)
```

**Edge Function Structure** (from existing functions):
- TypeScript/Deno
- Uses `serve()` from `https://deno.land/std@0.168.0/http/server.ts`
- CORS headers required
- Environment variables: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` (auto-provided)
- Custom secrets: `OPENAI_API_KEY` (to be set)

### Supabase Storage Upload Pattern

**Service**: `SupabaseStorageService`
**Pattern**:
```swift
try await client.storage
    .from("bucket-name")
    .upload(path: "path/to/file", file: data)
```

**For Recall**:
- Bucket: `recall-media` (private)
- Path pattern: `{userId}/{recallId}/voice.m4a` or `{userId}/{recallId}/image.jpg`
- Content types: `audio/m4a`, `image/jpeg`

### Realtime Subscriptions

**Current Usage**: Not extensively used in codebase
- `NotificationService` uses polling
- `FeedViewModel` uses `FeedStore` with Combine publishers
- For Recall, we'll use polling initially (simpler, matches existing patterns)

### UI Framework

**Framework**: SwiftUI
- Modern SwiftUI patterns
- Custom components in `Rockout/Views/Shared/`
- Gradient backgrounds (`AnimatedGradientBackground`)
- Glass morphism effects (`.glassMorphism()`)
- Card-based layouts

### Studio Sessions Tables/Services

**Not removing** - keeping Studio Sessions feature
- Tables: `albums`, `tracks`, `album_collaborators`, etc.
- Services: `AlbumService`, `ShareService`, `CollaboratorService`
- Views: `StudioSessionsView` and related

## Implementation Strategy

1. **Remove SoundPrint/RockList** first (clean slate)
2. **Create Supabase schema** (SQL migration)
3. **Create Edge Functions** (TypeScript)
4. **Create Swift models and service**
5. **Create UI views** (SwiftUI)
6. **Wire into tab bar**
7. **Test end-to-end**

## Key Decisions

- **Edge Function Invocation**: Client-side via `client.functions.invoke()` (new pattern for this codebase)
- **Status Updates**: Polling-based (matches existing patterns, simpler than realtime)
- **Post Type for Recall**: Use existing `create_post` RPC, store recall metadata in `text` field or future JSONB column
- **Auto Ask the Crowd**: Edge function `recall_process` will automatically call `recall_ask_crowd` when confidence < 0.65
- **OCR**: On-device using iOS Vision framework (no external API needed)

