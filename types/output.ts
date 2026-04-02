export type Range = {
  min: number;
  max: number;
};

export type EstimationResult = {
  calories: Range;
  protein: Range;
  confidence: number;
};