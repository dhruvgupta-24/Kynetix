// openai-link-disconnect — Clears the user's ChatGPT connection
// Sets is_connected=false and nulls all token fields.
//
// Sign in with ChatGPT links are first revoked at OpenAI (best effort, per
// the SIWC sign-out docs; see shared/siwc.ts). The local tokens are cleared
// either way; the response says whether remote revocation was confirmed
// (`remote_revoked`: true / false, or null when nothing was revocable, e.g.
// legacy device-code links, which have no documented revocation).

// @ts-ignore
import { createClient } from "npm:@supabase/supabase-js@2";
import { revokeSiwcLink } from "../shared/siwc.ts";

declare const Deno: any;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return json({ error: 'Missing Authorization header' }, 401);

    const jwt = authHeader.replace('Bearer ', '').trim();
    const supabaseAnon = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: `Bearer ${jwt}` } } },
    );
    const { data: { user }, error: userErr } = await supabaseAnon.auth.getUser();
    if (userErr || !user) return json({ error: 'Unauthorized' }, 401);

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    );

    console.log(`[openai-link-disconnect] user=${user.id} — disconnecting`);

    // Revoke at OpenAI before the tokens are cleared (best effort).
    let revoke: 'revoked' | 'failed' | 'skipped' = 'skipped';
    {
      const { data: link, error: linkErr } = await supabaseAdmin
        .from('user_openai_links')
        .select('auth_method, refresh_token, oauth_client_id')
        .eq('user_id', user.id)
        .maybeSingle();
      if (linkErr) console.warn(`[openai-link-disconnect] link read failed: ${linkErr.code ?? ''}`);
      else revoke = await revokeSiwcLink(link);
      console.log(`[openai-link-disconnect] user=${user.id} remote revoke=${revoke}`);
    }

    const { error } = await supabaseAdmin
      .from('user_openai_links')
      .update({
        is_connected:            false,
        access_token:            null,
        refresh_token:           null,
        id_token:                null,
        expires_at:              null,
        selected_model:          null,
        model_discovery_verified: false,
        last_provider_used:      null,
        updated_at:              new Date().toISOString(),
      })
      .eq('user_id', user.id);

    if (error) {
      console.error(`[openai-link-disconnect] DB update failed: ${error.message}`);
      return json({ error: 'Failed to disconnect' }, 500);
    }

    // Sign in with ChatGPT fields. Best-effort so disconnect still works before
    // the siwc migration. oauth_client_id is kept on purpose: the docs say to
    // reuse the issued client id when the user signs in again.
    {
      const { error: siwcErr } = await supabaseAdmin
        .from('user_openai_links')
        .update({ granted_scopes: null, plan_paused_until: null, refresh_lock_until: null, openai_subject: null })
        .eq('user_id', user.id);
      if (siwcErr) console.warn(`[openai-link-disconnect] siwc fields not cleared: ${siwcErr.code ?? ''}`);
    }

    // Also clear any pending sessions
    await supabaseAdmin
      .from('openai_device_auth_sessions')
      .delete()
      .eq('user_id', user.id);

    console.log(`[openai-link-disconnect] ✅ user=${user.id} disconnected`);
    return json({ success: true, remote_revoked: revoke === 'skipped' ? null : revoke === 'revoked' });

  } catch (err: any) {
    console.error(`[openai-link-disconnect] Unhandled: ${err?.message ?? err}`);
    return json({ error: 'Internal Server Error' }, 500);
  }
});

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
