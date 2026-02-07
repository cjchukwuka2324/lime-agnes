# Fix: pg_cron Extension Not Available

## Quick Solution: Enable pg_cron via Dashboard

1. Go to **Supabase Dashboard** → **Database** → **Extensions**
2. Search for **"pg_cron"**
3. Click **"Enable"**
4. Wait for it to enable (may take a few seconds)
5. Re-run `supabase/setup_cron_jobs.sql`

## Alternative: Use GitHub Actions (No pg_cron needed)

If `pg_cron` is not available on your plan, use GitHub Actions instead:

### Already Set Up

I've created GitHub Actions workflows that will run automatically:

1. **`.github/workflows/recall-worker.yml`** - Runs every minute
2. **`.github/workflows/recall-learning-processor.yml`** - Runs daily at 2 AM

### To Activate

1. Commit and push these files to your GitHub repo
2. Go to GitHub → Actions tab
3. The workflows will run automatically on schedule

### Manual Trigger

You can also manually trigger them:
- GitHub → Actions → "Recall Worker Cron" → "Run workflow"
- GitHub → Actions → "Recall Learning Processor Cron" → "Run workflow"

## Alternative: Use External Cron Service

If you prefer not to use GitHub Actions:

1. Sign up for a free cron service (e.g., cron-job.org, EasyCron)
2. Create a cron job that calls:
   - **URL**: `https://wklzogrfdrqluwchoqsp.supabase.co/functions/v1/recall-v2-worker`
   - **Method**: POST
   - **Headers**: 
     ```
     Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndrbHpvZ3JmZHJxbHV3Y2hvcXNwIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2MzEyMDM0NywiZXhwIjoyMDc4Njk2MzQ3fQ.Z0JuCvDrRnlHt_IKYi-fOhvV4_Tb8EYVW0eyAIN6WUc
     Content-Type: application/json
     ```
   - **Body**: `{"max_jobs": 10}`
   - **Schedule**: Every minute (`* * * * *`)

## Recommended: Use GitHub Actions

The GitHub Actions approach is:
- ✅ Free
- ✅ No database extension needed
- ✅ Easy to monitor (GitHub Actions tab)
- ✅ Can be manually triggered
- ✅ Already configured and ready to use

Just commit and push the workflow files!

















