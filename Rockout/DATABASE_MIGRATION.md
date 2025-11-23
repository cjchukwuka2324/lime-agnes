# Database Migration Guide

This document outlines the database schema changes needed for the new StudioSessions features: Sharing, Version History, and Audio Player.

## Required Tables

### 1. `shareable_links` Table

```sql
CREATE TABLE shareable_links (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    resource_type TEXT NOT NULL CHECK (resource_type IN ('album', 'track')),
    resource_id UUID NOT NULL,
    share_token TEXT NOT NULL UNIQUE,
    created_by UUID NOT NULL REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    password TEXT,
    expires_at TIMESTAMPTZ,
    access_count INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    UNIQUE(resource_type, resource_id, created_by)
);

CREATE INDEX idx_shareable_links_token ON shareable_links(share_token);
CREATE INDEX idx_shareable_links_resource ON shareable_links(resource_type, resource_id);
```

### 2. `listeners` Table

```sql
CREATE TABLE listeners (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    share_link_id UUID NOT NULL REFERENCES shareable_links(id) ON DELETE CASCADE,
    resource_type TEXT NOT NULL,
    resource_id UUID NOT NULL,
    listener_id UUID REFERENCES auth.users(id), -- NULL for anonymous listeners
    listened_at TIMESTAMPTZ DEFAULT NOW(),
    duration_listened DOUBLE PRECISION -- How long they listened in seconds
);

CREATE INDEX idx_listeners_share_link ON listeners(share_link_id);
CREATE INDEX idx_listeners_resource ON listeners(resource_type, resource_id);
```

### 3. `track_versions` Table

```sql
CREATE TABLE track_versions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    track_id UUID NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
    version_number INTEGER NOT NULL,
    audio_url TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    created_by UUID NOT NULL REFERENCES auth.users(id),
    notes TEXT,
    file_size BIGINT, -- File size in bytes
    duration DOUBLE PRECISION, -- Duration in seconds
    UNIQUE(track_id, version_number)
);

CREATE INDEX idx_track_versions_track ON track_versions(track_id);
CREATE INDEX idx_track_versions_created ON track_versions(created_at DESC);
```

## Row Level Security (RLS) Policies

### shareable_links

```sql
-- Enable RLS
ALTER TABLE shareable_links ENABLE ROW LEVEL SECURITY;

-- Users can view their own share links
CREATE POLICY "Users can view own share links"
    ON shareable_links FOR SELECT
    USING (auth.uid() = created_by);

-- Users can create share links for their own resources
CREATE POLICY "Users can create own share links"
    ON shareable_links FOR INSERT
    WITH CHECK (auth.uid() = created_by);

-- Users can update their own share links
CREATE POLICY "Users can update own share links"
    ON shareable_links FOR UPDATE
    USING (auth.uid() = created_by);

-- Public can view active share links (for sharing functionality)
CREATE POLICY "Public can view active share links"
    ON shareable_links FOR SELECT
    USING (is_active = true);
```

### listeners

```sql
-- Enable RLS
ALTER TABLE listeners ENABLE ROW LEVEL SECURITY;

-- Anyone can insert listener records (for tracking)
CREATE POLICY "Anyone can record listeners"
    ON listeners FOR INSERT
    WITH CHECK (true);

-- Users can view listeners for their own share links
CREATE POLICY "Users can view own listeners"
    ON listeners FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM shareable_links
            WHERE shareable_links.id = listeners.share_link_id
            AND shareable_links.created_by = auth.uid()
        )
    );
```

### track_versions

```sql
-- Enable RLS
ALTER TABLE track_versions ENABLE ROW LEVEL SECURITY;

-- Users can view versions for tracks they own
CREATE POLICY "Users can view own track versions"
    ON track_versions FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM tracks
            WHERE tracks.id = track_versions.track_id
            AND tracks.artist_id = auth.uid()
        )
    );

-- Users can create versions for their own tracks
CREATE POLICY "Users can create own track versions"
    ON track_versions FOR INSERT
    WITH CHECK (
        auth.uid() = created_by
        AND EXISTS (
            SELECT 1 FROM tracks
            WHERE tracks.id = track_versions.track_id
            AND tracks.artist_id = auth.uid()
        )
    );

-- Users can delete their own track versions
CREATE POLICY "Users can delete own track versions"
    ON track_versions FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM tracks
            WHERE tracks.id = track_versions.track_id
            AND tracks.artist_id = auth.uid()
        )
    );
```

## Storage Bucket Setup

Make sure your `studio` storage bucket exists and has proper policies:

```sql
-- Create bucket if it doesn't exist
INSERT INTO storage.buckets (id, name, public)
VALUES ('studio', 'studio', false)
ON CONFLICT (id) DO NOTHING;

-- Allow authenticated users to upload
CREATE POLICY "Authenticated users can upload"
    ON storage.objects FOR INSERT
    WITH CHECK (
        bucket_id = 'studio'
        AND auth.role() = 'authenticated'
    );

-- Allow authenticated users to read their own files
CREATE POLICY "Users can read own files"
    ON storage.objects FOR SELECT
    USING (
        bucket_id = 'studio'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

-- Allow public read for shared files (if needed)
-- You might want to create a separate bucket for public shares
```

## Notes

1. **Share Tokens**: The `share_token` should be a unique, URL-safe string. The code generates UUIDs without dashes.

2. **Version Numbers**: Version numbers start at 1 and increment. The code handles this automatically.

3. **File Storage**: Track versions are stored in `tracks/{album_id}/{track_id}/versions/` path structure.

4. **Deep Links**: The share URLs use the format `rockout://share/{share_token}`. Make sure your app handles this URL scheme.

5. **Password Protection**: Passwords are stored in plain text (for now). Consider hashing them if security is a concern.

6. **Access Count**: The access count is incremented when listeners are recorded. This requires fetching the current count and updating it.

## Testing

After running these migrations, test:

1. Create a share link for an album/track
2. Record a listener
3. Create a track version
4. View version history
5. Restore a previous version

