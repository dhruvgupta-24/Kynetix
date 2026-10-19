// ai_guard — request policy for ai-chat-router.
//
// - The router only serves known purposes. System prompts are server-owned;
//   any client-sent system/developer message is discarded.
// - The one exception is the trusted server-to-server path from ai-meal-coach
//   (purpose 'coach'), authenticated with a shared secret header.
// - Hard caps on message count, text size, image count and image size.
// - Per-user rate limits (per minute + per day) backed by public.ai_usage.
//
// Pure helpers live here so they can be unit-tested (ai_guard_test.ts).

import { mealEstimateSystemPrompt, type PortionAnchor } from './meal_estimate_prompt.ts';
import {
  LABEL_READ_SYSTEM_PROMPT,
  LabelUnreadableError,
  normalizeLabelReadOutput,
} from './label_read_prompt.ts';

declare const Deno: any;

// ── Errors ───────────────────────────────────────────────────────────────────

export class AiGuardError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    readonly userMessage: string,
    readonly extra: Record<string, unknown> = {},
  ) {
    super(code);
  }

  toBody(): Record<string, unknown> {
    return { success: false, error: this.code, message: this.userMessage, ...this.extra };
  }
}

// ── Purposes ─────────────────────────────────────────────────────────────────

export type AiPurpose = 'meal_estimate' | 'weekly_summary' | 'label_read' | 'coach';
export type ClientPurpose = 'meal_estimate' | 'weekly_summary' | 'label_read';

export const CLIENT_PURPOSES: readonly AiPurpose[] = ['meal_estimate', 'weekly_summary', 'label_read'];

/** Purposes whose answer must be one JSON object, validated server-side
 *  before it is returned. These are never streamed (a stream:true request
 *  gets the normal JSON response; current app builds never stream these). */
export const JSON_ONLY_PURPOSES: readonly AiPurpose[] = ['label_read', 'meal_estimate'];

/** Client purposes that take exactly one user message and nothing else: no
 *  client assistant turns (which would let the app endpoint be used as a
 *  general chatbot with a forged history). Current and legacy app builds
 *  send one user message (legacy builds also send a system message, which
 *  is dropped). */
export const SINGLE_TURN_PURPOSES: readonly AiPurpose[] = ['meal_estimate', 'weekly_summary'];
export const INTERNAL_PURPOSES: readonly AiPurpose[] = ['coach'];

export const WEEKLY_SUMMARY_SYSTEM_PROMPT =
  "You are Kyno, the coach in Kynetix, an Indian training and nutrition app. Write a 2 to 3 sentence summary of the user's week using only the report data. Mention logged days, gym days and average protein against target; compare with last week only if a change is given. Never invent numbers or targets. Calm, warm, plain words, no hype. Plain text: no markdown, no emoji, no em or en dashes. End with one specific action for next week.";

// Fingerprints of the system prompts built by released app versions, used to
// map a legacy request (no `purpose`) onto the server-owned prompt. The
// client text itself is never forwarded.
const LEGACY_MEAL_PREFIX =
  'You are the backend intelligence layer for an Indian-first fat-loss nutrition coach';
const LEGACY_WEEKLY_PREFIX =
  "You are Kyno, an elite Indian-first fat-loss nutrition coach. Analyze the user's weekly report";

export interface Limits {
  maxMessages: number;
  maxTextChars: number;
  maxImages: number;
  maxImageChars: number;   // per image, length of the data URL
  maxTotalImageChars: number;
  maxOutputTokens: number;
}

export const CLIENT_LIMITS: Record<ClientPurpose, Limits> = {
  meal_estimate:  { maxMessages: 1, maxTextChars: 16_000, maxImages: 0, maxImageChars: 0, maxTotalImageChars: 0, maxOutputTokens: 2500 },
  weekly_summary: { maxMessages: 1, maxTextChars: 6_000,  maxImages: 0, maxImageChars: 0, maxTotalImageChars: 0, maxOutputTokens: 400 },
  // One photo of a nutrition table (~2 MB binary max) and a short fixed text.
  label_read:     { maxMessages: 1, maxTextChars: 500,    maxImages: 1, maxImageChars: 2_800_000, maxTotalImageChars: 2_800_000, maxOutputTokens: 500 },
};

