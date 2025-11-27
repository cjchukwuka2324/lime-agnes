#!/bin/bash

# Setup script to install dependencies and configure auto-add to Xcode

echo "Setting up automatic Xcode file addition..."

# Check if xcodeproj gem is installed
if ! gem list xcodeproj -i > /dev/null 2>&1; then
    echo "Installing xcodeproj gem..."
    gem install xcodeproj
else
    echo "✓ xcodeproj gem already installed"
fi

# Make scripts executable
chmod +x "$(dirname "$0")/add_files_to_xcode.sh"
chmod +x "$(dirname "$0")/auto_add_to_xcode.rb"

echo ""
echo "✓ Setup complete!"
echo ""
echo "To automatically add files to Xcode project, run:"
echo "  ruby $(dirname "$0")/auto_add_to_xcode.rb"
echo ""
echo "Or add this to your .git/hooks/post-commit:"
echo "  ruby $(dirname "$0")/auto_add_to_xcode.rb"

