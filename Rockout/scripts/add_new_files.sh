#!/bin/bash

# Simple script to help add new files to Xcode project
# This creates a list of files that need to be added
# Uses the same logic as clean_and_add_files.sh

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Use the clean script which has better detection
exec "$SCRIPT_DIR/scripts/clean_and_add_files.sh"

