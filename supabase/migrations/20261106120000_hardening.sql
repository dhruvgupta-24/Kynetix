-- Backend hardening (audit 2026-11-06).
--
--  1. Global AI budget + kill switch. public.system_flags (service role only)
--     holds ai_disabled and optional global limit overrides.
--     public.ai_usage_consume_v2 checks, in one transaction under row locks:
--     kill switch, the per-user minute/day limits, the per-user daily photo
--     cap, and (for requests that will run on Kynetix's shared free-tier keys)
--     a global per-minute/per-day budget in public.ai_global_usage. Nothing is
--     counted unless every check passes, which also closes the old race where
--     the photo cap was read before ai_usage_consume incremented it.
--     public.ai_global_consume charges the global budget alone, for a
--     plan-user request that falls back to the free chain.
--     The old public.ai_usage_consume stays so the currently deployed router
--     keeps working until it is redeployed.
--  2. Per-user hourly insert limits on app_events, feedback and kyno_reports
--     (same pattern as client_errors_before_insert: over the limit the row is
--     dropped silently), JSON size caps (NOT VALID: existing rows are not
--     rechecked) and a retention function for app_events.
--  3. workout_sessions (user_id, date) index; RLS policies on the per-user
--     tables re-created with (select auth.uid()) so it is evaluated once per
--     statement instead of once per row. Semantics (commands, roles, USING /
--     WITH CHECK) are unchanged.
--  5. app_curators: users can read only their own row (the app only ever asks
--     "am I a curator?"). Curator checks in other policies still work, since
--     they only look for the caller's own row; analytics_* are SECURITY
--     DEFINER.
--  6. No EXECUTE for anon / PUBLIC on future functions by default, and an
--     explicit revoke on the existing functions clients must not call.
--
-- Idempotent: safe to run twice.

-- ═════════════════════════════════════════════════════════════════════════════
-- 1. Global AI budget + kill switch
-- ═════════════════════════════════════════════════════════════════════════════

create table if not exists public.system_flags (
  key        text primary key check (key ~ '^[a-z][a-z0-9_]{1,62}$'),
  value      jsonb not null,
  note       text check (note is null or char_length(note) <= 500),
  updated_at timestamptz not null default now()
);

comment on table public.system_flags is
  'Runtime switches read by edge functions (service role only). ai_disabled: true pauses all AI with a friendly 503. ai_global_per_minute / ai_global_per_day: optional numbers overriding the AI_GLOBAL_* env limits.';

alter table public.system_flags enable row level security;
-- Default privileges hand new tables to anon/authenticated: take that back.
revoke all on table public.system_flags from anon, authenticated, public;
grant all on table public.system_flags to service_role;

insert into public.system_flags (key, value, note)
values ('ai_disabled', 'false'::jsonb, 'Set to true to pause every AI request (router answers 503 ai_paused).')
on conflict (key) do nothing;

create table if not exists public.ai_global_usage (
  day           date primary key,
  requests      integer not null default 0,
  images        integer not null default 0,
  minute_window timestamptz,
  minute_count  integer not null default 0,
  updated_at    timestamptz not null default now()
);

comment on table public.ai_global_usage is
  'One row per UTC day: requests served on Kynetix''s shared free-tier AI keys (Gemini / Groq / OpenRouter). Service role only.';

alter table public.ai_global_usage enable row level security;
revoke all on table public.ai_global_usage from anon, authenticated, public;
grant all on table public.ai_global_usage to service_role;

-- Reads a numeric override from system_flags, else the fallback.
create or replace function public.kx_flag_int(p_key text, p_fallback integer)
returns integer
language sql
stable
security definer
set search_path to ''
as $$
  select coalesce(
    -- Nested CASE: the cast only runs on a JSON number (AND does not
    -- short-circuit in SQL).
    (select case when jsonb_typeof(f.value) = 'number' then
              case when (f.value::text)::numeric between 1 and 100000000
                   then (f.value::text)::numeric::integer end
            end
       from public.system_flags f where f.key = p_key),
    p_fallback);
$$;

create or replace function public.ai_usage_consume_v2(
  p_user_id           uuid,
  p_chars             integer,
  p_images            integer,
  p_per_minute        integer,
  p_per_day           integer,
  p_image_cap         integer default null,   -- null = no photo cap for this request
  p_count_global      boolean default true,   -- false = runs on the user's own ChatGPT plan
  p_global_per_minute integer default 30,
  p_global_per_day    integer default 1500
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_now      timestamptz := now();
  v_day      date        := (v_now at time zone 'utc')::date;
  v_window   timestamptz := date_trunc('minute', v_now);
  v_to_day   integer     := greatest(1, ceil(extract(epoch from (((v_day + 1)::timestamp at time zone 'utc') - v_now)))::int);
  v_to_min   integer     := greatest(1, ceil(extract(epoch from ((v_window + interval '1 minute') - v_now)))::int);
  v_images   integer     := greatest(coalesce(p_images, 0), 0);
  v_row      public.ai_usage%rowtype;
  v_minute   integer;
  v_g        public.ai_global_usage%rowtype;
  v_gminute  integer := 0;
  v_gmax_min integer;
  v_gmax_day integer;
begin
  if p_user_id is null then
    raise exception 'p_user_id required';
  end if;

  -- Kill switch.
  if exists (select 1 from public.system_flags f where f.key = 'ai_disabled' and f.value = 'true'::jsonb) then
    return jsonb_build_object('allowed', false, 'scope', 'disabled', 'retry_after', 300,
                              'day_requests', 0, 'minute_requests', 0);
  end if;

  -- Per user (row lock serialises this user's concurrent requests).
  insert into public.ai_usage (user_id, day) values (p_user_id, v_day)
  on conflict (user_id, day) do nothing;

  select * into v_row from public.ai_usage
   where user_id = p_user_id and day = v_day
   for update;

  v_minute := case when v_row.minute_window = v_window then v_row.minute_count else 0 end;

  if v_row.requests >= greatest(p_per_day, 1) then
    return jsonb_build_object('allowed', false, 'scope', 'day', 'retry_after', v_to_day,
                              'day_requests', v_row.requests, 'minute_requests', v_minute);
  end if;
  if v_minute >= greatest(p_per_minute, 1) then
    return jsonb_build_object('allowed', false, 'scope', 'minute', 'retry_after', v_to_min,
                              'day_requests', v_row.requests, 'minute_requests', v_minute);
  end if;
  if p_image_cap is not null and v_images > 0 and v_row.images + v_images > greatest(p_image_cap, 0) then
    return jsonb_build_object('allowed', false, 'scope', 'images', 'retry_after', v_to_day,
                              'day_requests', v_row.requests, 'minute_requests', v_minute,
                              'images_today', v_row.images);
  end if;

  -- Global budget for the shared free-tier keys. Always locked after the
  -- user row (same order everywhere, so no deadlocks).
  if coalesce(p_count_global, true) then
    v_gmax_min := public.kx_flag_int('ai_global_per_minute', greatest(coalesce(p_global_per_minute, 30), 1));
    v_gmax_day := public.kx_flag_int('ai_global_per_day',    greatest(coalesce(p_global_per_day, 1500), 1));

    insert into public.ai_global_usage (day) values (v_day)
    on conflict (day) do nothing;

    select * into v_g from public.ai_global_usage where day = v_day for update;
    v_gminute := case when v_g.minute_window = v_window then v_g.minute_count else 0 end;

    if v_g.requests >= v_gmax_day then
      return jsonb_build_object('allowed', false, 'scope', 'global_day', 'retry_after', v_to_day,
                                'day_requests', v_row.requests, 'minute_requests', v_minute);
    end if;
    if v_gminute >= v_gmax_min then
      return jsonb_build_object('allowed', false, 'scope', 'global_minute', 'retry_after', v_to_min,
                                'day_requests', v_row.requests, 'minute_requests', v_minute);
    end if;

    update public.ai_global_usage
       set requests      = requests + 1,
           images        = images + v_images,
           minute_window = v_window,
           minute_count  = v_gminute + 1,
           updated_at    = v_now
     where day = v_day;
  end if;

  update public.ai_usage
     set requests      = requests + 1,
         chars         = chars + greatest(coalesce(p_chars, 0), 0),
         images        = images + v_images,
         minute_window = v_window,
         minute_count  = v_minute + 1,
         updated_at    = v_now
   where user_id = p_user_id and day = v_day;

  return jsonb_build_object(
    'allowed', true,
    'day_requests', v_row.requests + 1,
    'minute_requests', v_minute + 1,
    'images_today', v_row.images + v_images,
    'global_counted', coalesce(p_count_global, true));
end;
$$;

-- Global budget only: a plan-tier request (already counted per user by
-- ai_usage_consume_v2 with p_count_global = false) that falls back to the
-- shared free-tier chain.
create or replace function public.ai_global_consume(
  p_images            integer default 0,
  p_global_per_minute integer default 30,
  p_global_per_day    integer default 1500
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_now      timestamptz := now();
  v_day      date        := (v_now at time zone 'utc')::date;
  v_window   timestamptz := date_trunc('minute', v_now);
  v_g        public.ai_global_usage%rowtype;
  v_gminute  integer;
  v_gmax_min integer := public.kx_flag_int('ai_global_per_minute', greatest(coalesce(p_global_per_minute, 30), 1));
  v_gmax_day integer := public.kx_flag_int('ai_global_per_day',    greatest(coalesce(p_global_per_day, 1500), 1));
begin
  insert into public.ai_global_usage (day) values (v_day)
  on conflict (day) do nothing;

  select * into v_g from public.ai_global_usage where day = v_day for update;
  v_gminute := case when v_g.minute_window = v_window then v_g.minute_count else 0 end;

  if v_g.requests >= v_gmax_day then
    return jsonb_build_object('allowed', false, 'scope', 'global_day',
      'retry_after', greatest(1, ceil(extract(epoch from (((v_day + 1)::timestamp at time zone 'utc') - v_now)))::int));
  end if;
  if v_gminute >= v_gmax_min then
    return jsonb_build_object('allowed', false, 'scope', 'global_minute',
      'retry_after', greatest(1, ceil(extract(epoch from ((v_window + interval '1 minute') - v_now)))::int));
  end if;

  update public.ai_global_usage
     set requests      = requests + 1,
         images        = images + greatest(coalesce(p_images, 0), 0),
         minute_window = v_window,
         minute_count  = v_gminute + 1,
         updated_at    = v_now
   where day = v_day;

  return jsonb_build_object('allowed', true);
end;
$$;

revoke all on function public.kx_flag_int(text, integer) from public, anon, authenticated;
revoke all on function public.ai_usage_consume_v2(uuid, integer, integer, integer, integer, integer, boolean, integer, integer) from public, anon, authenticated;
revoke all on function public.ai_global_consume(integer, integer, integer) from public, anon, authenticated;
grant execute on function public.kx_flag_int(text, integer) to service_role;
grant execute on function public.ai_usage_consume_v2(uuid, integer, integer, integer, integer, integer, boolean, integer, integer) to service_role;
grant execute on function public.ai_global_consume(integer, integer, integer) to service_role;

-- ═════════════════════════════════════════════════════════════════════════════
-- 2. Insert rate limits, JSON size caps, retention
-- ═════════════════════════════════════════════════════════════════════════════

create table if not exists public.user_insert_rate (
  user_id     uuid not null references auth.users (id) on delete cascade,
  bucket      text not null,
  hour_window timestamptz not null,
  inserts     integer not null default 0,
  primary key (user_id, bucket, hour_window)
);

comment on table public.user_insert_rate is
  'Per-user hourly insert counters for app_events / feedback / kyno_reports (see user_insert_rate_guard). Service role only.';

alter table public.user_insert_rate enable row level security;
revoke all on table public.user_insert_rate from anon, authenticated, public;
grant all on table public.user_insert_rate to service_role;

-- BEFORE INSERT trigger. TG_ARGV[0] = hourly limit per user. Over the limit
-- the row is dropped silently (same as client_errors_before_insert), so the
-- app never sees an error. Service-role inserts (no JWT user) are not
-- limited. created_at stays client-supplied (analytics queues events and
-- sends their real time) but is clamped to [now - 7 days, now], so rows
-- cannot be back-dated past retention or dated in the future.
create or replace function public.user_insert_rate_guard()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_uid    uuid        := auth.uid();
  v_window timestamptz := date_trunc('hour', now());
  v_limit  integer     := coalesce(nullif(TG_ARGV[0], '')::integer, 60);
  v_count  integer;
begin
  new.created_at := least(greatest(coalesce(new.created_at, now()), now() - interval '7 days'), now());

  if v_uid is null then
    return new;
  end if;

  insert into public.user_insert_rate as r (user_id, bucket, hour_window, inserts)
  values (v_uid, TG_TABLE_NAME, v_window, 1)
  on conflict (user_id, bucket, hour_window)
  do update set inserts = r.inserts + 1
  returning r.inserts into v_count;

  if v_count > v_limit then
    return null; -- drop silently
  end if;

  -- Opportunistic cleanup of this user's old windows (first insert per hour).
  if v_count = 1 then
    delete from public.user_insert_rate
     where user_id = v_uid and bucket = TG_TABLE_NAME and hour_window < v_window - interval '1 day';
  end if;

  return new;
end;
$$;

revoke all on function public.user_insert_rate_guard() from public, anon, authenticated;
grant execute on function public.user_insert_rate_guard() to service_role;

-- Analytics flushes batches of <= 20 events every 30 s while the app is in
-- use (a busy hour is ~100-200 events); 600 leaves wide headroom.
drop trigger if exists app_events_rate_limit on public.app_events;
create trigger app_events_rate_limit
  before insert on public.app_events
  for each row execute function public.user_insert_rate_guard('600');

drop trigger if exists feedback_rate_limit on public.feedback;
create trigger feedback_rate_limit
  before insert on public.feedback
  for each row execute function public.user_insert_rate_guard('20');

drop trigger if exists kyno_reports_rate_limit on public.kyno_reports;
create trigger kyno_reports_rate_limit
  before insert on public.kyno_reports
  for each row execute function public.user_insert_rate_guard('30');

-- JSON size caps. Measured: a heavy real user's largest day (16 meals logged
-- with full item breakdowns) is ~17 KB of sections_json; profile_json is
-- under 1 KB plus target history. Caps are 10x-30x that. NOT VALID: existing
-- rows are not checked (an existing oversized row only fails when it is next
-- written). Run `alter table ... validate constraint ...` later if wanted.
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'day_logs_sections_json_size') then
    alter table public.day_logs
      add constraint day_logs_sections_json_size
      check (sections_json is null or pg_column_size(sections_json) <= 524288) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'day_logs_deleted_meal_ids_size') then
    alter table public.day_logs
      add constraint day_logs_deleted_meal_ids_size
      check (pg_column_size(deleted_meal_ids) <= 262144) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'day_logs_gym_day_json_size') then
    alter table public.day_logs
      add constraint day_logs_gym_day_json_size
      check (gym_day_json is null or pg_column_size(gym_day_json) <= 262144) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'workout_sessions_entries_json_size') then
    alter table public.workout_sessions
      add constraint workout_sessions_entries_json_size
      check (entries_json is null or pg_column_size(entries_json) <= 1048576) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'profiles_profile_json_size') then
    alter table public.profiles
      add constraint profiles_profile_json_size
      check (profile_json is null or pg_column_size(profile_json) <= 262144) not valid;
  end if;
