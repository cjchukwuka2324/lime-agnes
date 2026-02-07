# Load Testing Guide

This guide explains how to test RockOut's ability to handle 10,000 concurrent users.

## Prerequisites

- Load testing tool (e.g., k6, Apache JMeter, Locust)
- Access to Supabase project
- Test user accounts

## Test Scenarios

### 1. Feed Loading (High Priority)

**Endpoint**: `get_feed_posts_paginated` RPC

**Test Cases**:
- 10k concurrent users loading "For You" feed
- 10k concurrent users loading "Following" feed
- Mixed feed types (50/50 split)

**Expected Behavior**:
- Request coalescing should reduce actual requests to ~1-10
- Response time <500ms (p95)
- No errors

**Metrics to Track**:
- Request count (should be << 10k due to coalescing)
- Response time (p50, p95, p99)
- Error rate (should be <0.1%)

### 2. Profile Loading (Medium Priority)

**Endpoint**: `profiles` table queries

**Test Cases**:
- 10k concurrent users viewing different profiles
- 10k concurrent users viewing same profile (test cache)

**Expected Behavior**:
- First request: ~200ms
- Cached requests: <10ms
- Cache hit rate >80% after warmup

**Metrics to Track**:
- Cache hit rate
- Response time (p50, p95)
- Database query count

### 3. Image Loading (Low Priority)

**Endpoint**: Image URLs from storage

**Test Cases**:
- 10k concurrent users loading profile pictures
- 10k concurrent users loading post images

**Expected Behavior**:
- Memory usage stays <100MB for ImageCache
- LRU eviction working correctly
- No OOM crashes

**Metrics to Track**:
- ImageCache size (should be <100MB)
- Cache eviction rate
- Memory usage

### 4. Pagination (Critical)

**Endpoints**: All list endpoints

**Test Cases**:
- Load first page (20 items)
- Load subsequent pages
- Load all pages sequentially

**Expected Behavior**:
- Each page loads <500ms
- No unbounded queries
- Cursor pagination working correctly

**Metrics to Track**:
- Response size per page
- Query execution time
- Total items loaded

## Load Testing Scripts

### k6 Example

```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '30s', target: 1000 },
    { duration: '1m', target: 5000 },
    { duration: '2m', target: 10000 },
    { duration: '1m', target: 0 },
  ],
};

export default function () {
  const url = 'https://your-project.supabase.co/rest/v1/rpc/get_feed_posts_paginated';
  const headers = {
    'apikey': 'your-anon-key',
    'Authorization': 'Bearer your-token',
    'Content-Type': 'application/json',
  };
  const payload = JSON.stringify({
    p_feed_type: 'for_you',
    p_region: null,
    p_limit: 20,
    p_cursor: null,
  });

  const res = http.post(url, payload, { headers });
  
  check(res, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
  });

  sleep(1);
}
```

## Monitoring During Tests

### Supabase Dashboard
- Monitor database CPU/memory
- Check query performance
- Watch for connection pool exhaustion

### Application Logs
- Request coalescing logs
- Cache hit/miss rates
- Performance metrics

### System Metrics
- Memory usage (should stay bounded)
- CPU usage
- Network bandwidth

## Success Criteria

1. **Request Coalescing**: Actual requests << concurrent users
2. **Response Times**: p95 < 500ms for feed loads
3. **Error Rate**: <0.1%
4. **Memory**: ImageCache <100MB, no OOM crashes
5. **Cache Hit Rate**: Profile cache >80% after warmup

## Troubleshooting

### High Error Rate
- Check Supabase connection limits
- Verify RLS policies aren't blocking requests
- Check retry policy is working

### Slow Response Times
- Review slow queries in Supabase dashboard
- Check if pagination is working
- Verify indexes exist on queried columns

### Memory Issues
- Verify ImageCache LRU eviction
- Check for memory leaks in ViewModels
- Monitor ProfileCache size

## Reporting

After load testing, document:
1. Peak concurrent users achieved
2. Actual request count (vs expected without coalescing)
3. Response time percentiles
4. Error rate
5. Cache hit rates
6. Memory usage
7. Any bottlenecks identified








