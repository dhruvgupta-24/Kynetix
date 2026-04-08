// ai-chat-router — Central AI provider router
// Priority: 1. User-linked OpenAI (via token exchange)  2. OpenRouter fallback
//
// Source references:
//  - API key exchange: openai/codex server.rs obtain_api_key() (token-exchange grant)
//  - Token refresh: POST /oauth/token grant_type=refresh_token to get a fresh id_token
//  - Route: POST /oauth/token with grant_type=urn:ietf:params:oauth:grant-type:token-exchange
//
// KEY FIX (2026-04-08):
//  - id_token JWTs expire in ~1 hour. Storing them and reusing for days causes
//    "API key exchange failed (401)" → silent OpenRouter fallback.
//  - Fix: always refresh the access/id tokens via refresh_token before the API key exchange.
//  - The fresh id_token from the refresh response is used for the API key exchange.
//  - We also persist the new access_token + id_token back to the DB.
//
// BUG FIX (response_format):
//  - Removed response_format: json_object — it caused the AI to wrap coaching text
//    in a JSON envelope, resulting in "[1]" being rendered in the Flutter chat bubble.
//  - Vision requests (image_url content) were also incompatible with json_object mode.

// @ts-ignore
import { createClient } from "npm:@supabase/supabase-js@2.44.2";

declare const Deno: any;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const OPENAI_ISSUER        = 'https://auth.openai.com';
const OPENAI_CHAT_URL      = 'https://api.openai.com/v1/chat/completions';
const OPENAI_DEFAULT_MODEL = 'gpt-4o-mini';
const OPENROUTER_CHAT_URL  = 'https://openrouter.ai/api/v1/chat/completions';
const OPENROUTER_MODEL     = 'deepseek/deepseek-chat-v3-0324';
const CLIENT_ID            = 'app_EMoamEEZ73f0CkXaXp7hrann';

