// openai-link-siwc: store a "Sign in with ChatGPT" (plan usage) link.
//
// The app runs OAuth 2.0 + PKCE in the system browser and exchanges the code
// on-device (public client, no secret). It then posts the token set here right
// away. This function:
//   1. Verifies the caller's Supabase JWT.
//   2. Checks the grant includes chatgpt.tokens.use.direct.
//   3. Verifies the ID token: JWKS signature, iss, aud == issued client_id,
//      exp, and the attempt's nonce.
//   4. Lists the account's models (visibility == "list") and confirms one
//      answers on POST /v1/responses, surfacing "not eligible" up front.
//   5. Upserts user_openai_links with auth_method = 'siwc'.
//   6. Returns only non-secret fields. Tokens never go back to the client.
//
// Never logs tokens or upstream bodies.
// Requires migration 20261016000000_siwc_plan_usage.sql.

// @ts-ignore
import { createClient } from "npm:@supabase/supabase-js@2";
// @ts-ignore
import { createRemoteJWKSet, jwtVerify } from "npm:jose@5.9.6";
import { AUTH_HEADERS_TIMEOUT_MS, AUTH_TOTAL_TIMEOUT_MS, timedFetch } from "../shared/timed_fetch.ts";
import {
  hasPlanScope,
  selectSiwcModel,
  SIWC_ISSUER,
  SIWC_RESPONSES_URL,
  PLAN_PAUSE_MS,
} from "../shared/siwc.ts";

declare const Deno: any;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const DISCOVERY_URL = `${SIWC_ISSUER}/.well-known/openid-configuration`;
const JWKS_FALLBACK = `${SIWC_ISSUER}/.well-known/jwks.json`;

let jwks: ReturnType<typeof createRemoteJWKSet> | null = null;

async function getJwks() {
  if (jwks) return jwks;
  let uri = JWKS_FALLBACK;
  try {
    const res = await timedFetch(DISCOVERY_URL, {}, AUTH_HEADERS_TIMEOUT_MS, AUTH_TOTAL_TIMEOUT_MS);
    if (res.ok) {
      const conf = await res.json();
      if (typeof conf?.jwks_uri === 'string') uri = conf.jwks_uri;
    }
  } catch { /* use fallback */ }
  jwks = createRemoteJWKSet(new URL(uri));
  return jwks;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  try {
    // ── 1. Caller ───────────────────────────────────────────────────────────
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return json({ error: 'unauthorized' }, 401);

    const jwt = authHeader.replace('Bearer ', '').trim();
    const supabaseAnon = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: `Bearer ${jwt}` } } },
    );
    const { data: { user }, error: userErr } = await supabaseAnon.auth.getUser();
    if (userErr || !user) return json({ error: 'unauthorized' }, 401);

    // ── 2. Payload ──────────────────────────────────────────────────────────
    const body = await req.json().catch(() => ({}));
    const accessToken  = str(body.access_token);
    const refreshToken = str(body.refresh_token);
    const idToken      = str(body.id_token);
    const clientId     = str(body.client_id);
    const nonce        = str(body.nonce);
    const scope        = str(body.scope);
    const hostId       = str(body.ext_agent_host_id);
    const expiresIn    = Number(body.expires_in) > 0 ? Number(body.expires_in) : 3600;

    if (!accessToken || !idToken || !clientId || !nonce) {
      return json({ error: 'bad_request' }, 400);
    }
    if (clientId === 'dynamic_agent_client') {
      return json({ error: 'registration_incomplete' }, 400);
    }
    if (!hasPlanScope(scope)) {
      return json({ error: 'plan_scope_missing' }, 400);
    }

    // ── 3. ID token ─────────────────────────────────────────────────────────
    let subject: string;
    let email: string | null = null;
    try {
      const { payload } = await jwtVerify(idToken, await getJwks(), {
        issuer:   SIWC_ISSUER,
        audience: clientId,
      });
      if (payload.nonce !== nonce) throw new Error('nonce');
      if (typeof payload.sub !== 'string' || !payload.sub) throw new Error('sub');
      subject = payload.sub;
      if (typeof payload.email === 'string') email = payload.email;
    } catch (e: any) {
      console.warn(`[openai-link-siwc] user=${user.id} id_token rejected (${e?.code ?? e?.message ?? 'invalid'})`);
      return json({ error: 'invalid_id_token' }, 400);
    }

    // ── 4. Plan access + model ──────────────────────────────────────────────
    const selection = await selectSiwcModel(accessToken);
    console.log(`[openai-link-siwc] user=${user.id} models=${selection.allSlugs.length} ok=${selection.ok} kind=${selection.errorKind ?? '-'} code=${selection.errorCode ?? '-'}`);

    if (!selection.ok) {
      const error = selection.errorKind === 'not_eligible' ? 'not_eligible'
        : selection.errorKind === 'config' ? 'not_eligible'
        : selection.errorKind === 'no_models' ? 'no_models'
        : selection.errorKind === 'auth' ? 'not_authorized'
        : 'upstream_error';
      // Nothing is stored: a not-eligible account shouldn't be retried or
      // looped through OAuth, and an existing link stays as it was.
      return json({ error }, error === 'upstream_error' ? 502 : 403);
    }

    // ── 5. Persist (server-side only) ───────────────────────────────────────
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    );
    const now = new Date();
    const { error: upsertErr } = await supabaseAdmin
      .from('user_openai_links')
      .upsert({
        user_id:                  user.id,
        is_connected:             true,
        auth_method:              'siwc',
        oauth_client_id:          clientId,
        granted_scopes:           scope,
        openai_subject:           subject,
        ext_agent_host_id:        hostId || null,
        access_token:             accessToken,
        refresh_token:            refreshToken || null,
        id_token:                 idToken,
        expires_at:               new Date(now.getTime() + expiresIn * 1000).toISOString(),
        connected_at:             now.toISOString(),
        updated_at:               now.toISOString(),
        last_refreshed_at:        null,
        refresh_lock_until:       null,
        plan_paused_until:        selection.usageLimited ? new Date(now.getTime() + PLAN_PAUSE_MS).toISOString() : null,
        fallback_reason:          selection.usageLimited ? 'usage_limit' : null,
        selected_model:           selection.selectedModel,
        model_discovery_verified: true,
        discovered_models: {
          all:          selection.allSlugs,
          chat_capable: selection.allSlugs,
          endpoint:     SIWC_RESPONSES_URL,
          tried:        selection.tried,
        },
        discovery_timestamp:      now.toISOString(),
        test_generation_snippet:  selection.testSnippet,
      }, { onConflict: 'user_id' });

    if (upsertErr) {
      console.error(`[openai-link-siwc] user=${user.id} upsert failed: ${upsertErr.code ?? ''} ${upsertErr.message}`);
      return json({ error: 'storage_failed' }, 500);
    }

    // Clear any half-finished device-code session.
    await supabaseAdmin.from('openai_device_auth_sessions').delete().eq('user_id', user.id);

    console.log(`[openai-link-siwc] user=${user.id} linked (siwc) model=${selection.selectedModel} usage_limited=${selection.usageLimited}`);
    return json({
      status:         'connected',
      auth_method:    'siwc',
      selected_model: selection.selectedModel,
      usage_limited:  selection.usageLimited,
      email,
    });
  } catch (err: any) {
    console.error(`[openai-link-siwc] unhandled: ${err?.name ?? 'Error'}`);
    return json({ error: 'internal_error' }, 500);
  }
});

function str(v: unknown): string {
  return typeof v === 'string' ? v.trim() : '';
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
