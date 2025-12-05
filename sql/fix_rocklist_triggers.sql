-- Fix RockList Triggers
-- Remove or fix any triggers on rocklist_stats that reference non-existent "rank" field
-- Rank is calculated dynamically in queries, not stored in the table

-- Drop the problematic trigger if it exists
DROP TRIGGER IF EXISTS trg_rocklist_rank_notification ON rocklist_stats;

-- The notify_rocklist_rank_improvement function references NEW.rank and OLD.rank
-- which don't exist in rocklist_stats table. Since rank is calculated dynamically,
-- we need to either:
-- 1. Remove the trigger entirely (rank notifications would need to be calculated differently)
-- 2. Rewrite the function to calculate rank on-the-fly (more complex)

-- For now, we'll drop the trigger and note that rank-based notifications
-- would need to be implemented differently (e.g., via a scheduled job that
-- compares current rank with previous rank stored elsewhere)

-- If rank-based notifications are needed in the future, consider:
-- 1. Creating a separate table to store user's previous rank per artist
-- 2. Using a scheduled function to compare current ranks with stored ranks
-- 3. Sending notifications when rank improves

-- Note: The trigger function itself can remain commented out in notification_triggers.sql
-- but the trigger should not be created until a proper solution is implemented

