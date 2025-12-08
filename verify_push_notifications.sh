#!/bin/bash

# Push Notifications Verification Script
# This script checks if push notifications are properly configured

echo "🔔 Push Notifications Verification Checklist"
echo "============================================"
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check 1: Xcode Project Configuration
echo "1. Xcode Project Configuration"
echo "-------------------------------"

if [ -f "Rockout/Rockout.entitlements" ]; then
    if grep -q "aps-environment" "Rockout/Rockout.entitlements"; then
        echo -e "${GREEN}✅ Push Notifications capability enabled${NC}"
    else
        echo -e "${RED}❌ Push Notifications capability NOT found in entitlements${NC}"
    fi
else
    echo -e "${RED}❌ Entitlements file not found${NC}"
fi

if [ -f "Rockout/Info.plist" ]; then
    if grep -q "UIBackgroundModes" "Rockout/Info.plist" && grep -q "remote-notification" "Rockout/Info.plist"; then
        echo -e "${GREEN}✅ Background Modes configured for remote notifications${NC}"
    else
        echo -e "${YELLOW}⚠️  Background Modes may not be configured${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  Info.plist not found${NC}"
fi

echo ""

# Check 2: Required Files
echo "2. Required Files"
echo "-----------------"

files=(
    "Rockout/App/AppDelegate.swift"
    "Rockout/Services/Notifications/DeviceTokenService.swift"
    "supabase/functions/send_push_notification/index.ts"
    "sql/device_tokens_schema.sql"
    "sql/notifications_schema.sql"
    "sql/notification_triggers.sql"
    "sql/push_notification_trigger.sql"
)

for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        echo -e "${GREEN}✅ $file${NC}"
    else
        echo -e "${RED}❌ $file - MISSING${NC}"
    fi
done

echo ""

# Check 3: AppDelegate Implementation
echo "3. AppDelegate Implementation"
echo "------------------------------"

if grep -q "registerForRemoteNotifications" "Rockout/App/AppDelegate.swift"; then
    echo -e "${GREEN}✅ AppDelegate registers for remote notifications${NC}"
else
    echo -e "${RED}❌ AppDelegate does NOT register for remote notifications${NC}"
fi

if grep -q "didRegisterForRemoteNotificationsWithDeviceToken" "Rockout/App/AppDelegate.swift"; then
    echo -e "${GREEN}✅ AppDelegate handles device token registration${NC}"
else
    echo -e "${RED}❌ AppDelegate does NOT handle device token registration${NC}"
fi

if grep -q "DeviceTokenService" "Rockout/App/AppDelegate.swift"; then
    echo -e "${GREEN}✅ AppDelegate uses DeviceTokenService${NC}"
else
    echo -e "${RED}❌ AppDelegate does NOT use DeviceTokenService${NC}"
fi

echo ""

# Check 4: DeviceTokenService
echo "4. DeviceTokenService"
echo "---------------------"

if grep -q "registerDeviceToken" "Rockout/Services/Notifications/DeviceTokenService.swift"; then
    echo -e "${GREEN}✅ DeviceTokenService has registerDeviceToken method${NC}"
else
    echo -e "${RED}❌ DeviceTokenService missing registerDeviceToken method${NC}"
fi

if grep -q "device_tokens" "Rockout/Services/Notifications/DeviceTokenService.swift"; then
    echo -e "${GREEN}✅ DeviceTokenService uses device_tokens table${NC}"
else
    echo -e "${RED}❌ DeviceTokenService does NOT use device_tokens table${NC}"
fi

echo ""

# Check 5: Edge Function
echo "5. Edge Function"
echo "----------------"

if [ -f "supabase/functions/send_push_notification/index.ts" ]; then
    if grep -q "APNs\|apns" "supabase/functions/send_push_notification/index.ts"; then
        echo -e "${GREEN}✅ Edge Function includes APNs implementation${NC}"
    else
        echo -e "${YELLOW}⚠️  Edge Function may not have APNs implementation${NC}"
    fi
    
    if grep -q "device_tokens" "supabase/functions/send_push_notification/index.ts"; then
        echo -e "${GREEN}✅ Edge Function queries device_tokens table${NC}"
    else
        echo -e "${RED}❌ Edge Function does NOT query device_tokens table${NC}"
    fi
else
    echo -e "${RED}❌ Edge Function file not found${NC}"
fi

echo ""

# Check 6: Database Schema
echo "6. Database Schema"
echo "-------------------"

if [ -f "sql/device_tokens_schema.sql" ]; then
    if grep -q "CREATE TABLE.*device_tokens" "sql/device_tokens_schema.sql"; then
        echo -e "${GREEN}✅ device_tokens table schema exists${NC}"
    else
        echo -e "${RED}❌ device_tokens table schema incomplete${NC}"
    fi
else
    echo -e "${RED}❌ device_tokens_schema.sql not found${NC}"
fi

if [ -f "sql/notification_triggers.sql" ]; then
    if grep -q "CREATE TRIGGER.*notification" "sql/notification_triggers.sql"; then
        echo -e "${GREEN}✅ Notification triggers schema exists${NC}"
    else
        echo -e "${RED}❌ Notification triggers schema incomplete${NC}"
    fi
else
    echo -e "${RED}❌ notification_triggers.sql not found${NC}"
fi

if [ -f "sql/push_notification_trigger.sql" ]; then
    if grep -q "trigger_push_notification" "sql/push_notification_trigger.sql"; then
        echo -e "${GREEN}✅ Push notification trigger exists${NC}"
    else
        echo -e "${RED}❌ Push notification trigger incomplete${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  push_notification_trigger.sql not found (optional)${NC}"
fi

echo ""

# Check 7: RootAppView Integration
echo "7. RootAppView Integration"
echo "-------------------------"

if grep -q "registerForRemoteNotifications" "Rockout/Views/RootAppView.swift"; then
    echo -e "${GREEN}✅ RootAppView re-registers for notifications on auth${NC}"
else
    echo -e "${YELLOW}⚠️  RootAppView may not re-register for notifications${NC}"
fi

echo ""

# Summary
echo "============================================"
echo "📋 Next Steps:"
echo ""
echo "1. Verify in Supabase Dashboard:"
echo "   - Run SQL scripts: device_tokens_schema.sql, notifications_schema.sql, notification_triggers.sql"
echo "   - Deploy Edge Function: supabase functions deploy send_push_notification"
echo "   - Set APNs secrets: supabase secrets set APNS_KEY_ID=... (see PUSH_NOTIFICATIONS_SETUP.md)"
echo ""
echo "2. Test on Physical Device:"
echo "   - Build and run on iPhone/iPad (not simulator)"
echo "   - Grant notification permissions"
echo "   - Check Xcode console for device token registration"
echo "   - Verify token appears in device_tokens table"
echo ""
echo "3. Test Push Notification:"
echo "   - Follow a user or like a post"
echo "   - Check if push notification is received"
echo ""
echo "For detailed setup instructions, see:"
echo "  - NOTIFICATIONS_SETUP.md"
echo "  - PUSH_NOTIFICATIONS_SETUP.md"
echo ""

