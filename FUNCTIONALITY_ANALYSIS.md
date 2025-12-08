# RockOut App - Complete Functionality Analysis

## Executive Summary

RockOut is a comprehensive music social platform that combines Spotify integration, social networking, music discovery, and collaborative music creation. The app features a sophisticated listener scoring system, real-time social feeds, public album sharing, and advanced music analytics.

---

## 1. Core Features & Modules

### 1.1 Authentication & User Management

**Capabilities:**
- Email/password authentication via Supabase
- Google OAuth integration
- Password reset functionality
- Session management with automatic token refresh
- User profile management with display names, handles, and avatars
- Social media profile links (Instagram, Twitter, TikTok)

**Implementation:**
- `AuthService` - Handles authentication flows
- `SupabaseAuthService` - Supabase-specific auth implementation
- `AuthViewModel` - Manages authentication state
- Onboarding flow for first-time users

**Key Files:**
- `Rockout/Views/Auth/` - All authentication UI
- `Rockout/Services/AuthService.swift`
- `Rockout/ViewModels/Auth/AuthViewModel.swift`

---

### 1.2 Spotify Integration

**Capabilities:**
- Full Spotify OAuth authentication
- Access to user's Spotify listening data
- Fetch top artists, tracks, and genres
- Create and manage Spotify playlists
- Real-time listening history ingestion
- Playlist creation and management

**Features:**
- **Spotify Connect** - Seamless authentication flow
- **Listening Data Sync** - Automatic ingestion of play history
- **Playlist Management** - Create custom playlists from app
- **Token Management** - Automatic token refresh and storage

**Implementation:**
- `SpotifyAuthService` - Handles OAuth and token management
- `SpotifyAPI` - Core API client for Spotify endpoints
- `SpotifyPlaylistService` - Playlist creation and management
- `SpotifyConnectionService` - Manages connection state

**Key Files:**
- `Rockout/Services/Spotify/`
- `Rockout/Views/Auth/ConnectSpotifyView.swift`

---

### 1.3 SoundPrint (Music Analytics & Discovery)

**Capabilities:**
SoundPrint is a comprehensive music analytics dashboard that provides deep insights into a user's listening habits.

**Features:**

#### Overview Tab
- User profile with Spotify integration
- Fan personality analysis
- Quick stats summary

#### Artists Tab
- Top artists carousel
- Artist listening statistics
- Genre distribution

#### Tracks Tab
- Top tracks list
- Track listening patterns
- Play count analytics

#### Genres Tab
- Genre breakdown with visualizations
- Genre preferences over time
- Animated genre bar charts

#### Stats Tab
- **Listening Stats**: Total listening time, track count, artist count
- **Audio Features**: Average energy, danceability, valence, tempo
- **Year in Music**: Annual listening summary
- **Monthly Evolution**: Listening trends over months

#### Time Analysis Tab
- **Time Patterns**: Listening habits by time of day
- **Seasonal Trends**: Music preferences by season
- **Listening Schedule**: Peak listening times

#### Discovery Tab
- **Discover Weekly Integration**: Spotify's personalized recommendations
- **Release Radar**: New releases from followed artists
- **Recently Discovered**: New artists and tracks
- **Discovery Engine**: AI-powered music recommendations

#### Social Tab
- **Taste Compatibility**: Compare music taste with other users
- **Social Sharing**: Share SoundPrint insights
- **Friend Comparisons**: See what friends are listening to

#### Mood Tab
- **Mood Playlists**: Curated playlists by mood
- **Mood Context**: Music analysis by emotional context
- **Mood Patterns**: Listening habits by mood

#### Analytics Tab
- **Advanced Analytics**: Deep dive into listening patterns
- **Music Taste Diversity**: Catalog breadth analysis
- **Custom Playlists**:
  - Real You Mix - Personalized discovery
  - SoundPrint Forecast - Predictive recommendations
  - Discovery Bundle - Curated discovery playlists

**Implementation:**
- `SoundPrintView` - Main view with tab navigation
- `SpotifyAPI` - Fetches all Spotify data
- Feature-specific views in `Rockout/Views/SoundPrint/Features/`

**Key Files:**
- `Rockout/Views/SoundPrint/SoundPrintView.swift`
- `Rockout/Views/SoundPrint/Features/` (6 feature views)
- `Rockout/Services/Spotify/SpotifyAPI.swift`

---

### 1.4 RockList (Listener Leaderboards)

**Capabilities:**
RockList is a competitive leaderboard system that ranks users based on their listening engagement with specific artists.

