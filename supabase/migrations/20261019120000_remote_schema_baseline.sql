-- Baseline: the whole production schema as of 2026-10-19, dumped from the
-- linked project with `supabase db dump -s public`, plus the pieces that live
-- outside the public schema (auth trigger, storage buckets and policies).
--
-- Replaces the earlier migration files, several of which assumed tables that
-- were first created in the dashboard (profiles, user_openai_links, ...), so
-- a fresh preview branch could not replay them. Their SQL stays in git
-- history. Every statement here is already in effect on production.




SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE OR REPLACE FUNCTION "public"."ai_usage_consume"("p_user_id" "uuid", "p_chars" integer, "p_images" integer, "p_per_minute" integer, "p_per_day" integer) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."ai_usage_consume"("p_user_id" "uuid", "p_chars" integer, "p_images" integer, "p_per_minute" integer, "p_per_day" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."client_errors_before_insert"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."client_errors_before_insert"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  INSERT INTO public.profiles (id, email, name)
  VALUES (
    new.id,
    new.email,
    COALESCE(new.raw_user_meta_data->>'name', new.raw_user_meta_data->>'full_name', '')
  )
  ON CONFLICT (id) DO UPDATE
  SET email = EXCLUDED.email,
      name = COALESCE(profiles.name, EXCLUDED.name);
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."handle_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."kx_meal_entry_id"("p_entry" "jsonb") RETURNS "text"
    LANGUAGE "sql" STABLE
    SET "search_path" TO 'pg_catalog', 'pg_temp'
    AS $$
  select coalesce(
    nullif(p_entry->>'id', ''),
    'l-' || md5(coalesce(p_entry->>'addedAt', '') || '|' || coalesce(p_entry->>'rawInput', ''))
  );
$$;


ALTER FUNCTION "public"."kx_meal_entry_id"("p_entry" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."kx_merge_meal_sections"("p_server_sections" "jsonb", "p_server_deleted" "jsonb", "p_incoming_sections" "jsonb", "p_incoming_deleted" "jsonb") RETURNS "jsonb"
    LANGUAGE "sql" STABLE
    SET "search_path" TO 'public', 'pg_catalog', 'pg_temp'
    AS $$
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


ALTER FUNCTION "public"."kx_merge_meal_sections"("p_server_sections" "jsonb", "p_server_deleted" "jsonb", "p_incoming_sections" "jsonb", "p_incoming_deleted" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."kx_try_timestamptz"("p" "text") RETURNS timestamp with time zone
    LANGUAGE "plpgsql" STABLE
    SET "search_path" TO 'pg_catalog', 'pg_temp'
    AS $$
begin
  if p is null or p = '' then
    return null;
  end if;
  return p::timestamptz;
exception when others then
  return null;
end;
$$;


ALTER FUNCTION "public"."kx_try_timestamptz"("p" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."merge_day_log"("p_date_key" "text", "p_sections" "jsonb", "p_deleted" "jsonb" DEFAULT '{}'::"jsonb", "p_gym_day_json" "jsonb" DEFAULT NULL::"jsonb", "p_target_calories" double precision DEFAULT NULL::double precision, "p_target_protein" double precision DEFAULT NULL::double precision) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public', 'pg_catalog', 'pg_temp'
    AS $_$
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
$_$;


ALTER FUNCTION "public"."merge_day_log"("p_date_key" "text", "p_sections" "jsonb", "p_deleted" "jsonb", "p_gym_day_json" "jsonb", "p_target_calories" double precision, "p_target_protein" double precision) OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."ai_usage" (
    "user_id" "uuid" NOT NULL,
    "day" "date" NOT NULL,
    "requests" integer DEFAULT 0 NOT NULL,
    "chars" bigint DEFAULT 0 NOT NULL,
    "images" integer DEFAULT 0 NOT NULL,
    "minute_window" timestamp with time zone,
    "minute_count" integer DEFAULT 0 NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."ai_usage" OWNER TO "postgres";


COMMENT ON TABLE "public"."ai_usage" IS 'Per-user daily AI request counters for ai-chat-router rate limiting. Service role only.';



CREATE TABLE IF NOT EXISTS "public"."app_curators" (
    "user_id" "uuid" NOT NULL,
    "role" "text" DEFAULT 'curator'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."app_curators" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."body_metrics" (
    "user_id" "uuid" NOT NULL,
    "date_key" "text" NOT NULL,
    "water_ml" integer DEFAULT 0 NOT NULL,
    "weight_kg" numeric(5,2),
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "body_metrics_date_key_check" CHECK (("date_key" ~ '^\d{4}-\d{2}-\d{2}$'::"text")),
    CONSTRAINT "body_metrics_water_ml_check" CHECK ((("water_ml" >= 0) AND ("water_ml" <= 20000))),
    CONSTRAINT "body_metrics_weight_kg_check" CHECK ((("weight_kg" IS NULL) OR (("weight_kg" >= (20)::numeric) AND ("weight_kg" <= (400)::numeric))))
);


ALTER TABLE "public"."body_metrics" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."client_error_rate" (
    "reporter_id" "uuid" NOT NULL,
    "hour_window" timestamp with time zone NOT NULL,
    "reports" integer DEFAULT 0 NOT NULL
);


ALTER TABLE "public"."client_error_rate" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."client_errors" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "app_version" "text",
    "platform" "text",
    "error_type" "text",
    "message" "text",
    "stack" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "client_errors_message_len" CHECK ((("message" IS NULL) OR ("char_length"("message") <= 2000))),
    CONSTRAINT "client_errors_platform_len" CHECK ((("platform" IS NULL) OR ("char_length"("platform") <= 40))),
    CONSTRAINT "client_errors_stack_len" CHECK ((("stack" IS NULL) OR ("char_length"("stack") <= 8000))),
    CONSTRAINT "client_errors_type_len" CHECK ((("error_type" IS NULL) OR ("char_length"("error_type") <= 120))),
    CONSTRAINT "client_errors_version_len" CHECK ((("app_version" IS NULL) OR ("char_length"("app_version") <= 40)))
);


ALTER TABLE "public"."client_errors" OWNER TO "postgres";


COMMENT ON TABLE "public"."client_errors" IS 'Client error reports from the app. Insert-only for authenticated users; read via service role / dashboard.';



CREATE TABLE IF NOT EXISTS "public"."day_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "date_key" "text" NOT NULL,
    "gym_day_json" "jsonb",
    "sections_json" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "target_calories" double precision,
    "target_protein" double precision,
    "deleted_meal_ids" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL
);


ALTER TABLE "public"."day_logs" OWNER TO "postgres";


COMMENT ON COLUMN "public"."day_logs"."deleted_meal_ids" IS 'Meal entry id -> deletion time (ISO-8601). Written by merge_day_log; keeps a meal deleted on one device from being re-added by another.';



CREATE TABLE IF NOT EXISTS "public"."global_food_defaults" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "canonical_name" "text" NOT NULL,
    "calories_per_unit" double precision NOT NULL,
    "protein_per_unit" double precision NOT NULL,
    "carbs_per_unit" double precision,
    "fat_per_unit" double precision,
    "fiber_per_unit" double precision,
    "reference_quantity" double precision DEFAULT 1.0 NOT NULL,
    "reference_unit" "text" DEFAULT 'serving'::"text" NOT NULL,
    "curated_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."global_food_defaults" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."openai_device_auth_sessions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "device_code" "text",
    "user_code" "text",
    "verification_url" "text",
    "interval_seconds" integer,
    "expires_at" timestamp with time zone NOT NULL,
    "claimed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "access_token" "text",
    "refresh_token" "text",
    "id_token" "text",
    "connected_at" timestamp with time zone,
    "status" "text" DEFAULT 'pending'::"text",
    "pkce_code_verifier" "text",
    "pkce_authorization_code" "text",
    "debug_logs" "jsonb"
);


ALTER TABLE "public"."openai_device_auth_sessions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "email" "text",
    "name" "text",
    "age" integer,
    "gender" "text",
    "height_cm" numeric,
    "weight_kg" numeric,
    "goal" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "workout_days_min" integer,
    "workout_days_max" integer,
    "phone" "text",
    "carry_forward_enabled" boolean DEFAULT false,
    "carry_forward_threshold" integer DEFAULT 100,
    "portion_anchor" "text",
    "privacy_consent_at" timestamp with time zone,
    "privacy_policy_version" "text",
    "age_confirmed_adult" boolean,
    "profile_json" "jsonb",
    "profile_updated_at" timestamp with time zone
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


COMMENT ON COLUMN "public"."profiles"."privacy_consent_at" IS 'When the user accepted the privacy policy (null = not recorded).';



COMMENT ON COLUMN "public"."profiles"."privacy_policy_version" IS 'Version string of the privacy policy the user accepted.';



COMMENT ON COLUMN "public"."profiles"."age_confirmed_adult" IS 'User confirmed they are 18+ (null = not asked yet).';



COMMENT ON COLUMN "public"."profiles"."profile_json" IS 'Full app UserProfile JSON (custom targets, target history, steps, ...). Preferred over the individual columns on restore.';



COMMENT ON COLUMN "public"."profiles"."profile_updated_at" IS 'When profile_json was last written by the app.';



CREATE TABLE IF NOT EXISTS "public"."profiles_backup_pre_rollback" (
    "id" "uuid",
    "email" "text",
    "name" "text",
    "age" integer,
    "gender" "text",
    "height_cm" integer,
    "weight_kg" numeric,
    "goal" "text",
    "created_at" timestamp with time zone,
    "workout_days_min" integer,
    "workout_days_max" integer,
    "phone" "text",
    "carry_forward_enabled" boolean,
    "carry_forward_threshold" integer,
    "portion_anchor" "text",
    "username" "text",
    "current_level" "text",
    "current_xp" integer,
    "integrity_rate" integer
);


ALTER TABLE "public"."profiles_backup_pre_rollback" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_achievements" (
    "user_id" "uuid" NOT NULL,
    "id" "text" NOT NULL,
    "earned_at" timestamp with time zone NOT NULL
);


ALTER TABLE "public"."user_achievements" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_eating_patterns" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "target_role" "text" NOT NULL,
    "context_role" "text",
    "pipeline_estimate" double precision NOT NULL,
    "user_corrected_cal" double precision NOT NULL,
    "ratio" double precision NOT NULL,
    "recorded_at" timestamp with time zone NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."user_eating_patterns" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_insights_cache" (
    "user_id" "uuid" NOT NULL,
    "weekly_json" "jsonb",
    "monthly_json" "jsonb",
    "yearly_json" "jsonb",
    "personal_bests_json" "jsonb",
    "updated_at" timestamp with time zone NOT NULL
);


ALTER TABLE "public"."user_insights_cache" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_meal_contexts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "primary_food_names" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "primary_total_qty" double precision DEFAULT 1.0 NOT NULL,
    "primary_dominant" "text" DEFAULT ''::"text" NOT NULL,
    "recorded_at" timestamp with time zone NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."user_meal_contexts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_nutrition_memory" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "canonical_meal" "text" NOT NULL,
    "calories" numeric NOT NULL,
    "protein" numeric NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "calories_per_unit" double precision,
    "protein_per_unit" double precision,
    "reference_quantity" double precision DEFAULT 1.0,
    "reference_unit" "text" DEFAULT 'serving'::"text",
    "times_used" integer DEFAULT 1 NOT NULL,
    "carbohydrates_per_unit" double precision,
    "fat_per_unit" double precision,
    "fiber_per_unit" double precision
);


