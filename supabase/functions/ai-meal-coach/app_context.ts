// The app's computed brief (targets, 14 days of eating, lift trends, steps,
// weight, food options). Pure; tested in app_context_test.ts.
//
// The brief is built on the phone from the user's own data, so it is treated
// like any other user data: every string is cleaned and capped, keys must be
// plain identifiers, size and depth are bounded, and the result is placed only
// inside the fenced USER DATA area of the system prompt.

import { cleanUserText, USER_DATA_BEGIN, USER_DATA_END } from './prompt_safety.ts';

/** Raw JSON size accepted from the client. */
export const MAX_APP_CONTEXT_CHARS = 20_000;
/** Size of the rendered block in the prompt. */
export const MAX_APP_CONTEXT_RENDERED = 18_000;
const MAX_DEPTH = 5;
const MAX_ARRAY = 40;
const MAX_KEYS = 40;
const KEY_RE = /^[a-z0-9_]{1,48}$/;

export type Json = null | boolean | number | string | Json[] | { [k: string]: Json };

/** Returns a cleaned copy, or null when [raw] isn't an acceptable object. */
export function sanitizeAppContext(raw: unknown): { [k: string]: Json } | null {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
  let size = 0;
  try {
    size = JSON.stringify(raw).length;
  } catch {
    return null;
  }
  if (size > MAX_APP_CONTEXT_CHARS) return null;
  const v = clean(raw, 0);
  return v && typeof v === 'object' && !Array.isArray(v) ? v as { [k: string]: Json } : null;
}

function clean(v: unknown, depth: number): Json | undefined {
  if (v === null) return null;
  if (typeof v === 'boolean') return v;
  if (typeof v === 'number') return Number.isFinite(v) ? Math.round(v * 10) / 10 : undefined;
  if (typeof v === 'string') return cleanUserText(v, 80);
  if (depth >= MAX_DEPTH) return undefined;
  if (Array.isArray(v)) {
    const out: Json[] = [];
    for (const item of v.slice(0, MAX_ARRAY)) {
      const c = clean(item, depth + 1);
      if (c !== undefined) out.push(c);
    }
    return out;
  }
  if (typeof v === 'object') {
    const out: { [k: string]: Json } = {};
    let n = 0;
    for (const [k, val] of Object.entries(v as Record<string, unknown>)) {
      if (n >= MAX_KEYS) break;
      if (!KEY_RE.test(k)) continue;
      const c = clean(val, depth + 1);
      if (c === undefined) continue;
      out[k] = c;
      n++;
    }
    return out;
  }
  return undefined;
}

/** The brief as compact JSON inside its own fence. */
export function renderAppContext(ctx: { [k: string]: Json }): string {
  let body = JSON.stringify(ctx);
  if (body.length > MAX_APP_CONTEXT_RENDERED) {
    body = body.slice(0, MAX_APP_CONTEXT_RENDERED) + ' …(truncated)';
  }
  // Defence in depth: strings were cleaned of [[ ]], but never let the fence
  // markers appear inside the block.
  body = body.split(USER_DATA_BEGIN).join(' ').split(USER_DATA_END).join(' ');
  return `${USER_DATA_BEGIN}\nAPP BRIEF (computed by the app from the user's own logs):\n${body}\n${USER_DATA_END}`;
}

/** Day targets the app computed, when present and plausible. The app owns
 *  the target engine (steps, training day, manual targets), so its numbers
 *  win over the server's approximation. */
export function clientTargets(ctx: { [k: string]: Json } | null): {
  calories: number;
  protein: number;
  carbs: number | null;
  fat: number | null;
  dayType: string | null;
  userSet: boolean;
} | null {
  const today = ctx?.today;
  if (!today || typeof today !== 'object' || Array.isArray(today)) return null;
  const t = (today as Record<string, Json>).target;
  if (!t || typeof t !== 'object' || Array.isArray(t)) return null;
  const tt = t as Record<string, Json>;
  const kcal = tt.kcal, pro = tt.protein_g;
  if (typeof kcal !== 'number' || typeof pro !== 'number') return null;
  if (kcal < 800 || kcal > 6500 || pro < 20 || pro > 450) return null;
  const num = (x: Json | undefined) => (typeof x === 'number' && x >= 0 && x < 2000 ? x : null);
  const dt = (today as Record<string, Json>).day_type;
  return {
    calories: Math.round(kcal),
    protein: Math.round(pro),
    carbs: num(tt.carbs_g),
    fat: num(tt.fat_g),
    dayType: typeof dt === 'string' && dt ? dt : null,
    userSet: tt.kcal_set_by_user === true,
  };
}
