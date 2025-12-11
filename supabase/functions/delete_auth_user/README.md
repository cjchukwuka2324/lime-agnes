# Delete Auth User Edge Function

This Supabase Edge Function deletes a user from `auth.users` using the Admin API.

## Purpose

When a user deletes their account, all their data is removed from public tables via the `delete_user_account()` RPC function. This edge function then deletes the user from `auth.users` to complete the account deletion process.

## Deployment

1. **Deploy the function:**
   ```bash
   supabase functions deploy delete_auth_user
   ```

2. **The function automatically uses these environment variables (set by Supabase):**
   - `SUPABASE_URL` - Your Supabase project URL
   - `SUPABASE_SERVICE_ROLE_KEY` - Service role key for Admin API access

3. **No additional secrets are required** - the function uses the service role key that Supabase automatically provides to edge functions.

## How It Works

1. Client calls `UserProfileService.deleteAccount()`
2. `delete_user_account()` RPC is called to delete all user data from public tables
3. This edge function is called with the user's access token
4. Function verifies the token and gets the user ID
5. Function uses Admin API to delete the user from `auth.users`
6. Client signs out

## Security

- The function requires a valid user access token (Bearer token in Authorization header)
- Only the authenticated user can delete their own account (via token verification)
- Uses service role key to call Admin API (not exposed to client)
- CORS enabled for cross-origin requests

## Testing

```bash
# Replace YOUR_PROJECT, USER_ACCESS_TOKEN, and ANON_KEY
curl -X POST 'https://YOUR_PROJECT.supabase.co/functions/v1/delete_auth_user' \
  -H 'Authorization: Bearer USER_ACCESS_TOKEN' \
  -H 'apikey: ANON_KEY' \
  -H 'Content-Type: application/json'
```

## Error Handling

- Returns 401 if no authorization token provided
- Returns 401 if token is invalid or expired
- Returns 500 if Admin API call fails
- Returns 200 on successful deletion

## Notes

- This function should ONLY be called AFTER `delete_user_account()` RPC has successfully deleted all public data
- Once the auth user is deleted, they cannot sign in again (even if some data remains)
- The function logs all operations for debugging