// ai-meal-coach builds the system prompt (targets, today's meals, memory,
// trends) plus <=10 history turns and the user turn.
export const COACH_LIMITS: Limits = {
  maxMessages: 24,
  maxTextChars: 100_000,
  maxImages: 6,
  maxImageChars: 2_800_000,       // ~2 MB binary; app sends <=1024px q75 JPEGs
  maxTotalImageChars: 9_000_000,
  maxOutputTokens: 1500,
};

export interface ChatMessage {
  role: 'system' | 'user' | 'assistant';
  content: string | Array<Record<string, unknown>>;
}

export interface GuardedRequest {
  purpose: AiPurpose;
  messages: ChatMessage[];   // final messages to forward (server system prompt first)
  textChars: number;         // client-supplied text chars (for usage accounting)
  imageCount: number;
  limits: Limits;
  legacy: boolean;
}

const PORTION_ANCHORS: readonly PortionAnchor[] = ['carbAnchored', 'curryAnchored', 'balanced'];

export function parsePortionAnchor(v: unknown): PortionAnchor | null {
  return typeof v === 'string' && (PORTION_ANCHORS as readonly string[]).includes(v)
    ? v as PortionAnchor
    : null;
}

function legacyAnchorFromSystemText(text: string): PortionAnchor | null {
  if (text.includes('This user is CARB-ANCHORED')) return 'carbAnchored';
  if (text.includes('This user is CURRY-ANCHORED')) return 'curryAnchored';
  if (text.includes('USER EATING STYLE: BALANCED')) return 'balanced';
  return null;
}

function firstSystemText(raw: unknown[]): string {
  for (const m of raw) {
    if (m && typeof m === 'object' && (m as any).role === 'system' && typeof (m as any).content === 'string') {
      return (m as any).content as string;
    }
  }
  return '';
}

const IMAGE_DATA_URL = /^data:image\/(jpeg|jpg|png|webp|gif|heic|heif);base64,[A-Za-z0-9+/=\s]+$/;

/** Validates and normalises the caller's messages. Drops system/developer
 *  messages unless [allowSystem]. Throws AiGuardError on any cap breach. */
