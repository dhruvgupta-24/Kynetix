// Shared helpers for "Sign in with ChatGPT" plan usage (auth_method = 'siwc').
//
// Docs: https://developers.openai.com/siwc/token-sharing-open-source/
//   - Inference: POST https://api.openai.com/v1/responses, Bearer access token,
//     stream: true + store: false on every request, context in `instructions`
//     + `input` (no system-role items), none of the unsupported fields.
//   - Models:    GET https://api.openai.com/v1/models -> { models: [{ slug,
//     display_name, visibility }] }, keep visibility == "list", server order.
//   - Success only after a `response.completed` event.
//
// Never log tokens or upstream bodies. Only status codes and error codes.

import { timedFetch } from './timed_fetch.ts';

export const SIWC_TOKEN_URL     = 'https://auth.openai.com/api/accounts/oauth/token';
export const SIWC_ISSUER        = 'https://auth.openai.com';
export const SIWC_RESOURCE      = 'https://api.openai.com/v1';
export const SIWC_RESPONSES_URL = 'https://api.openai.com/v1/responses';
export const SIWC_MODELS_URL    = 'https://api.openai.com/v1/models';
export const SIWC_PLAN_SCOPE    = 'chatgpt.tokens.use.direct';
export const MANAGE_USAGE_URL   = 'https://chatgpt.com/settings/usage';

/** Bounded pause after a usage-limit / usage-unavailable response. This is a
 *  backoff, not a guess at the plan's reset time. */
export const PLAN_PAUSE_MS = 10 * 60 * 1000;

export function hasPlanScope(scope: unknown): boolean {
  return typeof scope === 'string' && scope.split(/\s+/).includes(SIWC_PLAN_SCOPE);
}

// ── Error classification (errors-and-recovery) ───────────────────────────────

export type SiwcErrorKind =
  | 'not_eligible'       // don't retry, don't loop OAuth
  | 'usage_limit'        // pause plan requests, link to Manage usage
  | 'temporarily_unavailable' // keep creds, retry later with backoff
  | 'unsupported'        // drop the offending input / try another model
  | 'auth'               // credential problem; keep creds unless refresh says otherwise
  | 'config'             // client / grant configuration
  | 'unknown';

export function classifySiwcError(status: number, code: string | null): SiwcErrorKind {
  switch (code) {
    case 'subscription_sharing_user_not_eligible':
      return 'not_eligible';
    case 'subscription_sharing_usage_limit_exceeded':
      return 'usage_limit';
    case 'subscription_sharing_usage_unavailable':
    case 'subscription_sharing_user_unavailable':
      return 'temporarily_unavailable';
    case 'subscription_sharing_unsupported_capability':
      return 'unsupported';
    case 'subscription_sharing_invalid_user':
      return 'auth';
    case 'subscription_sharing_route_not_supported':
    case 'chatpass_v2_scope_not_authorized':
    case 'chatpass_v2_invalid_authorization_context':
      return 'config';
  }
  if (status === 429) return 'usage_limit';
  if (status === 503) return 'temporarily_unavailable';
  if (status === 401) return 'auth';
  return 'unknown';
}

/** Reads `error.code` / `error.param` from an error body without logging it. */
export async function readSiwcError(res: Response): Promise<{ code: string | null; param: string | null }> {
  try {
    const body = await res.json();
    const err = body?.error;
    if (err && typeof err === 'object') {
      return {
        code:  typeof err.code === 'string' ? err.code : null,
        param: typeof err.param === 'string' ? err.param : null,
      };
    }
    if (typeof err === 'string') return { code: err, param: null };
  } catch { /* not JSON */ }
  return { code: null, param: null };
}

export class SiwcApiError extends Error {
  constructor(
    public status: number,
    public code: string | null,
    public kind: SiwcErrorKind,
  ) {
    super(`siwc ${status} ${code ?? '-'}`);
  }
}

// ── Models ───────────────────────────────────────────────────────────────────