end;
$$;

-- Retention: deletes app_events older than [keep_days] (min 30), in batches
-- so one call never holds a long lock. Returns rows deleted. Service role
-- only. pg_cron is not used by any migration in this project, so this is not
-- scheduled here. To schedule once pg_cron is enabled:
--   select cron.schedule('app-events-retention', '17 3 * * *',
--                        $c$select public.app_events_purge_old(180)$c$);
create or replace function public.app_events_purge_old(keep_days integer default 180, batch_size integer default 50000)
returns bigint
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_cutoff timestamptz := now() - make_interval(days => greatest(coalesce(keep_days, 180), 30));
  v_batch  integer     := least(greatest(coalesce(batch_size, 50000), 1000), 200000);
  v_total  bigint      := 0;
  v_n      bigint;
begin
  loop
    delete from public.app_events
     where id in (select id from public.app_events where created_at < v_cutoff limit v_batch);
    get diagnostics v_n = row_count;
    v_total := v_total + v_n;
    exit when v_n < v_batch;
  end loop;
  return v_total;
end;
$$;

revoke all on function public.app_events_purge_old(integer, integer) from public, anon, authenticated;
grant execute on function public.app_events_purge_old(integer, integer) to service_role;

-- ═════════════════════════════════════════════════════════════════════════════
-- 3. Index + RLS policies with (select auth.uid())
-- ═════════════════════════════════════════════════════════════════════════════

