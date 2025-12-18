# Recall Schema Troubleshooting

## Common Errors

### Error: "column 'artist' does not exist"
This error occurs when:
1. The migration hasn't been run yet, OR
2. The migration ran partially and some columns are missing, OR
3. A query is trying to access `artist` from the wrong table

### Error: "column 'created_by' does not exist"
This error occurs when:
1. The `tracks` table was created without the `created_by` column, OR
2. The column was dropped or never added during migration

### Solution

Run the fix script to ensure all columns exist:

```sql
-- Run this in Supabase SQL Editor
-- File: sql/recall_schema_fix.sql
```

This script:
- Checks if tables exist
- Adds missing `artist` columns to:
  - `recall_candidates` table (column: `artist`)
  - `recall_confirmations` table (column: `confirmed_artist`)
  - `tracks` table (column: `artist`)
- Adds missing `created_by` column to `tracks` table
- Recreates all tables and policies if needed
- Is idempotent (safe to run multiple times)

### Verification

After running the fix, verify columns exist:

```sql
SELECT 
  table_name, 
  column_name 
FROM information_schema.columns 
WHERE table_schema = 'public' 
  AND table_name IN ('recall_candidates', 'recall_confirmations', 'tracks')
  AND column_name LIKE '%artist%'
ORDER BY table_name, column_name;
```

Expected output:
- `recall_candidates.artist`
- `recall_confirmations.confirmed_artist`
- `tracks.artist`
- `tracks.created_by`

### Common Issues

1. **Migration not run**: Run `sql/recall_schema.sql` first, then the fix script
2. **Partial migration**: The fix script will add missing columns
3. **Wrong table in query**: Make sure queries select `artist` from `recall_candidates`, not `recall_events`

### Table Structure Reference

- `recall_events`: Does NOT have `artist` column
- `recall_candidates`: Has `artist` column (TEXT NOT NULL)
- `recall_confirmations`: Has `confirmed_artist` column (TEXT NOT NULL)
- `tracks`: Has `artist` column (TEXT NOT NULL) and `created_by` column (UUID, references auth.users)