export async function listSiwcModels(accessToken: string): Promise<{
  status: number;
  code: string | null;
  slugs: string[];
}> {
  const res = await timedFetch(SIWC_MODELS_URL, {
    method:  'GET',
    headers: { 'Authorization': `Bearer ${accessToken}` },
  });
  if (!res.ok) {
    const { code } = await readSiwcError(res);
    return { status: res.status, code, slugs: [] };
  }
  let slugs: string[] = [];
  try {
    const data = await res.json();
    const list = Array.isArray(data?.models) ? data.models
      : Array.isArray(data?.data) ? data.data
      : [];
    slugs = list
      .filter((m: any) => m?.visibility === undefined || m?.visibility === 'list')
      .map((m: any) => m?.slug ?? m?.id)
      .filter((s: unknown): s is string => typeof s === 'string' && s.length > 0);
  } catch { /* leave empty */ }
  return { status: res.status, code: null, slugs };
}

// ── Request body ─────────────────────────────────────────────────────────────

/** Chat-style messages -> a plan-usage-safe Responses body. System messages are
 *  folded into `instructions`; full history goes in `input`. */
export function buildSiwcResponsesBody(model: string, messages: any[]): Record<string, unknown> {
  const instructions = messages
    .filter((m: any) => m?.role === 'system' && typeof m.content === 'string')
    .map((m: any) => m.content as string)
    .join('\n\n');

  const input = messages
    .filter((m: any) => m?.role !== 'system')
    .map((m: any) => {
      const role = m.role === 'assistant' ? 'assistant' : (m.role === 'developer' ? 'developer' : 'user');
      const textType = role === 'assistant' ? 'output_text' : 'input_text';
      let content: any[] = [];
      if (typeof m.content === 'string') {
        content = [{ type: textType, text: m.content }];
      } else if (Array.isArray(m.content)) {
        content = m.content.map((b: any) => {
          if (b?.type === 'text' || b?.type === 'input_text') {
            return { type: textType, text: b.text ?? '' };
          }
          if (b?.type === 'image_url' || b?.type === 'input_image') {
            const url = typeof b.image_url === 'string' ? b.image_url : (b.image_url?.url ?? '');
            // Public Responses API: image_url is a string, detail is a sibling.
            return { type: 'input_image', image_url: url, detail: 'auto' };
          }
          return { type: textType, text: typeof b === 'string' ? b : JSON.stringify(b) };
        });
      }
      return { type: 'message', role, content };
    });

  return {
    model,
    instructions,
    input,
    stream: true,
    store:  false,
  };
}

export async function postSiwcResponses(accessToken: string, body: Record<string, unknown>): Promise<Response> {
  const res = await timedFetch(SIWC_RESPONSES_URL, {
    method:  'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type':  'application/json',
      'Accept':        'text/event-stream',
    },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const { code } = await readSiwcError(res);
    throw new SiwcApiError(res.status, code, classifySiwcError(res.status, code));
  }
  return res;
}

// ── Streaming ────────────────────────────────────────────────────────────────

export type SiwcStreamEvent =
  | { kind: 'delta'; text: string }
  | { kind: 'completed' }
  | { kind: 'failed'; code: string | null; errorKind: SiwcErrorKind }
  | { kind: 'incomplete' };

/** Parses a Responses SSE stream into the few events we care about. */
export async function* readSiwcStream(res: Response): AsyncGenerator<SiwcStreamEvent> {
  const reader = res.body?.getReader();
  if (!reader) return;
  const decoder = new TextDecoder();
  let buffer = '';
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split('\n');
      buffer = lines.pop() ?? '';
      for (const line of lines) {
        if (!line.startsWith('data:')) continue;
        const payload = line.slice(5).trim();
        if (!payload || payload === '[DONE]') continue;
        let ev: any;
        try { ev = JSON.parse(payload); } catch { continue; }
        switch (ev?.type) {
          case 'response.output_text.delta':
            if (typeof ev.delta === 'string') yield { kind: 'delta', text: ev.delta };
            break;
          case 'response.completed':
            yield { kind: 'completed' };
            return;
          case 'response.incomplete':
            yield { kind: 'incomplete' };
            return;
          case 'response.failed':
          case 'error': {
            const code = ev?.response?.error?.code ?? ev?.error?.code ?? ev?.code ?? null;
            yield { kind: 'failed', code, errorKind: classifySiwcError(0, code) };
            return;
          }
        }
      }
    }
  } finally {
    try { reader.releaseLock(); } catch { /* ignore */ }
  }
}

