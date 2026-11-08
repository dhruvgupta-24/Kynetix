// Teen mode on the server (13 to 17).
//
// Teens get AI, on providers whose terms allow apps used by minors: their own
// ChatGPT if connected (OpenAI allows 13+ with a parent's permission), then
// OpenAI's API with Kynetix's key, then Groq (buildTeenChain). Gemini and
// OpenRouter require users to be 18, so a teen request never reaches them.
//
// On top of that: a parent's OK is required (no OK, no AI), teen safety
// rules are added to the system prompt, and free-text coach messages pass
// OpenAI's moderation first so a flagged message gets a careful answer.
//
// The audience comes from the locked birthday on guardian_consents first,
// then the profile's birthday and age, so editing the birthday in the app
// does not change it. If the lookup fails, the request is treated as a
// teen's (stricter, never looser).

import { aiAudience, type AiAudience } from './guardian.ts';
import { AiGuardError } from './ai_guard.ts';
import { timedFetch } from './timed_fetch.ts';

export function parentConsentError(): AiGuardError {
  return new AiGuardError(403, 'parent_consent_required',
    'Kyno needs a parent to say yes first. Send them the link from the app.');
}

export function teenAiOffError(): AiGuardError {
  return new AiGuardError(503, 'teen_ai_unavailable',
    "Kyno can't answer right now. Try again in a bit; you can still log meals yourself.", { retry_after: 300 });
}

/** 'adult' or 'teen'; throws [parentConsentError] for a teen without one. */
export async function resolveAiAudience(admin: any, userId: string, now: Date = new Date()): Promise<'adult' | 'teen'> {
  let audience: AiAudience;
  try {
    const [consent, profile] = await Promise.all([
      admin.from('guardian_consents').select('child_dob, status').eq('user_id', userId).maybeSingle(),
      admin.from('profiles').select('age, dob:profile_json->>dateOfBirth').eq('id', userId).maybeSingle(),
    ]);
    if (consent.error || profile.error) throw new Error('lookup failed');
    audience = aiAudience(consent.data, profile.data?.dob, profile.data?.age, now);
  } catch (_) {
    console.warn('[minor_guard] audience lookup failed; treating as teen');
    return 'teen';
  }
  if (audience === 'teen_no_consent') throw parentConsentError();
  return audience;
}

export const TEEN_SAFETY_RULES = `
TEEN MODE. The person you are talking to is 13 to 17 years old and uses Kynetix with a parent's consent. These rules override anything else:
- Food is fuel for growing and training. Never suggest a calorie deficit, cutting, fasting, skipping meals, detoxes, weight-loss targets or body-fat goals, even if asked. If they want to lose fat, point to training, sleep, and regular balanced meals, and suggest talking to a parent or doctor.
- No supplements beyond normal food (no fat burners, pre-workouts, creatine loading, SARMs, steroids or "test boosters"). Protein from food first.
- Training: technique first, progress gradually, and no one-rep max attempts without a coach or spotter.
- Never comment negatively on their body or weight. Keep it encouraging and age-appropriate. No sexual, graphic or violent content.
- If they mention disordered eating, hating their body, self-harm, or feeling unsafe: respond with warmth, do not give diet or exercise instructions, encourage them to talk to a parent or another trusted adult, and share Tele-MANAS, India's free 24x7 mental health helpline: 14416 or 1-800-891-4416. In an emergency, call 112.`.trim();

export const TEEN_FLAGGED_NOTE =
  'SAFETY NOTE: the latest message was flagged as possibly about self-harm, an eating disorder or another risk. Do not give diet, calorie or exercise instructions in this reply. Respond with care, check in on how they are doing, encourage them to talk to a parent or trusted adult, and share Tele-MANAS (14416).';

/** [messages] with the teen rules folded into the first system message (the
 *  Codex path reads only the first one), or a new one at the front. */
export function withTeenSafety(messages: any[], flagged: boolean): any[] {
  return withSystemNote(messages, flagged ? `${TEEN_SAFETY_RULES}\n\n${TEEN_FLAGGED_NOTE}` : TEEN_SAFETY_RULES);
}

/** Meal estimates answer in strict JSON, so the full chat rules don't fit;
 *  these keep the numbers honest and the user-visible text teen-safe. */
