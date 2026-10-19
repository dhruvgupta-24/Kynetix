// deno test --allow-env supabase/functions/shared/free_providers_test.ts
import {
  buildFallbackChain,
  chatBody,
  GEMINI_URL,
  GROQ_URL,
  isFreeOpenRouterModel,
  modelList,
  OPENROUTER_URL,
} from './free_providers.ts';

function assert(cond: unknown, msg: string) {
  if (!cond) throw new Error(msg);
}
function eq(a: unknown, b: unknown, msg: string) {
  const ja = JSON.stringify(a), jb = JSON.stringify(b);
  if (ja !== jb) throw new Error(`${msg}: ${ja} !== ${jb}`);
}
const envOf = (vars: Record<string, string>) => (k: string) => vars[k];
const providers = (chain: { provider: string }[]) => [...new Set(chain.map((a) => a.provider))];

Deno.test('no keys set → empty chain', () => {
  eq(buildFallbackChain(envOf({}), false), [], 'text');
  eq(buildFallbackChain(envOf({}), true), [], 'vision');
});

Deno.test('only OpenRouter key → OpenRouter free models only (unchanged fallthrough)', () => {
  const chain = buildFallbackChain(envOf({ OPENROUTER_API_KEY: 'k' }), false);
  eq(providers(chain), ['openrouter'], 'providers');
  assert(chain.length > 0, 'has models');
  assert(chain.every((a) => isFreeOpenRouterModel(a.model)), 'free only');
  assert(chain.every((a) => a.endpoint === OPENROUTER_URL), 'endpoint');
  assert(chain[0].headers['X-Title'] === 'Kynetix AI Coach', 'openrouter headers kept');
});

Deno.test('order is Gemini → Groq → OpenRouter when all keys set', () => {
  const env = envOf({ GEMINI_API_KEY: 'g', GROQ_API_KEY: 'q', OPENROUTER_API_KEY: 'o' });
  for (const vision of [false, true]) {
    const chain = buildFallbackChain(env, vision);
    eq(providers(chain), ['gemini', 'groq', 'openrouter'], `order vision=${vision}`);
    const firstIdx = (p: string) => chain.findIndex((a) => a.provider === p);
    const lastIdx = (p: string) => chain.map((a): string => a.provider).lastIndexOf(p);
    assert(lastIdx('gemini') < firstIdx('groq'), 'gemini block before groq');
    assert(lastIdx('groq') < firstIdx('openrouter'), 'groq block before openrouter');
  }
});

Deno.test('each provider skipped silently when its key is missing or blank', () => {
  eq(providers(buildFallbackChain(envOf({ GROQ_API_KEY: 'q', OPENROUTER_API_KEY: 'o' }), false)), ['groq', 'openrouter'], 'no gemini');
  eq(providers(buildFallbackChain(envOf({ GEMINI_API_KEY: 'g', OPENROUTER_API_KEY: 'o' }), true)), ['gemini', 'openrouter'], 'no groq');
  eq(providers(buildFallbackChain(envOf({ GEMINI_API_KEY: '  ', GROQ_API_KEY: 'q' }), false)), ['groq'], 'blank gemini');
});

Deno.test('keys and endpoints go with their provider', () => {
  const chain = buildFallbackChain(envOf({ GEMINI_API_KEY: 'g', GROQ_API_KEY: 'q', OPENROUTER_API_KEY: 'o' }), false);
  for (const a of chain) {
    if (a.provider === 'gemini') assert(a.apiKey === 'g' && a.endpoint === GEMINI_URL, 'gemini');
    if (a.provider === 'groq') assert(a.apiKey === 'q' && a.endpoint === GROQ_URL, 'groq');
    if (a.provider === 'openrouter') assert(a.apiKey === 'o' && a.endpoint === OPENROUTER_URL, 'openrouter');
  }
});