#### Listener Score System
- **Unified Scoring (0-100)**: Combines 6 weighted indices:
  - **Stream Index (40%)**: Number of streams normalized
  - **Duration Index (25%)**: Total listening time
  - **Completion Index (15%)**: How completely tracks are listened to
  - **Recency Index (10%)**: Exponential decay based on last listen
  - **Engagement Index (5%)**: Album saves, track likes, playlist adds
  - **Fan Spread Index (5%)**: Catalog breadth (unique tracks / total catalog)

#### Features:
- **Artist Leaderboards**: Rank users per artist by region
- **My RockList**: View your rankings across all artists
- **Score Breakdown**: Detailed view of score components
- **Time-based Filtering**: Rankings for specific time periods
- **Region Filtering**: Global or country-specific rankings
- **Real-time Updates**: Scores recalculated every 15 minutes
- **Cached Leaderboards**: Fast queries with top 100 cache

#### Database Architecture:
- `rocklist_stats` - Aggregated listening statistics
- `rocklist_play_events` - Detailed play event tracking
- `user_artist_engagement` - Engagement metrics (saves, likes)
- `artist_leaderboard_cache` - Cached top 100 rankings
- `listener_score_config` - Configurable scoring weights

#### Backend Functions:
- `rocklist_ingest_plays()` - Processes Spotify play events
- `calculate_listener_score()` - Computes unified score
- `recalculate_artist_listener_scores()` - Batch recalculation
- `refresh_artist_leaderboard_cache()` - Cache refresh
- `get_rocklist_for_artist()` - Leaderboard query
- `get_my_rocklist_summary()` - User's rankings
- `get_listener_score_breakdown()` - Detailed score components

#### Scheduled Jobs:
- **Score Recalculation**: Edge function runs every 15 minutes
- **Engagement Sync**: Syncs engagement data from Spotify API
- **Catalog Sync**: Updates artist catalog sizes

**Implementation:**
- `RockListService` - Core service for RockList operations
- `RockListDataService` - Handles data ingestion
- `RockListViewModel` - View model for UI
- `ScoreBreakdownView` - Detailed score visualization

**Key Files:**
- `Rockout/Views/RockList/RockListView.swift`
- `Rockout/Views/RockList/ScoreBreakdownView.swift`
- `Rockout/Services/RockList/`
- `sql/calculate_listener_score.sql`
- `docs/listener_score_system.md`

---

### 1.5 Social Feed

**Capabilities:**
A comprehensive social media feed for music-related content sharing and interaction.

#### Feed Types:
- **For You**: Region-based personalized feed
- **Following**: Posts from users you follow
- **Trending**: Posts with trending hashtags

#### Post Features:
- **Text Posts**: Rich text with hashtag support
- **Image Posts**: Multiple image support with slideshow
- **Video Posts**: Full video playback with controls
- **Audio Posts**: Audio file playback
- **Spotify Links**: Embedded Spotify track/album links
- **Leaderboard Attachments**: Share RockList rankings
- **Polls**: Interactive polls with voting
- **Background Music**: Add background music to posts
- **Thread Replies**: Nested reply system

#### Interactions:
- **Likes**: Like/unlike posts
- **Replies**: Comment on posts with full threading
- **Shares**: Share posts (future)
- **Hashtags**: Automatic hashtag detection and trending
- **Mentions**: User mention support (future)

#### Media Features:
- **Image Upload**: Multiple image selection
- **Video Upload**: Video recording and selection
- **Full-screen Media**: Immersive media viewing
- **Image Cropping**: Built-in image editor
- **Video Player**: Custom video player with controls

#### Post Composition:
- **Rich Composer**: Multi-media post creation
- **Draft Saving**: Save drafts (future)
- **Media Preview**: Preview before posting
- **Hashtag Suggestions**: Auto-complete hashtags

**Implementation:**
- `SupabaseFeedService` - Backend feed operations
- `FeedViewModel` - Feed state management
- `PostComposerView` - Post creation UI
- `FeedCardView` - Post display component
- `FeedMediaService` - Media handling

**Key Files:**
- `Rockout/Views/Feed/FeedView.swift`
- `Rockout/Views/Feed/PostComposerView.swift`
- `Rockout/Services/Feed/`
- `sql/get_feed_posts_paginated.sql`

---

### 1.6 Studio Sessions (Music Creation & Collaboration)

**Capabilities:**
A full-featured music creation and collaboration platform for artists and producers.

#### Album Management:
- **Create Albums**: Create albums with title, artist name, cover art
- **Public/Private Albums**: Control album visibility
- **Edit Albums**: Update album details and visibility
- **Delete Albums**: Remove albums (with proper permissions)
- **Album Tabs**:
  - My Albums: User's own albums
  - Shared with You: Albums shared by others
  - Collaborations: Collaborative albums
  - Discoveries: Discovered public albums