// ── Step A: Refresh to get a fresh id_token ───────────────────────────────────
// The stored id_token has ~1hr TTL. We must refresh before attempting key exchange.
// Returns { id_token, access_token, refresh_token? }
async function refreshTokens(refreshToken: string): Promise<{
  id_token: string;
  access_token: string;
  refresh_token?: string;
}> {
  const body = new URLSearchParams({
    grant_type:    'refresh_token',
    refresh_token: refreshToken,
    client_id:     CLIENT_ID,
  }).toString();

  const res = await fetch(`${OPENAI_ISSUER}/oauth/token`, {
    method:  'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  });

  const raw = await res.text();
  console.log(`[AI ROUTER] refresh status=${res.status} body_preview=${raw.slice(0, 300)}`);

  if (!res.ok) {
    throw new Error(`Token refresh failed (${res.status}): ${raw.slice(0, 300)}`);
  }

  let data: any;
  try { data = JSON.parse(raw); } catch (_) {
    throw new Error(`Token refresh non-JSON: ${raw.slice(0, 200)}`);
  }

  if (!data.id_token) {
    throw new Error(`Token refresh returned no id_token. keys=${Object.keys(data).join(',')}`);
  }
  if (!data.access_token) {
    throw new Error(`Token refresh returned no access_token. keys=${Object.keys(data).join(',')}`);
  }

  return {
    id_token:      data.id_token,
    access_token:  data.access_token,
    refresh_token: data.refresh_token,
  };
}

// ── Step B: Exchange id_token → openai-api-key ────────────────────────────────
// Source: openai/codex server.rs obtain_api_key() lines 1066-1101
async function exchangeIdTokenForApiKey(idToken: string): Promise<string> {
  const body = new URLSearchParams({
    grant_type:         'urn:ietf:params:oauth:grant-type:token-exchange',
    client_id:          CLIENT_ID,
    requested_token:    'openai-api-key',
    subject_token:      idToken,
    subject_token_type: 'urn:ietf:params:oauth:token-type:id_token',
  }).toString();

  const res = await fetch(`${OPENAI_ISSUER}/oauth/token`, {
    method:  'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  });

  const raw = await res.text();
  console.log(`[AI ROUTER] key exchange status=${res.status} body_preview=${raw.slice(0, 200)}`);

  if (!res.ok) {
    throw new Error(`API key exchange failed (${res.status}): ${raw.slice(0, 300)}`);
  }

  let data: any;
  try { data = JSON.parse(raw); } catch (_) {
    throw new Error(`API key exchange non-JSON: ${raw.slice(0, 200)}`);
  }

  if (!data.access_token) {
    throw new Error(`API key exchange no access_token. keys=${Object.keys(data).join(',')}`);
  }

  return data.access_token;
}

// ── Safe content extraction ───────────────────────────────────────────────────
// Handles all known response shapes from OpenAI/OpenRouter:
//   - choices[0].message.content as a plain string  (normal)
//   - choices[0].message.content as a JSON string   (when model wraps in JSON)
//   - choices[0].message.content as array            (vision completions)
function extractText(json: any, rawBody: string): string {
  const choice  = json?.choices?.[0];
  const message = choice?.message;

  if (!message) {
    console.error(`[AI ROUTER] No choices[0].message. raw=${rawBody.slice(0, 300)}`);
    return '';
  }

  const content = message.content;

  // Case 1: plain string (most common — free-form coaching text)
  if (typeof content === 'string' && content.trim()) {
    const trimmed = content.trim();
    // Guard: if model wrapped answer in a JSON envelope, unwrap it
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        const parsed = JSON.parse(trimmed);
        if (typeof parsed?.message  === 'string') return parsed.message;
        if (typeof parsed?.text     === 'string') return parsed.text;
        if (typeof parsed?.response === 'string') return parsed.response;
        if (typeof parsed?.answer   === 'string') return parsed.answer;
        if (typeof parsed?.content  === 'string') return parsed.content;
        if (Array.isArray(parsed) && parsed.every((x: any) => typeof x === 'string')) {
          return parsed.join(' ');
        }
        // Non-recognisable JSON — return raw string (coach might have answered in JSON format)
        return trimmed;
      } catch (_) { /* not JSON — use trimmed as-is */ }
    }
    return trimmed;
  }

  // Case 2: content is an array of content blocks (vision / multi-part)
  if (Array.isArray(content)) {
    const textBlocks = content
      .filter((b: any) => b?.type === 'text' && typeof b?.text === 'string')
      .map((b: any) => b.text as string);
    if (textBlocks.length) return textBlocks.join('\n');
  }

  console.error(`[AI ROUTER] Empty/unexpected content. type=${typeof content} raw=${rawBody.slice(0, 300)}`);
  return '';
}

// ── Chat call ─────────────────────────────────────────────────────────────────
// NOTE: response_format is deliberately NOT set — coaching responses are free-form text.
// Setting json_object would cause: model wraps answer → "[1]" renders in Flutter.
// Vision requests (image_url) are also incompatible with json_object.
async function callChat(
  endpoint:     string,
  apiKey:       string,
  model:        string,
  messages:     any[],
  extraHeaders: Record<string, string> = {},
): Promise<{ text: string; usage: any }> {
  // Detect vision request (image_url content block)
  const hasImages = messages.some(m =>
    Array.isArray(m?.content) &&
    m.content.some((b: any) => b?.type === 'image_url')
  );

  // gpt-4o-mini supports vision; gpt-4o is stronger but costlier
  const effectiveModel = (endpoint === OPENAI_CHAT_URL && hasImages)
    ? 'gpt-4o'
    : model;

  const requestBody: any = {
    model:       effectiveModel,
    messages,
    temperature: 0.25,
    max_tokens:  1500,
    // ← NO response_format — keeps coaching text as natural language
  };

  console.log(`[AI ROUTER] → ${endpoint} model=${effectiveModel} hasImages=${hasImages} msgs=${messages.length}`);

  const res = await fetch(endpoint, {
    method:  'POST',
    headers: {
      'Authorization': `Bearer ${apiKey}`,
      'Content-Type':  'application/json',
      ...extraHeaders,
    },
    body: JSON.stringify(requestBody),
    // @ts-ignore
    signal: AbortSignal.timeout(28_000),
  });

  const raw = await res.text();
  console.log(`[AI ROUTER] ← status=${res.status} body_preview=${raw.slice(0, 500)}`);

  if (!res.ok) {
    throw new Error(`HTTP ${res.status}: ${raw.slice(0, 400)}`);
  }

  let json: any;
  try { json = JSON.parse(raw); }
  catch (_) { throw new Error(`Non-JSON response: ${raw.slice(0, 200)}`); }

  const text = extractText(json, raw);
  console.log(`[AI ROUTER] extracted len=${text.length} preview="${text.slice(0, 120)}"`);

  if (!text) {
    throw new Error(`Empty text from provider. raw=${raw.slice(0, 300)}`);
  }

  return { text, usage: json?.usage ?? null };
}

// ── Main handler ───────────────────────────────────────────────────────────────
Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // ── Auth ─────────────────────────────────────────────────────────────────
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Missing Authorization header' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const userJwt = authHeader.replace('Bearer ', '').trim();
    const supabaseAnon = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
    );
    const { data: { user }, error: userErr } = await supabaseAnon.auth.getUser(userJwt);
    if (userErr || !user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // ── Parse request ────────────────────────────────────────────────────────
    const body     = await req.json().catch(() => ({}));
    const messages: any[] = body.messages ?? [];
    if (!messages.length) {
      return new Response(JSON.stringify({ error: 'messages array is required' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const openrouterKey: string = Deno.env.get('OPENROUTER_API_KEY') ?? '';

    // ── Step 1: Try user-linked OpenAI ───────────────────────────────────────
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    );

    const { data: link, error: linkErr } = await supabaseAdmin
      .from('user_openai_links')
      .select('id_token, access_token, refresh_token, is_connected, expires_at')
      .eq('user_id', user.id)
      .maybeSingle();

    console.log(`[AI ROUTER] OpenAI linked=${!!link} is_connected=${link?.is_connected} linkErr=${linkErr?.message ?? 'none'}`);
    console.log(`[AI ROUTER] id_token len=${link?.id_token?.length ?? 0} refresh_token len=${link?.refresh_token?.length ?? 0}`);

    let openaiApiFailed  = false;
    let openaiFailReason = '';

    if (link?.is_connected && link?.refresh_token) {
      try {
        // ── Refresh first to get a fresh id_token ───────────────────────────
        // id_token JWTs expire in ~1hr. ALWAYS refresh before exchanging.
        console.log(`[AI ROUTER] OpenAI linked=true — refreshing tokens to get fresh id_token`);
        const refreshed = await refreshTokens(link.refresh_token);
        console.log(`[AI ROUTER] token refresh success — id_token len=${refreshed.id_token.length}`);

        // Persist fresh tokens back to DB (keeps refresh_token valid)
        const newExpiry = new Date(Date.now() + 10 * 24 * 60 * 60 * 1000).toISOString(); // ~10 days
        await supabaseAdmin
          .from('user_openai_links')
          .update({
            id_token:      refreshed.id_token,
            access_token:  refreshed.access_token,
            refresh_token: refreshed.refresh_token ?? link.refresh_token,
            expires_at:    newExpiry,
            updated_at:    new Date().toISOString(),
          })
          .eq('user_id', user.id);
        console.log(`[AI ROUTER] persisted fresh tokens for user=${user.id}`);

        // ── Exchange fresh id_token for an API key ───────────────────────────
        console.log(`[AI ROUTER] starting api-key token exchange with fresh id_token`);
        const apiKey = await exchangeIdTokenForApiKey(refreshed.id_token);
        console.log(`[AI ROUTER] api-key exchange success — calling OpenAI`);

        const { text, usage } = await callChat(
          OPENAI_CHAT_URL,
          apiKey,
          OPENAI_DEFAULT_MODEL,
          messages,
        );

        console.log(`[AI ROUTER] OpenAI response SUCCESS provider=openai`);
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
        openaiApiFailed  = true;
        openaiFailReason = err?.message ?? String(err);
        console.error(`[AI ROUTER] OpenAI FAILED → fallback reason: ${openaiFailReason}`);
      }

    } else {
      const reason = !link
        ? 'no link row'
        : !link.is_connected
        ? 'is_connected=false'
        : 'refresh_token missing';
      console.log(`[AI ROUTER] OpenAI skipped — ${reason}`);
    }

    // ── Step 2: OpenRouter fallback ──────────────────────────────────────────
    if (!openrouterKey) {
      console.error(`[AI ROUTER] No OpenRouter key — no provider available`);
      return new Response(JSON.stringify({
        success: false,
        error:   'No AI provider available',
        detail:  openaiApiFailed ? openaiFailReason : 'No OpenAI link + no OpenRouter key',
      }), {
        status: 503, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    if (openaiApiFailed) {
      console.warn(`[AI ROUTER] OpenAI had link but failed — using OpenRouter as emergency fallback`);
    } else {
      console.log(`[AI ROUTER] No OpenAI link — using OpenRouter directly`);
    }

    try {
      const { text, usage } = await callChat(
        OPENROUTER_CHAT_URL,
        openrouterKey,
        OPENROUTER_MODEL,
        messages,
        { 'HTTP-Referer': 'https://kynetix.app', 'X-Title': 'Kynetix' },
      );

      console.log(`[AI ROUTER] OpenRouter SUCCESS provider=openrouter`);
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
      console.error(`[AI ROUTER] Both providers failed. openrouter=${reason}`);
      return new Response(JSON.stringify({
        success:          false,
        provider_used:    'none',
        error:            'All AI providers failed',
        openai_error:     openaiApiFailed ? openaiFailReason : null,
        openrouter_error: reason,
        fallback_used:    true,
      }), {
        status: 503, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

  } catch (err: any) {
    console.error(`[AI ROUTER] Exception: ${err?.message ?? err}`);
    return new Response(JSON.stringify({ error: 'Internal Server Error' }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
