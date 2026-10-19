-- In-house product analytics. No third-party SDK: the app writes small usage
-- events (names plus numbers and enums, never meal or message text) into
-- public.app_events, and curators read aggregates through the functions
-- below.
--
-- Clients may only insert their own rows. Curators (public.app_curators; the
-- owner is one) may read every row. Nobody updates or deletes through the
-- API. Rows go with the user on account deletion (FK cascade, and the
-- delete-account function lists the table too).
--
-- Days are UTC days.

create table if not exists public.app_events (
  id          bigint generated always as identity primary key,
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now(),
  session_id  uuid,
  name        text not null check (name ~ '^[a-z][a-z0-9_]{1,48}$'),
  props       jsonb not null default '{}'::jsonb check (pg_column_size(props) <= 2048),
  app_version text check (app_version is null or char_length(app_version) <= 40),
  platform    text check (platform is null or char_length(platform) <= 60)
);

create index if not exists app_events_created_idx      on public.app_events (created_at desc);
create index if not exists app_events_user_created_idx on public.app_events (user_id, created_at desc);
create index if not exists app_events_name_created_idx on public.app_events (name, created_at desc);

alter table public.app_events enable row level security;

drop policy if exists "Users can log their own events" on public.app_events;
create policy "Users can log their own events"
  on public.app_events
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists "Curators can read events" on public.app_events;
create policy "Curators can read events"
  on public.app_events
  for select
  to authenticated
  using (exists (select 1 from public.app_curators c where c.user_id = (select auth.uid())));

revoke all on table public.app_events from anon;
revoke all on table public.app_events from authenticated;
grant insert, select on table public.app_events to authenticated;
grant all on table public.app_events to service_role;

-- ── Curator guard ────────────────────────────────────────────────────────────

create or replace function public.analytics_assert_curator()
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.app_curators c where c.user_id = auth.uid()) then
    raise exception 'curators only' using errcode = '42501';
  end if;
end;
$$;

-- ── Overview: DAU / WAU / MAU, totals, and a per-day series ─────────────────

create or replace function public.analytics_overview(days int default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  n int := least(greatest(coalesce(days, 30), 1), 365);
  today date := (now() at time zone 'utc')::date;
begin
  perform public.analytics_assert_curator();
  return jsonb_build_object(
    'total_users',  (select count(*) from auth.users),
    'dau',          (select count(distinct e.user_id) from public.app_events e where e.created_at >= now() - interval '1 day'),
    'wau',          (select count(distinct e.user_id) from public.app_events e where e.created_at >= now() - interval '7 days'),
    'mau',          (select count(distinct e.user_id) from public.app_events e where e.created_at >= now() - interval '30 days'),
    'active_today', (select count(distinct e.user_id) from public.app_events e where e.created_at >= today::timestamptz),
    'new_today',    (select count(*) from auth.users u where u.created_at >= today::timestamptz),
    'series', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'day',          g.day::date,
               'new_users',    coalesce(s.cnt, 0),
               'active_users', coalesce(a.cnt, 0)
             ) order by g.day), '[]'::jsonb)
      from generate_series(today - (n - 1), today, interval '1 day') as g(day)
      left join (
        select (u.created_at at time zone 'utc')::date as day, count(*) as cnt
        from auth.users u
        where u.created_at >= (today - (n - 1))::timestamptz
        group by 1
      ) s on s.day = g.day::date
      left join (
        select (e.created_at at time zone 'utc')::date as day, count(distinct e.user_id) as cnt
        from public.app_events e
        where e.created_at >= (today - (n - 1))::timestamptz
        group by 1
      ) a on a.day = g.day::date
    )
  );
end;
$$;

-- ── Retention: weekly signup cohorts ────────────────────────────────────────
-- Dn = share of the cohort that used the app on or after day n since signup,
-- among users signed up at least n days ago (null when none are yet).

create or replace function public.analytics_retention()
returns table (cohort_week date, users int, d1 numeric, d7 numeric, d30 numeric)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.analytics_assert_curator();
  return query
  with cohort as (
    select u.id,
           u.created_at,
           date_trunc('week', u.created_at at time zone 'utc')::date as week
    from auth.users u
    where u.created_at >= date_trunc('week', now() at time zone 'utc') - interval '11 weeks'
  ),
  flags as (
    select c.week,
           c.created_at,
           exists (select 1 from public.app_events e where e.user_id = c.id and e.created_at >= c.created_at + interval '1 day')   as r1,
           exists (select 1 from public.app_events e where e.user_id = c.id and e.created_at >= c.created_at + interval '7 days')  as r7,
           exists (select 1 from public.app_events e where e.user_id = c.id and e.created_at >= c.created_at + interval '30 days') as r30
    from cohort c
  )
  select f.week,
         count(*)::int,
         round(100.0 * count(*) filter (where f.r1)  / nullif(count(*) filter (where f.created_at <= now() - interval '1 day'), 0), 1),
         round(100.0 * count(*) filter (where f.r7)  / nullif(count(*) filter (where f.created_at <= now() - interval '7 days'), 0), 1),
         round(100.0 * count(*) filter (where f.r30) / nullif(count(*) filter (where f.created_at <= now() - interval '30 days'), 0), 1)
  from flags f
  group by f.week
  order by f.week desc;
