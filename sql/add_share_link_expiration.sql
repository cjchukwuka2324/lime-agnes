-- ============================================
-- Add Expiration and Collaboration Support to Share Links
-- This migration ensures all necessary columns exist for expiration and revocation
-- Safe to run multiple times - it checks if columns exist before adding
-- ============================================

-- Add is_collaboration column if it doesn't exist
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_schema = 'public'
        AND table_name = 'shareable_links' 
        AND column_name = 'is_collaboration'
    ) THEN
        ALTER TABLE shareable_links
        ADD COLUMN is_collaboration BOOLEAN DEFAULT FALSE;
        
        -- Update existing records to be view-only (false) if needed
        UPDATE shareable_links
        SET is_collaboration = FALSE
        WHERE is_collaboration IS NULL;
        
        RAISE NOTICE 'Added is_collaboration column to shareable_links table';
    ELSE
        RAISE NOTICE 'Column is_collaboration already exists in shareable_links table';
    END IF;
END $$;

-- Verify expires_at column exists (should already be there from initial schema)
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_schema = 'public'
        AND table_name = 'shareable_links' 
        AND column_name = 'expires_at'
    ) THEN
        ALTER TABLE shareable_links
        ADD COLUMN expires_at TIMESTAMPTZ;
        
        RAISE NOTICE 'Added expires_at column to shareable_links table';
    ELSE
        RAISE NOTICE 'Column expires_at already exists in shareable_links table';
    END IF;
END $$;

-- Verify is_active column exists (should already be there from initial schema)
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_schema = 'public'
        AND table_name = 'shareable_links' 
        AND column_name = 'is_active'
    ) THEN
        ALTER TABLE shareable_links
        ADD COLUMN is_active BOOLEAN DEFAULT TRUE;
        
        -- Set all existing records to active if null
        UPDATE shareable_links
        SET is_active = TRUE
        WHERE is_active IS NULL;
        
        RAISE NOTICE 'Added is_active column to shareable_links table';
    ELSE
        RAISE NOTICE 'Column is_active already exists in shareable_links table';
    END IF;
END $$;

-- Add indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_shareable_links_expires_at 
ON shareable_links(expires_at) 
WHERE expires_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_shareable_links_is_active 
ON shareable_links(is_active) 
WHERE is_active = TRUE;

-- Add comments for documentation
COMMENT ON COLUMN shareable_links.is_collaboration IS 'Whether this share link allows collaboration (true) or is view-only (false)';
COMMENT ON COLUMN shareable_links.expires_at IS 'Optional timestamp when this share link expires. NULL means it never expires.';
COMMENT ON COLUMN shareable_links.is_active IS 'Whether this share link is currently active. Can be set to false to revoke access.';
