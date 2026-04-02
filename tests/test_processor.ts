import { processMealInput } from "../processor/meal_processor";

// ─── Helpers ──────────────────────────────────────────────────────────────────

let passed = 0;
let failed = 0;

function fmt(n: number): string { return n.toFixed(1); }

type Check = {
    /** minimum number of expected warnings */
    minWarnings?: number;
    /** warning kinds that MUST be present */
    hasKind?: string[];
    /** warning kinds that must NOT be present */
    lacksKind?: string[];
    /** foods that MUST appear in warnings */
    warnedFoods?: string[];
    /** foods that must NOT appear in warnings */
    unwarnedFoods?: string[];
    /** exact item count */
    itemCount?: number;
    /** result must be empty (all zeros) */
    isEmpty?: true;
};

function run(label: string, input: string, checks: Check = {}): void {
    const r = processMealInput(input);

    const structurallyValid =
        r.calories.min >= 0 &&
        r.calories.max >= r.calories.min &&
        r.protein.min >= 0 &&
        r.protein.max >= r.protein.min &&
        r.confidence >= 0 &&
        r.confidence <= 1;

    const allChecks: string[] = [];

    if (!structurallyValid) allChecks.push("INVALID_RANGES");

    if (checks.isEmpty) {
        if (r.calories.min !== 0 || r.calories.max !== 0)
            allChecks.push("expected empty result");
    }

    if (checks.itemCount !== undefined && r.itemCount !== checks.itemCount)
        allChecks.push(`itemCount expected ${checks.itemCount} got ${r.itemCount}`);

    if (checks.minWarnings !== undefined && r.warnings.length < checks.minWarnings)
        allChecks.push(`expected ≥${checks.minWarnings} warnings, got ${r.warnings.length}`);

    const warnKinds = r.warnings.map(w => w.kind);
    const warnFoods = r.warnings.map(w => w.food);

    for (const kind of checks.hasKind ?? []) {
        if (!warnKinds.includes(kind as never))
            allChecks.push(`missing warning kind: ${kind}`);
    }
    for (const kind of checks.lacksKind ?? []) {
        if (warnKinds.includes(kind as never))
            allChecks.push(`unexpected warning kind: ${kind}`);
    }
    for (const food of checks.warnedFoods ?? []) {
        if (!warnFoods.includes(food as never))
            allChecks.push(`expected warning for: ${food}`);
    }
    for (const food of checks.unwarnedFoods ?? []) {
        if (warnFoods.includes(food as never))
            allChecks.push(`unexpected warning for: ${food}`);
    }

    const ok = allChecks.length === 0;
    const calLine = `cal:[${fmt(r.calories.min)}–${fmt(r.calories.max)}]`;
    const confLine = `conf:${(r.confidence * 100).toFixed(0)}%`;
    const wStr = r.warnings.map(w => `${w.kind}(${w.food})`).join(" ");

    if (ok) {
        console.log(`  ✓  [${label}]  ${calLine}  ${confLine}  items:${r.itemCount}${wStr ? "  ⚠ " + wStr : ""}`);
        passed++;
    } else {
        console.log(`  ✗  [${label}]  ${calLine}  ${confLine}  items:${r.itemCount}`);
        console.log(`       input: "${input}"`);
        for (const e of allChecks) console.log(`       ✗ ${e}`);
        console.log(`       warnings: ${JSON.stringify(r.warnings)}`);
        failed++;
    }
}

// ─── Original 10 (regression) ─────────────────────────────────────────────────

console.log("\n── Regression (original 10) ─────────────────────");

run("01 – standard meal", "2 roti and dal",
    { lacksKind: ["underreport_adjusted", "reduced"], itemCount: 2 });

run("02 – empty", "", { isEmpty: true });

run("03 – thoda paneer and roti", "thoda paneer and roti",
    { hasKind: ["reduced"], warnedFoods: ["paneer"], unwarnedFoods: ["roti"] });

run("04 – 10 paneer capped", "10 paneer",
    { hasKind: ["capped"], warnedFoods: ["paneer"] });

run("05 – dal sabzi underreport", "dal sabzi",
    { hasKind: ["underreport_adjusted"], warnedFoods: ["dal", "sabzi"] });

run("06 – large messy meal", "2 roti dal rice thoda paneer",
    { itemCount: 4 });

run("07 – no food words", "some random text xyz", { isEmpty: true });

run("08 – repeated paneer merged", "paneer paneer 2 paneer",
    { itemCount: 1 });

run("09 – carb present no underreport", "I ate dal and 2 chapati with sabzi",
    { lacksKind: ["underreport_adjusted"] });

run("10 – half rice paneer", "half rice with paneer",
    { lacksKind: ["underreport_adjusted"] });

// ─── New 10 (smart correction behaviour) ──────────────────────────────────────

console.log("\n── Smart corrections (new 10) ───────────────────");

run("11 – thoda targets nearest food only", "thoda paneer and 2 roti",
    {
        hasKind: ["reduced"],
        warnedFoods: ["paneer"],
        unwarnedFoods: ["roti"],
        itemCount: 2,
    });

run("12 – little sabzi, paneer untouched", "paneer with little sabzi",
    {
        hasKind: ["reduced"],
        warnedFoods: ["sabzi"],
        unwarnedFoods: ["paneer"],
        lacksKind: ["underreport_adjusted"],
    });

run("13 – side-dish only underreport", "dal sabzi only",
    {
        hasKind: ["underreport_adjusted"],
        warnedFoods: ["dal", "sabzi"],
        itemCount: 2,
    });

run("14 – roti paneer sabzi no correction", "2 roti paneer sabzi",
    {
        lacksKind: ["underreport_adjusted", "reduced", "priority_reduced"],
        itemCount: 3,
    });

run("15 – 4 items priority reduction on low-priority", "paneer sabzi dal rice",
    {
        hasKind: ["priority_reduced"],
        warnedFoods: ["sabzi", "dal"],
        itemCount: 4,
    });

run("16 – thoda both dal sabzi anti-stack", "thoda dal and thoda sabzi",
    {
        lacksKind: ["reduced"],   // underreport fires first; thoda skipped for same foods
        hasKind: ["underreport_adjusted"],
    });

run("17 – 15 roti capped", "15 roti",
    { hasKind: ["capped"], warnedFoods: ["roti"], itemCount: 1 });

run("18 – double paneer no extreme correction", "double paneer",
    { lacksKind: ["capped"], itemCount: 1 });

run("19 – little rice reduction", "I ate little rice",
    {
        hasKind: ["reduced"],
        warnedFoods: ["rice"],
        lacksKind: ["underreport_adjusted"],
    });

run("20 – single sabzi underreport", "sabzi",
    {
        hasKind: ["underreport_adjusted"],
        warnedFoods: ["sabzi"],
        itemCount: 1,
    });

// ─── Summary ──────────────────────────────────────────────────────────────────

console.log(`\n${"─".repeat(58)}`);
console.log(`  ${passed} passed  |  ${failed} failed  |  ${passed + failed} total`);
console.log(`${"─".repeat(58)}\n`);

if (failed > 0) throw new Error(`${failed} test(s) failed`);
