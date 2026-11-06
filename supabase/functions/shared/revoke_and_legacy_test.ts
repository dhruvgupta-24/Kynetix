// deno test --allow-all supabase/functions/shared/revoke_and_legacy_test.ts
import {
  revokeSiwcLink,
  SIWC_REVOKE_URL,
  siwcRevocationTarget,
  siwcRevokeBody,
} from './siwc.ts';
import { LEGACY_DEVICE_LINK_GONE, legacyDeviceLinkAllowed } from './legacy_link.ts';

function assert(cond: unknown, msg: string) {
  if (!cond) throw new Error(msg);
}

const SIWC_LINK = { auth_method: 'siwc', refresh_token: 'rt-123', oauth_client_id: 'oaiapp_abc' };

Deno.test('revocation target: only siwc links with refresh token and client id', () => {
  const t = siwcRevocationTarget(SIWC_LINK);
  assert(t?.refreshToken === 'rt-123' && t?.clientId === 'oaiapp_abc', 'siwc');
  assert(siwcRevocationTarget({ ...SIWC_LINK, auth_method: 'codex_device' }) === null, 'device-code skipped');
  assert(siwcRevocationTarget({ ...SIWC_LINK, refresh_token: null }) === null, 'no refresh token');
  assert(siwcRevocationTarget({ ...SIWC_LINK, oauth_client_id: '' }) === null, 'no client id');
  assert(siwcRevocationTarget(null) === null && siwcRevocationTarget('x') === null, 'junk');
});

Deno.test('revoke body: token, refresh_token hint, client_id (form-encoded)', () => {
  const p = new URLSearchParams(siwcRevokeBody('a+b/c', 'oaiapp_1'));
  assert(p.get('token') === 'a+b/c', 'token round-trips');
  assert(p.get('token_type_hint') === 'refresh_token', 'hint');
  assert(p.get('client_id') === 'oaiapp_1', 'client id');
  assert([...p.keys()].length === 3, 'nothing else');
});

Deno.test('revokeSiwcLink: posts once to the revocation endpoint; never throws', async () => {
  const seen: Array<{ url: string; init: RequestInit }> = [];
  const ok = await revokeSiwcLink(SIWC_LINK, (url, init) => {
    seen.push({ url, init });
    return Promise.resolve(new Response('', { status: 200 }));
  });
  assert(ok === 'revoked', 'empty 200 = revoked');
  assert(seen.length === 1 && seen[0].url === SIWC_REVOKE_URL && seen[0].init.method === 'POST', 'one POST');
  assert(String((seen[0].init.headers as Record<string, string>)['Content-Type']).startsWith('application/x-www-form-urlencoded'), 'form');

  assert(await revokeSiwcLink(SIWC_LINK, () => Promise.resolve(new Response('{}', { status: 503 }))) === 'failed', '5xx');
  assert(await revokeSiwcLink(SIWC_LINK, () => Promise.reject(new TypeError('network'))) === 'failed', 'network');

  let called = false;
  const skipped = await revokeSiwcLink({ auth_method: 'codex_device', refresh_token: 'x' }, () => {
    called = true;
    return Promise.resolve(new Response(''));
  });
  assert(skipped === 'skipped' && !called, 'device-code links are not sent anywhere');
});

Deno.test('legacy device link: off unless ALLOW_LEGACY_DEVICE_LINK=true', () => {
  const env = (v: string | undefined) => (k: string) => (k === 'ALLOW_LEGACY_DEVICE_LINK' ? v : undefined);
  assert(!legacyDeviceLinkAllowed(env(undefined)), 'unset = off');
  assert(!legacyDeviceLinkAllowed(env('')), 'empty = off');
  assert(!legacyDeviceLinkAllowed(env('1')), '1 = off');
  assert(!legacyDeviceLinkAllowed(env('yes')), 'yes = off');
  assert(legacyDeviceLinkAllowed(env('true')) && legacyDeviceLinkAllowed(env(' TRUE ')), 'true = on');
  assert(LEGACY_DEVICE_LINK_GONE.error === 'device_link_retired', 'code');
  assert(!/[\u2013\u2014]/.test(LEGACY_DEVICE_LINK_GONE.message), 'no dashes in copy');
});
