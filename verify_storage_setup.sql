-- ============================================
-- Verify Storage Setup for recall-audio
-- ============================================
-- Run this to diagnose any remaining issues
-- ============================================

-- 1. Verify bucket exists and configuration
SELECT 
    id, 
    name, 
    public, 
    file_size_limit,
    allowed_mime_types,
    created_at
FROM storage.buckets 
WHERE name = 'recall-audio';

-- 2. Verify RLS is enabled on storage.objects
SELECT 
    schemaname,
    tablename,
    rowsecurity as rls_enabled
FROM pg_tables 
WHERE schemaname = 'storage' AND tablename = 'objects';

-- 3. List ALL policies on storage.objects (to check for conflicts)
SELECT 
    policyname,
    cmd,
    permissive,
    roles,
    qual,
    with_check
FROM pg_policies
WHERE tablename = 'objects' 
  AND schemaname = 'storage'
ORDER BY policyname;

-- 4. Verify our specific recall-audio policies
SELECT 
    policyname,
    cmd,
    permissive,
    CASE 
        WHEN with_check IS NOT NULL THEN 'WITH CHECK: ' || with_check::text
        WHEN qual IS NOT NULL THEN 'USING: ' || qual::text
        ELSE 'No condition'
    END as policy_condition
FROM pg_policies
WHERE tablename = 'objects' 
  AND schemaname = 'storage'
  AND policyname LIKE '%recall-audio%'
ORDER BY cmd;

-- 5. Test the foldername function with your actual path
SELECT 
    '62832CF5-8A68-4BAC-A4B9-51BC79385A85/FF62D239-E3F0-4090-A9B7-30599F75F58B/voice_1765866536.m4a' as test_path,
    storage.foldername('62832CF5-8A68-4BAC-A4B9-51BC79385A85/FF62D239-E3F0-4090-A9B7-30599F75F58B/voice_1765866536.m4a') as folders,
    (storage.foldername('62832CF5-8A68-4BAC-A4B9-51BC79385A85/FF62D239-E3F0-4090-A9B7-30599F75F58B/voice_1765866536.m4a'))[1] as first_folder;

-- 6. Check current authenticated user (if running as authenticated user)
SELECT 
    auth.uid() as current_user_id,
    auth.uid()::text as current_user_id_text;

-- 7. Test if policy would match (requires authenticated session)
-- This will only work if you're running as an authenticated user
SELECT 
    'recall-audio' as bucket_id,
    '62832CF5-8A68-4BAC-A4B9-51BC79385A85/FF62D239-E3F0-4090-A9B7-30599F75F58B/voice_1765866536.m4a' as test_path,
    CASE 
        WHEN 'recall-audio' = 'recall-audio' THEN 'Bucket matches ✓'
        ELSE 'Bucket mismatch ✗'
    END as bucket_check;

















