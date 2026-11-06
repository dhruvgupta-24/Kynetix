// deno test --allow-all supabase/functions/shared/ai_quota_test.ts
// Global AI budget, kill switch and the atomic photo cap (ai_usage_consume_v2).
import {
  AiGuardError,
  consumeGlobalBudget,
  consumeQuota,
  GLOBAL_BUDGET_DEFAULT,
  globalBudget,
  parseQuotaResult,
  quotaError,
  STANDARD_TIER_DEFAULT,
  standardTier,
} from './ai_guard.ts';

function assert(cond: unknown, msg: string) {
  if (!cond) throw new Error(msg);
}

type RpcReply = { data: unknown; error: { code: string } | null };

/** Fake admin client: answers rpc(name) from [replies]; records calls. */
function fakeRpc(replies: Record<string, RpcReply>, imagesRow: { images: number } | null = null) {
  const calls: Array<{ fn: string; args: Record<string, unknown> }> = [];
  const q: any = {
    select: () => q,
    eq: () => q,
    maybeSingle: () => Promise.resolve({ data: imagesRow, error: null }),
  };
  const admin = {
    rpc: (fn: string, args: Record<string, unknown>) => {
      calls.push({ fn, args });
      return Promise.resolve(replies[fn] ?? { data: null, error: { code: 'PGRST202' } });
    },
    from: () => q,
  };
  return { admin, calls };
}

const NO_FN = { data: null, error: { code: 'PGRST202' } };

Deno.test('defaults: free fallback users get a low daily cap; global budget is set', () => {
  const prev = [Deno.env.get('AI_RATE_PER_DAY'), Deno.env.get('AI_GLOBAL_PER_DAY')];
  try {
    Deno.env.delete('AI_RATE_PER_DAY');
    Deno.env.delete('AI_GLOBAL_PER_DAY');
    assert(standardTier().perDay === 60 && STANDARD_TIER_DEFAULT.perDay === 60, 'standard 60/day');
    assert(globalBudget().perDay === GLOBAL_BUDGET_DEFAULT.perDay, 'global default');
    Deno.env.set('AI_GLOBAL_PER_DAY', '900');
    assert(globalBudget().perDay === 900, 'env override');
    Deno.env.set('AI_GLOBAL_PER_DAY', 'nonsense');
    assert(globalBudget().perDay === GLOBAL_BUDGET_DEFAULT.perDay, 'bad env ignored');
  } finally {
    if (prev[0] === undefined) Deno.env.delete('AI_RATE_PER_DAY'); else Deno.env.set('AI_RATE_PER_DAY', prev[0]);
    if (prev[1] === undefined) Deno.env.delete('AI_GLOBAL_PER_DAY'); else Deno.env.set('AI_GLOBAL_PER_DAY', prev[1]);
  }
});

Deno.test('parseQuotaResult: object, array, unknown scope', () => {
  const a = parseQuotaResult({ allowed: true, day_requests: 3, minute_requests: 1 });
  assert(a.allowed && a.dayRequests === 3 && a.minuteRequests === 1 && a.enforced, 'object');
  const b = parseQuotaResult([{ allowed: false, scope: 'global_day', retry_after: 0 }]);
  assert(!b.allowed && b.scope === 'global_day' && b.retryAfter === 1, 'array + retry floor');
  const c = parseQuotaResult({ allowed: false, scope: 'weird' });
  assert(c.scope === undefined, 'unknown scope dropped');
  assert(!parseQuotaResult(null).allowed, 'null = refused');
});

Deno.test('quotaError: each scope maps to the right status, code and copy', () => {
  const now = new Date(Date.UTC(2026, 10, 6, 23, 0, 0));
  const cases: Array<[string, number, string]> = [
    ['disabled', 503, 'ai_paused'],
    ['global_minute', 503, 'ai_busy'],
    ['global_day', 503, 'ai_busy'],
    ['images', 429, 'rate_limited'],
    ['day', 429, 'rate_limited'],
    ['minute', 429, 'rate_limited'],
  ];
  for (const [scope, status, code] of cases) {
    const e = quotaError({ allowed: false, scope: scope as any, dayRequests: 0, minuteRequests: 0, enforced: true }, now);
    assert(e instanceof AiGuardError && e.status === status && e.code === code, `${scope} -> ${e.status}/${e.code}`);
    const body = e.toBody();
    assert(typeof body.message === 'string' && !/[\u2013\u2014]/.test(body.message as string), `${scope} copy has no dashes`);
    assert(typeof body.retry_after === 'number' && (body.retry_after as number) >= 1, `${scope} retry_after`);
  }
  const day = quotaError({ allowed: false, scope: 'global_day', dayRequests: 0, minuteRequests: 0, enforced: true }, now);
  assert(day.extra['retry_after'] === 3600, 'global_day defaults to UTC midnight');
});

