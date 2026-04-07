// @ts-ignore
import { createClient } from "npm:@supabase/supabase-js@2.44.2";

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
    if (!authHeader) {
      console.error("[openai-link-poll] Missing Authorization header");
      return new Response(JSON.stringify({ error: 'Missing Authorization header' }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const token = authHeader.replace('Bearer ', '').trim();
    if (!token) {
      console.error("[openai-link-poll] Authorization header is malformed or empty");
      return new Response(JSON.stringify({ error: 'Malformed Authorization header' }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? ''
    );

    const { data: { user }, error: userError } = await supabaseClient.auth.getUser(token);
    if (userError || !user) {
      console.error(`[openai-link-poll] Auth failed. Error:`, userError?.message || 'No user returned');
      return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    // Fetch the pending session for this user
    const { data: sessionData, error: sessionError } = await supabaseAdmin
      .from('openai_device_auth_sessions')
      .select('device_code, status')
      .eq('user_id', user.id)
      .single();

    if (sessionError || !sessionData) {
      console.error(`[openai-link-poll] Session lookup error for user ${user.id}:`, JSON.stringify(sessionError));
      return new Response(JSON.stringify({ error: 'No active authentication session found' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    if (sessionData.status === 'connected') {
      return new Response(JSON.stringify({ status: 'connected' }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }
    if (sessionData.status === 'expired') {
      return new Response(JSON.stringify({ status: 'expired' }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const clientId = "app_EMoamEEZ73f0CkXaXp7hrann"; // Kynetix app
    console.log(`[openai-link-poll] Polling OpenAI for user: ${user.id}`);

    const tokenResponse = await fetch('https://auth.openai.com/oauth/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        client_id: clientId,
        grant_type: 'urn:ietf:params:oauth:grant-type:device_code',
        device_code: sessionData.device_code
      })
    });

    console.log(`[openai-link-poll] OpenAI response status: ${tokenResponse.status}`);

    if (!tokenResponse.ok) {
      const errBody = await tokenResponse.json().catch(() => null);
      if (errBody && errBody.error === 'authorization_pending') {
        console.log(`[openai-link-poll] Still pending for user ${user.id}`);
        return new Response(JSON.stringify({ status: 'pending' }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
      } else if (errBody && (errBody.error === 'expired_token' || errBody.error === 'invalid_grant')) {
        console.log(`[openai-link-poll] Token expired/invalid for user ${user.id}. Marking as expired.`);
        await supabaseAdmin.from('openai_device_auth_sessions').update({ status: 'expired' }).eq('user_id', user.id);
        return new Response(JSON.stringify({ status: 'expired' }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
      }

      console.error(`[openai-link-poll] Fetch failed. Body:`, JSON.stringify(errBody));
      return new Response(JSON.stringify({ error: 'Failed to exchange authorization code' }), { status: tokenResponse.status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const tokenData = await tokenResponse.json();

    // Store tokens
    const { error: updateError } = await supabaseAdmin
      .from('openai_device_auth_sessions')
      .update({
        access_token: tokenData.access_token,
        refresh_token: tokenData.refresh_token,
        id_token: tokenData.id_token,
        connected_at: new Date().toISOString(),
        status: 'connected'
      })
      .eq('user_id', user.id);

    if (updateError) {
      console.error(`[openai-link-poll] DB token update error for user ${user.id}:`, JSON.stringify(updateError));
      return new Response(JSON.stringify({ error: 'Failed to store tokens' }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    console.log(`[openai-link-poll] Successfully connected user ${user.id}`);

    return new Response(
      JSON.stringify({ status: 'connected' }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (err: any) {
    console.error(`[openai-link-poll] Exception:`, err);
    return new Response(JSON.stringify({ error: 'Internal Server Error' }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
});