export function sanitizeMessages(raw: unknown, limits: Limits, allowSystem: boolean, userOnly = false): {
  messages: ChatMessage[]; textChars: number; imageCount: number;
} {
  if (!Array.isArray(raw) || raw.length === 0) {
    throw new AiGuardError(400, 'invalid_request', 'messages array is required');
  }
  if (raw.length > limits.maxMessages + (allowSystem ? 0 : 2)) {
    throw new AiGuardError(413, 'too_many_messages', 'This conversation is too long. Start a new one and try again.', { limit: limits.maxMessages });
  }

  const out: ChatMessage[] = [];
  let textChars = 0;
  let imageCount = 0;
  let imageChars = 0;

  for (const m of raw) {
    if (!m || typeof m !== 'object') throw new AiGuardError(400, 'invalid_request', 'Malformed message.');
    const role = (m as any).role;
    if (role === 'system' || role === 'developer') {
      if (!allowSystem) continue; // server owns instructions
      if (role === 'developer') continue;
    } else if (role !== 'user' && role !== 'assistant') {
      throw new AiGuardError(400, 'invalid_request', 'Unsupported message role.');
    } else if (role === 'assistant' && userOnly) {
      throw new AiGuardError(400, 'invalid_request', 'Only a user message is accepted here.');
    }
    const content = (m as any).content;
    if (typeof content === 'string') {
      textChars += content.length;
      out.push({ role, content });
      continue;
    }
    if (!Array.isArray(content) || content.length === 0) {
      throw new AiGuardError(400, 'invalid_request', 'Malformed message content.');
    }
    const blocks: Array<Record<string, unknown>> = [];
    for (const b of content) {
      const type = (b as any)?.type;
      if (type === 'text') {
        const text = (b as any).text;
        if (typeof text !== 'string') throw new AiGuardError(400, 'invalid_request', 'Malformed text block.');
        textChars += text.length;
        blocks.push({ type: 'text', text });
      } else if (type === 'image_url') {
        if (role !== 'user') throw new AiGuardError(400, 'invalid_request', 'Images are only allowed in user messages.');
        const iu = (b as any).image_url;
        const url = typeof iu === 'string' ? iu : iu?.url;
        if (typeof url !== 'string' || !IMAGE_DATA_URL.test(url.slice(0, 64)) ) {
          throw new AiGuardError(400, 'invalid_image', 'Images must be sent as base64 data URLs.');
        }
        imageCount++;
        if (imageCount > limits.maxImages) {
          throw new AiGuardError(413, 'too_many_images',
            limits.maxImages === 0 ? 'Images are not supported here.' : `You can send up to ${limits.maxImages} photos at once.`,
            { limit: limits.maxImages });
        }
        if (url.length > limits.maxImageChars) {
          throw new AiGuardError(413, 'image_too_large', 'That photo is too large. Try a smaller one.', { limit_bytes: Math.floor(limits.maxImageChars * 3 / 4) });
        }
        imageChars += url.length;
        if (imageChars > limits.maxTotalImageChars) {
          throw new AiGuardError(413, 'images_too_large', 'Those photos are too large together. Send fewer at once.');
        }
        blocks.push({ type: 'image_url', image_url: { url } });
      } else {
        throw new AiGuardError(400, 'invalid_request', 'Unsupported content block.');
      }
    }
    out.push({ role, content: blocks });
  }

  if (out.filter((m) => m.role !== 'system').length === 0) {
    throw new AiGuardError(400, 'invalid_request', 'A user message is required.');
  }
  if (out.length > limits.maxMessages) {
    throw new AiGuardError(413, 'too_many_messages', 'This conversation is too long. Start a new one and try again.', { limit: limits.maxMessages });
  }
  if (textChars > limits.maxTextChars) {
    throw new AiGuardError(413, 'too_many_chars', 'That message is too long. Shorten it and try again.', { limit: limits.maxTextChars });
  }
  return { messages: out, textChars, imageCount };
}

/** Resolves the request purpose and builds the final message list. */
export function guardRequest(body: any, trustedInternal: boolean): GuardedRequest {
  if (!body || typeof body !== 'object') {
    throw new AiGuardError(400, 'invalid_request', 'Request body must be JSON.');
  }
  const raw: unknown[] = Array.isArray(body.messages) ? body.messages : [];
  let purpose: unknown = body.purpose;
  let legacy = false;
  let anchor: PortionAnchor | null = parsePortionAnchor(body.portion_anchor);

  if (purpose === undefined || purpose === null || purpose === '') {
    if (trustedInternal) {
      purpose = 'coach';
    } else {
      // Released app builds send their own system prompt and no purpose.
      const sys = firstSystemText(raw);
      if (sys.startsWith(LEGACY_MEAL_PREFIX)) {
        purpose = 'meal_estimate';
        anchor = anchor ?? legacyAnchorFromSystemText(sys);
        legacy = true;
      } else if (sys.startsWith(LEGACY_WEEKLY_PREFIX)) {
        purpose = 'weekly_summary';
        legacy = true;
      }
    }
  }

  if (typeof purpose !== 'string') {
    throw new AiGuardError(400, 'unknown_purpose', 'This request type is not supported.');
  }

  if (purpose === 'coach') {
    if (!trustedInternal) {
      throw new AiGuardError(403, 'forbidden_purpose', 'This request type is not supported.');
    }
    const s = sanitizeMessages(raw, COACH_LIMITS, true);
    return { purpose, messages: s.messages, textChars: s.textChars, imageCount: s.imageCount, limits: COACH_LIMITS, legacy };
  }

  if (purpose === 'meal_estimate' || purpose === 'weekly_summary' || purpose === 'label_read') {
    const limits = CLIENT_LIMITS[purpose];
    const singleTurn = SINGLE_TURN_PURPOSES.includes(purpose);
    const s = sanitizeMessages(raw, limits, false, singleTurn);
    if (singleTurn && (s.messages.length !== 1 || s.messages[0].role !== 'user')) {
      throw new AiGuardError(400, 'invalid_request', 'Send exactly one user message.');
    }
    if (purpose === 'label_read' && s.imageCount !== 1) {
      throw new AiGuardError(400, 'invalid_request', 'Send one photo of the nutrition label.');
    }
    const system = purpose === 'meal_estimate'
      ? mealEstimateSystemPrompt(anchor)
      : purpose === 'label_read'
        ? LABEL_READ_SYSTEM_PROMPT
        : WEEKLY_SUMMARY_SYSTEM_PROMPT;
    return {
      purpose,
      messages: [{ role: 'system', content: system }, ...s.messages],
      textChars: s.textChars,
      imageCount: s.imageCount,
      limits,
      legacy,
    };
  }

  throw new AiGuardError(400, 'unknown_purpose', 'This request type is not supported.');
}

