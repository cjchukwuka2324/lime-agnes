# Xcode Build Phase Setup - Automatic File Addition

This setup automatically adds new Swift files to your Xcode project **every time you build**. No manual steps needed!

## Quick Setup (5 minutes)

### Step 1: Open Xcode Project
Open `Rockout.xcodeproj` in Xcode.

### Step 2: Add Run Script Phase
1. Click on your **Rockout** project in the navigator (top left)
2. Select the **Rockout** target (under TARGETS)
3. Click the **Build Phases** tab
4. Click the **+** button at the top left
5. Select **New Run Script Phase**

### Step 3: Move to Top
1. **Drag the new "Run Script" phase** to the very top of the list
2. It should be **above "Compile Sources"**

### Step 4: Configure the Script

**Option A: Use External Script (Recommended)**
1. Expand the "Run Script" phase by clicking the disclosure triangle
2. In the script box, paste this:

```bash
"${SRCROOT}/Rockout/scripts/build_phase_add_files.sh"
```

**Option B: Use Inline Script (If Option A fails)**
If the external script doesn't work, paste this directly into the script box:

```bash
set +e
SCRIPT="${SRCROOT}/Rockout/scripts/auto_add_to_xcode.rb"
if command -v ruby > /dev/null 2>&1 && [ -f "$SCRIPT" ]; then
    ruby -e "require 'xcodeproj'" 2>/dev/null && ruby "$SCRIPT" > /dev/null 2>&1 || true
fi
exit 0
```

3. **Important Settings:**
   - ✅ **Shell**: `/bin/sh` (default)
   - ✅ **Show environment variables in build log**: **Unchecked** (to keep it clean)
   - ✅ **Run script only when installing**: **Unchecked** (we want it on every build)
   - ✅ **Based on dependency analysis**: **Unchecked**

### Step 5: Name the Phase (Optional)
1. Click on "Run Script" text to rename it
2. Change it to: **"Auto-Add New Files"** (for clarity)

### Step 6: Test It
1. Create a new Swift file in `Rockout/Views/` (or any subdirectory)
2. Build the project (⌘B or Product → Build)
3. The file should automatically appear in Xcode's navigator
4. Build again - it should compile without errors

## What This Does

Every time you build your project:
1. ✅ Script runs automatically (before compilation)
2. ✅ Scans for new Swift files in `Rockout/` directory
3. ✅ Adds them to the Xcode project
4. ✅ Organizes them into correct groups (Views/, Services/, etc.)
5. ✅ Adds them to build phases automatically
6. ✅ Saves the project file

**Result:** New files are immediately available for compilation! 🎉

## Requirements

The script will automatically check for:
- ✅ Ruby (usually pre-installed on macOS)
- ✅ `xcodeproj` gem (installed automatically if needed)

If the gem is missing, install it:
```bash
gem install xcodeproj
# Or if you need sudo:
sudo gem install xcodeproj
```

## How It Works

1. **Build Phase Script** (`build_phase_add_files.sh`):
   - Runs silently before compilation
   - Checks for Ruby and xcodeproj gem
   - Calls the Ruby script to add files
   - Never fails the build (errors are ignored)

2. **Ruby Script** (`auto_add_to_xcode.rb`):
   - Scans `Rockout/` for Swift files
   - Compares with files already in project
   - Adds missing files to correct groups
   - Updates build phases
   - Saves project file

## Example Workflow

1. You create: `Rockout/Views/Profile/EditNameView.swift`
2. You build the project (⌘B)
3. Script detects the new file
4. File is added to Xcode project automatically
5. File appears in `Views/Profile/` group
6. File is added to build phases
7. Build continues and compiles the new file

**No manual steps needed!**

## Troubleshooting

### Files not being added?

1. **Check if script is running:**
   - Temporarily enable "Show environment variables in build log"
   - Build the project and check the build log
   - You should see the script running

2. **Check Ruby is installed:**
   ```bash
   which ruby
   ruby --version
   ```

3. **Check xcodeproj gem:**
   ```bash
   gem list xcodeproj
   ```
   
   If missing, install:
   ```bash
   gem install xcodeproj
   ```

4. **Check script permissions:**
   ```bash
   ls -l Rockout/scripts/build_phase_add_files.sh
   ```
   
   Should show `-rwxr-xr-x`. If not:
   ```bash
   chmod +x Rockout/scripts/build_phase_add_files.sh
   ```

5. **Test script manually:**
   ```bash
   cd /Users/suinoikhioda/Documents/lime-agnes
   ./Rockout/scripts/build_phase_add_files.sh
   ```

### Build fails or script errors?

The script is designed to **never fail the build**. If you see errors:
1. Check the build log (enable "Show environment variables")
2. Run the Ruby script manually to see full error:
   ```bash
   cd /Users/suinoikhioda/Documents/lime-agnes
   ruby Rockout/scripts/auto_add_to_xcode.rb
   ```

### Script runs but files still not added?

1. Make sure Xcode project file is not locked
2. Close Xcode and run script manually:
   ```bash
   ruby Rockout/scripts/auto_add_to_xcode.rb
   ```
3. Check for permission errors
4. Verify the file path in the script matches your setup

## Disabling (if needed)

To temporarily disable:
1. Open Build Phases
2. Uncheck the "Auto-Add New Files" phase checkbox

To permanently remove:
1. Select the "Auto-Add New Files" phase
2. Press Delete key
3. Confirm deletion

## Manual Alternative

If you prefer to add files manually:
1. Remove the build phase
2. Run when needed:
   ```bash
   cd /Users/suinoikhioda/Documents/lime-agnes
   ruby Rockout/scripts/auto_add_to_xcode.rb
   ```

## Notes

- The script runs **silently** by default (no build log spam)
- It only processes **Swift files** (`.swift` extension)
- It skips files in `scripts/`, `.git/`, and build directories
- Files are organized into groups matching directory structure
- The script is **fast** - adds minimal time to build process

