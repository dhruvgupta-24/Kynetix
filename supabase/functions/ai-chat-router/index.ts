// ai-chat-router — Central AI provider router
//
// Provider priority:
//   1. user_chatgpt  — user's own authenticated OpenAI token (from user_openai_links)
//                      Routes to: https://chatgpt.com/backend-api/codex/responses
//                      (ChatGPT OAuth session tokens work only on this endpoint,
//                       NOT on api.openai.com/v1 which requires a Platform API key)
//   2. free fallback  — Kynetix's free-tier keys, each skipped if unset
//                      (shared/free_providers.ts): Gemini (GEMINI_API_KEY)
//                      → Groq (GROQ_API_KEY) → OpenRouter ':free' models
//                      (OPENROUTER_API_KEY). Paid OpenRouter models only
//                      with OPENROUTER_ALLOW_PAID=true.
//
// Kynetix's own OPENAI_API_KEY is NOT in the provider chain.
// Users never silently consume Kynetix OpenAI credits.
//
// The access_token is read ONLY from Supabase DB (server-side).
// It is NEVER returned in any response, logged in full, or exposed to the client.

// @ts-ignore
import { createClient } from "npm:@supabase/supabase-js@2";
import { refreshAccessTokenIfNeeded } from "../shared/oauth_refresh.ts";
import {
  buildSiwcResponsesBody,
  drainSiwcStream,
  postSiwcResponses,
  readSiwcStream,
  SiwcApiError,
  SIWC_RESPONSES_URL,
  PLAN_PAUSE_MS,
  MANAGE_USAGE_URL,
} from "../shared/siwc.ts";
import {
  AiGuardError,
  allowsStreaming,
  consumeQuota,
  enforceDailyImageCap,
  finalizeResponseText,
  guardRequest,
  INTERNAL_HEADER,
  INTERNAL_SECRET_ENV,
  internalSecret,
  isTrustedInternal,
  jsonError,
  planTier,
  rateLimitedError,
  secondsUntilUtcMidnight,
  standardTier,
  type GuardedRequest,
} from "../shared/ai_guard.ts";
import { timedFetch } from "../shared/timed_fetch.ts";
import { BodyTooLargeError, readJsonLimited } from "../shared/body_limit.ts";
import { buildFallbackChain, chatBody, type ProviderAttempt } from "../shared/free_providers.ts";

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

