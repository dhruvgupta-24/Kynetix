import 'package:flutter/foundation.dart';
import '../models/nutrition_result.dart';
import '../services/meal_memory.dart';
import '../services/personal_nutrition_memory.dart';
import '../services/ai_nutrition_service.dart';
import '../services/meal_classifier.dart';
import '../services/nutrition_guardrails.dart';
import '../services/mock_estimation_service.dart'
  show
    analyzeLocalEstimation,
    LocalEstimationAnalysis,
    NutrientRange;

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

  static const _minOverallLocalConfidence = 0.93;
  static const _minCoverageConfidence = 0.90;
  static const _minMatchConfidence = 0.88;

  Future<NutritionResult> estimateMeal(String rawInput) async {
    final trimmed = rawInput.trim();
    final classification = MealClassifier.instance.classify(trimmed);

    debugPrint('\n══════════════════════════════════════');
    debugPrint('[Pipeline] estimateMeal: "$trimmed"');
    debugPrint('[Pipeline] classification: ${classification.category.name} '
               '(${classification.reason})');

    if (trimmed.isEmpty) return _empty();

    final localAnalysis = analyzeLocalEstimation(trimmed);
    final complexity = _assessComplexity(trimmed, localAnalysis);
    final localGate = _buildGate(localAnalysis, complexity);

    debugPrint('[Pipeline] local gate: '
           'match=${localGate.matchConfidence.toStringAsFixed(3)} '
           'coverage=${localGate.coverageConfidence.toStringAsFixed(3)} '
           'overall=${localGate.overallConfidence.toStringAsFixed(3)} '
           'complexity=${complexity.score} flags=${complexity.flags.join(', ')}');

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

    if (localGate.shouldFinalizeLocal) {
      debugPrint('[Pipeline] ✅ LOCAL FINALIZED via confidence gate');
      return _finalizeLocal(
        trimmed,
        localAnalysis,
        classification: classification,
        fallbackReason: 'Hybrid local confidence gate passed',
      );
    }

    debugPrint('[Pipeline] local gate failed → escalating to AI verifier/refiner');

    // ── 5. AI verification / refinement ─────────────────────────────────────
    if (AiNutritionService.instance.isConfigured) {
      debugPrint('[Pipeline] 🚀 calling AI (${AiNutritionService.modelName})...');
      try {
        final raw = await AiNutritionService.instance.estimateWithContext(
          trimmed,
          context: AiEscalationContext(
            localInterpretation: _localInterpretation(localAnalysis),
            localMatchConfidence: localGate.matchConfidence,
            localCoverageConfidence: localGate.coverageConfidence,
            overallLocalConfidence: localGate.overallConfidence,
            flags: complexity.flags,
          ),
        );
        final result = NutritionGuardrails.apply(
          raw,
          trimmed,
          classification: classification,
        ).normalizedUncertainty();
        debugPrint('[Pipeline] ✅ AI result: "${result.canonicalMeal}" | '
                   '${result.calories.min.toInt()}–${result.calories.max.toInt()} kcal | '
                   'conf=${result.confidence}');
        await MealMemory.instance.storeAiCandidate(trimmed, result);
        return result;
      } catch (e) {
        debugPrint('[Pipeline] ❌ AI failed: $e');
        return _finalizeLocal(
          trimmed,
          localAnalysis,
          classification: classification,
          fallbackReason: 'AI escalation required; AI failed: $e',
        );
      }
    }

    // ── 6. Local fallback ───────────────────────────────────────────────────
    return _finalizeLocal(
      trimmed,
      localAnalysis,
      classification: classification,
      fallbackReason: 'AI escalation required but OPENROUTER_API_KEY not configured',
    );
  }

  NutritionResult _finalizeLocal(
    String rawInput,
    LocalEstimationAnalysis analysis, {
    required MealClassification classification,
    required String fallbackReason,
  }) {
    debugPrint('[Pipeline] 📦 LOCAL RESULT — reason: $fallbackReason');
    final base = NutritionResult.fromEstimationResult(analysis.estimation, rawInput)
        .copyWith(source: 'local_hybrid', fallbackReason: fallbackReason);
    return NutritionGuardrails.apply(base, rawInput,
            classification: classification)
        .normalizedUncertainty();
  }

  _LocalGate _buildGate(
    LocalEstimationAnalysis analysis,
    _ComplexityAssessment complexity,
  ) {
    final rawMatch = analysis.estimation.confidence.clamp(0.0, 1.0);
    final match = ((0.58 + rawMatch * 0.42) +
            (analysis.estimation.items.isNotEmpty ? 0.02 : 0.0))
        .clamp(0.0, 1.0);
    final coverage = analysis.coverageConfidence;
    final complexityPenalty = (complexity.score * 0.03).clamp(0.0, 0.18);

    final overall =
        (match * 0.58) + (coverage * 0.42) - complexityPenalty;

    final lowCoverage = coverage < _minCoverageConfidence;
    final lowMatch = match < _minMatchConfidence;
    final lowOverall = overall < _minOverallLocalConfidence;
    final noItems = analysis.estimation.items.isEmpty;
    final collapseRisk = complexity.multiItem && analysis.estimation.items.length <= 1;

    return _LocalGate(
      matchConfidence: match,
      coverageConfidence: coverage,
      overallConfidence: overall.clamp(0.0, 1.0),
      shouldFinalizeLocal:
          !(lowCoverage || lowMatch || lowOverall || noItems || complexity.forceAi || collapseRisk),
    );
  }

  _ComplexityAssessment _assessComplexity(
    String rawInput,
    LocalEstimationAnalysis analysis,
  ) {
    final lc = rawInput.toLowerCase();
    final flags = <String>[];
    int score = 0;

    final halfAndHalf = RegExp(r'half\s+[^,]+\s+and\s+half\s+').hasMatch(lc);
    if (halfAndHalf) {
      flags.add('half_and_half_structure');
      score += 3;
    }

    final separators = RegExp(r'\b(and|with|plus)\b|[,+/&]').allMatches(lc).length;
    if (separators >= 2) {
      flags.add('multi_item_meal');
      score += 2;
    }

    final hasComboWord = RegExp(
      r'\b(combo|meal|platter|thali|burger|fries|sandwich|roll|wrap)\b',
    ).hasMatch(lc);
    if (hasComboWord) {
      flags.add('composite_or_combo_food');
      score += 2;
    }

    final hasRestaurant = RegExp(
      r'\b(outside|restaurant|hotel|dhaba|zomato|swiggy|kfc|mcd)\b',
    ).hasMatch(lc);
    if (hasRestaurant) {
      flags.add('restaurant_context');
      score += 2;
    }

    final hasBeverage = RegExp(
      r'\b(coke|cola|pepsi|sprite|fanta|drink|soda|juice|shake|tea|coffee)\b',
    ).hasMatch(lc);
    if (hasBeverage) {
      flags.add('beverage_present');
      score += 1;
    }

    final quantityAmbiguity = RegExp(
      r'\b(some|little|thoda|thodi|approx|around|about|few)\b',
    ).hasMatch(lc);
    if (quantityAmbiguity) {
      flags.add('quantity_ambiguity');
      score += 1;
    }

    if (analysis.coverageConfidence < 0.75 && analysis.meaningfulTokenCount >= 3) {
      flags.add('poor_local_coverage');
      score += 2;
    }

    return _ComplexityAssessment(
      flags: flags,
      score: score,
      multiItem: separators >= 1 || analysis.estimation.items.length >= 2,
      forceAi: halfAndHalf || hasComboWord || hasRestaurant || analysis.coverageConfidence < 0.6,
    );
  }

  String _localInterpretation(LocalEstimationAnalysis analysis) {
    if (analysis.estimation.items.isEmpty) return 'No local items recognized.';

    final items = analysis.estimation.items
        .map((i) => '${i.name}: '
            '${i.calories.min.toStringAsFixed(0)}-${i.calories.max.toStringAsFixed(0)} kcal, '
            '${i.protein.min.toStringAsFixed(1)}-${i.protein.max.toStringAsFixed(1)} g')
        .join(' | ');

    return 'items=[$items]; '
        'total=${analysis.estimation.calories.min.toStringAsFixed(0)}-'
        '${analysis.estimation.calories.max.toStringAsFixed(0)} kcal; '
        'local_conf=${analysis.estimation.confidence.toStringAsFixed(3)}; '
        'local_coverage=${analysis.coverageConfidence.toStringAsFixed(3)}; '
        'matched_keywords=${analysis.matchedKeywords.join(', ')}';
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

class _ComplexityAssessment {
  final List<String> flags;
  final int score;
  final bool multiItem;
  final bool forceAi;

  const _ComplexityAssessment({
    required this.flags,
    required this.score,
    required this.multiItem,
    required this.forceAi,
  });
}

class _LocalGate {
  final double matchConfidence;
  final double coverageConfidence;
  final double overallConfidence;
  final bool shouldFinalizeLocal;

  const _LocalGate({
    required this.matchConfidence,
    required this.coverageConfidence,
    required this.overallConfidence,
    required this.shouldFinalizeLocal,
  });
}
