-- ============================================
-- Fix Storage Policies - Remove Conflicting Policies
-- ============================================
-- This script removes any potentially conflicting policies
-- and ensures only our recall-audio policies are active
-- ============================================

-- First, let's see what policies exist
SELECT 
    policyname,
    cmd,
    permissive,
    roles::text as roles,
    CASE 
        WHEN with_check IS NOT NULL THEN 'WITH CHECK: ' || with_check::text
        WHEN qual IS NOT NULL THEN 'USING: ' || qual::text
        ELSE 'No condition'
    END as policy_condition
FROM pg_policies
WHERE tablename = 'objects' 
  AND schemaname = 'storage'
ORDER BY policyname;

-- If there are RESTRICTIVE policies that might be blocking, we need to handle them
-- Supabase Storage uses PERMISSIVE policies by default, but RESTRICTIVE ones can block

-- Check if there are any RESTRICTIVE policies that might conflict
SELECT 
    policyname,
    cmd,
    permissive,
    'This is a RESTRICTIVE policy that might be blocking access' as warning
FROM pg_policies
WHERE tablename = 'objects' 
  AND schemaname = 'storage'
  AND permissive = 'RESTRICTIVE'
ORDER BY policyname;

-- If the above shows RESTRICTIVE policies, you may need to:
-- 1. Drop them if they're not needed
-- 2. Or modify them to allow recall-audio bucket

-- ============================================
-- Alternative: Create a more permissive policy
-- ============================================
-- If the simple policies aren't working, try this even simpler version:

-- Drop and recreate with explicit permissions
DROP POLICY IF EXISTS "Allow authenticated uploads to recall-audio" ON storage.objects;
DROP POLICY IF EXISTS "Allow authenticated reads from recall-audio" ON storage.objects;
DROP POLICY IF EXISTS "Allow authenticated deletes from recall-audio" ON storage.objects;

-- Recreate with explicit TO authenticated
CREATE POLICY "Allow authenticated uploads to recall-audio" ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'recall-audio'
  );

CREATE POLICY "Allow authenticated reads from recall-audio" ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'recall-audio'
  );

CREATE POLICY "Allow authenticated deletes from recall-audio" ON storage.objects
  FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'recall-audio'
  );

-- Verify they were recreated
SELECT 
    policyname,
    cmd,
    permissive,
    roles::text as roles
FROM pg_policies
WHERE tablename = 'objects' 
  AND schemaname = 'storage'
  AND policyname LIKE '%recall-audio%'
ORDER BY cmd;







