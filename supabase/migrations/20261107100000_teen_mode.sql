-- Teen mode (13 to 17): a parent or guardian's OK before a minor's data is
-- processed (DPDP Act 2023 s.9 and Rule 10), recorded per account.
--
-- One row per teen account. The app never writes here: the guardian-consent
-- edge function (service role) creates the request and records the parent's
-- answer. The teen can read their own row's status, never the token hash.
--
-- child_dob is fixed at the first request, so changing the birthday in the
-- app later cannot lift teen mode on the server (AI stays off until the real
-- 18th birthday).

create table if not exists public.guardian_consents (
  user_id           uuid primary key references auth.users (id) on delete cascade,
  child_dob         date not null,
  child_first_name  text check (char_length(child_first_name) <= 40),
  token_hash        text not null unique,
  status            text not null default 'pending'
                    check (status in ('pending', 'approved', 'declined', 'revoked')),
  parent_name       text check (char_length(parent_name) <= 80),
  parent_birth_year integer check (parent_birth_year between 1900 and 2100),
  relation          text check (relation in ('mother', 'father', 'guardian')),
  requested_at      timestamptz not null default now(),
  expires_at        timestamptz not null default (now() + interval '7 days'),
  decided_at        timestamptz
);

comment on table public.guardian_consents is
  'Parental consent for teen accounts (13 to 17). Written only by the guardian-consent edge function.';
comment on column public.guardian_consents.token_hash is
  'SHA-256 (hex) of the link token the parent opens. The token itself is never stored.';

alter table public.guardian_consents enable row level security;

revoke all on public.guardian_consents from public, anon, authenticated;
grant select (user_id, child_dob, child_first_name, status, parent_name, relation,
              requested_at, expires_at, decided_at)
  on public.guardian_consents to authenticated;

drop policy if exists guardian_consents_own_read on public.guardian_consents;
create policy guardian_consents_own_read on public.guardian_consents
  for select to authenticated
  using (user_id = (select auth.uid()));
