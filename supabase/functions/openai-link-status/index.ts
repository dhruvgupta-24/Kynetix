// openai-link-status — Returns current connection state + provider visibility
// Never returns tokens. Client-safe fields only.

// @ts-ignore
import { createClient } from "npm:@supabase/supabase-js@2";
import { refreshAccessTokenIfNeeded } from "../shared/oauth_refresh.ts";

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
      .select('*')
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
        last_refreshed_at: null,
        fallback_reason:   null,
        test_generation_snippet: null,
      });
    }

    // Proactively refresh access token if expired or expiring
    // This keeps status checks accurate and heals expired access tokens on app open
    await refreshAccessTokenIfNeeded(supabaseAdmin, user.id, link);

    // Fetch the updated columns
    const { data: latestLink } = await supabaseAdmin
      .from('user_openai_links')
      .select('*')
      .eq('user_id', user.id)
      .maybeSingle();

    const activeLink = latestLink || link;

    // Check if token is still expired after refresh attempt
    const tokenExpired = activeLink.expires_at
      ? new Date(activeLink.expires_at) < new Date()
      : false;

    const isEffectivelyConnected = activeLink.is_connected && !tokenExpired;

    return json({
      is_connected:            isEffectivelyConnected,
      token_expired:           tokenExpired,
      active_provider:         isEffectivelyConnected ? 'user_chatgpt' : 'openrouter',
      active_model:            isEffectivelyConnected ? (activeLink.selected_model ?? null) : null,
      selected_model:          activeLink.selected_model ?? null,
      last_provider_used:      activeLink.last_provider_used ?? null,
      last_used_at:            activeLink.last_used_at ?? null,
      connected_at:            activeLink.connected_at ?? null,
      expires_at:              activeLink.expires_at ?? null,
      model_discovery_verified: activeLink.model_discovery_verified ?? false,
      discovered_models:       activeLink.discovered_models ?? null,
      discovery_timestamp:     activeLink.discovery_timestamp ?? null,
      last_refreshed_at:       activeLink.last_refreshed_at ?? null,
      fallback_reason:         activeLink.fallback_reason ?? null,
      test_generation_snippet:  activeLink.test_generation_snippet ?? null,
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
