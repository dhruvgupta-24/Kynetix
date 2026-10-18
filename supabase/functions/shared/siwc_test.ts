// deno test supabase/functions/shared/siwc_test.ts
import {
  buildSiwcResponsesBody,
  classifySiwcError,
  drainSiwcStream,
  hasPlanScope,
  SiwcApiError,
} from "./siwc.ts";

function assert(cond: unknown, msg: string) {
  if (!cond) throw new Error(msg);
}

function sse(events: unknown[]): Response {
  const body = events.map((e) => `data: ${JSON.stringify(e)}\n\n`).join('');
  return new Response(body, { headers: { 'Content-Type': 'text/event-stream' } });
}

Deno.test('body: instructions, no system items, stream + store:false, no forbidden fields', () => {
  const body = buildSiwcResponsesBody('gpt-x', [
    { role: 'system', content: 'You are Kyno.' },
    { role: 'user', content: 'hi' },
    { role: 'assistant', content: 'hey' },
    { role: 'user', content: [{ type: 'text', text: 'see' }, { type: 'image_url', image_url: { url: 'data:image/png;base64,AA' } }] },
  ]) as any;
  assert(body.instructions === 'You are Kyno.', 'instructions');
  assert(body.stream === true && body.store === false, 'stream/store');
  assert(body.input.every((m: any) => m.role !== 'system'), 'no system items');
  assert(body.input[1].content[0].type === 'output_text', 'assistant output_text');
  assert(body.input[2].content[1].image_url === 'data:image/png;base64,AA', 'image_url string');
  for (const f of ['temperature', 'max_output_tokens', 'top_p', 'metadata', 'user', 'previous_response_id']) {
    assert(!(f in body), `forbidden field ${f}`);
  }
});

Deno.test('stream: success only after response.completed', async () => {
  const text = await drainSiwcStream(sse([
    { type: 'response.output_text.delta', delta: 'O' },
    { type: 'response.output_text.delta', delta: 'K' },
    { type: 'response.completed' },
  ]));
  assert(text === 'OK', 'text');

  let threw = false;
  try {
    await drainSiwcStream(sse([{ type: 'response.output_text.delta', delta: 'O' }]));
  } catch { threw = true; }
  assert(threw, 'no completed -> failure');
});

Deno.test('stream: mid-stream usage limit is classified', async () => {
  try {
    await drainSiwcStream(sse([
      { type: 'response.failed', response: { error: { code: 'subscription_sharing_usage_limit_exceeded' } } },
    ]));
    throw new Error('should throw');
  } catch (e) {
    assert(e instanceof SiwcApiError && e.kind === 'usage_limit', 'usage_limit');
  }
});

Deno.test('classification + scope', () => {
  assert(classifySiwcError(403, 'subscription_sharing_user_not_eligible') === 'not_eligible', 'not eligible');
  assert(classifySiwcError(503, 'subscription_sharing_usage_unavailable') === 'temporarily_unavailable', 'unavailable');
  assert(classifySiwcError(429, null) === 'usage_limit', '429');
  assert(hasPlanScope('openid chatgpt.tokens.use.direct email'), 'has scope');
  assert(!hasPlanScope('openid email'), 'no scope');
});
