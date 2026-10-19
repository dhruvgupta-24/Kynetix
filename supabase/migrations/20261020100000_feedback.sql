-- In-app feedback ("Talk to us") and an owner inbox.
--
-- Any signed-in user may insert their own feedback rows. Curators (rows in
-- public.app_curators; the owner is one) may read every row and change its
-- status. Nobody else can read anything back, including their own rows.
-- Rows go with the user on account deletion (FK cascade, and the
-- delete-account function lists the table too).
--
-- Kyno reports join the same inbox: curators can now read them and mark
-- them read or done through a new status column.

create table if not exists public.feedback (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now(),
  kind        text not null check (kind in ('idea', 'bug', 'love', 'other')),
  message     text not null check (char_length(message) between 1 and 2000),
  reply_to    text check (reply_to is null or char_length(reply_to) <= 320),
  app_version text check (app_version is null or char_length(app_version) <= 40),
  platform    text check (platform is null or char_length(platform) <= 60),
  status      text not null default 'new' check (status in ('new', 'read', 'done'))
);

create index if not exists feedback_user_id_idx on public.feedback (user_id);
create index if not exists feedback_created_idx on public.feedback (created_at desc);
create index if not exists feedback_status_idx  on public.feedback (status);

alter table public.feedback enable row level security;

drop policy if exists "Users can send feedback" on public.feedback;
create policy "Users can send feedback"
  on public.feedback
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists "Curators can read feedback" on public.feedback;
create policy "Curators can read feedback"
  on public.feedback
  for select
  to authenticated
  using (exists (select 1 from public.app_curators c where c.user_id = (select auth.uid())));

drop policy if exists "Curators can update feedback" on public.feedback;
create policy "Curators can update feedback"
  on public.feedback
  for update
  to authenticated
  using (exists (select 1 from public.app_curators c where c.user_id = (select auth.uid())))
  with check (exists (select 1 from public.app_curators c where c.user_id = (select auth.uid())));

revoke all on table public.feedback from anon;
revoke all on table public.feedback from authenticated;
grant insert, select on table public.feedback to authenticated;
grant update (status) on table public.feedback to authenticated;
grant all on table public.feedback to service_role;

-- ── Kyno reports in the inbox ────────────────────────────────────────────────

alter table public.kyno_reports
  add column if not exists status text not null default 'new'
  check (status in ('new', 'read', 'done'));

create index if not exists kyno_reports_status_idx on public.kyno_reports (status);

drop policy if exists "Curators can read Kyno reports" on public.kyno_reports;
create policy "Curators can read Kyno reports"
  on public.kyno_reports
  for select
  to authenticated
  using (exists (select 1 from public.app_curators c where c.user_id = (select auth.uid())));

drop policy if exists "Curators can update Kyno reports" on public.kyno_reports;
create policy "Curators can update Kyno reports"
  on public.kyno_reports
  for update
  to authenticated
  using (exists (select 1 from public.app_curators c where c.user_id = (select auth.uid())))
  with check (exists (select 1 from public.app_curators c where c.user_id = (select auth.uid())));

-- Non-curators match no select or update policy, so these grants give them
-- nothing.
grant select on table public.kyno_reports to authenticated;
grant update (status) on table public.kyno_reports to authenticated;
