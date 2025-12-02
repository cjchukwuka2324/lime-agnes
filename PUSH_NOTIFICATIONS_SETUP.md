# 🔔 Push Notifications Setup Guide

## Prerequisites Check

Your APNs credentials:
- ✅ **Key ID**: HC2445Y3JA
- ✅ **Team ID**: L5Y7VL3X35
- ✅ **Bundle ID**: suinoik.RockOut
- ✅ **Key File**: AuthKey_HC2445Y3JA.p8 (in project root)
- ✅ **Environment**: Production

## Step 1: Install Supabase CLI (if not installed)

```bash
# macOS (Homebrew)
brew install supabase/tap/supabase

# Or via NPM
npm install -g supabase

# Verify installation
supabase --version
```

## Step 2: Login to Supabase

```bash
# Login to your Supabase account
supabase login

# Link to your project (if not already linked)
cd /Users/chukwudiebube/Downloads/RockOut-main
supabase link --project-ref YOUR_PROJECT_REF
```

## Step 3: Configure APNs Secrets

Run these commands in your terminal:

```bash
# Navigate to project directory
cd /Users/chukwudiebube/Downloads/RockOut-main

# Set APNs Key ID
supabase secrets set APNS_KEY_ID="HC2445Y3JA"

# Set APNs Team ID
supabase secrets set APNS_TEAM_ID="L5Y7VL3X35"

# Set APNs Private Key (reads from file)
supabase secrets set APNS_KEY_P8="$(cat /Users/chukwudiebube/Downloads/RockOut-main/AuthKey_HC2445Y3JA.p8)"

# Set App Bundle ID
supabase secrets set APNS_BUNDLE_ID="suinoik.RockOut"

# Set Production Mode (true for App Store builds, false for TestFlight)
supabase secrets set APNS_PRODUCTION="true"

# Verify all secrets are set
supabase secrets list
```

Expected output:
```
APNS_KEY_ID
APNS_TEAM_ID
APNS_KEY_P8
APNS_BUNDLE_ID
APNS_PRODUCTION
```

## Step 4: Deploy Edge Function

```bash
# Deploy the push notification Edge Function
cd /Users/chukwudiebube/Downloads/RockOut-main
supabase functions deploy send_push_notification

# Expected output:
# ✓ Deployed Function send_push_notification
# URL: https://YOUR_PROJECT_REF.supabase.co/functions/v1/send_push_notification
```

## Step 5: Run Database Migrations

Open your Supabase Dashboard SQL Editor and run these scripts in order:

### 5.1 Device Tokens Table
```bash
# Copy contents of sql/device_tokens_schema.sql and run in SQL Editor
```

### 5.2 Notifications Table
```bash
# Copy contents of sql/notifications_schema.sql and run in SQL Editor
```

### 5.3 Notification Triggers
```bash
# Copy contents of sql/notification_triggers.sql and run in SQL Editor
```

**OR** run all at once using Supabase CLI:

```bash
cd /Users/chukwudiebube/Downloads/RockOut-main

# Run migrations
supabase db push
```

## Step 6: Configure Xcode Project

### 6.1 Add Push Notifications Capability
1. Open `Rockout.xcodeproj` in Xcode
2. Select **Rockout** target
3. Go to **Signing & Capabilities** tab
4. Click **+ Capability**
5. Add **Push Notifications**

### 6.2 Enable Background Modes
1. In the same **Signing & Capabilities** tab
2. Click **+ Capability**
3. Add **Background Modes**
4. Check **Remote notifications**

### 6.3 Verify Bundle Identifier
- Ensure Bundle Identifier matches: `suinoik.RockOut`

### 6.4 Update Info.plist (if needed)
Check that `Rockout/Info.plist` contains:
```xml
<key>UIBackgroundModes</key>
<array>
    <string>remote-notification</string>
</array>
```

## Step 7: Test on Physical Device

⚠️ **Push notifications require a physical iOS device** - they don't work in the Simulator.

