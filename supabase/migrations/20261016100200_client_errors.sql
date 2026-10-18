-- In-house client error reporting (no Sentry/Crashlytics).
--
-- The app inserts directly with the signed-in user's session:
--   supabase.from('client_errors').insert({
--     user_id: <auth uid or null>, app_version, platform, error_type, message, stack
--   })
-- (no .select() — clients cannot read this table).
--
-- Guarantees:
--   * Insert only, authenticated only; user_id must be null or auth.uid().
--   * No select/update/delete for client roles.
--   * Lengths are truncated server-side (message 2000, stack 8000, ...).
--   * Rate limit: 30 reports per user per hour; extra reports are dropped
--     silently (the insert succeeds with no row) so a crash loop cannot
--     flood the table or surface new errors in the app.
--   * id / created_at are server-set.
-- Additive and idempotent.

create table if not exists public.client_errors (
  id           uuid        primary key default gen_random_uuid(),
  user_id      uuid        references auth.users(id) on delete cascade,
  app_version  text,
  platform     text,
  error_type   text,
  message      text,
  stack        text,
  created_at   timestamptz not null default now(),
  constraint client_errors_message_len  check (message is null or char_length(message) <= 2000),
  constraint client_errors_stack_len    check (stack is null or char_length(stack) <= 8000),
  constraint client_errors_type_len     check (error_type is null or char_length(error_type) <= 120),
  constraint client_errors_version_len  check (app_version is null or char_length(app_version) <= 40),
  constraint client_errors_platform_len check (platform is null or char_length(platform) <= 40)
);

create index if not exists client_errors_created_at_idx on public.client_errors (created_at desc);
create index if not exists client_errors_user_id_idx on public.client_errors (user_id);

alter table public.client_errors enable row level security;

revoke all on table public.client_errors from anon, authenticated;
grant insert (user_id, app_version, platform, error_type, message, stack)
  on table public.client_errors to authenticated;
grant all on table public.client_errors to service_role;

drop policy if exists "Authenticated users can report errors" on public.client_errors;
create policy "Authenticated users can report errors"
  on public.client_errors
  for insert
  to authenticated
  with check (user_id is null or user_id = (select auth.uid()));

-- Per-reporter hourly counter (keyed by auth.uid(), even when user_id is null).
create table if not exists public.client_error_rate (
  reporter_id  uuid        not null references auth.users(id) on delete cascade,
  hour_window  timestamptz not null,
  reports      integer     not null default 0,
  primary key (reporter_id, hour_window)
);

alter table public.client_error_rate enable row level security;
revoke all on table public.client_error_rate from anon, authenticated;
grant all on table public.client_error_rate to service_role;

create or replace function public.client_errors_before_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid        := auth.uid();
  v_window timestamptz := date_trunc('hour', now());
  v_count  integer;
begin
  new.id         := gen_random_uuid();
  new.created_at := now();
  new.message     := left(new.message, 2000);
  new.stack       := left(new.stack, 8000);
  new.error_type  := left(new.error_type, 120);
  new.app_version := left(new.app_version, 40);
  new.platform    := left(new.platform, 40);

  -- Service-role inserts (no JWT user) are not rate limited.
  if v_uid is null then
    return new;
  end if;

  insert into public.client_error_rate as r (reporter_id, hour_window, reports)
  values (v_uid, v_window, 1)
  on conflict (reporter_id, hour_window)
  do update set reports = r.reports + 1
  returning r.reports into v_count;

  if v_count > 30 then
    return null; -- drop silently
  end if;

  -- Opportunistic cleanup of this reporter's old windows.
  delete from public.client_error_rate
  where reporter_id = v_uid and hour_window < v_window - interval '1 day';

  return new;
end;
$$;

revoke all on function public.client_errors_before_insert() from public, anon, authenticated;

drop trigger if exists client_errors_before_insert on public.client_errors;
create trigger client_errors_before_insert
  before insert on public.client_errors
  for each row execute function public.client_errors_before_insert();

comment on table public.client_errors is
  'Client error reports from the app. Insert-only for authenticated users; read via service role / dashboard.';