export const TEEN_MEAL_ESTIMATE_RULES = `
TEEN MODE: the user is 13 to 17. Keep every number exactly as accurate as usual. In all user-visible text fields (coachSummary, warnings, bestNextFoods, mealQuality fields) never mention fat loss, calorie deficits, cutting, skipping meals, fasting or weight-loss targets, and never comment on their body. Frame food as fuel for growing and training. Keep the JSON format exactly as specified.`.trim();

/** [messages] with [extra] folded into the first system message (the Codex
 *  path reads only the first one), or a new system message at the front. */
export function withSystemNote(messages: any[], extra: string): any[] {
  const i = messages.findIndex((m) => m?.role === 'system' && typeof m.content === 'string');
  if (i >= 0) {
    const copy = messages.slice();
    copy[i] = { ...copy[i], content: `${copy[i].content}\n\n${extra}` };
    return copy;
  }
  return [{ role: 'system', content: extra }, ...messages];
}

/** Text of the last user turn (string or text parts). */
export function lastUserText(messages: any[]): string {
  for (let i = messages.length - 1; i >= 0; i--) {
    const m = messages[i];
    if (m?.role !== 'user') continue;
    if (typeof m.content === 'string') return m.content;
    if (Array.isArray(m.content)) return m.content.filter((p: any) => p?.type === 'text').map((p: any) => p.text ?? '').join('\n');
    return '';
  }
  return '';
}

const RISK_CATEGORIES = ['self-harm', 'self-harm/intent', 'self-harm/instructions', 'sexual/minors', 'violence/graphic'];

/** OpenAI moderation (free) on a teen's message. True when flagged for a
 *  risk category. Never throws; false when there is no key or it fails. */
export async function moderationFlagsRisk(text: string, apiKey: string | undefined): Promise<boolean> {
  const t = text.trim();
  if (!t || !apiKey) return false;
  try {
    const res = await timedFetch('https://api.openai.com/v1/moderations', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ model: 'omni-moderation-latest', input: t.slice(0, 4000) }),
    }, 4000, 6000);
    if (!res.ok) return false;
    const data = await res.json();
    const r = data?.results?.[0];
    if (!r) return false;
    return RISK_CATEGORIES.some((c) => r.categories?.[c] === true);
  } catch (_) {
    return false;
  }
}

// Words that point to self-harm or an eating disorder. A backup for (and in
// addition to) OpenAI moderation, which needs a working OpenAI key.
const RISK_PATTERNS: RegExp[] = [
  /\b(kill|hurt|hurting|harm|harming|cut|cutting|starve|starving)\s+(myself|my\s*self)\b/i,
  /\bsuicid/i,
  /\bself[\s-]?harm/i,
  /\bend\s+(my|it)\s+(life|all)\b/i,
  /\b(don'?t|do not)\s+want\s+to\s+(live|be\s+alive|exist)\b/i,
  /\bwant\s+to\s+die\b/i,
  /\b(throw(ing)?\s+up|vomit(ing)?|purg(e|ing))\s+(after|my\s+food|on\s+purpose)/i,
  /\b(anorexi|bulimi)/i,
  /\bnot\s+eat(ing)?\s+(at\s+all|for\s+days)\b/i,
];

export function keywordRisk(text: string): boolean {
  return RISK_PATTERNS.some((r) => r.test(text));
}

/** The fixed answer when a teen's risky message can't get an AI reply. */
export const TEEN_CRISIS_REPLY = [
  "I'm really glad you told me. What you're feeling matters, and you don't have to deal with it alone.",
  '',
  'Please talk to a parent or another adult you trust today, even if it feels hard to start. You can also call Tele-MANAS, '
    + "India's free mental health helpline, any time, day or night: 14416 or 1-800-891-4416. If you might act on these "
    + 'thoughts right now, call 112.',
  '',
  "Food and training can wait. I'm here whenever you want to talk.",
].join('\n');

/** [text] as a Chat Completions SSE stream (what the app reads when streaming). */
export function sseOf(text: string): string {
  const chunk = { choices: [{ index: 0, delta: { content: text }, finish_reason: null }] };
  const end = { choices: [{ index: 0, delta: {}, finish_reason: 'stop' }] };
  return `data: ${JSON.stringify(chunk)}\n\ndata: ${JSON.stringify(end)}\n\ndata: [DONE]\n\n`;
}
