# User Profile and Instagram Integration Setup

## Overview
The feed now uses real user data from signup (first name, last name) instead of demo users, and Instagram stories integration has been added to RockList leaderboard cards.

## Changes Made

### 1. Database Schema Update

**File**: `update_profiles_schema.sql`

The `profiles` table has been updated to include:
- `first_name` (TEXT)
- `last_name` (TEXT)
- `instagram_handle` (TEXT)

**To apply:**
1. Open Supabase SQL Editor
2. Run the contents of `update_profiles_schema.sql`
3. This will add the new columns to the existing `profiles` table

### 2. User Profile Service

**File**: `Rockout/Services/UserProfileService.swift`

New service for managing user profiles:
- `getCurrentUserProfile()` - Fetches current user's profile from Supabase
- `updateInstagramHandle(_:)` - Updates Instagram handle in profile
- `createOrUpdateProfile(firstName:lastName:displayName:)` - Creates/updates profile with name information

### 3. Updated Signup Form

**File**: `Rockout/Views/Auth/SignupForm.swift`

Now collects:
- First Name (required)
- Last Name (required)
- Email (required)
- Password (required)

After successful signup, automatically creates a profile entry with first and last name.

### 4. Dynamic User Data in Feed

**File**: `Rockout/Services/Feed/FeedService.swift`

- Removed demo user seeding
- `currentUserSummary()` now dynamically generates user info from profile:
  - Display Name: First + Last name, or display_name, or email prefix
  - Handle: Generated from email prefix (e.g., "@john")
  - Avatar Initials: First letter of first name + first letter of last name (e.g., "JD")
- All posts now use real authenticated user data

### 5. Instagram Stories Integration

**File**: `Rockout/Views/RockList/RockListView.swift`

Added Instagram handle management:
- **Instagram Button**: Opens Instagram stories URL if handle exists, otherwise prompts for handle
- **Instagram Handle Prompt Sheet**: Modal dialog to add/edit Instagram handle
- Handle is saved to `profiles.instagram_handle` in Supabase
- Stories URL format: `https://www.instagram.com/stories/{handle}/`

**Features:**
- Pre-fills existing handle when editing
- Validates handle input
- Automatically loads handle on view appear
- Link opens Instagram app to stories

## Database Migration Required

Run this SQL in Supabase SQL Editor:

```sql
ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS first_name TEXT,
ADD COLUMN IF NOT EXISTS last_name TEXT,
ADD COLUMN IF NOT EXISTS instagram_handle TEXT;

CREATE INDEX IF NOT EXISTS idx_profiles_instagram_handle 
ON profiles(instagram_handle) 
WHERE instagram_handle IS NOT NULL;
```

## Usage Flow

1. **Signup**: User enters first name, last name, email, password
2. **Profile Created**: Profile automatically created with name information
3. **Feed Posts**: Posts show real user name and avatar initials
4. **Instagram Integration**:
   - User clicks Instagram button on RockList card
   - If no handle: Prompt appears to add Instagram handle
   - If handle exists: Opens Instagram stories URL
   - Handle is saved and remembered for future use

## Next Steps

1. Run the SQL migration in Supabase
2. Test signup flow with first/last name collection
3. Test Instagram handle prompt and stories link
4. Verify feed shows real user names and initials

