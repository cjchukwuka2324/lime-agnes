# Recall v2 Supabase Deployment Guide

This guide covers all Supabase changes needed for Recall v2.

## Prerequisites

1. Supabase CLI installed: `brew install supabase/tap/supabase`
2. Logged into Supabase: `supabase login`
3. Project linked: `supabase link --project-ref wklzogrfdrqluwchoqsp`

## Step 1: Deploy Database Schema

### Option A: Via Supabase Dashboard (Recommended)

1. Open Supabase Dashboard → SQL Editor
2. Copy entire contents of `supabase/recall_v2_schema.sql`
3. Paste and execute
4. Verify tables created:
   ```sql
   SELECT table_name FROM information_schema.tables 
   WHERE table_schema = 'public' 
   AND table_name LIKE 'recall%';
   ```

Expected tables:
- `recalls`
- `recall_sources`
- `recall_candidates`
- `saved_recalls`
- `recall_jobs`
- `recall_feedback`
- `recall_user_preferences`
- `recall_learning_data`
- `recall_logs`

### Option B: Via Supabase CLI

```bash
cd /Users/chukwudiebube/Downloads/RockOut-main
supabase db push
# Or manually:
psql YOUR_DATABASE_URL < supabase/recall_v2_schema.sql
```

## Step 2: Create/Verify Storage Buckets

### Check Existing Buckets

```sql
SELECT name, public FROM storage.buckets WHERE name LIKE 'recall%';
```

### Create Missing Buckets

Run in Supabase Dashboard → SQL Editor:

```sql
-- Create recall-audio bucket (if not exists)
INSERT INTO storage.buckets (id, name, public)
VALUES ('recall-audio', 'recall-audio', false)
ON CONFLICT (id) DO NOTHING;

-- Create recall-images bucket (if not exists)
INSERT INTO storage.buckets (id, name, public)
VALUES ('recall-images', 'recall-images', false)
ON CONFLICT (id) DO NOTHING;

-- Create recall-background bucket (if not exists)
INSERT INTO storage.buckets (id, name, public)
VALUES ('recall-background', 'recall-background', false)
ON CONFLICT (id) DO NOTHING;
```

### Apply Storage RLS Policies

The storage policies are already in `recall_v2_schema.sql`, but verify they exist:

```sql
-- Check storage policies
SELECT * FROM pg_policies WHERE tablename LIKE 'objects' AND schemaname = 'storage';
```

If missing, the policies are defined in the schema file under RLS sections.

## Step 3: Set Environment Variables/Secrets

### Required Secrets

```bash
# OpenAI API Key (for GPT-4o, Whisper, intent detection)
supabase secrets set OPENAI_API_KEY="your-openai-api-key"

# ACRCloud (for audio identification)
supabase secrets set ACRCLOUD_ACCESS_KEY="your-acrcloud-access-key"
supabase secrets set ACRCLOUD_ACCESS_SECRET="your-acrcloud-access-secret"
supabase secrets set ACRCLOUD_HOST="identify-us-west-2.acrcloud.com"

# Shazam API (via RapidAPI)
supabase secrets set SHAZAM_API_KEY="your-rapidapi-key"

# Verify secrets
supabase secrets list
```

### Optional Secrets

```bash
# If using external Redis for caching
supabase secrets set REDIS_URL="redis://..."

# If using external queue service
supabase secrets set QUEUE_URL="..."
```

## Step 4: Deploy Edge Functions

Deploy all Recall v2 edge functions:

```bash
cd /Users/chukwudiebube/Downloads/RockOut-main

# Core functions
supabase functions deploy recall-v2-router
supabase functions deploy recall-v2-identify
supabase functions deploy recall-v2-knowledge
supabase functions deploy recall-v2-recommend
supabase functions deploy recall-v2-worker

# Training system functions
supabase functions deploy recall-v2-learning
supabase functions deploy recall-v2-learning-processor
```

### Verify Deployments

```bash
supabase functions list
```

Expected output should include all 7 functions above.

## Step 5: Set Up Cron Jobs (Optional)

For the learning processor to run automatically:

