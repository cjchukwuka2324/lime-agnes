-- Fix Recall image upload: storage RLS for recall-images bucket
-- Fixes "new row violates row-level security policy" when adding a photo in Recall.
-- 1) Use auth.jwt()->>'sub' for path check (matches Supabase docs; reliable in storage context).
-- 2) Add UPDATE policy so upsert (overwrite) is allowed.

-- Drop all existing recall-images policies (avoid duplicates from recall.sql vs setup_storage_buckets.sql)
DROP POLICY IF EXISTS "Users can upload their own images" ON storage.objects;
DROP POLICY IF EXISTS "Users can upload images to their own folder" ON storage.objects;
DROP POLICY IF EXISTS "Users can read their own images" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete their own images" ON storage.objects;
DROP POLICY IF EXISTS "recall-images: authenticated insert" ON storage.objects;
DROP POLICY IF EXISTS "recall-images: authenticated select" ON storage.objects;
DROP POLICY IF EXISTS "recall-images: authenticated update" ON storage.objects;

-- INSERT: first path segment must be the authenticated user's id (JWT sub); case-insensitive (Swift UUID.uuidString is uppercase)
CREATE POLICY "recall-images: authenticated insert"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'recall-images'
  AND lower((storage.foldername(name))[1]) = lower(auth.jwt() ->> 'sub')
);

-- SELECT: same path rule
CREATE POLICY "recall-images: authenticated select"
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'recall-images'
  AND lower((storage.foldername(name))[1]) = lower(auth.jwt() ->> 'sub')
);

-- UPDATE: required for upsert (overwrite); same path rule
CREATE POLICY "recall-images: authenticated update"
ON storage.objects
FOR UPDATE
TO authenticated
USING (
  bucket_id = 'recall-images'
  AND lower((storage.foldername(name))[1]) = lower(auth.jwt() ->> 'sub')
)
WITH CHECK (
  bucket_id = 'recall-images'
  AND lower((storage.foldername(name))[1]) = lower(auth.jwt() ->> 'sub')
);

-- DELETE: keep users able to delete their own images
DROP POLICY IF EXISTS "recall-images: authenticated delete" ON storage.objects;
CREATE POLICY "recall-images: authenticated delete"
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'recall-images'
  AND lower((storage.foldername(name))[1]) = lower(auth.jwt() ->> 'sub')
);
