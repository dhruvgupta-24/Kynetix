// openai-link-start — Phase A: Initiate Codex device-code auth flow
//
// Flow:
//   1. Verify caller is a logged-in Kynetix user (Supabase JWT)
//   2. POST to OpenAI deviceauth/usercode with hardcoded client_id
//   3. Save pending session to openai_device_auth_sessions
//   4. Return { session_id, user_code, verification_url, interval_seconds, expires_at }
//      to the Flutter client — NEVER tokens, NEVER device_auth_id
//
// Security: this function has verify_jwt=false because we manually verify
// the Supabase JWT using getUser(), which supports ES256 tokens correctly.

// @ts-ignore
import { createClient } from "npm:@supabase/supabase-js@2";

declare const Deno: any;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// Codex CLI client_id — same as openai/codex repo
const CODEX_CLIENT_ID = 'app_EMoamEEZ73f0CkXaXp7hrann';
const OPENAI_AUTH_BASE = 'https://auth.openai.com/api/accounts';
const VERIFICATION_URL = 'https://chatgpt.com/device';

// Session TTL: 15 minutes (OpenAI device codes typically expire in 15m)
const SESSION_TTL_MINUTES = 15;

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // ── 1. Verify Supabase JWT ────────────────────────────────────────────────
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
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
      console.error(`[openai-link-start] Auth failed: ${userErr?.message ?? 'no user'}`);
      return json({ error: 'Unauthorized' }, 401);
    }

    console.log(`[openai-link-start] user=${user.id} — requesting device code`);

    // ── 2. Request user_code from OpenAI device auth endpoint ────────────────
    const deviceRes = await fetch(`${OPENAI_AUTH_BASE}/deviceauth/usercode`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ client_id: CODEX_CLIENT_ID }),
    });

    if (!deviceRes.ok) {
      const errBody = await deviceRes.text();
      console.error(`[openai-link-start] OpenAI deviceauth failed: ${deviceRes.status} ${errBody.slice(0, 300)}`);

      if (deviceRes.status === 404) {
        return json({
          error: 'device_code_disabled',
          message: 'Device code authorization is not enabled on this ChatGPT account. Go to chatgpt.com/settings → Security → Enable "Device code authorization".',
        }, 403);
      }
      return json({ error: 'OpenAI device auth request failed', status: deviceRes.status }, 502);
    }

    const deviceData = await deviceRes.json();
    const device_auth_id: string = deviceData.device_auth_id ?? deviceData.deviceAuthId ?? '';
    const user_code: string = deviceData.user_code ?? deviceData.usercode ?? '';
    const interval_raw: string | number = deviceData.interval ?? 5;
    const interval_seconds: number = typeof interval_raw === 'string'
      ? parseInt(interval_raw.trim(), 10)
      : Number(interval_raw);

    if (!device_auth_id || !user_code) {
      console.error(`[openai-link-start] Unexpected response shape: ${JSON.stringify(deviceData).slice(0, 200)}`);
      return json({ error: 'Unexpected response from OpenAI device auth endpoint' }, 502);
    }

    console.log(`[openai-link-start] Got user_code=${user_code} interval=${interval_seconds}s`);

    // ── 3. Save pending session to DB ─────────────────────────────────────────
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    );

    const expiresAt = new Date(Date.now() + SESSION_TTL_MINUTES * 60 * 1000).toISOString();

    // Delete any stale pending sessions for this user first
    await supabaseAdmin
      .from('openai_device_auth_sessions')
      .delete()
      .eq('user_id', user.id)
      .eq('status', 'pending');

    const { data: session, error: sessionErr } = await supabaseAdmin
      .from('openai_device_auth_sessions')
      .insert({
        user_id:          user.id,
        device_code:      device_auth_id,   // stores device_auth_id
        user_code:        user_code,
        verification_url: VERIFICATION_URL,
        interval_seconds: interval_seconds,
        expires_at:       expiresAt,
        status:           'pending',
      })
      .select('id')
      .single();

    if (sessionErr || !session) {
      console.error(`[openai-link-start] DB insert failed: ${sessionErr?.message}`);
      return json({ error: 'Failed to save device auth session' }, 500);
    }

    console.log(`[openai-link-start] Session saved: ${session.id}`);

    // ── 4. Return safe payload to client (NO device_auth_id, NO tokens) ──────
    return json({
      success:          true,
      session_id:       session.id,        // opaque ID, client uses this to poll
      user_code:        user_code,         // user enters this at chatgpt.com/device
      verification_url: VERIFICATION_URL,
      interval_seconds: interval_seconds,
      expires_at:       expiresAt,
    });

  } catch (err: any) {
    console.error(`[openai-link-start] Unhandled: ${err?.message ?? err}`);
    return json({ error: 'Internal Server Error' }, 500);
  }
});

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
