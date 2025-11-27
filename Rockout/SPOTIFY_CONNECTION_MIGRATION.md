# Spotify Connection Database Migration

This document outlines the database schema needed for per-user Spotify account connections.

## Required Table

### `spotify_connections` Table

```sql
CREATE TABLE spotify_connections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    spotify_user_id TEXT NOT NULL,
    access_token TEXT NOT NULL,
    refresh_token TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    connected_at TIMESTAMPTZ DEFAULT NOW(),
    display_name TEXT,
    email TEXT,
    UNIQUE(user_id)
);

CREATE INDEX idx_spotify_connections_user ON spotify_connections(user_id);
CREATE INDEX idx_spotify_connections_spotify_user ON spotify_connections(spotify_user_id);
```

## Row Level Security (RLS) Policies

```sql
-- Enable RLS
ALTER TABLE spotify_connections ENABLE ROW LEVEL SECURITY;

-- Users can view their own connections
CREATE POLICY "Users can view own connections"
    ON spotify_connections FOR SELECT
    USING (auth.uid() = user_id);

-- Users can insert their own connections
CREATE POLICY "Users can create own connections"
    ON spotify_connections FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Users can update their own connections
CREATE POLICY "Users can update own connections"
    ON spotify_connections FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Users can delete their own connections
CREATE POLICY "Users can delete own connections"
    ON spotify_connections FOR DELETE
    USING (auth.uid() = user_id);
```

## Notes

1. **Token Security**: Access tokens and refresh tokens are stored in plain text. Consider encrypting them if you have additional security requirements.

2. **Token Expiration**: The `expires_at` field stores when the access token expires. The app will automatically refresh tokens when needed.

3. **User Info**: `display_name` and `email` are optional and fetched from Spotify's user profile API.

4. **Unique Constraint**: Each user can only have one Spotify connection (enforced by UNIQUE constraint on `user_id`).

5. **Cascade Delete**: When a user is deleted, their Spotify connection is automatically deleted.

## Testing

After running these migrations, test:

1. Connect Spotify account from Profile view
2. Verify connection appears in database
3. Disconnect Spotify account
4. Verify connection is deleted from database
5. Reconnect with different Spotify account
6. Verify tokens are updated correctly

