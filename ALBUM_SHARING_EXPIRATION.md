# Album Sharing with Expiration and Revocation

This document describes the time-based sharing controls for albums, allowing shares to be set for a specific duration or indefinitely, with the ability to revoke access at any time.

## Features Implemented

### 1. **Expiration Controls**
- Albums can be shared **indefinitely** (default) or for a **specific duration**
- When creating a share link, users can toggle expiration on/off
- If expiration is enabled, users can select a date and time for the link to expire
- Expiration date must be in the future

### 2. **Expiration Validation**
- When someone tries to accept a shared album, the system checks if the share link has expired
- Expired links cannot be used and show an appropriate error message
- Expiration is checked server-side for security

### 3. **Revoke Access**
- Share link owners can revoke access at any time
- Revoking immediately sets `is_active = false` in the database
- Anyone trying to use a revoked link will see an error
- Revocation is irreversible (but a new link can be created)

### 4. **Share Link Management UI**
- View existing share link details including:
  - Expiration date (if set)
  - Indefinite status indicator
  - Collaboration mode indicator
- Revoke button with confirmation dialog
- Automatic loading of existing share links when opening the share sheet

## Database Migration Required

**You need to run a migration** to ensure all columns exist. The migration file is:
- `sql/add_share_link_expiration.sql`

This migration safely adds the `is_collaboration` column if missing and verifies that `expires_at` and `is_active` columns exist.

## Database Schema

The `shareable_links` table should have the following columns for expiration and collaboration support:

```sql
CREATE TABLE shareable_links (
    ...
    expires_at TIMESTAMPTZ,  -- Optional expiration timestamp
    is_active BOOLEAN DEFAULT true,  -- Can be set to false to revoke
    is_collaboration BOOLEAN DEFAULT false,  -- Whether link allows collaboration
    ...
);
```

**Note:** If your database doesn't have `is_collaboration` column yet, run the migration file:
- `sql/add_share_link_expiration.sql` - Adds `is_collaboration` column if missing and ensures all expiration fields exist

## Implementation Details

### ShareService Updates

1. **`createShareLink(for:isCollaboration:expiresAt:)`**
   - Now accepts optional `expiresAt: Date?` parameter
   - Stores expiration in ISO8601 format in database
   - Updates existing links with new expiration if link already exists

2. **`acceptSharedAlbum(shareToken:)`**
   - Validates expiration before allowing access
   - Returns error if link has expired
   - Checks both `is_active` flag and expiration timestamp

3. **`revokeShareLink(shareToken:)`**
   - Verifies user owns the share link
   - Sets `is_active = false` in database
   - Prevents future access via this token

4. **`getShareLinkDetails(for:)`**
   - Fetches complete share link information
   - Includes expiration date, collaboration status, etc.
   - Used to display link details in UI

### UI Components

#### ShareSheetView
- **Expiration Toggle**: Allows users to enable/disable expiration
- **Date Picker**: Appears when expiration is enabled
- **Expiration Display**: Shows expiration date or "Never expires" badge
- **Revoke Button**: Allows immediate revocation with confirmation
- **Auto-load**: Automatically loads existing share link details on view appear

## User Flow

### Creating a Share Link with Expiration

1. User opens share sheet for an album
2. User selects collaboration mode (view-only or collaborate)
3. User toggles "Link Expiration" on
4. User selects expiration date and time using date picker
5. User taps "Create Share Link"
6. Share link is created with expiration stored in database
7. Share link view shows expiration badge with date

### Creating an Indefinite Share Link

1. User opens share sheet for an album
2. User selects collaboration mode
3. User leaves "Link Expiration" toggle off (default)
4. User taps "Create Share Link"
5. Share link is created with `expires_at = NULL` (never expires)
6. Share link view shows "Never expires" badge

### Revoking a Share Link

1. User opens share sheet with existing link
2. User sees share link details including expiration status
3. User taps "Revoke Access" button
4. Confirmation dialog appears
5. User confirms revocation
6. Share link is immediately deactivated
7. Share link view resets, allowing creation of new link

### Accepting an Expired Share

1. User receives share link
2. User opens link in app
3. System validates expiration date
4. If expired, user sees error: "This share link has expired"
5. Access is denied

## Security Considerations

- Expiration is validated server-side (cannot be bypassed)
- Revocation requires ownership verification
- Expired/revoked links are filtered at database level
- Share tokens remain unique and secure

## Future Enhancements

- Email notifications when shares are about to expire
- Automatic cleanup of expired shares
- Share link analytics (access count, last accessed, etc.)
- Ability to extend expiration date
- Multiple share links per album with different permissions

