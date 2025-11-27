-- Update profiles table to include first_name, last_name, and instagram_handle
ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS first_name TEXT,
ADD COLUMN IF NOT EXISTS last_name TEXT,
ADD COLUMN IF NOT EXISTS instagram_handle TEXT;

-- Create index for instagram_handle lookups if needed
CREATE INDEX IF NOT EXISTS idx_profiles_instagram_handle ON profiles(instagram_handle) WHERE instagram_handle IS NOT NULL;