### 7.1 Build and Run
1. Connect your iPhone/iPad
2. Select device in Xcode
3. Build and run (Cmd+R)

### 7.2 Grant Permissions
- When prompted, tap **Allow** for notifications

### 7.3 Verify Registration
Check Xcode console for:
```
📱 AppDelegate: Received device token: [long hex string]
✅ DeviceTokenService: Successfully registered device token
```

### 7.4 Check Database
In Supabase Dashboard, verify:
1. Go to **Table Editor** → `device_tokens`
2. You should see a row with your device token

## Step 8: Test Notifications

### Test 1: Follow a User
1. Follow another user in the app
2. That user should receive a notification: "X started following you"

### Test 2: Like a Post
1. Like someone's post
2. Post author receives: "X liked your post"

### Test 3: Reply to Post
1. Reply to a post
2. Post author receives: "X replied to your post"

### Test 4: Manual Test (via Supabase SQL)
Run this in Supabase SQL Editor to send a test notification:

```sql
-- Replace USER_ID with your actual user ID
SELECT send_push_notification(
    'USER_ID',
    'Test Notification',
    'This is a test push notification from RockOut!',
    '{"type": "test"}'::jsonb
);
```

## Debugging

### Check Edge Function Logs
```bash
# View real-time logs
supabase functions logs send_push_notification --follow

# Or in Supabase Dashboard:
# Edge Functions → send_push_notification → Logs
```

### Common Issues

**Issue**: "Failed to register for remote notifications"
- **Solution**: You're using Simulator - must use physical device

**Issue**: No device token received
- **Solution**: 
  1. Check Xcode console for errors
  2. Verify Push Notifications capability is enabled
  3. Ensure device has internet connection

**Issue**: Notifications not delivered
- **Solution**:
  1. Check Edge Function logs for APNs errors
  2. Verify APNS_PRODUCTION matches your environment
  3. Ensure device token is valid (not expired)
  4. Check Apple Developer Portal that APNs key is active

**Issue**: "Invalid APNs credentials"
- **Solution**:
  1. Verify Key ID, Team ID, and P8 file are correct
  2. Ensure P8 file content was properly read (no extra newlines)
  3. Check bundle ID matches exactly: `suinoik.RockOut`

## Production Checklist

Before releasing to App Store:

- [ ] APNS_PRODUCTION set to "true"
- [ ] Push Notifications capability enabled in Xcode
- [ ] Background Modes enabled with Remote notifications
- [ ] Tested on physical device
- [ ] Verified notifications deliver successfully
- [ ] APNs key uploaded to Apple Developer Portal
- [ ] Bundle ID matches Apple Developer account
- [ ] Edge Function deployed and accessible
- [ ] Database tables created (device_tokens, notifications)
- [ ] Notification triggers active

## Monitoring

### View Active Device Tokens
```sql
SELECT 
    user_id,
    token,
    platform,
    created_at,
    updated_at
FROM device_tokens
ORDER BY updated_at DESC;
```

### View Recent Notifications
```sql
SELECT 
    n.id,
    n.type,
    n.message,
    n.created_at,
    p.display_name as user_name
FROM notifications n
JOIN profiles p ON n.user_id = p.id
ORDER BY n.created_at DESC
LIMIT 50;
```

### Check Notification Delivery Rate
```sql
SELECT 
    type,
    COUNT(*) as total,
    COUNT(read_at) as read_count,
    ROUND(COUNT(read_at)::numeric / COUNT(*)::numeric * 100, 2) as read_percentage
FROM notifications
WHERE created_at > NOW() - INTERVAL '7 days'
GROUP BY type
ORDER BY total DESC;
```

## Support

- **APNs Documentation**: https://developer.apple.com/documentation/usernotifications
- **Supabase Edge Functions**: https://supabase.com/docs/guides/functions
- **Troubleshooting**: Check `CRITICAL_FIXES_SUMMARY.md` for common issues

---

**Setup Status**: Ready to configure
**Last Updated**: Saturday Nov 29, 2025

