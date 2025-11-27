# Automatic Xcode File Addition

This setup automatically adds new Swift files to your Xcode project when they're created. The detection is **clean and accurate** - it only shows files that truly need to be added, avoiding duplicates.

## Quick Setup

Run the setup script:

```bash
cd /Users/suinoikhioda/Documents/RockOut
./Rockout/scripts/install_xcodeproj.sh
```

This will install the `xcodeproj` Ruby gem needed for automatic addition.

## Manual Usage

### Check for New Files:
```bash
cd /Users/suinoikhioda/Documents/RockOut
./Rockout/scripts/clean_and_add_files.sh
```

This will show you exactly which files need to be added (no duplicates, no false positives).

### Automatically Add Files:
```bash
cd /Users/suinoikhioda/Documents/RockOut
ruby Rockout/scripts/auto_add_to_xcode.rb
```

This will automatically add all new files to the Xcode project.

## How It Works

1. **Clean Detection** (`clean_and_add_files.sh`): 
   - Extracts all Swift filenames from `project.pbxproj`
   - Compares against actual files in the `Rockout/` directory
   - Only shows files that are truly missing
   - **No duplicates, no false positives**

2. **Automatic Addition** (`auto_add_to_xcode.rb`): 
   - Uses the `xcodeproj` gem to programmatically add files
   - Automatically organizes files into correct groups
   - Adds files to build phases
   - Cleans up the `new_files_to_add.txt` file after adding

3. **Git Hook** (`.git/hooks/post-commit`):
   - Automatically runs after each commit
   - Adds any new files to the Xcode project

## File Organization

Files are automatically organized into Xcode groups based on their directory:
- `Views/` → Views group
- `ViewModels/` → ViewModels group  
- `Services/` → Services group
- `Models/` → Models group
- `App/` → App group
- `Utils/` → Utils group

## Example Output

When you run `clean_and_add_files.sh`, you'll see:

```
📦 Xcode Project: /Users/suinoikhioda/Documents/RockOut/Rockout.xcodeproj
🔍 Scanning for new Swift files...

  ➕ Models/SpotifyConnection.swift
  ➕ Views/Profile/SpotifyConnectionView.swift

📋 Found 2 new file(s) that need to be added
```

Clean and accurate - no duplicates!

## Troubleshooting

If files aren't being added automatically:

1. **Check xcodeproj gem is installed:**
   ```bash
   gem list xcodeproj
   ```

2. **Install if missing:**
   ```bash
   ./Rockout/scripts/install_xcodeproj.sh
   ```

3. **Run manually:**
   ```bash
   cd /Users/suinoikhioda/Documents/RockOut
   ruby Rockout/scripts/auto_add_to_xcode.rb
   ```

4. **Check Xcode project is writable:**
   - Make sure `Rockout.xcodeproj` is not locked
   - Close Xcode before running the script

## Alternative: Xcode Build Phase

You can also add this as a Build Phase in Xcode:

1. Open Xcode project
2. Select the Rockout target
3. Go to Build Phases
4. Click "+" → New Run Script Phase
5. Drag it to the top (before Compile Sources)
6. Add:
   ```bash
   if command -v ruby > /dev/null 2>&1; then
       ruby "${SRCROOT}/../Rockout/scripts/auto_add_to_xcode.rb" 2>/dev/null || true
   fi
   ```

This will run the script before each build, ensuring new files are always added.
