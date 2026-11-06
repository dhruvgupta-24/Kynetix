// Pure helpers for teen mode (13 to 17) and the parent consent link.
// No I/O here, so every rule is unit tested (guardian_test.ts).

export const MIN_AGE = 13;
export const ADULT_AGE = 18;
export const LINK_DAYS = 7;
export const RELATIONS = ['mother', 'father', 'guardian'] as const;
export type Relation = typeof RELATIONS[number];

/** A plain calendar date from 'YYYY-MM-DD', or null when it isn't a real date. */
export function parseDate(v: unknown): { y: number; m: number; d: number } | null {
  if (typeof v !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(v)) return null;
  const [y, m, d] = v.split('-').map(Number);
  const t = new Date(Date.UTC(y, m - 1, d));
  if (t.getUTCFullYear() !== y || t.getUTCMonth() !== m - 1 || t.getUTCDate() !== d) return null;
  return { y, m, d };
}

/** Whole years between a birthday and [now] (IST calendar day). */
export function ageOn(dob: { y: number; m: number; d: number }, now: Date = new Date()): number {
  // India time, so the 18th birthday turns over at local midnight.
  const ist = new Date(now.getTime() + 5.5 * 3600 * 1000);
  const y = ist.getUTCFullYear(), m = ist.getUTCMonth() + 1, d = ist.getUTCDate();
  let age = y - dob.y;
  if (m < dob.m || (m === dob.m && d < dob.d)) age--;
  return age;
}

/** True while a birthday makes the account a minor. Unknown birthdays are not. */
export function isMinorDob(v: unknown, now: Date = new Date()): boolean {
  const dob = parseDate(v);
  return dob !== null && ageOn(dob, now) < ADULT_AGE;
}

/** Whether AI must stay off for this account: any server-side sign that it
 *  belongs to someone under 18 (the locked consent row first, then the
 *  profile's birthday and age). */
export function aiBlockedForMinor(
  consentChildDob: unknown,
  profileDob: unknown,
  profileAge: unknown,
  now: Date = new Date(),
): boolean {
  if (isMinorDob(consentChildDob, now)) return true;
  if (isMinorDob(profileDob, now)) return true;
  return typeof profileAge === 'number' && profileAge > 0 && profileAge < ADULT_AGE && parseDate(profileDob) === null;
}

export class GuardianError extends Error {
  constructor(public status: number, public code: string, message: string) {
    super(message);
  }
}

/** The teen's request: a birthday that is 13 to 17 today, and a first name. */
export function validateRequest(body: any, now: Date = new Date()): { dob: string; firstName: string } {
  const dob = parseDate(body?.dob);
  if (!dob) throw new GuardianError(400, 'bad_dob', 'That birthday does not look right.');
  const age = ageOn(dob, now);
  if (age < MIN_AGE) throw new GuardianError(403, 'too_young', 'Kynetix is for 13 and up.');
  if (age >= ADULT_AGE) throw new GuardianError(400, 'not_a_minor', 'No parent check needed at 18 and up.');
  const firstName = cleanName(body?.first_name, 40);
  if (!firstName) throw new GuardianError(400, 'bad_name', 'Add your first name so your parent knows it is you.');
  return { dob: body.dob, firstName };
}

/** The parent's answer. Approving needs their name, relation, a birthday that
 *  makes them an adult and the consent box; declining needs nothing else. */
export function validateDecision(body: any, childDob: string, now: Date = new Date()):
  { decision: 'approve' | 'decline'; parentName?: string; parentBirthYear?: number; relation?: Relation } {
  const decision = body?.decision;
  if (decision === 'decline') return { decision };
  if (decision !== 'approve') throw new GuardianError(400, 'bad_decision', 'Pick yes or no.');
  if (body?.agree !== true) throw new GuardianError(400, 'needs_agreement', 'Tick the box to give consent.');
  const parentName = cleanName(body?.parent_name, 80);
  if (!parentName || parentName.length < 2) throw new GuardianError(400, 'bad_parent_name', 'Add your full name.');
  const relation = body?.relation;
  if (!RELATIONS.includes(relation)) throw new GuardianError(400, 'bad_relation', 'Pick how you are related.');
  const pdob = parseDate(body?.parent_dob);
  if (!pdob) throw new GuardianError(400, 'bad_parent_dob', 'That birthday does not look right.');
  const parentAge = ageOn(pdob, now);
  if (parentAge < ADULT_AGE || parentAge > 110) {
    throw new GuardianError(403, 'parent_not_adult', 'Consent has to come from a parent or guardian who is 18 or older.');
  }
  const child = parseDate(childDob)!;
  if ((relation === 'mother' || relation === 'father') && parentAge - ageOn(child, now) < 12) {
    throw new GuardianError(400, 'parent_age_mismatch', 'Those ages do not add up for a parent. Check the year, or pick guardian.');
  }
  return { decision, parentName, parentBirthYear: pdob.y, relation };
}

/** Trimmed single-line text, no control characters, at most [max] chars. */
export function cleanName(v: unknown, max: number): string {
  if (typeof v !== 'string') return '';
  // deno-lint-ignore no-control-regex
  return v.replace(/\s+/g, ' ').replace(/[\u0000-\u001f\u007f<>]/g, '').trim().slice(0, max);
}

/** A 256-bit random link token, base64url. */
export function newToken(): string {
  const b = new Uint8Array(32);
  crypto.getRandomValues(b);
  return btoa(String.fromCharCode(...b)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export function isTokenShape(v: unknown): v is string {
  return typeof v === 'string' && /^[A-Za-z0-9_-]{43}$/.test(v);
}

export async function sha256Hex(s: string): Promise<string> {
  const d = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return Array.from(new Uint8Array(d)).map((x) => x.toString(16).padStart(2, '0')).join('');
}

/** What the teen sees: pending turns into expired once the link times out. */
export function effectiveStatus(row: { status: string; expires_at: string } | null, now: Date = new Date()): string {
  if (!row) return 'none';
  if (row.status === 'pending' && new Date(row.expires_at).getTime() <= now.getTime()) return 'expired';
  return row.status;
}

export const PARENT_PAGE = 'https://dhruvgupta-24.github.io/Kynetix/parent/';

/** The token rides in the fragment, so it never reaches a server log. */
export function parentLink(token: string): string {
  return `${PARENT_PAGE}#t=${token}`;
}
