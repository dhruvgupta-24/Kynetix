-- Photos on feedback ("Talk to us").
--
-- A user can attach up to three screenshots or photos to a feedback row.
-- Files live in the private feedback-photos bucket under <user id>/<file>.
-- Users may only upload into their own folder and can never read anything
-- back (same as the feedback rows themselves). Curators read every file.
-- The delete-account function empties the user's folder.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('feedback-photos', 'feedback-photos', false, 3145728, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "feedback_photos_own_insert" on storage.objects;
create policy "feedback_photos_own_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'feedback-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);

drop policy if exists "feedback_photos_curator_select" on storage.objects;
create policy "feedback_photos_curator_select" on storage.objects for select to authenticated
  using (bucket_id = 'feedback-photos'
         and exists (select 1 from public.app_curators c where c.user_id = (select auth.uid())));

-- Object paths inside the bucket, at most three.
alter table public.feedback
  add column if not exists photos text[] not null default '{}';

alter table public.feedback drop constraint if exists feedback_photos_max;
alter table public.feedback
  add constraint feedback_photos_max check (cardinality(photos) <= 3);

-- A row may only point at files in the sender's own folder.
drop policy if exists "Users can send feedback" on public.feedback;
create policy "Users can send feedback"
  on public.feedback
  for insert
  to authenticated
  with check (
    user_id = (select auth.uid())
    and not exists (
      select 1 from unnest(photos) as p(path)
      where split_part(p.path, '/', 1) <> (select auth.uid())::text
         or p.path like '%..%'
         or char_length(p.path) > 200
    )
  );