// Fallback providers (after the user's own ChatGPT) and their model lists
// live in shared/free_providers.ts.

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

  const res = await timedFetch(CODEX_URL, {
    method:  'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type':  'application/json',
    },
    body: buildCodexBody(model, messages),
  });

  console.log(`[AI ROUTER] codex ← status=${res.status}`);

  if (!res.ok) {
    throw new Error(`HTTP ${res.status} ${await upstreamErrorCode(res)}`);
  }

  const text = await drainCodexSSE(res);
  if (!text.trim()) throw new Error(`Empty response from Codex endpoint`);

  console.log(`[AI ROUTER] codex ok len=${text.length}`);
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

  const res = await timedFetch(CODEX_URL, {
    method:  'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type':  'application/json',
    },
    body: buildCodexBody(model, messages),
  });

  if (!res.ok) {
    throw new Error(`HTTP ${res.status} ${await upstreamErrorCode(res)}`);
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

// ── Sign in with ChatGPT (plan usage) via the public Responses API ──────────
// auth_method = 'siwc'. POST api.openai.com/v1/responses, stream + store:false,
// instructions + full history in input. Success only on response.completed.
// Never logs tokens or bodies.

async function callSiwc(
  accessToken: string,
  model:       string,
  messages:    any[],
): Promise<{ text: string; usage: null }> {
  console.log(`[AI ROUTER] siwc → ${SIWC_RESPONSES_URL} model=${model} msgs=${messages.length}`);
  const res = await postSiwcResponses(accessToken, buildSiwcResponsesBody(model, messages));
  const text = await drainSiwcStream(res);
  if (!text.trim()) throw new SiwcApiError(0, 'empty_output', 'unknown');
  console.log(`[AI ROUTER] siwc ← ok len=${text.length}`);
  return { text, usage: null };
}

// Plain, honest copy for a limit that lands mid-stream (VOICE.md).
const SIWC_MIDSTREAM_LIMIT_TEXT =
  `\n\nYou've hit your ChatGPT usage limit, so Kyno stopped here. ` +
  `Manage usage: ${MANAGE_USAGE_URL}`;

async function callSiwcStream(
  accessToken: string,
  model:       string,
  messages:    any[],
  onFailure:   (err: SiwcApiError) => Promise<void>,
): Promise<Response> {
  console.log(`[AI ROUTER] siwc stream → ${SIWC_RESPONSES_URL} model=${model}`);
  // Admission errors (401/403/429/503) throw here, before any byte is sent,
  // so the caller can still fall back to OpenRouter.
  const res = await postSiwcResponses(accessToken, buildSiwcResponsesBody(model, messages));

  const { readable, writable } = new TransformStream();
  const writer  = writable.getWriter();
  const encoder = new TextEncoder();

  const emit = async (delta: Record<string, unknown>, finish: string | null) => {
    const chunk = JSON.stringify({
      id:      'chatcmpl-siwc',
      object:  'chat.completion.chunk',
      model,
      choices: [{ index: 0, delta, finish_reason: finish }],
    });
    await writer.write(encoder.encode(`data: ${chunk}\n\n`));
  };

  (async () => {
    let finish = 'stop';
    try {
      for await (const ev of readSiwcStream(res)) {
        if (ev.kind === 'delta') {
          await emit({ content: ev.text }, null);
        } else if (ev.kind === 'failed') {
          finish = 'error';
          const err = new SiwcApiError(0, ev.code, ev.errorKind);
          await onFailure(err);
          if (ev.errorKind === 'usage_limit') {
            await emit({ content: SIWC_MIDSTREAM_LIMIT_TEXT }, null);
          }
        } else if (ev.kind === 'incomplete') {
          finish = 'length';
        }
      }
    } catch (err: any) {
      finish = 'error';
      console.error(`[AI ROUTER] siwc stream processing error: ${err?.name ?? 'Error'}`);
    } finally {
      try {
        await emit({}, finish);
        await writer.write(encoder.encode('data: [DONE]\n\n'));
      } catch { /* client gone */ }
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

/** Records a plan-usage failure so the next requests behave per the docs:
 *  not eligible -> stop using the plan (until the user signs in again);
 *  usage limit / unavailable -> bounded pause, keep credentials. */
async function recordSiwcFailure(supabaseAdmin: any, userId: string, err: any): Promise<string> {
  const kind = err instanceof SiwcApiError ? err.kind : 'unknown';
  const code = err instanceof SiwcApiError ? err.code : null;
  const reason =
    kind === 'not_eligible' || kind === 'config' ? 'not_eligible'
    : kind === 'usage_limit' ? 'usage_limit'
    : kind === 'temporarily_unavailable' ? 'plan_unavailable'
    : 'api_error';
  console.warn(`[AI ROUTER] siwc failed status=${err?.status ?? 0} code=${code ?? '-'} → ${reason}`);
  const update: Record<string, unknown> = {
    fallback_reason:    reason,
    last_provider_used: 'openrouter',
    updated_at:         new Date().toISOString(),
  };
  if (reason === 'usage_limit' || reason === 'plan_unavailable') {
    update.plan_paused_until = new Date(Date.now() + PLAN_PAUSE_MS).toISOString();
  }
  await supabaseAdmin.from('user_openai_links').update(update).eq('user_id', userId);
  return reason;
}

// ── Standard OpenAI Chat Completions (Gemini / Groq / OpenRouter) ──────────
async function callChat(
  a:         ProviderAttempt,
  messages:  any[],
  maxTokens: number = 1500,
): Promise<{ text: string; usage: any }> {
  console.log(`[AI ROUTER] → ${a.provider} model=${a.model} msgs=${messages.length} max_tokens=${maxTokens}`);

  const res = await timedFetch(a.endpoint, {
    method:  'POST',
    headers: {
      'Authorization': `Bearer ${a.apiKey}`,
      'Content-Type':  'application/json',
      ...a.headers,
    },
    body: JSON.stringify(chatBody(a, messages, maxTokens, false)),
  });

  if (!res.ok) {
    throw new Error(`HTTP ${res.status} ${await upstreamErrorCode(res)}`);
  }
  const rawBody = await res.text();
  console.log(`[AI ROUTER] ← status=${res.status}`);

  const data = JSON.parse(rawBody);
  const text = extractText(rawBody, data);
  if (!text) throw new Error(`Empty response from ${a.provider}`);

  console.log(`[AI ROUTER] extracted len=${text.length}`);
  return { text, usage: data.usage ?? null };
}

// ── Standard OpenAI streaming (Gemini / Groq / OpenRouter) ───────────────────
async function callChatStream(
  a:         ProviderAttempt,
  messages:  any[],
  maxTokens: number = 1500,
): Promise<Response> {
  console.log(`[AI ROUTER] stream → ${a.provider} model=${a.model} max_tokens=${maxTokens}`);

  const res = await timedFetch(a.endpoint, {
    method:  'POST',
    headers: {
      'Authorization': `Bearer ${a.apiKey}`,
      'Content-Type':  'application/json',
      ...a.headers,
    },
    body: JSON.stringify(chatBody(a, messages, maxTokens, true)),
  });

  if (!res.ok) {
    throw new Error(`HTTP ${res.status} ${await upstreamErrorCode(res)}`);
  }
  return res;
}

// ── Upstream error summary (code only; never bodies, which can echo input) ──
async function upstreamErrorCode(res: Response): Promise<string> {
  try {
    const j = JSON.parse(await res.text());
    const e = j?.error ?? j;
    const code = e?.code ?? e?.type ?? '';
    return typeof code === 'string' || typeof code === 'number' ? String(code).slice(0, 60) : '';
  } catch {
    return '';
  }
}

// ── Extract plain text from Chat Completions response ────────────────────────
function extractText(rawBody: string, data: any): string {
  const choice  = data?.choices?.[0];
  const message = choice?.message;
  if (!message) {
    console.error(`[AI ROUTER] No choices[0].message (len=${rawBody.length})`);
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
): Promise<{ accessToken: string; model: string; authMethod: 'siwc' | 'codex_device' } | null> {
  // select('*') so this keeps working before the siwc migration is applied
  // (auth_method is then simply absent and the link is treated as device-code).
  const { data, error } = await supabaseAdmin
    .from('user_openai_links')
    .select('*')
    .eq('user_id', userId)
    .maybeSingle();

  if (error || !data) return null;

  const authMethod: 'siwc' | 'codex_device' = data.auth_method === 'siwc' ? 'siwc' : 'codex_device';

  if (authMethod === 'siwc' && data.is_connected) {
    // Not eligible: don't retry or loop; the user re-signs in to clear it.
    if (data.fallback_reason === 'not_eligible') return null;
    // Usage limit / usage unavailable: bounded pause, credentials kept.
    const pausedUntil = data.plan_paused_until ? new Date(data.plan_paused_until).getTime() : 0;
    if (pausedUntil > Date.now()) return null;
  }

  if (!data.is_connected) {
    // Keep a siwc link's specific reason (e.g. reauth_required) intact.
    if (authMethod === 'siwc') return null;
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

  return { accessToken: refreshed.accessToken, model: data.selected_model, authMethod };
}

// ── Update last_provider_used after a successful call ─────────────────────────
async function trackUsage(supabaseAdmin: any, userId: string, provider: string): Promise<void> {
  const updateData: any = { 
    last_provider_used: provider, 
    last_used_at: new Date().toISOString() 
  };
  if (provider === 'user_chatgpt') {
    updateData.fallback_reason = null;
  }
  if (provider === 'user_chatgpt_plan') {
    // Plan-usage link answered: clear any earlier pause. Stored as
    // user_chatgpt so existing status consumers keep working.
    updateData.last_provider_used = 'user_chatgpt';
    updateData.fallback_reason = null;
    updateData.plan_paused_until = null;
  }
  await supabaseAdmin
    .from('user_openai_links')
    .update(updateData)
    .eq('user_id', userId);
}

// ── Main handler ─────────────────────────────────────────────────────────────
//
// Request: { purpose, messages, stream?, portion_anchor? }
//   purpose 'meal_estimate' | 'weekly_summary' | 'label_read' — app callers.
//     The server owns the system prompt; client system/developer messages are
//     dropped. 'label_read' takes exactly one photo, never streams, and its
//     answer is validated JSON (shared/label_read_prompt.ts) or a 422
//     { error: 'label_unreadable' }.
//   purpose 'coach' — only from ai-meal-coach with the internal header.
//   No purpose — legacy app builds; mapped by fingerprint (see ai_guard.ts).
// Errors: 400/403 bad request, 413 over a cap, 429 { error:'rate_limited',
//   retry_after, scope } — all JSON { success:false, error, message }.
const JSON_HEADERS = { ...corsHeaders, 'Content-Type': 'application/json' };

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'method_not_allowed' }), { status: 405, headers: JSON_HEADERS });
  }

  try {
    // ── Auth ──────────────────────────────────────────────────────────────────
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Missing Authorization header' }), {
        status: 401, headers: JSON_HEADERS,
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
      console.error(`[AI ROUTER] Auth failed`);
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401, headers: JSON_HEADERS,
      });
    }

    // ── Parse + guard request ─────────────────────────────────────────────────
    const secret = internalSecret();
    if (!secret && req.headers.get(INTERNAL_HEADER)) {
      // Fail closed: no fallback secret. The coach path is down until the
      // secret is set for both ai-meal-coach and ai-chat-router.
      console.error(`[AI ROUTER] ${INTERNAL_SECRET_ENV} is not set (or < 16 chars); rejecting internal coach request`);
      return jsonError(new AiGuardError(503, 'coach_unavailable', 'Kyno is unavailable right now. Try again later.'), corsHeaders);
    }
    const trusted = isTrustedInternal(req, secret);
    let body: any;
    try {
      body = await readJsonLimited(req, null);
    } catch (e) {
      if (e instanceof BodyTooLargeError) {
        console.warn(`[AI ROUTER] rejected user=${user.id} code=payload_too_large`);
        return jsonError(new AiGuardError(413, 'payload_too_large', 'That request is too large. Send fewer or smaller photos.', { limit_bytes: e.limit }), corsHeaders);
      }
      throw e;
    }
    let guarded: GuardedRequest;
    try {
      guarded = guardRequest(body, trusted);
    } catch (e) {
      if (e instanceof AiGuardError) {
        console.warn(`[AI ROUTER] rejected user=${user.id} code=${e.code}`);
        return jsonError(e, corsHeaders);
      }
      throw e;
    }
    const messages = guarded.messages;
    // JSON-only purposes (label_read) are validated whole, so never streamed.
    const streamMode: boolean = body?.stream === true && allowsStreaming(guarded.purpose);
    // The text a client receives: validated canonical JSON for label_read, or
    // a 422 the app reads as "couldn't read that label".
    const finalizeOrError = (text: string): string | Response => {
      try {
        return finalizeResponseText(guarded.purpose, text);
      } catch (e) {
        if (e instanceof AiGuardError) {
          console.warn(`[AI ROUTER] ${guarded.purpose} output rejected user=${user.id} code=${e.code}`);
          return jsonError(e, corsHeaders);
        }
        throw e;
      }
    };
    const maxTok = guarded.limits.maxOutputTokens;

    console.log(`[AI ROUTER] request user=${user.id} purpose=${guarded.purpose}${guarded.legacy ? ' (legacy)' : ''} msgs=${messages.length} chars=${guarded.textChars} images=${guarded.imageCount} stream=${streamMode}`);

    // ── Set up service-role client for token lookup + tracking ────────────────
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL')              ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    );


    // ── Resolve user's ChatGPT provider (if connected + verified) ────────────
    const userProvider = await getUserChatGptProvider(supabaseAdmin, user.id);
    const imageRequest = guarded.imageCount > 0;
    const isSiwc = userProvider?.authMethod === 'siwc';
    const useCodexForThisRequest = !!userProvider && !isSiwc && !imageRequest;
    const ownPlanFirst = isSiwc || useCodexForThisRequest;
    // Fallback chain after the user's plan: Gemini → Groq → OpenRouter free,
    // each present only when its key is set.
    const fallbackChain = buildFallbackChain((k: string) => Deno.env.get(k), imageRequest);
    const providerLabel = ownPlanFirst ? 'user_chatgpt' : (fallbackChain[0]?.provider ?? 'none');
    const activeFallbackModel = fallbackChain[0]?.model ?? 'none';

    // ── Rate limit (per user, per minute + per day) ──────────────────────────
    // Requests that will run on the user's own ChatGPT plan get a higher (still
    // bounded) cap. A fallback onto Kynetix's OpenRouter key is re-checked
    // against the standard cap below.
    // Daily photo cap for coach (vision is the costly path). Checked before
    // consumeQuota so a rejected request is not counted.
    if (guarded.purpose === 'coach' && guarded.imageCount > 0) {
      try {
        await enforceDailyImageCap(supabaseAdmin, user.id, guarded.imageCount);
      } catch (e) {
        if (e instanceof AiGuardError) {
          console.warn(`[AI ROUTER] rejected user=${user.id} code=${e.code} scope=${String(e.extra['scope'] ?? '-')}`);
          return jsonError(e, corsHeaders);
        }
        throw e;
      }
    }

    const stdTier = standardTier();
    const quota = await consumeQuota(
      supabaseAdmin, user.id, ownPlanFirst ? planTier() : stdTier,
      guarded.textChars, guarded.imageCount,
    );
    if (!quota.allowed) {
      const scope = quota.scope ?? 'minute';
      const retry = quota.retryAfter ?? (scope === 'day' ? secondsUntilUtcMidnight() : 60);
      console.warn(`[AI ROUTER] rate_limited user=${user.id} scope=${scope}`);
      return jsonError(rateLimitedError(scope, retry), corsHeaders);
    }
    /** null when the OpenRouter fallback is allowed for a plan-tier request. */
    const fallbackBlocked = (): Response | null => {
      if (!ownPlanFirst || !quota.enforced) return null;
      if (quota.dayRequests > stdTier.perDay) {
        return jsonError(rateLimitedError('day', secondsUntilUtcMidnight()), corsHeaders);
      }
      if (quota.minuteRequests > stdTier.perMinute) {
        return jsonError(rateLimitedError('minute', 60 - new Date().getUTCSeconds()), corsHeaders);
      }
      return null;
    };

    // Why a plan-usage (siwc) attempt fell back, surfaced to the client as
    // X-Fallback-Reason / plan_fallback_reason (e.g. 'usage_limit').
    let siwcFallbackReason: string | null = null;

    console.log(`[AI ROUTER] user=${user.id} stream=${streamMode} provider=${providerLabel} imageRequest=${imageRequest} model=${userProvider?.model ?? activeFallbackModel} chain=${fallbackChain.length}`);

    // ══════════════════════════════════════════════════
    // STREAMING PATH
    // ══════════════════════════════════════════════════
    if (streamMode) {
      // Codex (chatgpt.com/backend-api/codex/responses) is a text-only endpoint.
      // Skip it entirely for vision requests to avoid a guaranteed failure + wasted latency.

      // ── Attempt 1a: User's ChatGPT plan via the public Responses API ──────
      // Images are allowed here when the model accepts them.
      if (isSiwc) {
        try {
          const streamRes = await callSiwcStream(
            userProvider!.accessToken, userProvider!.model, messages,
            async (err) => { await recordSiwcFailure(supabaseAdmin, user.id, err); },
          );
          await trackUsage(supabaseAdmin, user.id, 'user_chatgpt_plan');
          console.log(`[AI ROUTER] streaming via user_chatgpt (plan) model=${userProvider!.model}`);
          const headers = new Headers(streamRes.headers);
          headers.set('X-Provider-Used', 'user_chatgpt');
          headers.set('X-Auth-Method', 'siwc');
          headers.set('X-Model-Used', userProvider!.model);
          return new Response(streamRes.body, { headers });
        } catch (err: any) {
          siwcFallbackReason = await recordSiwcFailure(supabaseAdmin, user.id, err);
          // Fall through to OpenRouter
        }
      }

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
          console.error(`[AI ROUTER] user_chatgpt (Codex) stream failed: ${String(err?.message ?? '').slice(0, 120)}`);
          await supabaseAdmin
            .from('user_openai_links')
            .update({ fallback_reason: 'api_error', last_provider_used: 'openrouter', updated_at: new Date().toISOString() })
            .eq('user_id', user.id);
          // Fall through to OpenRouter
        }
      } else if (userProvider && !isSiwc && imageRequest) {
        console.log(`[AI ROUTER] skipping Codex for vision request — routing directly to the fallback chain`);
      }

      // ── Attempt 2: free fallback chain (Gemini → Groq → OpenRouter free) ──
      const blockedS = fallbackBlocked();
      if (blockedS) return blockedS;
      for (const a of fallbackChain) {
        try {
          console.log(`[AI ROUTER] trying ${a.provider} model=${a.model} stream=true`);
          const sRes = await callChatStream(a, messages, maxTok);
          console.log(`[AI ROUTER] streaming via ${a.provider} model=${a.model}`);
          return new Response(sRes.body, {
            headers: {
              ...corsHeaders,
              'Content-Type':    'text/event-stream',
              'Cache-Control':   'no-cache',
              'X-Provider-Used': a.provider,
              'X-Model-Used':    a.model,
              ...(siwcFallbackReason ? { 'X-Fallback-Reason': siwcFallbackReason } : {}),
            },
          });
        } catch (err: any) {
          console.error(`[AI ROUTER] ${a.provider} stream failed model=${a.model}: ${String(err?.message ?? '').slice(0, 120)}`);
          // 402 no credits, 429 rate limited / quota, 5xx: try the next one
        }
      }

      return new Response(JSON.stringify({ success: false, error: 'All providers failed for streaming' }), {
        status: 503, headers: JSON_HEADERS,
      });
    }

    // ══════════════════════════════════════════════════
    // NON-STREAMING PATH
    // ══════════════════════════════════════════════════

    // ── Attempt 1a: User's ChatGPT plan via the public Responses API ────────
    if (isSiwc) {
      try {
        const { text, usage } = await callSiwc(
          userProvider!.accessToken, userProvider!.model, messages,
        );
        await trackUsage(supabaseAdmin, user.id, 'user_chatgpt_plan');
        console.log(`[AI ROUTER] provider=user_chatgpt (plan) model=${userProvider!.model} success`);
        const out = finalizeOrError(text);
        if (out instanceof Response) return out;
        return new Response(JSON.stringify({
          success:       true,
          provider_used: 'user_chatgpt',
          auth_method:   'siwc',
          model_used:    userProvider!.model,
          response:      out,
          usage,
          fallback_used: false,
        }), { status: 200, headers: JSON_HEADERS });
      } catch (err: any) {
        siwcFallbackReason = await recordSiwcFailure(supabaseAdmin, user.id, err);
        // Fall through to OpenRouter
      }
    }

    // ── Attempt 1: User's ChatGPT via Codex endpoint (text-only) ────────────
    if (useCodexForThisRequest) {
      try {
        const { text, usage } = await callCodex(
          userProvider!.accessToken, userProvider!.model, messages,
        );
        await trackUsage(supabaseAdmin, user.id, 'user_chatgpt');
        console.log(`[AI ROUTER] provider=user_chatgpt (Codex) model=${userProvider!.model} success`);
        const out = finalizeOrError(text);
        if (out instanceof Response) return out;
        return new Response(JSON.stringify({
          success:       true,
          provider_used: 'user_chatgpt',
          model_used:    userProvider!.model,
          response:      out,
          usage,
          fallback_used: false,
        }), { status: 200, headers: JSON_HEADERS });

      } catch (err: any) {
        console.error(`[AI ROUTER] user_chatgpt (Codex) failed: ${String(err?.message ?? '').slice(0, 120)}`);
        await supabaseAdmin
          .from('user_openai_links')
          .update({ fallback_reason: 'api_error', last_provider_used: 'openrouter', updated_at: new Date().toISOString() })
          .eq('user_id', user.id);
        // Fall through to OpenRouter
      }
    } else if (userProvider && !isSiwc && imageRequest) {
      console.log(`[AI ROUTER] skipping Codex for vision request — routing directly to the fallback chain`);
    }

    // ── Attempt 2: free fallback chain (Gemini → Groq → OpenRouter free) ────
    const blocked = fallbackBlocked();
    if (blocked) return blocked;
    if (fallbackChain.length === 0) {
      return new Response(JSON.stringify({
        success:       false,
        provider_used: 'none',
        error:         'No AI providers available. Connect your ChatGPT account or contact support.',
      }), { status: 503, headers: JSON_HEADERS });
    }

    let lastErr = '';
    for (const a of fallbackChain) {
      try {
        console.log(`[AI ROUTER] trying ${a.provider} model=${a.model} stream=false`);
        const { text, usage } = await callChat(a, messages, maxTok);
        console.log(`[AI ROUTER] provider=${a.provider} model=${a.model} success`);
        const out = finalizeOrError(text);
        if (out instanceof Response) return out;
        return new Response(JSON.stringify({
          success:       true,
          provider_used: a.provider,
          model_used:    a.model,
          response:      out,
          usage,
          fallback_used: !userProvider,
          ...(siwcFallbackReason ? { plan_fallback_reason: siwcFallbackReason } : {}),
        }), { status: 200, headers: JSON_HEADERS });
      } catch (err: any) {
        lastErr = String(err?.message ?? err);
        console.error(`[AI ROUTER] ${a.provider} model=${a.model} failed: ${lastErr.slice(0, 120)}`);
        // 402/429/5xx → try next
      }
    }
    console.error(`[AI ROUTER] all providers failed. lastErr=${lastErr.slice(0, 120)}`);
    // Only the upstream HTTP status (no bodies): 401 = bad key, 402 = out of
    // credits, 429 = rate limited. Lets the app and ops tell these apart.
    const upstream = /HTTP (\d{3})/.exec(lastErr)?.[1];
    return new Response(JSON.stringify({
      success:       false,
      provider_used: 'none',
      error:         'All AI providers failed',
      ...(upstream ? { upstream_status: Number(upstream) } : {}),
    }), { status: 503, headers: JSON_HEADERS });

  } catch (err: any) {
    console.error(`[AI ROUTER] Unhandled exception: ${err?.name ?? 'Error'}`);
    return new Response(JSON.stringify({ success: false, error: 'Internal Server Error' }), {
      status: 500, headers: JSON_HEADERS,
    });
  }
});
