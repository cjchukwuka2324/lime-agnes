# Fix: Files Being Added to Wrong Groups in Xcode

## Problem
When adding files to Xcode, they appear in the root "Rockout" group instead of their proper folders. Moving them creates duplicates.

## Solution: Add Files from Correct Groups

### Step-by-Step Fix:

#### 1. Remove Incorrectly Placed Files
- In Xcode Project Navigator, find files in the wrong location
- **Right-click each file** → **Delete**
- Choose **"Remove Reference"** (NOT "Move to Trash")
- This removes the Xcode reference but keeps the actual file

#### 2. Add to Correct Groups

**For `Models/SpotifyConnection.swift`:**
1. Right-click the **`Models`** group in Project Navigator
2. Select **"Add Files to Rockout..."**
3. Navigate to `Rockout/Models/SpotifyConnection.swift`
4. Settings:
   - ✅ **Uncheck** "Copy items if needed"
   - ✅ Select **"Create groups"** (not folder references)
   - ✅ **Check** "Add to targets: Rockout"
5. Click **Add**

**For `Views/Profile/SpotifyConnectionView.swift`:**
1. Right-click the **`Views/Profile`** group (not just Views)
2. Select **"Add Files to Rockout..."**
3. Navigate to `Rockout/Views/Profile/SpotifyConnectionView.swift`
4. Same settings as above
5. Click **Add**

**For `Views/Profile/SpotifyPresentationContextProvider.swift`:**
1. Same as above - add from `Views/Profile` group

**For `Services/Supabase/SpotifyConnectionService.swift`:**
1. Right-click the **`Services/Supabase`** group
2. Select **"Add Files to Rockout..."**
3. Navigate to `Rockout/Services/Supabase/SpotifyConnectionService.swift`
4. Same settings
5. Click **Add**

### Key Points:
- ✅ **Always right-click the DESTINATION group** first
- ✅ **Don't check "Copy items if needed"** - files already exist
- ✅ **Use "Create groups"** not folder references
- ✅ **Make sure target is checked** so files compile

### After Adding:
- Files should appear in the correct groups
- Build the project (⌘B) - errors should be gone
- No duplicates should be created

### Prevention:
Once you add files this way, the automatic script will also add future files to correct groups. The script has been updated to handle this properly.

