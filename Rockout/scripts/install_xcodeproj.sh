#!/bin/bash

# Install xcodeproj gem for automatic file addition

echo "Installing xcodeproj gem..."

# Check if gem is available
if ! command -v gem > /dev/null 2>&1; then
    echo "❌ Ruby gem command not found. Please install Ruby first."
    exit 1
fi

# Install xcodeproj gem
if gem install xcodeproj; then
    echo "✅ xcodeproj gem installed successfully!"
    echo ""
    echo "You can now use: ruby scripts/auto_add_to_xcode.rb"
else
    echo "❌ Failed to install xcodeproj gem"
    echo "You may need to use: sudo gem install xcodeproj"
    exit 1
fi

