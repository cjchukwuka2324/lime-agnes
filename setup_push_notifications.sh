#!/bin/bash

# RockOut Push Notifications Setup Script
# This script configures APNs credentials and deploys the Edge Function

set -e  # Exit on error

echo "🔔 RockOut Push Notifications Setup"
echo "===================================="
echo ""

# Check if Supabase CLI is installed
if ! command -v supabase &> /dev/null; then
    echo "❌ Supabase CLI not found!"
    echo ""
    echo "Install it with:"
    echo "  brew install supabase/tap/supabase"
    echo "  or"
    echo "  npm install -g supabase"
    echo ""
    exit 1
fi

echo "✅ Supabase CLI found: $(supabase --version)"
echo ""

# Navigate to project directory
cd "$(dirname "$0")"
PROJECT_DIR=$(pwd)
echo "📁 Project directory: $PROJECT_DIR"
echo ""

# Check if AuthKey file exists
APNS_KEY_FILE="$PROJECT_DIR/AuthKey_HC2445Y3JA.p8"
if [ ! -f "$APNS_KEY_FILE" ]; then
    echo "❌ APNs key file not found: $APNS_KEY_FILE"
    echo "Please ensure the file is in the project root directory."
    exit 1
fi

echo "✅ APNs key file found"
echo ""

# Configure APNs secrets
echo "📝 Configuring APNs secrets..."
echo ""

echo "Setting APNS_KEY_ID..."
supabase secrets set APNS_KEY_ID="HC2445Y3JA"

echo "Setting APNS_TEAM_ID..."
supabase secrets set APNS_TEAM_ID="L5Y7VL3X35"

echo "Setting APNS_KEY_P8..."
supabase secrets set APNS_KEY_P8="$(cat "$APNS_KEY_FILE")"

echo "Setting APNS_BUNDLE_ID..."
supabase secrets set APNS_BUNDLE_ID="suinoik.RockOut"

echo "Setting APNS_PRODUCTION..."
supabase secrets set APNS_PRODUCTION="true"

echo ""
echo "✅ All secrets configured!"
echo ""

# List secrets to verify
echo "📋 Verifying secrets..."
supabase secrets list
echo ""

# Deploy Edge Function
echo "🚀 Deploying Edge Function..."
echo ""
supabase functions deploy send_push_notification

echo ""
echo "✅ Edge Function deployed!"
echo ""

# Summary
echo "======================================"
echo "✨ Push Notifications Setup Complete!"
echo "======================================"
echo ""
echo "Next steps:"
echo "1. Open Xcode and add Push Notifications capability"
echo "2. Enable Background Modes → Remote notifications"
echo "3. Build and run on a physical iOS device (not Simulator)"
echo "4. Grant notification permissions when prompted"
echo "5. Test by following a user or liking a post"
echo ""
echo "For detailed instructions, see: PUSH_NOTIFICATIONS_SETUP.md"
echo ""
echo "To view Edge Function logs:"
echo "  supabase functions logs send_push_notification --follow"
echo ""

