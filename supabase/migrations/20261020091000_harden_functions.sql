-- Security advisor fixes before launch.
--
-- 1. Trigger functions get a fixed search_path (function_search_path_mutable).
-- 2. handle_new_user is SECURITY DEFINER and only meant to run from the
--    auth.users trigger: nobody may call it through /rest/v1/rpc.
-- 3. The pre-rollback profile backup holds old personal data and is read by
--    nothing but the service role (account deletion clears it): clients lose
--    every grant on it.

alter function public.handle_new_user() set search_path = public;
alter function public.handle_updated_at() set search_path = public;

revoke execute on function public.handle_new_user() from public, anon, authenticated;

revoke all on table public.profiles_backup_pre_rollback from anon, authenticated;
