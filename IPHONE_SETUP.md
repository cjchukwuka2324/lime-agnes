# Setting Up iPhone 16 Pro for Development

## Quick Setup Steps

### 1. Connect Your iPhone

1. **Connect via USB**: Plug your iPhone 16 Pro into your Mac using a USB cable
2. **Unlock iPhone**: Make sure your iPhone is unlocked
3. **Trust Computer**: If prompted on your iPhone, tap "Trust This Computer" and enter your passcode

### 2. Enable Developer Mode (iOS 16+)

1. On your iPhone, go to **Settings → Privacy & Security**
2. Scroll down to find **Developer Mode**
3. Turn **ON** Developer Mode
4. Your iPhone will restart (required for first-time setup)

### 3. Select Device in Xcode

1. Open `Rockout.xcodeproj` in Xcode
2. At the **top toolbar**, click the device selector (it currently shows "iPhone 15" or "Any iOS Device")
3. Your **iPhone 16 Pro** should appear in the dropdown under "iOS Device"
4. Select **"Your Name's iPhone"** or **"iPhone 16 Pro"**

### 4. Configure Signing

1. In Xcode, click on the **Rockout** project in the left sidebar
2. Select the **Rockout** target
3. Go to the **"Signing & Capabilities"** tab
4. Ensure **"Automatically manage signing"** is checked ✅
5. Select your **Team** from the dropdown (currently: `L5Y7VL3X35`)
   - If you don't see your team, click "Add Account..." to sign in with your Apple ID
6. Verify the **Bundle Identifier** is: `suinoik.RockOut`

### 5. Trust Developer Certificate (First Time Only)

After building and installing the app for the first time:

1. On your iPhone, when you try to open the app, you may see: **"Untrusted Developer"**
2. Go to: **Settings → General → VPN & Device Management** (or **Device Management**)
3. Find your developer account (your email/team name)
4. Tap it and select **"Trust [Your Name]"**
5. Confirm by tapping **"Trust"**

### 6. Build and Run

1. In Xcode, press **⌘R** (Command + R) or click the **▶️ Play** button
2. Xcode will:
   - Build the project
   - Install the app on your iPhone
   - Launch it automatically

## Troubleshooting

### Device Not Appearing

- **Check USB Connection**: Try a different USB cable or port
- **Restart Devices**: Restart both your Mac and iPhone
- **Check Xcode**: Make sure Xcode is up to date
- **Developer Mode**: Ensure Developer Mode is enabled on iPhone

### Signing Errors

- **Team Not Found**: 
  - Go to Xcode → Settings → Accounts
  - Add your Apple ID if not already added
  - Select your team in the Signing & Capabilities tab

- **Bundle ID Conflict**:
  - If the bundle ID is already taken, change it to something unique:
  - In Signing & Capabilities, edit Bundle Identifier to: `suinoik.RockOut.YourName`

- **Provisioning Profile Issues**:
  - Uncheck and re-check "Automatically manage signing"
  - Xcode will regenerate the provisioning profile

### Build Errors

- **Code Signing Failed**:
  - Clean build folder: **⌘⇧K** (Command + Shift + K)
  - Try building again: **⌘B**

- **Device Not Trusted**:
  - Go to iPhone Settings → General → VPN & Device Management
  - Trust your developer certificate

## Current Configuration

- **Team ID**: `L5Y7VL3X35`
- **Bundle Identifier**: `suinoik.RockOut`
- **Signing**: Automatic
- **Deployment Target**: iOS 17.2

## Next Steps After Setup

Once the app is running on your iPhone:

1. Test all features (Feed, RockList, SoundPrint, etc.)
2. Test Spotify connection
3. Test social features (posts, comments, likes)
4. Test navigation between views

If you encounter any issues, check the Xcode console for error messages.