create index if not exists workout_sessions_user_date_idx
  on public.workout_sessions (user_id, date desc);

-- day_logs (no TO clause = all roles, as in the baseline)
drop policy if exists "Users can view their own day logs"   on public.day_logs;
drop policy if exists "Users can insert their own day logs" on public.day_logs;
drop policy if exists "Users can update their own day logs" on public.day_logs;
drop policy if exists "Users can delete their own day logs" on public.day_logs;
create policy "Users can view their own day logs"   on public.day_logs for select using ((select auth.uid()) = user_id);
create policy "Users can insert their own day logs" on public.day_logs for insert with check ((select auth.uid()) = user_id);
create policy "Users can update their own day logs" on public.day_logs for update using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "Users can delete their own day logs" on public.day_logs for delete using ((select auth.uid()) = user_id);

-- workout_sessions
drop policy if exists "Users can view their own workouts"   on public.workout_sessions;
drop policy if exists "Users can insert their own workouts" on public.workout_sessions;
drop policy if exists "Users can update their own workouts" on public.workout_sessions;
drop policy if exists "Users can delete their own workouts" on public.workout_sessions;
create policy "Users can view their own workouts"   on public.workout_sessions for select using ((select auth.uid()) = user_id);
create policy "Users can insert their own workouts" on public.workout_sessions for insert with check ((select auth.uid()) = user_id);
create policy "Users can update their own workouts" on public.workout_sessions for update using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "Users can delete their own workouts" on public.workout_sessions for delete using ((select auth.uid()) = user_id);

