-- ============================================
-- Create profiles table and handle_new_user trigger
-- This must be run BEFORE users can sign up
-- ============================================

-- Step 1: Create profiles table
CREATE TABLE IF NOT EXISTS profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    display_name TEXT,
    username TEXT UNIQUE,
    first_name TEXT,
    last_name TEXT,
    email TEXT,
    profile_picture_url TEXT,
    region TEXT,
    followers_count INTEGER NOT NULL DEFAULT 0,
    following_count INTEGER NOT NULL DEFAULT 0,
    instagram TEXT,
    twitter TEXT,
    tiktok TEXT,
    last_ingested_played_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- Step 2: Create indexes
CREATE INDEX IF NOT EXISTS idx_profiles_username ON profiles(username) WHERE username IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_profiles_email ON profiles(email) WHERE email IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_profiles_last_ingested ON profiles(last_ingested_played_at);

-- Step 3: Enable RLS
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- Step 4: Create RLS Policies
-- Allow users to read all profiles
DROP POLICY IF EXISTS "Users can view all profiles" ON profiles;
CREATE POLICY "Users can view all profiles" ON profiles
    FOR SELECT
    USING (true);

-- Allow users to update their own profile
DROP POLICY IF EXISTS "Users can update their own profile" ON profiles;
CREATE POLICY "Users can update their own profile" ON profiles
    FOR UPDATE
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);

-- Allow users to insert their own profile (for trigger)
DROP POLICY IF EXISTS "Users can insert their own profile" ON profiles;
CREATE POLICY "Users can insert their own profile" ON profiles
    FOR INSERT
    WITH CHECK (auth.uid() = id);

-- Step 5: Create trigger function to automatically create profile when user signs up
-- Note: display_name and username are set to NULL initially - they will be set by createOrUpdateProfile
-- from the signup form data (firstName + lastName for display_name, and username for username)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, display_name, username, created_at, updated_at, email)
    VALUES (
        NEW.id,
        NULL, -- Will be set by createOrUpdateProfile from firstName + lastName
        NULL, -- Will be set by createOrUpdateProfile from signup form username
        COALESCE(NEW.created_at, NOW()),
        NOW(),
        NEW.email
    )
    ON CONFLICT (id) DO NOTHING;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 6: Create trigger on auth.users table
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_user();

-- Step 7: Grant necessary permissions
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO anon;
GRANT SELECT, INSERT, UPDATE ON public.profiles TO authenticated;
-- Allow anonymous users to read profiles (needed for username availability check during signup)
GRANT SELECT ON public.profiles TO anon;

-- Step 8: Add comment for documentation
COMMENT ON TABLE profiles IS 'User profile information synchronized with auth.users';
COMMENT ON FUNCTION handle_new_user IS 'Automatically creates a profile entry when a new user signs up. Sets display_name and username to NULL initially - these are populated by createOrUpdateProfile from signup form data (firstName + lastName for display_name, username for username)';