ALTER TABLE "public"."user_nutrition_memory" OWNER TO "postgres";


COMMENT ON COLUMN "public"."user_nutrition_memory"."carbohydrates_per_unit" IS 'grams of carbohydrates per 1 referenceUnit, nullable if unknown';



COMMENT ON COLUMN "public"."user_nutrition_memory"."fat_per_unit" IS 'grams of fat per 1 referenceUnit, nullable if unknown';



COMMENT ON COLUMN "public"."user_nutrition_memory"."fiber_per_unit" IS 'grams of fiber per 1 referenceUnit, nullable if unknown';



CREATE TABLE IF NOT EXISTS "public"."user_openai_links" (
    "user_id" "uuid" NOT NULL,
    "is_connected" boolean DEFAULT false,
    "access_token" "text",
    "refresh_token" "text",
    "id_token" "text",
    "expires_at" timestamp with time zone,
    "connected_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "responses_api_blocked" boolean DEFAULT false,
    "selected_model" "text",
    "discovered_models" "jsonb",
    "discovery_timestamp" timestamp with time zone,
    "last_provider_used" "text",
    "last_used_at" timestamp with time zone,
    "model_discovery_verified" boolean DEFAULT false,
    "test_generation_snippet" "text",
    "last_refreshed_at" timestamp with time zone,
    "fallback_reason" "text",
    "auth_method" "text" DEFAULT 'codex_device'::"text" NOT NULL,
    "oauth_client_id" "text",
    "granted_scopes" "text",
    "openai_subject" "text",
    "ext_agent_host_id" "text",
    "plan_paused_until" timestamp with time zone,
    "refresh_lock_until" timestamp with time zone,
    CONSTRAINT "user_openai_links_auth_method_check" CHECK (("auth_method" = ANY (ARRAY['codex_device'::"text", 'siwc'::"text"])))
);


