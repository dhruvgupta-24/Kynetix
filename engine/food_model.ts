import type { MealItem, Range } from "../types";
import { scaleRange, multiplyRanges } from "./portion_model";

interface NutrientProfile {
  calories: Range;
  protein: Range;
}

type FoodKey = "paneer" | "dal" | "sabzi";
type RotiType = "dry" | "normal" | "unknown";

const FOOD_BASE: Record<FoodKey, NutrientProfile> = {
  paneer: { calories: { min: 250, max: 320 }, protein: { min: 18, max: 22 } },
  dal: { calories: { min: 80, max: 130 }, protein: { min: 5, max: 9 } },
  sabzi: { calories: { min: 70, max: 150 }, protein: { min: 2, max: 5 } },
};

const ROTI_CALORIES: Record<RotiType, Range> = {
  dry: { min: 90, max: 110 },
  normal: { min: 120, max: 170 },
  unknown: { min: 100, max: 150 },
};

const ROTI_PROTEIN: Range = { min: 3, max: 4 };

const RICE_PER_LADLE: NutrientProfile = {
  calories: { min: 100, max: 140 },
  protein: { min: 2, max: 3 },
};

const DAL_DILUTION: Range = { min: 0.7, max: 0.85 };
const SABZI_OIL_MULTIPLIER: Range = { min: 1.0, max: 1.3 };

// -------------------- HELPERS --------------------

function per100gToAbsolute(
  profile: NutrientProfile,
  gramRange: Range
): NutrientProfile {
  return {
    calories: {
      min: (profile.calories.min * gramRange.min) / 100,
      max: (profile.calories.max * gramRange.max) / 100,
    },
    protein: {
      min: (profile.protein.min * gramRange.min) / 100,
      max: (profile.protein.max * gramRange.max) / 100,
    },
  };
}

// -------------------- ESTIMATORS --------------------

export function estimatePaneer(item: MealItem): NutrientProfile {
  const unit = item.unit ?? "M";

  let gramRange: Range;

  if (unit === "S") {
    gramRange = { min: 40, max: 70 };
  } else {
    gramRange = { min: 80, max: 120 };
  }

  gramRange = {
    min: gramRange.min * item.quantity,
    max: gramRange.max * item.quantity,
  };

  return per100gToAbsolute(FOOD_BASE.paneer, gramRange);
}

export function estimateDal(item: MealItem): NutrientProfile {
  const unit = item.unit ?? "M";

  const gramRange: Range =
    unit === "ladle"
      ? { min: 100 * item.quantity, max: 140 * item.quantity }
      : unit === "S"
      ? { min: 60 * item.quantity, max: 90 * item.quantity }
      : { min: 120 * item.quantity, max: 180 * item.quantity };

  const raw = per100gToAbsolute(FOOD_BASE.dal, gramRange);

  return {
    calories: multiplyRanges(raw.calories, DAL_DILUTION),
    protein: multiplyRanges(raw.protein, DAL_DILUTION),
  };
}

export function estimateSabzi(item: MealItem): NutrientProfile {
  const unit = item.unit ?? "M";

  const gramRange: Range =
    unit === "S"
      ? { min: 60 * item.quantity, max: 90 * item.quantity }
      : { min: 120 * item.quantity, max: 180 * item.quantity };

  const raw = per100gToAbsolute(FOOD_BASE.sabzi, gramRange);

  return {
    calories: multiplyRanges(raw.calories, SABZI_OIL_MULTIPLIER),
    protein: raw.protein,
  };
}

export function estimateRice(item: MealItem): NutrientProfile {
  return {
    calories: scaleRange(RICE_PER_LADLE.calories, item.quantity),
    protein: scaleRange(RICE_PER_LADLE.protein, item.quantity),
  };
}

export function estimateRoti(item: MealItem): NutrientProfile {
  const subtype: RotiType = item.rotiSubtype ?? "unknown";

  return {
    calories: scaleRange(ROTI_CALORIES[subtype], item.quantity),
    protein: scaleRange(ROTI_PROTEIN, item.quantity),
  };
}