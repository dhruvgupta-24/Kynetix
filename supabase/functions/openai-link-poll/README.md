# openai-link-poll

This Supabase Edge Function polls the OpenAI device authorization API. It handles token resolution and securely stores tokens to the database.

## Requirements

Create this table in your Supabase project using the SQL editor:

```sql
-- Securely store the linked OpenAI API tokens per user
CREATE TABLE public.user_openai_links (
    user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    access_token text NOT NULL,
    refresh_token text,
    id_token text,
    expires_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

-- Recommended: Enable RLS and block read/write from API depending on security posture.
-- If the UI doesn't need to read the token directly (e.g. only AiNutritionService accesses via service_role), block all.
ALTER TABLE public.user_openai_links ENABLE ROW LEVEL SECURITY;
```

## Deployment

Deploy this function by running:

```bash
supabase functions deploy openai-link-poll --no-verify-jwt
```
*Note: We skip `--no-verify-jwt` because we handle JWT verification securely inside the script to provide better internal error handling and CORS support to Flutter.*

## Environment Variables

Ensure the following variables are set on your Supabase Edge Function:

```bash
# Public Client ID from openai-link-start
supabase secrets set OPENAI_OAUTH_CLIENT_ID="<your_openai_client_id>"

# Wait, if this requests an OAuth token callback from the CLI equivalent, 
# you might also need OPENAI_OAUTH_REDIRECT_URI if defaults aren't adequate.
```
