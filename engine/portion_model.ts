import type { Range } from "../types";

type PortionUnit = "S" | "M" | "ladle";

const PORTION_GRAM_RANGES: Record<PortionUnit, Range> = {
  S: { min: 60, max: 90 },
  M: { min: 120, max: 180 },
  ladle: { min: 100, max: 140 },
};

export function getGramRange(unit: PortionUnit, quantity: number): Range {
  const base = PORTION_GRAM_RANGES[unit];
  return {
    min: base.min * quantity,
    max: base.max * quantity,
  };
}

export function scaleRange(range: Range, factor: number): Range {
  return {
    min: range.min * factor,
    max: range.max * factor,
  };
}

export function multiplyRanges(a: Range, b: Range): Range {
  return {
    min: a.min * b.min,
    max: a.max * b.max,
  };
}

export function addRanges(a: Range, b: Range): Range {
  return {
    min: a.min + b.min,
    max: a.max + b.max,
  };
}

export function capRange(range: Range, cap: number): Range {
  return {
    min: Math.min(range.min, cap),
    max: Math.min(range.max, cap),
  };
}

export function clampRange(range: Range, min: number, max: number): Range {
  return {
    min: Math.max(range.min, min),
    max: Math.min(range.max, max),
  };
}
