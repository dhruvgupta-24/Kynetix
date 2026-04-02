import { parseMeal } from "../parser/meal_parser";
import type { MealItem } from "../types";

// ─── Assertion helper ─────────────────────────────────────────────────────────

let passed = 0;
let failed = 0;

function check(
    label: string,
    input: string,
    expect: MealItem[]
): void {
    const got = parseMeal(input);
    const match =
        JSON.stringify(got) === JSON.stringify(expect);

    if (match) {
        console.log(`  ✓  [${label}]`);
        passed++;
    } else {
        console.log(`  ✗  [${label}]`);
        console.log(`       input:    "${input}"`);
        console.log(`       expected: ${JSON.stringify(expect)}`);
        console.log(`       got:      ${JSON.stringify(got)}`);
        failed++;
    }
}

// ─── Original 12 ─────────────────────────────────────────────────────────────

console.log("\n── Original tests ──────────────────────────────");

check("01 – 2 roti and dal",
    "2 roti and dal",
    [
        { type: "roti", quantity: 2, rotiSubtype: "unknown" },
        { type: "dal", quantity: 1, unit: "M" },
    ]
);

check("02 – paneer servings and roti",
    "paneer 2 servings and 3 roti",
    [
        { type: "paneer", quantity: 2, unit: "M" },
        { type: "roti", quantity: 3, rotiSubtype: "unknown" },
    ]
);

check("03 – 1 ladle rice with dal",
    "1 ladle rice with dal",
    [
        { type: "rice", quantity: 1, unit: "ladle" },
        { type: "dal", quantity: 1, unit: "M" },
    ]
);

check("04 – 4 roti comma sabzi",
    "4 roti, sabzi",
    [
        { type: "roti", quantity: 4, rotiSubtype: "unknown" },
        { type: "sabzi", quantity: 1, unit: "M" },
    ]
);

check("05 – paneer and rice",
    "paneer and rice",
    [
        { type: "paneer", quantity: 1, unit: "M" },
        { type: "rice", quantity: 1, unit: "ladle" },
    ]
);

check("06 – dry roti 3",
    "dry roti 3",
    [{ type: "roti", quantity: 3, rotiSubtype: "dry" }]
);

check("07 – ghee roti",
    "ghee roti",
    [{ type: "roti", quantity: 1, rotiSubtype: "normal" }]
);

check("08 – I ate dal and 2 chapati",
    "I ate dal and 2 chapati",
    [
        { type: "dal", quantity: 1, unit: "M" },
        { type: "roti", quantity: 2, rotiSubtype: "unknown" },
    ]
);

check("09 – empty string",
    "",
    []
);

check("10 – no food words",
    "some random text",
    []
);

check("11 – four items comma separated",
    "rice, dal, paneer, roti",
    [
        { type: "rice", quantity: 1, unit: "ladle" },
        { type: "dal", quantity: 1, unit: "M" },
        { type: "paneer", quantity: 1, unit: "M" },
        { type: "roti", quantity: 1, rotiSubtype: "unknown" },
    ]
);

check("12 – two chapati and small paneer",
    "two chapati and a small paneer",
    [
        { type: "roti", quantity: 2, rotiSubtype: "unknown" },
        { type: "paneer", quantity: 1, unit: "S" },
    ]
);

// ─── New 10 ───────────────────────────────────────────────────────────────────

console.log("\n── New tests ────────────────────────────────────");

check("13 – no separators: 2 roti dal rice",
    "2 roti dal rice",
    [
        { type: "roti", quantity: 2, rotiSubtype: "unknown" },
        { type: "dal", quantity: 1, unit: "M" },
        { type: "rice", quantity: 1, unit: "ladle" },
    ]
);

check("14 – no separators: paneer 2 roti sabzi",
    "paneer 2 roti sabzi",
    [
        { type: "paneer", quantity: 1, unit: "M" },
        { type: "roti", quantity: 2, rotiSubtype: "unknown" },
        { type: "sabzi", quantity: 1, unit: "M" },
    ]
);

check("15 – half roti",
    "half roti",
    [{ type: "roti", quantity: 0.5, rotiSubtype: "unknown" }]
);

check("16 – double paneer",
    "double paneer",
    [{ type: "paneer", quantity: 2, unit: "M" }]
);

check("17 – repeated roti merged",
    "1 roti 1 roti more",
    [{ type: "roti", quantity: 2, rotiSubtype: "unknown" }]
);

check("18 – ate paneer and roti",
    "ate paneer and roti",
    [
        { type: "paneer", quantity: 1, unit: "M" },
        { type: "roti", quantity: 1, rotiSubtype: "unknown" },
    ]
);

check("19 – thoda dal sabzi 2 roti",
    "thoda dal sabzi 2 roti",
    [
        { type: "dal", quantity: 1, unit: "M" },
        { type: "sabzi", quantity: 1, unit: "M" },
        { type: "roti", quantity: 2, rotiSubtype: "unknown" },
    ]
);

check("20 – messy 4-item string",
    "2 roti dal rice thoda paneer",
    [
        { type: "roti", quantity: 2, rotiSubtype: "unknown" },
        { type: "dal", quantity: 1, unit: "M" },
        { type: "rice", quantity: 1, unit: "ladle" },
        { type: "paneer", quantity: 1, unit: "M" },
    ]
);

check("21 – hindi synonyms: chawal and daal",
    "had some chawal and daal",
    [
        { type: "rice", quantity: 1, unit: "ladle" },
        { type: "dal", quantity: 1, unit: "M" },
    ]
);

check("22 – twice keyword",
    "twice dal",
    [{ type: "dal", quantity: 2, unit: "M" }]
);

// ─── Summary ──────────────────────────────────────────────────────────────────

console.log(`\n${"─".repeat(50)}`);
console.log(`  ${passed} passed  |  ${failed} failed  |  ${passed + failed} total`);
console.log(`${"─".repeat(50)}\n`);

if (failed > 0) throw new Error(`${failed} test(s) failed`);
