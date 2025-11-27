# Spotify OAuth Setup Guide

## Current Configuration

**Redirect URI in Code:** `rockout://spotify-callback`

**URL Scheme in Info.plist:** `rockout`

## Fix the "INVALID_CLIENT: Invalid redirect URI" Error

### Step 1: Go to Spotify Developer Dashboard

1. Visit: https://developer.spotify.com/dashboard
2. Log in with your Spotify account
3. Click on your app (or create a new one if needed)
4. Click **"Edit Settings"**

### Step 2: Add Redirect URI

In the **"Redirect URIs"** section, add:

```
rockout://spotify-callback
```

**Important:** 
- Add it exactly as shown above
- Make sure there are no extra spaces
- The format is: `scheme://host` (no path needed, but we use `/spotify-callback`)

### Step 3: Save Settings

- Click **"Add"** after entering the URI
- Click **"Save"** at the bottom
- Wait a few seconds for changes to propagate

### Step 4: Verify Your App Settings

Your Spotify app should have:
- **Client ID:** `13aa07c310bb445d82fc8035ee426d0c` (already in code)
- **Redirect URIs:** `rockout://spotify-callback`
- **App Type:** Web API (or Mobile App if available)

## Alternative: If You Want to Use a Different Redirect URI

If you prefer a different redirect URI, you can change it in two places:

1. **SpotifyAuthService.swift:**
   ```swift
   private let redirectURI = "rockout://spotify-callback"  // Change this
   ```

2. **Info.plist:**
   ```xml
   <string>rockout</string>  // Change the scheme part
   ```

3. **Spotify Developer Dashboard:**
   - Add the new redirect URI to match

## Common Issues

### Issue: "Redirect URI mismatch"
- **Solution:** Make sure the URI in your Spotify dashboard **exactly matches** the one in `SpotifyAuthService.swift`
- Check for typos, extra spaces, or missing slashes

### Issue: "Invalid client"
- **Solution:** Verify your Client ID is correct in `SpotifyAuthService.swift`
- Make sure you're using the right app in the dashboard

### Issue: Redirect not working after auth
- **Solution:** Make sure `Info.plist` has the URL scheme registered
- Check that `onOpenURL` in `RockOutApp.swift` is handling the redirect

## Testing

After updating the redirect URI in Spotify Dashboard:

1. Wait 1-2 minutes for changes to propagate
2. Try connecting again in the app
3. The error should be resolved

## Current Code Configuration

```swift
// In SpotifyAuthService.swift
private let redirectURI = "rockout://spotify-callback"
```

```xml
<!-- In Info.plist -->
<key>CFBundleURLSchemes</key>
<array>
    <string>rockout</string>
</array>
```

Make sure your Spotify Dashboard has: `rockout://spotify-callback`

