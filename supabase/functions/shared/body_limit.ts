// Bounded request-body reading for edge functions.
//
// req.json() buffers the whole body with no limit. readJsonLimited rejects an
// oversized Content-Length up front and, when the header is missing or wrong
// (chunked uploads), counts bytes while streaming and stops at the cap.

/** 10 MiB. The largest legitimate body is ai-meal-coach -> ai-chat-router
 *  with up to 9M chars of image data URLs (COACH_LIMITS) plus text. */
export const MAX_REQUEST_BODY_BYTES = 10 * 1024 * 1024;

export class BodyTooLargeError extends Error {
  constructor(readonly limit: number) {
    super('body_too_large');
  }
}

/** Reads the body as UTF-8 text, at most [maxBytes]. Throws BodyTooLargeError. */
export async function readTextLimited(req: Request, maxBytes = MAX_REQUEST_BODY_BYTES): Promise<string> {
  const declared = req.headers.get('content-length');
  if (declared !== null) {
    const n = Number(declared);
    if (Number.isFinite(n) && n > maxBytes) throw new BodyTooLargeError(maxBytes);
  }
  if (!req.body) return '';

  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > maxBytes) {
        try { await reader.cancel(); } catch { /* ignore */ }
        throw new BodyTooLargeError(maxBytes);
      }
      chunks.push(value);
    }
  } finally {
    try { reader.releaseLock(); } catch { /* already released */ }
  }

  const buf = new Uint8Array(total);
  let off = 0;
  for (const c of chunks) { buf.set(c, off); off += c.byteLength; }
  return new TextDecoder().decode(buf);
}

/** Parsed JSON body, or [fallback] when the body is empty or not JSON.
 *  Throws BodyTooLargeError over the cap (never parses an oversized body). */
export async function readJsonLimited<T = unknown>(
  req: Request, fallback: T, maxBytes = MAX_REQUEST_BODY_BYTES,
): Promise<any> {
  const text = await readTextLimited(req, maxBytes);
  try {
    return JSON.parse(text);
  } catch {
    return fallback;
  }
}