ALTER TABLE "public"."user_openai_links" OWNER TO "postgres";


COMMENT ON COLUMN "public"."user_openai_links"."auth_method" IS 'codex_device = Codex device-code link (chatgpt.com backend); siwc = Sign in with ChatGPT plan usage (api.openai.com/v1/responses).';



CREATE TABLE IF NOT EXISTS "public"."user_quick_adds" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "calories" numeric NOT NULL,
    "protein" numeric NOT NULL,
    "emoji" "text" DEFAULT '⚡'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."user_quick_adds" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."workout_sessions" (
    "id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "date" timestamp with time zone NOT NULL,
    "split_day_name" "text" NOT NULL,
    "split_day_weekday" integer,
    "was_manually_selected" boolean DEFAULT false,
    "entries_json" "jsonb",
    "notes" "text",
    "duration_minutes" integer,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."workout_sessions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."workout_splits" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "split_json" "jsonb" NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "custom_exercises_json" "jsonb"
);


ALTER TABLE "public"."workout_splits" OWNER TO "postgres";


ALTER TABLE ONLY "public"."ai_usage"
    ADD CONSTRAINT "ai_usage_pkey" PRIMARY KEY ("user_id", "day");



ALTER TABLE ONLY "public"."app_curators"
    ADD CONSTRAINT "app_curators_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."body_metrics"
    ADD CONSTRAINT "body_metrics_pkey" PRIMARY KEY ("user_id", "date_key");



