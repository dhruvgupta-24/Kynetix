-- Workout sessions never reached the cloud: the app's session ids are text
-- ("ws_1729500000000", "ws_import_…"), but the column was uuid, so every
-- upsert and delete was rejected with "invalid input syntax for type uuid"
-- (checked 2026-11-06: 0 rows for every user). The id becomes text; the
-- table is empty, and a uuid casts to its text form, so nothing is lost.
-- Once applied, the app's unsynced-session queue uploads every workout each
-- phone holds.

alter table public.workout_sessions
  alter column id type text using id::text;

-- Ids are per-phone timestamps, so two users can produce the same one. The
-- key is (user_id, id): one user's workout can never collide with another's.
alter table public.workout_sessions drop constraint if exists workout_sessions_pkey;
alter table public.workout_sessions add constraint workout_sessions_pkey primary key (user_id, id);
