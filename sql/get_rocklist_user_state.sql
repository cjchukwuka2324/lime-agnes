-- Get RockList User State Function
-- Returns the current user's last_ingested_played_at timestamp
-- Used by the app to determine if initial or incremental ingestion is needed

CREATE OR REPLACE FUNCTION get_rocklist_user_state()
RETURNS TABLE (
    last_ingested_played_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_user_id UUID;
BEGIN
    -- Get current authenticated user
    v_current_user_id := auth.uid();
    
    IF v_current_user_id IS NULL THEN
        RETURN;
    END IF;
    
    -- Return the last_ingested_played_at timestamp from profiles table
    RETURN QUERY
    SELECT COALESCE(p.last_ingested_played_at, NULL::TIMESTAMPTZ) AS last_ingested_played_at
    FROM profiles p
    WHERE p.id = v_current_user_id;
    
    -- If no profile exists, return NULL (no previous ingestion)
    IF NOT FOUND THEN
        RETURN QUERY SELECT NULL::TIMESTAMPTZ AS last_ingested_played_at;
    END IF;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION get_rocklist_user_state() TO authenticated;

