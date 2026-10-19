// Fallback provider chain for ai-chat-router (after the user's own ChatGPT).
//
// Order: Gemini (Google AI Studio free tier) → Groq (free plan) → OpenRouter
// ':free' models. Every provider here speaks the OpenAI Chat Completions
// format (Gemini through its /v1beta/openai endpoint), so the router sends
// the same messages[] (text + base64 image_url parts) to each one.
//
// A provider whose key is not set is skipped silently. With no GEMINI/GROQ
// key the chain is just OpenRouter, as before.
//
// Model lists can be overridden without a code change with comma-separated
// secrets: GEMINI_TEXT_MODELS, GEMINI_VISION_MODELS, GROQ_TEXT_MODELS,
// GROQ_VISION_MODELS, OPENROUTER_TEXT_MODELS, OPENROUTER_VISION_MODELS.
// OpenRouter paid models are only tried when OPENROUTER_ALLOW_PAID=true.

export type ProviderName = 'gemini' | 'groq' | 'openrouter';

export interface ProviderAttempt {
  provider: ProviderName;
  model: string;
  endpoint: string;
  apiKey: string;
  headers: Record<string, string>;
  /** Extra Chat Completions body fields for this provider/model. */
  extraBody: Record<string, unknown>;
  /** Added to max_tokens: hidden reasoning tokens count against it. */
  reasoningHeadroom: number;
}

export const GEMINI_URL = 'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions';
export const GROQ_URL = 'https://api.groq.com/openai/v1/chat/completions';
export const OPENROUTER_URL = 'https://openrouter.ai/api/v1/chat/completions';

// Gemini free tier (stable models, Oct 2026). Flash-Lite is fastest and has
// the largest free daily quota; Flash is the stronger backup. Both take images.
export const GEMINI_TEXT_MODELS = ['gemini-3.5-flash-lite', 'gemini-3.8-flash'];
export const GEMINI_VISION_MODELS = ['gemini-3.5-flash-lite', 'gemini-3.8-flash'];

// Groq free plan. qwen3.8-27b is Groq's generally-available vision model.
export const GROQ_TEXT_MODELS = ['openai/gpt-oss-120b', 'llama-3.3-70b-versatile'];
export const GROQ_VISION_MODELS = ['qwen/qwen3.8-27b'];

// OpenRouter: free models only by default (the account has no credit).
export const OPENROUTER_FREE_TEXT_MODELS = [
  'nvidia/nemotron-3.5-super-vl:free',
  'openrouter/free',
];
export const OPENROUTER_FREE_VISION_MODELS = [
  'google/gemma-4-31b-it:free',
  'nvidia/nemotron-3.5-super-vl:free',
  'openrouter/free',
];
export const OPENROUTER_PAID_TEXT_MODELS = ['deepseek/deepseek-chat-v3-0324', 'google/gemini-2.5-flash-lite'];
export const OPENROUTER_PAID_VISION_MODELS = ['google/gemini-2.5-flash-lite', 'google/gemini-2.5-flash'];

const OPENROUTER_HEADERS = { 'HTTP-Referer': 'https://kynetix.app', 'X-Title': 'Kynetix AI Coach' };

export type EnvGet = (name: string) => string | undefined;

/** Comma-separated override, or the default list. */
export function modelList(env: EnvGet, name: string, fallback: string[]): string[] {
  const raw = (env(name) ?? '').trim();
  if (!raw) return fallback;
  const list = raw.split(',').map((s) => s.trim()).filter((s) => s.length > 0);
  return list.length > 0 ? list : fallback;
}

/** Keep reasoning short (latency) and out of the answer text. */
export function extraBodyFor(provider: ProviderName, model: string): Record<string, unknown> {
  if (provider === 'gemini') {
    // 2.5 models can turn thinking off; 3.x cannot, so ask for the least.
    return { reasoning_effort: model.startsWith('gemini-2.5') ? 'none' : 'minimal' };
  }
  if (provider === 'groq') {
    if (model.startsWith('openai/gpt-oss')) return { reasoning_effort: 'low', include_reasoning: false };
    if (model.startsWith('qwen/')) return { reasoning_effort: 'none' };
  }
  return {};
}

