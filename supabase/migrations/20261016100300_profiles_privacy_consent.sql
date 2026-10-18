-- Consent + age confirmation fields on profiles. Additive, nullable,
-- idempotent; existing rows are untouched (all values start NULL).
-- Covered by the existing profiles RLS (users read/insert/update their own row).

alter table public.profiles
  add column if not exists privacy_consent_at      timestamptz,
  add column if not exists privacy_policy_version  text,
  add column if not exists age_confirmed_adult     boolean;

comment on column public.profiles.privacy_consent_at is
  'When the user accepted the privacy policy (null = not recorded).';
comment on column public.profiles.privacy_policy_version is
  'Version string of the privacy policy the user accepted.';
comment on column public.profiles.age_confirmed_adult is
  'User confirmed they are 18+ (null = not asked yet).';
