# Recall v2 Testing Guide

## Unit Tests

### ViewModel Tests
- **File**: `RockoutTests/RecallViewModelTests.swift`
- Tests state transitions (idle → listening → processing → done)
- Tests error handling
- Tests retry logic

### Service Tests
- **File**: `RockoutTests/RecallServiceTests.swift`
- Tests network resilience (retries, timeouts, backoff)
- Tests idempotency

## Integration Tests

### End-to-End Flow
1. Create recall with voice input
2. Upload audio to storage
3. Process recall via router
4. Receive candidates/answer
5. Display in UI

### Realtime Updates
1. Subscribe to recall updates
2. Verify incremental updates are received
3. Test offline handling

## RLS Tests

### User Isolation
```sql
-- Test that users can only access their own recalls
SELECT * FROM recalls WHERE user_id = 'user1-uuid';
-- Should only return user1's recalls
```

### Storage Access
- Verify signed URLs are user-specific
- Test that users cannot access other users' audio/images

## Performance Tests

### Large Audio Files
- Test with 10MB audio file (max 2 minutes)
- Verify upload completes within timeout
- Check processing completes successfully

### Concurrent Requests
- Test 10 simultaneous recall requests
- Verify all process correctly
- Check rate limiting is enforced

### Queue Processing
- Test queue processing under load
- Verify jobs are processed in order
- Check retry logic works correctly

## Manual QA Checklist

### Voice Input
- [ ] Record voice note
- [ ] Record background audio
- [ ] Hum a melody
- [ ] Verify transcription accuracy

### Text Input
- [ ] Type song search query
- [ ] Type music question
- [ ] Type mood request

### Image Input
- [ ] Upload photo
- [ ] Verify processing

### Results
- [ ] Song match cards display correctly
- [ ] Knowledge answers show sources
- [ ] Mood DJ recommendations appear
- [ ] Confidence scores are accurate

### Actions
- [ ] Share works
- [ ] Post to GreenRoom works
- [ ] Save/unsave works

### Feedback
- [ ] Thumbs up/down works
- [ ] Rating system works
- [ ] Corrections are submitted

### Error Handling
- [ ] Network errors are handled
- [ ] Timeouts are handled
- [ ] Rate limits are respected
- [ ] Error state shows in UI

### Realtime
- [ ] Updates appear incrementally
- [ ] Works when app is backgrounded
- [ ] Falls back to polling if realtime unavailable

















