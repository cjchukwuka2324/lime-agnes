#!/bin/bash
# Wrapper script to run git commands with fixed environment
export cursor_snap_ENV_VARS=""
export SHELL=/bin/bash

# Define dump_zsh_state if needed
dump_zsh_state() { return 0; }
export -f dump_zsh_state

# Execute the git command
cd /Users/chukwudiebube/Downloads/RockOut-main
exec "$@"
