import type { MealItem, EstimationResult } from "../types";
import {
    estimatePaneer,
    estimateDal,
    estimateSabzi,
    estimateRice,
    estimateRoti,
} from "./food_model";
import {
    detectMealContext,
    getConsumptionRate,
    applyConsumptionRate,
} from "./behavior_model";
import {
    applyIntelligenceLayer,
    type RawItemEstimate,
} from "./intelligence_layer";

const ITEM_CONFIDENCE: Record<MealItem["type"], number> = {
    paneer: 0.9,
    roti: 0.85,
    rice: 0.75,
    dal: 0.7,
    sabzi: 0.5,
};

function computeWeightedConfidence(estimates: RawItemEstimate[]): number {
    const totalCalMidpoint = estimates.reduce(
        (sum, e) => sum + (e.calories.min + e.calories.max) / 2,
        0
    );

    if (totalCalMidpoint === 0) return 0;

    const weightedSum = estimates.reduce((sum, e) => {
        const calMidpoint = (e.calories.min + e.calories.max) / 2;
        const weight = calMidpoint / totalCalMidpoint;
        return sum + e.confidence * weight;
    }, 0);

    return Math.min(1, Math.max(0, weightedSum));
}

function adjustConfidence(base: number, count: number): number {
    let adjusted = base;

    if (count >= 3) adjusted *= 0.7;
    else if (count === 2) adjusted *= 0.8;
    else adjusted *= 0.9;

    return Math.max(0.4, adjusted); // prevent unrealistic low
}

function estimateItem(
    item: MealItem,
    mealContext: ReturnType<typeof detectMealContext>
): RawItemEstimate {
    let rawNutrition = (() => {
        switch (item.type) {
            case "paneer":
                return estimatePaneer(item);
            case "dal":
                return estimateDal(item);
            case "sabzi":
                return estimateSabzi(item);
            case "rice":
                return estimateRice(item);
            case "roti":
                return estimateRoti(item);
        }
    })();

    const consumptionRate = getConsumptionRate(item.type, mealContext);

    return {
        type: item.type,
        calories: applyConsumptionRate(rawNutrition.calories, consumptionRate),
        protein: applyConsumptionRate(rawNutrition.protein, consumptionRate),
        confidence: ITEM_CONFIDENCE[item.type],
    };
}

export function estimateMeal(items: MealItem[]): EstimationResult {
    if (items.length === 0) {
        return {
            calories: { min: 0, max: 0 },
            protein: { min: 0, max: 0 },
            confidence: 0,
        };
    }

    const mealContext = detectMealContext(items);

    const rawEstimates: RawItemEstimate[] = items.map((item) =>
        estimateItem(item, mealContext)
    );

    const { calories, protein } = applyIntelligenceLayer(rawEstimates);
    const baseConfidence = computeWeightedConfidence(rawEstimates);
    const confidence = adjustConfidence(baseConfidence, items.length);

    return { calories, protein, confidence };
}

