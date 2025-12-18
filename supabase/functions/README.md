# Supabase Edge Functions for Recall Feature

## Overview

This directory contains Edge Functions for the Recall feature, which allows users to find songs from memory using text, voice, or images.

## Functions

### recall_create
Creates a new recall event.

**Deployment:**
```bash
supabase functions deploy recall_create
```

**Request:**
```json
{
  "input_type": "text" | "voice" | "image",
  "raw_text": "string (optional, required for text/image)",
  "media_path": "string (optional, required for voice/image)"
}
```

**Response:**
```json
{
  "recall_id": "uuid",
  "status": "queued"
}
```

### recall_process
Processes a recall event using OpenAI with web search.

**Deployment:**
```bash
supabase functions deploy recall_process
```

**Required Secret:**
- `OPENAI_API_KEY` - Your OpenAI API key

**Request:**
```json
{
  "recall_id": "uuid"
}
```

**Response:**
```json
{
  "success": true,
  "recall_id": "uuid",
  "status": "done" | "needs_crowd",
  "confidence": 0.0-1.0,
  "candidates_count": 10
}
```

### recall_confirm
Confirms a candidate as the correct match.

**Deployment:**
```bash
supabase functions deploy recall_confirm
```

**Request:**
```json
{
  "recall_id": "uuid",
  "confirmed_title": "string",
  "confirmed_artist": "string"
}
```

**Response:**
```json
{
  "success": true,
  "confirmation_id": "uuid"
}
```

### recall_ask_crowd
Creates a GreenRoom post asking the crowd for help.

**Deployment:**
```bash
supabase functions deploy recall_ask_crowd
```

**Request:**
```json
{
  "recall_id": "uuid"
}
```

**Response:**
```json
{
  "success": true,
  "post_id": "uuid"
}
```

## Environment Variables

### Required Secrets

Set these using Supabase CLI:

```bash
# OpenAI API Key (required for recall_process)
supabase secrets set OPENAI_API_KEY="your-openai-api-key"
```

### Auto-Provided Variables

These are automatically provided by Supabase:
- `SUPABASE_URL` - Your Supabase project URL
- `SUPABASE_ANON_KEY` - Anonymous key
- `SUPABASE_SERVICE_ROLE_KEY` - Service role key (for admin operations)

## Deployment

Deploy all functions:

```bash
supabase functions deploy recall_create
supabase functions deploy recall_process
supabase functions deploy recall_confirm
supabase functions deploy recall_ask_crowd
```

## Testing

Test functions using curl:

```bash
# Get your access token from the app
ACCESS_TOKEN="your-access-token"
PROJECT_URL="https://your-project.supabase.co"

# Test recall_create
curl -X POST "$PROJECT_URL/functions/v1/recall_create" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"input_type":"text","raw_text":"I heard this song in a TikTok"}'
```

## Notes

- All functions require authentication via Bearer token in Authorization header
- Functions use CORS headers for cross-origin requests
- `recall_process` automatically creates a crowd post if confidence is low
- Storage paths for media should be in format: `{userId}/{recallId}/filename.ext`

