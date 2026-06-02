// openai-link-verify — Phase D/E: Codex model discovery + endpoint verification
//
// Strategy:
//   1. Query https://chatgpt.com/backend-api/models with the user's ChatGPT
//      OAuth token → get the list of real model slugs the user has access to.
//   2. Filter to candidates that look like Codex-capable models (gpt-5.x family,
//      o3, etc.) based on the model slug.
//   3. Try each candidate against backend-api/codex/responses until one succeeds.
//      Log the FULL raw response body for every attempt.
//   4. Persist the selected_model that worked + store raw model discovery data.
//
// WHY: The error "The 'X' model is not supported when using Codex with a
//   ChatGPT account." is returned by the Codex backend when the model slug in
//   the request body is not on the user's allowlist. The correct slug differs
//   by subscription tier (Plus, Pro, Team, Enterprise) and evolves over time.
//   The ONLY reliable way to find it is to ask the backend itself.

// @ts-ignore
import { createClient } from "npm:@supabase/supabase-js@2";

declare const Deno: any;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const MODELS_URL = 'https://chatgpt.com/backend-api/models';
const CODEX_URL  = 'https://chatgpt.com/backend-api/codex/responses';
const TEST_PROMPT = 'Say exactly: "OK"';

// Model slug patterns that indicate Codex/generation capability.
// We try slugs that match these patterns first; anything else is tried last.
const CODEX_PRIORITY_PATTERNS = [
  /^gpt-5/,
  /^o4/,
  /^o3/,
  /^codex/,
  /^gpt-4/,
  /^gpt-3/,
];

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // ── 1. Verify Supabase JWT ────────────────────────────────────────────────
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return json({ error: 'Missing Authorization header' }, 401);

    const jwt = authHeader.replace('Bearer ', '').trim();
    const supabaseAnon = createClient(
      Deno.env.get('SUPABASE_URL')      ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: `Bearer ${jwt}` } } },
    );
    const { data: { user }, error: userErr } = await supabaseAnon.auth.getUser();
    if (userErr || !user) return json({ error: 'Unauthorized' }, 401);

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL')              ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    );

    // ── 2. Retrieve stored access_token ──────────────────────────────────────
    const { data: link, error: linkErr } = await supabaseAdmin
      .from('user_openai_links')
      .select('access_token, is_connected')
      .eq('user_id', user.id)
      .single();

    if (linkErr || !link?.access_token) {
      return json({ error: 'No connected account found. Complete the auth flow first.' }, 400);
    }
    if (!link.is_connected) {
      return json({ error: 'Account is not connected' }, 400);
    }

    const accessToken = link.access_token;

    // ── 3. Discover available models from ChatGPT backend ────────────────────
    console.log(`[openai-link-verify] user=${user.id} — calling ${MODELS_URL}`);
    const discoveryResult = await discoverModels(accessToken);
    console.log(`[openai-link-verify] discovery: status=${discoveryResult.status} models_count=${discoveryResult.models.length}`);
    console.log(`[openai-link-verify] raw discovery body (first 1000): ${discoveryResult.rawBody.slice(0, 1000)}`);

    // ── 4. Build ordered candidate list ──────────────────────────────────────
    //   Priority 1: models returned by the discovery endpoint (user's actual entitlement)
    //   Priority 2: hardcoded gpt-5.x variants as last-resort fallbacks
    const discoveredSlugs = discoveryResult.models;
    const priorityCandidates: string[] = [];
    const restCandidates: string[] = [];

    for (const slug of discoveredSlugs) {
      if (CODEX_PRIORITY_PATTERNS.some(p => p.test(slug))) {
        priorityCandidates.push(slug);
      } else {
        restCandidates.push(slug);
      }
    }

    // Hardcoded fallbacks in case the models endpoint returns nothing useful
    const hardcodedFallbacks = [
      'gpt-5.5', 'gpt-5.4', 'gpt-5.4-pro', 'gpt-5.4-mini', 'gpt-5.4-nano',
      'gpt-5', 'o4-mini', 'o3', 'gpt-4o', 'gpt-4-turbo',
    ];
    // Add fallbacks not already in discovered set
    for (const f of hardcodedFallbacks) {
      if (!discoveredSlugs.includes(f)) restCandidates.push(f);
    }

    const allCandidates = [...priorityCandidates, ...restCandidates];

    console.log(`[openai-link-verify] candidates to try (${allCandidates.length}): ${allCandidates.slice(0, 10).join(', ')}`);

    // ── 5. Try each candidate against the Codex endpoint ─────────────────────
    let selectedModel:    string | null = null;
    let testSnippet:      string | null = null;
    const triedModels: Array<{
      model: string;
      status: number | null;
      result: string;
      rawBody?: string;
      text?: string;
    }> = [];

    for (const candidate of allCandidates) {
      console.log(`[openai-link-verify] Trying model="${candidate}"`);
      const probe = await probeCodexEndpoint(accessToken, candidate);

      triedModels.push({
        model:   candidate,
        status:  probe.httpStatus,
        result:  probe.success ? 'success' : 'failed',
        rawBody: probe.rawError?.slice(0, 500),
        text:    probe.text?.slice(0, 100),
      });

      if (probe.success) {
        selectedModel = candidate;
        testSnippet   = probe.text ?? null;
        console.log(`[openai-link-verify] ✅ model="${candidate}" works. text="${probe.text?.slice(0, 80)}"`);
        break;
      } else {
        console.warn(`[openai-link-verify] ❌ model="${candidate}" → HTTP ${probe.httpStatus}: ${probe.rawError?.slice(0, 300)}`);

        // If auth error, stop immediately — the token itself is the problem
        if (probe.httpStatus === 401 || probe.httpStatus === 403) {
          console.error(`[openai-link-verify] Auth error — stopping candidate loop.`);
          break;
        }
      }
    }

    // ── 6. Persist results ────────────────────────────────────────────────────
    const verified = selectedModel !== null;
    await persistDiscovery(
      supabaseAdmin, user.id, selectedModel, verified, testSnippet,
      discoveredSlugs, triedModels,
    );

    if (!verified) {
      return json({
        success:         false,
        error:           'generation_failed',
        message:         'All model candidates failed. See tried[] for raw upstream errors.',
        endpoint_probed: CODEX_URL,
        discovery:       discoveryResult.models.slice(0, 30),
        tried:           triedModels,
      }, 400);
    }

    return json({
      success:          true,
      selected_model:   selectedModel,
      endpoint_used:    CODEX_URL,
      test_snippet:     testSnippet,
      discovered:       discoveredSlugs.slice(0, 30),
      tried:            triedModels,
    });

  } catch (err: any) {
    console.error(`[openai-link-verify] Unhandled: ${err?.message ?? err}`);
    return json({ error: 'Internal Server Error' }, 500);
  }
});

