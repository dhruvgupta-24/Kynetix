// Shared OAuth token refresh helper for Deno Edge Functions
// @ts-ignore
import { createClient } from "npm:@supabase/supabase-js@2";
import { SIWC_TOKEN_URL, SIWC_RESOURCE } from "./siwc.ts";
import { timedFetch } from "./timed_fetch.ts";

const CODEX_CLIENT_ID = 'app_EMoamEEZ73f0CkXaXp7hrann';
const OPENAI_TOKEN_URL = 'https://auth.openai.com/oauth/token';

// Token-endpoint deadlines. The whole refresh request (headers + body) must
// finish well inside the SIWC refresh lease (SIWC_LOCK_MS = 30s), so a slow
// refresh can never outlive its lease and race a second refresher.
export const REFRESH_HEADERS_TIMEOUT_MS = 10_000;
export const REFRESH_TOTAL_TIMEOUT_MS   = 15_000;

/** A short OAuth error code from a token-endpoint body, or null. Never the
 *  body itself (it can echo tokens or user data). */
export function oauthErrorCode(data: any): string | null {
  const raw = data?.error;
  const code = typeof raw === 'string' ? raw : typeof raw?.code === 'string' ? raw.code : null;
  return code && /^[A-Za-z0-9_.-]{1,60}$/.test(code) ? code : null;
}

