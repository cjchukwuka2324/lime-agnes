-- Debug script to check album ownership and RLS policies
-- Run this to verify the current user can update their albums

-- Check current user
SELECT auth.uid() as current_user_id;

-- Check if you own any albums
SELECT 
    id,
    title,
    CAST(artist_id AS text) as artist_id_text,
    CAST(auth.uid() AS text) as current_user_text,
    (CAST(artist_id AS text) = CAST(auth.uid() AS text)) as is_owner
FROM albums
LIMIT 5;

-- Test the RLS policy directly
-- This should return rows if the policy is working
SELECT 
    id,
    title,
    cover_art_url
FROM albums
WHERE CAST(artist_id AS text) = CAST(auth.uid() AS text)
LIMIT 5;

-- Check all RLS policies on albums table
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
WHERE tablename = 'albums';