// ── Discover models from ChatGPT backend ─────────────────────────────────────
// GET https://chatgpt.com/backend-api/models
// Returns a list of model slugs the authenticated user can access.
async function discoverModels(accessToken: string): Promise<{
  status: number;
  models: string[];
  rawBody: string;
}> {
  try {
    const res = await fetch(MODELS_URL, {
      method:  'GET',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type':  'application/json',
      },
    });

    const rawBody = await res.text();
    console.log(`[openai-link-verify] ${MODELS_URL} → status=${res.status}`);

    if (!res.ok) {
      console.warn(`[openai-link-verify] model discovery failed: ${rawBody.slice(0, 400)}`);
      return { status: res.status, models: [], rawBody };
    }

    // The response is either:
    // { models: [{ slug: "...", ... }] }  ← ChatGPT backend format
    // { data: [{ id: "...", ... }] }       ← OpenAI API format (unlikely here)
    let models: string[] = [];
    try {
      const data = JSON.parse(rawBody);

      // Format A: { models: [...] }
      if (Array.isArray(data?.models)) {
        models = data.models
          .map((m: any) => m?.slug ?? m?.id ?? m?.name)
          .filter(Boolean);
      }
      // Format B: { data: [...] } (OpenAI compat)
      else if (Array.isArray(data?.data)) {
        models = data.data
          .map((m: any) => m?.id ?? m?.slug)
          .filter(Boolean);
      }
      // Format C: flat array of strings
      else if (Array.isArray(data)) {
        models = data.map((m: any) =>
          typeof m === 'string' ? m : (m?.slug ?? m?.id)
        ).filter(Boolean);
      }
    } catch {
      console.warn(`[openai-link-verify] Failed to parse model discovery JSON`);
    }

    console.log(`[openai-link-verify] Discovered ${models.length} models: ${models.slice(0, 10).join(', ')}`);
    return { status: res.status, models, rawBody };

  } catch (err: any) {
    console.error(`[openai-link-verify] discoverModels exception: ${err?.message}`);
    return { status: 0, models: [], rawBody: err?.message ?? '' };
  }
}

