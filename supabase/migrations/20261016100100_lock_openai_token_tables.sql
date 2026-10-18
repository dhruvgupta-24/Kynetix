-- Lock the ChatGPT token tables to the service role.
--
-- user_openai_links holds access/refresh/id tokens. The policy
-- "Users can view own link" let the app read them directly. The app never
-- queries this table (kynetix_ui/lib has no from('user_openai_links')); all
-- reads go through edge functions with the service role (openai-link-status
-- returns a token-free summary). So: drop the SELECT policy and revoke all
-- table privileges from client roles. openai_device_auth_sessions already
-- has RLS with no policies; revoke its grants too (defence in depth).
--
-- No data is changed. Additive/idempotent apart from removing client access.

drop policy if exists "Users can view own link" on public.user_openai_links;

alter table public.user_openai_links enable row level security;
alter table public.openai_device_auth_sessions enable row level security;

revoke all on table public.user_openai_links from anon, authenticated;
revoke all on table public.openai_device_auth_sessions from anon, authenticated;

grant all on table public.user_openai_links to service_role;
grant all on table public.openai_device_auth_sessions to service_role;
