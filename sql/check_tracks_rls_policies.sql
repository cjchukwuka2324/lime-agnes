-- ============================================
-- Diagnostic: Check Tracks RLS Policies
-- Run this to see what RLS policies exist on the tracks table
-- ============================================

-- Check if RLS is enabled
SELECT 
    schemaname,
    tablename,
    rowsecurity as rls_enabled
FROM pg_tables
WHERE schemaname = 'public' 
  AND tablename = 'tracks';

-- List all RLS policies on tracks table
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
  AND tablename = 'tracks'
ORDER BY policyname;

-- Check if the helper function exists
SELECT 
    routine_name,
    routine_type,
    security_type
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name = 'is_album_public';

-- Test query: Try to see tracks for a public album
-- Replace 'YOUR_ALBUM_ID' with an actual public album ID
-- SELECT 
--     t.id,
--     t.title,
--     t.album_id,
--     a.is_public,
--     a.title as album_title
-- FROM tracks t
-- LEFT JOIN albums a ON a.id = t.album_id
-- WHERE a.is_public = true
-- LIMIT 5;

