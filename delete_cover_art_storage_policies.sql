-- Delete existing storage policies for cover-art bucket
-- NOTE: If this fails with "must be owner" error, delete policies through Dashboard instead

-- Try to drop policies (may fail if you don't have owner permissions)
DO $$ 
BEGIN
    DROP POLICY IF EXISTS "Artists can upload cover art" ON storage.objects;
    DROP POLICY IF EXISTS "Artists can update cover art" ON storage.objects;
    DROP POLICY IF EXISTS "Artists can delete cover art" ON storage.objects;
    DROP POLICY IF EXISTS "Authenticated users can read cover art" ON storage.objects;
    DROP POLICY IF EXISTS "Anyone can read cover art" ON storage.objects;
    DROP POLICY IF EXISTS "Authenticated users can upload cover art" ON storage.objects;
    DROP POLICY IF EXISTS "Authenticated users can update cover art" ON storage.objects;
    DROP POLICY IF EXISTS "Authenticated users can delete cover art" ON storage.objects;
EXCEPTION WHEN OTHERS THEN 
    RAISE NOTICE 'Could not delete policies via SQL. Delete them through Dashboard instead.';
END $$;

-- Verify which policies still exist
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
-- ALTERNATIVE: Delete Policies Through Dashboard
-- ============================================
-- 
-- If the SQL above fails, delete policies manually:
-- 
-- 1. Go to Supabase Dashboard → Storage → cover-art bucket
-- 2. Click on the "Policies" tab
-- 3. For each policy listed, click the three dots (⋯) or delete icon
-- 4. Confirm deletion
-- 
-- Delete these policies:
-- - "Artists can upload cover art"
-- - "Artists can update cover art"
-- - "Artists can delete cover art"
-- - "Authenticated users can read cover art"
--
-- ============================================

