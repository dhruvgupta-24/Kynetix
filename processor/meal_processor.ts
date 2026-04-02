import type { MealItem, EstimationResult } from "../types";
import { parseMeal } from "../parser/meal_parser";
import { estimateMeal } from "../engine/estimation_engine";

// ─── Types ────────────────────────────────────────────────────────────────────

type FoodType = MealItem["type"];

type WarningKind =
    | "capped"
    | "underreport_adjusted"
    | "reduced"
    | "priority_reduced";

interface ValidationWarning {
    kind: WarningKind;
    food: FoodType;
    original: number;
    corrected: number;
}

interface MealContext {
    hasPaneer: boolean;
    hasCarb: boolean;   // roti or rice present
    isSideDishOnly: boolean;  // no carb at all
    itemCount: number;
    thodaTargets: Set<FoodType>; // only foods preceded by a thoda signal
}

interface ProcessorResult extends EstimationResult {
    warnings: ValidationWarning[];
    itemCount: number;
}

// ─── AI Fallback Hook (future integration) ────────────────────────────────────

interface AIFallbackHook {
    isAvailable(): boolean;
    process(input: string): Promise<EstimationResult>;
}

const aiFallbackHooks: AIFallbackHook[] = [];

export function registerAIHook(hook: AIFallbackHook): void {
    aiFallbackHooks.push(hook);
}

// ─── Constants ────────────────────────────────────────────────────────────────

const QUANTITY_CAPS: Record<FoodType, number> = {
    roti: 8,
    rice: 4,
    dal: 3,
    sabzi: 3,
    paneer: 4,
};

// Underreport factors — only applied when no carb is present
const UNDERREPORT_FACTOR: Partial<Record<FoodType, number>> = {
    dal: 1.15,
    sabzi: 1.10,
};

// Food priority: higher = more important, corrections prefer low-priority items
const FOOD_PRIORITY: Record<FoodType, number> = {
    paneer: 5,
    roti: 4,
    rice: 3,
    dal: 2,
    sabzi: 1,
};

// Thoda signal words (raw input scan; parser strips these before estimation)
const THODA_SIGNALS = new Set(["thoda", "little", "thodi", "kam"]);

// Adjacent food keywords for thoda-target detection (mirrors parser keywords)
const FOOD_TOKEN_MAP: Record<string, FoodType> = {
    roti: "roti", chapati: "roti", chapatti: "roti", chappati: "roti",
    rice: "rice", chawal: "rice",
    dal: "dal", daal: "dal", lentil: "dal", lentils: "dal",
    paneer: "paneer",
    sabzi: "sabzi", sabji: "sabzi", curry: "sabzi",
    bhaji: "sabzi", bhajji: "sabzi",
};

// Correction limit — never move quantity by more than ±40%
const MAX_CORRECTION_RATIO = 0.40;

// ─── Utilities ────────────────────────────────────────────────────────────────

function emptyResult(): ProcessorResult {
    return {
        calories: { min: 0, max: 0 },
        protein: { min: 0, max: 0 },
        confidence: 0,
        warnings: [],
        itemCount: 0,
    };
}

function clampCorrectionFactor(
    original: number,
    factor: number
): number {
    const ratio = factor - 1; // e.g. 1.15 → +0.15, 0.75 → -0.25
    const clamped = Math.max(-MAX_CORRECTION_RATIO, Math.min(MAX_CORRECTION_RATIO, ratio));
    return 1 + clamped;
}

function applyFactor(
    item: MealItem,
    factor: number,
    kind: WarningKind,
    warnings: ValidationWarning[]
): MealItem {
    const safe = clampCorrectionFactor(item.quantity, factor);
    const corrected = parseFloat((item.quantity * safe).toFixed(2));
    if (corrected === item.quantity) return item;
    warnings.push({ kind, food: item.type, original: item.quantity, corrected });
    return { ...item, quantity: corrected };
}

// ─── Validation (unchanged) ───────────────────────────────────────────────────

function mergeDuplicates(items: MealItem[]): MealItem[] {
    const seen = new Map<FoodType, MealItem>();
    for (const item of items) {
        const existing = seen.get(item.type);
        if (existing) {
            existing.quantity += item.quantity;
        } else {
            seen.set(item.type, { ...item });
        }
    }
    return Array.from(seen.values());
}

