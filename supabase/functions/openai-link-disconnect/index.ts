// @ts-nocheck
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.44.2";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // ── 1. Verify caller is authenticated ────────────────────────────────────
    const authHeader = req.headers.get('Authorization');
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      console.error('[DISCONNECT] Missing or malformed Authorization header');
      return new Response(
        JSON.stringify({ success: false, error: 'Missing Authorization header' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Use anon client + user's JWT to resolve their identity
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } }
    );

    const { data: { user }, error: userError } = await supabaseClient.auth.getUser();
    if (userError || !user) {
      console.error('[DISCONNECT] Auth failed:', userError?.message ?? 'no user');
      return new Response(
        JSON.stringify({ success: false, error: 'Unauthorized' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    console.log(`[DISCONNECT] Authenticated user=${user.id}`);

    // ── 2. Delete using service role (bypasses RLS) ───────────────────────────
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    const { error: deleteError, count } = await supabaseAdmin
      .from('user_openai_links')
      .delete({ count: 'exact' })
      .eq('user_id', user.id);

    if (deleteError) {
      console.error(`[DISCONNECT] DB delete error for user=${user.id}:`, deleteError);
      return new Response(
        JSON.stringify({ success: false, error: `DB error: ${deleteError.message}` }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    console.log(`[DISCONNECT] Deleted ${count ?? 0} row(s) from user_openai_links for user=${user.id}`);

    // Also clear any pending device-auth sessions
    const { error: sessionDeleteError } = await supabaseAdmin
      .from('openai_device_auth_sessions')
      .delete()
      .eq('user_id', user.id);

    if (sessionDeleteError) {
      // Non-fatal — log and continue
      console.warn(`[DISCONNECT] Could not clear device sessions for user=${user.id}:`, sessionDeleteError.message);
    }

    // ── 3. Return success ─────────────────────────────────────────────────────
    console.log(`[DISCONNECT] Success for user=${user.id}`);
    return new Response(
      JSON.stringify({ success: true, isConnected: false }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (err: any) {
    console.error('[DISCONNECT] Unhandled exception:', err);
    return new Response(
      JSON.stringify({ success: false, error: err.message ?? 'Internal Server Error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