#### Track Management:
- **Upload Tracks**: Upload audio files from device
- **Track Versions**: Version history and management
- **Track Details**: Edit track metadata
- **Play Count**: Track play statistics
- **Play Breakdown**: Detailed play analytics per track

#### Sharing & Collaboration:
- **Share Links**: Generate shareable links for albums
- **Link Expiration**: Set expiration dates for shares
- **Indefinite Shares**: Share links that never expire
- **Revoke Access**: Revoke share links at any time
- **Collaboration Mode**: Allow others to edit albums
- **View-only Mode**: Share for viewing only
- **Accept Shared Albums**: Accept and add shared albums

#### Discovery:
- **Public Albums**: Discover public albums by other users
- **Search by User**: Search public albums by username/email
- **Discover Feed**: Curated feed of public albums
- **Album Cards**: Beautiful album discovery cards

#### Analytics:
- **Track Play Count**: Track how many times tracks are played
- **Play Breakdown View**: Detailed analytics per track
- **Saved Users**: See who saved your albums
- **Collaborator Management**: Add/remove collaborators

**Implementation:**
- `AlbumService` - Album CRUD operations
- `TrackService` - Track management
- `ShareService` - Sharing and collaboration
- `TrackPlayService` - Play tracking and analytics
- `CollaboratorService` - Collaboration management

**Key Files:**
- `Rockout/Views/StudioSessions/StudioSessionsView.swift`
- `Rockout/Services/Supabase/AlbumService.swift`
- `Rockout/Services/Supabase/ShareService.swift`
- `sql/add_public_albums.sql`
- `sql/add_share_link_expiration.sql`
- `sql/add_track_play_counting.sql`

---

### 1.7 Social Graph (Following & Discovery)

**Capabilities:**
Complete social networking features for user connections and discovery.

#### Features:
- **Follow/Unfollow**: Follow other users
- **Followers List**: View who follows you
- **Following List**: View who you follow
- **Mutuals**: Find mutual connections
- **User Search**: Search users by name, handle, or email
- **Paginated Search**: Efficient user search with pagination
- **Suggested Follows**: AI-powered user recommendations
- **Contacts Integration**: Find users from contacts (future)

#### Profile Features:
- **User Profiles**: View other users' profiles
- **Profile Stats**: Followers, following, posts count
- **Profile Posts**: View user's posts, replies, and likes
- **Social Media Links**: Instagram, Twitter, TikTok links
- **Post Notifications**: Enable/disable notifications for specific users

**Implementation:**
- `SupabaseSocialGraphService` - Core social graph operations
- `SuggestedFollowService` - User recommendations
- `ContactsService` - Contacts integration (future)

**Key Files:**
- `Rockout/Services/Social/SupabaseSocialGraphService.swift`
- `Rockout/Views/Profile/UserProfileDetailView.swift`
- `sql/fix_follower_system.sql`

---

### 1.8 Notifications System

**Capabilities:**
Comprehensive notification system with both in-app and push notifications.

#### Notification Types:
- **New Follower**: Someone started following you
- **Post Like**: Someone liked your post
- **Post Reply**: Someone replied to your post
- **RockList Rank**: Your rank improved on a RockList
- **New Post**: Someone you follow posted (if enabled)

#### Features:
- **In-App Notifications**: Stored in Supabase, displayed in-app
- **Push Notifications**: APNs integration for iOS
- **Deep Linking**: Notifications link to relevant content
- **Read/Unread Status**: Track notification read state
- **Notification Badge**: Unread count indicator
- **Auto-Creation**: Database triggers auto-create notifications
- **Post Notifications Toggle**: Enable/disable per user

#### Architecture:
- **Database Triggers**: Auto-create notifications on events
- **Edge Function**: Sends push notifications via APNs
- **Device Token Management**: Register and manage device tokens
- **Notification Service**: Fetch and manage notifications

**Implementation:**
- `NotificationService` - Fetch notifications
- `DeviceTokenService` - Manage device tokens
- `NotificationsView` - Display notifications
- Edge function: `send_push_notification`

**Key Files:**
- `Rockout/Views/Notifications/NotificationsView.swift`
- `Rockout/Services/Notifications/`
- `sql/notifications_schema.sql`
- `sql/notification_triggers.sql`
- `sql/push_notification_trigger.sql`

---

### 1.9 User Profiles

**Capabilities:**
Comprehensive user profile management and viewing.