function capQuantities(
    items: MealItem[],
    warnings: ValidationWarning[]
): MealItem[] {
    return items.map((item) => {
        const cap = QUANTITY_CAPS[item.type];
        if (item.quantity > cap) {
            warnings.push({
                kind: "capped",
                food: item.type,
                original: item.quantity,
                corrected: cap,
            });
            return { ...item, quantity: cap };
        }
        return item;
    });
}

function validate(items: MealItem[], warnings: ValidationWarning[]): MealItem[] {
    return capQuantities(mergeDuplicates(items), warnings);
}

// ─── Context Detection ────────────────────────────────────────────────────────

/**
 * Scan the raw input token-by-token.
 * For each thoda-signal word, find the NEXT food token after it — that food
 * is tagged as a thoda target.  If no next food found, fall back to the
 * previous food token.  This gives targeted (not blanket) reduction.
 */
function detectThodaTargets(raw: string): Set<FoodType> {
    const tokens = raw.toLowerCase().split(/\s+/);
    const targets = new Set<FoodType>();

    for (let i = 0; i < tokens.length; i++) {
        const tok = tokens[i]!;
        if (!THODA_SIGNALS.has(tok)) continue;

        // Look forward for the nearest food token
        let found = false;
        for (let j = i + 1; j < tokens.length; j++) {
            const food = FOOD_TOKEN_MAP[tokens[j]!];
            if (food) { targets.add(food); found = true; break; }
        }

        // Fall back: look backward
        if (!found) {
            for (let j = i - 1; j >= 0; j--) {
                const food = FOOD_TOKEN_MAP[tokens[j]!];
                if (food) { targets.add(food); break; }
            }
        }
    }

    return targets;
}

function detectContext(items: MealItem[], raw: string): MealContext {
    const types = new Set(items.map((i) => i.type));
    return {
        hasPaneer: types.has("paneer"),
        hasCarb: types.has("roti") || types.has("rice"),
        isSideDishOnly: !types.has("roti") && !types.has("rice"),
        itemCount: items.length,
        thodaTargets: detectThodaTargets(raw),
    };
}

// ─── Corrections ─────────────────────────────────────────────────────────────

/**
 * Underreport correction — only when no carb present AND paneer absent.
 * Paneer's caloric density means the user is not truly underreporting.
 */
function underreportCorrection(
    items: MealItem[],
    ctx: MealContext,
    warnings: ValidationWarning[]
): MealItem[] {
    if (!ctx.isSideDishOnly || ctx.hasPaneer) return items;

    return items.map((item) => {
        const factor = UNDERREPORT_FACTOR[item.type];
        return factor ? applyFactor(item, factor, "underreport_adjusted", warnings) : item;
    });
}

/**
 * Targeted thoda reduction — applies ONLY to foods that had a thoda signal
 * adjacent to them in the raw input.
 *
 * Anti-stack rule: if underreport already ran on this item, skip thoda — the
 * corrections conflict in direction (up vs down).
 */
function thodaReduction(
    items: MealItem[],
    ctx: MealContext,
    warnings: ValidationWarning[],
    underreportTouched: Set<FoodType>
): MealItem[] {
    if (ctx.thodaTargets.size === 0) return items;

    return items.map((item) => {
        if (!ctx.thodaTargets.has(item.type)) return item;
        if (underreportTouched.has(item.type)) return item; // anti-stack
        return applyFactor(item, 0.78, "reduced", warnings);
    });
}

/**
 * Priority-based reduction for large meals (≥4 items).
 * Only corrects low-priority foods (sabzi, dal) when high-priority foods
 * (paneer) are present — avoids touching the main protein source.
 */
function priorityReduction(
    items: MealItem[],
    ctx: MealContext,
    warnings: ValidationWarning[]
): MealItem[] {
    if (ctx.itemCount < 4 || !ctx.hasPaneer) return items;

    const LOW_PRIORITY_THRESHOLD = 2; // sabzi(1) and dal(2)

    return items.map((item) => {
        const priority = FOOD_PRIORITY[item.type];
        if (priority > LOW_PRIORITY_THRESHOLD) return item;
        return applyFactor(item, 0.88, "priority_reduced", warnings);
    });
}

