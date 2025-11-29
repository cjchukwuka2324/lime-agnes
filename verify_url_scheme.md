# URL Scheme Verification Guide

## The Error: "Rockout Is No Longer Available"

This error appears when iOS cannot find an app to handle the `rockout://` URL scheme. Here's how to fix it:

## Step 1: Verify URL Scheme in Info.plist

The URL scheme should be registered in `Rockout/Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLName</key>
        <string>RockoutRedirect</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>rockout</string>
        </array>
    </dict>
</array>
```

## Step 2: Verify in Xcode Project Settings

1. Open Xcode
2. Select the **Rockout** project in the navigator
3. Select the **Rockout** target
4. Go to the **Info** tab
5. Expand **URL Types**
6. Verify there's an entry with:
   - **Identifier**: `RockoutRedirect` (or similar)
   - **URL Schemes**: `rockout`

## Step 3: Clean Build and Reinstall

1. In Xcode: **Product** → **Clean Build Folder** (Shift+Cmd+K)
2. Delete the app from your device/simulator
3. Rebuild and reinstall the app
4. **Restart your device/simulator** (this is important - iOS caches URL scheme associations)

## Step 4: Test URL Scheme

After reinstalling, test if the URL scheme works:

1. Open Safari on your device
2. Type in the address bar: `rockout://share/test123`
3. Tap Go
4. The app should open (even if it shows an error, it means the URL scheme is working)

## Step 5: Verify Bundle Identifier

Make sure the bundle identifier hasn't changed:

1. In Xcode: **Rockout** target → **General** tab
2. Check **Bundle Identifier**: Should be `com.suinoik.rockout` (or whatever you set)
3. Make sure this matches your provisioning profile

## Common Issues:

1. **App was deleted and reinstalled**: iOS loses URL scheme associations. Restart device.
2. **Bundle identifier changed**: URL scheme registration is tied to bundle ID
3. **App not properly signed**: Code signing issues can prevent URL scheme registration
4. **iOS cache**: Restart device to clear URL scheme cache

## Debugging:

Check Xcode console when clicking a share link. You should see:
- `🔥 Deep link received in App: rockout://share/...`
- If you don't see this, the URL isn't reaching the app

