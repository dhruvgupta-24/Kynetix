// label_read — server-owned prompt and output contract for reading a photo of
// a packaged-food nutrition table (purpose 'label_read' in ai-chat-router).
//
// The app sends one photo. The model returns JSON only; the router validates
// it with normalizeLabelReadOutput before anything reaches the client, and the
// client shows the values in an editable form the user must confirm. Nothing
// here is logged or saved without that confirmation.

export const LABEL_READ_SYSTEM_PROMPT: string = [
  'You read nutrition information tables on packaged food sold in India (FSSAI labels).',
  'You are given one photo. Read only what is printed. Never guess or use outside knowledge of the product.',
  '',
  'Extract:',
  '- product_name and brand if clearly printed on the photo, else null.',
  '- net_quantity and net_unit: the pack\'s net weight or volume ("Net Wt. 40 g", "Net Qty 200 ml", "1 kg"). Convert kg to g and L to ml. For a multipack ("6 x 35 g") use the total. null if not visible.',
  '- serving_size: the stated serving in g or ml, else null.',
  '- basis: "per_100ml" if the table is per 100 ml, otherwise "per_100g".',
  '- per_100: energy_kcal, protein_g, carbohydrates_g, fat_g, fibre_g, sugar_g, all per 100 g (or per 100 ml).',
  '',
  'Rules:',
  '- If energy is only in kJ, convert: kcal = kJ / 4.184.',
  '- If the table is only per serving, convert to per 100 using the serving size. If the serving size is not printed, set readable to false.',
  '- Use "Total sugars" for sugar_g. Use dietary fibre for fibre_g. Use null for a value that is not printed.',
  '- If the photo is not a nutrition table, or the numbers cannot be read with confidence, set readable to false and the numbers to null.',
  '- Numbers are plain JSON numbers (no units, no strings).',
  '',
  'Return ONLY this JSON object, no prose, no code fences:',
  '{"readable": true, "product_name": null, "brand": null, "basis": "per_100g", "net_quantity": null, "net_unit": null, "serving_size": null, "per_100": {"energy_kcal": 0, "protein_g": 0, "carbohydrates_g": 0, "fat_g": 0, "fibre_g": null, "sugar_g": null}}',
].join('\n');

export interface LabelReadOutput {
  readable: true;
  product_name: string | null;
  brand: string | null;
  basis: 'per_100g' | 'per_100ml';
  net_quantity: number | null;
  net_unit: 'g' | 'ml' | null;
  serving_size: number | null;
  per_100: {
    energy_kcal: number;
    protein_g: number;
    carbohydrates_g: number;
    fat_g: number;
    fibre_g: number | null;
    sugar_g: number | null;
  };
}

/** Thrown when the model's answer is not a readable, plausible label. */
export class LabelUnreadableError extends Error {
  constructor(readonly reason: string) {
    super('label_unreadable');
  }
}

function extractJsonObject(text: string): unknown {
  let t = (text ?? '').trim();
  const fence = t.match(/^```[a-zA-Z]*\s*([\s\S]*?)\s*```$/);
  if (fence) t = fence[1].trim();
  if (!t.startsWith('{')) {
    const start = t.indexOf('{');
    const end = t.lastIndexOf('}');
    if (start < 0 || end <= start) throw new LabelUnreadableError('no json');
    t = t.slice(start, end + 1);
  }
  try {
    return JSON.parse(t);
  } catch {
    throw new LabelUnreadableError('invalid json');
  }
}

function num(v: unknown, max: number, required: boolean, field: string): number | null {
  if (v === null || v === undefined) {
    if (required) throw new LabelUnreadableError(`${field} missing`);
    return null;
  }
  if (typeof v !== 'number' || !Number.isFinite(v) || v < 0 || v > max) {
    throw new LabelUnreadableError(`${field} out of range`);
  }
  return Math.round(v * 10) / 10;
}

function str(v: unknown): string | null {
  if (typeof v !== 'string') return null;
  // Plain text only: drop control characters and cap the length.
  const s = v.replace(/[\u0000-\u001f\u007f]/g, ' ').trim();
  return s.length === 0 ? null : s.slice(0, 80);
}

/** Validate the model's answer against the strict schema and return it in
 *  canonical form. Throws LabelUnreadableError when it is unreadable, has
 *  extra structure we cannot trust, or is physically implausible. */
export function normalizeLabelReadOutput(text: string): LabelReadOutput {
  const raw = extractJsonObject(text);
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    throw new LabelUnreadableError('not an object');
  }
  const o = raw as Record<string, unknown>;
  if (o.readable !== true) throw new LabelUnreadableError('model said unreadable');

  const per = o.per_100;
  if (!per || typeof per !== 'object' || Array.isArray(per)) {
    throw new LabelUnreadableError('per_100 missing');
  }
  const p = per as Record<string, unknown>;
  const kcal = num(p.energy_kcal, 900, true, 'energy_kcal')!;
  const protein = num(p.protein_g, 100, true, 'protein_g')!;
  const carbs = num(p.carbohydrates_g, 100, true, 'carbohydrates_g')!;
  const fat = num(p.fat_g, 100, true, 'fat_g')!;
  const fibre = num(p.fibre_g, 100, false, 'fibre_g');
  const sugar = num(p.sugar_g, 100, false, 'sugar_g');

  // 100 g cannot hold more than ~100 g of macros (5% for rounding).
  if (protein + carbs + fat > 105) throw new LabelUnreadableError('macros exceed 100 g');
  // Energy must roughly agree with 4/4/9 when there is energy to check.
  const atwater = 4 * protein + 4 * carbs + 9 * fat;
  if (kcal > 20 && atwater > 0 && Math.abs(atwater - kcal) / kcal > 0.35) {
    throw new LabelUnreadableError('energy contradicts macros');
  }
  if (kcal === 0 && atwater > 20) throw new LabelUnreadableError('zero energy with macros');

  const basis = o.basis === 'per_100ml' ? 'per_100ml' : 'per_100g';
  const netUnitRaw = o.net_unit;
  const netQuantity = num(o.net_quantity, 100_000, false, 'net_quantity');
  const netUnit = netQuantity === null
    ? null
    : (netUnitRaw === 'ml' ? 'ml' : netUnitRaw === 'g' ? 'g' : (basis === 'per_100ml' ? 'ml' : 'g'));

  return {
    readable: true,
    product_name: str(o.product_name),
    brand: str(o.brand),
    basis,
    net_quantity: netQuantity !== null && netQuantity > 0 ? netQuantity : null,
    net_unit: netQuantity !== null && netQuantity > 0 ? netUnit : null,
    serving_size: num(o.serving_size, 1000, false, 'serving_size'),
    per_100: {
      energy_kcal: kcal,
      protein_g: protein,
      carbohydrates_g: carbs,
      fat_g: fat,
      fibre_g: fibre,
      sugar_g: sugar,
    },
  };
}
