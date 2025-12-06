# Public Albums Functionality Implementation

This document describes the implementation of the public/private album functionality for Studio Sessions.

## Overview

Users can now mark their albums as public or private. Public albums are discoverable when someone searches for the user's @username or email address.

## Database Changes

### Migration File: `sql/add_public_albums.sql`

1. **Added `is_public` column** to `albums` table
   - Type: `BOOLEAN`
   - Default: `FALSE` (private by default)
   - Indexed for efficient queries

2. **Created RPC function** `search_public_albums_by_user()`
   - Searches for public albums by user email or username
   - Returns matching public albums
   - Can be called from the Swift client

3. **Created view** `public_albums_view`
   - Convenient view for querying public albums with user information

## Code Changes

### Models

- **`StudioAlbumRecord`**: Added `is_public: Bool?` property

### Services

- **`AlbumService`**:
  - Updated `createAlbum()` to accept `isPublic` parameter (defaults to `false`)
  - Updated `updateAlbum()` to accept `isPublic` parameter
  - Added `searchPublicAlbumsByUser()` method to find public albums by email/username

### ViewModels

- **`StudioSessionsViewModel`**:
  - Updated `createAlbum()` to accept and pass through `isPublic` parameter

### Views

- **`StudioSessionsView`** (create album sheet):
  - Added public/private toggle UI
  - Added state variable `isPublic`
  - Updated album creation to include visibility setting

- **`EditAlbumView`**:
  - Added public/private toggle UI
  - Added state variable `isPublic` (initialized from album)
  - Updated album update to include visibility changes

## Usage

### Creating a Public Album

1. Tap the "+" button in Studio Sessions
2. Fill in album details
3. Toggle "Visibility" to Public
4. Create the album

### Editing Album Visibility

1. Open an album
2. Tap "Edit"
3. Toggle "Visibility" to Public or Private
4. Save changes

### Searching for Public Albums

Use the `AlbumService.searchPublicAlbumsByUser()` method:

```swift
let albums = try await AlbumService.shared.searchPublicAlbumsByUser(
    query: "@username",  // or email address
    limit: 50
)
```

## Future Enhancements

- Create a dedicated search UI for finding public albums
- Add search by album title/keywords
- Add public album discovery feed
- Add analytics for public album views

## Database Migration Instructions

Run the SQL migration file in your Supabase SQL editor:

```sql
-- Execute sql/add_public_albums.sql
```

This will:
- Add the `is_public` column to existing albums (defaults to `FALSE`)
- Create indexes for efficient queries
- Create the search RPC function
- Create the public albums view