ALTER TABLE ONLY "public"."client_error_rate"
    ADD CONSTRAINT "client_error_rate_pkey" PRIMARY KEY ("reporter_id", "hour_window");



ALTER TABLE ONLY "public"."client_errors"
    ADD CONSTRAINT "client_errors_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."day_logs"
    ADD CONSTRAINT "day_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."day_logs"
    ADD CONSTRAINT "day_logs_user_id_date_key_key" UNIQUE ("user_id", "date_key");



ALTER TABLE ONLY "public"."global_food_defaults"
    ADD CONSTRAINT "global_food_defaults_canonical_name_key" UNIQUE ("canonical_name");



ALTER TABLE ONLY "public"."global_food_defaults"
    ADD CONSTRAINT "global_food_defaults_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."openai_device_auth_sessions"
    ADD CONSTRAINT "openai_device_auth_sessions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."openai_device_auth_sessions"
    ADD CONSTRAINT "openai_device_auth_sessions_user_id_key" UNIQUE ("user_id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_achievements"
    ADD CONSTRAINT "user_achievements_pkey" PRIMARY KEY ("user_id", "id");



ALTER TABLE ONLY "public"."user_eating_patterns"
    ADD CONSTRAINT "user_eating_patterns_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_eating_patterns"
    ADD CONSTRAINT "user_eating_patterns_uq" UNIQUE ("user_id", "target_role", "recorded_at");



ALTER TABLE ONLY "public"."user_insights_cache"
    ADD CONSTRAINT "user_insights_cache_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."user_meal_contexts"
    ADD CONSTRAINT "user_meal_contexts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_meal_contexts"
    ADD CONSTRAINT "user_meal_contexts_uq" UNIQUE ("user_id", "recorded_at");



ALTER TABLE ONLY "public"."user_nutrition_memory"
    ADD CONSTRAINT "user_nutrition_memory_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_nutrition_memory"
    ADD CONSTRAINT "user_nutrition_memory_user_id_canonical_meal_key" UNIQUE ("user_id", "canonical_meal");



ALTER TABLE ONLY "public"."user_openai_links"
    ADD CONSTRAINT "user_openai_links_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."user_quick_adds"
    ADD CONSTRAINT "user_quick_adds_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_quick_adds"
    ADD CONSTRAINT "user_quick_adds_user_id_name_key" UNIQUE ("user_id", "name");



ALTER TABLE ONLY "public"."workout_sessions"
    ADD CONSTRAINT "workout_sessions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."workout_splits"
    ADD CONSTRAINT "workout_splits_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."workout_splits"
    ADD CONSTRAINT "workout_splits_user_id_key" UNIQUE ("user_id");



CREATE INDEX "ai_usage_day_idx" ON "public"."ai_usage" USING "btree" ("day");



CREATE INDEX "client_errors_created_at_idx" ON "public"."client_errors" USING "btree" ("created_at" DESC);



CREATE INDEX "client_errors_user_id_idx" ON "public"."client_errors" USING "btree" ("user_id");



CREATE INDEX "user_eating_patterns_recorded_at_idx" ON "public"."user_eating_patterns" USING "btree" ("user_id", "recorded_at" DESC);



CREATE INDEX "user_eating_patterns_user_id_idx" ON "public"."user_eating_patterns" USING "btree" ("user_id");



CREATE INDEX "user_meal_contexts_user_id_idx" ON "public"."user_meal_contexts" USING "btree" ("user_id");



CREATE OR REPLACE TRIGGER "client_errors_before_insert" BEFORE INSERT ON "public"."client_errors" FOR EACH ROW EXECUTE FUNCTION "public"."client_errors_before_insert"();



CREATE OR REPLACE TRIGGER "set_updated_at" BEFORE UPDATE ON "public"."user_quick_adds" FOR EACH ROW EXECUTE FUNCTION "public"."handle_updated_at"();



ALTER TABLE ONLY "public"."ai_usage"
    ADD CONSTRAINT "ai_usage_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."app_curators"
    ADD CONSTRAINT "app_curators_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."body_metrics"
    ADD CONSTRAINT "body_metrics_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."client_error_rate"
    ADD CONSTRAINT "client_error_rate_reporter_id_fkey" FOREIGN KEY ("reporter_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."client_errors"
    ADD CONSTRAINT "client_errors_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."day_logs"
    ADD CONSTRAINT "day_logs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."global_food_defaults"
    ADD CONSTRAINT "global_food_defaults_curated_by_fkey" FOREIGN KEY ("curated_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."openai_device_auth_sessions"
    ADD CONSTRAINT "openai_device_auth_sessions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_achievements"
    ADD CONSTRAINT "user_achievements_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_eating_patterns"
    ADD CONSTRAINT "user_eating_patterns_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_insights_cache"
    ADD CONSTRAINT "user_insights_cache_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_meal_contexts"
    ADD CONSTRAINT "user_meal_contexts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_nutrition_memory"
    ADD CONSTRAINT "user_nutrition_memory_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_openai_links"
    ADD CONSTRAINT "user_openai_links_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."user_quick_adds"
    ADD CONSTRAINT "user_quick_adds_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."workout_sessions"
    ADD CONSTRAINT "workout_sessions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."workout_splits"
    ADD CONSTRAINT "workout_splits_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



CREATE POLICY "Authenticated users can report errors" ON "public"."client_errors" FOR INSERT TO "authenticated" WITH CHECK ((("user_id" IS NULL) OR ("user_id" = ( SELECT "auth"."uid"() AS "uid"))));



CREATE POLICY "Curators readable by authenticated users" ON "public"."app_curators" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Global food defaults readable by all authenticated users" ON "public"."global_food_defaults" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Only curators can delete global food defaults" ON "public"."global_food_defaults" FOR DELETE TO "authenticated" USING (("auth"."uid"() IN ( SELECT "app_curators"."user_id"
   FROM "public"."app_curators")));



CREATE POLICY "Only curators can insert global food defaults" ON "public"."global_food_defaults" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() IN ( SELECT "app_curators"."user_id"
   FROM "public"."app_curators")));



CREATE POLICY "Only curators can update global food defaults" ON "public"."global_food_defaults" FOR UPDATE TO "authenticated" USING (("auth"."uid"() IN ( SELECT "app_curators"."user_id"
   FROM "public"."app_curators"))) WITH CHECK (("auth"."uid"() IN ( SELECT "app_curators"."user_id"
   FROM "public"."app_curators")));



CREATE POLICY "Users can delete their own day logs" ON "public"."day_logs" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete their own memory" ON "public"."user_nutrition_memory" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete their own quick adds" ON "public"."user_quick_adds" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete their own workouts" ON "public"."workout_sessions" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can insert their own day logs" ON "public"."day_logs" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can insert their own memory" ON "public"."user_nutrition_memory" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can insert their own profile" ON "public"."profiles" FOR INSERT WITH CHECK (("auth"."uid"() = "id"));



CREATE POLICY "Users can insert their own quick adds" ON "public"."user_quick_adds" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can insert their own workouts" ON "public"."workout_sessions" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can manage own eating patterns" ON "public"."user_eating_patterns" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can manage own meal contexts" ON "public"."user_meal_contexts" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can manage their own splits" ON "public"."workout_splits" TO "authenticated" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update their own day logs" ON "public"."day_logs" FOR UPDATE USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update their own memory" ON "public"."user_nutrition_memory" FOR UPDATE USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update their own profile" ON "public"."profiles" FOR UPDATE USING (("auth"."uid"() = "id"));



CREATE POLICY "Users can update their own quick adds" ON "public"."user_quick_adds" FOR UPDATE USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update their own workouts" ON "public"."workout_sessions" FOR UPDATE USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view their own day logs" ON "public"."day_logs" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view their own memory" ON "public"."user_nutrition_memory" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view their own profile" ON "public"."profiles" FOR SELECT USING (("auth"."uid"() = "id"));



CREATE POLICY "Users can view their own quick adds" ON "public"."user_quick_adds" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view their own workouts" ON "public"."workout_sessions" FOR SELECT USING (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."ai_usage" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."app_curators" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."body_metrics" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "body_metrics owner delete" ON "public"."body_metrics" FOR DELETE TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "body_metrics owner insert" ON "public"."body_metrics" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "body_metrics owner select" ON "public"."body_metrics" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "body_metrics owner update" ON "public"."body_metrics" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."client_error_rate" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."client_errors" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."day_logs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."global_food_defaults" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."openai_device_auth_sessions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "own_achievements" ON "public"."user_achievements" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "own_insights_cache" ON "public"."user_insights_cache" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."profiles_backup_pre_rollback" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_achievements" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_eating_patterns" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_insights_cache" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_meal_contexts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_nutrition_memory" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_openai_links" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_quick_adds" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."workout_sessions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."workout_splits" ENABLE ROW LEVEL SECURITY;


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



REVOKE ALL ON FUNCTION "public"."ai_usage_consume"("p_user_id" "uuid", "p_chars" integer, "p_images" integer, "p_per_minute" integer, "p_per_day" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."ai_usage_consume"("p_user_id" "uuid", "p_chars" integer, "p_images" integer, "p_per_minute" integer, "p_per_day" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."client_errors_before_insert"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."client_errors_before_insert"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."kx_meal_entry_id"("p_entry" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."kx_meal_entry_id"("p_entry" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."kx_meal_entry_id"("p_entry" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."kx_merge_meal_sections"("p_server_sections" "jsonb", "p_server_deleted" "jsonb", "p_incoming_sections" "jsonb", "p_incoming_deleted" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."kx_merge_meal_sections"("p_server_sections" "jsonb", "p_server_deleted" "jsonb", "p_incoming_sections" "jsonb", "p_incoming_deleted" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."kx_merge_meal_sections"("p_server_sections" "jsonb", "p_server_deleted" "jsonb", "p_incoming_sections" "jsonb", "p_incoming_deleted" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."kx_try_timestamptz"("p" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."kx_try_timestamptz"("p" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."kx_try_timestamptz"("p" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."merge_day_log"("p_date_key" "text", "p_sections" "jsonb", "p_deleted" "jsonb", "p_gym_day_json" "jsonb", "p_target_calories" double precision, "p_target_protein" double precision) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."merge_day_log"("p_date_key" "text", "p_sections" "jsonb", "p_deleted" "jsonb", "p_gym_day_json" "jsonb", "p_target_calories" double precision, "p_target_protein" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."merge_day_log"("p_date_key" "text", "p_sections" "jsonb", "p_deleted" "jsonb", "p_gym_day_json" "jsonb", "p_target_calories" double precision, "p_target_protein" double precision) TO "service_role";



GRANT ALL ON TABLE "public"."ai_usage" TO "service_role";



GRANT ALL ON TABLE "public"."app_curators" TO "anon";
GRANT ALL ON TABLE "public"."app_curators" TO "authenticated";
GRANT ALL ON TABLE "public"."app_curators" TO "service_role";



GRANT ALL ON TABLE "public"."body_metrics" TO "authenticated";
GRANT ALL ON TABLE "public"."body_metrics" TO "service_role";



GRANT ALL ON TABLE "public"."client_error_rate" TO "service_role";



GRANT ALL ON TABLE "public"."client_errors" TO "service_role";



GRANT INSERT("user_id") ON TABLE "public"."client_errors" TO "authenticated";



GRANT INSERT("app_version") ON TABLE "public"."client_errors" TO "authenticated";



GRANT INSERT("platform") ON TABLE "public"."client_errors" TO "authenticated";



GRANT INSERT("error_type") ON TABLE "public"."client_errors" TO "authenticated";



GRANT INSERT("message") ON TABLE "public"."client_errors" TO "authenticated";



GRANT INSERT("stack") ON TABLE "public"."client_errors" TO "authenticated";



GRANT ALL ON TABLE "public"."day_logs" TO "anon";
GRANT ALL ON TABLE "public"."day_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."day_logs" TO "service_role";



GRANT ALL ON TABLE "public"."global_food_defaults" TO "anon";
GRANT ALL ON TABLE "public"."global_food_defaults" TO "authenticated";
GRANT ALL ON TABLE "public"."global_food_defaults" TO "service_role";



GRANT ALL ON TABLE "public"."openai_device_auth_sessions" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT ALL ON TABLE "public"."profiles_backup_pre_rollback" TO "anon";
GRANT ALL ON TABLE "public"."profiles_backup_pre_rollback" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles_backup_pre_rollback" TO "service_role";



GRANT ALL ON TABLE "public"."user_achievements" TO "anon";
GRANT ALL ON TABLE "public"."user_achievements" TO "authenticated";
GRANT ALL ON TABLE "public"."user_achievements" TO "service_role";



GRANT ALL ON TABLE "public"."user_eating_patterns" TO "anon";
GRANT ALL ON TABLE "public"."user_eating_patterns" TO "authenticated";
GRANT ALL ON TABLE "public"."user_eating_patterns" TO "service_role";



GRANT ALL ON TABLE "public"."user_insights_cache" TO "anon";
GRANT ALL ON TABLE "public"."user_insights_cache" TO "authenticated";
GRANT ALL ON TABLE "public"."user_insights_cache" TO "service_role";



GRANT ALL ON TABLE "public"."user_meal_contexts" TO "anon";
GRANT ALL ON TABLE "public"."user_meal_contexts" TO "authenticated";
GRANT ALL ON TABLE "public"."user_meal_contexts" TO "service_role";



GRANT ALL ON TABLE "public"."user_nutrition_memory" TO "anon";
GRANT ALL ON TABLE "public"."user_nutrition_memory" TO "authenticated";
GRANT ALL ON TABLE "public"."user_nutrition_memory" TO "service_role";



GRANT ALL ON TABLE "public"."user_openai_links" TO "service_role";



GRANT ALL ON TABLE "public"."user_quick_adds" TO "anon";
GRANT ALL ON TABLE "public"."user_quick_adds" TO "authenticated";
GRANT ALL ON TABLE "public"."user_quick_adds" TO "service_role";



GRANT ALL ON TABLE "public"."workout_sessions" TO "anon";
GRANT ALL ON TABLE "public"."workout_sessions" TO "authenticated";
GRANT ALL ON TABLE "public"."workout_sessions" TO "service_role";



GRANT ALL ON TABLE "public"."workout_splits" TO "anon";
GRANT ALL ON TABLE "public"."workout_splits" TO "authenticated";
GRANT ALL ON TABLE "public"."workout_splits" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";









-- ── Outside the public schema ───────────────────────────────────────────────

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types) VALUES
  ('public-pages', 'public-pages', true,  null,    null),
  ('documents',    'documents',    false, null,    null),
  ('avatars',      'avatars',      false, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO UPDATE
  SET public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Profile pictures: each user reads and writes only their own folder.
DROP POLICY IF EXISTS "avatars_own_select" ON storage.objects;
DROP POLICY IF EXISTS "avatars_own_insert" ON storage.objects;
DROP POLICY IF EXISTS "avatars_own_update" ON storage.objects;
DROP POLICY IF EXISTS "avatars_own_delete" ON storage.objects;
CREATE POLICY "avatars_own_select" ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);
CREATE POLICY "avatars_own_insert" ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);
CREATE POLICY "avatars_own_update" ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text)
  WITH CHECK (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);
CREATE POLICY "avatars_own_delete" ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);