1. Go to Supabase Dashboard → Database → Cron Jobs
2. Create new cron job:
   - **Name**: `recall_learning_processor`
   - **Schedule**: `0 2 * * *` (daily at 2 AM)
   - **SQL**: 
   ```sql
   SELECT net.http_post(
     url := 'https://wklzogrfdrqluwchoqsp.supabase.co/functions/v1/recall-v2-learning-processor',
     headers := jsonb_build_object(
       'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndrbHpvZ3JmZHJxbHV3Y2hvcXNwIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2MzEyMDM0NywiZXhwIjoyMDc4Njk2MzQ3fQ.Z0JuCvDrRnlHt_IKYi-fOhvV4_Tb8EYVW0eyAIN6WUc',
       'Content-Type', 'application/json'
     ),
     body := '{}'::jsonb
   );
   ```
   
   **Note:** Service role key is configured above and in `setup_cron_jobs.sql`

Or use pg_cron extension:

```sql
-- Enable pg_cron if not already enabled
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Schedule learning processor (daily at 2 AM)
-- Service role key is configured in setup_cron_jobs.sql
SELECT cron.schedule(
  'recall-learning-processor',
  '0 2 * * *',
  $$
  SELECT net.http_post(
    url := 'https://wklzogrfdrqluwchoqsp.supabase.co/functions/v1/recall-v2-learning-processor',
    headers := jsonb_build_object(
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndrbHpvZ3JmZHJxbHV3Y2hvcXNwIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2MzEyMDM0NywiZXhwIjoyMDc4Njk2MzQ3fQ.Z0JuCvDrRnlHt_IKYi-fOhvV4_Tb8EYVW0eyAIN6WUc',
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb
  );
  $$
);
```

## Step 6: Set Up Worker Cron (Required)

The worker needs to run periodically to process queued jobs. **Choose one method:**

### Method A: Using pg_cron Extension (Recommended if available)

**First, enable pg_cron:**
1. Go to Supabase Dashboard → Database → Extensions
2. Search for "pg_cron"
3. Click "Enable"

Then run:

```sql
-- Schedule worker to run every minute
-- Service role key is configured in setup_cron_jobs.sql
SELECT cron.schedule(
  'recall-v2-worker',
  '* * * * *', -- Every minute
  $$
  SELECT net.http_post(
    url := 'https://wklzogrfdrqluwchoqsp.supabase.co/functions/v1/recall-v2-worker',
    headers := jsonb_build_object(
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndrbHpvZ3JmZHJxbHV3Y2hvcXNwIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2MzEyMDM0NywiZXhwIjoyMDc4Njk2MzQ3fQ.Z0JuCvDrRnlHt_IKYi-fOhvV4_Tb8EYVW0eyAIN6WUc',
      'Content-Type', 'application/json'
    ),
    body := '{"max_jobs": 10}'::jsonb
  );
  $$
);
```

### Method B: Using External Cron Service (If pg_cron not available)

If `pg_cron` is not available on your plan, use an external cron service:

**Option 1: GitHub Actions (Free)**
Create `.github/workflows/recall-worker.yml`:
```yaml
name: Recall Worker
on:
  schedule:
    - cron: '* * * * *'  # Every minute
  workflow_dispatch:  # Manual trigger

jobs:
  trigger-worker:
    runs-on: ubuntu-latest
    steps:
      - name: Trigger Worker
        run: |
          curl -X POST https://wklzogrfdrqluwchoqsp.supabase.co/functions/v1/recall-v2-worker \
            -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndrbHpvZ3JmZHJxbHV3Y2hvcXNwIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2MzEyMDM0NywiZXhwIjoyMDc4Njk2MzQ3fQ.Z0JuCvDrRnlHt_IKYi-fOhvV4_Tb8EYVW0eyAIN6WUc" \
            -H "Content-Type: application/json" \
            -d '{"max_jobs": 10}'
```

**Option 2: Cron-job.org or EasyCron (Free tier available)**
- Set up a cron job to call the worker endpoint every minute
- URL: `https://wklzogrfdrqluwchoqsp.supabase.co/functions/v1/recall-v2-worker`
- Method: POST
- Headers: `Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndrbHpvZ3JmZHJxbHV3Y2hvcXNwIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2MzEyMDM0NywiZXhwIjoyMDc4Njk2MzQ3fQ.Z0JuCvDrRnlHt_IKYi-fOhvV4_Tb8EYVW0eyAIN6WUc`
- Body: `{"max_jobs": 10}`

**Option 3: Manual Trigger (For Testing)**
You can manually trigger the worker when needed:
```bash
curl -X POST https://wklzogrfdrqluwchoqsp.supabase.co/functions/v1/recall-v2-worker \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndrbHpvZ3JmZHJxbHV3Y2hvcXNwIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2MzEyMDM0NywiZXhwIjoyMDc4Njk2MzQ3fQ.Z0JuCvDrRnlHt_IKYi-fOhvV4_Tb8EYVW0eyAIN6WUc" \
  -H "Content-Type: application/json" \
  -d '{"max_jobs": 10}'
```

