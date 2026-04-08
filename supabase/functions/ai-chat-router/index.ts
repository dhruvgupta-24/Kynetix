// ai-chat-router — Central AI provider router
// Priority: 1. User-linked OpenAI (via token exchange)  2. OpenRouter fallback
//
// Source references:
//  - API key exchange: openai/codex server.rs obtain_api_key() (token-exchange grant)
//  - Route: POST /oauth/token with grant_type=urn:ietf:params:oauth:grant-type:token-exchange

// @ts-ignore
import { createClient } from "npm:@supabase/supabase-js@2.44.2";

declare const Deno: any;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const OPENAI_ISSUER          = 'https://auth.openai.com';
const OPENAI_CHAT_URL        = 'https://api.openai.com/v1/chat/completions';
const OPENAI_DEFAULT_MODEL   = 'gpt-4o-mini';
const OPENROUTER_CHAT_URL    = 'https://openrouter.ai/api/v1/chat/completions';
const OPENROUTER_MODEL       = 'deepseek/deepseek-chat-v3-0324';

// ── Token exchange: id_token → openai-api-key ────────────────────────────────
// Source: openai/codex server.rs obtain_api_key() lines 1066-1101
async function exchangeIdTokenForApiKey(idToken: string): Promise<string> {
  const body = new URLSearchParams({
    grant_type:          'urn:ietf:params:oauth:grant-type:token-exchange',
    client_id:           'app_EMoamEEZ73f0CkXaXp7hrann',
    requested_token:     'openai-api-key',
    subject_token:       idToken,
    subject_token_type:  'urn:ietf:params:oauth:token-type:id_token',
  }).toString();

  const res = await fetch(`${OPENAI_ISSUER}/oauth/token`, {
    method:  'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`API key exchange failed (${res.status}): ${text}`);
  }

  const data = await res.json();
  if (!data.access_token) {
    throw new Error(`API key exchange returned no access_token: ${JSON.stringify(data)}`);
  }
  return data.access_token;
}

// ── Chat call ─────────────────────────────────────────────────────────────────
async function callChat(
  endpoint: string,
  apiKey: string,
  model: string,
  messages: any[],
  extraHeaders: Record<string, string> = {},
): Promise<{ text: string; usage: any }> {
  const res = await fetch(endpoint, {
    method:  'POST',
    headers: {
      'Authorization': `Bearer ${apiKey}`,
      'Content-Type':  'application/json',
      ...extraHeaders,
    },
    body: JSON.stringify({
      model,
      messages,
      temperature:     0.15,
      max_tokens:      1200,
      response_format: { type: 'json_object' },
    }),
    // @ts-ignore — Deno fetch supports signal
    signal: AbortSignal.timeout(25_000),
  });

  const raw = await res.text();
  if (!res.ok) {
    throw new Error(`HTTP ${res.status}: ${raw.slice(0, 400)}`);
  }
  const json = JSON.parse(raw);
  const text = json?.choices?.[0]?.message?.content ?? '';
  return { text, usage: json?.usage ?? null };
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // ── Auth ──────────────────────────────────────────────────────────────────
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Missing Authorization header' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const token = authHeader.replace('Bearer ', '').trim();
    const supabaseAnon = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? ''
    );
    const { data: { user }, error: userErr } = await supabaseAnon.auth.getUser(token);
    if (userErr || !user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // ── Parse request ─────────────────────────────────────────────────────────
    const body = await req.json().catch(() => ({}));
    const messages: any[] = body.messages ?? [];
    if (!messages.length) {
      return new Response(JSON.stringify({ error: 'messages array is required' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const openrouterKey: string = Deno.env.get('OPENROUTER_API_KEY') ?? '';

    // ── Step 1: Try user-linked OpenAI ────────────────────────────────────────
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    const { data: link } = await supabaseAdmin
      .from('user_openai_links')
      .select('id_token, access_token, is_connected, expires_at')
      .eq('user_id', user.id)
      .maybeSingle();

    let openaiApiFailed = false;
    let openaiFailReason = '';

    if (link?.is_connected) {
      // Attempt to get an API key via token-exchange using the stored id_token
      // Source: openai/codex obtain_api_key()
      try {
        console.log(`[AI ENGINE] provider=OPENAI user=${user.id} — attempting token exchange`);
        const apiKey = await exchangeIdTokenForApiKey(link.id_token);
        console.log(`[AI ENGINE] provider=OPENAI user=${user.id} — token exchange succeeded, calling API`);

        const { text, usage } = await callChat(
          OPENAI_CHAT_URL,
          apiKey,
          OPENAI_DEFAULT_MODEL,
          messages,
        );

        console.log(`[AI ENGINE] provider=OPENAI user=${user.id} — SUCCESS`);
        return new Response(JSON.stringify({
          success:       true,
          provider_used: 'openai',
          response:      text,
          usage,
          fallback_used: false,
        }), {
          status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });

      } catch (err: any) {
        openaiApiFailed = true;
        openaiFailReason = err?.message ?? String(err);
        console.error(`[AI ENGINE FALLBACK] OpenAI failed → OpenRouter used`);
        console.error(`  user=${user.id}`);
        console.error(`  reason=${openaiFailReason}`);
      }
    }

    // ── Step 2: OpenRouter fallback ───────────────────────────────────────────
    if (!openrouterKey) {
      console.error(`[AI ENGINE ERROR] No OpenRouter key configured — cannot fallback`);
      return new Response(JSON.stringify({
        success: false,
        error:   'No AI provider available',
        detail:  openaiApiFailed ? openaiFailReason : 'No OpenAI link and no OpenRouter key',
      }), {
        status: 503, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Log if OpenAI was linked but failed (unexpected fallback)
    if (openaiApiFailed) {
      console.warn(`[AI ENGINE FALLBACK] user=${user.id} has OpenAI linked but it failed — falling back`);
    } else {
      // User has no OpenAI link — OpenRouter is the direct provider
      console.log(`[AI ENGINE] provider=OPENROUTER user=${user.id} — no OpenAI link, using OpenRouter directly`);
    }

    try {
      const { text, usage } = await callChat(
        OPENROUTER_CHAT_URL,
        openrouterKey,
        OPENROUTER_MODEL,
        messages,
        { 'HTTP-Referer': 'https://kynetix.app', 'X-Title': 'Kynetix' },
      );

      console.log(`[AI ENGINE] provider=OPENROUTER user=${user.id} — SUCCESS`);
      return new Response(JSON.stringify({
        success:       true,
        provider_used: 'openrouter',
        response:      text,
        usage,
        fallback_used: openaiApiFailed,
      }), {
        status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });

    } catch (err: any) {
      const reason = err?.message ?? String(err);
      console.error(`[AI ENGINE ERROR] Both providers failed. user=${user.id} openrouter_error=${reason}`);
      return new Response(JSON.stringify({
        success:       false,
        provider_used: 'none',
        error:         'All AI providers failed',
        openai_error:  openaiApiFailed ? openaiFailReason : null,
        openrouter_error: reason,
        fallback_used: true,
      }), {
        status: 503, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

  } catch (err: any) {
    console.error(`[AI ENGINE] Exception: ${err?.message ?? err}`);
    return new Response(JSON.stringify({ error: 'Internal Server Error' }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
