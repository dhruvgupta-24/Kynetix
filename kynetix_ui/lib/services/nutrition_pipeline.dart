import '../data/micronutrient_library.dart';
import 'package:flutter/foundation.dart';
import '../models/nutrition_result.dart';
import '../services/meal_memory.dart';
import '../services/personal_nutrition_memory.dart';
import '../services/user_nutrition_memory.dart';
import '../services/global_food_service.dart';
import '../services/ai_nutrition_service.dart';
import '../services/meal_classifier.dart';
import '../services/nutrition_guardrails.dart';
import '../services/mock_estimation_service.dart'
  show
    analyzeLocalEstimation,
    LocalEstimationAnalysis,
    NutrientRange;
import '../services/item_parser.dart';
import '../services/food_link_service.dart';
import '../services/unit_normalizer.dart';
import '../services/food_role_classifier.dart';
import '../services/eating_pattern_service.dart';
import '../services/cloud_sync_service.dart';
import '../data/indian_curry_table.dart';
import 'accompaniment_portion_resolver.dart';
import '../models/user_profile.dart';
import 'profile_service.dart';

export '../services/mock_estimation_service.dart' show NutrientRange;

// Logging in this file is debug-only: release builds skip the console I/O.
void _debugLog(String? message, {int? wrapWidth}) {
  if (kDebugMode) debugPrint(message, wrapWidth: wrapWidth);
}


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

    _debugLog('\n══════════════════════════════════════');
    _debugLog('[Pipeline] estimateMeal: "$trimmed"');
    _debugLog('[Pipeline] classification: ${classification.category.name} '
               '(${classification.reason})');

    if (trimmed.isEmpty) return _empty();

    // ── 0. LINKED SCANNED FOOD ───────────────────────────────────────────────
    // A name the person linked to a scanned pack (its own name or an older
    // one) logs the pack's label numbers, exactly like the scanner does.
    final linked = FoodLinkService.instance.resolveMeal(trimmed);
    if (linked != null) {
      _debugLog('[Pipeline] ✅ Linked scanned food: ${linked.canonicalMeal}');
      return linked;
    }

    // ── 1. SPLIT & PARSE INTO ATOMIC ITEMS ─────────────────────────────────
    final parsedItems = ItemParser.parse(trimmed);
    _debugLog('[Pipeline] Extracted ${parsedItems.length} items:');
    for (final p in parsedItems) {
      _debugLog('  -> ${p.normalizedName} (qty: ${p.quantity}, unit: ${p.unit})');
    }

    var finalItems = <NutritionItem>[];
    double sumCalMin = 0, sumCalMax = 0;
    double sumProMin = 0, sumProMax = 0;
    final allWarnings = <String>[];
    bool aiUsed = false;
    bool localHybridUsed = false;
    
    final needsEstimation = <ParsedFoodItem>[];

    final matchesUsed = <String>[];
    final priorityLevels = <String>{};
    final uncertaintyFactors = <String>[];

    // Names whose values the person set themselves (their override, their
    // saved food, a scanned pack): the portion resolver leaves these alone.
    final pinned = <String>{};

    // ── 2. ITEM-LEVEL MEMORY LOOKUP ─────────────────────────────────────────
    for (final parsed in parsedItems) {
      // Normalize quantity and unit to base units (g, ml, or count).
      // This ensures 0.15 kg == 150 g when matching saved memories.
      final normParsed = _normalizeParsed(parsed);
      final name = normParsed.normalizedName;
      final itemStr = _constructItemString(normParsed);

      _debugLog('[Pipeline] --- Lookup for item: "$itemStr" (normalized: "$name") ---');

      // ── LINKED SCANNED FOOD ─────────────────────────────────────────────────
      final linkedItem = FoodLinkService.instance
          .resolveItem(name, normParsed.quantity, normParsed.unit);
      if (linkedItem != null) {
        finalItems.add(linkedItem);
        pinned.add(linkedItem.name.toLowerCase().trim());
        matchesUsed.add('linked_barcode: $name');
        priorityLevels.add('Branded Food');
        continue;
      }

      // ── USER OVERRIDE ───────────────────────────────────────────────────────────
      // Source: stores PER-UNIT-1 values. MUST scale by normParsed.quantity.
      // Hard blocks AI when matched. Unit-category guard applied.
      _debugLog('[Pipeline]   [1/5] Checking UserNutritionMemory...');
      final userOverride = UserNutritionMemory.instance.lookup(name);
      if (userOverride != null) {
        final storedUnit = UserNutritionMemory.instance.storedUnit(name);
        if (storedUnit != null &&
            !UnitNormalizer.sameCategory(storedUnit, normParsed.unit)) {
          _debugLog('[Pipeline]     ⚠️  unit mismatch: stored=$storedUnit input=${normParsed.unit}, skipping UserNutritionMemory');
        } else {
          final candidate = _itemFromPerUnitMemory(normParsed, userOverride);
          if (_isSane(candidate, name)) {
            _debugLog('[Pipeline]     ✅ Match in UserNutritionMemory: ${candidate.calories.mid.toStringAsFixed(1)} kcal, ${candidate.protein.mid.toStringAsFixed(1)}g protein, AI BLOCKED');
            finalItems.add(candidate);
            pinned.add(candidate.name.toLowerCase().trim());
            matchesUsed.add('user_override: $name');
            priorityLevels.add('User Memory');
            continue;
          } else {
            _debugLog('[Pipeline]     🚨 Matched but insane values, skipping UserNutritionMemory');
          }
        }
      } else {
        _debugLog('[Pipeline]     No match in UserNutritionMemory');
      }

      // ── PERSONAL EXACT / TEMPLATE ──────────────────────────────────────────────
      _debugLog('[Pipeline]   [2/5] Checking PersonalNutritionMemory...');
      final personalExact = PersonalNutritionMemory.instance.lookupExact(itemStr);
      if (personalExact != null) {
        final candidate = _itemFromPortionMemory(normParsed, personalExact);
        if (_isSane(candidate, name)) {
          _debugLog('[Pipeline]     ✅ Match in PersonalNutritionMemory (exact): ${candidate.calories.mid.toStringAsFixed(1)} kcal, ${candidate.protein.mid.toStringAsFixed(1)}g protein, AI BLOCKED');
          finalItems.add(candidate);
          pinned.add(candidate.name.toLowerCase().trim());
          matchesUsed.add('personal_exact: $itemStr');
          priorityLevels.add('Saved Meal');
          continue;
        }
      }
      final personalTemplate = PersonalNutritionMemory.instance.lookupTemplate(itemStr);
      if (personalTemplate != null) {
        final candidate = _itemFromPortionMemory(normParsed, personalTemplate);
        if (_isSane(candidate, name)) {
          _debugLog('[Pipeline]     ✅ Match in PersonalNutritionMemory (template): ${candidate.calories.mid.toStringAsFixed(1)} kcal, ${candidate.protein.mid.toStringAsFixed(1)}g protein, AI BLOCKED');
          finalItems.add(candidate);
          pinned.add(candidate.name.toLowerCase().trim());
          matchesUsed.add('personal_template: $itemStr');
          priorityLevels.add('Saved Meal');
          continue;
        }
      }
      _debugLog('[Pipeline]     No match in PersonalNutritionMemory');

      // ── EXACT KNOWN FOOD / RECURRING MEMORY ──────────────────────────────────────
      _debugLog('[Pipeline]   [3/5] Checking MealMemory (known/recurring)...');
      final exactKnown = MealMemory.instance.lookupExactKnownFood(itemStr);
      if (exactKnown != null) {
        final candidate = _itemFromPortionMemory(normParsed, exactKnown);
        if (_isSane(candidate, name)) {
          _debugLog('[Pipeline]     ✅ Match in MealMemory (exact known): ${candidate.calories.mid.toStringAsFixed(1)} kcal, ${candidate.protein.mid.toStringAsFixed(1)}g protein, AI BLOCKED');
          finalItems.add(candidate);
          matchesUsed.add('exact_known: $itemStr');
          final isBoot = MealMemory.instance.allKnownFoods.containsKey(name) &&
                         !UserNutritionMemory.instance.allOverrides.any((o) => o.canonicalMeal == name);
          priorityLevels.add(isBoot ? 'Branded Food' : 'User Memory');
          continue;
        }
      }
      final cached = MealMemory.instance.lookupRecurring(itemStr);
      if (cached != null) {
        final candidate = _itemFromPortionMemory(normParsed, cached);
        if (_isSane(candidate, name)) {
          _debugLog('[Pipeline]     ✅ Match in MealMemory (recurring cache): ${candidate.calories.mid.toStringAsFixed(1)} kcal, ${candidate.protein.mid.toStringAsFixed(1)}g protein, AI BLOCKED');
          finalItems.add(candidate);
          matchesUsed.add('recurring_memory: $itemStr');
          priorityLevels.add('User Memory');
          continue;
        }
      }
      _debugLog('[Pipeline]     No match in MealMemory');

      // ── INDIAN CURRY TABLE ──────────────────────────────────────────────────────
      // Dal, sabzi, chole, paneer and meat gravies: cited per 100 g values. The
      // portion resolver below sizes them by the roti and rice in the meal.
      final curry = IndianCurryTable.match(name);
      if (curry != null) {
        finalItems.add(_curryPlaceholder(normParsed, curry));
        matchesUsed.add('curry_table: $name');
        priorityLevels.add('Food Library');
        continue;
      }

      // ── GLOBAL FOOD DEFAULTS (KYNETIX CURATED) ──────────────────────────────────
      _debugLog('[Pipeline]   Checking GlobalFoodService...');
      final globalResult = GlobalFoodService.instance.lookup(name, quantity: normParsed.quantity);
      if (globalResult != null) {
        final candidate = _pullBestItem(globalResult, normParsed);
        if (_isSane(candidate, name)) {
          _debugLog('[Pipeline]     ✅ Match in GlobalFoodService: ${candidate.calories.mid.toStringAsFixed(1)} kcal, ${candidate.protein.mid.toStringAsFixed(1)}g protein, AI BLOCKED');
          finalItems.add(candidate.withScalar(1.0));
          matchesUsed.add('global_default: $name');
          priorityLevels.add('Global Default');
          continue;
        }
      }
      _debugLog('[Pipeline]     No match in GlobalFoodService');

      // ── FOOD LIBRARY (LOCAL DATABASE) ───────────────────────────────────────────
      _debugLog('[Pipeline]   [4/5] Checking Food Library (local database)...');
      final localAnalysis = analyzeLocalEstimation(itemStr);
      if (localAnalysis.coverageConfidence >= 0.9 && localAnalysis.estimation.items.isNotEmpty) {
        final localResult = NutritionResult.fromEstimationResult(localAnalysis.estimation, itemStr)
            .copyWith(source: 'local_hybrid');
        final candidate = _pullBestItem(localResult, normParsed);
        if (_isSane(candidate, name)) {
          _debugLog('[Pipeline]     ✅ Match in Food Library: ${candidate.calories.mid.toStringAsFixed(1)} kcal, ${candidate.protein.mid.toStringAsFixed(1)}g protein, AI BLOCKED');
          // Important: mark it true so portion anchor pass doesn't scale it!
          finalItems.add(candidate.withScalar(1.0));
          matchesUsed.add('food_library: $name');
          priorityLevels.add('Branded Food');
          continue;
        }
      }
      _debugLog('[Pipeline]     No match in Food Library');

      // ── AI ESTIMATE ESCALATION GATED ─────────────────────────────────────────────
      _debugLog('[Pipeline]   [5/5] All memory and database lookups failed for "$name". Escalation to AI/estimation required.');
      needsEstimation.add(normParsed);
    }

    // ── 3. AI / MOCK ESTIMATION PER ATOMIC ITEM ──────────────────────────────
    for (final parsed in needsEstimation) {
      // Re-stitch item specific string for the estimator engine. 
      // It relies on qty + unit + name context. e.g "1 scoop whey"
      final itemStr = _constructItemString(parsed);
      _debugLog('[Pipeline] Estimating unknown atomic item: "$itemStr"');

      final localAnalysis = analyzeLocalEstimation(itemStr);
      final complexity = _assessComplexity(itemStr, localAnalysis);
      final localGate = _buildGate(localAnalysis, complexity);

      if (localGate.shouldFinalizeLocal) {
        _debugLog('[Pipeline] ✅ LOCAL FINALIZED for "$itemStr"');
        final localResult = _finalizeLocal(itemStr, localAnalysis, classification: classification, fallbackReason: 'Local passed');
        final item = _pullBestItem(localResult, parsed);
        finalItems.add(item);
        localHybridUsed = true;
        matchesUsed.add('local_fallback: $itemStr');
        priorityLevels.add('AI Estimate');
        uncertaintyFactors.add('local fallback');
      } else {
        if (AiNutritionService.instance.isConfigured) {
          _debugLog('[Pipeline] 🚀 calling AI for item: "$itemStr"...');
          try {
            final raw = await AiNutritionService.instance.estimateWithContext(
              itemStr,
              context: AiEscalationContext(
                localInterpretation: _localInterpretation(localAnalysis),
                localMatchConfidence: localGate.matchConfidence,
                localCoverageConfidence: localGate.coverageConfidence,
                overallLocalConfidence: localGate.overallConfidence,
                flags: complexity.flags,
                mealContext: parsedItems.length > 1 ? trimmed : null,
              ),
            );
            final aiResult = NutritionGuardrails.apply(raw, itemStr, classification: classification).normalizedUncertainty();
            // Kyno saw the whole meal and the eater type, so its amount is
            // already sized to the roti and rice: the eater-type pass must
            // not shrink it a second time.
            final pulled = _pullBestItem(_onlyAskedItem(aiResult, parsed, parsedItems), parsed);
            final item = parsedItems.length > 1 ? pulled.withScalar(1.0) : pulled;
            finalItems.add(item);
            aiUsed = true;
            matchesUsed.add('ai_estimate: $itemStr');
            priorityLevels.add('AI Estimate');
            if (classification.category != MealDensityCategory.light) {
              uncertaintyFactors.add('mixed meal components');
            }
          } catch (e) {
            _debugLog('[Pipeline] ❌ AI failed for item "$itemStr": $e');
            final localResult = _finalizeLocal(itemStr, localAnalysis, classification: classification, fallbackReason: 'AI escalation required; AI failed for item');
            final item = _pullBestItem(localResult, parsed);
            finalItems.add(item);
            localHybridUsed = true;
            matchesUsed.add('local_fallback: $itemStr');
            priorityLevels.add('AI Estimate');
            uncertaintyFactors.add('local fallback (AI failed)');
          }
        } else {
          final localResult = _finalizeLocal(itemStr, localAnalysis, classification: classification, fallbackReason: 'AI escalation required; No AI key');
          final item = _pullBestItem(localResult, parsed);
          finalItems.add(item);
          localHybridUsed = true;
          matchesUsed.add('local_fallback: $itemStr');
          priorityLevels.add('AI Estimate');
          uncertaintyFactors.add('local fallback (AI unavailable)');
        }
      }
    }

    // Size dal / sabzi / chole by the roti and rice they were eaten with, then
    // apply eating pattern scalars and Portion Anchor meal-level adjustments.
    finalItems = AccompanimentPortionResolver.resolve(
      finalItems,
      anchor: ProfileService.instance.activePortionAnchor,
      pinned: pinned,
    );
    finalItems = _withMicros(_applyMealLevelPortionAnchorPass(finalItems));

    // ── 4. AGGREGATION ───────────────────────────────────────────────────────
    double? carbMin, carbMax, fatMin, fatMax, fibMin, fibMax, sugMin, sugMax, satMin, satMax, sodMin, sodMax;
    for (final item in finalItems) {
      sumCalMin += item.calories.min;
      sumCalMax += item.calories.max;
      sumProMin += item.protein.min;
      sumProMax += item.protein.max;

      if (item.carbohydrates != null) {
        carbMin = (carbMin ?? 0) + item.carbohydrates!.min;
        carbMax = (carbMax ?? 0) + item.carbohydrates!.max;
      }
      if (item.fat != null) {
        fatMin = (fatMin ?? 0) + item.fat!.min;
        fatMax = (fatMax ?? 0) + item.fat!.max;
      }
      if (item.fiber != null) {
        fibMin = (fibMin ?? 0) + item.fiber!.min;
        fibMax = (fibMax ?? 0) + item.fiber!.max;
      }
      if (item.sugar != null) {
        sugMin = (sugMin ?? 0) + item.sugar!.min;
        sugMax = (sugMax ?? 0) + item.sugar!.max;
      }
      if (item.saturatedFat != null) {
        satMin = (satMin ?? 0) + item.saturatedFat!.min;
        satMax = (satMax ?? 0) + item.saturatedFat!.max;
      }
      if (item.sodium != null) {
        sodMin = (sodMin ?? 0) + item.sodium!.min;
        sodMax = (sodMax ?? 0) + item.sodium!.max;
      }
    }

    String source = 'user_override';
    if (aiUsed) {
      source = 'ai';
    } else if (localHybridUsed) {
      source = 'local_hybrid';
    } else if (matchesUsed.isNotEmpty) {
      if (matchesUsed.any((m) => m.startsWith('personal_exact:'))) {
        source = 'personal_exact';
      } else if (matchesUsed.any((m) => m.startsWith('personal_template:'))) {
        source = 'personal_template';
      } else if (matchesUsed.any((m) => m.startsWith('exact_known:'))) {
        source = 'memory_exact';
      } else if (matchesUsed.any((m) => m.startsWith('recurring_memory:'))) {
        source = 'cache';
      } else if (matchesUsed.any((m) => m.startsWith('user_override:'))) {
        source = 'user_override';
      }
    }

    final midCal = (sumCalMin + sumCalMax) / 2;
    final midPro = (sumProMin + sumProMax) / 2;
    final score = NutritionResult.calculateLocalQualityScore(
      midCal,
      midPro,
      trimmed,
      carbs: carbMin != null && carbMax != null ? (carbMin + carbMax) / 2 : null,
      fat: fatMin != null && fatMax != null ? (fatMin + fatMax) / 2 : null,
      fiber: fibMin != null && fibMax != null ? (fibMin + fibMax) / 2 : null,
    );

    // Record meal context for pattern learning and sync to cloud
    EatingPatternService.instance.recordMealContext(
        FoodRoleClassifier.classifyAll(parsedItems));
    // Fire-and-forget: upload new contexts to Supabase so they survive device wipes
    CloudSyncService.instance.syncMealContextsBackground().ignore();
    CloudSyncService.instance.syncEatingPatternsBackground().ignore();

    String memoryPriorityLevel = 'AI Estimate';
    if (priorityLevels.contains('User Memory')) {
      memoryPriorityLevel = 'User Memory';
    } else if (priorityLevels.contains('Saved Meal')) {
      memoryPriorityLevel = 'Saved Meal';
    } else if (priorityLevels.contains('Branded Food')) {
      memoryPriorityLevel = 'Branded Food';
    }

    final audit = EstimationAudit(
      memoryMatchUsed: matchesUsed.isNotEmpty ? matchesUsed.join('; ') : 'none, AI fallback',
      portionAssumption: ProfileService.instance.currentUserProfile?.portionAnchor?.toString() ?? 'PortionAnchor.balanced',
      environmentAssumption: 'behavior-based (default)',
      finalChoiceReason: aiUsed ? 'AI estimation successful' : (localHybridUsed ? 'local pipeline fallback' : 'memory exact match'),
      uncertaintyFactors: uncertaintyFactors,
      pipelineConfidence: aiUsed ? 0.95 : 0.90,
      memoryPriorityLevel: memoryPriorityLevel,
    );

    return NutritionResult(
      canonicalMeal: trimmed,
      items: finalItems,
      calories: NutrientRange(min: sumCalMin, max: sumCalMax),
      protein: NutrientRange(min: sumProMin, max: sumProMax),
      confidence: aiUsed ? 0.95 : 0.90, // simplify for aggregate
      warnings: allWarnings,
      source: source,
      createdAt: DateTime.now(),
      carbohydrates: carbMin != null ? NutrientRange(min: carbMin, max: carbMax!) : null,
      fat: fatMin != null ? NutrientRange(min: fatMin, max: fatMax!) : null,
      fiber: fibMin != null ? NutrientRange(min: fibMin, max: fibMax!) : null,
      sugar: sugMin != null ? NutrientRange(min: sugMin, max: sugMax!) : null,
      saturatedFat: satMin != null ? NutrientRange(min: satMin, max: satMax!) : null,
      sodium: sodMin != null ? NutrientRange(min: sodMin, max: sodMax!) : null,
      mealQualityScore: score,
      mealQualityExplanation: NutritionResult.getLocalQualityExplanation(score, trimmed),
      mealQualityPositive: NutritionResult.getLocalQualityPositive(score, trimmed),
      mealQualityImprovement: NutritionResult.getLocalQualityImprovement(score, trimmed),
      estimationAudit: audit,
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
      return parsed; // already canonical, avoid allocation
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

  // ── Memory helpers ───────────────────────────────────────────────────

  /// FOR USER OVERRIDE MEMORY ONLY.
  /// Memory stores PER-UNIT-1 values (e.g. 2 kcal per gram).
  /// Result is scaled by normParsed.quantity to get total for this portion.
  /// e.g. 2 kcal/g × 150 g = 300 kcal.
  NutritionItem _itemFromPerUnitMemory(
      ParsedFoodItem parsed, NutritionResult mem) {
    final scale = parsed.quantity.clamp(0.0, double.infinity);
    if (scale == 0) {
      // Guard: avoid zero-scale resulting in 0 kcal misleadingly.
      return _itemFromPortionMemory(parsed, mem);
    }
    
    final calVal = mem.calories.min * scale;
    final proVal = mem.protein.min * scale;
    final fallbackCarbs = NutritionResult.estimateCarbsLocally(calVal, proVal, parsed.normalizedName);
    final fallbackFat = NutritionResult.estimateFatLocally(calVal, proVal, parsed.normalizedName);
    final fallbackFiber = NutritionResult.estimateFiberLocally(calVal, parsed.normalizedName);

    return NutritionItem(
      name:      parsed.normalizedName,
      quantity:  parsed.quantity,
      unit:      parsed.unit,
      estimated: true,
      mode: mem.items.isNotEmpty
          ? mem.items.first.mode
          : EstimationMode.packagedKnown,
      calories: NutrientRange(
          min: mem.calories.min * scale, max: mem.calories.max * scale),
      protein: NutrientRange(
          min: mem.protein.min * scale, max: mem.protein.max * scale),
      carbohydrates: mem.carbohydrates != null
          ? NutrientRange(min: mem.carbohydrates!.min * scale, max: mem.carbohydrates!.max * scale)
          : fallbackCarbs,
      fat: mem.fat != null
          ? NutrientRange(min: mem.fat!.min * scale, max: mem.fat!.max * scale)
          : fallbackFat,
      fiber: mem.fiber != null
          ? NutrientRange(min: mem.fiber!.min * scale, max: mem.fiber!.max * scale)
          : fallbackFiber,
      sugar: mem.sugar != null
          ? NutrientRange(min: mem.sugar!.min * scale, max: mem.sugar!.max * scale)
          : null,
      saturatedFat: mem.saturatedFat != null
          ? NutrientRange(min: mem.saturatedFat!.min * scale, max: mem.saturatedFat!.max * scale)
          : null,
      sodium: mem.sodium != null
          ? NutrientRange(min: mem.sodium!.min * scale, max: mem.sodium!.max * scale)
          : null,
      eatingPatternScalarApplied: true,
    );
  }

  /// FOR PersonalNutritionMemory, MealMemory.lookupExactKnownFood,
  /// and MealMemory.lookupRecurring.
  /// These sources return TOTAL calories for the full queried portion
  /// (they already include quantity in their stored value).
  /// MUST NOT scale by quantity — use the result directly.
  NutritionItem _itemFromPortionMemory(
      ParsedFoodItem parsed, NutritionResult mem) {
    // Sum items if present, otherwise use top-level totals.
    double cMin = 0, cMax = 0, pMin = 0, pMax = 0;
    double? carbMin, carbMax, fatMin, fatMax, fibMin, fibMax, sugMin, sugMax, satMin, satMax, sodMin, sodMax;

    if (mem.items.isNotEmpty) {
      for (final i in mem.items) {
        cMin += i.calories.min; cMax += i.calories.max;
        pMin += i.protein.min;  pMax += i.protein.max;
        if (i.carbohydrates != null) {
          carbMin = (carbMin ?? 0) + i.carbohydrates!.min;
          carbMax = (carbMax ?? 0) + i.carbohydrates!.max;
        }
        if (i.fat != null) {
          fatMin = (fatMin ?? 0) + i.fat!.min;
          fatMax = (fatMax ?? 0) + i.fat!.max;
        }
        if (i.fiber != null) {
          fibMin = (fibMin ?? 0) + i.fiber!.min;
          fibMax = (fibMax ?? 0) + i.fiber!.max;
        }
        if (i.sugar != null) {
          sugMin = (sugMin ?? 0) + i.sugar!.min;
          sugMax = (sugMax ?? 0) + i.sugar!.max;
        }
        if (i.saturatedFat != null) {
          satMin = (satMin ?? 0) + i.saturatedFat!.min;
          satMax = (satMax ?? 0) + i.saturatedFat!.max;
        }
        if (i.sodium != null) {
          sodMin = (sodMin ?? 0) + i.sodium!.min;
          sodMax = (sodMax ?? 0) + i.sodium!.max;
        }
      }
    } else {
      cMin = mem.calories.min; cMax = mem.calories.max;
      pMin = mem.protein.min;  pMax = mem.protein.max;
      if (mem.carbohydrates != null) {
        carbMin = mem.carbohydrates!.min;
        carbMax = mem.carbohydrates!.max;
      }
      if (mem.fat != null) {
        fatMin = mem.fat!.min;
        fatMax = mem.fat!.max;
      }
      if (mem.fiber != null) {
        fibMin = mem.fiber!.min;
        fibMax = mem.fiber!.max;
      }
      if (mem.sugar != null) {
        sugMin = mem.sugar!.min;
        sugMax = mem.sugar!.max;
      }
      if (mem.saturatedFat != null) {
        satMin = mem.saturatedFat!.min;
        satMax = mem.saturatedFat!.max;
      }
      if (mem.sodium != null) {
        sodMin = mem.sodium!.min;
        sodMax = mem.sodium!.max;
      }
    }

    final midCal = (cMin + cMax) / 2;
    final midPro = (pMin + pMax) / 2;
    final fallbackCarbs = NutritionResult.estimateCarbsLocally(midCal, midPro, parsed.normalizedName);
    final fallbackFat = NutritionResult.estimateFatLocally(midCal, midPro, parsed.normalizedName);
    final fallbackFiber = NutritionResult.estimateFiberLocally(midCal, parsed.normalizedName);

    return NutritionItem(
      name:      parsed.normalizedName,
      quantity:  parsed.quantity,
      unit:      parsed.unit,
      estimated: true,
      mode: mem.items.isNotEmpty
          ? mem.items.first.mode
          : EstimationMode.directQuantity,
      calories: NutrientRange(min: cMin, max: cMax),
      protein:  NutrientRange(min: pMin, max: pMax),
      carbohydrates: carbMin != null ? NutrientRange(min: carbMin, max: carbMax!) : fallbackCarbs,
      fat: fatMin != null ? NutrientRange(min: fatMin, max: fatMax!) : fallbackFat,
      fiber: fibMin != null ? NutrientRange(min: fibMin, max: fibMax!) : fallbackFiber,
      sugar: sugMin != null ? NutrientRange(min: sugMin, max: sugMax!) : const NutrientRange(min: 0, max: 0),
      saturatedFat: satMin != null ? NutrientRange(min: satMin, max: satMax!) : const NutrientRange(min: 0, max: 0),
      sodium: sodMin != null ? NutrientRange(min: sodMin, max: sodMax!) : const NutrientRange(min: 0, max: 0),
      eatingPatternScalarApplied: true,
    );
  }

  /// Hard sanity check on a single NutritionItem.
  /// Rejects any result that exceeds physically impossible bounds for a
  /// single food item in a single meal. These bounds are intentionally
  /// very permissive — they only catch clear corruption, not edge cases.
  ///
  /// Max calories per item: 3 000 kcal  (realistic upper bound: large pizza slice)
  /// Max protein per item: 300 g        (more than any real single-item portion)
  ///
  /// If a category hint is available (liquid item), the calorie cap is tighter:
  /// liquids: max 1 500 kcal (e.g. highest-calorie smoothies)
  bool _isSane(NutritionItem item, String foodName) {
    final cal = item.calories.max;
    final pro = item.protein.max;

    // Absolute maximums (physics-level)
    if (cal > 3000 || pro > 300) {
      _debugLog('[Pipeline] 🚨 SANITY FAIL absolute: '
          '"$foodName" cal=$cal pro=$pro');
      return false;
    }

    // Liquid heuristic: if unit is ml and quantity > 100ml, cap at 1 500 kcal
    if (item.unit == 'ml' && item.quantity > 100 && cal > 1500) {
      _debugLog('[Pipeline] 🚨 SANITY FAIL liquid: '
          '"$foodName" ${item.quantity}ml = $cal kcal');
      return false;
    }

    // Weight heuristic: if unit is g and quantity < 1000g, kcal cannot exceed
    // ~9 kcal/g × quantity (pure fat is 9 kcal/g — nothing is denser).
    if (item.unit == 'g' && item.quantity > 0 && cal > item.quantity * 9.5) {
      _debugLog('[Pipeline] 🚨 SANITY FAIL density: '
          '"$foodName" ${item.quantity}g = $cal kcal '
          '(>${(item.quantity * 9.5).toStringAsFixed(0)} max)');
      return false;
    }

    return true;
  }

  /// When Kyno was shown the whole meal for one item, keep only what it
  /// returned for that item: a stray roti or rice row must not be added into
  /// the sabzi's numbers.
  NutritionResult _onlyAskedItem(NutritionResult r, ParsedFoodItem asked, List<ParsedFoodItem> meal) {
    if (meal.length < 2 || r.items.length < 2) return r;
    final others = [for (final p in meal) if (!identical(p, asked)) p.normalizedName.toLowerCase()];
    Set<String> words(String s) => s.toLowerCase().split(RegExp(r'[^a-z]+')).where((w) => w.length > 2).toSet();
    final askedWords = words(asked.normalizedName);
    final keep = [
      for (final i in r.items)
        if (words(i.name).intersection(askedWords).isNotEmpty ||
            !others.any((o) => words(o).intersection(words(i.name)).isNotEmpty))
          i,
    ];
    if (keep.isEmpty || keep.length == r.items.length) return r;
    final cal = keep.fold<NutrientRange>(const NutrientRange(min: 0, max: 0), (a, i) => a + i.calories);
    final pro = keep.fold<NutrientRange>(const NutrientRange(min: 0, max: 0), (a, i) => a + i.protein);
    return r.copyWith(items: keep, calories: cal, protein: pro);
  }

  /// A curry from [IndianCurryTable] at one katori per serving (or the amount
  /// typed), keeping the typed quantity and unit so that
  /// [AccompanimentPortionResolver] can size it against the meal's carbs.
  NutritionItem _curryPlaceholder(ParsedFoodItem parsed, CurryDish dish) {
    final asTyped = NutritionItem(
      name: parsed.normalizedName,
      quantity: parsed.quantity,
      unit: parsed.unit,
      estimated: true,
      mode: EstimationMode.contextualIntake,
      calories: const NutrientRange(min: 0, max: 0),
      protein: const NutrientRange(min: 0, max: 0),
    );
    final grams = AccompanimentPortionResolver.explicitGramsOf(asTyped) ??
        AccompanimentPortionResolver.katoriGrams * (parsed.quantity > 0 ? parsed.quantity : 1);
    return AccompanimentPortionResolver.itemFor(dish, grams,
        name: parsed.normalizedName, quantity: parsed.quantity, unit: parsed.unit);
  }

  NutritionItem _pullBestItem(NutritionResult result, ParsedFoodItem parsed) {
    if (result.items.isEmpty) {
      final calMid = result.calories.mid;
      final proMid = result.protein.mid;
      return NutritionItem(
        name: parsed.normalizedName,
        quantity: parsed.quantity,
        unit: parsed.unit,
        estimated: true,
        mode: EstimationMode.directQuantity,
        calories: result.calories,
        protein: result.protein,
        carbohydrates: result.carbohydrates ?? NutritionResult.estimateCarbsLocally(calMid, proMid, parsed.normalizedName),
        fat: result.fat ?? NutritionResult.estimateFatLocally(calMid, proMid, parsed.normalizedName),
        fiber: result.fiber ?? NutritionResult.estimateFiberLocally(calMid, parsed.normalizedName),
        sugar: result.sugar,
        saturatedFat: result.saturatedFat,
        sodium: result.sodium,
      );
    }

    // Micros carry over only when every part had them; a partial sum would
    // read as a complete (and too low) value.
    Micronutrients? micros;
    if (result.items.every((i) => i.micros != null)) {
      micros = result.items.fold<Micronutrients>(Micronutrients.empty, (a, i) => a + i.micros!);
    }
    
    // Bundle mock-separated logic pieces logically tracking atomic components
    double cMin = 0, cMax = 0, pMin = 0, pMax = 0;
    double? carbMin, carbMax, fatMin, fatMax, fibMin, fibMax, sugMin, sugMax, satMin, satMax, sodMin, sodMax;
    for (final i in result.items) {
      cMin += i.calories.min; cMax += i.calories.max;
      pMin += i.protein.min; pMax += i.protein.max;
      if (i.carbohydrates != null) {
        carbMin = (carbMin ?? 0) + i.carbohydrates!.min;
        carbMax = (carbMax ?? 0) + i.carbohydrates!.max;
      }
      if (i.fat != null) {
        fatMin = (fatMin ?? 0) + i.fat!.min;
        fatMax = (fatMax ?? 0) + i.fat!.max;
      }
      if (i.fiber != null) {
        fibMin = (fibMin ?? 0) + i.fiber!.min;
        fibMax = (fibMax ?? 0) + i.fiber!.max;
      }
      if (i.sugar != null) {
        sugMin = (sugMin ?? 0) + i.sugar!.min;
        sugMax = (sugMax ?? 0) + i.sugar!.max;
      }
      if (i.saturatedFat != null) {
        satMin = (satMin ?? 0) + i.saturatedFat!.min;
        satMax = (satMax ?? 0) + i.saturatedFat!.max;
      }
      if (i.sodium != null) {
        sodMin = (sodMin ?? 0) + i.sodium!.min;
        sodMax = (sodMax ?? 0) + i.sodium!.max;
      }
    }

    final double midC = (cMin + cMax) / 2;
    final double midP = (pMin + pMax) / 2;
    final fallbackCarbs = result.carbohydrates ?? NutritionResult.estimateCarbsLocally(midC, midP, parsed.normalizedName);
    final fallbackFat = result.fat ?? NutritionResult.estimateFatLocally(midC, midP, parsed.normalizedName);
    final fallbackFiber = result.fiber ?? NutritionResult.estimateFiberLocally(midC, parsed.normalizedName);

    return NutritionItem(
      name: parsed.normalizedName,
      quantity: parsed.quantity,
      unit: parsed.unit,
      estimated: true,
      mode: result.items.first.mode,
      calories: NutrientRange(min: cMin, max: cMax),
      protein: NutrientRange(min: pMin, max: pMax),
      carbohydrates: carbMin != null ? NutrientRange(min: carbMin, max: carbMax!) : fallbackCarbs,
      fat: fatMin != null ? NutrientRange(min: fatMin, max: fatMax!) : fallbackFat,
      fiber: fibMin != null ? NutrientRange(min: fibMin, max: fibMax!) : fallbackFiber,
      sugar: sugMin != null ? NutrientRange(min: sugMin, max: sugMax!) : null,
      saturatedFat: satMin != null ? NutrientRange(min: satMin, max: satMax!) : null,
      sodium: sodMin != null ? NutrientRange(min: sodMin, max: sodMax!) : null,
      micros: micros == null || micros.isEmpty ? null : micros,
    );
  }

  NutritionResult _finalizeLocal(
    String rawInput,
    LocalEstimationAnalysis analysis, {
    required MealClassification classification,
    required String fallbackReason,
  }) {
    _debugLog('[Pipeline] 📦 LOCAL RESULT, reason: $fallbackReason');
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
    final minMatch = (coverage >= 1.0) ? 0.85 : _minMatchConfidence;
    final lowMatch = match < minMatch;
    final minOverall = (coverage >= 1.0) ? 0.90 : _minOverallLocalConfidence;
    final lowOverall = overall < minOverall;
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

  NutritionResult _empty() {
    final score = NutritionResult.calculateLocalQualityScore(0, 0, '');
    return NutritionResult(
      canonicalMeal:  '',
      items:          const [],
      calories:       const NutrientRange(min: 0, max: 0),
      protein:        const NutrientRange(min: 0, max: 0),
      confidence:     0,
      warnings:       const ['No input provided.'],
      source:         'local_fallback',
      fallbackReason: 'Empty input',
      createdAt:      DateTime.now(),
      mealQualityScore: score,
      mealQualityExplanation: NutritionResult.getLocalQualityExplanation(score, ''),
      mealQualityPositive: NutritionResult.getLocalQualityPositive(score, ''),
      mealQualityImprovement: NutritionResult.getLocalQualityImprovement(score, ''),
    );
  }

  /// Synchronous memory evaluation. Useful for UI elements that need memory numbers instantly 
  /// without risking an async OpenRouter AI API call.
  NutritionResult? fastMemoryLookupSync(String rawInput) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) return null;

    final linked = FoodLinkService.instance.resolveMeal(trimmed);
    if (linked != null) return linked;

    final parsedItems = ItemParser.parse(trimmed);
    var finalItems = <NutritionItem>[];
    final pinned = <String>{};

    for (final parsed in parsedItems) {
      final normParsed = _normalizeParsed(parsed);
      final name = normParsed.normalizedName;
      final itemStr = _constructItemString(normParsed);

      final linkedItem = FoodLinkService.instance
          .resolveItem(name, normParsed.quantity, normParsed.unit);
      if (linkedItem != null) { finalItems.add(linkedItem); pinned.add(linkedItem.name.toLowerCase().trim()); continue; }

      final userOverride = UserNutritionMemory.instance.lookup(name);
      if (userOverride != null) {
        final storedUnit = UserNutritionMemory.instance.storedUnit(name);
        if (storedUnit != null &&
            !UnitNormalizer.sameCategory(storedUnit, normParsed.unit)) {
          _debugLog('[Pipeline Sync] ⚠️  unit mismatch: stored=$storedUnit '
              'input=${normParsed.unit} for "$name", skipping user memory');
        } else {
          final candidate = _itemFromPerUnitMemory(normParsed, userOverride);
          if (_isSane(candidate, name)) { finalItems.add(candidate); pinned.add(candidate.name.toLowerCase().trim()); continue; }
        }
      }

      final personalExact = PersonalNutritionMemory.instance.lookupExact(itemStr);
      if (personalExact != null) {
        final candidate = _itemFromPortionMemory(normParsed, personalExact);
        if (_isSane(candidate, name)) { finalItems.add(candidate); pinned.add(candidate.name.toLowerCase().trim()); continue; }
      }

      final personalTemplate = PersonalNutritionMemory.instance.lookupTemplate(itemStr);
      if (personalTemplate != null) {
        final candidate = _itemFromPortionMemory(normParsed, personalTemplate);
        if (_isSane(candidate, name)) { finalItems.add(candidate); pinned.add(candidate.name.toLowerCase().trim()); continue; }
      }

      final exactKnown = MealMemory.instance.lookupExactKnownFood(itemStr);
      if (exactKnown != null) {
        final candidate = _itemFromPortionMemory(normParsed, exactKnown);
        if (_isSane(candidate, name)) { finalItems.add(candidate); continue; }
      }

      final cached = MealMemory.instance.lookupRecurring(itemStr);
      if (cached != null) {
        final candidate = _itemFromPortionMemory(normParsed, cached);
        if (_isSane(candidate, name)) { finalItems.add(candidate); continue; }
      }

      final curry = IndianCurryTable.match(name);
      if (curry != null) { finalItems.add(_curryPlaceholder(normParsed, curry)); continue; }

      final localAnalysis = analyzeLocalEstimation(itemStr);
      if (localAnalysis.coverageConfidence >= 0.9 && localAnalysis.estimation.items.isNotEmpty) {
        final localResult = NutritionResult.fromEstimationResult(localAnalysis.estimation, itemStr)
            .copyWith(source: 'local_hybrid');
        final candidate = _pullBestItem(localResult, normParsed);
        if (_isSane(candidate, name)) {
          finalItems.add(candidate.withScalar(1.0));
          continue;
        }
      }

      return null; // Atomic item missed memory, requires AI -> fail sync lookup
    }

    finalItems = AccompanimentPortionResolver.resolve(
      finalItems,
      anchor: ProfileService.instance.activePortionAnchor,
      pinned: pinned,
    );
    finalItems = _withMicros(_applyMealLevelPortionAnchorPass(finalItems));

    double sumCalMin = 0, sumCalMax = 0, sumProMin = 0, sumProMax = 0;
    double? carbMin, carbMax, fatMin, fatMax, fibMin, fibMax, sugMin, sugMax, satMin, satMax, sodMin, sodMax;
    for (final item in finalItems) {
      sumCalMin += item.calories.min; sumCalMax += item.calories.max;
      sumProMin += item.protein.min; sumProMax += item.protein.max;
      if (item.carbohydrates != null) {
        carbMin = (carbMin ?? 0) + item.carbohydrates!.min;
        carbMax = (carbMax ?? 0) + item.carbohydrates!.max;
      }
      if (item.fat != null) {
        fatMin = (fatMin ?? 0) + item.fat!.min;
        fatMax = (fatMax ?? 0) + item.fat!.max;
      }
      if (item.fiber != null) {
        fibMin = (fibMin ?? 0) + item.fiber!.min;
        fibMax = (fibMax ?? 0) + item.fiber!.max;
      }
      if (item.sugar != null) {
        sugMin = (sugMin ?? 0) + item.sugar!.min;
        sugMax = (sugMax ?? 0) + item.sugar!.max;
      }
      if (item.saturatedFat != null) {
        satMin = (satMin ?? 0) + item.saturatedFat!.min;
        satMax = (satMax ?? 0) + item.saturatedFat!.max;
      }
      if (item.sodium != null) {
        sodMin = (sodMin ?? 0) + item.sodium!.min;
        sodMax = (sodMax ?? 0) + item.sodium!.max;
      }
    }

    final midCal = (sumCalMin + sumCalMax) / 2;
    final midPro = (sumProMin + sumProMax) / 2;
    final score = NutritionResult.calculateLocalQualityScore(
      midCal,
      midPro,
      trimmed,
      carbs: carbMin != null && carbMax != null ? (carbMin + carbMax) / 2 : null,
      fat: fatMin != null && fatMax != null ? (fatMin + fatMax) / 2 : null,
      fiber: fibMin != null && fibMax != null ? (fibMin + fibMax) / 2 : null,
    );

    return NutritionResult(
      canonicalMeal: trimmed,
      items: finalItems,
      calories: NutrientRange(min: sumCalMin, max: sumCalMax),
      protein: NutrientRange(min: sumProMin, max: sumProMax),
      confidence: 0.95,
      warnings: const [],
      source: 'memory_exact',
      createdAt: DateTime.now(),
      carbohydrates: carbMin != null ? NutrientRange(min: carbMin, max: carbMax!) : null,
      fat: fatMin != null ? NutrientRange(min: fatMin, max: fatMax!) : null,
      fiber: fibMin != null ? NutrientRange(min: fibMin, max: fibMax!) : null,
      sugar: sugMin != null ? NutrientRange(min: sugMin, max: sugMax!) : null,
      saturatedFat: satMin != null ? NutrientRange(min: satMin, max: satMax!) : null,
      sodium: sodMin != null ? NutrientRange(min: sodMin, max: sodMax!) : null,
      mealQualityScore: score,
      mealQualityExplanation: NutritionResult.getLocalQualityExplanation(score, trimmed),
      mealQualityPositive: NutritionResult.getLocalQualityPositive(score, trimmed),
      mealQualityImprovement: NutritionResult.getLocalQualityImprovement(score, trimmed),
    );
  }

  /// Micronutrients: cited food-library values for foods it knows (scaled by
  /// each item's calories); Kyno's estimate fills the rest. Unknown foods stay
  /// untracked rather than zero.
  static List<NutritionItem> _withMicros(List<NutritionItem> items) => [
        for (final i in items)
          i.withMicros(MicronutrientLibrary.instance.enrich(i.name, i.calories.mid, i.micros)),
      ];

  List<NutritionItem> _applyMealLevelPortionAnchorPass(List<NutritionItem> items) {
    if (items.isEmpty) return items;

    // Check if the pass has already been applied to prevent double application
    if (items.isNotEmpty && items.every((item) => item.eatingPatternScalarApplied)) {
      if (kDebugMode) {
        _debugLog('[Pipeline Pass] ⚠️  Skipping Portion Anchor pass: already applied to all.');
      }
      return items;
    }

    // Source of truth: ProfileService.activePortionAnchor.
    //
    // EatingPatternService._seededAnchor is intentionally NOT used here.
    // That field exists only to bootstrap the learning/scalar engine with
    // synthetic correction records. It is not guaranteed to be in sync with
    // the user's current profile preference (the user may change eating style
    // after a seed without triggering a reseed).
    //
    // Reading from ProfileService ensures that a profile change is immediately
    // visible to the pipeline on the very next estimation call, regardless of
    // whether EatingPatternService has been reseeded yet.
    final anchor = ProfileService.instance.activePortionAnchor;

    // 1. Detect roles and compile base metrics
    final roles = <NutritionItem, FoodRole>{};
    double totalPrimaryCalories = 0;
    double totalAccompanimentCalories = 0;

    for (final item in items) {
      final role = FoodRoleClassifier.classify(item.name);
      roles[item] = role;
      if (role == FoodRole.primary) {
        totalPrimaryCalories += item.calories.mid;
      } else if (role == FoodRole.accompaniment) {
        totalAccompanimentCalories += item.calories.mid;
      }
    }

    final hasPrimary = totalPrimaryCalories > 0;
    final hasAccompaniment = totalAccompanimentCalories > 0;

    // 2. Compute unscaled serving equivalents
    double baseCarbServings = 0;
    double baseAccServings = 0;
    for (final item in items) {
      final role = roles[item]!;
      if (role == FoodRole.primary) {
        baseCarbServings += FoodRoleClassifier.estimateServingCount(item.name, FoodRole.primary, item.quantity, item.calories.mid);
      } else if (role == FoodRole.accompaniment) {
        baseAccServings += FoodRoleClassifier.estimateServingCount(item.name, FoodRole.accompaniment, item.quantity, item.calories.mid);
      }
    }

    // Safeguards against extreme scaling / pathological inputs
    baseCarbServings = baseCarbServings.clamp(0.1, 10.0);
    baseAccServings = baseAccServings.clamp(0.1, 10.0);

    final result = <NutritionItem>[];

    // Helper to safely retrieve user-specific learned/seeded pattern scalars
    double? getPatternScalar(FoodRole role, FoodRole? context) {
      return EatingPatternService.instance.getScalar(role, contextRole: context);
    }

    for (final item in items) {
      if (item.eatingPatternScalarApplied) {
        if (kDebugMode) {
          _debugLog('[Pipeline Pass] 🔒 Skipping Portion Anchor scalar for memory-matched item: "${item.name}"');
        }
        result.add(item);
        continue;
      }

      final role = roles[item]!;
      double? finalScalar;

      if (anchor == PortionAnchor.carbAnchored && hasPrimary && hasAccompaniment) {
        if (role == FoodRole.accompaniment) {
          // Expected accompaniment servings scaled based on carb servings
          final expectedAccServings = baseCarbServings * 0.5;
          final baseScale = (expectedAccServings / baseAccServings).clamp(0.3, 3.0);
          final patternScalar = getPatternScalar(FoodRole.accompaniment, FoodRole.primary) ?? 0.55;
          finalScalar = (baseScale * patternScalar).clamp(0.3, 2.5);
        } else {
          finalScalar = getPatternScalar(role, hasAccompaniment ? FoodRole.accompaniment : null);
        }
      } else if (anchor == PortionAnchor.curryAnchored && hasPrimary && hasAccompaniment) {
        if (role == FoodRole.primary) {
          // Carbs portion scales to finish accompaniment curries.
          // Scaled curries are used to calculate the accompanimentServings.
          final accPatternScalar = getPatternScalar(FoodRole.accompaniment, FoodRole.primary) ?? 1.40;
          final scaledAccServings = baseAccServings * accPatternScalar;

          final expectedCarbServings = scaledAccServings * 1.5;
          final baseScale = (expectedCarbServings / baseCarbServings).clamp(0.3, 3.0);
          final patternScalar = getPatternScalar(FoodRole.primary, FoodRole.accompaniment) ?? 0.60;
          finalScalar = (baseScale * patternScalar).clamp(0.3, 2.5);
        } else if (role == FoodRole.accompaniment) {
          finalScalar = getPatternScalar(FoodRole.accompaniment, FoodRole.primary) ?? 1.40;
        } else {
          finalScalar = getPatternScalar(role, hasPrimary ? FoodRole.primary : null);
        }
      } else {
        // Balanced / Solo / No-profile: standard scalar logic
        final context = (role == FoodRole.primary)
            ? (hasAccompaniment ? FoodRole.accompaniment : null)
            : (role == FoodRole.accompaniment)
                ? (hasPrimary ? FoodRole.primary : null)
                : null;
        finalScalar = getPatternScalar(role, context);
      }

      if (finalScalar != null) {
        result.add(item.withScalar(finalScalar));
        if (kDebugMode) {
          _debugLog('[Pipeline Pass] 🧠 Scalar ${finalScalar.toStringAsFixed(2)}× applied to "${item.name}" ($role)');
        }
      } else {
        // Mark as processed/scalar-applied even if 1.0 to protect against double application
        result.add(item.withScalar(1.0));
      }
    }

    return result;
  }
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
