# Fix Signup and Spotify Connection Errors

## Issue 1: Spotify 403 Error

**Error Message:** "API error (403): Check settings on developer.spotify.com/dashboard, the user may not be registered."

### Root Causes:

1. **Redirect URI Not Configured**
   - The redirect URI `rockout://auth` must be added to your Spotify app settings

2. **User Not Added to Development App**
   - If your app is in Development mode, your Spotify email must be added

3. **Client ID Mismatch**
   - The Client ID in code must match your Spotify app

### Fix Steps:

#### Step 1: Configure Redirect URI in Spotify Dashboard

1. Go to https://developer.spotify.com/dashboard
2. Log in with your Spotify account
3. Click on your app (or create a new one)
4. Click **"Edit Settings"**
5. In **"Redirect URIs"**, add:
   ```
   rockout://auth
   ```
6. Click **"Add"** then **"Save"**
7. Wait 1-2 minutes for changes to propagate

#### Step 2: Add User to Development App (if needed)

1. In your Spotify app settings, find **"Users and Access"** or **"Edit Users"**
2. Click **"Add User"**
3. Add your Spotify account email address
4. Save changes

#### Step 3: Verify Configuration

**In Code (SpotifyAuthService.swift):**
- Client ID: `0d1441ca6ac6428f83b8980295fe7f14`
- Redirect URI: `rockout://auth`

**In Spotify Dashboard:**
- Must match exactly
- No extra spaces or typos

#### Step 4: After Configuration

1. Wait 1-2 minutes for changes to propagate
2. Force quit and restart the app
3. Try connecting again

---

## Issue 2: Signup Errors

### Common Signup Errors and Fixes:

1. **"Email already registered"**
   - Solution: Use "Log In" instead, or use a different email

2. **"Weak password"**
   - Solution: Use at least 6 characters

3. **"Invalid email format"**
   - Solution: Check email spelling and format

4. **Network errors**
   - Solution: Check internet connection

### What Was Fixed:

- ✅ Improved error messages for signup form
- ✅ Better error messages for login form
- ✅ Improved Spotify API error handling with helpful 403 messages
- ✅ Clearer guidance for users

---

## Verification Checklist

- [ ] Redirect URI `rockout://auth` added to Spotify Dashboard
- [ ] User email added to Spotify app (if in Development mode)
- [ ] Client ID matches in code and dashboard
- [ ] Info.plist has `rockout` URL scheme configured
- [ ] Waited 1-2 minutes after making changes
- [ ] App restarted completely

---

## Testing

1. **Test Signup:**
   - Try creating a new account
   - Check that error messages are clear

2. **Test Spotify Connection:**
   - Go to Profile tab
   - Click "Connect to Spotify"
   - Should open browser and redirect back
   - Should not show 403 error

---

## Still Having Issues?

1. **Double-check redirect URI:**
   - In Spotify Dashboard, it must be exactly: `rockout://auth`
   - No `https://`, no trailing slashes

2. **Check app status:**
   - Make sure your Spotify app is not restricted or suspended

3. **Try different Spotify account:**
   - Test with the account that owns the Spotify app

4. **Clear app data:**
   - Delete and reinstall the app
   - Try again

