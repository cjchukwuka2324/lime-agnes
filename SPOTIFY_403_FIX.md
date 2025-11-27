# Fix Spotify 403 Error

## Error: "API error (403): Check settings on developer.spotify.com/dashboard, the user may not be registered."

This error typically occurs due to one of these reasons:

### 1. Redirect URI Not Configured in Spotify Dashboard

**Fix Steps:**

1. Go to [Spotify Developer Dashboard](https://developer.spotify.com/dashboard)
2. Log in with your Spotify account
3. Click on your app (or create a new one)
4. Click **"Edit Settings"**
5. In the **"Redirect URIs"** section, add:
   ```
   rockout://auth
   ```
6. Click **"Add"** and then **"Save"**
7. Wait 1-2 minutes for changes to propagate

### 2. User Not Added to Development App

If your Spotify app is in **Development mode**:

1. Go to your app in the Spotify Dashboard
2. Click **"Users and Access"** or **"Settings"**
3. Click **"Add User"** or **"Edit Users"**
4. Add your Spotify account email address
5. Save and wait 1-2 minutes

### 3. Verify Your Configuration

Make sure these match:

**In your code:**
- Client ID: `0d1441ca6ac6428f83b8980295fe7f14`
- Redirect URI: `rockout://auth`

**In Spotify Dashboard:**
- Client ID must be: `0d1441ca6ac6428f83b8980295fe7f14` (matches code)
- Redirect URI must be: `rockout://auth` (exactly as shown)

### 4. Check Info.plist

Make sure your `Info.plist` has the URL scheme:
```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>rockout</string>
        </array>
    </dict>
</array>
```

### 5. After Making Changes

1. Wait 1-2 minutes for Spotify to update their servers
2. Force quit the app completely
3. Rebuild and run the app
4. Try connecting again

## Still Having Issues?

If the error persists:
1. Double-check the redirect URI has no typos or extra spaces
2. Verify your Spotify app is not in a restricted state
3. Try using a different Spotify account (or make sure your account email matches)
4. Check if your app needs to be approved (if it's a new app)

