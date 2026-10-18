-- Sign in with ChatGPT (plan usage) support for user_openai_links.
--
-- OWNER APPLIES THIS MIGRATION (SQL editor or `supabase db push`) BEFORE
-- deploying openai-link-siwc. Agents did not run it. It is additive and
-- idempotent; existing device-code links keep working unchanged
-- (auth_method defaults to 'codex_device').
--
-- Tokens stay server-side in this table (service role only), as before.

alter table public.user_openai_links
  add column if not exists auth_method        text not null default 'codex_device',
  add column if not exists oauth_client_id    text,         -- issued oaiapp_… id (not a secret); reused on re-sign-in
  add column if not exists granted_scopes     text,         -- space-separated; must include chatgpt.tokens.use.direct
  add column if not exists openai_subject     text,         -- verified ID-token `sub`
  add column if not exists ext_agent_host_id  text,         -- stable per-device host id sent at sign-in
  add column if not exists plan_paused_until  timestamptz,  -- bounded pause after usage-limit / usage-unavailable
  add column if not exists refresh_lock_until timestamptz;  -- serializes rotating-refresh-token refreshes

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'user_openai_links_auth_method_check'
  ) then
    alter table public.user_openai_links
      add constraint user_openai_links_auth_method_check
      check (auth_method in ('codex_device', 'siwc'));
  end if;
end $$;

comment on column public.user_openai_links.auth_method is
  'codex_device = Codex device-code link (chatgpt.com backend); siwc = Sign in with ChatGPT plan usage (api.openai.com/v1/responses).';
