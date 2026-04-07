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
    const body = await req.json();
    const { nonce, device_code, user_code, verification_url, interval_seconds, expires_at } = body;

    if (!nonce || !device_code || !user_code) {
      return new Response(JSON.stringify({ error: 'Missing required fields' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    // Look up the user from the nonce table — single-use, expires after 5 min
    const { data: nonceRow, error: nonceError } = await supabaseAdmin
      .from('openai_auth_nonces')
      .select('user_id, expires_at')
      .eq('nonce', nonce)
      .single();

    if (nonceError || !nonceRow) {
      console.error('[openai-link-save] Nonce lookup failed:', JSON.stringify(nonceError));
      return new Response(JSON.stringify({ error: 'Invalid or expired session' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    if (new Date(nonceRow.expires_at) < new Date()) {
      console.error('[openai-link-save] Nonce expired for user:', nonceRow.user_id);
      // Clean up expired nonce
      await supabaseAdmin.from('openai_auth_nonces').delete().eq('nonce', nonce);
      return new Response(JSON.stringify({ error: 'Session expired. Please try again.' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const userId = nonceRow.user_id;

    // Delete nonce immediately — single use
    await supabaseAdmin.from('openai_auth_nonces').delete().eq('nonce', nonce);

    // Save device session
    const { error: upsertError } = await supabaseAdmin
      .from('openai_device_auth_sessions')
      .upsert({
        user_id: userId,
        device_code,
        user_code,
        verification_url: verification_url ?? 'https://chatgpt.com/auth/device',
        interval_seconds: interval_seconds ?? 5,
        expires_at: expires_at ?? new Date(Date.now() + 1800 * 1000).toISOString(),
        status: 'pending',
      }, { onConflict: 'user_id' });

    if (upsertError) {
      console.error('[openai-link-save] DB upsert error:', JSON.stringify(upsertError));
      return new Response(JSON.stringify({ error: 'Failed to save session' }), {
        status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    console.log(`[openai-link-save] Session saved for user ${userId}`);

    return new Response(JSON.stringify({ success: true }), {
      status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  } catch (err: any) {
    console.error('[openai-link-save] Exception:', err);
    return new Response(JSON.stringify({ error: 'Internal Server Error' }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
