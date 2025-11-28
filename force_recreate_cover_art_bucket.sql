-- Force delete cover-art bucket and all its policies
-- This script attempts to delete policies first, then the bucket

-- Step 1: Try to delete all policies for cover-art bucket
-- Note: This may fail if you don't have owner permissions, but we'll try
DO $$ 
BEGIN
    -- Try to drop all policies that reference cover-art bucket
    DROP POLICY IF EXISTS "Artists can upload cover art" ON storage.objects;
    DROP POLICY IF EXISTS "Artists can update cover art" ON storage.objects;
    DROP POLICY IF EXISTS "Artists can delete cover art" ON storage.objects;
    DROP POLICY IF EXISTS "Authenticated users can read cover art" ON storage.objects;
    DROP POLICY IF EXISTS "Authenticated users can upload cover art" ON storage.objects;
    DROP POLICY IF EXISTS "Authenticated users can update cover art" ON storage.objects;
    DROP POLICY IF EXISTS "Authenticated users can delete cover art" ON storage.objects;
    DROP POLICY IF EXISTS "Anyone can read cover art" ON storage.objects;
EXCEPTION WHEN OTHERS THEN 
    RAISE NOTICE 'Could not delete policies via SQL (this is expected). Policies will need to be deleted manually or will be orphaned.';
END $$;

-- Step 2: Delete all files in the bucket first (if any exist)
-- This is required before deleting the bucket
DELETE FROM storage.objects 
WHERE bucket_id = 'cover-art';

-- Step 3: Delete the bucket
DELETE FROM storage.buckets 
WHERE id = 'cover-art';

-- Step 4: Recreate the bucket
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'cover-art', 
    'cover-art', 
    true,
    10485760, -- 10MB limit
    ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/jpg']
);

-- Step 5: Verify bucket was created and check for any remaining policies
SELECT 
    'Bucket Status' as info,
    id, 
    name, 
    public
FROM storage.buckets
WHERE id = 'cover-art';

-- Check for any remaining policies (they should be gone if bucket was deleted)
SELECT 
    'Remaining Policies' as info,
    policyname,
    cmd,
    roles
FROM pg_policies
WHERE tablename = 'objects' 
  AND schemaname = 'storage'
  AND (policyname LIKE '%cover%' OR policyname LIKE '%art%')
ORDER BY policyname;

-- ============================================
-- IMPORTANT: If policies still exist
-- ============================================
-- 
-- If the query above shows policies still exist, you have two options:
--
-- Option 1: Contact Supabase support to delete orphaned policies
--
-- Option 2: Create new policies with DIFFERENT names in Dashboard:
--   - Use names like "Upload cover art v2" instead of "Artists can upload cover art"
--   - The new policies will work even if old ones exist (they just won't be used)
--
-- Then create these 4 NEW policies in Dashboard:
--
-- 1. "Upload cover art v2" - INSERT - authenticated - bucket_id = 'cover-art'
-- 2. "Update cover art v2" - UPDATE - authenticated - bucket_id = 'cover-art'
-- 3. "Delete cover art v2" - DELETE - authenticated - bucket_id = 'cover-art'
-- 4. "Read cover art v2" - SELECT - anon, authenticated - bucket_id = 'cover-art'
--
-- ============================================

