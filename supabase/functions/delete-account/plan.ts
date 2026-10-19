// delete-account plan: which rows belong to a user, and the confirm guard.
// Pure module so it can be unit-tested (plan_test.ts).
//
// Every entry is filtered by `column = <caller's auth uid>`; nothing here
// ever deletes rows of another user. Order: dependent/user data first,
// profile last, then the auth user (done in index.ts).

export interface UserTable {
  table: string;
  column: 'user_id' | 'id' | 'reporter_id';
}

/** Tables whose rows are wholly owned by one user (checked against the live
 *  schema 2026-10-16, plus tables added by this release's migrations). */
export const USER_TABLES: readonly UserTable[] = [
  { table: 'day_logs',                    column: 'user_id' },
  { table: 'workout_sessions',            column: 'user_id' },
  { table: 'workout_splits',              column: 'user_id' },
  { table: 'user_nutrition_memory',       column: 'user_id' },
  { table: 'user_quick_adds',             column: 'user_id' },
  { table: 'user_eating_patterns',        column: 'user_id' },
  { table: 'user_meal_contexts',          column: 'user_id' },
  { table: 'user_insights_cache',         column: 'user_id' },
  { table: 'user_achievements',           column: 'user_id' },
  { table: 'body_metrics',                column: 'user_id' },
  { table: 'user_openai_links',           column: 'user_id' },
  { table: 'openai_device_auth_sessions', column: 'user_id' },
  { table: 'app_curators',                column: 'user_id' }, // only the user's own curator role row
  { table: 'ai_usage',                    column: 'user_id' },
  { table: 'client_errors',               column: 'user_id' },
  { table: 'client_error_rate',           column: 'reporter_id' },
  { table: 'kyno_reports',                column: 'user_id' },
  { table: 'feedback',                    column: 'user_id' },
  { table: 'profiles_backup_pre_rollback', column: 'id' },     // old profile snapshot keyed by user id
  { table: 'profiles',                    column: 'id' },
];

/** Shared rows that only carry attribution to the user. The shared food data
 *  stays for everyone; only the link to the deleted user is cleared (the
 *  FK has no ON DELETE action, so it would otherwise block deleting the auth
 *  user). */
export const ATTRIBUTION_COLUMNS: readonly { table: string; column: string }[] = [
  { table: 'global_food_defaults', column: 'curated_by' },
];

export const CONFIRM_PHRASE = 'DELETE';

/** True only for an explicit { confirm: "DELETE" } body. */
export function isConfirmed(body: unknown): boolean {
  return !!body && typeof body === 'object' && !Array.isArray(body) &&
    (body as Record<string, unknown>).confirm === CONFIRM_PHRASE;
}

/** Postgres / PostgREST "table does not exist" (e.g. migration not applied). */
export function isMissingTable(error: { code?: string } | null | undefined): boolean {
  const code = String(error?.code ?? '');
  return code === '42P01' || code === 'PGRST205';
}

/** Admin API "user not found" — a repeated call after a successful delete. */
export function isUserNotFound(error: { status?: number; code?: string; message?: string } | null | undefined): boolean {
  if (!error) return false;
  return error.status === 404 || error.code === 'user_not_found' || /not\s*found/i.test(error.message ?? '');
}
