// ai-chat-router — Central AI provider router
//
// Provider priority:
//   1. user_chatgpt  — user's own authenticated OpenAI token (from user_openai_links)
//                      Routes to: https://chatgpt.com/backend-api/codex/responses
//                      (ChatGPT OAuth session tokens work only on this endpoint,
//                       NOT on api.openai.com/v1 which requires a Platform API key)
//   2. openrouter    — shared fallback (Kynetix-funded, acknowledged in UI)
//
// Kynetix's own OPENAI_API_KEY is NOT in the provider chain.
// Users never silently consume Kynetix OpenAI credits.
//
// The access_token is read ONLY from Supabase DB (server-side).
// It is NEVER returned in any response, logged in full, or exposed to the client.

// @ts-ignore
import { createClient } from "npm:@supabase/supabase-js@2";
import { refreshAccessTokenIfNeeded } from "../shared/oauth_refresh.ts";

declare const Deno: any;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// Codex backend endpoint (works with ChatGPT OAuth tokens)
const CODEX_URL = 'https://chatgpt.com/backend-api/codex/responses';
// NOTE: CODEX_MODEL is intentionally not hardcoded here.
// The model is always discovered dynamically by openai-link-verify and
// stored in user_openai_links.selected_model. We never guess model names.

// OpenRouter fallback
const OPENROUTER_URL   = 'https://openrouter.ai/api/v1/chat/completions';
const OPENROUTER_MODEL = 'deepseek/deepseek-chat-v3-0324';
// Vision model candidates in priority order.
// The account is on OpenRouter free tier — paid models return 402.
// Free-tier (:free) models are tried in order; first success wins.
const OPENROUTER_VISION_MODELS = [
  'google/gemma-4-27b-it:free',      // Google Gemma 4 27B — free, multimodal
  'google/gemma-4-26b-a4b-it:free',  // Google Gemma 4 26B MoE — free, multimodal
  'nvidia/nemotron-nano-12b-v2-vl:free', // NVIDIA Nemotron VL — free, multimodal
  'moonshotai/kimi-k2.6:free',       // Kimi K2 — free, multimodal
];

function hasImage(messages: any[]): boolean {
  for (const m of messages) {
    if (Array.isArray(m.content)) {
      for (const block of m.content) {
        if (block?.type === 'image_url' || block?.type === 'input_image') {
          return true;
        }
      }
    }
  }
  return false;
}

// ── Convert standard messages[] → Codex request body ─────────────────────────
// The Codex Responses API uses:
//   - "instructions" for the system message
//   - "input" array for user/assistant turns, each with a content block array
//   - "stream": true  (required by the Codex backend)
//   - "store": false  (prevents storing in ChatGPT history)
function buildCodexBody(model: string, messages: any[]): string {
  const systemMsg      = messages.find((m: any) => m.role === 'system');
  const instructions   = typeof systemMsg?.content === 'string' ? systemMsg.content : '';
  const nonSystemMsgs  = messages.filter((m: any) => m.role !== 'system');

  const input = nonSystemMsgs.map((m: any) => {
    let contentBlocks: any[] = [];
    if (typeof m.content === 'string') {
      const contentType = m.role === 'user' ? 'input_text' : 'output_text';
      contentBlocks = [{ type: contentType, text: m.content }];
    } else if (Array.isArray(m.content)) {
      contentBlocks = m.content.map((b: any) => {
        if (b?.type === 'text') {
          const contentType = m.role === 'user' ? 'input_text' : 'output_text';
          return { type: contentType, text: b.text ?? '' };
        } else if (b?.type === 'image_url') {
          const url = b.image_url?.url ?? b.image_url ?? '';
          return {
            type: 'input_image',
            image_url: {
              url: url,
              detail: 'auto'
            }
          };
        } else {
          // Unknown block type fallback
          const contentType = m.role === 'user' ? 'input_text' : 'output_text';
          return { type: contentType, text: typeof b === 'string' ? b : JSON.stringify(b) };
        }
      });
    }

    return {
      type:    'message',
      role:    m.role,
      content: contentBlocks,
    };
  });

  // Build request body. The model MUST be a real slug from DB discovery — the
  // Codex backend returns HTTP 400 for any unrecognised model identifier.
  // If somehow the DB has an empty/placeholder, omit the field and let the
  // backend use its subscription-based default.
  const reqBody: Record<string, unknown> = {
    instructions,
    stream: true,
    store:  false,
    input,
  };
  if (model && model !== 'codex') {
    reqBody.model = model;
  }

  // Debug logging of final request body received by Codex to inspect blocks and order.
  // We censor long base64 strings to keep logs readable.
  const loggedInput = input.map((msg: any) => ({
    role: msg.role,
    content: msg.content.map((b: any) => {
      if (b.type === 'input_image') {
        const urlStr = typeof b.image_url === 'object' ? (b.image_url?.url ?? '') : (b.image_url ?? '');
        const preview = urlStr.startsWith('data:') 
          ? `${urlStr.slice(0, 30)}...[len=${urlStr.length}]` 
          : urlStr;
        return { type: b.type, image_url: { url: preview, detail: 'auto' } };
      }
      return b;
    })
  }));
  console.log('[AI ROUTER] Codex request body built:', JSON.stringify({
    instructions: instructions.slice(0, 100) + '...',
    model: reqBody.model,
    input: loggedInput
  }, null, 2));

  return JSON.stringify(reqBody);
}

