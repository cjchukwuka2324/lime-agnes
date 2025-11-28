-- Delete and recreate cover-art bucket with proper setup
-- This will remove all existing policies and files

-- First, delete the bucket (this will also delete all policies and files)
DELETE FROM storage.buckets 
WHERE id = 'cover-art';

-- Recreate the bucket with proper settings
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'cover-art', 
    'cover-art', 
    true,  -- Public bucket for easy access
    10485760, -- 10MB file size limit
    ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/jpg'] -- Allowed image types
);

-- Verify bucket was created
SELECT 
    id, 
    name, 
    public, 
    file_size_limit, 
    allowed_mime_types,
    created_at
FROM storage.buckets
WHERE id = 'cover-art';

-- ============================================
-- NOW CREATE POLICIES IN DASHBOARD
-- ============================================
-- 
-- After running this script, go to:
-- Supabase Dashboard → Storage → cover-art bucket → Policies → New Policy
-- 
-- Create these 4 policies (one at a time):
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
-- 4. Policy Name: "Anyone can read cover art"
--    - Operation: SELECT
--    - Target roles: anon, authenticated
--    - Policy definition: bucket_id = 'cover-art'
--
-- ============================================

