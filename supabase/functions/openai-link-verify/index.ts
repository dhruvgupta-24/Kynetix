// openai-link-verify — Phase D/E: Model discovery + generation verification
//
// Called immediately after successful token exchange (openai-link-poll returns 'connected').
//
// Responsibilities:
//   1. Verify Supabase JWT
//   2. Retrieve user's access_token from user_openai_links (server-side only)
//   3. GET /v1/models — discover ALL models the token can access
//   4. Filter & rank chat-capable models by capability (newest first)
//   5. For each candidate model (highest priority first):
//      - Attempt a real test generation (short prompt, ≤50 tokens)
//      - First model that succeeds = selected_model
//   6. Persist: selected_model, discovered_models[], discovery_timestamp, test_snippet
//   7. Return discovery report to client (no tokens)
//
// NEVER falls back to a hardcoded model. If no model passes generation test → error.

// @ts-ignore
import { createClient } from "npm:@supabase/supabase-js@2";

declare const Deno: any;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const OPENAI_API_BASE = 'https://api.openai.com/v1';

// ── Model ranking heuristic ───────────────────────────────────────────────────
// Order: newest/most capable first. We do NOT hardcode which models exist —
// this list is just the tiebreaker sort order for models discovered at runtime.
// Any model NOT in this list gets deprioritized to the end (by creation date desc).
const MODEL_PRIORITY_PREFIXES: string[] = [
  'o3',
  'o4',
  'gpt-5',
  'gpt-4.5',
  'gpt-4.1',
  'gpt-4o',      // below o-series and 4.x
  'codex',
  'gpt-4',
  'gpt-3.5',
];

// Models to explicitly skip (non-chat, deprecated, embedding, etc.)
const SKIP_PATTERNS = [
  'whisper', 'dall-e', 'tts', 'embedding', 'davinci', 'babbage',
  'curie', 'ada', 'instruct', 'text-', 'code-', 'audio', 'realtime',
  'moderation', 'vision', 'image', 'transcrib', 'translate',
];

// Test prompt for generation verification
const TEST_PROMPT = 'Reply with exactly: "Kynetix verification OK"';

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
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: `Bearer ${jwt}` } } },
    );
    const { data: { user }, error: userErr } = await supabaseAnon.auth.getUser();
    if (userErr || !user) return json({ error: 'Unauthorized' }, 401);

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    );

    // ── 2. Retrieve user's access_token (server-side only, never sent to client)
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
    console.log(`[openai-link-verify] user=${user.id} — starting model discovery`);

    // ── 3. Query /v1/models ───────────────────────────────────────────────────
    const modelsRes = await fetch(`${OPENAI_API_BASE}/models`, {
      headers: { 'Authorization': `Bearer ${accessToken}` },
    });

    if (!modelsRes.ok) {
      const errBody = await modelsRes.text();
      console.error(`[openai-link-verify] /v1/models failed: ${modelsRes.status} ${errBody.slice(0, 300)}`);
      return json({
        error: 'model_discovery_failed',
        status: modelsRes.status,
        message: `Failed to list models. Token may be invalid or expired. HTTP ${modelsRes.status}`,
      }, 502);
    }

    const modelsData = await modelsRes.json();
    const allModels: any[] = modelsData.data ?? [];
    console.log(`[openai-link-verify] Total models returned by API: ${allModels.length}`);

    // ── 4. Filter to chat-capable models ─────────────────────────────────────
    const chatModels = allModels
      .filter((m: any) => {
        const id: string = (m.id ?? '').toLowerCase();
        // Skip non-chat models
        if (SKIP_PATTERNS.some(p => id.includes(p))) return false;
        // Must be a gpt/o-series/codex chat model
        return id.startsWith('gpt-') || id.startsWith('o1') || id.startsWith('o3')
          || id.startsWith('o4') || id.startsWith('codex') || id.startsWith('chatgpt');
      })
      .map((m: any) => m.id as string);

    console.log(`[openai-link-verify] Chat-capable models (${chatModels.length}): ${chatModels.join(', ')}`);

    if (chatModels.length === 0) {
      await persistDiscovery(supabaseAdmin, user.id, [], null, false, null, allModels.map((m: any) => m.id));
      return json({
        success: false,
        error: 'no_chat_models',
        message: 'No chat-capable models found in this account',
        all_discovered: allModels.map((m: any) => m.id),
      }, 400);
    }

    // ── 5. Sort by capability (priority prefixes order) ───────────────────────
    const sorted = sortModelsByPriority(chatModels);
    console.log(`[openai-link-verify] Models ranked: ${sorted.join(', ')}`);

    // ── 6. Test each candidate until one succeeds ─────────────────────────────
    let selectedModel: string | null = null;
    let testSnippet: string | null = null;
    let selectionReason = '';
    const triedModels: Array<{ model: string; result: 'success' | 'failed'; error?: string }> = [];

    for (const model of sorted) {
      console.log(`[openai-link-verify] Testing generation with model="${model}"...`);
      const result = await testGeneration(accessToken, model);

      if (result.success) {
        selectedModel = model;
        testSnippet = result.text ?? null;
        selectionReason = `Highest priority model that passed real generation test (tried ${triedModels.length + 1} model(s))`;
        triedModels.push({ model, result: 'success' });
        console.log(`[openai-link-verify] ✅ model="${model}" works. snippet="${result.text?.slice(0, 80)}"`);
        break;
      } else {
        triedModels.push({ model, result: 'failed', error: result.error });
        console.warn(`[openai-link-verify] ❌ model="${model}" failed: ${result.error?.slice(0, 100)}`);
      }
    }

    // ── 7. Persist results ────────────────────────────────────────────────────
    const verified = selectedModel !== null;
    await persistDiscovery(
      supabaseAdmin, user.id, sorted, selectedModel, verified,
      testSnippet, allModels.map((m: any) => m.id),
    );

    if (!verified) {
      return json({
        success: false,
        error: 'generation_failed',
        message: 'No model passed the generation test. Your account may not have API access.',
        tried: triedModels,
        chat_models_found: sorted,
        all_discovered: allModels.map((m: any) => m.id),
      }, 400);
    }

    // ── 8. Return discovery report ────────────────────────────────────────────
    return json({
      success:           true,
      selected_model:    selectedModel,
      selection_reason:  selectionReason,
      chat_models_found: sorted,
      all_discovered:    allModels.map((m: any) => m.id),
      generation_tested: triedModels,
      test_snippet:      testSnippet,
    });

  } catch (err: any) {
    console.error(`[openai-link-verify] Unhandled: ${err?.message ?? err}`);
    return json({ error: 'Internal Server Error' }, 500);
  }
});

