-- Per-user AI usage counters + atomic rate-limit check for ai-chat-router.
--
-- Additive and idempotent. No client access: RLS on with no policies, and
-- table/function privileges revoked from anon/authenticated. Only the
-- service role (edge functions) reads or writes.
--
-- Apply BEFORE deploying the new ai-chat-router. (If the function is
-- deployed first, the router fails open on the missing RPC and logs a
-- warning; message/image caps still apply.)

create table if not exists public.ai_usage (
  user_id        uuid        not null references auth.users(id) on delete cascade,
  day            date        not null,               -- UTC day
  requests       integer     not null default 0,
  chars          bigint      not null default 0,     -- client-supplied text chars
  images         integer     not null default 0,
  minute_window  timestamptz,                        -- start of current 1-minute window
  minute_count   integer     not null default 0,
  updated_at     timestamptz not null default now(),
  primary key (user_id, day)
);

create index if not exists ai_usage_day_idx on public.ai_usage (day);

alter table public.ai_usage enable row level security;
revoke all on table public.ai_usage from anon, authenticated;
grant all on table public.ai_usage to service_role;

comment on table public.ai_usage is
  'Per-user daily AI request counters for ai-chat-router rate limiting. Service role only.';

-- Checks the per-minute and per-day caps and, when allowed, records the
-- request — in one row-locked transaction so concurrent requests cannot
-- overshoot. A rejected request is not counted.
--
-- Returns jsonb:
--   { allowed: true,  day_requests, minute_requests }
--   { allowed: false, scope: 'minute'|'day', retry_after (seconds), day_requests, minute_requests }
create or replace function public.ai_usage_consume(
  p_user_id    uuid,
  p_chars      integer,
  p_images     integer,
  p_per_minute integer,
  p_per_day    integer
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_now    timestamptz := now();
  v_day    date        := (v_now at time zone 'utc')::date;
  v_window timestamptz := date_trunc('minute', v_now);
  v_row    public.ai_usage%rowtype;
  v_minute integer;
begin
  if p_user_id is null then
    raise exception 'p_user_id required';
  end if;

  insert into public.ai_usage (user_id, day)
  values (p_user_id, v_day)
  on conflict (user_id, day) do nothing;

  select * into v_row
  from public.ai_usage
  where user_id = p_user_id and day = v_day
  for update;

  v_minute := case when v_row.minute_window = v_window then v_row.minute_count else 0 end;

  if v_row.requests >= greatest(p_per_day, 1) then
    return jsonb_build_object(
      'allowed', false,
      'scope', 'day',
      'retry_after', greatest(1, ceil(extract(epoch from (((v_day + 1)::timestamp at time zone 'utc') - v_now)))::int),
      'day_requests', v_row.requests,
      'minute_requests', v_minute);
  end if;

  if v_minute >= greatest(p_per_minute, 1) then
    return jsonb_build_object(
      'allowed', false,
      'scope', 'minute',
      'retry_after', greatest(1, ceil(extract(epoch from ((v_window + interval '1 minute') - v_now)))::int),
      'day_requests', v_row.requests,
      'minute_requests', v_minute);
  end if;

  update public.ai_usage
  set requests      = requests + 1,
      chars         = chars + greatest(coalesce(p_chars, 0), 0),
      images        = images + greatest(coalesce(p_images, 0), 0),
      minute_window = v_window,
      minute_count  = v_minute + 1,
      updated_at    = v_now
  where user_id = p_user_id and day = v_day;

  return jsonb_build_object(
    'allowed', true,
    'day_requests', v_row.requests + 1,
    'minute_requests', v_minute + 1);
end;
$$;

revoke all on function public.ai_usage_consume(uuid, integer, integer, integer, integer) from public, anon, authenticated;
grant execute on function public.ai_usage_consume(uuid, integer, integer, integer, integer) to service_role;
