-- ============================================
-- Verify Username Availability Check Permissions
-- Run this to check if anonymous users can read profiles
-- ============================================

-- Check if anon role has SELECT permission on profiles table
SELECT 
    grantee,
    table_name,
    privilege_type
FROM information_schema.table_privileges
WHERE table_schema = 'public'
  AND table_name = 'profiles'
  AND grantee = 'anon';

-- Check RLS policies on profiles table
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'profiles';

-- Test query as anonymous user (simulate)
-- Note: This will only work if permissions are correctly set
DO $$
BEGIN
    RAISE NOTICE 'If you see this message, the script ran successfully.';
    RAISE NOTICE 'Check the results above - anon should have SELECT privilege.';
    RAISE NOTICE 'The RLS policy should allow SELECT with USING (true).';
END $$;

