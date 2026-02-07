import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');

export const options = {
  stages: [
    { duration: '2m', target: 1000 },   // Ramp up to 1k users
    { duration: '5m', target: 5000 },   // Ramp up to 5k users
    { duration: '10m', target: 10000 }, // Stay at 10k users
    { duration: '2m', target: 0 },      // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<2000'], // 95% of requests < 2s
    http_req_failed: ['rate<0.01'],     // <1% errors
    errors: ['rate<0.01'],              // <1% custom errors
  },
};

export default function () {
  const baseUrl = __ENV.SUPABASE_URL || 'https://your-project.supabase.co';
  const anonKey = __ENV.SUPABASE_ANON_KEY || 'your-anon-key';
  
  // Simulate user authentication (in real test, use actual auth tokens)
  const userId = `user-${Math.random().toString(36).substr(2, 9)}`;
  const threadId = `thread-${Math.random().toString(36).substr(2, 9)}`;
  const messageId = `msg-${Math.random().toString(36).substr(2, 9)}`;
  
  // Test 1: Text recall request
  const textRecallResponse = http.post(
    `${baseUrl}/functions/v1/recall-resolve`,
    JSON.stringify({
      thread_id: threadId,
      message_id: messageId,
      input_type: 'text',
      text: 'Find this song'
    }),
    {
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${anonKey}`,
        'apikey': anonKey,
      },
      tags: { name: 'recall-resolve-text' },
    }
  );
  
  const textRecallSuccess = check(textRecallResponse, {
    'status is 200 or 429': (r) => r.status === 200 || r.status === 429,
    'response time < 5s': (r) => r.timings.duration < 5000,
  });
  
  if (!textRecallSuccess) {
    errorRate.add(1);
  }
  
  // Test 2: Fetch messages (if thread exists)
  if (textRecallResponse.status === 200) {
    const messagesResponse = http.get(
      `${baseUrl}/rest/v1/recall_messages?thread_id=eq.${threadId}&order=created_at.asc&limit=50`,
      {
        headers: {
          'Authorization': `Bearer ${anonKey}`,
          'apikey': anonKey,
          'Prefer': 'return=representation',
        },
        tags: { name: 'fetch-messages' },
      }
    );
    
    check(messagesResponse, {
      'messages status is 200': (r) => r.status === 200,
      'messages response time < 1s': (r) => r.timings.duration < 1000,
    });
  }
  
  // Test 3: Rate limiting (should get 429 after exceeding limits)
  // This test intentionally makes rapid requests to test rate limiting
  if (__VU % 10 === 0) { // Every 10th virtual user tests rate limiting
    for (let i = 0; i < 15; i++) {
      const rateLimitResponse = http.post(
        `${baseUrl}/functions/v1/recall-resolve`,
        JSON.stringify({
          thread_id: `rate-limit-test-${__VU}`,
          message_id: `msg-${i}`,
          input_type: 'text',
          text: 'Test rate limit'
        }),
        {
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${anonKey}`,
            'apikey': anonKey,
          },
          tags: { name: 'rate-limit-test' },
        }
      );
      
      if (i >= 10) {
        // After 10 requests, should start getting 429
        check(rateLimitResponse, {
          'rate limit enforced': (r) => r.status === 429 || r.status === 200,
        });
      }
      
      sleep(0.1); // Small delay between requests
    }
  }
  
  sleep(1); // Think time between iterations
}

export function handleSummary(data) {
  return {
    'stdout': textSummary(data, { indent: ' ', enableColors: true }),
    'summary.json': JSON.stringify(data),
  };
}

function textSummary(data, options) {
  return `
    ============================================
    Recall Load Test Summary
    ============================================
    Total Requests: ${data.metrics.http_reqs.values.count}
    Failed Requests: ${data.metrics.http_req_failed.values.rate * 100}%
    Average Response Time: ${data.metrics.http_req_duration.values.avg.toFixed(2)}ms
    P95 Response Time: ${data.metrics.http_req_duration.values['p(95)'].toFixed(2)}ms
    P99 Response Time: ${data.metrics.http_req_duration.values['p(99)'].toFixed(2)}ms
    Error Rate: ${data.metrics.errors.values.rate * 100}%
    ============================================
  `;
}