// ── Drain Codex SSE → plain text (for non-streaming callers) ─────────────────
async function drainCodexSSE(res: Response): Promise<string> {
  const reader = res.body?.getReader();
  if (!reader) return '';

  const decoder = new TextDecoder();
  let fullText = '';
  let buffer   = '';

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split('\n');
      buffer = lines.pop() ?? '';

      for (const line of lines) {
        if (!line.startsWith('data: ')) continue;
        const payload = line.slice(6).trim();
        if (payload === '[DONE]') return fullText;

        try {
          const ev = JSON.parse(payload);
          if (ev?.type === 'response.output_text.delta' && typeof ev.delta === 'string') {
            fullText += ev.delta;
          } else if (ev?.type === 'response.output_text.done' && typeof ev.text === 'string') {
            if (fullText.length === 0) fullText = ev.text; // fallback if delta missed
          } else if (typeof ev?.choices?.[0]?.delta?.content === 'string') {
            fullText += ev.choices[0].delta.content; // OpenAI-compatible gateway
          } else if (typeof ev?.delta === 'string') {
            fullText += ev.delta; // flat proxy format
          }
        } catch { /* skip malformed lines */ }
      }
    }
  } finally {
    try { reader.releaseLock(); } catch { /* already released */ }
  }

  return fullText;
}

// ── Non-streaming Codex call ──────────────────────────────────────────────────
async function callCodex(
  accessToken: string,
  model:       string,
  messages:    any[],
): Promise<{ text: string; usage: null }> {
  // model comes directly from the DB-discovered slug (selected_model from user_openai_links).
  // buildCodexBody already handles the case where model is empty/placeholder.
  console.log(`[AI ROUTER] codex → ${CODEX_URL} model=${model || '(auto)'} msgs=${messages.length}`);

  const res = await fetch(CODEX_URL, {
    method:  'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type':  'application/json',
    },
    body: buildCodexBody(model, messages),
  });

  console.log(`[AI ROUTER] codex ← status=${res.status}`);

  if (!res.ok) {
    const errBody = await res.text();
    throw new Error(`HTTP ${res.status}: ${errBody.slice(0, 400)}`);
  }

  const text = await drainCodexSSE(res);
  if (!text.trim()) throw new Error(`Empty response from Codex endpoint`);

  console.log(`[AI ROUTER] codex extracted len=${text.length} preview="${text.slice(0, 120)}"`);
  return { text, usage: null };
}