/** Drains a stream to text. Throws unless `response.completed` arrived. */
export async function drainSiwcStream(res: Response): Promise<string> {
  let text = '';
  for await (const ev of readSiwcStream(res)) {
    if (ev.kind === 'delta') text += ev.text;
    else if (ev.kind === 'completed') return text;
    else if (ev.kind === 'failed') throw new SiwcApiError(0, ev.code, ev.errorKind);
    else if (ev.kind === 'incomplete') throw new SiwcApiError(0, 'response_incomplete', 'unknown');
  }
  throw new SiwcApiError(0, 'stream_ended_early', 'unknown');
}

// ── Model selection (used at link time and by openai-link-verify) ───────────

export interface SiwcSelection {
  ok: boolean;
  selectedModel: string | null;
  allSlugs: string[];
  testSnippet: string | null;
  usageLimited: boolean;
  /** Set when !ok. */
  errorKind?: SiwcErrorKind | 'no_models';
  errorCode?: string | null;
  tried: Array<{ model: string; result: string; code: string | null }>;
}

/** Lists the account's models and confirms one answers. A tiny probe, so plan
 *  eligibility problems surface at connect time, not mid-chat. */
export async function selectSiwcModel(accessToken: string): Promise<SiwcSelection> {
  const listed = await listSiwcModels(accessToken);
  const tried: SiwcSelection['tried'] = [];

  if (listed.status !== 200) {
    const kind = classifySiwcError(listed.status, listed.code);
    return { ok: false, selectedModel: null, allSlugs: [], testSnippet: null, usageLimited: false, errorKind: kind, errorCode: listed.code, tried };
  }
  if (listed.slugs.length === 0) {
    return { ok: false, selectedModel: null, allSlugs: [], testSnippet: null, usageLimited: false, errorKind: 'no_models', errorCode: null, tried };
  }

  for (const model of listed.slugs.slice(0, 3)) {
    try {
      const res = await postSiwcResponses(accessToken, buildSiwcResponsesBody(model, [
        { role: 'system', content: 'Reply with the single word OK.' },
        { role: 'user', content: 'ping' },
      ]));
      const text = await drainSiwcStream(res);
      tried.push({ model, result: 'success', code: null });
      return { ok: true, selectedModel: model, allSlugs: listed.slugs, testSnippet: text.trim().slice(0, 60), usageLimited: false, tried };
    } catch (err: any) {
      const e = err instanceof SiwcApiError ? err : new SiwcApiError(0, null, 'unknown');
      tried.push({ model, result: 'failed', code: e.code });
      switch (e.kind) {
        case 'unsupported':
        case 'unknown':
          continue; // try the next listed model
        case 'usage_limit':
        case 'temporarily_unavailable':
          // Credentials are fine; plan is busy or capped right now.
          return { ok: true, selectedModel: model, allSlugs: listed.slugs, testSnippet: null, usageLimited: e.kind === 'usage_limit', tried };
        default:
          return { ok: false, selectedModel: null, allSlugs: listed.slugs, testSnippet: null, usageLimited: false, errorKind: e.kind, errorCode: e.code, tried };
      }
    }
  }
  return { ok: false, selectedModel: null, allSlugs: listed.slugs, testSnippet: null, usageLimited: false, errorKind: 'unknown', errorCode: tried.at(-1)?.code ?? null, tried };
}
