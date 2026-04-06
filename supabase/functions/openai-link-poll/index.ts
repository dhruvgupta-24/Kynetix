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
    // 1. Verify User is Authenticated
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Missing Authorization header' }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } }
    );

    const { data: { user }, error: userError } = await supabaseClient.auth.getUser();
    if (userError || !user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    // Parse Request Body
    const body = await req.json().catch(() => ({}));
    const deviceCode = body.device_code;
    
    if (!deviceCode) {
      return new Response(JSON.stringify({ error: 'device_code is required' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const clientId = Deno.env.get('OPENAI_OAUTH_CLIENT_ID') || '<use same public client id pattern as codex>';

    // 2. Poll OpenAI Device Auth Token Endpoint
    const pollResponse = await fetch('https://auth.openai.com/api/accounts/deviceauth/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        client_id: clientId,
        device_code: deviceCode
      })
    });

    const pollData = await pollResponse.json().catch(() => ({}));

    // Handle Pending or Expired states
    // Standard OAuth might return 400 with {"error": "authorization_pending"}, but we handle both object styles.
    const statusOrError = pollData.status || pollData.error;
    if (statusOrError === 'authorization_pending' || statusOrError === 'pending') {
      return new Response(JSON.stringify({ status: 'pending' }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }
    
    if (statusOrError === 'expired_token' || statusOrError === 'expired') {
      return new Response(JSON.stringify({ status: 'expired' }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    // 3. If authorized, extract authorization code. 
    // In some flows `deviceauth/token` returns the final tokens directly. 
    // If we receive tokens here, we skip the exchange.
    let tokens = null;

    if (pollData.authorization_code || pollData.code) {
      // We got an auth code, exchange it
      const authCode = pollData.authorization_code || pollData.code;
      const redirectUri = Deno.env.get('OPENAI_OAUTH_REDIRECT_URI') || 'com.openai.chat://auth0.openai.com/ios/com.openai.chat/callback';

      const tokenResponse = await fetch('https://auth.openai.com/oauth/token', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          client_id: clientId,
          grant_type: 'authorization_code',
          code: authCode,
          redirect_uri: redirectUri
        })
      });

      if (!tokenResponse.ok) {
        const errorText = await tokenResponse.text();
        console.error("Token Exchange Failed:", errorText);
        return new Response(JSON.stringify({ error: 'Failed to exchange authorization code' }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
      }

      tokens = await tokenResponse.json();
    } else if (pollData.access_token) {
      // The device polling endpoint returned the tokens directly
      tokens = pollData;
    } else {
      // Unknown state
      console.error("Unknown poll response:", pollData);
      return new Response(JSON.stringify({ error: 'Unexpected response from OpenAI', details: pollData }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    // 4. Store Tokens in Supabase Database
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    const expiresAt = tokens.expires_in 
      ? new Date(Date.now() + (tokens.expires_in * 1000)).toISOString()
      : null;

    const { error: upsertError } = await supabaseAdmin.from('user_openai_links').upsert({
      user_id: user.id,
      access_token: tokens.access_token,
      refresh_token: tokens.refresh_token,
      id_token: tokens.id_token,
      expires_at: expiresAt,
      updated_at: new Date().toISOString()
    }, { onConflict: 'user_id' });

    if (upsertError) {
      console.error("Database Upsert Failed:", upsertError);
      return new Response(JSON.stringify({ error: 'Failed to save linked connection' }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    // Optionally cleanup the old session in `openai_device_auth_sessions` since we are connected
    await supabaseAdmin.from('openai_device_auth_sessions').delete().eq('user_id', user.id);

    // 5. Return Connected Status
    return new Response(JSON.stringify({ status: 'connected' }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

  } catch (err: any) {
    console.error("Poll Exception:", err);
    return new Response(JSON.stringify({ error: err.message || 'Internal Server Error' }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
});