-- profiles (update has no WITH CHECK in the baseline; USING then also
-- applies to the new row, so semantics are kept by leaving it out)
drop policy if exists "Users can view their own profile"   on public.profiles;
drop policy if exists "Users can insert their own profile" on public.profiles;
drop policy if exists "Users can update their own profile" on public.profiles;
create policy "Users can view their own profile"   on public.profiles for select using ((select auth.uid()) = id);
create policy "Users can insert their own profile" on public.profiles for insert with check ((select auth.uid()) = id);
create policy "Users can update their own profile" on public.profiles for update using ((select auth.uid()) = id);

-- user_nutrition_memory
drop policy if exists "Users can view their own memory"   on public.user_nutrition_memory;
drop policy if exists "Users can insert their own memory" on public.user_nutrition_memory;
drop policy if exists "Users can update their own memory" on public.user_nutrition_memory;
drop policy if exists "Users can delete their own memory" on public.user_nutrition_memory;
create policy "Users can view their own memory"   on public.user_nutrition_memory for select using ((select auth.uid()) = user_id);
create policy "Users can insert their own memory" on public.user_nutrition_memory for insert with check ((select auth.uid()) = user_id);
create policy "Users can update their own memory" on public.user_nutrition_memory for update using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "Users can delete their own memory" on public.user_nutrition_memory for delete using ((select auth.uid()) = user_id);

