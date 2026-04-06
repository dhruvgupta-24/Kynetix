# openai-link-start

This Supabase Edge Function initiates the OpenAI device authorization flow on behalf of an authenticated Kynetix user.

## Requirements

You must create the following table in your public schema or a secure private schema to hold the temporary device codes. Since the function uses the `service_role` key to interact with this table, it does not strictly need to be exposed via PostgREST, but you must create it via the SQL editor.

```sql
-- Create a table to temporarily hold the OpenAI device_code for a user while they authenticate
CREATE TABLE public.openai_device_auth_sessions (
    user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    device_code text NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

-- Recommended: Enable RLS, but restrict all HTTP access since only Edge Functions (service_role) should touch this.
ALTER TABLE public.openai_device_auth_sessions ENABLE ROW LEVEL SECURITY;
```

## Deployment

To deploy this function (assuming you have `supabase` initialized locally):

```bash
supabase functions deploy openai-link-start --no-verify-jwt
```
*Note: We skip JWT verification at the API Gateway level because we explicitly handle checking the `Authorization` header within the code so we can inject robust errors and CORS headers back to Flutter.*

## Secrets Required

You must set the OpenAI Client ID environment variable for the Edge Function:

```bash
supabase secrets set OPENAI_OAUTH_CLIENT_ID="<your_openai_client_id>"
```
