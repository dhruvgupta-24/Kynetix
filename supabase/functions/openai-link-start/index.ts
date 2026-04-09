import { createClient } from "https://esm.sh/@supabase/supabase-js@2.44.2";

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
      console.error("[openai-link-start] Missing Authorization header");
      return new Response(JSON.stringify({ error: 'Missing Authorization header' }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const token = authHeader.replace('Bearer ', '').trim();
    if (!token) {
      console.error("[openai-link-start] Authorization header is malformed or empty");
      return new Response(JSON.stringify({ error: 'Malformed Authorization header' }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? ''
    );

    const { data: { user }, error: userError } = await supabaseClient.auth.getUser(token);
    if (userError || !user) {
      console.error(`[openai-link-start] Auth failed. Error:`, userError?.message || 'No user returned');
      return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const clientId = "app_EMoamEEZ73f0CkXaXp7hrann"; // Kynetix app
    const deviceAuthUrl = "https://auth.openai.com/oauth/device/code";

    console.log(`[openai-link-start] Initiating device flow for user: ${user.id}`);

    // Request device code
    const openAiResponse = await fetch(deviceAuthUrl, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: clientId,
        scope: "openid profile email offline_access api.connectors.read api.connectors.invoke api.responses.write",

      }),
    });

    console.log(`[openai-link-start] OpenAI response status: ${openAiResponse.status}`);

    if (!openAiResponse.ok) {
      const respText = await openAiResponse.text();
      console.error(`[openai-link-start] OpenAI rejected device code request. HTTP ${openAiResponse.status}. Body: ${respText}`);
      return new Response(JSON.stringify({ error: 'OpenAI Device request failed' }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const data = await openAiResponse.json();

    // Standardize variables
    const normalizedDeviceCode = data.device_code ?? data.device_auth_id;
    const normalizedUserCode = data.user_code;
    const normalizedVerificationUrl = data.verification_uri ?? data.verification_url ?? "https://chatgpt.com/auth/device";
    const normalizedInterval = data.interval ?? data.interval_seconds ?? 5;
    const normalizedExpiresAt = data.expires_at ?? new Date(Date.now() + (data.expires_in ?? 1800) * 1000).toISOString();

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    const upsertPayload = {
      user_id: user.id,
      device_code: normalizedDeviceCode,
      user_code: normalizedUserCode,
      verification_url: normalizedVerificationUrl,
      interval_seconds: normalizedInterval,
      expires_at: normalizedExpiresAt,
      status: 'pending'
    };

    const { error: insertError } = await supabaseAdmin
      .from('openai_device_auth_sessions')
      .upsert(upsertPayload, { onConflict: 'user_id' });

    if (insertError) {
       console.error(`[openai-link-start] DB insert error for user ${user.id}:`, JSON.stringify(insertError));
       return new Response(JSON.stringify({ error: 'Failed to write session state' }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    console.log(`[openai-link-start] Success for user ${user.id}. Saved interval: ${normalizedInterval}`);

    // Return the sanitized device data back to Flutter
    return new Response(
      JSON.stringify({
        device_code: normalizedDeviceCode,
        user_code: normalizedUserCode,
        verification_url: normalizedVerificationUrl,
        verification_uri: normalizedVerificationUrl,
        interval: normalizedInterval,
        interval_seconds: normalizedInterval,
        expires_in: data.expires_in ?? 1800,
        expires_at: normalizedExpiresAt
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (err: any) {
    console.error("[openai-link-start] Exception:", err);
    return new Response(JSON.stringify({ error: 'Internal Server Error' }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
});
