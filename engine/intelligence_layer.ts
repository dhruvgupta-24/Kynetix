import type { MealItem, Range, EstimationResult } from "../types";

interface RawItemEstimate {
  type: MealItem["type"];
  calories: Range;
  protein: Range;
  confidence: number;
}

// -------- AI HOOK (future) --------

export interface AIFallbackProvider {
  canHandle(items: MealItem[]): boolean;
  estimate(items: MealItem[]): Promise<EstimationResult>;
}

const providers: AIFallbackProvider[] = [];

export function registerAIFallback(provider: AIFallbackProvider) {
  providers.push(provider);
}

// -------- LOGIC --------

const HIGH_CAL_THRESHOLD = 300;
const REDUCTION_FACTOR = 0.92;
const MAX_SPREAD_RATIO = 0.7;
const PROTEIN_FLOOR = 0.6;

// Clamp wide ranges
function clamp(range: Range): Range {
  const spread = range.max - range.min;

  if (spread > range.min * MAX_SPREAD_RATIO) {
    return {
      min: range.min,
      max: range.min + range.min * 0.6,
    };
  }

  return range;
}

// Prevent unrealistic low protein
function fixProtein(range: Range): Range {
  return {
    min: Math.max(range.min, range.max * PROTEIN_FLOOR),
    max: range.max,
  };
}

function normalizeCalories(range: Range): Range {
  const maxRatio = range.max / range.min;

  // tighter control
  if (maxRatio > 1.3) {
    return {
      min: range.min,
      max: range.min * 1.25
    };
  }

  return range;
}

// Reduce heavy meals
function reduce(range: Range): Range {
  return {
    min: range.min,
    max: range.max * REDUCTION_FACTOR,
  };
}

function aggregate(ranges: Range[]): Range {
  return {
    min: ranges.reduce((s, r) => s + r.min, 0),
    max: ranges.reduce((s, r) => s + r.max, 0),
  };
}

export function applyIntelligenceLayer(
  items: RawItemEstimate[]
): { calories: Range; protein: Range } {

  const highCalCount = items.filter(i => i.calories.max > HIGH_CAL_THRESHOLD).length;

  const adjusted = items.map(i => {
    let cal = i.calories;
    let protein = i.protein;

    if (highCalCount >= 2) {
      cal = {
        min: cal.min,
        max: cal.max * 0.88
      };
    }

    return {
      ...i,
      calories: clamp(cal),
      protein: clamp(protein),
    };
  });

  const totalCalories = clamp(aggregate(adjusted.map(i => i.calories)));
  const totalProtein = fixProtein(clamp(aggregate(adjusted.map(i => i.protein))));

  return {
    calories: normalizeCalories(totalCalories),
    protein: totalProtein,
  };
}

export type { RawItemEstimate };