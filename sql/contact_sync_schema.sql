-- Contact Sync Schema for RockOut
-- Stores synced contacts and matches them with existing users

-- ============================================================================
-- Table: user_contacts
-- ============================================================================

CREATE TABLE IF NOT EXISTS user_contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    contact_phone TEXT,
    contact_email TEXT,
    contact_name TEXT NOT NULL,
    matched_user_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- Ensure at least one contact identifier exists
    CONSTRAINT contact_identifier_check CHECK (
        contact_phone IS NOT NULL OR contact_email IS NOT NULL
    ),
    
    -- Unique constraint: one contact per user (by phone or email)
    CONSTRAINT unique_user_contact UNIQUE (user_id, contact_phone, contact_email)
);

-- Indexes for efficient querying
CREATE INDEX IF NOT EXISTS idx_user_contacts_user_id ON user_contacts(user_id);
CREATE INDEX IF NOT EXISTS idx_user_contacts_matched_user_id ON user_contacts(matched_user_id) WHERE matched_user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_user_contacts_phone ON user_contacts(contact_phone) WHERE contact_phone IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_user_contacts_email ON user_contacts(contact_email) WHERE contact_email IS NOT NULL;

-- ============================================================================
-- Function: match_contacts_with_users
-- ============================================================================

CREATE OR REPLACE FUNCTION match_contacts_with_users(
    p_user_id UUID,
    p_contacts TEXT
)
RETURNS TABLE (
    contact_name TEXT,
    contact_phone TEXT,
    contact_email TEXT,
    matched_user_id UUID,
    matched_user_display_name TEXT,
    matched_user_handle TEXT,
    matched_user_avatar_url TEXT,
    has_account BOOLEAN
) AS $$
DECLARE
    contact_item JSONB;
    phone_number TEXT;
    email_address TEXT;
    matched_profile RECORD;
DECLARE
    contacts_jsonb JSONB;
BEGIN
    -- Parse the JSON string to JSONB
    contacts_jsonb := p_contacts::JSONB;
    
    -- Loop through each contact in the JSONB array
    FOR contact_item IN SELECT * FROM jsonb_array_elements(contacts_jsonb)
    LOOP
        -- Extract contact information
        contact_name := contact_item->>'name';
        phone_number := NULL;
        email_address := NULL;
        
        -- Extract phone numbers (first one if multiple)
        IF contact_item ? 'phone_numbers' AND jsonb_typeof(contact_item->'phone_numbers') = 'array' THEN
            IF jsonb_array_length(contact_item->'phone_numbers') > 0 THEN
                phone_number := contact_item->'phone_numbers'->>0;
            END IF;
        END IF;
        
        -- Extract email if present
        IF contact_item ? 'email' THEN
            email_address := contact_item->>'email';
        END IF;
        
        -- Skip if no contact identifier
        IF phone_number IS NULL AND email_address IS NULL THEN
            CONTINUE;
        END IF;
        
        -- Try to match with existing user by phone or email
        matched_profile := NULL;
        
        -- Match by phone number (assuming profiles table has a phone column)
        -- Note: You may need to adjust this based on your actual schema
        IF phone_number IS NOT NULL THEN
            SELECT p.id, p.display_name, p.handle, p.profile_picture_url
            INTO matched_profile
            FROM profiles p
            WHERE p.phone = phone_number
               OR p.phone_hash = encode(digest(phone_number, 'sha256'), 'hex')
            LIMIT 1;
        END IF;
        
        -- If no match by phone, try email
        IF matched_profile IS NULL AND email_address IS NOT NULL THEN
            SELECT p.id, p.display_name, p.handle, p.profile_picture_url
            INTO matched_profile
            FROM profiles p
            JOIN auth.users u ON u.id = p.id
            WHERE u.email = email_address
            LIMIT 1;
        END IF;
        
        -- Upsert contact record
        INSERT INTO user_contacts (user_id, contact_phone, contact_email, contact_name, matched_user_id, updated_at)
        VALUES (p_user_id, phone_number, email_address, contact_name, matched_profile.id, NOW())
        ON CONFLICT (user_id, contact_phone, contact_email)
        DO UPDATE SET
            matched_user_id = COALESCE(EXCLUDED.matched_user_id, user_contacts.matched_user_id),
            updated_at = NOW();
        
        -- Return matched contact information
        RETURN QUERY SELECT
            contact_name,
            phone_number,
            email_address,
            matched_profile.id,
            matched_profile.display_name,
            matched_profile.handle,
            matched_profile.profile_picture_url,
            (matched_profile.id IS NOT NULL) as has_account;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- Row Level Security (RLS) Policies
-- ============================================================================

ALTER TABLE user_contacts ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Users can view their own contacts" ON user_contacts;
DROP POLICY IF EXISTS "Users can insert their own contacts" ON user_contacts;
DROP POLICY IF EXISTS "Users can update their own contacts" ON user_contacts;

-- Users can only read their own contacts
CREATE POLICY "Users can view their own contacts"
    ON user_contacts FOR SELECT
    USING (auth.uid() = user_id);

-- Users can insert their own contacts
CREATE POLICY "Users can insert their own contacts"
    ON user_contacts FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Users can update their own contacts
CREATE POLICY "Users can update their own contacts"
    ON user_contacts FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- ============================================================================
-- Comments
-- ============================================================================

COMMENT ON TABLE user_contacts IS 'Stores synced contacts for users and matches them with existing accounts';
COMMENT ON COLUMN user_contacts.matched_user_id IS 'ID of the user profile that matches this contact (if found)';
COMMENT ON FUNCTION match_contacts_with_users IS 'Syncs contacts to the database and matches them with existing users by phone or email';

