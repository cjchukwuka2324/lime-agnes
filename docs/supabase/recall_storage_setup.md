# Recall Storage Bucket Setup

## Overview

The Recall feature requires a Supabase Storage bucket to store voice recordings and images uploaded by users.

## Bucket Configuration

### Create Bucket

1. Open Supabase Dashboard
2. Navigate to **Storage**
3. Click **New bucket**
4. Name: `recall-media`
5. **Public**: No (Private bucket)
6. Click **Create bucket**

### RLS Policies

The bucket should have RLS enabled with the following policies:

```sql
-- Allow authenticated users to upload to their own folder
CREATE POLICY "Users can upload to their own recall folder"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'recall-media' AND
  (storage.foldername(name))[1] = auth.uid()::text
);

-- Allow users to read their own files
CREATE POLICY "Users can read their own recall files"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'recall-media' AND
  (storage.foldername(name))[1] = auth.uid()::text
);

-- Allow users to delete their own files
CREATE POLICY "Users can delete their own recall files"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'recall-media' AND
  (storage.foldername(name))[1] = auth.uid()::text
);
```

## Path Structure

Files are stored with the following path pattern:

```
recall-media/{userId}/{recallId}/filename.ext
```

Examples:
- `recall-media/550e8400-e29b-41d4-a716-446655440000/123e4567-e89b-12d3-a456-426614174000/voice.m4a`
- `recall-media/550e8400-e29b-41d4-a716-446655440000/123e4567-e89b-12d3-a456-426614174000/image.jpg`

## Content Types

- Voice recordings: `audio/m4a`
- Images: `image/jpeg`

## Usage in Swift

The `RecallService.uploadMedia()` method handles uploads:

```swift
let mediaPath = try await service.uploadMedia(
    data: audioData,
    recallId: recallId,
    fileName: "voice.m4a",
    contentType: "audio/m4a"
)
```

## Edge Function Access

Edge Functions use the service role key to access storage, so they can read any file in the bucket for processing (e.g., transcription).

