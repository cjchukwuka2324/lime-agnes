# Spotify OAuth Configuration Verification

## Current Configuration in Code

### 1. Redirect URI (Sent to Spotify)
**File:** `Services/Spotify/SpotifyAuthService.swift` (line 16)
```swift
private let redirectURI = "rockout://auth"
```

### 2. Callback URL Scheme (ASWebAuthenticationSession)
**File:** `Views/Profile/SpotifyConnectionView.swift` (line 143)
```swift
callbackURLScheme: "rockout"
```

### 3. Info.plist URL Scheme
**File:** `Info.plist` (line 14)
```xml
<string>rockout</string>
```

### 4. Deep Link Handler
**File:** `App/RockOutApp.swift` (line 32)
```swift
if url.scheme == "rockout" && url.host == "auth" {
```

## Expected Callback URL Format

When Spotify redirects back to your app, the URL will be:
```
rockout://auth?code=XXXXX&state=YYYYY
```

## Required Spotify Developer Dashboard Configuration

### Steps to Verify/Configure:

1. **Go to Spotify Developer Dashboard**
   - URL: https://developer.spotify.com/dashboard
   - Log in with your Spotify account

2. **Select Your App**
   - Find the app with Client ID: `13aa07c310bb445d82fc8035ee426d0c`

3. **Go to Settings**
   - Click on your app
   - Click "Settings" tab

4. **Check Redirect URIs Section**
   - Scroll to "Redirect URIs"
   - **REQUIRED:** Add or verify this exact URI:
     ```
     rockout://auth
     ```
   - ⚠️ **IMPORTANT:** The URI must match EXACTLY (case-sensitive, no trailing slash)

5. **Save Changes**
   - Click "Add" if adding new URI
   - Click "Save" to save all settings

## Common Issues

### ❌ Wrong Redirect URI
- ❌ `rockout://auth/` (trailing slash)
- ❌ `rockout://auth/callback` (different path)
- ❌ `rockout://` (missing path)
- ✅ `rockout://auth` (correct)

### ✅ Correct Configuration
- ✅ Redirect URI in code: `rockout://auth`
- ✅ Callback scheme: `rockout`
- ✅ Info.plist scheme: `rockout`
- ✅ Spotify Dashboard: `rockout://auth`

## Testing

After configuring:

1. **Connect to Spotify** from Profile screen
2. **Complete OAuth** in the browser
3. **Check console logs** for:
   - `✅ Spotify callback received: rockout://auth?code=...`
   - `✅ Got authorization code, exchanging for tokens...`
   - `✅ Successfully exchanged code for tokens`

If you see errors:
- Check Spotify Dashboard redirect URI matches exactly
- Verify Info.plist URL scheme is registered
- Check console logs for specific error messages

## Verification Checklist

- [ ] Redirect URI in code: `rockout://auth` ✓
- [ ] Callback URL scheme: `rockout` ✓
- [ ] Info.plist URL scheme: `rockout` ✓
- [ ] Spotify Dashboard redirect URI: `rockout://auth` ⚠️ **VERIFY THIS**
- [ ] All match exactly (no typos, no trailing slashes) ⚠️ **VERIFY THIS**