Deno.test('consumeQuota: calls ai_usage_consume_v2 with cap and global flags', async () => {
  const { admin, calls } = fakeRpc({ ai_usage_consume_v2: { data: { allowed: true, day_requests: 1, minute_requests: 1 }, error: null } });
  const q = await consumeQuota(admin, 'u1', { perMinute: 10, perDay: 60 }, 120.7, 2,
    { imageCap: 30, countGlobal: true, global: { perMinute: 5, perDay: 100 } });
  assert(q.allowed && q.enforced, 'allowed');
  assert(calls.length === 1 && calls[0].fn === 'ai_usage_consume_v2', 'single atomic RPC');
  const a = calls[0].args;
  assert(a.p_user_id === 'u1' && a.p_chars === 120 && a.p_images === 2, 'counts');
  assert(a.p_image_cap === 30 && a.p_count_global === true, 'cap + global');
  assert(a.p_global_per_minute === 5 && a.p_global_per_day === 100, 'global limits');
});

Deno.test('consumeQuota: refusals come back as results (no throw)', async () => {
  for (const scope of ['images', 'global_minute', 'disabled']) {
    const { admin } = fakeRpc({ ai_usage_consume_v2: { data: { allowed: false, scope, retry_after: 42 }, error: null } });
    const q = await consumeQuota(admin, 'u1', { perMinute: 10, perDay: 60 }, 0, 1,
      { imageCap: 30, countGlobal: true, global: GLOBAL_BUDGET_DEFAULT });
    assert(!q.allowed && q.scope === scope && q.retryAfter === 42, scope);
  }
});

Deno.test('consumeQuota: DB error fails closed (503)', async () => {
  const { admin } = fakeRpc({ ai_usage_consume_v2: { data: null, error: { code: '57014' } } });
  try {
    await consumeQuota(admin, 'u1', { perMinute: 10, perDay: 60 }, 0, 0);
    throw new Error('expected throw');
  } catch (e) {
    assert(e instanceof AiGuardError && e.status === 503 && e.code === 'rate_limit_unavailable', 'fail closed');
  }
});

Deno.test('consumeQuota: before the migration, legacy path (photo read + ai_usage_consume)', async () => {
  const { admin, calls } = fakeRpc({
    ai_usage_consume_v2: NO_FN,
    ai_usage_consume: { data: { allowed: true, day_requests: 4, minute_requests: 1 }, error: null },
  }, { images: 0 });
  const q = await consumeQuota(admin, 'u1', { perMinute: 10, perDay: 60 }, 10, 2,
    { imageCap: 30, countGlobal: true, global: GLOBAL_BUDGET_DEFAULT });
  assert(q.allowed && q.dayRequests === 4, 'legacy result');
  assert(calls.map((c) => c.fn).join(',') === 'ai_usage_consume_v2,ai_usage_consume', 'fell back');

  // Legacy photo cap still enforced.
  const over = fakeRpc({ ai_usage_consume_v2: NO_FN }, { images: 29 });
  try {
    await consumeQuota(over.admin, 'u1', { perMinute: 10, perDay: 60 }, 0, 2,
      { imageCap: 30, countGlobal: true, global: GLOBAL_BUDGET_DEFAULT });
    throw new Error('expected throw');
  } catch (e) {
    assert(e instanceof AiGuardError && e.status === 429, 'legacy cap');
  }

  // Neither function: fail open (deploy window), as before.
  const none = fakeRpc({});
  const r = await consumeQuota(none.admin, 'u1', { perMinute: 10, perDay: 60 }, 0, 0);
  assert(r.allowed && !r.enforced, 'fail open when nothing is migrated');
});

Deno.test('consumeGlobalBudget: allowed, refused, missing, error', async () => {
  const ok = fakeRpc({ ai_global_consume: { data: { allowed: true }, error: null } });
  assert((await consumeGlobalBudget(ok.admin, 1, GLOBAL_BUDGET_DEFAULT)).allowed, 'allowed');
  assert(ok.calls[0].args.p_images === 1, 'images passed');

  const no = fakeRpc({ ai_global_consume: { data: { allowed: false, scope: 'global_day', retry_after: 10 }, error: null } });
  const r = await consumeGlobalBudget(no.admin, 0, GLOBAL_BUDGET_DEFAULT);
  assert(!r.allowed && r.scope === 'global_day', 'refused');

  const missing = fakeRpc({});
  const m = await consumeGlobalBudget(missing.admin, 0, GLOBAL_BUDGET_DEFAULT);
  assert(m.allowed && !m.enforced, 'missing fails open');

  const bad = fakeRpc({ ai_global_consume: { data: null, error: { code: '57014' } } });
  try {
    await consumeGlobalBudget(bad.admin, 0, GLOBAL_BUDGET_DEFAULT);
    throw new Error('expected throw');
  } catch (e) {
    assert(e instanceof AiGuardError && e.status === 503, 'error fails closed');
  }
});
