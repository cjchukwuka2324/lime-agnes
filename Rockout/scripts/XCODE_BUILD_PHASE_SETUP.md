# Xcode Build Phase Setup - Automatic File Addition

## Step-by-Step Instructions

### 1. Open Your Xcode Project
Open `Rockout.xcodeproj` in Xcode.

### 2. Add Run Script Phase
1. Click on your **Rockout** project in the navigator (top left)
2. Select the **Rockout** target (under TARGETS)
3. Click the **Build Phases** tab
4. Click the **+** button at the top
5. Select **New Run Script Phase**

### 3. Configure the Script
1. **Drag the Run Script Phase** to the very top (before "Compile Sources")
2. Expand the Run Script phase
3. In the script box, paste this:

```bash
if command -v ruby > /dev/null 2>&1; then
    ruby "${SRCROOT}/Rockout/scripts/auto_add_to_xcode.rb" 2>/dev/null || true
fi
```

### 4. Important Settings
- ✅ **Shell**: `/bin/sh` (default)
- ✅ **Show environment variables in build log**: Unchecked (to keep it clean)
- ✅ **Run script only when installing**: Unchecked (we want it on every build)

### 5. Test It
1. Create a new Swift file (or use an existing one that's not in the project)
2. Build the project (⌘B)
3. Check the build log - you should see files being added automatically
4. Verify the file appears in Xcode's navigator

## What This Does

Every time you build your project:
1. The script runs automatically
2. It scans for new Swift files
3. Adds them to the Xcode project
4. Organizes them into the correct groups
5. Adds them to build phases

**No manual work needed!** 🎉

## Alternative: Manual Run (if you prefer)

If you don't want it to run on every build, you can:
- Remove the Build Phase
- Run manually when needed:
  ```bash
  cd /Users/suinoikhioda/Documents/RockOut
  ruby Rockout/scripts/auto_add_to_xcode.rb
  ```

## Troubleshooting

**If it doesn't work:**
1. Check Ruby is installed: `which ruby`
2. Check xcodeproj gem: `gem list xcodeproj`
3. Install gem if needed: `./Rockout/scripts/install_xcodeproj.sh`
4. Check the build log for errors (enable "Show environment variables" temporarily)

**If you see errors:**
- Make sure Xcode is closed when running the script
- Check file permissions on the script
- Verify the path is correct: `${SRCROOT}/Rockout/scripts/auto_add_to_xcode.rb`

