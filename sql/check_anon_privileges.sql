-- Check if anon role has SELECT permission on profiles table
SELECT 
    grantee,
    table_name,
    privilege_type
FROM information_schema.table_privileges
WHERE table_schema = 'public'
  AND table_name = 'profiles'
  AND grantee = 'anon';

-- If the above returns no rows, run this to grant the permission:
-- GRANT SELECT ON public.profiles TO anon;