// ── Response contract ────────────────────────────────────────────────────────

/** Whether this purpose may stream. JSON-only purposes are validated as a
 *  whole before anything is returned, so they never stream. */
export function allowsStreaming(purpose: AiPurpose): boolean {
  return !JSON_ONLY_PURPOSES.includes(purpose);
}

/** Finds the JSON object in a meal-estimate answer exactly the way the app's
 *  parser does (AiNutritionService._parse): strip markdown fences, then take
 *  the first '{' through the last '}'. */
export function extractMealEstimateJson(raw: string): string {
  let text = raw.trim()
    .replace(/^```json\s*/gm, '')
    .replace(/^```\s*/gm, '')
    .replace(/\s*```$/gm, '')
    .trim();
  const s = text.indexOf('{');
  const e = text.lastIndexOf('}');
  if (s >= 0 && e > s) text = text.substring(s, e + 1);
  return text;
}

function isRangeLike(v: unknown): boolean {
  if (typeof v === 'number') return Number.isFinite(v);
  if (!v || typeof v !== 'object' || Array.isArray(v)) return false;
  const o = v as Record<string, unknown>;
  return ['min', 'max', 'minimum', 'maximum'].some((k) => typeof o[k] === 'number' && Number.isFinite(o[k] as number));
}

/** Throws a 422 unless [text] holds a meal-estimate JSON object the app can
 *  use: a JSON object with a numeric `calories` (number or {min,max}) or a
 *  non-empty `items` list. Deliberately looser than label_read: the app's
 *  parser tolerates missing fields, so only clearly non-estimate answers
 *  (prose, chat replies, arrays) are rejected. The text is returned
 *  unchanged so the app parses exactly what it parsed before. */
export function validateMealEstimateOutput(text: string): string {
  let parsed: unknown;
  try {
    parsed = JSON.parse(extractMealEstimateJson(text));
  } catch {
    parsed = null;
  }
  let ok = false;
  if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
    const o = parsed as Record<string, unknown>;
    ok = isRangeLike(o.calories) || (Array.isArray(o.items) && o.items.length > 0);
  }
  if (!ok) {
    throw new AiGuardError(422, 'estimate_unreadable',
      "Couldn't estimate that meal. Try describing it differently.");
  }
  return text;
}

/** The model text the client receives. For label_read this is the validated,
 *  canonical JSON; an unreadable or implausible answer becomes a 422 the app
 *  maps to "Couldn't read that label". meal_estimate must be a usable JSON
 *  estimate (else 422, which the app treats as an AI failure and falls back
 *  to its local estimate). Other purposes pass through. */
export function finalizeResponseText(purpose: AiPurpose, text: string): string {
  if (purpose === 'meal_estimate') return validateMealEstimateOutput(text);
  if (purpose !== 'label_read') return text;
  try {
    return JSON.stringify(normalizeLabelReadOutput(text));
  } catch (e) {
    if (e instanceof LabelUnreadableError) {
      throw new AiGuardError(422, 'label_unreadable',
        "Couldn't read that label. Try a sharper photo, or enter it yourself.");
    }
    throw e;
  }
}

// ── Trusted internal caller (ai-meal-coach → ai-chat-router) ────────────────

export const INTERNAL_HEADER = 'x-kynetix-internal';

export const INTERNAL_SECRET_ENV = 'AI_ROUTER_INTERNAL_SECRET';
export const MIN_INTERNAL_SECRET_LEN = 16;

/** The shared secret both ai-meal-coach (sender) and ai-chat-router
 *  (verifier) read from AI_ROUTER_INTERNAL_SECRET. There is deliberately no
 *  fallback (e.g. to the service role key): if it is unset or shorter than
 *  MIN_INTERNAL_SECRET_LEN this returns '' and the coach path fails closed. */
export function internalSecret(): string {
  const v = (Deno.env.get(INTERNAL_SECRET_ENV) ?? '').trim();
  return v.length >= MIN_INTERNAL_SECRET_LEN ? v : '';
}

export function timingSafeEqual(a: string, b: string): boolean {
  const ea = new TextEncoder().encode(a);
  const eb = new TextEncoder().encode(b);
  let diff = ea.length ^ eb.length;
  const n = Math.max(ea.length, eb.length);
  for (let i = 0; i < n; i++) diff |= (ea[i] ?? 0) ^ (eb[i] ?? 0);
  return diff === 0;
}

export function isTrustedInternal(req: Request, secret: string): boolean {
  const v = req.headers.get(INTERNAL_HEADER);
  return !!v && secret.length >= MIN_INTERNAL_SECRET_LEN && timingSafeEqual(v, secret);
}

// ── Rate limits ──────────────────────────────────────────────────────────────

function envInt(name: string, fallback: number): number {
  const v = parseInt(Deno.env.get(name) ?? '', 10);
  return Number.isFinite(v) && v > 0 ? v : fallback;
}

export interface RateTier { perMinute: number; perDay: number; }

/** Requests that run on Kynetix's OpenRouter key. */
export function standardTier(): RateTier {
  return { perMinute: envInt('AI_RATE_PER_MINUTE', 20), perDay: envInt('AI_RATE_PER_DAY', 300) };
}

/** Requests that run on the user's own ChatGPT plan. Higher, still bounded. */
export function planTier(): RateTier {
  return { perMinute: envInt('AI_PLAN_RATE_PER_MINUTE', 40), perDay: envInt('AI_PLAN_RATE_PER_DAY', 1000) };
}

export interface QuotaResult {
  allowed: boolean;
  scope?: 'minute' | 'day';
  retryAfter?: number;
  dayRequests: number;
  minuteRequests: number;
  enforced: boolean; // false when the ai_usage migration is not applied yet
}

/** Atomically checks + records one request via public.ai_usage_consume. */
export async function consumeQuota(
  admin: any, userId: string, tier: RateTier, chars: number, images: number,
): Promise<QuotaResult> {
  const { data, error } = await admin.rpc('ai_usage_consume', {
    p_user_id: userId,
    p_chars: Math.max(0, Math.floor(chars)),
    p_images: Math.max(0, Math.floor(images)),
    p_per_minute: tier.perMinute,
    p_per_day: tier.perDay,
  });
  if (error) {
    // Function missing = migration not applied yet. Fail open so AI keeps
    // working during the deploy window; caps above still apply.
    const code = String(error.code ?? '');
    if (code === 'PGRST202' || code === '42883') {
      console.warn('[ai_guard] ai_usage_consume missing; rate limit not enforced');
      return { allowed: true, dayRequests: 0, minuteRequests: 0, enforced: false };
    }
    throw new AiGuardError(503, 'rate_limit_unavailable', 'Kyno is busy right now. Try again in a minute.', { retry_after: 30 });
  }
  const d = (Array.isArray(data) ? data[0] : data) ?? {};
  return {
    allowed: d.allowed === true,
    scope: d.scope === 'day' ? 'day' : d.scope === 'minute' ? 'minute' : undefined,
    retryAfter: typeof d.retry_after === 'number' ? Math.max(1, d.retry_after) : undefined,
    dayRequests: Number(d.day_requests ?? 0),
    minuteRequests: Number(d.minute_requests ?? 0),
    enforced: true,
  };
}

// ── Daily image cap (coach) ─────────────────────────────────────────────────
//
// Vision calls are the expensive ones. The coach path may carry up to 6 photos
// per request; this caps photos per user per UTC day using the `images`
// counter that ai_usage_consume already maintains. (The counter includes
// label_read photos too: one per scan.)
//
// Model choice is unchanged. Trying a cheaper vision model first (e.g. Flash
// before Pro in OPENROUTER_VISION_MODELS) is an owner decision, not made here.

export function coachImagesPerDay(): number {
  return envInt('AI_COACH_IMAGES_PER_DAY', 30);
}

/** Pure: would [requested] more photos exceed [cap] given [usedToday]? */
export function imageCapExceeded(usedToday: number, requested: number, cap: number): boolean {
  return requested > 0 && Math.max(0, usedToday) + requested > cap;
}

export function imageCapError(retryAfter: number): AiGuardError {
  return new AiGuardError(429, 'rate_limited',
    "You've sent a lot of photos today. Photo analysis resets tomorrow; you can still type your meal.",
    { retry_after: Math.max(1, Math.ceil(retryAfter)), scope: 'images' });
}

/** Throws a 429 { error:'rate_limited', scope:'images', retry_after } when
 *  this request's photos would take the user over today's cap. Checked
 *  before ai_usage_consume, so a rejected request is not counted. Fails open
 *  only when the ai_usage table is missing (migration not applied). */
export async function enforceDailyImageCap(
  admin: any, userId: string, requested: number, cap = coachImagesPerDay(), now = new Date(),
): Promise<void> {
  if (requested <= 0) return;
  if (requested > cap) throw imageCapError(secondsUntilUtcMidnight(now));
  const day = now.toISOString().slice(0, 10); // UTC day, as ai_usage_consume
  const { data, error } = await admin
    .from('ai_usage')
    .select('images')
    .eq('user_id', userId)
    .eq('day', day)
    .maybeSingle();
  if (error) {
    const code = String(error.code ?? '');
    if (code === '42P01' || code === 'PGRST205') {
      console.warn('[ai_guard] ai_usage missing; image cap not enforced');
      return;
    }
    throw new AiGuardError(503, 'rate_limit_unavailable', 'Kyno is busy right now. Try again in a minute.', { retry_after: 30 });
  }
  const used = Number(data?.images ?? 0);
  if (imageCapExceeded(Number.isFinite(used) ? used : 0, requested, cap)) {
    throw imageCapError(secondsUntilUtcMidnight(now));
  }
}

export function rateLimitedError(scope: 'minute' | 'day', retryAfter: number): AiGuardError {
  return new AiGuardError(429, 'rate_limited',
    scope === 'day'
      ? "You've reached today's Kyno limit. It resets tomorrow."
      : "You're sending messages quickly. Wait a moment and try again.",
    { retry_after: Math.max(1, Math.ceil(retryAfter)), scope });
}

/** Seconds until the next UTC midnight (daily window reset). */
export function secondsUntilUtcMidnight(now = new Date()): number {
  const next = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1);
  return Math.max(1, Math.ceil((next - now.getTime()) / 1000));
}

export function jsonError(err: AiGuardError, cors: Record<string, string>): Response {
  const headers: Record<string, string> = { ...cors, 'Content-Type': 'application/json' };
  const ra = err.extra['retry_after'];
  if (typeof ra === 'number') headers['Retry-After'] = String(ra);
  return new Response(JSON.stringify(err.toBody()), { status: err.status, headers });
}
