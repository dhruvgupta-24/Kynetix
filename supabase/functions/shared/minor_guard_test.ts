import { assert, assertEquals } from 'jsr:@std/assert@1';
import { keywordRisk, lastUserText, sseOf, TEEN_CRISIS_REPLY, TEEN_FLAGGED_NOTE, TEEN_SAFETY_RULES, withTeenSafety } from './minor_guard.ts';
import { buildTeenChain, chatBody } from './free_providers.ts';

Deno.test('teen rules fold into the first system message (the Codex path reads only that one)', () => {
  const out = withTeenSafety([{ role: 'system', content: 'You are Kyno.' }, { role: 'user', content: 'hi' }], false);
  assertEquals(out.length, 2);
  assert(out[0].content.startsWith('You are Kyno.'));
  assert(out[0].content.includes('TEEN MODE'));
  assert(!out[0].content.includes(TEEN_FLAGGED_NOTE));
  const bare = withTeenSafety([{ role: 'user', content: 'hi' }], true);
  assertEquals(bare[0].role, 'system');
  assert(bare[0].content.includes(TEEN_SAFETY_RULES) && bare[0].content.includes(TEEN_FLAGGED_NOTE));
  assert(TEEN_SAFETY_RULES.includes('14416'));
});

Deno.test('last user text reads strings and text parts', () => {
  assertEquals(lastUserText([{ role: 'user', content: 'a' }, { role: 'assistant', content: 'b' }]), 'a');
  assertEquals(lastUserText([{ role: 'user', content: [{ type: 'text', text: 'x' }, { type: 'image_url', image_url: { url: 'data:' } }] }]), 'x');
  assertEquals(lastUserText([]), '');
});

Deno.test('teen chain: Groq then OpenAI, never Gemini or OpenRouter; TEEN_AI=off empties it', () => {
  const env: Record<string, string> = { GEMINI_API_KEY: 'g', OPENROUTER_API_KEY: 'o', OPENAI_API_KEY: 'k', GROQ_API_KEY: 'q' };
  const chain = buildTeenChain((k) => env[k], false);
  assert(chain.length > 0);
  assert(chain.every((a) => a.provider === 'openai' || a.provider === 'groq'));
  assertEquals(chain[0].provider, 'groq');
  assertEquals(chain.filter((a) => a.provider === 'groq').length, 3);
  assertEquals(buildTeenChain((k) => ({ ...env, TEEN_AI: 'off' } as Record<string, string>)[k], false), []);
  assertEquals(buildTeenChain((k) => ({ GEMINI_API_KEY: 'g' } as Record<string, string>)[k], true), []);
});

Deno.test('OpenAI bodies use max_completion_tokens; reasoning models drop temperature', () => {
  const [gpt5] = buildTeenChain((k) => ({ OPENAI_API_KEY: 'k', OPENAI_TEEN_MODELS: 'gpt-5-mini' } as Record<string, string>)[k], false);
  const b = chatBody(gpt5, [], 500, false, true);
  assertEquals(b.max_completion_tokens, 1524);
  assert(!('max_tokens' in b) && !('temperature' in b));
  assertEquals(b.reasoning_effort, 'low');
  assertEquals(b.response_format, { type: 'json_object' });
  const [mini] = buildTeenChain((k) => ({ OPENAI_API_KEY: 'k', OPENAI_TEEN_MODELS: 'gpt-4.1-mini' } as Record<string, string>)[k], false);
  const m = chatBody(mini, [], 500, true);
  assertEquals(m.temperature, 0.25);
  assertEquals(m.max_completion_tokens, 500);
});

Deno.test('keyword risk catches self-harm and eating-disorder phrases, not gym talk', () => {
  for (const t of ['i keep thinking about hurting myself', 'I want to kill myself', 'thinking about suicide',
    'i throw up after eating', "I don't want to live anymore", 'i have been starving myself', 'self-harm']) {
    assert(keywordRisk(t), t);
  }
  for (const t of ['this workout is killing me', 'cut phase macros?', 'my legs hurt after squats', 'is 2 roti ok']) {
    assert(!keywordRisk(t), t);
  }
});

Deno.test('the crisis reply has the helpline and streams as one SSE message', () => {
  assert(TEEN_CRISIS_REPLY.includes('14416') && TEEN_CRISIS_REPLY.includes('112'));
  assert(!/[\u2013\u2014]/.test(TEEN_CRISIS_REPLY));
  const sse = sseOf('hi');
  assert(sse.startsWith('data: {') && sse.trimEnd().endsWith('data: [DONE]'));
  assertEquals(JSON.parse(sse.split('\n\n')[0].slice(6)).choices[0].delta.content, 'hi');
});
