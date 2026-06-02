// codex-model-probe — One-shot diagnostic: what models does this ChatGPT token have access to?
//
// This function:
//   1. Calls GET chatgpt.com/backend-api/models  → lists user's available models
//   2. Calls POST chatgpt.com/backend-api/codex/responses with NO model field
//      → lets backend auto-select, logs the raw response
//   3. Returns ALL raw data so we can see exactly what's available
//
// This is a diagnostic-only endpoint. NEVER returns the access_token to the client.

// @ts-ignore
import { createClient } from "npm:@supabase/supabase-js@2";

declare const Deno: any;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const MODELS_URL = 'https://chatgpt.com/backend-api/models';
const CODEX_URL  = 'https://chatgpt.com/backend-api/codex/responses';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return json({ error: 'Missing Authorization' }, 401);

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

  const { data: link } = await supabaseAdmin
    .from('user_openai_links')
    .select('access_token, is_connected')
    .eq('user_id', user.id)
    .single();

  if (!link?.access_token) return json({ error: 'No token in DB' }, 400);

  const accessToken = link.access_token;
  const report: any = { user_id: user.id };

  // ── Step 1: models endpoint ──────────────────────────────────────────────────
  try {
    const modelsRes = await fetch(MODELS_URL, {
      method: 'GET',
      headers: { 'Authorization': `Bearer ${accessToken}` },
    });
    const modelsBody = await modelsRes.text();
    report.models_endpoint = {
      status: modelsRes.status,
      body_preview: modelsBody.slice(0, 2000),
    };
  } catch (e: any) {
    report.models_endpoint = { error: e?.message };
  }

  // ── Step 2: try codex endpoint with NO model field ───────────────────────────
  try {
    const noModelRes = await fetch(CODEX_URL, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        instructions: '',
        stream: true,
        store:  false,
        input: [{ type: 'message', role: 'user',
          content: [{ type: 'input_text', text: 'Say: OK' }] }],
      }),
    });
    const bodyPreview = await noModelRes.text();
    report.no_model_probe = {
      status: noModelRes.status,
      body_preview: bodyPreview.slice(0, 2000),
    };
  } catch (e: any) {
    report.no_model_probe = { error: e?.message };
  }

  // ── Step 3: try a small set of specific model slugs, one at a time ───────────
  const candidates = ['gpt-5.5', 'gpt-5', 'gpt-5.4', 'o3', 'o4-mini'];
  report.single_probes = [];

  for (const model of candidates) {
    try {
      const res = await fetch(CODEX_URL, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model,
          instructions: '',
          stream: true,
          store:  false,
          input: [{ type: 'message', role: 'user',
            content: [{ type: 'input_text', text: 'Say: OK' }] }],
        }),
      });
      const raw = await res.text();
      report.single_probes.push({
        model,
        status: res.status,
        ok: res.ok,
        body_preview: raw.slice(0, 500),
      });
      // Stop at first success
      if (res.ok) break;
    } catch (e: any) {
      report.single_probes.push({ model, error: e?.message });
    }
  }

  return json(report);
});

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data, null, 2), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
