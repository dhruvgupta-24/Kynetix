// deno test --allow-all supabase/functions/shared/body_limit_test.ts
import { BodyTooLargeError, readJsonLimited, readTextLimited } from './body_limit.ts';

function assert(cond: unknown, msg: string) {
  if (!cond) throw new Error(msg);
}

async function expectTooLarge(p: Promise<unknown>) {
  try {
    await p;
  } catch (e) {
    assert(e instanceof BodyTooLargeError, `expected BodyTooLargeError, got ${e}`);
    return;
  }
  throw new Error('expected BodyTooLargeError');
}

/** A request whose body is streamed in chunks with no Content-Length. */
function chunked(chunks: string[]): Request {
  const enc = new TextEncoder();
  const stream = new ReadableStream<Uint8Array>({
    start(c) {
      for (const s of chunks) c.enqueue(enc.encode(s));
      c.close();
    },
  });
  return new Request('http://x', { method: 'POST', body: stream });
}

Deno.test('parses a normal JSON body', async () => {
  const req = new Request('http://x', { method: 'POST', body: JSON.stringify({ a: 1 }) });
  const v = await readJsonLimited(req, null, 1024);
  assert(v.a === 1, 'parsed');
});

Deno.test('invalid or empty JSON yields the fallback', async () => {
  assert((await readJsonLimited(new Request('http://x', { method: 'POST', body: '{nope' }), 'fb', 1024)) === 'fb', 'invalid');
  assert((await readJsonLimited(new Request('http://x', { method: 'POST' }), 'fb', 1024)) === 'fb', 'empty');
});

Deno.test('oversized Content-Length is rejected before reading', async () => {
  // A body that never ends: if the helper tried to read it, the test would hang.
  const stream = new ReadableStream<Uint8Array>({ pull() { /* never enqueues */ } });
  const req = new Request('http://x', { method: 'POST', body: stream, headers: { 'content-length': '20000000' } });
  await expectTooLarge(readTextLimited(req, 10 * 1024 * 1024));
  assert(!req.bodyUsed, 'body never read');
});

Deno.test('missing Content-Length: stream is cut off at the byte cap', async () => {
  await expectTooLarge(readTextLimited(chunked(['x'.repeat(600), 'y'.repeat(600)]), 1000));
  const ok = await readTextLimited(chunked(['{"a":', '"', 'é'.repeat(10), '"}']), 1000);
  assert(JSON.parse(ok).a === 'é'.repeat(10), 'multi-chunk utf-8 reassembled');
});
