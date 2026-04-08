// @ts-ignore
import { createClient } from "npm:@supabase/supabase-js@2.44.2";

declare const Deno: any;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// Source: openai/codex codex-rs/login/src/device_code_auth.rs
// Poll endpoint: POST /api/accounts/deviceauth/token  (body: JSON {device_auth_id, user_code})
// On pending: returns 403 or 404 — keep polling
// On approval: returns { authorization_code, code_challenge, code_verifier }
// Token exchange: POST /oauth/token  (body: form-encoded, grant_type=authorization_code)
const OPENAI_ISSUER       = 'https://auth.openai.com';
const POLL_URL            = `${OPENAI_ISSUER}/api/accounts/deviceauth/token`;
const TOKEN_URL           = `${OPENAI_ISSUER}/oauth/token`;
const DEVICE_REDIRECT_URI = `${OPENAI_ISSUER}/deviceauth/callback`;
const CLIENT_ID           = 'app_EMoamEEZ73f0CkXaXp7hrann';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      console.error('[openai-link-poll] Missing Authorization header');
      return new Response(JSON.stringify({ error: 'Missing Authorization header' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const token = authHeader.replace('Bearer ', '').trim();
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? ''
    );
    const { data: { user }, error: userError } = await supabaseClient.auth.getUser(token);
    if (userError || !user) {
      console.error(`[openai-link-poll] Auth failed:`, userError?.message);
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    // ── 1. Fetch the pending session ──────────────────────────────────────
    const { data: session, error: sessionError } = await supabaseAdmin
      .from('openai_device_auth_sessions')
      .select('id, device_code, user_code, status, interval_seconds, expires_at')
      .eq('user_id', user.id)
      .order('created_at', { ascending: false })
      .limit(1)
      .single();

    console.log(`[openai-link-poll] user=${user.id} session=${JSON.stringify({
      id: session?.id,
      status: session?.status,
      device_auth_id: session?.device_code,
      user_code: session?.user_code,
    })}`);

    if (sessionError || !session) {
      console.error(`[openai-link-poll] No session found for user ${user.id}:`, sessionError?.message);
      return new Response(JSON.stringify({ error: 'No active authentication session found' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // ── 2. Already connected — read from user_openai_links ───────────────
    if (session.status === 'connected') {
      console.log(`[openai-link-poll] Already connected for user ${user.id}`);
      return new Response(JSON.stringify({ status: 'connected' }), {
        status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    if (session.status === 'expired' || new Date(session.expires_at) < new Date()) {
      await supabaseAdmin
        .from('openai_device_auth_sessions')
        .update({ status: 'expired' })
        .eq('id', session.id);
      return new Response(JSON.stringify({ status: 'expired' }), {
        status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // ── 3. Poll OpenAI for token approval ─────────────────────────────────
    // Endpoint: POST /api/accounts/deviceauth/token
    // Body: JSON { device_auth_id, user_code }
    // Source: openai/codex device_code_auth.rs line 109-148
    const pollBody = JSON.stringify({
      device_auth_id: session.device_code, // stored as device_code in DB
      user_code:      session.user_code,
    });

    console.log(`[openai-link-poll] POST ${POLL_URL} body=${pollBody}`);

    const pollRes = await fetch(POLL_URL, {
      method:  'POST',
      headers: { 'Content-Type': 'application/json' },
      body:    pollBody,
    });

    const pollRawBody = await pollRes.text();
    console.log(`[openai-link-poll] poll status=${pollRes.status} body=${pollRawBody}`);

    // 403 or 404 = authorization still pending; user hasn't approved yet
    if (pollRes.status === 403 || pollRes.status === 404) {
      return new Response(JSON.stringify({ status: 'pending' }), {
        status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    if (!pollRes.ok) {
      // Check for standard OAuth errors
      let errBody: any = {};
      try { errBody = JSON.parse(pollRawBody); } catch (_) {}
      if (errBody.error === 'authorization_pending' || errBody.error === 'slow_down') {
        return new Response(JSON.stringify({ status: 'pending' }), {
          status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }
      if (errBody.error === 'expired_token' || errBody.error === 'invalid_grant') {
        await supabaseAdmin
          .from('openai_device_auth_sessions')
          .update({ status: 'expired' })
          .eq('id', session.id);
        return new Response(JSON.stringify({ status: 'expired' }), {
          status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }
      console.error(`[openai-link-poll] Unexpected poll error ${pollRes.status}: ${pollRawBody}`);
      return new Response(JSON.stringify({ status: 'pending', debug: pollRawBody }), {
        status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // ── 4. Poll succeeded — response contains authorization_code + code_verifier
    // Source: openai/codex device_code_auth.rs CodeSuccessResp struct (line 58-62)
    let pollData: any;
    try { pollData = JSON.parse(pollRawBody); } catch (_) {
      console.error(`[openai-link-poll] Poll returned non-JSON: ${pollRawBody}`);
      return new Response(JSON.stringify({ error: 'Bad poll response from OpenAI' }), {
        status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const { authorization_code, code_verifier } = pollData;
    if (!authorization_code || !code_verifier) {
      console.error(`[openai-link-poll] Poll success but missing authorization_code/code_verifier: ${pollRawBody}`);
      return new Response(JSON.stringify({ error: 'Incomplete poll response from OpenAI' }), {
        status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // ── 5. Exchange authorization_code for tokens ─────────────────────────
    // POST /oauth/token  form-encoded
    // Source: openai/codex server.rs exchange_code_for_tokens() line 710-719
    const tokenBody = new URLSearchParams({
      grant_type:    'authorization_code',
      code:          authorization_code,
      redirect_uri:  DEVICE_REDIRECT_URI,
      client_id:     CLIENT_ID,
      code_verifier: code_verifier,
    }).toString();

    console.log(`[openai-link-poll] POST ${TOKEN_URL} (code exchange)`);
    const tokenRes = await fetch(TOKEN_URL, {
      method:  'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body:    tokenBody,
    });
    const tokenRaw = await tokenRes.text();
    console.log(`[openai-link-poll] token exchange status=${tokenRes.status} body=${tokenRaw}`);

    if (!tokenRes.ok) {
      console.error(`[openai-link-poll] Token exchange failed ${tokenRes.status}: ${tokenRaw}`);
      return new Response(JSON.stringify({ error: 'Token exchange failed', detail: tokenRaw }), {
        status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    let tokenData: any;
    try { tokenData = JSON.parse(tokenRaw); } catch (_) {
      console.error(`[openai-link-poll] Token exchange non-JSON: ${tokenRaw}`);
      return new Response(JSON.stringify({ error: 'Bad token response from OpenAI' }), {
        status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // ── 6. Persist tokens in user_openai_links + mark session connected ───
    // openai-link-status reads user_openai_links — must write there.
    const now = new Date().toISOString();

    const { error: upsertError } = await supabaseAdmin
      .from('user_openai_links')
      .upsert({
        user_id:       user.id,
        is_connected:  true,
        access_token:  tokenData.access_token,
        refresh_token: tokenData.refresh_token,
        id_token:      tokenData.id_token ?? null,
        expires_at:    tokenData.expires_in
          ? new Date(Date.now() + tokenData.expires_in * 1000).toISOString()
          : null,
        connected_at:  now,
        updated_at:    now,
      }, { onConflict: 'user_id' });

    if (upsertError) {
      console.error(`[openai-link-poll] user_openai_links upsert error for ${user.id}:`, upsertError.message);
      return new Response(JSON.stringify({ error: 'Failed to persist tokens' }), {
        status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Mark device session as connected (clean reference)
    await supabaseAdmin
      .from('openai_device_auth_sessions')
      .update({ status: 'connected', access_token: tokenData.access_token })
      .eq('id', session.id);

    console.log(`[openai-link-poll] ✅ Connected user ${user.id}`);
    return new Response(JSON.stringify({ status: 'connected' }), {
      status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  } catch (err: any) {
    console.error(`[openai-link-poll] Exception:`, err?.message ?? err);
    return new Response(JSON.stringify({ error: 'Internal Server Error' }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