// ── Streaming Codex call (converts Codex SSE → OpenAI Chat SSE format) ────────
// Clients expect the standard OpenAI streaming format:
//   data: {"choices":[{"delta":{"content":"..."},"index":0,"finish_reason":null}]}
async function callCodexStream(
  accessToken: string,
  model:       string,
  messages:    any[],
): Promise<Response> {
  console.log(`[AI ROUTER] codex stream → ${CODEX_URL} model=${model || '(auto)'}`);

  const res = await fetch(CODEX_URL, {
    method:  'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type':  'application/json',
    },
    body: buildCodexBody(model, messages),
  });

  if (!res.ok) {
    const errBody = await res.text();
    throw new Error(`HTTP ${res.status}: ${errBody.slice(0, 400)}`);
  }

  // Convert Codex SSE events → OpenAI Chat SSE events in a TransformStream
  const { readable, writable } = new TransformStream();
  const writer  = writable.getWriter();
  const encoder = new TextEncoder();

  // Process the Codex stream in the background
  (async () => {
    const reader  = res.body!.getReader();
    const decoder = new TextDecoder();
    let buffer    = '';

    const emitDelta = async (delta: string) => {
      const chunk = JSON.stringify({
        id:      'chatcmpl-codex',
        object:  'chat.completion.chunk',
        model:   model || 'auto',
        choices: [{ index: 0, delta: { content: delta }, finish_reason: null }],
      });
      await writer.write(encoder.encode(`data: ${chunk}\n\n`));
    };

    const emitDone = async () => {
      const chunk = JSON.stringify({
        id:      'chatcmpl-codex',
        object:  'chat.completion.chunk',
        model:   model || 'auto',
        choices: [{ index: 0, delta: {}, finish_reason: 'stop' }],
      });
      await writer.write(encoder.encode(`data: ${chunk}\n\n`));
      await writer.write(encoder.encode('data: [DONE]\n\n'));
    };

    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split('\n');
        buffer = lines.pop() ?? '';

        for (const line of lines) {
          if (!line.startsWith('data: ')) continue;
          const payload = line.slice(6).trim();
          if (payload === '[DONE]') {
            await emitDone();
            return;
          }

          try {
            const ev = JSON.parse(payload);
            if (ev?.type === 'response.output_text.delta' && typeof ev.delta === 'string') {
              await emitDelta(ev.delta);
            } else if (typeof ev?.choices?.[0]?.delta?.content === 'string') {
              await emitDelta(ev.choices[0].delta.content);
            } else if (typeof ev?.delta === 'string') {
              await emitDelta(ev.delta);
            }
          } catch { /* skip malformed lines */ }
        }
      }
      // If we exit the loop without seeing [DONE], emit the done event
      await emitDone();
    } catch (err: any) {
      console.error(`[AI ROUTER] codex stream processing error: ${err?.message}`);
    } finally {
      try { reader.releaseLock(); } catch { /* ignore */ }
      try { await writer.close(); } catch { /* ignore */ }
    }
  })();

  return new Response(readable, {
    headers: {
      ...corsHeaders,
      'Content-Type':  'text/event-stream',
      'Cache-Control': 'no-cache',
    },
  });
}

// ── Standard OpenAI Chat Completions (OpenRouter / fallback) ─────────────────
async function callChat(
  endpoint:     string,
  apiKey:       string,
  model:        string,
  messages:     any[],
  extraHeaders: Record<string, string> = {},
  maxTokens:    number = 1500,
): Promise<{ text: string; usage: any }> {
  const requestBody: any = { model, messages, temperature: 0.25, max_tokens: maxTokens };
  console.log(`[AI ROUTER] → ${endpoint} model=${model} msgs=${messages.length} max_tokens=${maxTokens}`);

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
    console.error(`[AI ROUTER] ← FULL ERROR from ${endpoint}: ${rawBody.slice(0, 1000)}`);
    throw new Error(`HTTP ${res.status}: ${rawBody.slice(0, 400)}`);
  }

  const data = JSON.parse(rawBody);
  const text = extractText(rawBody, data);
  if (!text) throw new Error(`Empty response from ${endpoint}. raw=${rawBody.slice(0, 200)}`);

  console.log(`[AI ROUTER] extracted len=${text.length} preview="${text.slice(0, 120)}"`);
  return { text, usage: data.usage ?? null };
}

