-- Add is_collaboration column to shareable_links table
-- This allows share links to specify if they're for collaborations

ALTER TABLE shareable_links 
ADD COLUMN IF NOT EXISTS is_collaboration BOOLEAN DEFAULT false;

