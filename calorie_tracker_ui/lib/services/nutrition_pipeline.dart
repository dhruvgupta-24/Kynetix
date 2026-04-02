import 'package:flutter/foundation.dart';
import '../models/nutrition_result.dart';
import '../services/meal_memory.dart';
import '../services/personal_nutrition_memory.dart';
import '../services/ai_nutrition_service.dart';
import '../services/meal_classifier.dart';
import '../services/nutrition_guardrails.dart';
import '../services/mock_estimation_service.dart'
    show mockProcessMealInput, NutrientRange;

export '../services/mock_estimation_service.dart' show NutrientRange;

// ─── Nutrition Pipeline ───────────────────────────────────────────────────────
//
// Priority order (highest → lowest):
//
//  1. PersonalNutritionMemory.lookupExact()
//     Exact personal food defaults, meal templates, milk interpolation.
//     These are user-specific, validated values. Confidence ~0.97.
//     Skip AI entirely when matched.
//
//  2. PersonalNutritionMemory.lookupTemplate()
//     Keyword-based partial match against personal templates.
//     Only fires when ALL keywords present — conservative by design.
//
//  3. MealMemory.lookupExactKnownFood()
//     App-wide exact known foods (whey, tofu, bread) stored in MealMemory.
//     Kept for backward compatibility with previously saved known foods.
//
//  4. MealMemory.lookupRecurring()
//     Previously AI-estimated meals that were confirmed / cached.
//
//  5. AI estimation (OpenRouter / DeepSeek)
//     Full AI call. Result is guardrail-corrected then cached.
//
//  6. Local fallback
//     Mock engine + guardrails when AI is unavailable.

class NutritionPipeline {
  NutritionPipeline._();
  static final NutritionPipeline instance = NutritionPipeline._();

  Future<NutritionResult> estimateMeal(String rawInput) async {
    final trimmed = rawInput.trim();
    final classification = MealClassifier.instance.classify(trimmed);

    debugPrint('\n══════════════════════════════════════');
    debugPrint('[Pipeline] estimateMeal: "$trimmed"');
    debugPrint('[Pipeline] classification: ${classification.category.name} '
               '(${classification.reason})');

    if (trimmed.isEmpty) return _empty();

    // ── 1. Personal exact match ─────────────────────────────────────────────
    final personalExact = PersonalNutritionMemory.instance.lookupExact(trimmed);
    if (personalExact != null) {
      debugPrint('[Pipeline] ✅ PERSONAL EXACT — '
                 '"${personalExact.canonicalMeal}" '
                 '${personalExact.calories.min.toInt()} kcal / '
                 '${personalExact.protein.min.toStringAsFixed(1)}g protein');
      return personalExact;
    }

    // ── 2. Personal template match ──────────────────────────────────────────
    final personalTemplate =
        PersonalNutritionMemory.instance.lookupTemplate(trimmed);
    if (personalTemplate != null) {
      debugPrint('[Pipeline] ✅ PERSONAL TEMPLATE — '
                 '"${personalTemplate.canonicalMeal}" '
                 '${personalTemplate.calories.min.toInt()} kcal / '
                 '${personalTemplate.protein.min.toStringAsFixed(1)}g protein');
      return personalTemplate;
    }

    // ── 3. App-wide exact known foods ───────────────────────────────────────
    final exactKnown = MealMemory.instance.lookupExactKnownFood(trimmed);
    if (exactKnown != null) {
      debugPrint('[Pipeline] ✅ EXACT KNOWN FOOD — '
                 '${exactKnown.calories.min.toInt()} kcal');
      return exactKnown;
    }

    // ── 4. Recurring AI-confirmed memory ────────────────────────────────────
    final cached = MealMemory.instance.lookupRecurring(trimmed);
    if (cached != null) {
      debugPrint('[Pipeline] ✅ RECURRING MEMORY — '
                 '${cached.calories.min.toInt()}–${cached.calories.max.toInt()} kcal');
      return cached;
    }

    debugPrint('[Pipeline] all memory missed → calling AI');

    // ── 5. AI estimation ────────────────────────────────────────────────────
    if (AiNutritionService.instance.isConfigured) {
      debugPrint('[Pipeline] 🚀 calling AI (${AiNutritionService.modelName})...');
      try {
        final raw    = await AiNutritionService.instance.estimate(trimmed);
        final result = NutritionGuardrails.apply(
                raw, trimmed, classification: classification)
            .normalizedUncertainty();
        debugPrint('[Pipeline] ✅ AI result: "${result.canonicalMeal}" | '
                   '${result.calories.min.toInt()}–${result.calories.max.toInt()} kcal | '
                   'conf=${result.confidence}');
        await MealMemory.instance.store(trimmed, result);
        return result;
      } catch (e) {
        debugPrint('[Pipeline] ❌ AI failed: $e');
        return _localFallback(trimmed, e.toString());
      }
    }

    // ── 6. Local fallback ───────────────────────────────────────────────────
    return _localFallback(trimmed, 'OPENROUTER_API_KEY not configured');
  }

  NutritionResult _localFallback(String rawInput, String reason) {
    debugPrint('[Pipeline] 📦 LOCAL FALLBACK — reason: $reason');
    final classification = MealClassifier.instance.classify(rawInput);
    final local = mockProcessMealInput(rawInput);
    final base  = NutritionResult.fromEstimationResult(local, rawInput)
        .copyWith(source: 'local_fallback', fallbackReason: reason);
    return NutritionGuardrails.apply(base, rawInput,
            classification: classification)
        .normalizedUncertainty();
  }

  NutritionResult _empty() => NutritionResult(
        canonicalMeal:  '',
        items:          const [],
        calories:       const NutrientRange(min: 0, max: 0),
        protein:        const NutrientRange(min: 0, max: 0),
        confidence:     0,
        warnings:       const ['No input provided.'],
        source:         'local_fallback',
        fallbackReason: 'Empty input',
        createdAt:      DateTime.now(),
      );
}