// ── Standard OpenAI streaming (OpenRouter fallback) ──────────────────────────
async function callChatStream(
  endpoint:     string,
  apiKey:       string,
  model:        string,
  messages:     any[],
  extraHeaders: Record<string, string> = {},
  maxTokens:    number = 1500,
): Promise<Response> {
  console.log(`[AI ROUTER] stream → ${endpoint} model=${model} max_tokens=${maxTokens}`);

  const res = await fetch(endpoint, {
    method:  'POST',
    headers: {
      'Authorization': `Bearer ${apiKey}`,
      'Content-Type':  'application/json',
      ...extraHeaders,
    },
    body: JSON.stringify({ model, messages, temperature: 0.25, max_tokens: maxTokens, stream: true }),
  });

  if (!res.ok) {
    const errBody = await res.text();
    console.error(`[AI ROUTER] stream ← FULL ERROR from ${endpoint} (${res.status}): ${errBody.slice(0, 1000)}`);
    throw new Error(`HTTP ${res.status}: ${errBody.slice(0, 400)}`);
  }
  return res;
}

// ── Extract plain text from Chat Completions response ────────────────────────
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

// ── Look up user's connected ChatGPT token ────────────────────────────────────
async function getUserChatGptProvider(
  supabaseAdmin: any,
  userId: string,
): Promise<{ accessToken: string; model: string } | null> {
  const { data, error } = await supabaseAdmin
    .from('user_openai_links')
    .select('is_connected, access_token, refresh_token, expires_at, selected_model, model_discovery_verified')
    .eq('user_id', userId)
    .maybeSingle();

  if (error || !data) return null;

  if (!data.is_connected) {
    await supabaseAdmin
      .from('user_openai_links')
      .update({ fallback_reason: 'account_disconnected', updated_at: new Date().toISOString() })
      .eq('user_id', userId);
    return null;
  }

  if (!data.model_discovery_verified || !data.selected_model) {
    await supabaseAdmin
      .from('user_openai_links')
      .update({ fallback_reason: 'model_unavailable', updated_at: new Date().toISOString() })
      .eq('user_id', userId);
    return null;
  }

  // Auto-refresh token if expired or expiring
  const refreshed = await refreshAccessTokenIfNeeded(supabaseAdmin, userId, data);
  if (!refreshed) {
    console.warn(`[AI ROUTER] user=${userId} token refresh failed.`);
    return null;
  }

  return { accessToken: refreshed.accessToken, model: data.selected_model };
}

// ── Update last_provider_used after a successful call ─────────────────────────
async function trackUsage(supabaseAdmin: any, userId: string, provider: string): Promise<void> {
  await supabaseAdmin
    .from('user_openai_links')
    .update({ last_provider_used: provider, last_used_at: new Date().toISOString() })
    .eq('user_id', userId);
}

