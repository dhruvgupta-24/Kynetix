-- Full profile backup.
--
-- The app's profile has many fields with no column (custom targets, target
-- change history, step data, ...), so a reinstall or second device lost them.
-- profile_json holds the app's whole UserProfile.toJson(); the app prefers it
-- on restore and falls back to the existing columns for rows without it.
--
-- height_cm was integer, truncating e.g. 175.5 cm. integer -> numeric is a
-- lossless widening (every stored value is kept exactly). Readers already
-- parse it as a number (app: num, ai-meal-coach: parseFloat).
--
-- Additive: no row or existing value is removed. Covered by the existing
-- profiles RLS (users read/insert/update only their own row).

alter table public.profiles
  add column if not exists profile_json       jsonb,
  add column if not exists profile_updated_at timestamptz;

do $$
begin
  if exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'profiles'
       and column_name = 'height_cm' and data_type = 'integer'
  ) then
    alter table public.profiles
      alter column height_cm type numeric using height_cm::numeric;
  end if;
end;
$$;

comment on column public.profiles.profile_json is
  'Full app UserProfile JSON (custom targets, target history, steps, ...). Preferred over the individual columns on restore.';
comment on column public.profiles.profile_updated_at is
  'When profile_json was last written by the app.';
