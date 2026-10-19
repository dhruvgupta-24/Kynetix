// Input caps and allow-lists for ai-meal-coach. Pure; tested in limits_test.ts.

export const MAX_COACH_MESSAGE_CHARS = 4_000;
export const MAX_COACH_HISTORY = 10;
export const MAX_COACH_HISTORY_ITEM_CHARS = 4_000;
export const MAX_COACH_IMAGES = 6;
/** Raw base64 length per image (~2 MB binary). The app sends <=1024px q75 JPEGs. */
export const MAX_COACH_IMAGE_B64 = 2_700_000;

export interface InputError {
  status: number;
  body: { success: false; error: string; message: string; limit?: number };
}

function err(status: number, error: string, message: string, limit?: number): InputError {
  return { status, body: { success: false, error, message, ...(limit !== undefined ? { limit } : {}) } };
}

/** Returns an error for over-cap or malformed input, or null when OK. */
export function coachInputError(body: any): InputError | null {
  if (!body || typeof body !== 'object') return err(400, 'invalid_request', 'Request body must be JSON.');
  if (body.message !== undefined && body.message !== null && typeof body.message !== 'string') {
    return err(400, 'invalid_request', 'message must be text.');
  }
  if (typeof body.message === 'string' && body.message.length > MAX_COACH_MESSAGE_CHARS) {
    return err(413, 'too_many_chars', 'That message is too long. Shorten it and try again.', MAX_COACH_MESSAGE_CHARS);
  }

  const images: unknown[] = Array.isArray(body.images_base64)
    ? body.images_base64
    : (body.image_base64 != null ? [body.image_base64] : []);
  if (images.length > MAX_COACH_IMAGES) {
    return err(413, 'too_many_images', `You can send up to ${MAX_COACH_IMAGES} photos at once.`, MAX_COACH_IMAGES);
  }
  for (const img of images) {
    if (typeof img !== 'string' || img.length === 0) return err(400, 'invalid_image', 'Malformed photo.');
    if (img.length > MAX_COACH_IMAGE_B64) {
      return err(413, 'image_too_large', 'That photo is too large. Try a smaller one.', Math.floor(MAX_COACH_IMAGE_B64 * 3 / 4));
    }
    if (!/^[A-Za-z0-9+/=\r\n]+$/.test(img.slice(0, 256))) return err(400, 'invalid_image', 'Malformed photo.');
  }

  if (body.history !== undefined && body.history !== null) {
    if (!Array.isArray(body.history)) return err(400, 'invalid_request', 'history must be a list.');
    // Only the last MAX_COACH_HISTORY turns are used, each truncated to
    // MAX_COACH_HISTORY_ITEM_CHARS (long Kyno replies must not block a chat).
  }
  return null;
}

// Server-owned portion-anchor text (mirrors PortionAnchor.aiHint in the app).
// The client's free text is never placed in the system prompt.
const PORTION_HINTS: Record<'carbAnchored' | 'curryAnchored' | 'balanced', string> = {
  carbAnchored:
    'User eats a fixed roti/rice amount and uses sabzi or dal as a condiment ' +
    '(about 35 g dal per roti, 60 g per rice ladle). Do NOT assume a full ' +
    'katori of dal/sabzi unless the user explicitly mentions a large serving.',
  curryAnchored:
    'User eats until the dal/sabzi runs out, treating it as the main dish. ' +
    'Assume one full katori of dal (150 ml) only when no carb count is ' +
    'given; keep the stated roti count.',
  balanced:
    'User eats balanced portions of carbs and sides. Use standard Indian ' +
    'hostel estimates: about 50 g dal per roti, 85 g per rice ladle.',
};

/** Accepts an enum name ('carbAnchored' etc.) or the legacy hint text the app
 *  sends today, and returns the matching server-owned text (or null). */
export function coachPortionHint(v: unknown): string | null {
  if (typeof v !== 'string') return null;
  if (v in PORTION_HINTS) return PORTION_HINTS[v as keyof typeof PORTION_HINTS];
  if (v.startsWith('User eats a fixed roti/rice amount')) return PORTION_HINTS.carbAnchored;
  if (v.startsWith('User eats until the dal/sabzi runs out')) return PORTION_HINTS.curryAnchored;
  if (v.startsWith('User eats balanced portions')) return PORTION_HINTS.balanced;
  return null;
}
