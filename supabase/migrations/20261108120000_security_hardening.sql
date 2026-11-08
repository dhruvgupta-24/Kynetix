-- Security hardening after the November 2026 audit.
--
-- 1. Storage paths are exact: an avatar is only <uid>/avatar.jpg, and a
--    feedback photo is one file directly in <uid>/ (no sub-folders), with a
--    rolling cap of 15 uploads per user per 24 hours so one account cannot
--    fill the bucket.
-- 2. Feedback and Kyno reports: senders may only fill the content columns,
--    never status (a sender could otherwise file a row as already 'done' and
--    hide it from the curator inbox).
-- 3. A minor's birthday cannot be edited into an adult one. The server keeps
--    the old birthday/age instead of raising, so the rest of the profile still
--    syncs. Teens still turn 18 on their real birthday because the check is
--    on the date, not on the stored age.

-- ── 1. Storage ───────────────────────────────────────────────────────────────

drop policy if exists "avatars_own_insert" on storage.objects;
create policy "avatars_own_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and name = (select auth.uid())::text || '/avatar.jpg');

drop policy if exists "avatars_own_update" on storage.objects;
create policy "avatars_own_update" on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'avatars' and name = (select auth.uid())::text || '/avatar.jpg');

-- Counts the caller's recent feedback photos. SECURITY DEFINER because users
-- cannot select from the bucket (only curators can).
create or replace function public.feedback_photo_uploads_24h()
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::integer
    from storage.objects o
   where o.bucket_id = 'feedback-photos'
     and (storage.foldername(o.name))[1] = (select auth.uid())::text
     and o.created_at > now() - interval '24 hours';
$$;
revoke all on function public.feedback_photo_uploads_24h() from public, anon;
grant execute on function public.feedback_photo_uploads_24h() to authenticated;

drop policy if exists "feedback_photos_own_insert" on storage.objects;
create policy "feedback_photos_own_insert" on storage.objects for insert to authenticated
  with check (
    bucket_id = 'feedback-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and array_length(storage.foldername(name), 1) = 1
    and position('..' in name) = 0
    and char_length(name) <= 200
    and public.feedback_photo_uploads_24h() < 15
  );

-- ── 2. Column-level insert grants ────────────────────────────────────────────

revoke insert on table public.feedback from authenticated;
grant insert (kind, message, reply_to, app_version, platform, photos)
  on table public.feedback to authenticated;

revoke insert on table public.kyno_reports from authenticated;
grant insert (reason, note, message, prompt)
  on table public.kyno_reports to authenticated;

-- ── 3. Birthday lock for minors ──────────────────────────────────────────────

-- Whole years old today (India date) from a 'YYYY-MM-DD' birthday; null when
-- the birthday is missing or malformed.
create or replace function public.years_old_ist(dob text)
returns integer
language plpgsql
stable
set search_path = ''
as $$
declare
  d date;
begin
  if dob is null or dob !~ '^\d{4}-\d{2}-\d{2}' then
    return null;
  end if;
  begin
    d := left(dob, 10)::date;
  exception when others then
    return null;
  end;
  return extract(year from age((now() at time zone 'Asia/Kolkata')::date, d))::integer;
end;
$$;

create or replace function public.profiles_pin_minor_birthday()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  old_dob text := old.profile_json ->> 'dateOfBirth';
  new_dob text := new.profile_json ->> 'dateOfBirth';
  old_years integer := coalesce(public.years_old_ist(old_dob), old.age);
  new_years integer := coalesce(public.years_old_ist(new_dob), new.age);
begin
  -- Only signed-in users editing their own row; the service role (support,
  -- migrations) can still correct a birthday.
  if coalesce((select auth.role()), '') <> 'authenticated' then
    return new;
  end if;
  if old_years is not null and old_years < 18 and (new_years is null or new_years >= 18) then
    new.age := old.age;
    if old_dob is not null then
      new.profile_json := jsonb_set(coalesce(new.profile_json, '{}'::jsonb), '{dateOfBirth}', to_jsonb(old_dob));
    elsif new.profile_json ? 'dateOfBirth' then
      new.profile_json := new.profile_json - 'dateOfBirth';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function public.profiles_pin_minor_birthday() from public, anon, authenticated;

drop trigger if exists profiles_pin_minor_birthday on public.profiles;
create trigger profiles_pin_minor_birthday
  before update on public.profiles
  for each row execute function public.profiles_pin_minor_birthday();
