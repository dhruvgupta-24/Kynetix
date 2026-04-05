import 'package:flutter/foundation.dart';
import '../models/nutrition_result.dart';
import '../services/meal_memory.dart';
import '../services/personal_nutrition_memory.dart';
import '../services/user_nutrition_memory.dart';
import '../services/ai_nutrition_service.dart';
import '../services/meal_classifier.dart';
import '../services/nutrition_guardrails.dart';
import '../services/mock_estimation_service.dart'
  show
    analyzeLocalEstimation,
    LocalEstimationAnalysis,
    NutrientRange;
import '../services/item_parser.dart';
import '../services/unit_normalizer.dart';

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

    // ── 1. SPLIT & PARSE INTO ATOMIC ITEMS ─────────────────────────────────
    final parsedItems = ItemParser.parse(trimmed);
    debugPrint('[Pipeline] Extracted ${parsedItems.length} items:');
    for (final p in parsedItems) {
      debugPrint('  -> ${p.normalizedName} (qty: ${p.quantity}, unit: ${p.unit})');
    }

    final finalItems = <NutritionItem>[];
    double sumCalMin = 0, sumCalMax = 0;
    double sumProMin = 0, sumProMax = 0;
    final allWarnings = <String>[];
    bool aiUsed = false;
    bool localHybridUsed = false;
    
    final needsEstimation = <ParsedFoodItem>[];

    // ── 2. ITEM-LEVEL MEMORY LOOKUP ─────────────────────────────────────────
    for (final parsed in parsedItems) {
      // Normalize quantity and unit to base units (g, ml, or count).
      // This ensures 0.15 kg == 150 g when matching saved memories.
      final normParsed = _normalizeParsed(parsed);
      final name = normParsed.normalizedName;
      
      // ── USER OVERRIDE (highest priority — hard blocks AI) ─────────────────
      final userOverride = UserNutritionMemory.instance.lookup(name);
      if (userOverride != null) {
        // Unit-category guard: reject matches across incompatible unit types.
        // e.g. memory stored in 'g' must not be used for 'ml' input.
        final storedUnit = UserNutritionMemory.instance.storedUnit(name);
        if (storedUnit != null &&
            UnitNormalizer.isMetric(storedUnit) &&
            UnitNormalizer.isMetric(normParsed.unit) &&
            !UnitNormalizer.sameCategory(storedUnit, normParsed.unit)) {
          debugPrint('[Pipeline] ⚠️  unit mismatch: stored=$storedUnit input=${normParsed.unit} for "$name" — skipping memory');
          needsEstimation.add(normParsed);
          continue;
        }
        debugPrint('[Pipeline] ✅ USER OVERRIDE for "$name" (qty=${normParsed.quantity} ${normParsed.unit}) — AI BLOCKED');
        finalItems.add(_itemFromMemory(normParsed, userOverride, 'user_override'));
        continue;
      }

      final personalExact = PersonalNutritionMemory.instance.lookupExact(name);
      if (personalExact != null) {
        debugPrint('[Pipeline] ✅ PERSONAL EXACT for "$name"');
        finalItems.add(_itemFromMemory(normParsed, personalExact, 'personal_exact'));
        continue;
      }

      final personalTemplate = PersonalNutritionMemory.instance.lookupTemplate(name);
      if (personalTemplate != null) {
        debugPrint('[Pipeline] ✅ PERSONAL TEMPLATE for "$name"');
        finalItems.add(_itemFromMemory(normParsed, personalTemplate, 'personal_template'));
        continue;
      }

      final exactKnown = MealMemory.instance.lookupExactKnownFood(name);
      if (exactKnown != null) {
        debugPrint('[Pipeline] ✅ EXACT KNOWN for "$name"');
        finalItems.add(_itemFromMemory(normParsed, exactKnown, 'exact_known'));
        continue;
      }

      final cached = MealMemory.instance.lookupRecurring(name);
      if (cached != null) {
        debugPrint('[Pipeline] ✅ RECURRING MEMORY for "$name"');
        finalItems.add(_itemFromMemory(normParsed, cached, 'recurring'));
        continue;
      }

      // No memory match — needs AI or local estimation.
      needsEstimation.add(normParsed);
    }

    // ── 3. AI / MOCK ESTIMATION PER ATOMIC ITEM ──────────────────────────────
    for (final parsed in needsEstimation) {
      // Re-stitch item specific string for the estimator engine. 
      // It relies on qty + unit + name context. e.g "1 scoop whey"
      final itemStr = _constructItemString(parsed);
      debugPrint('[Pipeline] Estimating unknown atomic item: "$itemStr"');

      final localAnalysis = analyzeLocalEstimation(itemStr);
      final complexity = _assessComplexity(itemStr, localAnalysis);
      final localGate = _buildGate(localAnalysis, complexity);

      if (localGate.shouldFinalizeLocal) {
        debugPrint('[Pipeline] ✅ LOCAL FINALIZED for "$itemStr"');
        final localResult = _finalizeLocal(itemStr, localAnalysis, classification: classification, fallbackReason: 'Local passed');
        final item = _pullBestItem(localResult, parsed);
        finalItems.add(item);
        localHybridUsed = true;
      } else {
        if (AiNutritionService.instance.isConfigured) {
          debugPrint('[Pipeline] 🚀 calling AI for item: "$itemStr"...');
          try {
            final raw = await AiNutritionService.instance.estimateWithContext(
              itemStr,
              context: AiEscalationContext(
                localInterpretation: _localInterpretation(localAnalysis),
                localMatchConfidence: localGate.matchConfidence,
                localCoverageConfidence: localGate.coverageConfidence,
                overallLocalConfidence: localGate.overallConfidence,
                flags: complexity.flags,
              ),
            );
            final aiResult = NutritionGuardrails.apply(raw, itemStr, classification: classification).normalizedUncertainty();
            final item = _pullBestItem(aiResult, parsed);
            finalItems.add(item);
            aiUsed = true;
          } catch (e) {
            debugPrint('[Pipeline] ❌ AI failed for item "$itemStr": $e');
            final localResult = _finalizeLocal(itemStr, localAnalysis, classification: classification, fallbackReason: 'AI failed for item');
            final item = _pullBestItem(localResult, parsed);
            finalItems.add(item);
            localHybridUsed = true;
          }
        } else {
          final localResult = _finalizeLocal(itemStr, localAnalysis, classification: classification, fallbackReason: 'No AI key');
          final item = _pullBestItem(localResult, parsed);
          finalItems.add(item);
          localHybridUsed = true;
        }
      }
    }

    // ── 4. AGGREGATION ───────────────────────────────────────────────────────
    for (final item in finalItems) {
      sumCalMin += item.calories.min;
      sumCalMax += item.calories.max;
      sumProMin += item.protein.min;
      sumProMax += item.protein.max;
    }

    String source = 'user_override';
    if (aiUsed) source = 'ai';
    else if (localHybridUsed) source = 'local_hybrid';

    return NutritionResult(
      canonicalMeal: trimmed,
      items: finalItems,
      calories: NutrientRange(min: sumCalMin, max: sumCalMax),
      protein: NutrientRange(min: sumProMin, max: sumProMax),
      confidence: aiUsed ? 0.95 : 0.90, // simplify for aggregate
      warnings: allWarnings,
      source: source,
      createdAt: DateTime.now(),
    );
  }

  // ── Normalization helper ───────────────────────────────────────────────────

  /// Returns a copy of [parsed] with quantity and unit normalized to base
  /// SI units (g or ml).  Non-metric units (scoop, serving, etc.) pass through
  /// unchanged.  The normalizedName is also cleaned through FoodNameNormalizer.
  ParsedFoodItem _normalizeParsed(ParsedFoodItem parsed) {
    final normQty  = UnitNormalizer.normalizeQuantity(parsed.quantity, parsed.unit);
    final normUnit = UnitNormalizer.normalizeUnit(parsed.unit);
    final normName = FoodNameNormalizer.normalize(parsed.normalizedName);
    if (normQty == parsed.quantity && normUnit == parsed.unit && normName == parsed.normalizedName) {
      return parsed; // already canonical — avoid allocation
    }
    return ParsedFoodItem(
      rawChunk:       parsed.rawChunk,
      normalizedName: normName,
      quantity:       normQty,
      unit:           normUnit,
    );
  }

  String _constructItemString(ParsedFoodItem parsed) {
    if (parsed.quantity == 1.0 && parsed.unit == 'serving') return parsed.normalizedName;
    if (parsed.quantity == 1.0) return '${parsed.unit} ${parsed.normalizedName}'.trim();
    String formattedQty = parsed.quantity == parsed.quantity.toInt() ? '${parsed.quantity.toInt()}' : '${parsed.quantity}';
    return '$formattedQty ${parsed.unit} ${parsed.normalizedName}'.trim();
  }

  NutritionItem _itemFromMemory(ParsedFoodItem parsed, NutritionResult mem, String sourceStr) {
    final scale = parsed.quantity;
    return NutritionItem(
      name: parsed.normalizedName,
      quantity: parsed.quantity,
      unit: parsed.unit,
      estimated: true,
      mode: mem.items.isNotEmpty ? mem.items.first.mode : EstimationMode.packagedKnown,
      calories: NutrientRange(min: mem.calories.min * scale, max: mem.calories.max * scale),
      protein: NutrientRange(min: mem.protein.min * scale, max: mem.protein.max * scale),
    );
  }

  NutritionItem _pullBestItem(NutritionResult result, ParsedFoodItem parsed) {
    if (result.items.isEmpty) {
      return NutritionItem(
        name: parsed.normalizedName,
        quantity: parsed.quantity,
        unit: parsed.unit,
        estimated: true,
        mode: EstimationMode.directQuantity,
        calories: result.calories,
        protein: result.protein,
      );
    }
    
    // Bundle mock-separated logic pieces logically tracking atomic components
    double cMin = 0, cMax = 0, pMin = 0, pMax = 0;
    for (final i in result.items) {
      cMin += i.calories.min; cMax += i.calories.max;
      pMin += i.protein.min; pMax += i.protein.max;
    }

    return NutritionItem(
      name: parsed.normalizedName,
      quantity: parsed.quantity,
      unit: parsed.unit,
      estimated: true,
      mode: result.items.first.mode,
      calories: NutrientRange(min: cMin, max: cMax),
      protein: NutrientRange(min: pMin, max: pMax),
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
