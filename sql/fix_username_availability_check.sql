-- ============================================
-- Fix Username Availability Check for Signup
-- This grants anonymous users permission to read usernames
-- ============================================

-- Grant SELECT permission to anonymous users on profiles table
-- This is needed for username availability check during signup (before user is authenticated)
GRANT SELECT ON public.profiles TO anon;

-- Verify the RLS policy allows anonymous reads (should already exist)
-- The policy "Users can view all profiles" should already allow this with USING (true)
-- But let's ensure it exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE schemaname = 'public' 
        AND tablename = 'profiles' 
        AND policyname = 'Users can view all profiles'
    ) THEN
        CREATE POLICY "Users can view all profiles" ON profiles
            FOR SELECT
            USING (true);
    END IF;
END $$;

-- Comment for documentation
COMMENT ON TABLE profiles IS 'User profile information. Anonymous users can read usernames for availability checks during signup.';

