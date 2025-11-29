# RockOut Notifications System Setup Guide

## Overview

The RockOut notification system is now fully implemented with:
- ✅ **In-app notifications** - Stored in Supabase, displayed in-app
- ✅ **Push notifications** - APNs integration for iOS
- ✅ **Database triggers** - Automatic notification creation
- ✅ **UI components** - Beautiful glassmorphism notification cards

## Architecture

### Backend (Supabase)

1. **`notifications` table** - Stores all notifications
2. **`device_tokens` table** - Stores APNs device tokens
3. **Database triggers** - Auto-create notifications on events:
   - New follower
   - Post like
   - Post reply
   - RockList rank improvement
   - New posts from followed users (if enabled)
4. **Edge Function** - Sends APNs push notifications

### iOS App

1. **Models** - `AppNotification` struct
2. **Services**:
   - `SupabaseNotificationService` - Fetch/manage notifications from database
   - `DeviceTokenService` - Register device tokens for push
3. **UI**:
   - `NotificationsView` - Display notifications with deep linking
   - `NotificationsViewModel` - Handle business logic
   - Bell icon with unread badge in FeedView
4. **AppDelegate** - Handle APNs lifecycle and notification taps

## Setup Instructions

### Step 1: Set Up Database Schema

Run these SQL files in your Supabase SQL editor (in order):

```bash
# 1. Create notifications table and add notify_on_posts column
sql/notifications_schema.sql

# 2. Create device_tokens table
sql/device_tokens_schema.sql

# 3. Create notification triggers
sql/notification_triggers.sql
```

**Important**: After running these, verify in Supabase dashboard:
- Tables `notifications` and `device_tokens` exist
- RLS policies are enabled
- Triggers are created (check Functions tab)

### Step 2: Configure APNs (Apple Push Notifications)

#### 2.1 Get APNs Credentials from Apple Developer

