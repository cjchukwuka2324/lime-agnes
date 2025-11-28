#!/bin/bash
# Xcode Build Phase Script - Auto-add new Swift files
# This script runs before "Compile Sources" to automatically add new files

# Ensure we always exit successfully
set +e
set +o pipefail

# Get paths
SCRIPT_DIR="${SRCROOT}/Rockout/scripts"
RUBY_SCRIPT="${SCRIPT_DIR}/auto_add_to_xcode.rb"

# Check prerequisites and exit silently if not available
command -v ruby > /dev/null 2>&1 || exit 0
[ -f "$RUBY_SCRIPT" ] || exit 0
ruby -e "require 'xcodeproj'" 2>/dev/null || exit 0

# Run the Ruby script, ignoring all errors
ruby "$RUBY_SCRIPT" > /dev/null 2>&1

# Always exit successfully
exit 0

