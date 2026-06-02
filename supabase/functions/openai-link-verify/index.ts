// openai-link-verify — Phase D/E: Codex endpoint probe + verification
//
// The ChatGPT OAuth token obtained via the device-auth flow is a SESSION token
// that authenticates to chatgpt.com/backend-api/codex, NOT the OpenAI Platform API.
//
// Calling /v1/models or /v1/chat/completions with this token will always return
// HTTP 403 — those endpoints require a Platform API key.
//
// This function instead:
//   1. Verifies the Supabase JWT.
//   2. Retrieves the user's access_token from user_openai_links (server-side only).
//   3. Probes https://chatgpt.com/backend-api/codex/responses with a short test prompt.
//   4. Parses the SSE stream to confirm a real text response was received.
//   5. Persists selected_model = "codex" and model_discovery_verified = true.

// @ts-ignore
import { createClient } from "npm:@supabase/supabase-js@2";

declare const Deno: any;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const CODEX_URL   = 'https://chatgpt.com/backend-api/codex/responses';
const TEST_PROMPT = 'Reply with exactly: "Kynetix verification OK"';

// Model candidates to try in order. The backend may reject unknown names.
const MODEL_CANDIDATES = ['codex', 'gpt-5.3-codex', 'gpt-4o'];

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

    // ── 2. Retrieve access_token (server-side only — never sent to client) ───
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
    console.log(`[openai-link-verify] user=${user.id} — probing Codex endpoint at ${CODEX_URL}`);

    // ── 3. Probe Codex endpoint — try each model candidate until one works ───
    let selectedModel: string | null = null;
    let testSnippet:   string | null = null;
    const triedModels: Array<{ model: string; result: string; error?: string }> = [];

    for (const candidate of MODEL_CANDIDATES) {
      console.log(`[openai-link-verify] Probing with model="${candidate}"`);
      const result = await probeCodexEndpoint(accessToken, candidate);

      if (result.success) {
        selectedModel = candidate;
        testSnippet   = result.text ?? null;
        triedModels.push({ model: candidate, result: 'success' });
        console.log(`[openai-link-verify] ✅ model="${candidate}" OK. snippet="${result.text?.slice(0, 80)}"`);
        break;
      } else {
        triedModels.push({ model: candidate, result: 'failed', error: result.error });
        console.warn(`[openai-link-verify] ❌ model="${candidate}" → ${result.error?.slice(0, 200)}`);
        // If the error is auth-related (401/403), stop trying — the token itself is bad.
        if (result.error?.startsWith('HTTP 401') || result.error?.startsWith('HTTP 403')) {
          console.error(`[openai-link-verify] Auth error — stopping candidate loop early.`);
          break;
        }
      }
    }

    // ── 4. Persist results ────────────────────────────────────────────────────
    await persistDiscovery(supabaseAdmin, user.id, selectedModel, selectedModel !== null, testSnippet);

    if (!selectedModel) {
      return json({
        success: false,
        error:   'generation_failed',
        message: 'Codex endpoint probe failed for all model candidates. The connected token may lack Codex access.',
        endpoint_probed: CODEX_URL,
        tried: triedModels,
      }, 400);
    }

    // ── 5. Return success report ──────────────────────────────────────────────
    return json({
      success:          true,
      selected_model:   selectedModel,
      endpoint_used:    CODEX_URL,
      test_snippet:     testSnippet,
      generation_tested: triedModels,
    });

  } catch (err: any) {
    console.error(`[openai-link-verify] Unhandled: ${err?.message ?? err}`);
    return json({ error: 'Internal Server Error' }, 500);
  }
});

// ── Probe the Codex backend with a single candidate model ───────────────────
async function probeCodexEndpoint(
  accessToken: string,
  model:       string,
): Promise<{ success: boolean; text?: string; error?: string }> {
  try {
    const res = await fetch(CODEX_URL, {
      method: 'POST',
      headers: {
        'Content-Type':  'application/json',
        'Authorization': `Bearer ${accessToken}`,
      },
      body: JSON.stringify({
        model,
        instructions: '',
        stream:        true,
        store:         false,
        input: [{
          type:    'message',
          role:    'user',
          content: [{ type: 'input_text', text: TEST_PROMPT }],
        }],
      }),
    });

    if (!res.ok) {
      const errBody = await res.text();
      return { success: false, error: `HTTP ${res.status}: ${errBody.slice(0, 300)}` };
    }

    // The Codex endpoint always streams — consume the SSE to extract text.
    const text = await drainCodexSSE(res);
    if (!text || text.trim().length === 0) {
      return { success: false, error: 'Received empty text from Codex stream' };
    }
    return { success: true, text: text.trim() };

  } catch (err: any) {
    return { success: false, error: err?.message ?? String(err) };
  }
}

// ── Drain a Codex SSE stream and return accumulated text ─────────────────────
// Handles both the Responses-API event format (response.output_text.delta)
// and any OpenAI-compatible fallback (choices[].delta.content).
export async function drainCodexSSE(res: Response): Promise<string> {
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
      buffer = lines.pop() ?? ''; // retain incomplete trailing line

      for (const line of lines) {
        if (!line.startsWith('data: ')) continue;
        const payload = line.slice(6).trim();
        if (payload === '[DONE]') return fullText;

        try {
          const ev = JSON.parse(payload);

          // ① Responses API — text delta
          if (ev?.type === 'response.output_text.delta' && typeof ev.delta === 'string') {
            fullText += ev.delta;
            continue;
          }
          // ② Responses API — output_text done (use as fallback if delta was empty)
          if (ev?.type === 'response.output_text.done' && typeof ev.text === 'string') {
            if (fullText.length === 0) fullText = ev.text;
            continue;
          }
          // ③ OpenAI Chat Completions compatible delta (just in case)
          const chatDelta = ev?.choices?.[0]?.delta?.content;
          if (typeof chatDelta === 'string') {
            fullText += chatDelta;
            continue;
          }
          // ④ Flat delta (some gateway proxies)
          if (typeof ev?.delta === 'string') {
            fullText += ev.delta;
          }
        } catch { /* ignore malformed JSON lines */ }
      }
    }
  } finally {
    try { reader.releaseLock(); } catch { /* already released */ }
  }

  return fullText;
}

// ── Persist discovery results to user_openai_links ───────────────────────────
async function persistDiscovery(
  admin:        any,
  userId:       string,
  selectedModel: string | null,
  verified:     boolean,
  testSnippet:  string | null,
): Promise<void> {
  const { error } = await admin
    .from('user_openai_links')
    .update({
      selected_model:           selectedModel,
      discovered_models:        { all: MODEL_CANDIDATES, chat_capable: MODEL_CANDIDATES, endpoint: CODEX_URL },
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