end;
$$;

-- ── Feature usage: events and unique users per event name ───────────────────

create or replace function public.analytics_feature_usage(days int default 30)
returns table (name text, events bigint, users bigint)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.analytics_assert_curator();
  return query
  select e.name, count(*), count(distinct e.user_id)
  from public.app_events e
  where e.created_at >= now() - make_interval(days => least(greatest(coalesce(days, 30), 1), 365))
  group by e.name
  order by 2 desc, 1;
end;
$$;

-- ── Users: one row each, most recently seen first ───────────────────────────
-- Counts cover the last `days` days. Last seen falls back to the last sign-in
-- for users with no events yet.

create or replace function public.analytics_user_list(days int default 30)
returns table (
  user_id           uuid,
  email             text,
  name              text,
  signed_up_at      timestamptz,
  last_seen_at      timestamptz,
  active_days       int,
  meals_logged      int,
  workouts_finished int,
  kyno_messages     int,
  share_exports     int,
  widgets_added     int,
  app_version       text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  since timestamptz := now() - make_interval(days => least(greatest(coalesce(days, 30), 1), 365));
begin
  perform public.analytics_assert_curator();
  return query
  with ev as (
    select e.user_id,
           count(distinct (e.created_at at time zone 'utc')::date)::int as active_days,
           (count(*) filter (where e.name = 'meal_logged'))::int        as meals,
           (count(*) filter (where e.name = 'workout_finished'))::int   as workouts,
           (count(*) filter (where e.name = 'kyno_message_sent'))::int  as kyno,
           (count(*) filter (where e.name = 'share_exported'))::int     as shares,
           (count(*) filter (where e.name = 'widget_pinned'))::int      as widgets
    from public.app_events e
    where e.created_at >= since
    group by e.user_id
  ),
  latest as (
    select distinct on (e.user_id) e.user_id, e.created_at, e.app_version
    from public.app_events e
    order by e.user_id, e.created_at desc
  )
  select u.id,
         u.email::text,
         p.name,
         u.created_at,
         coalesce(l.created_at, u.last_sign_in_at),
         coalesce(ev.active_days, 0),
         coalesce(ev.meals, 0),
         coalesce(ev.workouts, 0),
         coalesce(ev.kyno, 0),
         coalesce(ev.shares, 0),
         coalesce(ev.widgets, 0),
         l.app_version
  from auth.users u
  left join public.profiles p on p.id = u.id
  left join ev on ev.user_id = u.id
  left join latest l on l.user_id = u.id
  order by coalesce(l.created_at, u.last_sign_in_at) desc nulls last;
end;
$$;

-- ── One user's recent events ────────────────────────────────────────────────

create or replace function public.analytics_user_timeline(uid uuid, max_rows int default 100)
returns table (
  created_at  timestamptz,
  name        text,
  props       jsonb,
  session_id  uuid,
  app_version text,
  platform    text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.analytics_assert_curator();
  return query
  select e.created_at, e.name, e.props, e.session_id, e.app_version, e.platform
  from public.app_events e
  where e.user_id = uid
  order by e.created_at desc
  limit least(greatest(coalesce(max_rows, 100), 1), 500);
end;
$$;

revoke execute on function public.analytics_assert_curator()             from public, anon;
revoke execute on function public.analytics_overview(int)                from public, anon;
revoke execute on function public.analytics_retention()                  from public, anon;
revoke execute on function public.analytics_feature_usage(int)           from public, anon;
revoke execute on function public.analytics_user_list(int)               from public, anon;
revoke execute on function public.analytics_user_timeline(uuid, int)     from public, anon;
grant execute on function public.analytics_assert_curator()              to authenticated;
grant execute on function public.analytics_overview(int)                 to authenticated;
grant execute on function public.analytics_retention()                   to authenticated;
grant execute on function public.analytics_feature_usage(int)            to authenticated;
grant execute on function public.analytics_user_list(int)                to authenticated;
grant execute on function public.analytics_user_timeline(uuid, int)      to authenticated;