1. Go to [Apple Developer Portal](https://developer.apple.com)
2. Navigate to: **Certificates, Identifiers & Profiles** → **Keys**
3. Click **+** to create a new key
4. Name it "RockOut Push Notifications"
5. Check **Apple Push Notifications service (APNs)**
6. Click **Continue** then **Register**
7. **Download the .p8 file** (you can only download once!)
8. Note your **Key ID** (e.g., `ABC123DEFG`)
9. Note your **Team ID** (found in top right of developer portal)

#### 2.2 Enable Push Notifications in Xcode

1. Open `Rockout.xcodeproj` in Xcode
2. Select the **Rockout** target
3. Go to **Signing & Capabilities** tab
4. Click **+ Capability**
5. Add **Push Notifications**
6. Add **Background Modes** and check:
   - ✅ Remote notifications

#### 2.3 Set Environment Variables in Supabase

```bash
# Navigate to your project
cd /path/to/RockOut-main

# Set APNs credentials (replace with your values)
supabase secrets set APNS_KEY_ID="ABC123DEFG"
supabase secrets set APNS_TEAM_ID="XYZ9876543"
supabase secrets set APNS_BUNDLE_ID="com.rockout.app"  # Your actual bundle ID
supabase secrets set APNS_PRODUCTION="false"  # Use "true" for production

# Set the private key (replace with content from your .p8 file)
supabase secrets set APNS_AUTH_KEY="-----BEGIN PRIVATE KEY-----
MIGTAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBHkwdwIBAQQg...
...your key content here...
...
-----END PRIVATE KEY-----"
```

**Tip**: To get the key content, open the .p8 file in a text editor and copy the entire contents including the BEGIN/END lines.

### Step 3: Deploy Edge Function

```bash
# Make sure you're logged in to Supabase CLI
supabase login

# Link to your project
supabase link --project-ref YOUR_PROJECT_REF

# Deploy the function
supabase functions deploy send_push_notification

# Verify deployment
supabase functions list
```

### Step 4: Test the System

#### Test In-App Notifications

1. Build and run the app on a device or simulator
2. Create a test notification manually in Supabase SQL editor:

```sql
-- Replace USER_ID with your actual user UUID
INSERT INTO notifications (user_id, type, message, actor_id)
VALUES (
  'YOUR_USER_ID',
  'new_follower',
  'Test user started following you',
  'SOME_OTHER_USER_ID'
);
```

3. Open the app and tap the bell icon - you should see the notification!

#### Test Push Notifications

**Note**: Push notifications require a **physical iOS device** (won't work in simulator).

1. Build and run on a physical device
2. Grant notification permissions when prompted
3. Check the Xcode console - you should see:
   ```
   📱 AppDelegate: Received device token: abc123...
   ✅ DeviceTokenService: Successfully registered device token
   ```
4. Test sending a push via the Edge Function:

```bash
# Get your user ID from Supabase dashboard
# Get your anon key from Supabase project settings

curl -X POST 'https://YOUR_PROJECT.supabase.co/functions/v1/send_push_notification' \
  -H 'Authorization: Bearer YOUR_ANON_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "user_id": "YOUR_USER_ID",
    "title": "Test Notification",
    "body": "This is a test push notification!",
    "data": {
      "type": "new_follower",
      "actor_id": "SOME_USER_ID"
    }
  }'
```

5. You should receive a push notification on your device!

### Step 5: Enable Automatic Notifications

The database triggers automatically create notifications when:

- ✅ Someone follows you
- ✅ Someone likes your post
- ✅ Someone replies to your post
- ✅ Your RockList rank improves
- ✅ Someone you follow (with notifications on) posts

**To enable post notifications for a specific user:**

```swift
// In your app code (already implemented in UserProfileDetailView)
try await SupabaseSocialGraphService.shared.setPostNotifications(
    for: userId,
    enabled: true
)
```

## Notification Types

| Type | Trigger | Message | Deep Link |
|------|---------|---------|-----------|
| `new_follower` | User follows you | "{name} started following you" | User profile |
| `post_like` | Post is liked | "{name} liked your post" | Post detail |
| `post_reply` | Post is replied to | "{name} replied to your post" | Parent post |
| `rocklist_rank` | Rank improves | "You moved up to rank {X} for {artist}" | RockList |
| `new_post` | Followed user posts | "{name} posted: {preview}" | Post detail |

## Troubleshooting

### No Notifications Appearing

1. Check Supabase database:
   ```sql
   SELECT * FROM notifications ORDER BY created_at DESC LIMIT 10;
   ```
2. Verify triggers are firing:
   ```sql
   -- Check if triggers exist
   SELECT * FROM pg_trigger WHERE tgname LIKE '%notification%';
   ```
3. Check app logs for errors

### Push Notifications Not Working

1. **Verify device token registration:**
   ```sql
   SELECT * FROM device_tokens WHERE user_id = 'YOUR_USER_ID';
   ```

2. **Check APNs credentials:**
   ```bash
   supabase secrets list
   ```

3. **Test Edge Function directly** (see Step 4 above)

4. **Common issues:**
   - Using simulator (push requires physical device)
   - Wrong bundle ID in Supabase secrets
   - Invalid .p8 key
   - Using production server with sandbox certificate (or vice versa)

### Notifications Not Auto-Creating

1. Verify triggers are installed:
   ```sql
   \df notify_*
   ```

2. Check for trigger errors in Supabase logs (Dashboard → Logs)

3. Manually test a trigger:
   ```sql
   -- Test follow trigger
   INSERT INTO user_follows (follower_id, followed_id)
   VALUES ('USER_A_ID', 'USER_B_ID');
   
   -- Check if notification was created
   SELECT * FROM notifications WHERE user_id = 'USER_B_ID' ORDER BY created_at DESC LIMIT 1;
   ```

## Production Checklist

Before going live:

- [ ] Run all SQL scripts in production Supabase
- [ ] Deploy Edge Function to production
- [ ] Set `APNS_PRODUCTION="true"` in Supabase secrets
- [ ] Get production APNs certificate from Apple
- [ ] Test on production build (not debug)
- [ ] Verify RLS policies are correct
- [ ] Set up monitoring for Edge Function errors
- [ ] Test all notification types end-to-end

## Future Enhancements

Possible improvements:

1. **Notification preferences** - Let users customize which types they want
2. **Batch notifications** - Group similar notifications ("John and 5 others liked your post")
3. **Rich notifications** - Images, actions, custom UI
4. **Notification sounds** - Custom sounds per type
5. **Analytics** - Track notification open rates
6. **Scheduled notifications** - Digest emails, weekly summaries

## Support

For issues:
1. Check Supabase logs: Dashboard → Logs
2. Check Xcode console for iOS errors
3. Verify database state with SQL queries
4. Test Edge Function with curl

## Summary

Your notification system is now **production-ready**! 🎉

- ✅ Persistent notifications in Supabase
- ✅ Real-time push notifications via APNs
- ✅ Automatic creation via database triggers
- ✅ Beautiful UI with deep linking
- ✅ Unread badges and mark as read
- ✅ Device token management

Just follow the setup steps above to activate it!

