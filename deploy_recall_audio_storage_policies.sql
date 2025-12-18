-- ============================================
-- Deploy Storage Policies for recall-audio bucket
-- ============================================
-- Copy and paste this entire file into Supabase SQL Editor and run it
-- ============================================

-- Step 1: Verify bucket exists (should return 1 row)
SELECT id, name, public, created_at
FROM storage.buckets 
WHERE name = 'recall-audio';

-- If the above returns 0 rows, create the bucket first:
-- INSERT INTO storage.buckets (id, name, public)
-- VALUES ('recall-audio', 'recall-audio', false)
-- ON CONFLICT (id) DO NOTHING;

-- Step 2: Drop existing policies (if any)
DROP POLICY IF EXISTS "Users can upload their own audio" ON storage.objects;
DROP POLICY IF EXISTS "Users can read their own audio" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete their own audio" ON storage.objects;
DROP POLICY IF EXISTS "Allow authenticated uploads to recall-audio" ON storage.objects;
DROP POLICY IF EXISTS "Allow authenticated reads from recall-audio" ON storage.objects;
DROP POLICY IF EXISTS "Allow authenticated deletes from recall-audio" ON storage.objects;

-- Step 3: Create simple policies (allows all authenticated users)
-- Use this for quick testing:
CREATE POLICY "Allow authenticated uploads to recall-audio" ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (bucket_id = 'recall-audio');

CREATE POLICY "Allow authenticated reads from recall-audio" ON storage.objects
  FOR SELECT
  TO authenticated
  USING (bucket_id = 'recall-audio');

CREATE POLICY "Allow authenticated deletes from recall-audio" ON storage.objects
  FOR DELETE
  TO authenticated
  USING (bucket_id = 'recall-audio');

-- Step 4: Verify policies were created (should return 3 rows)
SELECT policyname, cmd, permissive
FROM pg_policies
WHERE tablename = 'objects' 
  AND schemaname = 'storage'
  AND policyname LIKE '%recall-audio%'
ORDER BY policyname;

-- ============================================
-- OPTIONAL: Secure policies (restrict to user's own folder)
-- ============================================
-- If you want to restrict users to only their own folders, 
-- drop the simple policies above and use these instead:

/*
DROP POLICY IF EXISTS "Allow authenticated uploads to recall-audio" ON storage.objects;
DROP POLICY IF EXISTS "Allow authenticated reads from recall-audio" ON storage.objects;
DROP POLICY IF EXISTS "Allow authenticated deletes from recall-audio" ON storage.objects;

CREATE POLICY "Users can upload their own audio" ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'recall-audio' AND
    (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Users can read their own audio" ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'recall-audio' AND
    (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Users can delete their own audio" ON storage.objects
  FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'recall-audio' AND
    (storage.foldername(name))[1] = auth.uid()::text
  );
*/




