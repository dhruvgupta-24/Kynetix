import { estimateMeal } from "../engine/estimation_engine";
import { MealItem } from "../types/meal";

const testMeal: MealItem[] = [
  { type: "roti", quantity: 2, rotiSubtype: "normal" },
  { type: "dal", quantity: 1, unit: "M" },
  { type: "paneer", quantity: 1, unit: "M" }
];

const result = estimateMeal(testMeal);

console.log(JSON.stringify(result, null, 2));