// ── Probe the Codex endpoint with a specific model ────────────────────────────
async function probeCodexEndpoint(
  accessToken: string,
  model:       string,
): Promise<{
  success:    boolean;
  httpStatus: number | null;
  text?:      string;
  rawError?:  string;
}> {
  try {
    const body = {
      model,
      instructions: '',
      stream:        true,
      store:         false,
      input: [{
        type:    'message',
        role:    'user',
        content: [{ type: 'input_text', text: TEST_PROMPT }],
      }],
    };

    const res = await fetch(CODEX_URL, {
      method:  'POST',
      headers: {
        'Content-Type':  'application/json',
        'Authorization': `Bearer ${accessToken}`,
      },
      body: JSON.stringify(body),
    });

    if (!res.ok) {
      const errBody = await res.text();
      return {
        success:    false,
        httpStatus: res.status,
        rawError:   errBody,
      };
    }

    // Parse SSE stream to extract generated text
    const text = await drainCodexSSE(res);
    if (!text || text.trim().length === 0) {
      return {
        success:    false,
        httpStatus: res.status,
        rawError:   'Received empty text response from stream',
      };
    }

    return { success: true, httpStatus: res.status, text: text.trim() };

  } catch (err: any) {
    return {
      success:    false,
      httpStatus: null,
      rawError:   err?.message ?? String(err),
    };
  }
}

// ── Drain Codex SSE → plain text ─────────────────────────────────────────────
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
            if (!fullText) fullText = ev.text;
          } else if (typeof ev?.choices?.[0]?.delta?.content === 'string') {
            fullText += ev.choices[0].delta.content;
          } else if (typeof ev?.delta === 'string') {
            fullText += ev.delta;
          }
        } catch { /* skip malformed lines */ }
      }
    }
  } finally {
    try { reader.releaseLock(); } catch { /* ignore */ }
  }

  return fullText;
}

// ── Persist discovery results ─────────────────────────────────────────────────
async function persistDiscovery(
  admin:          any,
  userId:         string,
  selectedModel:  string | null,
  verified:       boolean,
  testSnippet:    string | null,
  discoveredSlugs: string[],
  triedModels:    any[],
): Promise<void> {
  const { error } = await admin
    .from('user_openai_links')
    .update({
      selected_model:           selectedModel,
      discovered_models:        {
        all:          discoveredSlugs,
        chat_capable: triedModels.filter(t => t.result === 'success').map(t => t.model),
        endpoint:     CODEX_URL,
        tried:        triedModels,
      },
      discovery_timestamp:      new Date().toISOString(),
      model_discovery_verified: verified,
      test_generation_snippet:  testSnippet,
      updated_at:               new Date().toISOString(),
    })
    .eq('user_id', userId);

  if (error) {
    console.error(`[openai-link-verify] persistDiscovery error: ${error.message}`);
  }
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
