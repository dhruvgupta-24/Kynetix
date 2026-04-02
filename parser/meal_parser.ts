import type { MealItem } from "../types";

// ─── Types ────────────────────────────────────────────────────────────────────

type FoodType = MealItem["type"];
type Unit = NonNullable<MealItem["unit"]>;
type RotiSubtype = NonNullable<MealItem["rotiSubtype"]>;

// ─── Keyword Maps ─────────────────────────────────────────────────────────────

const FOOD_KEYWORDS: Record<FoodType, string[]> = {
    roti: ["roti", "chapati", "chapatti", "chappati"],
    rice: ["rice", "chawal"],
    dal: ["dal", "daal", "lentil", "lentils"],
    paneer: ["paneer"],
    sabzi: ["sabzi", "sabji", "curry", "bhaji", "bhajji", "vegetable", "veggies"],
};

// Flat reverse-lookup: keyword → FoodType
const KEYWORD_TO_FOOD: Map<string, FoodType> = new Map(
    (Object.entries(FOOD_KEYWORDS) as [FoodType, string[]][]).flatMap(
        ([food, kws]) => kws.map((kw) => [kw, food] as [string, FoodType])
    )
);

const DEFAULT_UNIT: Partial<Record<FoodType, Unit>> = {
    rice: "ladle",
    dal: "M",
    sabzi: "M",
    paneer: "M",
};

const UNIT_KEYWORDS: Record<Unit, string[]> = {
    S: ["small", "s"],
    M: ["medium", "m", "serving", "servings"],
    ladle: ["ladle", "ladles", "scoop", "scoops"],
};

// Flat reverse-lookup: keyword → Unit
const KEYWORD_TO_UNIT: Map<string, Unit> = new Map(
    (Object.entries(UNIT_KEYWORDS) as [Unit, string[]][]).flatMap(
        ([unit, kws]) => kws.map((kw) => [kw, unit] as [string, Unit])
    )
);

const ROTI_NORMAL_WORDS = ["butter", "ghee", "oily", "buttered"];
const ROTI_DRY_WORDS = ["dry", "plain", "without"];
const FILLER_WORDS = new Set([
    "with", "and", "i", "ate", "had", "some", "a", "an", "of", "the",
    "little", "thoda", "more", "extra", "also",
]);

const NUMBER_WORDS: Record<string, number> = {
    one: 1, two: 2, three: 3, four: 4, five: 5,
    six: 6, seven: 7, eight: 8, nine: 9, ten: 10,
};

// Quantity modifier words (resolved before per-food extraction)
const QUANTITY_MODIFIERS: Record<string, number> = {
    half: 0.5,
    double: 2,
    twice: 2,
};

// ─── Helpers ──────────────────────────────────────────────────────────────────

function normalizeInput(input: string): string {
    return input
        .toLowerCase()
        .replace(/,/g, " and ")
        .replace(/\s+/g, " ")
        .trim();
}

function splitIntoChunks(normalized: string): string[] {
    return normalized
        .split(/\b(?:and|with)\b/)
        .map((c) => c.trim())
        .filter((c) => c.length > 0);
}

function tokenizeChunk(chunk: string): string[] {
    return chunk
        .split(/\s+/)
        .map((t) => t.replace(/[^a-z0-9.]/g, ""))
        .filter((t) => t.length > 0);
}

function isFoodToken(token: string): boolean {
    return KEYWORD_TO_FOOD.has(token);
}

function isQuantityToken(token: string): boolean {
    const n = parseFloat(token);
    if (!isNaN(n) && n > 0) return true;
    return token in NUMBER_WORDS || token in QUANTITY_MODIFIERS;
}

function resolveQuantityToken(token: string): number {
    const n = parseFloat(token);
    if (!isNaN(n) && n > 0) return n;
    if (token in NUMBER_WORDS) return NUMBER_WORDS[token]!;
    if (token in QUANTITY_MODIFIERS) return QUANTITY_MODIFIERS[token]!;
    return 1;
}

function detectFoodType(tokens: string[]): FoodType | null {
    for (const token of tokens) {
        const food = KEYWORD_TO_FOOD.get(token);
        if (food !== undefined) return food;
    }
    return null;
}

/**
 * Nearest-number-to-food priority rule:
 * Scan left from foodIndex, then right, pick closest numeric token.
 */
function extractQuantityNearFood(tokens: string[], foodIndex: number): number {
    let bestDistance = Infinity;
    let bestValue = 1;

    for (let i = 0; i < tokens.length; i++) {
        if (!isQuantityToken(tokens[i]!)) continue;
        const dist = Math.abs(i - foodIndex);
        if (dist < bestDistance) {
            bestDistance = dist;
            bestValue = resolveQuantityToken(tokens[i]!);
        }
    }

    return bestValue;
}

function extractUnit(tokens: string[]): Unit | undefined {
    for (const token of tokens) {
        const unit = KEYWORD_TO_UNIT.get(token);
        if (unit !== undefined) return unit;
    }
    return undefined;
}

function detectRotiSubtype(tokens: string[]): RotiSubtype {
    for (const token of tokens) {
        if (ROTI_NORMAL_WORDS.includes(token)) return "normal";
        if (ROTI_DRY_WORDS.includes(token)) return "dry";
    }
    return "unknown";
}

/**
 * Split a token array into segments, one per food token found.
 *
 * Boundary rule: the gap between two adjacent food tokens is owned by the
 * RIGHT food (numbers in natural language precede their subject: "2 roti").
 * Concretely, the left segment's right boundary is the food token itself
 * (exclusive of anything after it up to the next food), and the right
 * segment starts from the token immediately after the left food.
 */