// ── Main handler ─────────────────────────────────────────────────────────────
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

    const userJwt = authHeader.replace('Bearer ', '').trim();
    const supabaseAnon = createClient(
      Deno.env.get('SUPABASE_URL')      ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: `Bearer ${userJwt}` } } },
    );
    const { data: { user }, error: userErr } = await supabaseAnon.auth.getUser();
    if (userErr || !user) {
      console.error(`[AI ROUTER] Auth failed: ${userErr?.message ?? 'no user'}`);
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // ── Parse request ─────────────────────────────────────────────────────────
    const body         = await req.json().catch(() => ({}));
    const messages: any[] = body.messages ?? [];
    const streamMode: boolean = body.stream === true;

    console.log(`[AI ROUTER] (5/7) Request received: messages=${messages.length}, streamMode=${streamMode}`);
    messages.forEach((msg, idx) => {
      if (typeof msg.content === 'string') {
        console.log(`  msg[${idx}] role=${msg.role}: content_type=string (length=${msg.content.length})`);
      } else if (Array.isArray(msg.content)) {
        const types = msg.content.map((b: any) => b?.type ?? 'unknown');
        console.log(`  msg[${idx}] role=${msg.role}: content_type=array (blocks=${types.join(', ')})`);
      } else {
        console.log(`  msg[${idx}] role=${msg.role}: content_type=other (${typeof msg.content})`);
      }
    });

    if (!messages.length) {
      return new Response(JSON.stringify({ error: 'messages array is required' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // ── Set up service-role client for token lookup + tracking ────────────────
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL')              ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    );

    const openrouterKey: string = Deno.env.get('OPENROUTER_API_KEY') ?? '';

    // ── Resolve user's ChatGPT provider (if connected + verified) ────────────
    const userProvider = await getUserChatGptProvider(supabaseAdmin, user.id);
    const providerLabel = userProvider ? 'user_chatgpt' : 'openrouter';
    const imageRequest = hasImage(messages);
    const activeOpenRouterModel = imageRequest ? OPENROUTER_VISION_MODELS[0] : OPENROUTER_MODEL;

    console.log(`[AI ROUTER] user=${user.id} stream=${streamMode} provider=${providerLabel} imageRequest=${imageRequest} model=${userProvider?.model ?? activeOpenRouterModel}`);

    // ══════════════════════════════════════════════════
    // STREAMING PATH
    // ══════════════════════════════════════════════════
    if (streamMode) {
      const imageRequest = hasImage(messages);
      // Codex (chatgpt.com/backend-api/codex/responses) is a text-only endpoint.
      // Skip it entirely for vision requests to avoid a guaranteed failure + wasted latency.
      const useCodexForThisRequest = userProvider && !imageRequest;

      // ── Attempt 1: User's ChatGPT via Codex endpoint (text-only) ──────────
      if (useCodexForThisRequest) {
        try {
          const streamRes = await callCodexStream(
            userProvider!.accessToken, userProvider!.model, messages,
          );
          await trackUsage(supabaseAdmin, user.id, 'user_chatgpt');
          console.log(`[AI ROUTER] streaming via user_chatgpt (Codex) model=${userProvider!.model}`);
          // Inject provider headers into the existing response headers
          const headers = new Headers(streamRes.headers);
          headers.set('X-Provider-Used', 'user_chatgpt');
          headers.set('X-Model-Used', userProvider!.model);
          return new Response(streamRes.body, { headers });
        } catch (err: any) {
          console.error(`[AI ROUTER] user_chatgpt (Codex) stream failed: ${err?.message?.slice(0, 300)}`);
          await supabaseAdmin
            .from('user_openai_links')
            .update({ fallback_reason: 'api_error', last_provider_used: 'openrouter', updated_at: new Date().toISOString() })
            .eq('user_id', user.id);
          // Fall through to OpenRouter
        }
      } else if (userProvider && imageRequest) {
        console.log(`[AI ROUTER] skipping Codex for vision request — routing directly to OpenRouter`);
      }

      // ── Attempt 2: OpenRouter (with per-model fallback for vision) ──────────
      if (openrouterKey) {
        const maxTok = 1500;
        const modelsToTry = imageRequest ? OPENROUTER_VISION_MODELS : [OPENROUTER_MODEL];
        for (const model of modelsToTry) {
          try {
            console.log(`[AI ROUTER] trying openrouter model=${model} stream=true`);
            const sRes = await callChatStream(
              OPENROUTER_URL, openrouterKey, model, messages,
              { 'HTTP-Referer': 'https://kynetix.app', 'X-Title': 'Kynetix AI Coach' },
              maxTok,
            );
            console.log(`[AI ROUTER] streaming via openrouter model=${model}`);
            return new Response(sRes.body, {
              headers: {
                ...corsHeaders,
                'Content-Type':    'text/event-stream',
                'Cache-Control':   'no-cache',
                'X-Provider-Used': 'openrouter',
                'X-Model-Used':    model,
              },
            });
          } catch (err: any) {
            console.error(`[AI ROUTER] OpenRouter stream failed model=${model}: ${err?.message?.slice(0, 300)}`);
            // 402 = no credits for this model, 429 = rate limited, try next
          }
        }
      }

      return new Response(JSON.stringify({ error: 'All providers failed for streaming' }), {
        status: 503, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // ══════════════════════════════════════════════════
    // NON-STREAMING PATH
    // ══════════════════════════════════════════════════

    // imageRequest was already computed above at line ~533
    // Codex is text-only — skip for vision requests
    const useCodexForThisRequest = userProvider && !imageRequest;
    const maxTok = 1500;

    // ── Attempt 1: User's ChatGPT via Codex endpoint (text-only) ────────────
    if (useCodexForThisRequest) {
      try {
        const { text, usage } = await callCodex(
          userProvider!.accessToken, userProvider!.model, messages,
        );
        await trackUsage(supabaseAdmin, user.id, 'user_chatgpt');
        console.log(`[AI ROUTER] provider=user_chatgpt (Codex) model=${userProvider!.model} success`);
        return new Response(JSON.stringify({
          success:       true,
          provider_used: 'user_chatgpt',
          model_used:    userProvider!.model,
          response:      text,
          usage,
          fallback_used: false,
        }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

      } catch (err: any) {
        console.error(`[AI ROUTER] user_chatgpt (Codex) failed: ${err?.message?.slice(0, 300)}`);
        await supabaseAdmin
          .from('user_openai_links')
          .update({ fallback_reason: 'api_error', last_provider_used: 'openrouter', updated_at: new Date().toISOString() })
          .eq('user_id', user.id);
        // Fall through to OpenRouter
      }
    } else if (userProvider && imageRequest) {
      console.log(`[AI ROUTER] skipping Codex for vision request — routing directly to OpenRouter`);
    }

    // ── Attempt 2: OpenRouter (with per-model fallback for vision) ────────────
    if (!openrouterKey) {
      return new Response(JSON.stringify({
        success:       false,
        provider_used: 'none',
        error:         'No AI providers available. Connect your ChatGPT account or contact support.',
      }), { status: 503, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const modelsToTry = imageRequest ? OPENROUTER_VISION_MODELS : [OPENROUTER_MODEL];
    let lastErr = '';
    for (const model of modelsToTry) {
      try {
        console.log(`[AI ROUTER] trying openrouter model=${model} stream=false`);
        const { text, usage } = await callChat(
          OPENROUTER_URL, openrouterKey, model, messages,
          { 'HTTP-Referer': 'https://kynetix.app', 'X-Title': 'Kynetix AI Coach' },
          maxTok,
        );
        console.log(`[AI ROUTER] provider=openrouter model=${model} success`);
        return new Response(JSON.stringify({
          success:       true,
          provider_used: 'openrouter',
          model_used:    model,
          response:      text,
          usage,
          fallback_used: !userProvider,
        }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
      } catch (err: any) {
        lastErr = err?.message ?? String(err);
        console.error(`[AI ROUTER] openrouter model=${model} failed: ${lastErr.slice(0, 300)}`);
        // 402/429 → try next model
      }
    }
    console.error(`[AI ROUTER] all providers failed. lastErr=${lastErr.slice(0, 500)}`);
    return new Response(JSON.stringify({
      success:       false,
      provider_used: 'none',
      error:         'All AI providers failed',
    }), { status: 503, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

  } catch (err: any) {
    console.error(`[AI ROUTER] Unhandled exception: ${err?.message ?? err}`);
    return new Response(JSON.stringify({ error: 'Internal Server Error' }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