export async function refreshAccessTokenIfNeeded(
  supabaseAdmin: any,
  userId: string,
  link: {
    access_token: string | null;
    refresh_token: string | null;
    expires_at: string | null;
    is_connected: boolean;
    // Present once migration 20261016000000_siwc_plan_usage.sql is applied.
    auth_method?: string | null;
    oauth_client_id?: string | null;
  }
): Promise<{ accessToken: string; expiresAt: string } | null> {
  if (!link.is_connected || !link.access_token) {
    return null;
  }

  // Sign in with ChatGPT (plan usage) links refresh against a different
  // endpoint with their own issued client id. Device-code links below are
  // unchanged.
  if (link.auth_method === 'siwc') {
    return refreshSiwcIfNeeded(supabaseAdmin, userId, link);
  }

  // Check if token is expired or expiring in less than 5 minutes (300,000 ms)
  const expiresAtMs = link.expires_at ? new Date(link.expires_at).getTime() : 0;
  const isExpiring = expiresAtMs === 0 || (expiresAtMs - Date.now() < 5 * 60 * 1000);

  if (!isExpiring) {
    // Access token is still valid
    return {
      accessToken: link.access_token,
      expiresAt: link.expires_at || '',
    };
  }

  // Token is expired or expiring; attempt refresh
  if (!link.refresh_token) {
    console.warn(`[OAUTH REFRESH] user=${userId} token is expired but no refresh_token is present.`);
    // Mark as expired in DB
    await supabaseAdmin
      .from('user_openai_links')
      .update({
        fallback_reason: 'token_expired',
        updated_at: new Date().toISOString(),
      })
      .eq('user_id', userId);
    return null;
  }

  console.log(`[OAUTH REFRESH] user=${userId} access token expired/expiring. Refreshing via OpenAI...`);

  try {
    const params = new URLSearchParams({
      grant_type: 'refresh_token',
      client_id: CODEX_CLIENT_ID,
      refresh_token: link.refresh_token,
    });

    const res = await timedFetch(OPENAI_TOKEN_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: params.toString(),
    }, REFRESH_HEADERS_TIMEOUT_MS, REFRESH_TOTAL_TIMEOUT_MS);

    if (!res.ok) {
      let errData: any = null;
      try { errData = await res.json(); } catch { /* non-JSON */ }
      console.error(`[OAUTH REFRESH] OpenAI refresh request failed status=${res.status} code=${oauthErrorCode(errData) ?? '-'}`);

      // Handle permanent authorization/token failures by disconnecting user.
      // Guarded on the refresh token we used, so a stale failure cannot
      // disconnect a link the user has since re-created.
      if (res.status === 400 || res.status === 401 || res.status === 403) {
        console.warn(`[OAUTH REFRESH] Permanent error from OpenAI. Disconnecting user=${userId} credentials.`);
        await supabaseAdmin
          .from('user_openai_links')
          .update({
            is_connected: false,
            fallback_reason: 'refresh_failed',
            updated_at: new Date().toISOString(),
          })
          .eq('user_id', userId)
          .eq('refresh_token', link.refresh_token);
      }
      return null;
    }

    const data = await res.json();
    const newAccessToken = data.access_token;
    if (!newAccessToken) {
      console.error(`[OAUTH REFRESH] Refresh succeeded but returned no access_token. keys=${Object.keys(data ?? {}).join(",")}`);
      return null;
    }

    const newRefreshToken = data.refresh_token ?? link.refresh_token; // use old if not rotated
    const expiresSeconds = data.expires_in ? Number(data.expires_in) : 3600;
    const newExpiresAt = new Date(Date.now() + expiresSeconds * 1000).toISOString();

    console.log(`[OAUTH REFRESH] Refresh token flow success for user=${userId}. expires_in=${expiresSeconds}s`);

    // Update DB with new tokens — only if the row still holds the refresh
    // token we used (a re-link in the meantime must not be overwritten).
    const { data: saved, error: updateErr } = await supabaseAdmin
      .from('user_openai_links')
      .update({
        access_token: newAccessToken,
        refresh_token: newRefreshToken,
        expires_at: newExpiresAt,
        last_refreshed_at: new Date().toISOString(),
        fallback_reason: null, // Clear any previous fallback reason
        updated_at: new Date().toISOString(),
      })
      .eq('user_id', userId)
      .eq('refresh_token', link.refresh_token)
      .select('user_id');

    if (updateErr) {
      console.error(`[OAUTH REFRESH] Failed to save refreshed tokens in DB: ${updateErr.code ?? ''}`);
      // return new credentials anyway to complete the current request
    } else if (!saved || saved.length === 0) {
      console.warn(`[OAUTH REFRESH] user=${userId} link changed during refresh; not saved`);
      // The link was replaced while we refreshed; still answer this request.
    }

    return {
      accessToken: newAccessToken,
      expiresAt: newExpiresAt,
    };

  } catch (err: any) {
    console.error(`[OAUTH REFRESH] Unhandled exception during token refresh: ${err?.name ?? 'Error'}`);
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sign in with ChatGPT (auth_method = 'siwc')
//
// POST https://auth.openai.com/api/accounts/oauth/token (form-encoded)
//   grant_type=refresh_token, client_id=<issued oaiapp_…>, refresh_token,
//   resource=https://api.openai.com/v1   (scope omitted = keep the grant)
// Refresh tokens rotate, so refreshes are serialized per user with a short
// DB lease (refresh_lock_until) and guarded on the refresh token we read.
// Never logs tokens or response bodies.
// ─────────────────────────────────────────────────────────────────────────────

const SIWC_EXPIRY_SKEW_MS = 5 * 60 * 1000;
// Lease (30s) > whole refresh request (REFRESH_TOTAL_TIMEOUT_MS = 15s), so the
// lease cannot lapse while our refresh is still in flight.
export const SIWC_LOCK_MS = 30 * 1000;

// Refresh errors that mean "this refresh token is done": clear tokens and ask
// the user to sign in again (with the saved client id).
const SIWC_TERMINAL_REFRESH_ERRORS = new Set([
  'invalid_grant',
  'invalid_refresh_token',
  'token_expired',
  'refresh_token_expired',
  'refresh_token_invalidated',
  'refresh_token_reused',
]);

async function refreshSiwcIfNeeded(
  supabaseAdmin: any,
  userId: string,
  link: {
    access_token: string | null;
    refresh_token: string | null;
    expires_at: string | null;
    oauth_client_id?: string | null;
  },
): Promise<{ accessToken: string; expiresAt: string } | null> {
  const expiresAtMs = link.expires_at ? new Date(link.expires_at).getTime() : 0;
  if (link.access_token && expiresAtMs - Date.now() > SIWC_EXPIRY_SKEW_MS) {
    return { accessToken: link.access_token, expiresAt: link.expires_at ?? '' };
  }

  if (!link.refresh_token || !link.oauth_client_id) {
    console.warn(`[OAUTH REFRESH][siwc] user=${userId} expired and not refreshable`);
    await supabaseAdmin
      .from('user_openai_links')
      .update({ fallback_reason: 'token_expired', updated_at: new Date().toISOString() })
      .eq('user_id', userId);
    return null;
  }

  // ── Take the lease (only if nobody rotated the token under us) ────────────
  const nowIso = new Date().toISOString();
  const { data: leased, error: leaseErr } = await supabaseAdmin
    .from('user_openai_links')
    .update({ refresh_lock_until: new Date(Date.now() + SIWC_LOCK_MS).toISOString() })
    .eq('user_id', userId)
    .eq('refresh_token', link.refresh_token)
    .or(`refresh_lock_until.is.null,refresh_lock_until.lt.${nowIso}`)
    .select('user_id');

  if (leaseErr) {
    console.error(`[OAUTH REFRESH][siwc] user=${userId} lease error: ${leaseErr.code ?? ''}`);
    return null;
  }
  if (!leased || leased.length === 0) {
    // Someone else is refreshing (or already did). Wait for their result.
    return await waitForSiwcRefresh(supabaseAdmin, userId);
  }

  // Every write after the lease is guarded on the refresh token we used: if
  // the user re-linked meanwhile (openai-link-siwc replaces the token and
  // clears the lease), a stale refresh must not touch the new link.
  const usedRefreshToken = link.refresh_token;
  const release = (extra: Record<string, unknown> = {}) =>
    supabaseAdmin
      .from('user_openai_links')
      .update({ refresh_lock_until: null, updated_at: new Date().toISOString(), ...extra })
      .eq('user_id', userId)
      .eq('refresh_token', usedRefreshToken);

  try {
    const res = await timedFetch(SIWC_TOKEN_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type:    'refresh_token',
        client_id:     link.oauth_client_id,
        refresh_token: usedRefreshToken,
        resource:      SIWC_RESOURCE,
      }).toString(),
    }, REFRESH_HEADERS_TIMEOUT_MS, REFRESH_TOTAL_TIMEOUT_MS);

    let data: any = null;
    try { data = await res.json(); } catch { /* non-JSON */ }

    if (!res.ok || typeof data?.access_token !== 'string') {
      const code = oauthErrorCode(data);
      console.warn(`[OAUTH REFRESH][siwc] user=${userId} refresh failed status=${res.status} code=${code ?? '-'}`);

      if (code && SIWC_TERMINAL_REFRESH_ERRORS.has(code)) {
        // Unusable refresh token: clear tokens, keep the issued client id so
        // the next sign-in reuses it.
        await release({
          is_connected:    false,
          access_token:    null,
          refresh_token:   null,
          id_token:        null,
          expires_at:      null,
          fallback_reason: 'reauth_required',
        });
      } else if (code === 'invalid_client') {
        await release({ is_connected: false, fallback_reason: 'invalid_client' });
      } else {
        // Temporary (network / 5xx / unknown): keep credentials.
        await release();
      }
      return null;
    }

    const expiresIn = Number(data.expires_in) > 0 ? Number(data.expires_in) : 3600;
    const newExpiresAt = new Date(Date.now() + expiresIn * 1000).toISOString();
    const update: Record<string, unknown> = {
      access_token:       data.access_token,
      // Rotation: store the replacement together with the access token.
      refresh_token:      typeof data.refresh_token === 'string' ? data.refresh_token : usedRefreshToken,
      expires_at:         newExpiresAt,
      last_refreshed_at:  new Date().toISOString(),
      refresh_lock_until: null,
      updated_at:         new Date().toISOString(),
    };
    if (typeof data.scope === 'string') update.granted_scopes = data.scope;
    if (typeof data.id_token === 'string') update.id_token = data.id_token;

    const { data: saved, error: saveErr } = await supabaseAdmin
      .from('user_openai_links')
      .update(update)
      .eq('user_id', userId)
      .eq('refresh_token', usedRefreshToken)
      .select('user_id');
    if (saveErr) {
      console.error(`[OAUTH REFRESH][siwc] user=${userId} save failed: ${saveErr.code ?? ''}`);
    } else if (!saved || saved.length === 0) {
      // The link was replaced (re-link) while we refreshed. Don't overwrite
      // it; use whatever the current link holds, if it is usable.
      console.warn(`[OAUTH REFRESH][siwc] user=${userId} link changed during refresh; result discarded`);
      return await currentSiwcToken(supabaseAdmin, userId);
    }

    console.log(`[OAUTH REFRESH][siwc] user=${userId} refreshed expires_in=${expiresIn}s`);
    return { accessToken: data.access_token, expiresAt: newExpiresAt };
  } catch (err: any) {
    console.error(`[OAUTH REFRESH][siwc] user=${userId} exception: ${err?.name ?? 'Error'}`);
    await release();
    return null;
  }
}

