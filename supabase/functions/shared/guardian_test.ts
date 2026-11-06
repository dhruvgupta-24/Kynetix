import { assert, assertEquals, assertThrows } from 'jsr:@std/assert@1';
import {
  ageOn,
  aiBlockedForMinor,
  cleanName,
  effectiveStatus,
  GuardianError,
  isTokenShape,
  newToken,
  parentLink,
  parseDate,
  sha256Hex,
  validateDecision,
  validateRequest,
} from './guardian.ts';

// 7 Nov 2026, 10:00 IST
const NOW = new Date('2026-11-07T04:30:00Z');

Deno.test('dates: rejects impossible days and turns ages over at IST midnight', () => {
  assertEquals(parseDate('2010-02-30'), null);
  assertEquals(parseDate('2010-2-3'), null);
  assertEquals(parseDate(20100203), null);
  const dob = parseDate('2008-11-07')!;
  assertEquals(ageOn(dob, NOW), 18);
  // 6 Nov 2026 23:00 IST is 17:30 UTC: still 17.
  assertEquals(ageOn(dob, new Date('2026-11-06T17:30:00Z')), 17);
  // 7 Nov 2026 00:30 IST is 6 Nov 19:00 UTC: already 18.
  assertEquals(ageOn(dob, new Date('2026-11-06T19:00:00Z')), 18);
});

Deno.test('AI block: any sign of a minor blocks, adults and unknowns pass', () => {
  assert(aiBlockedForMinor('2010-05-01', null, null, NOW));
  // The locked consent birthday wins over an edited adult profile birthday.
  assert(aiBlockedForMinor('2010-05-01', '1990-01-01', 36, NOW));
  assert(aiBlockedForMinor(null, '2010-05-01', 16, NOW));
  assert(aiBlockedForMinor(null, null, 16, NOW));
  assert(!aiBlockedForMinor(null, '1999-01-01', 27, NOW));
  assert(!aiBlockedForMinor(null, null, 27, NOW));
  assert(!aiBlockedForMinor(null, null, null, NOW));
  // A teen who turned 18 is free.
  assert(!aiBlockedForMinor('2008-11-07', '2008-11-07', 17, NOW));
});

Deno.test('request: 13 to 17 only, with a first name', () => {
  assertEquals(validateRequest({ dob: '2011-01-01', first_name: '  Aarav  ' }, NOW), { dob: '2011-01-01', firstName: 'Aarav' });
  const code = (b: unknown) => {
    try { validateRequest(b, NOW); return 'ok'; } catch (e) { return (e as GuardianError).code; }
  };
  assertEquals(code({ dob: '2014-01-01', first_name: 'A' }), 'too_young');
  assertEquals(code({ dob: '2013-11-07', first_name: 'A' }), 'ok');
  assertEquals(code({ dob: '2008-11-07', first_name: 'A' }), 'not_a_minor');
  assertEquals(code({ dob: 'nope', first_name: 'A' }), 'bad_dob');
  assertEquals(code({ dob: '2011-01-01', first_name: '   ' }), 'bad_name');
});

Deno.test('decision: approving needs an adult parent, a relation and the box', () => {
  const ok = { decision: 'approve', agree: true, parent_name: 'Priya Gupta', relation: 'mother', parent_dob: '1980-04-02' };
  assertEquals(validateDecision(ok, '2011-01-01', NOW), {
    decision: 'approve', parentName: 'Priya Gupta', parentBirthYear: 1980, relation: 'mother',
  });
  assertEquals(validateDecision({ decision: 'decline' }, '2011-01-01', NOW), { decision: 'decline' });
  const code = (b: unknown) => {
    try { validateDecision(b, '2011-01-01', NOW); return 'ok'; } catch (e) { return (e as GuardianError).code; }
  };
  assertEquals(code({ ...ok, agree: false }), 'needs_agreement');
  assertEquals(code({ ...ok, parent_dob: '2010-01-01' }), 'parent_not_adult');
  assertEquals(code({ ...ok, parent_dob: '2005-01-01' }), 'parent_age_mismatch');
  assertEquals(code({ ...ok, parent_dob: '2005-01-01', relation: 'guardian' }), 'ok');
  assertEquals(code({ ...ok, relation: 'uncle' }), 'bad_relation');
  assertEquals(code({ ...ok, parent_name: 'x' }), 'bad_parent_name');
  assertEquals(code({ decision: 'maybe' }), 'bad_decision');
});

Deno.test('names are single-line plain text', () => {
  assertEquals(cleanName('<b>Ria</b>\n\tS', 40), 'bRia/b S');
  assertEquals(cleanName(42, 40), '');
  assertEquals(cleanName('a'.repeat(100), 40).length, 40);
});

Deno.test('tokens: 256-bit, url safe, only the hash is stored, link uses the fragment', async () => {
  const t = newToken();
  assert(isTokenShape(t));
  assert(t !== newToken());
  assert(!isTokenShape('short'));
  assert(!isTokenShape(t + '!'));
  assertEquals((await sha256Hex('abc')).length, 64);
  assertEquals(parentLink(t), `https://dhruvgupta-24.github.io/Kynetix/parent/#t=${t}`);
});

Deno.test('pending links expire', () => {
  assertEquals(effectiveStatus(null, NOW), 'none');
  assertEquals(effectiveStatus({ status: 'pending', expires_at: '2026-11-08T00:00:00Z' }, NOW), 'pending');
  assertEquals(effectiveStatus({ status: 'pending', expires_at: '2026-11-01T00:00:00Z' }, NOW), 'expired');
  assertEquals(effectiveStatus({ status: 'approved', expires_at: '2026-11-01T00:00:00Z' }, NOW), 'approved');
});

Deno.test('AI audience: adults, approved teens, teens without a yes', async () => {
  const { aiAudience } = await import('./guardian.ts');
  assertEquals(aiAudience(null, '1999-01-01', 27, NOW), 'adult');
  assertEquals(aiAudience(null, null, null, NOW), 'adult');
  assertEquals(aiAudience({ child_dob: '2011-05-05', status: 'approved' }, '2011-05-05', 15, NOW), 'teen');
  assertEquals(aiAudience({ child_dob: '2011-05-05', status: 'pending' }, '2011-05-05', 15, NOW), 'teen_no_consent');
  assertEquals(aiAudience({ child_dob: '2011-05-05', status: 'revoked' }, '1990-01-01', 36, NOW), 'teen_no_consent');
  // A minor with no consent row at all (should never get this far).
  assertEquals(aiAudience(null, '2011-05-05', 15, NOW), 'teen_no_consent');
  // Turned 18: an adult, whatever the old row says.
  assertEquals(aiAudience({ child_dob: '2008-11-07', status: 'revoked' }, '2008-11-07', 18, NOW), 'adult');
});