// ─── Correction Pipeline ─────────────────────────────────────────────────────

function applyCorrections(
    items: MealItem[],
    ctx: MealContext,
    warnings: ValidationWarning[]
): MealItem[] {
    // Track which foods were touched by underreport (to prevent stack)
    const underreportTouched = new Set<FoodType>();
    const beforeUR = warnings.length;

    let result = underreportCorrection(items, ctx, warnings);

    // Record which foods got underreport correction
    for (let i = beforeUR; i < warnings.length; i++) {
        underreportTouched.add(warnings[i]!.food);
    }

    result = thodaReduction(result, ctx, warnings, underreportTouched);
    result = priorityReduction(result, ctx, warnings);

    return result;
}

// ─── Public API ───────────────────────────────────────────────────────────────

export function processMealInput(input: string): ProcessorResult {
    const warnings: ValidationWarning[] = [];

    if (!input || input.trim().length === 0) return emptyResult();

    let items: MealItem[];
    try {
        items = parseMeal(input);
    } catch {
        return emptyResult();
    }

    if (items.length === 0) return emptyResult();

    // Step 1 — Validate
    items = validate(items, warnings);

    // Step 2 — Detect context (must happen AFTER merge/cap)
    const ctx = detectContext(items, input);

    // Step 3 — Correct
    items = applyCorrections(items, ctx, warnings);

    // Step 4 — Estimate
    let estimation: EstimationResult;
    try {
        estimation = estimateMeal(items);
    } catch {
        return emptyResult();
    }

    // Step 5 — Multi-item upper-bound trim (low-priority only)
    if (items.length >= 4) {
        const reductionRatio = 1 - (items.length - 3) * 0.03;
        estimation = {
            ...estimation,
            calories: {
                min: estimation.calories.min,
                max: parseFloat((estimation.calories.max * reductionRatio).toFixed(2)),
            },
        };
    }

    return {
        ...estimation,
        warnings,
        itemCount: items.length,
    };
}

/*
─────────────────────────────────────────────────────────────────────
TEST CASES
─────────────────────────────────────────────────────────────────────

Original 10 (must still pass):
1.  "2 roti and dal"                → no corrections
2.  ""                              → emptyResult
3.  "thoda paneer and roti"         → paneer reduced (nearest), roti untouched
4.  "10 paneer"                     → capped at 4
5.  "dal sabzi"                     → underreport: dal×1.15, sabzi×1.10
6.  "2 roti dal rice thoda paneer"  → thoda targets paneer only; multi-item trim
7.  "some random text"              → emptyResult
8.  "paneer paneer 2 paneer"        → merged→4, capped=4
9.  "I ate dal and 2 chapati sabzi" → has carb; NO underreport
10. "half rice with paneer"         → no thoda/underreport

New 10:
11. "thoda paneer and 2 roti"
    → thoda targets paneer only (nearest food after "thoda")
    → paneer reduced, 2 roti untouched

12. "paneer with little sabzi"
    → thoda target: sabzi (nearest food after "little")
    → sabzi reduced, paneer untouched
    → no underreport (paneer present)

13. "dal sabzi only"
    → underreport: dal×1.15, sabzi×1.10
    → "only" is filler, ignored

14. "2 roti paneer sabzi"
    → hasPaneer + hasCarb → NO underreport
    → 3 items < 4 → no priority reduction
    → no thoda → clean estimate

15. "paneer sabzi dal rice"
    → 4 items, has paneer
    → priority reduction on sabzi(1) and dal(2): factor 0.88
    → multi-item upper-bound trim (−3%)

16. "thoda dal and thoda sabzi"
    → both dal and sabzi are thoda targets
    → both reduced; isSideDishOnly so underreport would apply
    → anti-stack: underreport runs first, thoda is skipped for same foods

17. "15 roti"
    → capped at 8; warning emitted

18. "double paneer"
    → parser resolves "double"→2; no correction (not extreme)

19. "I ate little rice"
    → thoda targets: rice (nearest food after "little")
    → rice reduced 22%; hasCarb=true, no underreport

20. "sabzi"
    → single item, isSideDishOnly, no paneer
    → underreport: sabzi×1.10
    → no thoda, no priority reduction

─────────────────────────────────────────────────────────────────────
*/