Deno.test('paid OpenRouter models only with OPENROUTER_ALLOW_PAID=true, and after Gemini/Groq', () => {
  const base = { GEMINI_API_KEY: 'g', OPENROUTER_API_KEY: 'o' };
  const noPaid = buildFallbackChain(envOf(base), false).filter((a) => a.provider === 'openrouter');
  assert(noPaid.every((a) => isFreeOpenRouterModel(a.model)), 'default free only');
  const overridden = buildFallbackChain(envOf({ ...base, OPENROUTER_TEXT_MODELS: 'deepseek/x,foo/bar:free' }), false)
    .filter((a) => a.provider === 'openrouter');
  eq(overridden.map((a) => a.model), ['foo/bar:free'], 'paid override filtered without opt-in');
  const paid = buildFallbackChain(envOf({ ...base, OPENROUTER_ALLOW_PAID: 'true' }), false);
  assert(paid[0].provider === 'gemini', 'gemini still first');
  assert(paid.some((a) => a.provider === 'openrouter' && !isFreeOpenRouterModel(a.model)), 'paid present');
});

Deno.test('vision vs text model lists and env overrides', () => {
  const env = envOf({ GEMINI_API_KEY: 'g', GROQ_API_KEY: 'q', GROQ_VISION_MODELS: ' a/b , c/d ,' });
  const vision = buildFallbackChain(env, true).filter((a) => a.provider === 'groq').map((a) => a.model);
  eq(vision, ['a/b', 'c/d'], 'groq vision override');
  const text = buildFallbackChain(env, false).filter((a) => a.provider === 'groq').map((a) => a.model);
  assert(text.length > 0 && !text.includes('a/b'), 'text list independent');
  eq(modelList(envOf({ X: ' , ' }), 'X', ['d']), ['d'], 'empty override → default');
});

Deno.test('chatBody keeps request shape and adds per-provider reasoning settings', () => {
  const msgs = [{ role: 'user', content: [{ type: 'text', text: 'hi' }, { type: 'image_url', image_url: { url: 'data:image/jpeg;base64,AAAA' } }] }];
  const chain = buildFallbackChain(envOf({ GEMINI_API_KEY: 'g', GROQ_API_KEY: 'q', OPENROUTER_API_KEY: 'o' }), false);
  const gem = chain.find((a) => a.provider === 'gemini')!;
  const b = chatBody(gem, msgs, 400, true);
  eq(b.messages, msgs, 'messages untouched (base64 images pass through)');
  eq(b.stream, true, 'stream flag');
  eq(b.temperature, 0.25, 'temperature');
  assert(b.reasoning_effort === 'minimal', 'gemini 3.x minimal thinking');
  assert((b.max_tokens as number) >= 400, 'max_tokens at least the cap');
  const or = chain.find((a) => a.provider === 'openrouter')!;
  const ob = chatBody(or, msgs, 400, false);
  eq(ob.max_tokens, 400, 'openrouter max_tokens unchanged');
  assert(!('stream' in ob) && !('reasoning_effort' in ob), 'openrouter body as before');
  const gpt = chain.find((a) => a.model.startsWith('openai/gpt-oss'))!;
  eq(chatBody(gpt, msgs, 400, false).include_reasoning, false, 'groq gpt-oss hides reasoning');
});

Deno.test('jsonMode adds response_format only for Groq/OpenRouter, never when streaming', () => {
  const msgs = [{ role: 'user', content: 'json please' }];
  const chain = buildFallbackChain(envOf({ GEMINI_API_KEY: 'g', GROQ_API_KEY: 'q', OPENROUTER_API_KEY: 'o' }), false);
  const json = { type: 'json_object' };
  for (const a of chain) {
    const b = chatBody(a, msgs, 400, false, true);
    if (a.provider === 'gemini') assert(!('response_format' in b), 'gemini left to the prompt');
    else eq(b.response_format, json, `${a.provider} json mode`);
    assert(!('response_format' in chatBody(a, msgs, 400, true, true)), 'never with stream');
    assert(!('response_format' in chatBody(a, msgs, 400, false)), 'off by default');
  }
});
