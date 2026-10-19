// deno test supabase/functions/delete-account/plan_test.ts
import {
  ATTRIBUTION_COLUMNS,
  isConfirmed,
  isMissingTable,
  isUserNotFound,
  USER_TABLES,
} from './plan.ts';

function assert(cond: unknown, msg: string) {
  if (!cond) throw new Error(msg);
}

Deno.test('confirm guard: only an explicit { confirm: "DELETE" } passes', () => {
  assert(isConfirmed({ confirm: 'DELETE' }), 'exact phrase');
  for (const bad of [
    null, undefined, {}, [], 'DELETE', { confirm: 'delete' }, { confirm: 'DELETE ' },
    { confirm: true }, { confirm: ['DELETE'] }, { confirmed: 'DELETE' }, [{ confirm: 'DELETE' }],
  ]) {
    assert(!isConfirmed(bad), `rejects ${JSON.stringify(bad)}`);
  }
});

Deno.test('table list covers every user-keyed table in the live schema', () => {
  const tables = USER_TABLES.map((t) => t.table);
  for (const t of [
    'day_logs', 'profiles', 'profiles_backup_pre_rollback', 'workout_sessions', 'workout_splits',
    'user_nutrition_memory', 'user_quick_adds', 'user_eating_patterns', 'user_meal_contexts',
    'user_insights_cache', 'user_achievements', 'user_openai_links', 'openai_device_auth_sessions',
    'app_curators', 'ai_usage', 'client_errors', 'client_error_rate', 'kyno_reports', 'feedback',
  ]) {
    assert(tables.includes(t), `missing ${t}`);
  }
  assert(new Set(tables).size === tables.length, 'no duplicates');
});

Deno.test('profiles is deleted last (after dependent rows)', () => {
  assert(USER_TABLES[USER_TABLES.length - 1].table === 'profiles', 'profiles last');
});

Deno.test('every filter is a per-user key column', () => {
  for (const t of USER_TABLES) {
    assert(['user_id', 'id', 'reporter_id'].includes(t.column), `${t.table} filters by ${t.column}`);
    if (t.column === 'id') {
      assert(t.table === 'profiles' || t.table === 'profiles_backup_pre_rollback',
        `${t.table}: id is only the user key on profile tables`);
    }
  }
});

Deno.test('shared tables are never deleted, only unlinked', () => {
  const tables = USER_TABLES.map((t) => t.table);
  assert(!tables.includes('global_food_defaults'), 'global_food_defaults not deleted');
  assert(ATTRIBUTION_COLUMNS.some((a) => a.table === 'global_food_defaults' && a.column === 'curated_by'),
    'curated_by cleared');
});

Deno.test('error classifiers', () => {
  assert(isMissingTable({ code: '42P01' }) && isMissingTable({ code: 'PGRST205' }), 'missing table');
  assert(!isMissingTable({ code: '42501' }) && !isMissingTable(null), 'other errors are real');
  assert(isUserNotFound({ status: 404 }) && isUserNotFound({ code: 'user_not_found' }), 'not found');
  assert(!isUserNotFound({ status: 500, message: 'boom' }) && !isUserNotFound(null), 'other auth errors');
});
