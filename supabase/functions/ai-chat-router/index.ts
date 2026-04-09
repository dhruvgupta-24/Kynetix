// ai-chat-router — Central AI provider router
//
// Provider priority:
//   1. OpenAI  — using OPENAI_API_KEY secret (standard /v1/chat/completions)
//   2. OpenRouter — emergency fallback only if OpenAI fails
//
// The API key is read ONLY from Supabase secrets (environment variable).
// It is NEVER returned in any response, logged in full, or exposed to the client.
//
// Image support: when messages contain image_url content blocks, gpt-4o is used
// instead of gpt-4o-mini for vision capability.

// @ts-ignore
import { createClient } from "npm:@supabase/supabase-js@2.44.2";

declare const Deno: any;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const OPENAI_CHAT_URL    = 'https://api.openai.com/v1/chat/completions';
const OPENAI_MODEL       = 'gpt-4o-mini';
const OPENAI_VISION_MODEL = 'gpt-4o';      // used automatically when image_url is present
const OPENROUTER_URL     = 'https://openrouter.ai/api/v1/chat/completions';
const OPENROUTER_MODEL   = 'deepseek/deepseek-chat-v3-0324';

// ── Chat completions call (OpenAI & OpenRouter share the same API shape) ────────
async function callChat(
  endpoint:     string,
  apiKey:       string,
  model:        string,
  messages:     any[],
  extraHeaders: Record<string, string> = {},
): Promise<{ text: string; usage: any }> {

  const hasImages = messages.some(m =>
    Array.isArray(m?.content) &&
    m.content.some((b: any) => b?.type === 'image_url')
  );

  // When images are present and we're hitting OpenAI, upgrade to vision model
  const effectiveModel =
    (endpoint === OPENAI_CHAT_URL && hasImages) ? OPENAI_VISION_MODEL : model;

  const requestBody: any = {
    model:       effectiveModel,
    messages,
    temperature: 0.25,
    max_tokens:  1500,
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
  });

  const rawBody = await res.text();
  console.log(`[AI ROUTER] ← status=${res.status} body_preview=${rawBody.slice(0, 300)}`);

  if (!res.ok) {
    throw new Error(`HTTP ${res.status}: ${rawBody.slice(0, 400)}`);
  }

  const data = JSON.parse(rawBody);
  const text = extractText(rawBody, data);

  if (!text) {
    throw new Error(`Empty response from ${endpoint}. raw=${rawBody.slice(0, 200)}`);
  }

  console.log(`[AI ROUTER] extracted len=${text.length} preview="${text.slice(0, 120)}"`);
  return { text, usage: data.usage ?? null };
}

// ── Extract plain text from a chat completions response ─────────────────────────
function extractText(rawBody: string, data: any): string {
  const choice  = data?.choices?.[0];
  const message = choice?.message;

  if (!message) {
    console.error(`[AI ROUTER] No choices[0].message. raw=${rawBody.slice(0, 300)}`);
    return '';
  }

  const content = message.content;

  if (typeof content === 'string' && content.trim()) {
    const trimmed = content.trim();
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
        return trimmed;
      } catch (_) { /* not JSON */ }
    }
    return trimmed;
  }

  if (Array.isArray(content)) {
    const textBlock = content.find((b: any) => b?.type === 'text' && b?.text);
    if (textBlock?.text) return textBlock.text.trim();
  }

  return '';
}

// ── Main handler ────────────────────────────────────────────────────────────────
Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // ── Auth — verify the caller is a logged-in Kynetix user ─────────────────
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Missing Authorization header' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const userJwt = authHeader.replace('Bearer ', '').trim();
    const supabaseAnon = createClient(
      Deno.env.get('SUPABASE_URL')      ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
    );
    const { data: { user }, error: userErr } = await supabaseAnon.auth.getUser(userJwt);
    if (userErr || !user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // ── Parse request ─────────────────────────────────────────────────────────
    const body     = await req.json().catch(() => ({}));
    const messages: any[] = body.messages ?? [];
    if (!messages.length) {
      return new Response(JSON.stringify({ error: 'messages array is required' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // ── Read secrets from environment (NEVER from client) ────────────────────
    const openaiKey:    string = Deno.env.get('OPENAI_API_KEY')    ?? '';
    const openrouterKey:string = Deno.env.get('OPENROUTER_API_KEY') ?? '';

    // Redacted prefix for safe logging
    const keyHint = openaiKey ? `sk-...${openaiKey.slice(-4)}` : '(not set)';
    console.log(`[AI ROUTER] user=${user.id} msgs=${messages.length} openai_key=${keyHint}`);

    // ── Step 1: Try OpenAI with API key ──────────────────────────────────────
    if (openaiKey) {
      try {
        const { text, usage } = await callChat(
          OPENAI_CHAT_URL,
          openaiKey,
          OPENAI_MODEL,
          messages,
        );

        console.log(`[AI ROUTER] provider=OPENAI success`);
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
        const reason = err?.message ?? String(err);
        console.error(`[AI ROUTER] OpenAI failed → fallback to OpenRouter. reason=${reason.slice(0, 200)}`);
        // Fall through to OpenRouter
      }
    } else {
      console.warn(`[AI ROUTER] OPENAI_API_KEY not set — skipping OpenAI, using OpenRouter directly`);
    }

    // ── Step 2: OpenRouter fallback ───────────────────────────────────────────
    if (!openrouterKey) {
      console.error(`[AI ROUTER] all providers failed — no OpenRouter key either`);
      return new Response(JSON.stringify({
        success:       false,
        provider_used: 'none',
        error:         'No AI providers available. Contact support.',
      }), {
        status: 503, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    try {
      const { text, usage } = await callChat(
        OPENROUTER_URL,
        openrouterKey,
        OPENROUTER_MODEL,
        messages,
        { 'HTTP-Referer': 'https://kynetix.app', 'X-Title': 'Kynetix AI Coach' },
      );

      console.log(`[AI ROUTER] provider=OPENROUTER success`);
      return new Response(JSON.stringify({
        success:       true,
        provider_used: 'openrouter',
        response:      text,
        usage,
        fallback_used: true,
      }), {
        status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });

    } catch (err: any) {
      const reason = err?.message ?? String(err);
      console.error(`[AI ROUTER] all providers failed. openrouter=${reason.slice(0, 200)}`);
      return new Response(JSON.stringify({
        success:       false,
        provider_used: 'none',
        error:         'All AI providers failed',
        openai_error:  'See logs',
        openrouter_error: reason.slice(0, 200),
      }), {
        status: 503, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

  } catch (err: any) {
    console.error(`[AI ROUTER] Unhandled exception: ${err?.message ?? err}`);
    return new Response(JSON.stringify({ error: 'Internal Server Error' }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
