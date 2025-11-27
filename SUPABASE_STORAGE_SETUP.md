# Supabase Storage Bucket Setup

## Creating the Feed Images Storage Bucket

You need to create a storage bucket named `feed-images` in Supabase to store photos uploaded with feed posts.

### Method 1: Using Supabase Dashboard (Recommended)

1. **Go to Supabase Dashboard**
   - Navigate to https://supabase.com/dashboard
   - Select your project

2. **Navigate to Storage**
   - In the left sidebar, click on **"Storage"**
   - This will show you all existing buckets

3. **Create New Bucket**
   - Click the **"New bucket"** button (usually top right)
   - A modal will appear with bucket configuration options

4. **Configure the Bucket**
   - **Name**: `feed-images`
   - **Public bucket**: ✅ **Enable this** (check the box)
     - This allows public read access to images via URLs
   - **File size limit**: Set to `5 MB` or `10 MB` (reasonable limit for images)
   - **Allowed MIME types**: (Optional) You can restrict to:
     - `image/jpeg`
     - `image/png`
     - `image/webp`
   - Click **"Create bucket"**

5. **Set Bucket Policies** (Important!)
   - After creating the bucket, click on it to view details
   - Go to the **"Policies"** tab
   - You need to create policies for authenticated users to upload images

6. **Create Upload Policy**
   - Click **"New Policy"**
   - Choose **"Create policy from scratch"**
   - **Policy name**: `Authenticated users can upload images`
   - **Allowed operation**: `INSERT`
   - **Target roles**: `authenticated`
   - **Policy definition**:
     ```sql
     (bucket_id = 'feed-images'::text) AND (auth.role() = 'authenticated'::text)
     ```
   - Click **"Save"**

7. **Create Read Policy** (if public bucket is enabled, this is automatic)
   - If not already public, create a read policy:
   - **Policy name**: `Anyone can read images`
   - **Allowed operation**: `SELECT`
   - **Target roles**: `anon, authenticated`
   - **Policy definition**:
     ```sql
     bucket_id = 'feed-images'::text
     ```
   - Click **"Save"**

### Method 2: Using SQL Editor

If you prefer SQL, run this in the Supabase SQL Editor:

```sql
-- Create the bucket
INSERT INTO storage.buckets (id, name, public)
VALUES ('feed-images', 'feed-images', true)
ON CONFLICT (id) DO NOTHING;

-- Create policy for authenticated users to upload
CREATE POLICY "Authenticated users can upload feed images"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'feed-images' AND
  (storage.foldername(name))[1] = 'feed_posts'
);

-- Create policy for anyone to read images (since bucket is public)
CREATE POLICY "Anyone can read feed images"
ON storage.objects
FOR SELECT
TO public
USING (bucket_id = 'feed-images');
```

### Verification

After creating the bucket:

1. Go to Storage → `feed-images` bucket
2. Try uploading a test image manually (if available)
3. Verify the bucket appears in the list
4. Check that policies are active in the Policies tab

### Folder Structure

The app will automatically organize images in this structure:
```
feed-images/
  └── feed_posts/
      └── {user-id}/
          └── {uuid}.jpg
```

### Troubleshooting

**Issue**: "Bucket not found" error
- **Solution**: Make sure the bucket name is exactly `feed-images` (case-sensitive)

**Issue**: "Permission denied" when uploading
- **Solution**: Check that the upload policy is created and active for authenticated users

**Issue**: Images not displaying
- **Solution**: 
  - Verify the bucket is set to public, OR
  - Ensure the read policy allows public access

**Issue**: File size too large
- **Solution**: Increase the file size limit in bucket settings, or compress images before upload

### Security Notes

- The bucket stores images in user-specific folders (`feed_posts/{user-id}/`)
- Only authenticated users can upload (enforced by policy)
- Public read access allows images to display in the app without authentication
- Consider adding:
  - Image compression/optimization before upload
  - Virus scanning (if available)
  - Rate limiting (handled by Supabase)

### Next Steps

After creating the bucket:
1. Test image upload in the app
2. Verify images display correctly in feed posts
3. Monitor storage usage in the Supabase dashboard