-- user_quick_adds
drop policy if exists "Users can view their own quick adds"   on public.user_quick_adds;
drop policy if exists "Users can insert their own quick adds" on public.user_quick_adds;
drop policy if exists "Users can update their own quick adds" on public.user_quick_adds;
drop policy if exists "Users can delete their own quick adds" on public.user_quick_adds;
create policy "Users can view their own quick adds"   on public.user_quick_adds for select using ((select auth.uid()) = user_id);
create policy "Users can insert their own quick adds" on public.user_quick_adds for insert with check ((select auth.uid()) = user_id);
create policy "Users can update their own quick adds" on public.user_quick_adds for update using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "Users can delete their own quick adds" on public.user_quick_adds for delete using ((select auth.uid()) = user_id);

-- workout_splits (TO authenticated, all commands)
drop policy if exists "Users can manage their own splits" on public.workout_splits;
create policy "Users can manage their own splits" on public.workout_splits to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

-- user_eating_patterns / user_meal_contexts / user_achievements / user_insights_cache (all commands)
drop policy if exists "Users can manage own eating patterns" on public.user_eating_patterns;
create policy "Users can manage own eating patterns" on public.user_eating_patterns
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

drop policy if exists "Users can manage own meal contexts" on public.user_meal_contexts;
create policy "Users can manage own meal contexts" on public.user_meal_contexts
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

drop policy if exists "own_achievements" on public.user_achievements;
create policy "own_achievements" on public.user_achievements
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

drop policy if exists "own_insights_cache" on public.user_insights_cache;
create policy "own_insights_cache" on public.user_insights_cache
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

-- body_metrics (TO authenticated)
drop policy if exists "body_metrics owner select" on public.body_metrics;
drop policy if exists "body_metrics owner insert" on public.body_metrics;
drop policy if exists "body_metrics owner update" on public.body_metrics;
drop policy if exists "body_metrics owner delete" on public.body_metrics;
create policy "body_metrics owner select" on public.body_metrics for select to authenticated using ((select auth.uid()) = user_id);
create policy "body_metrics owner insert" on public.body_metrics for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "body_metrics owner update" on public.body_metrics for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "body_metrics owner delete" on public.body_metrics for delete to authenticated using ((select auth.uid()) = user_id);

