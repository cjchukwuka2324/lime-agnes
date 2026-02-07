# Apply Database Migration for Recall Thread Management

## Error
The app is showing: `column recall_threads.pinned does not exist`

This means the database migration hasn't been applied yet.

## Solution

Run the migration file in your Supabase database:

### Option 1: Using Supabase CLI
```bash
supabase db push
```

Or manually:
```bash
supabase migration up
```

### Option 2: Using Supabase Dashboard
1. Go to your Supabase project dashboard
2. Navigate to SQL Editor
3. Copy and paste the contents of `supabase/migrations/add_thread_management_fields.sql`
4. Click "Run"

### Option 3: Direct SQL Execution
Run this SQL in your Supabase SQL Editor:

```sql
-- Add missing fields to recall_threads
ALTER TABLE public.recall_threads
ADD COLUMN IF NOT EXISTS pinned BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS archived BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS summary TEXT;

-- Add status field to recall_messages
ALTER TABLE public.recall_messages
ADD COLUMN IF NOT EXISTS status TEXT CHECK (status IN ('sending', 'sent', 'failed')) DEFAULT 'sent',
ADD COLUMN IF NOT EXISTS response_text TEXT;

-- Add indices for performance
CREATE INDEX IF NOT EXISTS idx_recall_threads_pinned ON public.recall_threads(pinned) WHERE pinned = TRUE;
CREATE INDEX IF NOT EXISTS idx_recall_threads_archived ON public.recall_threads(archived) WHERE archived = FALSE;
CREATE INDEX IF NOT EXISTS idx_recall_threads_deleted_at ON public.recall_threads(deleted_at) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_recall_messages_status ON public.recall_messages(status);
```

## After Migration

Once the migration is applied, the app will work correctly. The code has been updated to:
- Only select base columns until migration is applied
- Only update `title` field until migration is applied
- Gracefully handle missing columns

After migration, you can uncomment the `pinned` and `archived` fields in `RecallThreadStore.updateThread()` if needed.






