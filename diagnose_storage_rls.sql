-- ============================================
-- Diagnose Storage RLS Issue
-- ============================================

-- 1. Check if RLS is enabled (CRITICAL)
SELECT 
    tablename, 
    rowsecurity as rls_enabled,
    CASE 
        WHEN rowsecurity THEN 'RLS is ENABLED ✓'
        ELSE 'RLS is DISABLED ✗ - This might be the problem!'
    END as status
FROM pg_tables 
WHERE schemaname = 'storage' AND tablename = 'objects';

-- 2. Check ALL INSERT policies with their WITH CHECK clauses
SELECT 
    policyname,
    cmd,
    permissive,
    roles::text as roles,
    CASE 
        WHEN with_check IS NOT NULL THEN with_check::text
        ELSE 'No WITH CHECK clause'
    END as with_check_clause
FROM pg_policies
WHERE tablename = 'objects' 
  AND schemaname = 'storage'
  AND cmd = 'INSERT'
ORDER BY policyname;

-- 3. Specifically check the recall-audio INSERT policy details
SELECT 
    policyname,
    cmd,
    permissive,
    roles::text as roles,
    with_check::text as with_check_clause,
    qual::text as using_clause
FROM pg_policies
WHERE tablename = 'objects' 
  AND schemaname = 'storage'
  AND policyname = 'Allow authenticated uploads to recall-audio';

-- 4. Check if there are any RESTRICTIVE policies (these would block)
SELECT 
    policyname,
    cmd,
    permissive,
    roles::text as roles,
    'RESTRICTIVE policies block access even if PERMISSIVE policies allow it' as warning
FROM pg_policies
WHERE tablename = 'objects' 
  AND schemaname = 'storage'
  AND permissive = 'RESTRICTIVE';

-- 5. Test bucket existence and configuration
SELECT 
    id,
    name,
    public,
    file_size_limit,
    allowed_mime_types,
    CASE 
        WHEN public THEN 'Bucket is PUBLIC'
        ELSE 'Bucket is PRIVATE (RLS required)'
    END as bucket_type
FROM storage.buckets 
WHERE name = 'recall-audio';

















