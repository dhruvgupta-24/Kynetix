-- Kyno reply reports (Google Play generative AI policy: users can flag
-- offensive or wrong AI output in the app).
--
-- Clients may only insert their own rows. There is no select, update or
-- delete policy, so reports are readable only with the service role.
-- Rows go with the user on account deletion (FK cascade, and the
-- delete-account function lists the table too).

create table if not exists public.kyno_reports (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  reason     text not null check (reason in ('harmful', 'unsafe', 'other')),
  note       text check (note is null or char_length(note) <= 500),
  message    text not null check (char_length(message) between 1 and 4000),
  prompt     text check (prompt is null or char_length(prompt) <= 2000)
);

create index if not exists kyno_reports_user_id_idx  on public.kyno_reports (user_id);
create index if not exists kyno_reports_created_idx on public.kyno_reports (created_at desc);

alter table public.kyno_reports enable row level security;

drop policy if exists "Users can report Kyno replies" on public.kyno_reports;
create policy "Users can report Kyno replies"
  on public.kyno_reports
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));

revoke all on table public.kyno_reports from anon;
revoke all on table public.kyno_reports from authenticated;
grant insert on table public.kyno_reports to authenticated;
grant all on table public.kyno_reports to service_role;