function segmentByFood(
    tokens: string[]
): Array<{ foodIndex: number; tokens: string[] }> {
    const foodPositions: number[] = tokens
        .map((t, i) => (isFoodToken(t) ? i : -1))
        .filter((i) => i >= 0);

    if (foodPositions.length <= 1) {
        return foodPositions.length === 0
            ? []
            : [{ foodIndex: foodPositions[0]!, tokens }];
    }

    const segments: Array<{ foodIndex: number; tokens: string[] }> = [];

    for (let s = 0; s < foodPositions.length; s++) {
        const foodIdx = foodPositions[s]!;
        const prevFoodIdx = foodPositions[s - 1] ?? -1;
        const nextFoodIdx = foodPositions[s + 1] ?? tokens.length;

        // Left boundary: everything after the previous food token
        const leftBound = prevFoodIdx + 1;
        // Right boundary: this food token + any trailing non-food, non-quantity
        // context up to (but not including) the next food's pre-tokens.
        // Strategy: right segment starts at the first quantity-or-food token
        // that appears AFTER this food and BEFORE the next food.
        // Simpler: give this food token itself + everything to its LEFT
        // (back to leftBound), and give anything between this food and the
        // next food to the next food segment.
        const rightBound = foodIdx + 1;

        const segTokens = tokens.slice(leftBound, rightBound);
        const localFoodIndex = foodIdx - leftBound;
        segments.push({ foodIndex: localFoodIndex, tokens: segTokens });
    }

    return segments;
}

// ─── Core Parser ──────────────────────────────────────────────────────────────

function buildMealItem(tokens: string[], foodIndex: number): MealItem | null {
    const foodType = KEYWORD_TO_FOOD.get(tokens[foodIndex] ?? "");
    if (!foodType) return null;

    const meaningfulTokens = tokens.filter((t) => !FILLER_WORDS.has(t));
    const localMeaningful = meaningfulTokens;

    // Re-compute foodIndex within meaningful tokens for nearest-number rule
    const meaningfulFoodIndex = localMeaningful.indexOf(tokens[foodIndex] ?? "");
    const quantity = extractQuantityNearFood(
        localMeaningful,
        meaningfulFoodIndex >= 0 ? meaningfulFoodIndex : 0
    );

    const explicitUnit = extractUnit(meaningfulTokens);

    const item: MealItem = { type: foodType, quantity };

    const unit = explicitUnit ?? DEFAULT_UNIT[foodType];
    if (unit !== undefined) item.unit = unit;

    if (foodType === "roti") {
        item.rotiSubtype = detectRotiSubtype(tokens);
    }

    return item;
}

function parseChunk(chunk: string): MealItem[] {
    const tokens = tokenizeChunk(chunk);
    const segments = segmentByFood(tokens);
    return segments
        .map((seg) => buildMealItem(seg.tokens, seg.foodIndex))
        .filter((item): item is MealItem => item !== null);
}

// ─── Deduplication: merge repeated same-type items ────────────────────────────

function mergeRepeated(items: MealItem[]): MealItem[] {
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

// ─── Public API ───────────────────────────────────────────────────────────────

export function parseMeal(input: string): MealItem[] {
    if (!input || input.trim().length === 0) return [];

    const normalized = normalizeInput(input);
    const chunks = splitIntoChunks(normalized);
    const raw: MealItem[] = [];

    for (const chunk of chunks) {
        raw.push(...parseChunk(chunk));
    }

    return mergeRepeated(raw);
}

/*
──────────────────────────────────────────
TEST CASES — ORIGINAL 12
──────────────────────────────────────────

1.  "2 roti and dal"
    → [roti×2(unknown), dal×1(M)]

2.  "paneer 2 servings and 3 roti"
    → [paneer×2(M), roti×3(unknown)]

3.  "1 ladle rice with dal"
    → [rice×1(ladle), dal×1(M)]

4.  "4 roti, sabzi"
    → [roti×4(unknown), sabzi×1(M)]

5.  "paneer and rice"
    → [paneer×1(M), rice×1(ladle)]

6.  "dry roti 3"
    → [roti×3(dry)]

7.  "ghee roti"
    → [roti×1(normal)]

8.  "I ate dal and 2 chapati"
    → [dal×1(M), roti×2(unknown)]

9.  ""
    → []

10. "some random text"
    → []

11. "rice, dal, paneer, roti"
    → [rice×1(ladle), dal×1(M), paneer×1(M), roti×1(unknown)]

12. "two chapati and a small paneer"
    → [roti×2(unknown), paneer×1(S)]

──────────────────────────────────────────
TEST CASES — NEW (10)
──────────────────────────────────────────

13. "2 roti dal rice"
    → [roti×2(unknown), dal×1(M), rice×1(ladle)]

14. "paneer 2 roti sabzi"
    → [paneer×1(M), roti×2(unknown), sabzi×1(M)]

15. "half roti"
    → [roti×0.5(unknown)]

16. "double paneer"
    → [paneer×2(M)]

17. "1 roti 1 roti more"
    → [roti×2(unknown)]   ← merged

18. "ate paneer and roti"
    → [paneer×1(M), roti×1(unknown)]

19. "thoda dal sabzi 2 roti"
    → [dal×1(M), sabzi×1(M), roti×2(unknown)]

20. "2 roti dal rice thoda paneer"
    → [roti×2(unknown), dal×1(M), rice×1(ladle), paneer×1(M)]

21. "had some chawal and daal"
    → [rice×1(ladle), dal×1(M)]

22. "3 chapatti ghee roti"  ← two roti keywords in one chunk, merged
    → [roti×4(normal)]     ← 3 + 1, both detected and summed

──────────────────────────────────────────
*/
