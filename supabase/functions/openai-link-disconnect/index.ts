// openai-link-disconnect — Clears the user's ChatGPT connection
// Sets is_connected=false and nulls all token fields.

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

    console.log(`[openai-link-disconnect] user=${user.id} — disconnecting`);

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

    // Also clear any pending sessions
    await supabaseAdmin
      .from('openai_device_auth_sessions')
      .delete()
      .eq('user_id', user.id);

    console.log(`[openai-link-disconnect] ✅ user=${user.id} disconnected`);
    return json({ success: true });

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
