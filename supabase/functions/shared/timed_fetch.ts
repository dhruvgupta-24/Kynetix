// Upstream fetch deadlines shared by AI functions.

declare const Deno: any;

// ── Upstream timeouts ────────────────────────────────────────────────────────

export const UPSTREAM_HEADERS_TIMEOUT_MS = 45_000;
export const UPSTREAM_TOTAL_TIMEOUT_MS = 120_000;

// OAuth / discovery calls (token exchange, device code, JWKS): small JSON
// bodies, so a much shorter bound keeps the app's request from hanging.
export const AUTH_HEADERS_TIMEOUT_MS = 15_000;
export const AUTH_TOTAL_TIMEOUT_MS = 20_000;

/** fetch with a deadline for response headers (45s) and an overall cap
 *  (120s) that also bounds reading a streamed body. */
export async function timedFetch(
  url: string,
  init: RequestInit,
  headersTimeoutMs = UPSTREAM_HEADERS_TIMEOUT_MS,
  totalTimeoutMs = UPSTREAM_TOTAL_TIMEOUT_MS,
): Promise<Response> {
  const ctrl = new AbortController();
  const total = setTimeout(() => ctrl.abort(new DOMException('upstream total timeout', 'TimeoutError')), totalTimeoutMs);
  try { Deno.unrefTimer?.(total); } catch { /* older runtimes */ }
  const first = setTimeout(() => ctrl.abort(new DOMException('upstream headers timeout', 'TimeoutError')), headersTimeoutMs);
  try {
    return await fetch(url, { ...init, signal: ctrl.signal });
  } catch (e) {
    clearTimeout(total);
    throw e;
  } finally {
    clearTimeout(first);
  }
}
