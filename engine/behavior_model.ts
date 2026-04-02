import type { MealItem, Range } from "../types";

type MealContext = "rice_dominant" | "roti_dominant" | "mixed";

interface ConsumptionBands {
    paneer: Range;
    dal: Range;
    sabzi: Range;
}

const BASE_CONSUMPTION: ConsumptionBands = {
    paneer: { min: 0.95, max: 1.0 },
    dal: { min: 0.5, max: 0.7 },
    sabzi: { min: 0.3, max: 0.5 },
};

const SABZI_WITH_RICE: Range = { min: 0.5, max: 0.7 };
const SABZI_WITH_ROTI_ONLY: Range = { min: 0.3, max: 0.5 };
const DAL_SABZI_MAX_CAP = 0.6;

export function detectMealContext(items: MealItem[]): MealContext {
    const types = items.map((i) => i.type);
    const hasRice = types.includes("rice");
    const hasRoti = types.includes("roti");

    if (hasRice && hasRoti) return "mixed";
    if (hasRice) return "rice_dominant";
    return "roti_dominant";
}

export function getConsumptionRate(
    type: MealItem["type"],
    context: MealContext
): Range {
    switch (type) {
        case "paneer":
            return BASE_CONSUMPTION.paneer;

        case "dal": {
            const rate = { ...BASE_CONSUMPTION.dal };
            return {
                min: rate.min,
                max: Math.min(rate.max, DAL_SABZI_MAX_CAP),
            };
        }

        case "sabzi": {
            const raw =
                context === "roti_dominant" ? SABZI_WITH_ROTI_ONLY : SABZI_WITH_RICE;
            return {
                min: raw.min,
                max: Math.min(raw.max, DAL_SABZI_MAX_CAP),
            };
        }

        case "rice":
        case "roti":
            return { min: 1.0, max: 1.0 };
    }
}

export function applyConsumptionRate(
    nutrientRange: Range,
    consumptionRate: Range
): Range {
    return {
        min: nutrientRange.min * consumptionRate.min,
        max: nutrientRange.max * consumptionRate.max,
    };
}
