// openai-link-status — Returns current connection state + provider visibility
// Never returns tokens. Client-safe fields only.

// @ts-ignore
import { createClient } from "npm:@supabase/supabase-js@2";

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

    const { data: link } = await supabaseAdmin
      .from('user_openai_links')
      .select(
        'is_connected, connected_at, expires_at, updated_at, ' +
        'selected_model, discovered_models, discovery_timestamp, ' +
        'model_discovery_verified, last_provider_used, last_used_at, ' +
        'responses_api_blocked'
      )
      .eq('user_id', user.id)
      .maybeSingle();

    if (!link) {
      // No row at all — never connected
      return json({
        is_connected:      false,
        active_provider:   'openrouter',
        active_model:      null,
        selected_model:    null,
        last_provider_used: null,
        last_used_at:      null,
        connected_at:      null,
        expires_at:        null,
        model_discovery_verified: false,
        discovered_models: null,
        discovery_timestamp: null,
      });
    }

    // Check if token is expired
    const tokenExpired = link.expires_at
      ? new Date(link.expires_at) < new Date()
      : false;

    const isEffectivelyConnected = link.is_connected && !tokenExpired;

    return json({
      is_connected:            isEffectivelyConnected,
      token_expired:           tokenExpired,
      active_provider:         isEffectivelyConnected ? 'user_chatgpt' : 'openrouter',
      active_model:            isEffectivelyConnected ? (link.selected_model ?? null) : null,
      selected_model:          link.selected_model ?? null,
      last_provider_used:      link.last_provider_used ?? null,
      last_used_at:            link.last_used_at ?? null,
      connected_at:            link.connected_at ?? null,
      expires_at:              link.expires_at ?? null,
      model_discovery_verified: link.model_discovery_verified ?? false,
      discovered_models:       link.discovered_models ?? null,
      discovery_timestamp:     link.discovery_timestamp ?? null,
    });

  } catch (err: any) {
    console.error(`[openai-link-status] Unhandled: ${err?.message ?? err}`);
    return json({ error: 'Internal Server Error' }, 500);
  }
});

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
