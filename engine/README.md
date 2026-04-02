# /engine — Experimental TypeScript Prototype (ARCHIVED)

## Status: NOT PRODUCTION CODE — Experimental only

This folder contains an early-stage TypeScript prototype of an Indian food
estimation engine. It was built as a proof-of-concept to explore how meal
context (mess vs restaurant, dal-with-roti vs standalone dal, paneer
consumption patterns) could be modelled in a deterministic way.

---

## Why it exists

During early architecture design we explored whether a TypeScript-first engine
could be published as a lightweight backend microservice (e.g. Deno/Node
serverless function) to serve the Flutter app with low latency, independent of
OpenRouter availability.

---

## Current status

**This code is NOT wired to the Flutter app and is NOT called from anywhere.**

All live nutrition estimation in the app is handled by:

```
calorie_tracker_ui/lib/services/nutrition_pipeline.dart
```

Which routes through:
1. `MealMemory` (exact known foods + recurring cache)
2. `AiNutritionService` (OpenRouter → `NutritionGuardrails`)
3. `mockProcessMealInput` (local fallback)

---

## What to do with this

- **Do NOT extend this as parallel logic.** Any estimation improvements
  should go into the Flutter pipeline (guardrails, prompt tuning, memory).

- **May be revisited** if a backend microservice layer is ever added.
  In that case this should be migrated to a proper package with shared
  types and tests.

- **If this folder is confusing you**, ignore it entirely. It has zero
  effect on the running app.

---

## Files

| File | Purpose |
|---|---|
| `estimation_engine.ts` | Main estimator — calls food_model + intelligence_layer |
| `food_model.ts` | Per-food calorie/protein heuristics (paneer, roti, rice, dal, sabzi) |
| `behavior_model.ts` | Consumption rate model (sabzi eaten partially, paneer fully, etc.) |
| `intelligence_layer.ts` | Post-estimation aggregation and calorie-density adjustment |
| `portion_model.ts` | Unit-to-gram mappings |

---

_Last reviewed: April 2026 — no changes needed; archive in place._
