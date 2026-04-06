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
      return new Response(JSON.stringify({ error: 'Missing Authorization header' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const { code, state } = await req.json();
    if (!code || !state) {
      return new Response(JSON.stringify({ error: 'Missing code or state parameters' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } }
    );

    const { data: { user }, error: userError } = await supabaseClient.auth.getUser();
    if (userError || !user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    // Get session to validate state and retrieve code_verifier
    const { data: sessionData, error: sessionError } = await supabaseAdmin
      .from('openai_device_auth_sessions')
      .select('*')
      .eq('user_id', user.id)
      .single();

    if (sessionError || !sessionData) {
      console.error("Session lookup error:", sessionError);
      return new Response(JSON.stringify({ error: 'No active authentication session found' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    if (sessionData.oauth_state !== state) {
      console.error("State mismatch. Expected", sessionData.oauth_state, "but got", state);
      return new Response(JSON.stringify({ error: 'Invalid state parameter' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Exchange the code for the tokens
    const clientId = "app_EMoamEEZ73f0CkXaXp7hrann";
    const redirectUri = "kynetix://openai-auth/callback";

    const tokenResponse = await fetch('https://auth.openai.com/oauth/token', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        client_id: clientId,
        grant_type: 'authorization_code',
        code: code,
        redirect_uri: redirectUri,
        code_verifier: sessionData.code_verifier
      })
    });

    if (!tokenResponse.ok) {
      const errBody = await tokenResponse.text();
      console.error("OpenAI token exchange error:", errBody);
      return new Response(JSON.stringify({ error: 'Failed to exchange authorization code' }), {
        status: tokenResponse.status,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const tokenData = await tokenResponse.json();

    // Store the tokens
    const { error: updateError } = await supabaseAdmin
      .from('openai_device_auth_sessions')
      .update({
        access_token: tokenData.access_token,
        refresh_token: tokenData.refresh_token,
        id_token: tokenData.id_token,
        connected_at: new Date().toISOString(),
        expires_at: tokenData.expires_in ? new Date(Date.now() + tokenData.expires_in * 1000).toISOString() : null,
      })
      .eq('user_id', user.id);

    if (updateError) {
      console.error("DB token update error:", updateError);
      return new Response(JSON.stringify({ error: 'Failed to store tokens' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    return new Response(
      JSON.stringify({ success: true }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (err: any) {
    console.error("Link Finish Exception:", err);
    return new Response(JSON.stringify({ error: 'Internal Server Error' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