// ── Sort models by priority prefix order (newest/best first) ─────────────────
function sortModelsByPriority(models: string[]): string[] {
  return [...models].sort((a, b) => {
    const aIdx = MODEL_PRIORITY_PREFIXES.findIndex(p => a.toLowerCase().startsWith(p));
    const bIdx = MODEL_PRIORITY_PREFIXES.findIndex(p => b.toLowerCase().startsWith(p));

    // Both found in priority list
    if (aIdx !== -1 && bIdx !== -1) {
      if (aIdx !== bIdx) return aIdx - bIdx; // lower index = higher priority
      // Same prefix family: sort by version descending (newer = higher)
      return compareModelVersions(b, a);
    }
    // One found, one not
    if (aIdx !== -1) return -1;
    if (bIdx !== -1) return 1;
    // Neither found: sort alphabetically descending (guessing newer)
    return b.localeCompare(a);
  });
}

// Extract numeric versions for comparison (e.g. gpt-4o vs gpt-4o-mini)
function compareModelVersions(a: string, b: string): number {
  // Prefer non-mini models
  const aMini = a.includes('mini');
  const bMini = b.includes('mini');
  if (aMini !== bMini) return aMini ? 1 : -1;
  // Otherwise lexicographic descending
  return a.localeCompare(b);
}

// ── Test generation with a specific model ─────────────────────────────────────
async function testGeneration(
  accessToken: string,
  model: string,
): Promise<{ success: boolean; text?: string; error?: string }> {
  try {
    const res = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type':  'application/json',
      },
      body: JSON.stringify({
        model,
        messages: [{ role: 'user', content: TEST_PROMPT }],
        max_tokens: 50,
        temperature: 0,
      }),
    });

    if (!res.ok) {
      const errBody = await res.text();
      return { success: false, error: `HTTP ${res.status}: ${errBody.slice(0, 200)}` };
    }

    const data = await res.json();
    const text = data?.choices?.[0]?.message?.content ?? '';
    if (!text.trim()) {
      return { success: false, error: 'Empty response from model' };
    }
    return { success: true, text: text.trim() };

  } catch (err: any) {
    return { success: false, error: err?.message ?? String(err) };
  }
}

// ── Persist discovery results to user_openai_links ───────────────────────────
async function persistDiscovery(
  admin: any,
  userId: string,
  rankedChatModels: string[],
  selectedModel: string | null,
  verified: boolean,
  testSnippet: string | null,
  allModelIds: string[],
): Promise<void> {
  const { error } = await admin
    .from('user_openai_links')
    .update({
      selected_model:           selectedModel,
      discovered_models:        { all: allModelIds, chat_capable: rankedChatModels },
      discovery_timestamp:      new Date().toISOString(),
      model_discovery_verified: verified,
      test_generation_snippet:  testSnippet,
      updated_at:               new Date().toISOString(),
    })
    .eq('user_id', userId);

  if (error) {
    console.error(`[openai-link-verify] Failed to persist discovery: ${error.message}`);
  }
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