/** The current link's access token if it is connected and not expiring. */
async function currentSiwcToken(
  supabaseAdmin: any,
  userId: string,
): Promise<{ accessToken: string; expiresAt: string } | null> {
  const { data } = await supabaseAdmin
    .from('user_openai_links')
    .select('is_connected, access_token, expires_at')
    .eq('user_id', userId)
    .maybeSingle();
  if (!data || !data.is_connected || !data.access_token) return null;
  const exp = data.expires_at ? new Date(data.expires_at).getTime() : 0;
  return exp - Date.now() > SIWC_EXPIRY_SKEW_MS
    ? { accessToken: data.access_token, expiresAt: data.expires_at }
    : null;
}

async function waitForSiwcRefresh(
  supabaseAdmin: any,
  userId: string,
): Promise<{ accessToken: string; expiresAt: string } | null> {
  // Wait up to the refresher's whole request deadline (+1s), still < lease.
  const polls = Math.ceil(REFRESH_TOTAL_TIMEOUT_MS / 500) + 2;
  for (let i = 0; i < polls; i++) {
    await new Promise((r) => setTimeout(r, 500));
    const { data } = await supabaseAdmin
      .from('user_openai_links')
      .select('is_connected, access_token, expires_at, refresh_lock_until')
      .eq('user_id', userId)
      .maybeSingle();
    if (!data || !data.is_connected || !data.access_token) return null;
    const exp = data.expires_at ? new Date(data.expires_at).getTime() : 0;
    if (exp - Date.now() > SIWC_EXPIRY_SKEW_MS) {
      return { accessToken: data.access_token, expiresAt: data.expires_at };
    }
    const lockMs = data.refresh_lock_until ? new Date(data.refresh_lock_until).getTime() : 0;
    if (lockMs < Date.now()) return null; // lease dropped without a new token
  }
  return null;
}
