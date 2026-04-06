// @ts-nocheck
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.44.2";

// Define the CORS headers to allow requests from the Flutter client
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req: Request) => {
  // 1. Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // 2. Extract Authorization Header (Ensure user is logged into Supabase)
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Missing Authorization header' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Initialize Supabase client acting on behalf of the calling user
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } }
    );

    // Verify the JWT token is valid and get the user identity
    const { data: { user }, error: userError } = await supabaseClient.auth.getUser();
    
    if (userError || !user) {
      return new Response(JSON.stringify({ error: 'Unauthorized', details: userError?.message }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // 3. Call OpenAI Device Auth Endpoint
    const clientId = Deno.env.get('OPENAI_OAUTH_CLIENT_ID') || '<use same public client id pattern as codex>';
    
    const response = await fetch('https://auth.openai.com/api/accounts/deviceauth/usercode', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        client_id: clientId
      })
    });

    if (!response.ok) {
      const errBody = await response.text();
      console.error("OpenAI Auth Endpoint Error:", errBody);
      return new Response(JSON.stringify({ error: 'Failed to start OpenAI device auth' }), {
        status: response.status,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const data = await response.json();
    
    // OpenAI returns: device_code, user_code, verification_uri, expires_in, interval
    const { device_code, user_code, verification_uri, expires_in, interval } = data;

    // 4. Store Response in Temporary Session (Database Table)
    // We store the device_code securely so the polling endpoint can use it later without
    // sending it to the client.
    
    // We use the service_role client to interact securely with our state table
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    const expiresAt = new Date(Date.now() + (expires_in * 1000)).toISOString();

    // Upsert or insert into a holding table.
    // Table assumed: openai_device_auth_sessions (user_id PK, device_code, expires_at)
    const { error: insertError } = await supabaseAdmin
      .from('openai_device_auth_sessions')
      .upsert({
        user_id: user.id,
        device_code: device_code,
        expires_at: expiresAt
      }, { onConflict: 'user_id' });

    if (insertError) {
       console.error("Failed to persist device_code session:", insertError);
       return new Response(JSON.stringify({ error: 'Failed to store local device auth session.' }), {
         status: 500,
         headers: { ...corsHeaders, 'Content-Type': 'application/json' },
       });
    }

    // 5. Return Clean Output to Client (NO SECRETS)
    // We explicitly leave `device_code` out so it never hits the user's device.
    const safeResponse = {
      deviceCode: device_code, // Client needs this for the /poll endpoint
      userCode: user_code,
      verificationUrl: verification_uri,
      interval: interval,
      expiresIn: expires_in
    };

    return new Response(
      JSON.stringify(safeResponse),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (err: any) {
    console.error("Link Start Exception:", err);
    return new Response(JSON.stringify({ error: 'Internal Server Error' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
