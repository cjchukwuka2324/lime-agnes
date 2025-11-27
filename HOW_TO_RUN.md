# How to Run RockOut Project in Xcode

## Quick Start

### Method 1: Open from Terminal (Easiest)
```bash
cd /Users/chukwudiebube/Downloads/RockOut-main
open Rockout.xcodeproj
```

### Method 2: Open from Finder
1. Navigate to `/Users/chukwudiebube/Downloads/RockOut-main`
2. Double-click `Rockout.xcodeproj`

## Running the App

### Step-by-Step Instructions

1. **Open Xcode**
   - The project should open automatically if you used the terminal command
   - Or double-click `Rockout.xcodeproj` in Finder

2. **Select a Simulator**
   - At the top of Xcode, click the device selector (next to the scheme)
   - Choose: **iPhone 16 Pro** (or any iOS Simulator)
   - If no simulators appear, go to: **Xcode → Settings → Platforms** and download iOS Simulator

3. **Select the Scheme**
   - Make sure **Rockout** is selected in the scheme dropdown (next to device selector)

4. **Build and Run**
   - Press **⌘R** (Command + R) to build and run
   - Or click the **▶️ Play** button in the top-left toolbar
   - Or go to **Product → Run**

5. **Wait for Build**
   - Xcode will compile the project (first time may take 1-2 minutes)
   - The simulator will launch automatically
   - The app will install and run

## Keyboard Shortcuts

- **⌘R** - Build and Run
- **⌘B** - Build only (no run)
- **⌘.** - Stop running app
- **⌘⇧K** - Clean build folder
- **⌘⇧O** - Quick Open file

## Troubleshooting

### "No such module" errors
- Go to **File → Packages → Reset Package Caches**
- Then **File → Packages → Resolve Package Versions**

### Simulator won't launch
- Go to **Xcode → Settings → Platforms**
- Download iOS Simulator if needed
- Or manually open Simulator: **Xcode → Open Developer Tool → Simulator**

### Build fails
- Try **Product → Clean Build Folder** (⌘⇧K)
- Then build again (⌘B)
- Check the error messages in the Issue Navigator (⌘5)

### App crashes on launch
- Check the console output at the bottom of Xcode
- Look for error messages in red
- Common issues: Missing environment variables, network permissions, etc.

## Project Structure

```
Rockout/
├── App/
│   └── RockOutApp.swift          # App entry point
├── Views/
│   ├── Auth/                     # Login, Signup, Spotify Connect
│   ├── SoundPrint/               # Main music discovery
│   ├── RockList/                 # Ranking system
│   ├── Feed/                     # Social feed
│   └── Profile/                  # User profile
├── Services/
│   ├── Spotify/                  # Spotify API integration
│   ├── Supabase/                 # Backend services
│   └── RockList/                 # RockList data service
├── ViewModels/                   # Business logic
└── Models/                       # Data models
```

## First Run Checklist

- [ ] Project opens in Xcode
- [ ] Simulator is selected (iPhone 16 Pro recommended)
- [ ] Scheme is set to "Rockout"
- [ ] Build succeeds (⌘B)
- [ ] App runs in simulator (⌘R)
- [ ] Can sign up/login
- [ ] Can connect Spotify account

## Next Steps After Running

1. **Sign Up/Login** with your email
2. **Connect Spotify** from the welcome screen or profile
3. **Explore SoundPrint** to see your music stats
4. **Check RockList** rankings (after backend setup)
5. **View Feed** for social activity

## Need Help?

- Check the console output for errors
- Review the code comments
- Check `docs/rocklist_backend.md` for backend setup
- Verify Supabase and Spotify credentials are configured

