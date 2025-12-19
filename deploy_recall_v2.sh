#!/bin/bash

# Deploy Recall V2 - Intelligent Voice-First Conversational Implementation
# This script deploys the updated recall-resolve edge function to Supabase

set -e  # Exit on error

echo "🚀 Deploying Recall V2 to Supabase..."
echo ""

# Check if we're in the right directory
if [ ! -d "supabase/functions/recall-resolve" ]; then
    echo "❌ Error: Not in the RockOut project directory"
    echo "Please run this script from: /Users/chukwudiebube/Downloads/RockOut-main"
    exit 1
fi

# Check if supabase CLI is installed
if ! command -v supabase &> /dev/null; then
    echo "❌ Error: Supabase CLI not installed"
    echo "Install it with: brew install supabase/tap/supabase"
    exit 1
fi

echo "✅ Prerequisites check passed"
echo ""

# Deploy the function
echo "📦 Deploying recall-resolve function..."
cd supabase/functions
supabase functions deploy recall-resolve

echo ""
echo "✅ Deployment complete!"
echo ""
echo "📋 Next steps:"
echo ""
echo "1. Verify environment variables are set in Supabase:"
echo "   - OPENAI_API_KEY (required)"
echo "   - ACRCLOUD_ACCESS_KEY (optional)"
echo "   - ACRCLOUD_ACCESS_SECRET (optional)"
echo "   - SHAZAM_API_KEY (optional)"
echo ""
echo "2. Test the new flow:"
echo "   a) Voice conversation: 'Tell me about The Beatles'"
echo "   b) Humming: Hum a melody"
echo "   c) Background music: Play a song"
echo ""
echo "3. Monitor logs:"
echo "   supabase functions logs recall-resolve --follow"
echo ""
echo "🎉 Recall V2 is now live!"





