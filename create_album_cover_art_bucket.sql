-- Create new album-cover-art bucket
-- This is a fresh start without any existing policy conflicts

-- Create the bucket with proper settings
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'album-cover-art', 
    'album-cover-art', 
    true,  -- Public bucket for easy access
    10485760, -- 10MB file size limit
    ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/jpg'] -- Allowed image types
)
ON CONFLICT (id) DO UPDATE 
SET 
    public = true,
    file_size_limit = 10485760,
    allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/jpg'];

-- Verify bucket was created
SELECT 
    id, 
    name, 
    public, 
    file_size_limit, 
    allowed_mime_types,
    created_at
FROM storage.buckets
WHERE id = 'album-cover-art';

-- ============================================
-- NOW CREATE POLICIES IN DASHBOARD
-- ============================================
-- 
-- Go to: Supabase Dashboard → Storage → album-cover-art bucket → Policies → New Policy
-- 
-- Create these 4 policies:
--
-- 1. Policy Name: "Authenticated users can upload album cover art"
--    - Operation: INSERT
--    - Target roles: authenticated
--    - Policy definition: bucket_id = 'album-cover-art'
--
-- 2. Policy Name: "Authenticated users can update album cover art"
--    - Operation: UPDATE
--    - Target roles: authenticated
--    - Policy definition: bucket_id = 'album-cover-art'
--
-- 3. Policy Name: "Authenticated users can delete album cover art"
--    - Operation: DELETE
--    - Target roles: authenticated
--    - Policy definition: bucket_id = 'album-cover-art'
--
-- 4. Policy Name: "Anyone can read album cover art"
--    - Operation: SELECT
--    - Target roles: anon, authenticated
--    - Policy definition: bucket_id = 'album-cover-art'
--
-- ============================================

