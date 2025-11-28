-- This script verifies the bucket exists
-- Then you'll create NEW policies with different names in the Dashboard

-- Verify bucket exists
SELECT 
    id, 
    name, 
    public, 
    file_size_limit, 
    allowed_mime_types
FROM storage.buckets
WHERE id = 'cover-art';

-- Check existing policies (for reference)
SELECT 
    policyname,
    cmd,
    roles
FROM pg_policies
WHERE tablename = 'objects' 
  AND schemaname = 'storage'
  AND (policyname LIKE '%cover%' OR policyname LIKE '%art%')
ORDER BY policyname;

-- ============================================
-- CREATE NEW POLICIES IN DASHBOARD
-- ============================================
-- 
-- Go to: Supabase Dashboard → Storage → cover-art → Policies → New Policy
-- 
-- Create these 4 NEW policies (use different names to avoid conflicts):
--
-- 1. Policy Name: "Upload cover art v2"
--    - Operation: INSERT
--    - Target roles: authenticated
--    - Policy definition: bucket_id = 'cover-art'
--
-- 2. Policy Name: "Update cover art v2"
--    - Operation: UPDATE
--    - Target roles: authenticated
--    - Policy definition: bucket_id = 'cover-art'
--
-- 3. Policy Name: "Delete cover art v2"
--    - Operation: DELETE
--    - Target roles: authenticated
--    - Policy definition: bucket_id = 'cover-art'
--
-- 4. Policy Name: "Read cover art v2"
--    - Operation: SELECT
--    - Target roles: anon, authenticated
--    - Policy definition: bucket_id = 'cover-art'
--
-- Note: The old policies will remain but won't interfere.
-- The new policies will be active and will work.
--
-- ============================================

