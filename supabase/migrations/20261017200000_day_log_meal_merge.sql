-- Per-meal merge for day_logs (cross-device deletion / clobber fix).
--
-- Before: clients upserted a whole day's sections_json, so a stale device
-- re-uploaded meals another device had deleted and overwrote meals it had
-- never seen. Now clients call merge_day_log(), which merges per meal entry:
--
--   * entry identity = entry->>'id', or for entries written by older clients
--     'l-' || md5(addedAt || '|' || rawInput) (the app derives the same id),
--   * last writer wins per entry by entry->>'updatedAt' (absent = oldest),
--   * deletions persist in day_logs.deleted_meal_ids {id: deletedAt ISO}, and
--     a tombstone beats any copy of the entry not updated after it.
--
-- Additive and lossless: one new column with a default; no existing column,
-- row or value is changed by this migration. Old clients that still upsert
-- sections_json keep working (they simply don't carry tombstones).

alter table public.day_logs
  add column if not exists deleted_meal_ids jsonb not null default '{}'::jsonb;

comment on column public.day_logs.deleted_meal_ids is
  'Meal entry id -> deletion time (ISO-8601). Written by merge_day_log; keeps a meal deleted on one device from being re-added by another.';

-- Lenient timestamptz parse: null for null / unparseable input.
create or replace function public.kx_try_timestamptz(p text)
returns timestamptz
language plpgsql
stable
set search_path = pg_catalog, pg_temp
as $$
begin
  if p is null or p = '' then
    return null;
  end if;
  return p::timestamptz;
exception when others then
  return null;
end;
$$;

-- Stable id of a meal entry json (mirrors MealEntry.id in the app).
create or replace function public.kx_meal_entry_id(p_entry jsonb)
returns text
language sql
stable
set search_path = pg_catalog, pg_temp
as $$
  select coalesce(
    nullif(p_entry->>'id', ''),
    'l-' || md5(coalesce(p_entry->>'addedAt', '') || '|' || coalesce(p_entry->>'rawInput', ''))
  );
$$;

-- Pure per-entry merge. No table access, so it can be exercised directly.
-- Returns {"sections_json": {...}, "deleted_meal_ids": {...}}.
create or replace function public.kx_merge_meal_sections(
  p_server_sections jsonb,
  p_server_deleted  jsonb,
  p_incoming_sections jsonb,
  p_incoming_deleted  jsonb
)
returns jsonb
language sql
stable
set search_path = public, pg_catalog, pg_temp
as $$
  with tomb_src as (
    select key, value
      from jsonb_each_text(case when jsonb_typeof(p_server_deleted) = 'object'
                                then p_server_deleted else '{}'::jsonb end)
    union all
    select key, value
      from jsonb_each_text(case when jsonb_typeof(p_incoming_deleted) = 'object'
                                then p_incoming_deleted else '{}'::jsonb end)
  ),
  tombs as (
    -- Keep the latest deletion time per id (its original string).
    select distinct on (key) key, value, public.kx_try_timestamptz(value) as at
      from tomb_src
     where public.kx_try_timestamptz(value) is not null
     order by key, public.kx_try_timestamptz(value) desc
  ),
  entries as (
    select s.key as sec, e.value as entry, e.ord, 0 as src
      from jsonb_each(case when jsonb_typeof(p_server_sections) = 'object'
                           then p_server_sections else '{}'::jsonb end) s
      cross join lateral jsonb_array_elements(
        case when jsonb_typeof(s.value) = 'array' then s.value else '[]'::jsonb end
      ) with ordinality as e(value, ord)
     where jsonb_typeof(e.value) = 'object'
    union all
    select s.key, e.value, e.ord, 1
      from jsonb_each(case when jsonb_typeof(p_incoming_sections) = 'object'
                           then p_incoming_sections else '{}'::jsonb end) s
      cross join lateral jsonb_array_elements(
        case when jsonb_typeof(s.value) = 'array' then s.value else '[]'::jsonb end
      ) with ordinality as e(value, ord)
     where jsonb_typeof(e.value) = 'object'
  ),
  keyed as (
    select sec, entry, ord, src,
           public.kx_meal_entry_id(entry) as eid,
           public.kx_try_timestamptz(entry->>'updatedAt') as uat
      from entries
  ),
  winners as (
    -- Newest updatedAt wins; ties (incl. both absent) go to the uploader.
    select distinct on (eid) *
      from keyed
     order by eid, uat desc nulls last, src desc, ord
  ),
  alive as (
    select w.*
      from winners w
      left join tombs t on t.key = w.eid
     where t.key is null
        or (w.uat is not null and w.uat > t.at)
  ),
  by_section as (
    select sec,
           jsonb_agg(entry order by public.kx_try_timestamptz(entry->>'addedAt') nulls last, eid) as arr
      from alive
     group by sec
  )
  select jsonb_build_object(
    'sections_json',    coalesce((select jsonb_object_agg(sec, arr) from by_section), '{}'::jsonb),
    'deleted_meal_ids', coalesce((select jsonb_object_agg(key, value) from tombs), '{}'::jsonb)
  );
$$;

-- Owner-only merge-upload of one day. SECURITY INVOKER: RLS on day_logs
-- applies as well as the explicit auth.uid() scoping below.
create or replace function public.merge_day_log(
  p_date_key        text,
  p_sections        jsonb,
  p_deleted         jsonb default '{}'::jsonb,
  p_gym_day_json    jsonb default null,
  p_target_calories double precision default null,
  p_target_protein  double precision default null
)
returns jsonb
language plpgsql
security invoker
set search_path = public, pg_catalog, pg_temp
as $$
declare
  v_uid    uuid := auth.uid();
  v_row    public.day_logs%rowtype;
  v_merged jsonb;
begin
  if v_uid is null then
    raise exception 'merge_day_log: not authenticated' using errcode = '42501';
  end if;
  if p_date_key is null or p_date_key !~ '^\d{4}-\d{2}-\d{2}$' then
    raise exception 'merge_day_log: invalid date_key' using errcode = '22023';
  end if;

  insert into public.day_logs (user_id, date_key, sections_json)
  values (v_uid, p_date_key, '{}'::jsonb)
  on conflict (user_id, date_key) do nothing;

  -- Serialize concurrent uploads of the same day.
  select * into v_row
    from public.day_logs
   where user_id = v_uid and date_key = p_date_key
   for update;

  v_merged := public.kx_merge_meal_sections(
    v_row.sections_json, v_row.deleted_meal_ids, p_sections, p_deleted);

  update public.day_logs
     set sections_json    = v_merged->'sections_json',
         deleted_meal_ids = v_merged->'deleted_meal_ids',
         gym_day_json     = coalesce(p_gym_day_json, gym_day_json),
         target_calories  = coalesce(p_target_calories, target_calories),
         target_protein   = coalesce(p_target_protein, target_protein),
         updated_at       = now()
   where user_id = v_uid and date_key = p_date_key;

  return v_merged;
end;
$$;

revoke all on function public.merge_day_log(text, jsonb, jsonb, jsonb, double precision, double precision) from public, anon;
grant execute on function public.merge_day_log(text, jsonb, jsonb, jsonb, double precision, double precision) to authenticated;
