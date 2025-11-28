-- Fix storage policies for cover-art bucket
-- NOTE: Storage policies in Supabase are managed through the Storage UI
-- This script only ensures the bucket exists and is public
-- You'll need to set up the policies through the Supabase Dashboard

-- Ensure the bucket exists and is public
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'cover-art', 
    'cover-art', 
    true,
    10485760, -- 10MB limit
    ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/jpg']
)
ON CONFLICT (id) DO UPDATE 
SET 
    public = true,
    file_size_limit = 10485760,
    allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/jpg'];

-- Verify bucket exists
SELECT id, name, public, file_size_limit, allowed_mime_types
FROM storage.buckets
WHERE id = 'cover-art';

-- ============================================
-- IMPORTANT: Storage Policies Must Be Set Up in Dashboard
-- ============================================
-- 
-- Go to Supabase Dashboard → Storage → cover-art bucket → Policies
-- 
-- Create these policies manually:
--
-- 1. Policy Name: "Authenticated users can upload cover art"
--    - Operation: INSERT
--    - Target roles: authenticated
--    - Policy definition: bucket_id = 'cover-art'
--
-- 2. Policy Name: "Authenticated users can update cover art"
--    - Operation: UPDATE
--    - Target roles: authenticated
--    - Policy definition: bucket_id = 'cover-art'
--
-- 3. Policy Name: "Authenticated users can delete cover art"
--    - Operation: DELETE
--    - Target roles: authenticated
--    - Policy definition: bucket_id = 'cover-art'
--
-- 4. Policy Name: "Anyone can read cover art" (if bucket is public, this may not be needed)
--    - Operation: SELECT
--    - Target roles: anon, authenticated
--    - Policy definition: bucket_id = 'cover-art'
--
-- ============================================
