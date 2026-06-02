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

// @ts-ignore
Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const logs: string[] = [];
  let currentSessionId = '';
  let supabaseAdmin: any = null;

  const log = (msg: string) => {
    const time = new Date().toISOString();
    logs.push(`[${time}] ${msg}`);
    console.log(`[openai-link-poll] ${msg}`);
  };

  const flushLogs = async (statusOverride?: string) => {
    if (!supabaseAdmin || !currentSessionId) return;
    try {
      const updateData: any = { debug_logs: { logs } };
      if (statusOverride) {
        updateData.status = statusOverride;
      }
      const { error } = await supabaseAdmin
        .from('openai_device_auth_sessions')
        .update(updateData)
        .eq('id', currentSessionId);
      if (error) {
        console.error(`[openai-link-poll] Failed to save debug_logs: ${error.message}`);
      }
    } catch (e) {
      console.error(`[openai-link-poll] Failed to flush logs: ${e}`);
    }
  };

  try {
    log('--- POLL ATTEMPT START ---');
    // ── 1. Verify Supabase JWT ────────────────────────────────────────────────
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      log('Error: Missing Authorization header');
      return json({ error: 'Missing Authorization header' }, 401);
    }

    const jwt = authHeader.replace('Bearer ', '').trim();
    const supabaseAnon = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: `Bearer ${jwt}` } } },
    );
    const { data: { user }, error: userErr } = await supabaseAnon.auth.getUser();
    if (userErr || !user) {
      log(`Error: Unauthorized userErr=${userErr?.message}`);
      return json({ error: 'Unauthorized' }, 401);
    }
    log(`Auth success: user_id=${user.id}`);

    // ── 2. Parse request: need session_id ────────────────────────────────────
    const body = await req.json().catch(() => ({}));
    const session_id: string = body.session_id ?? '';
    if (!session_id) {
      log('Error: Missing session_id');
      return json({ error: 'session_id required' }, 400);
    }
    currentSessionId = session_id;
    log(`session_id=${session_id}`);

    supabaseAdmin = createClient(
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
      log(`Error: Session not found or error=${sessionErr?.message}`);
      await flushLogs();
      return json({ status: 'expired', message: 'Session not found' }, 404);
    }

    log(`Session found: status=${session.status}, expires_at=${session.expires_at}`);

    // Check expiry
    if (new Date(session.expires_at) < new Date()) {
      log('Session expired based on expires_at');
      await flushLogs('expired');
      return json({ status: 'expired' });
    }

    if (session.status === 'claimed') {
      log('Session already claimed');
      await flushLogs();
      return json({ status: 'connected' });
    }

    const device_auth_id = session.device_code;
    const user_code      = session.user_code;
    log(`device_auth_id=${device_auth_id}, user_code=${user_code}`);

    // ── 4. Poll OpenAI device token endpoint ─────────────────────────────────
    log(`Calling OpenAI deviceauth/token...`);
    const pollRes = await fetch(`${OPENAI_AUTH_BASE}/deviceauth/token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ device_auth_id, user_code }),
    });

    log(`OpenAI deviceauth/token status=${pollRes.status}`);

    if (pollRes.status === 428 || pollRes.status === 400) {
      const pollBody = await pollRes.json().catch(() => ({}));
      const errCode = pollBody?.error ?? pollBody?.code ?? '';
      log(`OpenAI pending status. errCode=${errCode}, body=${JSON.stringify(pollBody)}`);

      if (errCode === 'expired_token' || errCode === 'access_denied') {
        log(`Session expired/denied by OpenAI: ${errCode}`);
        await flushLogs('expired');
        return json({ status: 'expired', reason: errCode });
      }
      await flushLogs();
      return json({ status: 'pending' });
    }

    if (!pollRes.ok) {
      const errBody = await pollRes.text();
      log(`OpenAI error status=${pollRes.status}, body=${errBody}`);
      if (pollRes.status === 401 || pollRes.status === 403) {
        await flushLogs();
        return json({ status: 'pending' });
      }
      await flushLogs('error');
      return json({ status: 'error', message: `Poll failed: ${pollRes.status}` }, 502);
    }

    // ── 5. Parse authorized response ─────────────────────────────────────────
    const pollData = await pollRes.json();
    log(`OpenAI authorized. Response keys: ${Object.keys(pollData).join(', ')}`);

    const authorization_code: string = pollData.authorization_code ?? '';
    const code_verifier: string      = pollData.code_verifier ?? '';

    if (!authorization_code || !code_verifier) {
      log(`Error: Missing authorization_code or code_verifier. Response: ${JSON.stringify(pollData)}`);
      await flushLogs('error');
      return json({ status: 'error', message: 'Unexpected poll response format' }, 502);
    }

    log('Exchanging authorization_code for tokens...');

    // ── 6. PKCE token exchange ────────────────────────────────────────────────
    const tokens = await exchangeCodeForTokens(authorization_code, code_verifier, log);
    if (!tokens) {
      log('Error: Token exchange failed');
      await flushLogs('error');
      return json({ status: 'error', message: 'Token exchange failed' }, 502);
    }

    log(`Token exchange success. access_token_len=${tokens.access_token.length}, has_refresh=${!!tokens.refresh_token}`);

    const expiresAt = tokens.expires_in
      ? new Date(Date.now() + tokens.expires_in * 1000).toISOString()
      : null;

    // ── 7. Save tokens to user_openai_links ───────────────────────────────────
    log('Upserting user_openai_links...');
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
        fallback_reason: null,
      }, { onConflict: 'user_id' });

    if (upsertErr) {
      log(`Error: DB upsert failed: ${upsertErr.message}`);
      await flushLogs('error');
      return json({ status: 'error', message: `Failed to persist tokens: ${upsertErr.message}` }, 500);
    }

    log('Marking session as claimed...');
    await supabaseAdmin
      .from('openai_device_auth_sessions')
      .update({ status: 'claimed', claimed_at: new Date().toISOString() })
      .eq('id', session_id);

    log('✅ Successfully completed connection flow');
    await flushLogs();
    return json({ status: 'connected' });

  } catch (err: any) {
    const errMsg = err?.message ?? String(err);
    const stack = err?.stack ?? '';
    log(`CRITICAL UNHANDLED EXCEPTION: ${errMsg}\nStack: ${stack}`);
    await flushLogs('error');
    return json({ error: 'Internal Server Error', message: errMsg, stack }, 500);
  }
});

// ── PKCE token exchange — uses standard OAuth authorization_code + code_verifier
async function exchangeCodeForTokens(
  authorization_code: string,
  code_verifier: string,
  log: (msg: string) => void,
): Promise<{ access_token: string; refresh_token?: string; id_token?: string; expires_in?: number } | null> {

  const params = new URLSearchParams({
    grant_type:    'authorization_code',
    code:          authorization_code,
    code_verifier: code_verifier,
    client_id:     CODEX_CLIENT_ID,
  });

  log(`Exchange Attempt 1: urlencoded POST to auth.openai.com/oauth/token`);
  try {
    let res = await fetch(OPENAI_TOKEN_URL, {
      method:  'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body:    params.toString(),
    });

    log(`Exchange Attempt 1 status=${res.status}`);

    if (!res.ok) {
      const errBody = await res.text();
      log(`Exchange Attempt 1 failed status=${res.status}, body=${errBody}`);

      log(`Exchange Attempt 2: JSON POST to auth.openai.com/oauth/token`);
      const jsonRes = await fetch(OPENAI_TOKEN_URL, {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          grant_type:    'authorization_code',
          code:          authorization_code,
          code_verifier: code_verifier,
          client_id:     CODEX_CLIENT_ID,
        }),
      });

      log(`Exchange Attempt 2 status=${jsonRes.status}`);
      if (!jsonRes.ok) {
        const errBody2 = await jsonRes.text();
        log(`Exchange Attempt 2 failed status=${jsonRes.status}, body=${errBody2}`);
        return null;
      }
      res = jsonRes;
    }

    const data = await res.json();
    if (!data.access_token) {
      log(`Exchange response missing access_token. Data keys: ${Object.keys(data).join(', ')}`);
      return null;
    }

    return data;
  } catch (err: any) {
    log(`Exchange network/parsing error: ${err?.message ?? String(err)}`);
    return null;
  }
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
