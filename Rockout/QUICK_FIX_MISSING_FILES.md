# Quick Fix: Add Missing Files to Xcode

You have 4 files that need to be added to fix compilation errors:

1. `Models/SpotifyConnection.swift`
2. `Views/Profile/SpotifyConnectionView.swift`
3. `Views/Profile/SpotifyPresentationContextProvider.swift`
4. `Services/Supabase/SpotifyConnectionService.swift`

## Quick Manual Fix (2 minutes)

### Option 1: Add All at Once (Easiest)

1. **In Xcode**, right-click on the **Rockout** folder (top level) in the Project Navigator
2. Select **"Add Files to Rockout..."**
3. Navigate to the `Rockout` folder:
   - Hold **⌘ (Command)** and select these 4 files:
     - `Models/SpotifyConnection.swift`
     - `Views/Profile/SpotifyConnectionView.swift`
     - `Views/Profile/SpotifyPresentationContextProvider.swift`
     - `Services/Supabase/SpotifyConnectionService.swift`
4. Make sure:
   - ✅ **"Copy items if needed"** is **UNCHECKED** (files are already there)
   - ✅ **"Create groups"** is selected
   - ✅ **"Add to targets: Rockout"** is **CHECKED**
5. Click **Add**

**That's it! Build again and errors should be gone.**

---

### Option 2: Add to Specific Groups (More Organized)

1. **Models/SpotifyConnection.swift**:
   - Right-click **Models** group → Add Files → Select `Models/SpotifyConnection.swift`

2. **Views/Profile/SpotifyConnectionView.swift**:
   - Right-click **Views/Profile** group → Add Files → Select `Views/Profile/SpotifyConnectionView.swift`

3. **Views/Profile/SpotifyPresentationContextProvider.swift**:
   - Right-click **Views/Profile** group → Add Files → Select `Views/Profile/SpotifyPresentationContextProvider.swift`

4. **Services/Supabase/SpotifyConnectionService.swift**:
   - Right-click **Services/Supabase** group → Add Files → Select `Services/Supabase/SpotifyConnectionService.swift`

---

## After Adding Files

Once the files are added:
1. **Build again** (⌘B) - errors should be gone
2. **Install the xcodeproj gem** so automatic addition works:
   ```bash
   cd /Users/suinoikhioda/Documents/RockOut
   ./Rockout/scripts/install_xcodeproj.sh
   ```
3. Future files will be added automatically via the Build Phase script

