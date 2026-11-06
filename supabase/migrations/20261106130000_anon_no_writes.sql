-- The anonymous role never writes: every app write happens signed in, and
-- sign-up rows are made by the handle_new_user trigger (security definer).
-- RLS already blocks anon (every policy needs auth.uid()), so this is the
-- second lock: no INSERT / UPDATE / DELETE grant at all, on current and
-- future tables.

revoke insert, update, delete on all tables in schema public from anon;
alter default privileges for role postgres in schema public
  revoke insert, update, delete on tables from anon;
