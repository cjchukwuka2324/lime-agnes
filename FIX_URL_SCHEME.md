# Fixing "Rockout Is No Longer Available" Error

## The Problem
iOS shows "Rockout Is No Longer Available" when clicking share links, meaning iOS can't find an app to handle the `rockout://` URL scheme.

## Solution Steps

### 1. Verify Bundle Identifier
- Open Xcode → Rockout project → Rockout target → General tab
- Check **Bundle Identifier**: Should be `com.suinoik.rockout` (or your configured value)
- Make sure it matches your provisioning profile

### 2. Verify URL Scheme in Xcode (NOT just Info.plist)
- In Xcode: Rockout target → **Info** tab
- Scroll to **URL Types**
- Verify there's an entry with:
  - **Identifier**: `RockoutRedirect`
  - **URL Schemes**: `rockout`
  - **Role**: `Editor`

### 3. Clean Build and Reinstall
1. **Product** → **Clean Build Folder** (Shift+Cmd+K)
2. **Delete the app** from your device/simulator completely
3. **Restart your device/simulator** (CRITICAL - iOS caches URL scheme associations)
4. Rebuild and reinstall the app
5. **Restart device again** after installation

### 4. Test URL Scheme Directly
1. Open **Safari** on your device
2. Type in address bar: `rockout://share/test123`
3. Tap Go
4. If app opens → URL scheme works!
5. If still shows error → Continue to step 5

### 5. Re-register URL Scheme in Xcode
If step 4 fails:
1. In Xcode: Rockout target → Info tab → URL Types
2. **Delete** the existing `rockout` URL type entry
3. Click **+** to add new URL Type
4. Set:
   - **Identifier**: `RockoutRedirect`
   - **URL Schemes**: `rockout` (add this in the array)
   - **Role**: `Editor`
5. Save and rebuild

### 6. Verify Info.plist Matches
The Info.plist should have:
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

### 7. Check Code Signing
- Make sure your app is properly signed
- In Xcode: Rockout target → Signing & Capabilities
- Verify **Team** is selected and **Bundle Identifier** matches

## What We've Added

1. **AppDelegate.swift**: Handles URLs when app launches from a URL
2. **Enhanced URL parsing**: Better whitespace handling for tokens
3. **Multiple URL handlers**: AppDelegate, App.onOpenURL, and RootAppView.onOpenURL

## Debugging

Check Xcode console when clicking a share link. You should see:
- `🔗 AppDelegate received URL: rockout://share/...`
- `🔥 Deep link received in App: rockout://share/...`
- `📎 Handling share token: ...`

If you see these logs, the URL is reaching the app (the issue is iOS not finding the app).
If you DON'T see these logs, iOS isn't routing the URL to the app (URL scheme registration issue).

## Most Common Fix
**Restart your device** - iOS caches URL scheme associations and needs a restart to refresh them after app reinstallation.