#### Features:
- **Profile Viewing**: View your own and others' profiles
- **Profile Editing**: Edit display name, username, bio
- **Social Media Links**: Add Instagram, Twitter, TikTok handles
- **Profile Picture**: Upload and manage profile pictures
- **Profile Stats**: Followers, following, posts count
- **Profile Sections**:
  - Posts: User's posts
  - Replies: User's replies
  - Likes: Posts user liked
  - Mutuals: Mutual connections

#### Settings:
- **Account Settings**: Manage account preferences
- **Spotify Connection**: Connect/disconnect Spotify
- **Notification Preferences**: Control notification settings

**Implementation:**
- `UserProfileService` - Profile operations
- `UserProfileViewModel` - Profile state management
- `ProfileView` - Main profile UI

**Key Files:**
- `Rockout/Views/Profile/ProfileView.swift`
- `Rockout/Services/UserProfileService.swift`

---

### 1.10 Onboarding

**Capabilities:**
Comprehensive onboarding experience for new users.

#### Features:
- **Onboarding Flow**: Multi-step onboarding process
- **Video Slides**: Animated onboarding videos
- **Feature Introduction**: 
  - GreenRoom (Feed)
  - SoundPrint
  - RockLists
  - Studio Sessions
- **Signup Integration**: Seamless signup during onboarding
- **Skip Option**: Option to skip onboarding

**Implementation:**
- `OnboardingFlowView` - Main onboarding coordinator
- `OnboardingSlideView` - Individual slide component
- Video slides for each major feature

**Key Files:**
- `Rockout/Views/Onboarding/OnboardingFlowView.swift`
- `Rockout/Views/Onboarding/Slides/`

---

## 2. Technical Architecture

### 2.1 Backend (Supabase)

#### Database Schema:
- **User Management**: `profiles`, `auth.users`
- **Social Graph**: `user_follows`, `user_comments`
- **Feed**: `posts`, `post_likes`, `post_replies`
- **RockList**: `rocklist_stats`, `rocklist_play_events`, `artists`
- **Studio Sessions**: `albums`, `tracks`, `shareable_links`, `collaborators`
- **Notifications**: `notifications`, `device_tokens`
- **Engagement**: `user_artist_engagement`

#### RPC Functions:
- 20+ custom PostgreSQL functions for complex operations
- Score calculation functions
- Leaderboard queries
- Feed pagination
- User search

#### Edge Functions:
- `recalculate_listener_scores` - Scheduled score updates
- `sync_artist_engagement` - Engagement data sync
- `send_push_notification` - Push notification delivery

#### Database Features:
- **Row Level Security (RLS)**: Secure data access
- **Triggers**: Auto-create notifications, update aggregates
- **Indexes**: Optimized queries for performance
- **Caching**: Leaderboard cache for fast queries

### 2.2 iOS App Architecture

#### Design Patterns:
- **MVVM**: Model-View-ViewModel architecture
- **Protocol-Oriented**: Service protocols for testability
- **Singleton Services**: Shared service instances
- **ObservableObject**: SwiftUI state management

#### Key Components:
- **Services Layer**: Business logic and API calls
- **ViewModels**: State management and UI logic
- **Views**: SwiftUI presentation layer
- **Models**: Data structures and business models

#### Technologies:
- **SwiftUI**: Modern declarative UI framework
- **Combine**: Reactive programming
- **Async/Await**: Modern concurrency
- **Supabase Swift SDK**: Backend integration
- **Spotify iOS SDK**: Spotify integration

---

## 3. Data Flow & Integrations

### 3.1 Spotify Data Flow

1. **Authentication**: User connects Spotify account
2. **Token Management**: Store and refresh Spotify tokens
3. **Data Fetching**: Fetch listening history, top artists/tracks
4. **Ingestion**: Process play events into RockList system
5. **Score Calculation**: Calculate listener scores
6. **Leaderboard Updates**: Update rankings

### 3.2 Feed Data Flow

1. **Post Creation**: User creates post with media
2. **Media Upload**: Upload to Supabase Storage
3. **Post Storage**: Store post in database
4. **Feed Aggregation**: Aggregate posts by feed type
5. **Real-time Updates**: Listen for new posts
6. **Interaction Tracking**: Track likes, replies

### 3.3 Notification Flow

1. **Event Trigger**: User action (follow, like, reply)
2. **Database Trigger**: Auto-create notification
3. **Push Trigger**: Trigger push notification function
4. **APNs Delivery**: Send push via Apple Push Notification service
5. **In-App Display**: Show notification in app
6. **Deep Link**: Navigate to relevant content

---

## 4. Advanced Features

### 4.1 Listener Score Algorithm

