# How to Deploy recall-resolve Edge Function

## Prerequisites

1. **Supabase CLI installed**
   ```bash
   # Check if installed
   supabase --version
   
   # If not installed (macOS):
   brew install supabase/tap/supabase
   
   # Or via NPM:
   npm install -g supabase
   ```

2. **Logged into Supabase**
   ```bash
   supabase login
   ```

3. **Linked to your project**
   ```bash
   # Get your project ref from Supabase Dashboard (Settings > General > Reference ID)
   supabase link --project-ref YOUR_PROJECT_REF
   
   # Example:
   # supabase link --project-ref wklzogrfdrqluwchoqsp
   ```

## Step 1: Set Required Secrets

The `recall-resolve` function needs the OpenAI API key:

```bash
# Set OpenAI API key
supabase secrets set OPENAI_API_KEY="your-openai-api-key-here"

# Verify it's set
supabase secrets list
```

You should see `OPENAI_API_KEY` in the list.

**Note:** The following are automatically provided by Supabase (no need to set):
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`

## Step 2: Deploy the Function

Navigate to your project directory and deploy:

```bash
cd /Users/chukwudiebube/Downloads/RockOut-main

# Deploy recall-resolve function
supabase functions deploy recall-resolve
```

**Expected output:**
```
✓ Deployed Function recall-resolve
  URL: https://YOUR_PROJECT_REF.supabase.co/functions/v1/recall-resolve
```

## Step 3: Verify Deployment

Check that the function is deployed:

```bash
# List all deployed functions
supabase functions list
```

You should see `recall-resolve` in the list.

## Step 4: Test the Function (Optional)

Test using curl:

```bash
# Get your access token from the app (after logging in)
ACCESS_TOKEN="your-access-token-here"
PROJECT_URL="https://wklzogrfdrqluwchoqsp.supabase.co"

# Test with a text input
curl -X POST "$PROJECT_URL/functions/v1/recall-resolve" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "apikey: YOUR_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "thread_id": "your-thread-id",
    "message_id": "your-message-id",
    "input_type": "text",
    "text": "I heard this song in a TikTok"
  }'
```

## Troubleshooting

### Error: "Function not found"
- Make sure you're in the project root directory
- Verify the function folder exists: `supabase/functions/recall-resolve/index.ts`
- Check function name matches exactly (with hyphen: `recall-resolve`)

### Error: "OPENAI_API_KEY not configured"
- Run: `supabase secrets set OPENAI_API_KEY="your-key"`
- Verify: `supabase secrets list`

### Error: "Not authenticated" or "Invalid project ref"
- Run: `supabase login`
- Run: `supabase link --project-ref YOUR_PROJECT_REF`
- Get project ref from: Supabase Dashboard > Settings > General > Reference ID

### Error: "Permission denied"
- Make sure you're the project owner or have deployment permissions
- Check your Supabase account permissions

## Alternative: Deploy via Supabase Dashboard

If CLI doesn't work, you can deploy via the dashboard:

1. Go to **Supabase Dashboard** > **Edge Functions**
2. Click **"Create a new function"**
3. Name: `recall-resolve`
4. Copy contents from `supabase/functions/recall-resolve/index.ts`
5. Paste into the editor
6. Click **"Deploy"**
7. Go to **Settings** > **Edge Functions** > **Secrets**
8. Add secret: `OPENAI_API_KEY` = `your-key`

## What Happens After Deployment

Once deployed, the iOS app will:
1. Call `recall-resolve` when user sends text/voice/image
2. Function processes the input (transcribes voice if needed)
3. Calls OpenAI to find matching songs
4. Returns candidate results with confidence and sources
5. App displays the candidate card in the chat

**If function is not deployed:** The app will use a mock response (always returns "Example Song" with 85% confidence) for testing purposes.

## Quick Reference

```bash
# Full deployment sequence
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase secrets set OPENAI_API_KEY="your-key"
supabase functions deploy recall-resolve
supabase functions list  # Verify
```