## Step 7: Verify Deployment

### Test Database Schema

```sql
-- Test table creation
SELECT COUNT(*) FROM recalls;
SELECT COUNT(*) FROM recall_jobs;
SELECT COUNT(*) FROM recall_feedback;

-- Test RLS policies
-- (Run as authenticated user to verify access)
```

### Test Edge Functions

```bash
# Test router
curl -X POST https://wklzogrfdrqluwchoqsp.supabase.co/functions/v1/recall-v2-router \
  -H "Authorization: Bearer YOUR_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"recall_id": "test-id", "input_type": "text", "query_text": "test"}'

# Test worker
curl -X POST https://wklzogrfdrqluwchoqsp.supabase.co/functions/v1/recall-v2-worker \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndrbHpvZ3JmZHJxbHV3Y2hvcXNwIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2MzEyMDM0NywiZXhwIjoyMDc4Njk2MzQ3fQ.Z0JuCvDrRnlHt_IKYi-fOhvV4_Tb8EYVW0eyAIN6WUc" \
  -H "Content-Type: application/json" \
  -d '{"max_jobs": 1}'
```

### Test Storage

```sql
-- Verify bucket access
SELECT * FROM storage.buckets WHERE name LIKE 'recall%';
```

## Step 8: Migration from V1 (If Applicable)

If you have existing `recall_threads` and `recall_messages` data:

```sql
-- Optional: Migrate existing threads to new recalls table
-- This is a one-time migration script
INSERT INTO recalls (id, user_id, created_at, input_type, query_text, status)
SELECT 
  id,
  user_id,
  created_at,
  'text' as input_type,
  NULL as query_text,
  'done' as status
FROM recall_threads
ON CONFLICT (id) DO NOTHING;
```

## Troubleshooting

### RLS Policy Errors

If you see "new row violates row-level security policy":

1. Verify user is authenticated: `SELECT auth.uid();`
2. Check RLS is enabled: `SELECT tablename, rowsecurity FROM pg_tables WHERE tablename LIKE 'recall%';`
3. Verify policies exist: `SELECT * FROM pg_policies WHERE tablename LIKE 'recall%';`

### Storage Access Errors

1. Verify bucket exists: `SELECT * FROM storage.buckets WHERE name = 'recall-audio';`
2. Check storage policies: `SELECT * FROM storage.policies WHERE bucket_id = 'recall-audio';`
3. Ensure user is authenticated when uploading

### Edge Function Errors

1. Check function logs: `supabase functions logs recall-v2-router`
2. Verify secrets are set: `supabase secrets list`
3. Check function code for errors

### Worker Not Processing Jobs

1. Verify cron job is scheduled: `SELECT * FROM cron.job WHERE jobname = 'recall-v2-worker';`
2. Check cron logs: `SELECT * FROM cron.job_run_details WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'recall-v2-worker');`
3. Manually trigger worker to test

## Post-Deployment Checklist

- [ ] All tables created successfully
- [ ] All RLS policies applied
- [ ] Storage buckets created and accessible
- [ ] All edge functions deployed
- [ ] Secrets configured
- [ ] Worker cron job scheduled
- [ ] Learning processor cron job scheduled (optional)
- [ ] Test recall creation works
- [ ] Test job processing works
- [ ] Test storage upload works
- [ ] Test realtime subscriptions work

## Rollback Plan

If you need to rollback:

```sql
-- Drop tables (WARNING: This deletes all data!)
DROP TABLE IF EXISTS recall_logs CASCADE;
DROP TABLE IF EXISTS recall_learning_data CASCADE;
DROP TABLE IF EXISTS recall_user_preferences CASCADE;
DROP TABLE IF EXISTS recall_feedback CASCADE;
DROP TABLE IF EXISTS recall_jobs CASCADE;
DROP TABLE IF EXISTS saved_recalls CASCADE;
DROP TABLE IF EXISTS recall_candidates CASCADE;
DROP TABLE IF EXISTS recall_sources CASCADE;
DROP TABLE IF EXISTS recalls CASCADE;

-- Remove cron jobs
SELECT cron.unschedule('recall-v2-worker');
SELECT cron.unschedule('recall-learning-processor');
```

## Next Steps

After deployment:
1. Update iOS app to use new Recall v2 API
2. Test end-to-end flow
3. Monitor logs for errors
4. Adjust rate limits if needed
5. Tune learning processor schedule

