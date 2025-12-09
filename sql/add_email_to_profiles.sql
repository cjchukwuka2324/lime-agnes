-- Add email column to profiles table
-- This stores the email users register with in the profiles table

ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS email TEXT;

-- Create index for email lookups (useful for search)
CREATE INDEX IF NOT EXISTS idx_profiles_email ON profiles(email) WHERE email IS NOT NULL;

-- Backfill email from auth.users for existing profiles
UPDATE profiles p
SET email = u.email
FROM auth.users u
WHERE p.id = u.id 
  AND p.email IS NULL;

-- Comment
COMMENT ON COLUMN profiles.email IS 'Email address from user registration';