-- global_food_defaults curator writes (TO authenticated)
drop policy if exists "Only curators can insert global food defaults" on public.global_food_defaults;
drop policy if exists "Only curators can update global food defaults" on public.global_food_defaults;
drop policy if exists "Only curators can delete global food defaults" on public.global_food_defaults;
create policy "Only curators can insert global food defaults" on public.global_food_defaults for insert to authenticated
  with check ((select auth.uid()) in (select c.user_id from public.app_curators c));
create policy "Only curators can update global food defaults" on public.global_food_defaults for update to authenticated
  using ((select auth.uid()) in (select c.user_id from public.app_curators c))
  with check ((select auth.uid()) in (select c.user_id from public.app_curators c));
create policy "Only curators can delete global food defaults" on public.global_food_defaults for delete to authenticated
  using ((select auth.uid()) in (select c.user_id from public.app_curators c));

-- ═════════════════════════════════════════════════════════════════════════════
-- 5. app_curators: own row only
-- ═════════════════════════════════════════════════════════════════════════════
-- The app's only read is FeedbackService._lookUpCurator: select user_id where
-- user_id = <me>. Curator checks in RLS policies look only for the caller's
-- own row, so they keep working. No client writes (RLS had no write policy);
-- the grants now say so too.

drop policy if exists "Curators readable by authenticated users" on public.app_curators;
drop policy if exists "Users can read their own curator row" on public.app_curators;
create policy "Users can read their own curator row" on public.app_curators for select to authenticated
  using (user_id = (select auth.uid()));

revoke all on table public.app_curators from anon;
revoke insert, update, delete, truncate, references, trigger on table public.app_curators from authenticated;
grant select on table public.app_curators to authenticated;

-- TRUNCATE, REFERENCES and TRIGGER bypass RLS and no client needs them.
-- The baseline granted ALL on most tables to anon / authenticated.
do $$
declare
  t record;
begin
  for t in
    select c.relname
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind in ('r', 'p')
  loop
    execute format('revoke truncate, references, trigger on table public.%I from anon, authenticated', t.relname);
  end loop;
end;
$$;

-- ═════════════════════════════════════════════════════════════════════════════
-- 6. Function EXECUTE privileges
-- ═════════════════════════════════════════════════════════════════════════════
-- Future functions created by postgres: no EXECUTE for anon (schema default)
-- or PUBLIC (global default, which is what Postgres grants every new
-- function). Grant per function, in its migration, to the roles that need it.

alter default privileges for role postgres in schema public revoke execute on functions from anon;
alter default privileges for role postgres revoke execute on functions from public;

-- SECURITY DEFINER functions that only the service role or a trigger may run.
revoke execute on function public.ai_usage_consume(uuid, integer, integer, integer, integer) from public, anon, authenticated;
revoke execute on function public.client_errors_before_insert()                             from public, anon, authenticated;
revoke execute on function public.handle_new_user()                                         from public, anon, authenticated;

-- Curator analytics (SECURITY DEFINER, curator-checked): signed-in users only.
revoke execute on function public.analytics_assert_curator()         from public, anon;
revoke execute on function public.analytics_overview(int)            from public, anon;
revoke execute on function public.analytics_retention()              from public, anon;
revoke execute on function public.analytics_feature_usage(int)       from public, anon;
revoke execute on function public.analytics_user_list(int)           from public, anon;
revoke execute on function public.analytics_user_timeline(uuid, int) from public, anon;

-- Not SECURITY DEFINER, but anon has no business calling them. authenticated
-- keeps its explicit grants (merge_day_log runs the kx_* helpers as the
-- caller).
revoke execute on function public.handle_updated_at()                              from public, anon;
revoke execute on function public.kx_meal_entry_id(jsonb)                          from public, anon;
revoke execute on function public.kx_try_timestamptz(text)                         from public, anon;
revoke execute on function public.kx_merge_meal_sections(jsonb, jsonb, jsonb, jsonb) from public, anon;
revoke execute on function public.merge_day_log(text, jsonb, jsonb, jsonb, double precision, double precision) from public, anon;
grant execute on function public.kx_meal_entry_id(jsonb)                           to authenticated, service_role;
grant execute on function public.kx_try_timestamptz(text)                          to authenticated, service_role;
grant execute on function public.kx_merge_meal_sections(jsonb, jsonb, jsonb, jsonb) to authenticated, service_role;
grant execute on function public.merge_day_log(text, jsonb, jsonb, jsonb, double precision, double precision) to authenticated, service_role;
