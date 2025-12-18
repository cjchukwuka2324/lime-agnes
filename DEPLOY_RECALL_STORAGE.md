# Deploy Recall Storage Policies

## Issue
The error "new row violates row-level security policy" when uploading audio files indicates that the storage RLS policies for the `recall-audio` bucket are not deployed.

## Solution

### Step 1: Verify Bucket Exists

1. Open your Supabase Dashboard
2. Navigate to **Storage**
3. Verify that the `recall-audio` bucket exists
4. If it doesn't exist, create it:
   - Click **New bucket**
   - Name: `recall-audio`
   - **Public**: No (Private bucket)
   - Click **Create bucket**

### Step 2: Deploy Storage Policies

**Option A: Simple Policy (for testing - allows all authenticated users to upload)**

If you want to test quickly first, use this simpler policy:

```sql
-- Simple policy: Allow all authenticated users to upload to recall-audio
DROP POLICY IF EXISTS "Allow authenticated uploads to recall-audio" ON storage.objects;
CREATE POLICY "Allow authenticated uploads to recall-audio" ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (bucket_id = 'recall-audio');

DROP POLICY IF EXISTS "Allow authenticated reads from recall-audio" ON storage.objects;
CREATE POLICY "Allow authenticated reads from recall-audio" ON storage.objects
  FOR SELECT
  TO authenticated
  USING (bucket_id = 'recall-audio');

DROP POLICY IF EXISTS "Allow authenticated deletes from recall-audio" ON storage.objects;
CREATE POLICY "Allow authenticated deletes from recall-audio" ON storage.objects
  FOR DELETE
  TO authenticated
  USING (bucket_id = 'recall-audio');
```

**Option B: Secure Policy (recommended - restricts to user's own folder)**

For production, use this policy that restricts users to their own folders (lines 275-304 from `supabase/recall.sql`):

```sql
-- Storage Policies for recall-audio bucket
-- Policy: Users can upload their own audio
DROP POLICY IF EXISTS "Users can upload their own audio" ON storage.objects;
CREATE POLICY "Users can upload their own audio" ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'recall-audio' AND
    (storage.foldername(name))[1] = auth.uid()::text
  );

-- Policy: Users can read their own audio
DROP POLICY IF EXISTS "Users can read their own audio" ON storage.objects;
CREATE POLICY "Users can read their own audio" ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'recall-audio' AND
    (storage.foldername(name))[1] = auth.uid()::text
  );

-- Policy: Users can delete their own audio
DROP POLICY IF EXISTS "Users can delete their own audio" ON storage.objects;
CREATE POLICY "Users can delete their own audio" ON storage.objects
  FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'recall-audio' AND
    (storage.foldername(name))[1] = auth.uid()::text
  );
```

**To deploy:**

1. Open your Supabase Dashboard
2. Navigate to **SQL Editor**
3. Copy and paste **Option A** (for quick test) or **Option B** (for production)
4. Click **Run** to execute the SQL
5. Verify no errors appear in the results

### Step 3: Verify Policies Are Active

1. In Supabase Dashboard, go to **Storage** → **Policies**
2. Filter by bucket: `recall-audio`
3. You should see three policies:
   - "Users can upload their own audio" (INSERT)
   - "Users can read their own audio" (SELECT)
   - "Users can delete their own audio" (DELETE)
4. Ensure all three are **Active** (green checkmark)

### Step 4: Test Upload

1. Run the app again
2. Try recording and uploading a voice note
3. The upload should now succeed

## Troubleshooting

**If policies still don't work:**

1. Check that RLS is enabled on the `storage.objects` table:
   ```sql
   SELECT tablename, rowsecurity 
   FROM pg_tables 
   WHERE schemaname = 'storage' AND tablename = 'objects';
   ```
   `rowsecurity` should be `true`

2. Verify the bucket ID matches exactly:
   ```sql
   SELECT id, name, public 
   FROM storage.buckets 
   WHERE name = 'recall-audio';
   ```

3. **Verify policies are actually created:**
   ```sql
   SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
   FROM pg_policies
   WHERE tablename = 'objects' AND schemaname = 'storage'
   AND policyname LIKE '%recall-audio%';
   ```
   You should see 3 policies listed.

4. Test the policy manually:
   ```sql
   -- This should return your user ID
   SELECT auth.uid();
   
   -- This should show the folder structure as an array
   SELECT storage.foldername('62832CF5-8A68-4BAC-A4B9-51BC79385A85/9794756D-EAC0-43C2-90C7-4932D5EB2DA6/voice_1765866046.m4a');
   -- Should return: {62832CF5-8A68-4BAC-A4B9-51BC79385A85,9794756D-EAC0-43C2-90C7-4932D5EB2DA6}
   ```

5. **If using Option B (folder restriction), verify the path matches:**
   ```sql
   -- Check if the first folder matches your user ID
   SELECT 
     auth.uid()::text as user_id,
     (storage.foldername('62832CF5-8A68-4BAC-A4B9-51BC79385A85/9794756D-EAC0-43C2-90C7-4932D5EB2DA6/voice_1765866046.m4a'))[1] as first_folder,
     CASE 
       WHEN auth.uid()::text = (storage.foldername('62832CF5-8A68-4BAC-A4B9-51BC79385A85/9794756D-EAC0-43C2-90C7-4932D5EB2DA6/voice_1765866046.m4a'))[1] 
       THEN 'MATCH' 
       ELSE 'NO MATCH' 
     END as match_status;
   ```

6. **If policies exist but still fail, try dropping and recreating:**
   ```sql
   -- Drop all recall-audio policies
   DROP POLICY IF EXISTS "Users can upload their own audio" ON storage.objects;
   DROP POLICY IF EXISTS "Users can read their own audio" ON storage.objects;
   DROP POLICY IF EXISTS "Users can delete their own audio" ON storage.objects;
   DROP POLICY IF EXISTS "Allow authenticated uploads to recall-audio" ON storage.objects;
   DROP POLICY IF EXISTS "Allow authenticated reads from recall-audio" ON storage.objects;
   DROP POLICY IF EXISTS "Allow authenticated deletes from recall-audio" ON storage.objects;
   
   -- Then recreate using Option A (simple) or Option B (secure) from Step 2
   ```

## Path Structure

Files are uploaded with this path format:
```
{userId}/{threadId}/{filename}
```

Example:
```
62832CF5-8A68-4BAC-A4B9-51BC79385A85/9794756D-EAC0-43C2-90C7-4932D5EB2DA6/voice_1765865161.m4a
```

The policy checks that the first folder (`[1]`) matches the authenticated user's ID (`auth.uid()::text`).

