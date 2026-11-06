// Teen mode on the server: AI stays off for anyone under 18.
//
// Google's Gemini API terms do not allow it for users under 18, and Kynetix
// keeps the other providers to the same rule. The check reads the locked
// birthday on a guardian_consents row first, then the profile's birthday and
// age, so a teen who edits their birthday in the app does not lift it.

import { aiBlockedForMinor } from './guardian.ts';
import { AiGuardError } from './ai_guard.ts';

export function teenModeError(): AiGuardError {
  return new AiGuardError(403, 'teen_mode', 'Kyno unlocks when you turn 18. Everything else is all yours.');
}

/** Throws [teenModeError] for a minor; a 503 when it cannot tell (fails closed). */
export async function assertAdultForAi(admin: any, userId: string, now: Date = new Date()): Promise<void> {
  const [consent, profile] = await Promise.all([
    admin.from('guardian_consents').select('child_dob').eq('user_id', userId).maybeSingle(),
    admin.from('profiles').select('age, dob:profile_json->>dateOfBirth').eq('id', userId).maybeSingle(),
  ]);
  if (consent.error || profile.error) {
    throw new AiGuardError(503, 'rate_limit_unavailable', 'Kyno is busy right now. Try again in a minute.', { retry_after: 30 });
  }
  if (aiBlockedForMinor(consent.data?.child_dob, profile.data?.dob, profile.data?.age, now)) {
    throw teenModeError();
  }
}
