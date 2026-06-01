// openai-link-poll — Phase B/C: Poll for device auth completion + PKCE token exchange
//
// Flow:
//   1. Verify Supabase JWT
//   2. Look up pending session by session_id
//   3. POST to OpenAI deviceauth/token with { device_auth_id, user_code }
//   4. If authorized: receive { authorization_code, code_challenge, code_verifier }
//   5. Exchange authorization_code + code_verifier for access/refresh/id tokens
//   6. Save tokens to user_openai_links (server-side only)
//   7. Return { status: 'pending' | 'connected' | 'expired' } — NO tokens to client
//
// Called by Flutter every interval_seconds while waiting for user to authorize.

// @ts-ignore
import { createClient } from "npm:@supabase/supabase-js@2";

declare const Deno: any;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const CODEX_CLIENT_ID  = 'app_EMoamEEZ73f0CkXaXp7hrann';
const OPENAI_AUTH_BASE = 'https://auth.openai.com/api/accounts';
const OPENAI_TOKEN_URL = 'https://auth.openai.com/oauth/token';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // ── 1. Verify Supabase JWT ────────────────────────────────────────────────
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return json({ error: 'Missing Authorization header' }, 401);

    const jwt = authHeader.replace('Bearer ', '').trim();
    const supabaseAnon = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: `Bearer ${jwt}` } } },
    );
    const { data: { user }, error: userErr } = await supabaseAnon.auth.getUser();
    if (userErr || !user) {
      return json({ error: 'Unauthorized' }, 401);
    }

    // ── 2. Parse request: need session_id ────────────────────────────────────
    const body = await req.json().catch(() => ({}));
    const session_id: string = body.session_id ?? '';
    if (!session_id) {
      return json({ error: 'session_id required' }, 400);
    }

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    );

    // ── 3. Look up session ────────────────────────────────────────────────────
    const { data: session, error: sessionErr } = await supabaseAdmin
      .from('openai_device_auth_sessions')
      .select('*')
      .eq('id', session_id)
      .eq('user_id', user.id)
      .single();

    if (sessionErr || !session) {
      return json({ status: 'expired', message: 'Session not found' }, 404);
    }

    // Check expiry
    if (new Date(session.expires_at) < new Date()) {
      await supabaseAdmin
        .from('openai_device_auth_sessions')
        .update({ status: 'expired' })
        .eq('id', session_id);
      return json({ status: 'expired' });
    }

    if (session.status === 'claimed') {
      return json({ status: 'connected' });
    }

    const device_auth_id = session.device_code; // stored in device_code column
    const user_code      = session.user_code;

    console.log(`[openai-link-poll] user=${user.id} session=${session_id} polling...`);

    // ── 4. Poll OpenAI device token endpoint ─────────────────────────────────
    const pollRes = await fetch(`${OPENAI_AUTH_BASE}/deviceauth/token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ device_auth_id, user_code }),
    });

    // 428 / authorization_pending = still waiting
    // 400 / slow_down = wait longer
    // 200 = authorized
    if (pollRes.status === 428 || pollRes.status === 400) {
      const pollBody = await pollRes.json().catch(() => ({}));
      const errCode = pollBody?.error ?? pollBody?.code ?? '';
      if (errCode === 'expired_token' || errCode === 'access_denied') {
        await supabaseAdmin
          .from('openai_device_auth_sessions')
          .update({ status: 'expired' })
          .eq('id', session_id);
        return json({ status: 'expired', reason: errCode });
      }
      // Still pending (authorization_pending or slow_down)
      return json({ status: 'pending' });
    }

    if (!pollRes.ok) {
      const errBody = await pollRes.text();
      console.error(`[openai-link-poll] Poll error ${pollRes.status}: ${errBody.slice(0, 200)}`);
      // If it's a 4xx about the user not having authorized yet:
      if (pollRes.status === 401 || pollRes.status === 403) {
        return json({ status: 'pending' });
      }
      return json({ status: 'error', message: `Poll failed: ${pollRes.status}` }, 502);
    }

    // ── 5. Parse authorized response ─────────────────────────────────────────
    const pollData = await pollRes.json();
    console.log(`[openai-link-poll] Poll response keys: ${Object.keys(pollData).join(', ')}`);

    const authorization_code: string = pollData.authorization_code ?? '';
    const code_verifier: string      = pollData.code_verifier ?? '';
    // code_challenge is also returned but we only need code_verifier for exchange

    if (!authorization_code || !code_verifier) {
      console.error(`[openai-link-poll] Missing auth code or verifier in poll response: ${JSON.stringify(pollData).slice(0, 300)}`);
      return json({ status: 'error', message: 'Unexpected poll response format' }, 502);
    }

    console.log(`[openai-link-poll] Got authorization_code, exchanging for tokens...`);

    // ── 6. PKCE token exchange ────────────────────────────────────────────────
    // Try standard PKCE exchange first, then fallback variant
    const tokens = await exchangeCodeForTokens(authorization_code, code_verifier);
    if (!tokens) {
      return json({ status: 'error', message: 'Token exchange failed' }, 502);
    }

    const expiresAt = tokens.expires_in
      ? new Date(Date.now() + tokens.expires_in * 1000).toISOString()
      : null;

    // ── 7. Save tokens to user_openai_links ───────────────────────────────────
    const { error: upsertErr } = await supabaseAdmin
      .from('user_openai_links')
      .upsert({
        user_id:       user.id,
        is_connected:  true,
        access_token:  tokens.access_token,
        refresh_token: tokens.refresh_token ?? null,
        id_token:      tokens.id_token ?? null,
        expires_at:    expiresAt,
        connected_at:  new Date().toISOString(),
        updated_at:    new Date().toISOString(),
      }, { onConflict: 'user_id' });

    if (upsertErr) {
      console.error(`[openai-link-poll] DB upsert failed: ${upsertErr.message}`);
      return json({ status: 'error', message: 'Failed to persist tokens' }, 500);
    }

    // Mark session as claimed
    await supabaseAdmin
      .from('openai_device_auth_sessions')
      .update({ status: 'claimed', claimed_at: new Date().toISOString() })
      .eq('id', session_id);

    console.log(`[openai-link-poll] ✅ Tokens persisted for user=${user.id}`);

    return json({ status: 'connected' });

  } catch (err: any) {
    console.error(`[openai-link-poll] Unhandled: ${err?.message ?? err}`);
    return json({ error: 'Internal Server Error' }, 500);
  }
});

// ── PKCE token exchange — uses standard OAuth authorization_code + code_verifier
async function exchangeCodeForTokens(
  authorization_code: string,
  code_verifier: string,
): Promise<{ access_token: string; refresh_token?: string; id_token?: string; expires_in?: number } | null> {

  // Attempt 1: standard PKCE form-encoded exchange (no redirect_uri for device flow)
  const params = new URLSearchParams({
    grant_type:    'authorization_code',
    code:          authorization_code,
    code_verifier: code_verifier,
    client_id:     'app_EMoamEEZ73f0CkXaXp7hrann',
  });

  let res = await fetch('https://auth.openai.com/oauth/token', {
    method:  'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body:    params.toString(),
  });

  if (!res.ok) {
    const errBody = await res.text();
    console.warn(`[openai-link-poll] Exchange attempt 1 failed (${res.status}): ${errBody.slice(0, 300)}`);

    // Attempt 2: JSON body (some OpenAI endpoints accept JSON)
    const jsonRes = await fetch('https://auth.openai.com/oauth/token', {
      method:  'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        grant_type:    'authorization_code',
        code:          authorization_code,
        code_verifier: code_verifier,
        client_id:     'app_EMoamEEZ73f0CkXaXp7hrann',
      }),
    });

    if (!jsonRes.ok) {
      const errBody2 = await jsonRes.text();
      console.error(`[openai-link-poll] Exchange attempt 2 also failed (${jsonRes.status}): ${errBody2.slice(0, 300)}`);
      return null;
    }
    res = jsonRes;
  }

  const data = await res.json();
  if (!data.access_token) {
    console.error(`[openai-link-poll] Token exchange response missing access_token: ${JSON.stringify(data).slice(0, 300)}`);
    return null;
  }

  console.log(`[openai-link-poll] Token exchange success. expires_in=${data.expires_in}`);
  return data;
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
