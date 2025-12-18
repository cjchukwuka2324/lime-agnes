# Device Installation Error 3002 - Troubleshooting Guide

## Error Details
- **Error Code**: 3002
- **Domain**: com.apple.dt.CoreDeviceError
- **Issue**: Failed to install the app on the device

## Common Solutions (Try in Order)

### 1. Check Device Connection
- Ensure your iPhone is properly connected via USB
- Unlock your iPhone
- If prompted, tap "Trust This Computer" on your iPhone
- Try a different USB cable or port

### 2. Enable Developer Mode (iOS 16+)
1. On your iPhone: **Settings → Privacy & Security**
2. Scroll to **Developer Mode**
3. Turn **ON** Developer Mode
4. Restart your iPhone (required for first-time setup)

### 3. Clean Build and Derived Data
```bash
# In Xcode:
# 1. Product → Clean Build Folder (⌘⇧K)
# 2. Or manually delete DerivedData:
rm -rf ~/Library/Developer/Xcode/DerivedData/Rockout-*
```

### 4. Check Signing Configuration
1. In Xcode, select the **Rockout** project
2. Select the **Rockout** target
3. Go to **Signing & Capabilities** tab
4. Verify:
   - ✅ **Automatically manage signing** is checked
   - **Team**: `L5Y7VL3X35` (or your team)
   - **Bundle Identifier**: `suinoik.RockOut`

### 5. Trust Developer Certificate on Device
After first installation attempt:
1. On iPhone: **Settings → General → VPN & Device Management**
   (or **Device Management** on older iOS)
2. Find your developer account (your email/team name)
3. Tap it and select **"Trust [Your Name]"**
4. Confirm by tapping **"Trust"**

### 6. Restart Devices
- Restart your iPhone
- Restart your Mac
- Reconnect the iPhone

### 7. Check Device Registration
1. In Xcode: **Window → Devices and Simulators** (⇧⌘2)
2. Verify your device appears and shows "Ready for development"
3. If not, click "Use for Development"

### 8. Check Provisioning Profile
1. In Xcode: **Signing & Capabilities**
2. Uncheck and re-check **"Automatically manage signing"**
3. Xcode will regenerate the provisioning profile

### 9. Check Device Storage
- Ensure your iPhone has enough free storage (at least 500MB)
- Delete unused apps if needed

### 10. Check iOS Version Compatibility
- **Deployment Target**: iOS 17.2
- Ensure your device is running iOS 17.2 or later
- Check: **Settings → General → About → Software Version**

### 11. Reset Xcode Connection
1. Disconnect your iPhone
2. In Xcode: **Window → Devices and Simulators**
3. Right-click your device → **Unpair Device**
4. Reconnect and trust again

### 12. Check Console for Detailed Errors
1. In Xcode: **Window → Devices and Simulators**
2. Select your device
3. Click **"Open Console"**
4. Look for specific error messages during installation

## Advanced Troubleshooting

### Check Code Signing Identity
```bash
# Verify signing identity
security find-identity -v -p codesigning
```

### Check Provisioning Profiles
```bash
# List provisioning profiles
ls ~/Library/MobileDevice/Provisioning\ Profiles/
```

### Manual Clean
```bash
# Clean DerivedData
rm -rf ~/Library/Developer/Xcode/DerivedData/Rockout-*

# Clean module cache
rm -rf ~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex

# Clean build folder in project
cd /Users/chukwudiebube/Downloads/RockOut-main
rm -rf build/
```

## Current Configuration
- **Team ID**: `L5Y7VL3X35`
- **Bundle Identifier**: `suinoik.RockOut`
- **Signing**: Automatic
- **Deployment Target**: iOS 17.2
- **Code Sign Identity**: Apple Development

## If All Else Fails

1. **Create a new provisioning profile**:
   - Go to [Apple Developer Portal](https://developer.apple.com/account)
   - Certificates, Identifiers & Profiles
   - Create new provisioning profile for your device

2. **Try building for a different device** (if available)

3. **Check Xcode version compatibility**:
   - Ensure Xcode is up to date
   - Check if your iOS version requires a newer Xcode

4. **Contact Apple Developer Support** if the issue persists

## Quick Command to Clean Everything
```bash
cd /Users/chukwudiebube/Downloads/RockOut-main
rm -rf ~/Library/Developer/Xcode/DerivedData/Rockout-*
xcodebuild clean -project Rockout.xcodeproj -scheme Rockout
```

Then rebuild in Xcode (⌘R).

