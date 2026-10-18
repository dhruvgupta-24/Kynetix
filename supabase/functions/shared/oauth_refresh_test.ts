// deno test --allow-all supabase/functions/shared/oauth_refresh_test.ts
import {
  oauthErrorCode,
  refreshAccessTokenIfNeeded,
  REFRESH_TOTAL_TIMEOUT_MS,
  SIWC_LOCK_MS,
} from './oauth_refresh.ts';

function assert(cond: unknown, msg: string) {
  if (!cond) throw new Error(msg);
}

/** Minimal in-memory stand-in for supabase-js on one user_openai_links row.
 *  Supports update/select + eq/or filters + maybeSingle, as used here.
 *  [beforeWrite] lets a test change the row between the refresh call and
 *  the save (simulating a concurrent re-link). */
function fakeDb(row: Record<string, any>) {
  const writes: Array<{ patch: Record<string, unknown>; matched: boolean }> = [];
  const db = {
    row,
    writes,
    beforeSave: null as null | (() => void),
    from(_t: string) {
      let patch: Record<string, unknown> | null = null;
      const filters: Array<(r: any) => boolean> = [];
      const run = () => {
        const matched = filters.every((f) => f(db.row));
        if (patch) {
          if ('access_token' in patch && db.beforeSave) { const f = db.beforeSave; db.beforeSave = null; f(); }
          const m = filters.every((f) => f(db.row));
          writes.push({ patch, matched: m });
          if (m) Object.assign(db.row, patch);
          return { data: m ? [{ user_id: db.row.user_id }] : [], error: null };
        }
        return { data: matched ? { ...db.row } : null, error: null };
      };
      const q: any = {
        update(p: Record<string, unknown>) { patch = p; return q; },
        select(_c: string) { return q; },
        eq(k: string, v: unknown) { filters.push((r) => r[k] === v); return q; },
        or(_s: string) {
          filters.push((r) => !r.refresh_lock_until || new Date(r.refresh_lock_until).getTime() < Date.now());
          return q;
        },
        maybeSingle() { return Promise.resolve(run()); },
        then(res: (v: unknown) => unknown, rej: (e: unknown) => unknown) {
          return Promise.resolve(run()).then(res, rej);
        },
      };
      return q;
    },
  };
  return db;
}

function siwcRow(extra: Record<string, unknown> = {}) {
  return {
    user_id: 'u1',
    is_connected: true,
    auth_method: 'siwc',
    oauth_client_id: 'oaiapp_test',
    access_token: 'old-access',
    refresh_token: 'rt-old',
    expires_at: new Date(Date.now() - 1000).toISOString(),
    refresh_lock_until: null,
    ...extra,
  };
}

async function withFetch(impl: (url: string, init: RequestInit) => Promise<Response>, fn: () => Promise<void>) {
  const orig = globalThis.fetch;
  globalThis.fetch = ((u: string | URL | Request, init?: RequestInit) => impl(String(u), init ?? {})) as typeof fetch;
  try { await fn(); } finally { globalThis.fetch = orig; }
}

const tokenOk = () => new Response(JSON.stringify({ access_token: 'new-access', refresh_token: 'rt-new', expires_in: 3600 }), { status: 200 });

Deno.test('refresh request deadline is clearly shorter than the lease', () => {
  assert(REFRESH_TOTAL_TIMEOUT_MS * 2 <= SIWC_LOCK_MS, `${REFRESH_TOTAL_TIMEOUT_MS} vs ${SIWC_LOCK_MS}`);
});

Deno.test({ name: 'siwc refresh saves rotated tokens guarded on the used refresh token', sanitizeOps: false, sanitizeResources: false }, async () => {
  const db = fakeDb(siwcRow());
  await withFetch(() => Promise.resolve(tokenOk()), async () => {
    const r = await refreshAccessTokenIfNeeded(db, 'u1', { ...db.row } as any);
    assert(r?.accessToken === 'new-access', 'new token returned');
  });
  assert(db.row.refresh_token === 'rt-new' && db.row.access_token === 'new-access', 'saved');
  assert(db.row.refresh_lock_until === null, 'lease released');
});

Deno.test({ name: 'siwc refresh does not overwrite a re-link that happened mid-refresh', sanitizeOps: false, sanitizeResources: false }, async () => {
  const db = fakeDb(siwcRow());
  const relinkExpiry = new Date(Date.now() + 3600_000).toISOString();
  db.beforeSave = () => {
    // openai-link-siwc upsert: new tokens, lease cleared.
    Object.assign(db.row, { access_token: 'relinked-access', refresh_token: 'rt-relinked', expires_at: relinkExpiry, refresh_lock_until: null });
  };
  await withFetch(() => Promise.resolve(tokenOk()), async () => {
    const r = await refreshAccessTokenIfNeeded(db, 'u1', siwcRow() as any);
    assert(r?.accessToken === 'relinked-access', `uses the current link's token, got ${r?.accessToken}`);
  });
  assert(db.row.refresh_token === 'rt-relinked' && db.row.access_token === 'relinked-access', 'newer link intact');
  const save = db.writes.find((w) => 'access_token' in w.patch);
  assert(save && !save.matched, 'guarded save matched zero rows');
});

Deno.test({ name: 'a stale terminal refresh error cannot wipe a newer link', sanitizeOps: false, sanitizeResources: false }, async () => {
  const db = fakeDb(siwcRow());
  await withFetch(async () => {
    // Re-link lands while the (stale) refresh is in flight.
    Object.assign(db.row, { refresh_token: 'rt-relinked', access_token: 'relinked-access' });
    return new Response(JSON.stringify({ error: 'invalid_grant', error_description: 'secret rt-old' }), { status: 400 });
  }, async () => {
    const r = await refreshAccessTokenIfNeeded(db, 'u1', siwcRow() as any);
    assert(r === null, 'no token');
  });
  assert(db.row.is_connected === true && db.row.refresh_token === 'rt-relinked', 'newer link not cleared');
});

Deno.test({ name: 'terminal refresh error on the current link clears it', sanitizeOps: false, sanitizeResources: false }, async () => {
  const db = fakeDb(siwcRow());
  await withFetch(() => Promise.resolve(new Response(JSON.stringify({ error: 'invalid_grant' }), { status: 400 })), async () => {
    assert((await refreshAccessTokenIfNeeded(db, 'u1', siwcRow() as any)) === null, 'null');
  });
  assert(db.row.is_connected === false && db.row.refresh_token === null && db.row.fallback_reason === 'reauth_required', 'cleared');
});

Deno.test('oauthErrorCode returns only short codes, never bodies', () => {
  assert(oauthErrorCode({ error: 'invalid_grant' }) === 'invalid_grant', 'string');
  assert(oauthErrorCode({ error: { code: 'refresh_token_reused', message: 'tok_123' } }) === 'refresh_token_reused', 'object');
  assert(oauthErrorCode({ error: 'access_token=eyJhbGciOi... more text' }) === null, 'non-code text dropped');
  assert(oauthErrorCode(null) === null && oauthErrorCode('x') === null, 'garbage');
});