/** Extra max_tokens for models whose (hidden) reasoning counts as output. */
export function reasoningHeadroomFor(provider: ProviderName, model: string): number {
  if (provider === 'gemini' && !model.startsWith('gemini-2.5')) return 1024;
  if (provider === 'groq' && model.startsWith('openai/gpt-oss')) return 1024;
  return 0;
}

/** Ordered list of (provider, model) attempts, skipping providers with no key. */
export function buildFallbackChain(env: EnvGet, imageRequest: boolean): ProviderAttempt[] {
  const out: ProviderAttempt[] = [];
  const add = (provider: ProviderName, endpoint: string, apiKey: string, models: string[], headers: Record<string, string> = {}) => {
    if (!apiKey) return;
    for (const model of models) {
      out.push({ provider, model, endpoint, apiKey, headers, extraBody: extraBodyFor(provider, model), reasoningHeadroom: reasoningHeadroomFor(provider, model) });
    }
  };

  const geminiKey = (env('GEMINI_API_KEY') ?? '').trim();
  add('gemini', GEMINI_URL, geminiKey, imageRequest
    ? modelList(env, 'GEMINI_VISION_MODELS', GEMINI_VISION_MODELS)
    : modelList(env, 'GEMINI_TEXT_MODELS', GEMINI_TEXT_MODELS));

  const groqKey = (env('GROQ_API_KEY') ?? '').trim();
  add('groq', GROQ_URL, groqKey, imageRequest
    ? modelList(env, 'GROQ_VISION_MODELS', GROQ_VISION_MODELS)
    : modelList(env, 'GROQ_TEXT_MODELS', GROQ_TEXT_MODELS));

  const orKey = (env('OPENROUTER_API_KEY') ?? '').trim();
  const allowPaid = (env('OPENROUTER_ALLOW_PAID') ?? '').trim().toLowerCase() === 'true';
  const orFree = imageRequest
    ? modelList(env, 'OPENROUTER_VISION_MODELS', OPENROUTER_FREE_VISION_MODELS)
    : modelList(env, 'OPENROUTER_TEXT_MODELS', OPENROUTER_FREE_TEXT_MODELS);
  const orModels = allowPaid
    ? [...(imageRequest ? OPENROUTER_PAID_VISION_MODELS : OPENROUTER_PAID_TEXT_MODELS), ...orFree]
    : orFree.filter(isFreeOpenRouterModel);
  add('openrouter', OPENROUTER_URL, orKey, orModels, OPENROUTER_HEADERS);

  return out;
}

/** OpenRouter models that cost nothing: ':free' variants and the free router. */
export function isFreeOpenRouterModel(model: string): boolean {
  return model.endsWith(':free') || model === 'openrouter/free';
}

/** Providers whose Chat Completions endpoint accepts
 *  response_format {type:'json_object'}. Gemini's OpenAI-compatible endpoint
 *  documents response_format only with a JSON schema, so it is left out and
 *  relies on the prompt (the router validates the JSON either way). */
export function supportsJsonObjectMode(provider: ProviderName | undefined): boolean {
  return provider === 'groq' || provider === 'openrouter';
}

/** Body for a Chat Completions request to [a]. [jsonMode] asks for a single
 *  JSON object (non-streaming requests to providers that support it only). */
export function chatBody(
  a: Pick<ProviderAttempt, 'model' | 'extraBody' | 'reasoningHeadroom'> & { provider?: ProviderName },
  messages: unknown[],
  maxTokens: number,
  stream: boolean,
  jsonMode = false,
): Record<string, unknown> {
  const json = jsonMode && !stream && supportsJsonObjectMode(a.provider);
  return {
    model: a.model,
    messages,
    temperature: 0.25,
    max_tokens: maxTokens + a.reasoningHeadroom,
    ...a.extraBody,
    ...(json ? { response_format: { type: 'json_object' } } : {}),
    ...(stream ? { stream: true } : {}),
  };
}