**Sophisticated scoring system** that combines multiple engagement metrics:
- Normalized indices (0-1 range)
- Weighted combination (configurable weights)
- Penalties for low completion (skip detection)
- Recency decay (exponential)
- Catalog breadth measurement
- Engagement tracking (saves, likes)

### 4.2 Public Album Discovery

**Discovery system** for finding public music:
- Search by username/email
- Public album feed
- Album cards with metadata
- Saved users tracking

### 4.3 Share Link Management

**Advanced sharing controls**:
- Expiration dates
- Indefinite shares
- Revocation capability
- Collaboration vs view-only modes

### 4.4 Track Play Analytics

**Detailed play tracking**:
- Play count per track
- Play breakdown analytics
- User engagement metrics
- Time-based analytics

---

## 5. User Experience Features

### 5.1 Navigation
- **Tab-based Navigation**: Feed, SoundPrint, Studio Sessions, Profile
- **Swipe Gestures**: Swipe between tabs
- **Deep Linking**: Navigate from notifications
- **Navigation Stack**: Proper navigation hierarchy

### 5.2 Media Handling
- **Image Picker**: Select from photo library
- **Camera Integration**: Take photos/videos
- **Video Player**: Custom video playback
- **Audio Player**: Background audio playback
- **Media Caching**: Efficient media loading

### 5.3 UI/UX
- **Glassmorphism Design**: Modern UI with blur effects
- **Dark Theme**: Consistent dark theme throughout
- **Animations**: Smooth transitions and animations
- **Loading States**: Proper loading indicators
- **Error Handling**: User-friendly error messages

---

## 6. Security & Privacy

### 6.1 Authentication
- Secure token storage
- Automatic token refresh
- Session management
- Password reset flow

### 6.2 Data Security
- Row Level Security (RLS) policies
- Secure API endpoints
- Encrypted data transmission
- User data isolation

### 6.3 Privacy Controls
- Public/private album settings
- Share link expiration
- Revocation capabilities
- Notification preferences

---

## 7. Performance Optimizations

### 7.1 Database
- Indexed queries for fast lookups
- Cached leaderboards (top 100)
- Batch processing for score updates
- Efficient pagination

### 7.2 App Performance
- Lazy loading of content
- Image caching
- Background processing
- Optimized API calls

### 7.3 Scheduled Jobs
- Score recalculation every 15 minutes
- Engagement sync on-demand
- Catalog size updates

---

## 8. Future Enhancements (Planned/In Progress)

### 8.1 Feed Features
- Post sharing
- User mentions
- Draft saving
- Advanced hashtag features

### 8.2 Social Features
- Direct messaging
- Group creation
- Event creation
- Enhanced discovery

### 8.3 Analytics
- Real-time score updates
- Per-region normalization
- Genre-specific scoring
- Advanced analytics dashboard

### 8.4 Studio Sessions
- Real-time collaboration
- Version control improvements
- Advanced editing tools
- Export capabilities

---

## 9. Statistics & Metrics

### Codebase Size:
- **Views**: 91 Swift files
- **Services**: 38 Swift files
- **Models**: 20 Swift files
- **ViewModels**: 14 Swift files
- **SQL Functions**: 30+ SQL files
- **Edge Functions**: 3 TypeScript functions

### Database:
- **Tables**: 15+ core tables
- **RPC Functions**: 20+ functions
- **Triggers**: 10+ triggers
- **Indexes**: 30+ indexes

### Features:
- **4 Main Tabs**: Feed, SoundPrint, Studio Sessions, Profile
- **10 SoundPrint Tabs**: Comprehensive analytics
- **4 Studio Session Tabs**: Album management
- **3 Feed Types**: For You, Following, Trending
- **5 Notification Types**: Complete notification system

---

## 10. Conclusion

RockOut is a **feature-rich, production-ready music social platform** with:

✅ **Complete Spotify Integration** - Full OAuth and data access  
✅ **Advanced Analytics** - SoundPrint with 10+ analysis tabs  
✅ **Competitive Leaderboards** - Sophisticated listener scoring system  
✅ **Social Networking** - Full feed, following, and interactions  
✅ **Music Creation** - Studio Sessions with collaboration  
✅ **Public Discovery** - Album sharing and discovery  
✅ **Notifications** - In-app and push notifications  
✅ **Modern Architecture** - MVVM, async/await, SwiftUI  
✅ **Scalable Backend** - Supabase with optimized queries  
✅ **Production Ready** - Error handling, security, performance

The app represents a **comprehensive music platform** that successfully combines music streaming, social networking, competitive gaming, and creative tools into a unified experience.

