-- ============================================
-- Recall v2 Storage Buckets Setup
-- ============================================
-- Creates storage buckets for Recall v2 if they don't exist
-- Run this in Supabase Dashboard → SQL Editor
-- ============================================

-- Create recall-audio bucket (for voice notes, background audio, humming)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'recall-audio',
    'recall-audio',
    false, -- Private bucket
    10485760, -- 10MB limit
    ARRAY['audio/m4a', 'audio/mp3', 'audio/wav', 'audio/aac', 'audio/ogg']
)
ON CONFLICT (id) DO UPDATE SET
    file_size_limit = 10485760,
    allowed_mime_types = ARRAY['audio/m4a', 'audio/mp3', 'audio/wav', 'audio/aac', 'audio/ogg'];

-- Create recall-images bucket (for image uploads)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'recall-images',
    'recall-images',
    false, -- Private bucket
    5242880, -- 5MB limit
    ARRAY['image/jpeg', 'image/png', 'image/heic', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET
    file_size_limit = 5242880,
    allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/heic', 'image/webp'];

-- Create recall-background bucket (for background listening mode)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'recall-background',
    'recall-background',
    false, -- Private bucket
    10485760, -- 10MB limit
    ARRAY['audio/m4a', 'audio/mp3', 'audio/wav', 'audio/aac']
)
ON CONFLICT (id) DO UPDATE SET
    file_size_limit = 10485760,
    allowed_mime_types = ARRAY['audio/m4a', 'audio/mp3', 'audio/wav', 'audio/aac'];

-- ============================================
-- Storage RLS Policies
-- ============================================

-- Policy: Users can upload to their own folder in recall-audio
DROP POLICY IF EXISTS "Users can upload audio to their own folder" ON storage.objects;
CREATE POLICY "Users can upload audio to their own folder"
ON storage.objects
FOR INSERT
WITH CHECK (
    bucket_id = 'recall-audio' AND
    (storage.foldername(name))[1] = auth.uid()::text
);

-- Policy: Users can read their own audio files
DROP POLICY IF EXISTS "Users can read their own audio" ON storage.objects;
CREATE POLICY "Users can read their own audio"
ON storage.objects
FOR SELECT
USING (
    bucket_id = 'recall-audio' AND
    (storage.foldername(name))[1] = auth.uid()::text
);

-- Policy: Service role can read all audio files
DROP POLICY IF EXISTS "Service role can read all audio" ON storage.objects;
CREATE POLICY "Service role can read all audio"
ON storage.objects
FOR SELECT
USING (
    bucket_id = 'recall-audio' AND
    auth.jwt() ->> 'role' = 'service_role'
);

-- Policy: Users can upload to their own folder in recall-images
DROP POLICY IF EXISTS "Users can upload images to their own folder" ON storage.objects;
CREATE POLICY "Users can upload images to their own folder"
ON storage.objects
FOR INSERT
WITH CHECK (
    bucket_id = 'recall-images' AND
    (storage.foldername(name))[1] = auth.uid()::text
);

-- Policy: Users can read their own images
DROP POLICY IF EXISTS "Users can read their own images" ON storage.objects;
CREATE POLICY "Users can read their own images"
ON storage.objects
FOR SELECT
USING (
    bucket_id = 'recall-images' AND
    (storage.foldername(name))[1] = auth.uid()::text
);

-- Policy: Service role can read all images
DROP POLICY IF EXISTS "Service role can read all images" ON storage.objects;
CREATE POLICY "Service role can read all images"
ON storage.objects
FOR SELECT
USING (
    bucket_id = 'recall-images' AND
    auth.jwt() ->> 'role' = 'service_role'
);

-- Policy: Users can upload to their own folder in recall-background
DROP POLICY IF EXISTS "Users can upload background audio to their own folder" ON storage.objects;
CREATE POLICY "Users can upload background audio to their own folder"
ON storage.objects
FOR INSERT
WITH CHECK (
    bucket_id = 'recall-background' AND
    (storage.foldername(name))[1] = auth.uid()::text
);

-- Policy: Users can read their own background audio
DROP POLICY IF EXISTS "Users can read their own background audio" ON storage.objects;
CREATE POLICY "Users can read their own background audio"
ON storage.objects
FOR SELECT
USING (
    bucket_id = 'recall-background' AND
    (storage.foldername(name))[1] = auth.uid()::text
);

-- Policy: Service role can read all background audio
DROP POLICY IF EXISTS "Service role can read all background audio" ON storage.objects;
CREATE POLICY "Service role can read all background audio"
ON storage.objects
FOR SELECT
USING (
    bucket_id = 'recall-background' AND
    auth.jwt() ->> 'role' = 'service_role'
);

-- Verify buckets were created
SELECT 
    id,
    name,
    public,
    file_size_limit,
    allowed_mime_types,
    '✅ Created' as status
FROM storage.buckets 
WHERE name LIKE 'recall%'
ORDER BY name;







