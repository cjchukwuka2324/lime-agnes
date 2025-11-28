# Build Phase Script Troubleshooting

## If you see "Command PhaseScriptExecution failed with a nonzero exit code"

### Quick Fix

1. **Check the script path in Xcode:**
   - Make sure it's exactly: `"${SRCROOT}/Rockout/scripts/build_phase_add_files.sh"`
   - No extra quotes or spaces

2. **Verify script is executable:**
   ```bash
   chmod +x Rockout/scripts/build_phase_add_files.sh
   ```

3. **Test the script manually:**
   ```bash
   cd /Users/suinoikhioda/Documents/lime-agnes
   SRCROOT=/Users/suinoikhioda/Documents/lime-agnes bash Rockout/scripts/build_phase_add_files.sh
   echo "Exit code: $?"
   ```
   Should output: `Exit code: 0`

4. **Check Ruby and gem:**
   ```bash
   which ruby
   gem list xcodeproj
   ```

### Alternative: Use Inline Script

If the external script still fails, you can paste this directly into the Build Phase script box:

```bash
set +e
SCRIPT="${SRCROOT}/Rockout/scripts/auto_add_to_xcode.rb"
if command -v ruby > /dev/null 2>&1 && [ -f "$SCRIPT" ]; then
    ruby -e "require 'xcodeproj'" 2>/dev/null && ruby "$SCRIPT" > /dev/null 2>&1 || true
fi
exit 0
```

### Common Issues

1. **Project file locked by Xcode:**
   - The script tries to save the project file
   - If Xcode has it open, save might fail
   - This is OK - files will be added on next build
   - Script should still exit with 0

2. **Path issues:**
   - Make sure `${SRCROOT}` is set correctly
   - Script should be at: `${SRCROOT}/Rockout/scripts/build_phase_add_files.sh`

3. **Permissions:**
   - Script must be executable: `chmod +x`
   - User must have write access to project file

4. **Ruby/gem issues:**
   - Ruby must be in PATH
   - xcodeproj gem must be installed: `gem install xcodeproj`

### Debug Mode

To see what's happening, temporarily change the script to:

```bash
#!/bin/bash
set -x  # Enable debug output
# ... rest of script
```

Then check the build log to see where it fails.

