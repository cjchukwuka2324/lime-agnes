-- ============================================
-- Recall v2 Deployment Verification Script
-- ============================================
-- Run this after deploying to verify everything is set up correctly
-- ============================================

-- 1. Check all tables exist
SELECT 
    'Tables Check' as check_type,
    COUNT(*) as count,
    CASE 
        WHEN COUNT(*) >= 9 THEN '✅ PASS'
        ELSE '❌ FAIL - Missing tables'
    END as status
FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_name IN (
    'recalls',
    'recall_sources',
    'recall_candidates',
    'saved_recalls',
    'recall_jobs',
    'recall_feedback',
    'recall_user_preferences',
    'recall_learning_data',
    'recall_logs'
);

-- 2. Check RLS is enabled on all tables
SELECT 
    'RLS Check' as check_type,
    tablename,
    rowsecurity as rls_enabled,
    CASE 
        WHEN rowsecurity THEN '✅ ENABLED'
        ELSE '❌ DISABLED'
    END as status
FROM pg_tables 
WHERE schemaname = 'public' 
AND tablename LIKE 'recall%'
ORDER BY tablename;

-- 3. Check RLS policies exist
SELECT 
    'RLS Policies' as check_type,
    tablename,
    COUNT(*) as policy_count,
    CASE 
        WHEN COUNT(*) > 0 THEN '✅ HAS POLICIES'
        ELSE '❌ NO POLICIES'
    END as status
FROM pg_policies 
WHERE schemaname = 'public' 
AND tablename LIKE 'recall%'
GROUP BY tablename
ORDER BY tablename;

-- 4. Check indexes exist
SELECT 
    'Indexes Check' as check_type,
    COUNT(*) as index_count,
    CASE 
        WHEN COUNT(*) >= 20 THEN '✅ PASS'
        ELSE '⚠️  Some indexes may be missing'
    END as status
FROM pg_indexes 
WHERE schemaname = 'public' 
AND indexname LIKE 'idx_recall%';

-- 5. Check storage buckets exist
SELECT 
    'Storage Buckets' as check_type,
    name,
    public,
    CASE 
        WHEN name IN ('recall-audio', 'recall-images', 'recall-background') THEN '✅ EXISTS'
        ELSE '❌ MISSING'
    END as status
FROM storage.buckets 
WHERE name LIKE 'recall%'
ORDER BY name;

-- 6. Check storage policies exist
SELECT 
    'Storage Policies' as check_type,
    bucket_id,
    COUNT(*) as policy_count,
    CASE 
        WHEN COUNT(*) > 0 THEN '✅ HAS POLICIES'
        ELSE '❌ NO POLICIES'
    END as status
FROM storage.policies 
WHERE bucket_id LIKE 'recall%'
GROUP BY bucket_id
ORDER BY bucket_id;

-- 7. Check functions exist
SELECT 
    'Functions Check' as check_type,
    routine_name,
    routine_type,
    CASE 
        WHEN routine_name LIKE 'update_updated_at%' OR routine_name LIKE 'generate_request_id%' OR routine_name LIKE 'is_recall_processing%' THEN '✅ EXISTS'
        ELSE '⚠️  Unknown function'
    END as status
FROM information_schema.routines 
WHERE routine_schema = 'public' 
AND routine_name LIKE '%recall%' OR routine_name LIKE 'update_updated_at%' OR routine_name LIKE 'generate_request_id%'
ORDER BY routine_name;

-- 8. Check triggers exist
SELECT 
    'Triggers Check' as check_type,
    trigger_name,
    event_object_table,
    CASE 
        WHEN trigger_name LIKE 'update_%_updated_at' THEN '✅ EXISTS'
        ELSE '⚠️  Unknown trigger'
    END as status
FROM information_schema.triggers 
WHERE trigger_schema = 'public' 
AND trigger_name LIKE '%recall%' OR trigger_name LIKE 'update_%_updated_at'
ORDER BY event_object_table, trigger_name;

-- 9. Summary Report
SELECT 
    '=== DEPLOYMENT VERIFICATION SUMMARY ===' as summary;

SELECT 
    'Total Tables' as metric,
    COUNT(*)::text as value
FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_name LIKE 'recall%';

SELECT 
    'Tables with RLS Enabled' as metric,
    COUNT(*)::text as value
FROM pg_tables 
WHERE schemaname = 'public' 
AND tablename LIKE 'recall%'
AND rowsecurity = true;

SELECT 
    'Total RLS Policies' as metric,
    COUNT(*)::text as value
FROM pg_policies 
WHERE schemaname = 'public' 
AND tablename LIKE 'recall%';

SELECT 
    'Storage Buckets' as metric,
    COUNT(*)::text as value
FROM storage.buckets 
WHERE name LIKE 'recall%';

SELECT 
    'Storage Policies' as metric,
    COUNT(*)::text as value
FROM storage.policies 
WHERE bucket_id LIKE 'recall%';

-- 10. Test RLS (run as authenticated user)
-- This will only work if you're logged in
DO $$
BEGIN
    IF auth.uid() IS NOT NULL THEN
        RAISE NOTICE '✅ User is authenticated: %', auth.uid();
    ELSE
        RAISE NOTICE '⚠️  Not authenticated - RLS tests skipped';
    END IF;
END $$;




