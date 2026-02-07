# Recall Production-Scale Deployment Checklist

## Pre-Deployment

### 1. Database Migrations
- [ ] Run `supabase/migrations/optimize_recall_for_scale.sql`
  ```sql
  -- Execute in Supabase SQL Editor
  -- This creates indexes and optimized functions
  ```
- [ ] Verify indexes are created:
  ```sql
  SELECT indexname FROM pg_indexes 
  WHERE tablename LIKE 'recall_%' 
  AND indexname LIKE 'idx_%';
  ```
- [ ] Test pagination function:
  ```sql
  SELECT * FROM get_recall_messages_paginated(
    'your-thread-id'::UUID,
    NULL,
    50
  );
  ```

### 2. Edge Function Deployment
- [ ] Deploy updated `recall-resolve` function:
  ```bash
  supabase functions deploy recall-resolve
  ```
- [ ] Verify environment variables are set:
  - `OPENAI_API_KEY`
  - `ACRCLOUD_ACCESS_KEY` (optional)
  - `ACRCLOUD_ACCESS_SECRET` (optional)
  - `SHAZAM_API_KEY` (optional)
- [ ] Test rate limiting:
  - Make 11 requests in 1 minute → Should get 429 on 11th
- [ ] Test circuit breakers:
  - Simulate API failures → Circuit should open after 5 failures

### 3. Client Code Updates
- [ ] Add new files to Xcode project:
  - `RecallCache.swift`
  - `RecallMetrics.swift`
- [ ] Verify `RecallService.swift` imports:
  - `RequestCoalescer`
  - `RecallCache`
  - `RecallMetrics`
- [ ] Build and test:
  - Verify no compilation errors
  - Test message loading with cache
  - Test debouncing (rapid calls should be debounced)

### 4. Load Testing
- [ ] Install k6:
  ```bash
  brew install k6  # macOS
  # or
  # Download from https://k6.io/docs/getting-started/installation/
  ```
- [ ] Set environment variables:
  ```bash
  export SUPABASE_URL="https://your-project.supabase.co"
  export SUPABASE_ANON_KEY="your-anon-key"
  ```
- [ ] Run load test:
  ```bash
  k6 run loadtest/k6-recall-test.js
  ```
- [ ] Verify thresholds:
  - 95% of requests < 2s ✅
  - <1% error rate ✅

## Post-Deployment Monitoring

### 1. Performance Metrics
- [ ] Monitor `RecallMetrics.shared.getAllStats()`
- [ ] Check cache hit rates:
  ```swift
  let stats = await RecallCache.shared.getStats()
  // Should see threadCount and messageCount > 0
  ```
- [ ] Monitor request coalescing:
  - Check logs for `♻️ [Coalescer] Reusing inflight request`

### 2. Error Monitoring
- [ ] Set up alerts for:
  - Error rate > 1%
  - P95 response time > 2s
  - Rate limit 429 responses > 5%
- [ ] Monitor circuit breaker state:
  - Check logs for circuit breaker open events

### 3. Database Performance
- [ ] Monitor query performance:
  ```sql
  SELECT * FROM pg_stat_statements 
  WHERE query LIKE '%recall_%' 
  ORDER BY mean_exec_time DESC;
  ```
- [ ] Check index usage:
  ```sql
  SELECT * FROM pg_stat_user_indexes 
  WHERE indexrelname LIKE 'idx_recall_%';
  ```

## Rollback Plan

If issues occur:
1. **Database**: Indexes can be dropped without data loss
2. **Edge Function**: Revert to previous version
3. **Client**: Cache and coalescing are non-breaking (can be disabled)

## Success Criteria

✅ **10k concurrent users** can use Recall simultaneously
✅ **<2s response time** for 95% of requests
✅ **<1% error rate** under load
✅ **70%+ cache hit rate** for threads
✅ **Rate limiting** prevents abuse
✅ **Circuit breakers** prevent cascading failures

## Next Steps

1. Monitor for 24-48 hours
2. Adjust rate limits if needed
3. Optimize cache TTLs based on usage patterns
4. Consider Redis for distributed rate limiting
5. Add CDN for static assets






