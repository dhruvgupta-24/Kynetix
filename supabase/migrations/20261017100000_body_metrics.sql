-- Body metrics: daily water and manual weigh-ins, one row per user per day.
-- Owner-only RLS; deleted with the account (delete-account/plan.ts).

create table if not exists public.body_metrics (
  user_id    uuid        not null references auth.users (id) on delete cascade,
  date_key   text        not null check (date_key ~ '^\d{4}-\d{2}-\d{2}$'),
  water_ml   integer     not null default 0 check (water_ml between 0 and 20000),
  weight_kg  numeric(5,2)         check (weight_kg is null or weight_kg between 20 and 400),
  updated_at timestamptz not null default now(),
  primary key (user_id, date_key)
);

alter table public.body_metrics enable row level security;

drop policy if exists "body_metrics owner select" on public.body_metrics;
drop policy if exists "body_metrics owner insert" on public.body_metrics;
drop policy if exists "body_metrics owner update" on public.body_metrics;
drop policy if exists "body_metrics owner delete" on public.body_metrics;

create policy "body_metrics owner select" on public.body_metrics
  for select to authenticated using (auth.uid() = user_id);
create policy "body_metrics owner insert" on public.body_metrics
  for insert to authenticated with check (auth.uid() = user_id);
create policy "body_metrics owner update" on public.body_metrics
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "body_metrics owner delete" on public.body_metrics
  for delete to authenticated using (auth.uid() = user_id);

revoke all on public.body_metrics from anon;
