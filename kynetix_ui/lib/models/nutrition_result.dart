import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../services/mock_estimation_service.dart'
    show NutrientRange, FoodItem, EstimationResult;
import '../services/user_nutrition_memory.dart';
import '../services/unit_normalizer.dart';


double _safe(double v, [int precision = 1]) {
  if (v.isNaN || v.isInfinite) return 0.0;
  return double.tryParse(v.toStringAsFixed(precision)) ?? 0.0;
}

// ─── Estimation mode ──────────────────────────────────────────────────────────

enum EstimationMode {
  directQuantity,     // explicit qty — 400ml milk, 4 egg whites
  contextualIntake,   // sabzi/dal eaten alongside roti/rice
  packagedKnown,      // milk packet, bread, oats, whey
  outsideRestaurant;  // burger, pizza, biryani

  String toJson() => switch (this) {
        EstimationMode.directQuantity   => 'direct_quantity',
        EstimationMode.contextualIntake => 'contextual_intake',
        EstimationMode.packagedKnown    => 'packaged_known',
        EstimationMode.outsideRestaurant => 'outside_restaurant',
      };

  static EstimationMode fromString(String s) => switch (s) {
        'direct_quantity'    => EstimationMode.directQuantity,
        'contextual_intake'  => EstimationMode.contextualIntake,
        'packaged_known'     => EstimationMode.packagedKnown,
        'outside_restaurant' => EstimationMode.outsideRestaurant,
        _                    => EstimationMode.contextualIntake,
      };
}

// ─── EstimationAudit ─────────────────────────────────────────────────────────

class EstimationAudit {
  final String memoryMatchUsed;       // e.g. "memory_exact: 400 ml milk"
  final String portionAssumption;     // e.g. "PortionAnchor.carbAnchored"
  final String environmentAssumption; // e.g. "mess context, oil assumed"
  final String finalChoiceReason;     // e.g. "local pipeline exact match"
  final List<String> uncertaintyFactors; // e.g. ["restaurant food", "no quantity given"]
  final double pipelineConfidence;
  final String memoryPriorityLevel;   // e.g. "User Memory", "Saved Meal", "Branded Food", "AI Estimate"

  const EstimationAudit({
    required this.memoryMatchUsed,
    required this.portionAssumption,
    required this.environmentAssumption,
    required this.finalChoiceReason,
    required this.uncertaintyFactors,
    required this.pipelineConfidence,
    required this.memoryPriorityLevel,
  });

  Map<String, dynamic> toJson() => {
        'memoryMatchUsed': memoryMatchUsed,
        'portionAssumption': portionAssumption,
        'environmentAssumption': environmentAssumption,
        'finalChoiceReason': finalChoiceReason,
        'uncertaintyFactors': uncertaintyFactors,
        'pipelineConfidence': pipelineConfidence,
        'memoryPriorityLevel': memoryPriorityLevel,
      };

  factory EstimationAudit.fromJson(Map<String, dynamic> j) => EstimationAudit(
        memoryMatchUsed: j['memoryMatchUsed'] as String? ?? '',
        portionAssumption: j['portionAssumption'] as String? ?? '',
        environmentAssumption: j['environmentAssumption'] as String? ?? '',
        finalChoiceReason: j['finalChoiceReason'] as String? ?? '',
        uncertaintyFactors: List<String>.from(j['uncertaintyFactors'] as List<dynamic>? ?? const []),
        pipelineConfidence: (j['pipelineConfidence'] as num?)?.toDouble() ?? 0.0,
        memoryPriorityLevel: j['memoryPriorityLevel'] as String? ?? 'AI Estimate',
      );
}

// ─── NutritionItem ────────────────────────────────────────────────────────────

class NutritionItem {
  final String         name;
  final double         quantity;
  final String         unit;
  final bool           estimated;
  final EstimationMode mode;
  final NutrientRange  calories;
  final NutrientRange  protein;
  final NutrientRange? carbohydrates;
  final NutrientRange? fat;
  final NutrientRange? fiber;
  final NutrientRange? sugar;
  final NutrientRange? saturatedFat;
  final NutrientRange? sodium;
  final bool           eatingPatternScalarApplied;

  const NutritionItem({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.estimated,
    required this.mode,
    required this.calories,
    required this.protein,
    this.carbohydrates,
    this.fat,
    this.fiber,
    this.sugar,
    this.saturatedFat,
    this.sodium,
    this.eatingPatternScalarApplied = false,
  });

  Map<String, dynamic> toJson() => {
        'name':           name,
        'quantity':       quantity,
        'unit':           unit,
        'estimated':      estimated,
        'estimationMode': mode.toJson(),
        'calories':       {'min': calories.min, 'max': calories.max},
        'protein':        {'min': protein.min,  'max': protein.max},
        if (carbohydrates != null) 'carbohydrates': {'min': carbohydrates!.min, 'max': carbohydrates!.max},
        if (fat != null) 'fat': {'min': fat!.min, 'max': fat!.max},
        if (fiber != null) 'fiber': {'min': fiber!.min, 'max': fiber!.max},
        if (sugar != null) 'sugar': {'min': sugar!.min, 'max': sugar!.max},
        if (saturatedFat != null) 'saturatedFat': {'min': saturatedFat!.min, 'max': saturatedFat!.max},
        if (sodium != null) 'sodium': {'min': sodium!.min, 'max': sodium!.max},
        'eatingPatternScalarApplied': eatingPatternScalarApplied,
      };

  factory NutritionItem.fromJson(Map<String, dynamic> j) {
    final name = j['name'] as String? ?? '';
    final calories = _range(j['calories']);
    final protein = _range(j['protein']);
    final calMid = (calories.min + calories.max) / 2;
    final proMid = (protein.min + protein.max) / 2;

    return NutritionItem(
      name:      name,
      quantity:  (j['quantity'] as num?)?.toDouble() ?? 1.0,
      unit:      j['unit']     as String? ?? 'serving',
      estimated: j['estimated'] as bool? ?? false,
      mode:      EstimationMode.fromString(j['estimationMode'] as String? ?? ''),
      calories:  calories,
      protein:   protein,
      carbohydrates: j['carbohydrates'] != null
          ? _range(j['carbohydrates'])
          : NutritionResult.estimateCarbsLocally(calMid, proMid, name),
      fat: j['fat'] != null
          ? _range(j['fat'])
          : NutritionResult.estimateFatLocally(calMid, proMid, name),
      fiber: j['fiber'] != null
          ? _range(j['fiber'])
          : NutritionResult.estimateFiberLocally(calMid, name),
      sugar: j['sugar'] != null ? _range(j['sugar']) : null,
      saturatedFat:  j['saturatedFat'] != null ? _range(j['saturatedFat']) : null,
      sodium:        j['sodium'] != null ? _range(j['sodium']) : null,
      eatingPatternScalarApplied: j['eatingPatternScalarApplied'] as bool? ?? false,
    );
  }

  static NutrientRange _range(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      return NutrientRange(
        min: (raw['min'] as num?)?.toDouble() ?? 0,
        max: (raw['max'] as num?)?.toDouble() ?? 0,
      );
    }
    return const NutrientRange(min: 0, max: 0);
  }

  NutritionItem normalizedUncertainty() => NutritionItem(
        name: name,
        quantity: quantity,
        unit: unit,
        estimated: estimated,
        mode: mode,
        calories: _normalizeRange(calories),
        protein: _normalizeRange(protein),
        carbohydrates: carbohydrates != null ? _normalizeRange(carbohydrates!) : null,
        fat: fat != null ? _normalizeRange(fat!) : null,
        fiber: fiber != null ? _normalizeRange(fiber!) : null,
        sugar: sugar != null ? _normalizeRange(sugar!) : null,
        saturatedFat: saturatedFat != null ? _normalizeRange(saturatedFat!) : null,
        sodium: sodium != null ? _normalizeRange(sodium!) : null,
        eatingPatternScalarApplied: eatingPatternScalarApplied,
      );

  static NutrientRange _normalizeRange(NutrientRange r) {
    final diff = (r.max - r.min).abs();
    final meaningful = diff >= 5 && (r.max <= 0 || diff / r.max >= 0.04);
    if (meaningful) return r;
    final mid = ((r.min + r.max) / 2);
    final collapsed = _safe(mid);
    return NutrientRange(min: collapsed, max: collapsed);
  }

  NutritionItem withScalar(double scalar) {
    return NutritionItem(
      name: name,
      quantity: quantity,
      unit: unit,
      estimated: estimated,
      mode: mode,
      calories: NutrientRange(min: calories.min * scalar, max: calories.max * scalar),
      protein: NutrientRange(min: protein.min * scalar, max: protein.max * scalar),
      carbohydrates: carbohydrates != null
          ? NutrientRange(min: carbohydrates!.min * scalar, max: carbohydrates!.max * scalar)
          : null,
      fat: fat != null
          ? NutrientRange(min: fat!.min * scalar, max: fat!.max * scalar)
          : null,
      fiber: fiber != null
          ? NutrientRange(min: fiber!.min * scalar, max: fiber!.max * scalar)
          : null,
      sugar: sugar != null
          ? NutrientRange(min: sugar!.min * scalar, max: sugar!.max * scalar)
          : null,
      saturatedFat: saturatedFat != null
          ? NutrientRange(min: saturatedFat!.min * scalar, max: saturatedFat!.max * scalar)
          : null,
      sodium: sodium != null
          ? NutrientRange(min: sodium!.min * scalar, max: sodium!.max * scalar)
          : null,
      eatingPatternScalarApplied: true,
    );
  }
}

// ─── NutritionResult ─────────────────────────────────────────────────────────

class NutritionResult {
  final String              canonicalMeal;
  final List<NutritionItem> items;
  final NutrientRange       calories;
  final NutrientRange       protein;
  final NutrientRange?       carbohydrates;
  final NutrientRange?       fat;
  final NutrientRange?       fiber;
  final NutrientRange?       sugar;
  final NutrientRange?       saturatedFat;
  final NutrientRange?       sodium;

  final int?                 mealQualityScore;
  final String?              mealQualityExplanation;
  final String?              mealQualityPositive;
  final String?              mealQualityImprovement;

  final double              confidence;
  final List<String>        warnings;
  final String?             coachSummary;
  final List<String>        bestNextFoods;
  final String?             mealCategory;
  final String?             mealDensity;
  final List<String>        riskFlags;
  /// 'ai', 'cache', 'local_fallback', or 'user_override'
  final String              source;
  final DateTime            createdAt;
  /// Only set when source == 'local_fallback'. Explains why Gemini was skipped.
  final String?             fallbackReason;

  /// When true the user has manually edited one or more macros.
  /// The pipeline MUST NOT overwrite any macro on a locked result.
  final bool                macrosLockedByUser;
  final bool                userCorrected;
  final EstimationAudit?    estimationAudit;


  const NutritionResult({
    required this.canonicalMeal,
    required this.items,
    required this.calories,
    required this.protein,
    required this.confidence,
    required this.warnings,
    this.coachSummary,
    this.bestNextFoods = const [],
    this.mealCategory,
    this.mealDensity,
    this.riskFlags = const [],
    required this.source,
    required this.createdAt,
    this.fallbackReason,
    this.carbohydrates,
    this.fat,
    this.fiber,
    this.sugar,
    this.saturatedFat,
    this.sodium,
    this.mealQualityScore,
    this.mealQualityExplanation,
    this.mealQualityPositive,
    this.mealQualityImprovement,
    this.macrosLockedByUser = false,
    this.userCorrected = false,
    this.estimationAudit,
  });

  NutritionResult copyWith({
    String? source,
    String? fallbackReason,
    NutrientRange? calories,
    NutrientRange? protein,
    NutrientRange? carbohydrates,
    NutrientRange? fat,
    NutrientRange? fiber,
    NutrientRange? sugar,
    NutrientRange? saturatedFat,
    NutrientRange? sodium,
    int? mealQualityScore,
    String? mealQualityExplanation,
    String? mealQualityPositive,
    String? mealQualityImprovement,
    bool? macrosLockedByUser,
    bool? userCorrected,
    EstimationAudit? estimationAudit,
  }) => NutritionResult(
        canonicalMeal:  canonicalMeal,
        items:          items,
        calories:       calories ?? this.calories,
        protein:        protein ?? this.protein,
        confidence:     confidence,
        warnings:       warnings,
        coachSummary:   coachSummary,
        bestNextFoods:  bestNextFoods,
        mealCategory:   mealCategory,
        mealDensity:    mealDensity,
        riskFlags:      riskFlags,
        source:         source ?? this.source,
        createdAt:      createdAt,
        fallbackReason: fallbackReason ?? this.fallbackReason,
        carbohydrates:  carbohydrates ?? this.carbohydrates,
        fat:            fat ?? this.fat,
        fiber:          fiber ?? this.fiber,
        sugar:          sugar ?? this.sugar,
        saturatedFat:   saturatedFat ?? this.saturatedFat,
        sodium:         sodium ?? this.sodium,
        mealQualityScore: mealQualityScore ?? this.mealQualityScore,
        mealQualityExplanation: mealQualityExplanation ?? this.mealQualityExplanation,
        mealQualityPositive: mealQualityPositive ?? this.mealQualityPositive,
        mealQualityImprovement: mealQualityImprovement ?? this.mealQualityImprovement,
        macrosLockedByUser: macrosLockedByUser ?? this.macrosLockedByUser,
        userCorrected:  userCorrected ?? this.userCorrected,
        estimationAudit: estimationAudit ?? this.estimationAudit,
      );

  /// Guardrails-specific copy — replaces macros + warnings without touching items.
  /// Respects [macrosLockedByUser]: if true, returns [this] unchanged so that
  /// guardrails cannot clobber user-edited values.
  NutritionResult copyWithMacros({
    required NutrientRange calories,
    required NutrientRange protein,
    required List<String>  warnings,
    NutrientRange? carbohydrates,
    NutrientRange? fat,
    NutrientRange? fiber,
    NutrientRange? sugar,
    NutrientRange? saturatedFat,
    NutrientRange? sodium,
  }) {
    // Never overwrite user-edited macros.
    if (macrosLockedByUser) return this;
    return NutritionResult(
        canonicalMeal:  canonicalMeal,
        items:          items,
        calories:       calories,
        protein:        protein,
        confidence:     confidence,
        warnings:       warnings,
        coachSummary:   coachSummary,
        bestNextFoods:  bestNextFoods,
        mealCategory:   mealCategory,
        mealDensity:    mealDensity,
        riskFlags:      riskFlags,
        source:         source,
        createdAt:      createdAt,
        fallbackReason: fallbackReason,
        carbohydrates:  carbohydrates ?? this.carbohydrates,
        fat:            fat ?? this.fat,
        fiber:          fiber ?? this.fiber,
        sugar:          sugar ?? this.sugar,
        saturatedFat:   saturatedFat ?? this.saturatedFat,
        sodium:         sodium ?? this.sodium,
        mealQualityScore: mealQualityScore,
        mealQualityExplanation: mealQualityExplanation,
        mealQualityPositive: mealQualityPositive,
        mealQualityImprovement: mealQualityImprovement,
        macrosLockedByUser: macrosLockedByUser,
        userCorrected:  userCorrected,
        estimationAudit: estimationAudit,
      );
  }

  /// When macros are locked by the user we skip range normalization to preserve
  /// the exact values they entered (min == max, no artificial spread).
  NutritionResult normalizedUncertainty() {
    if (macrosLockedByUser) return this;
    return NutritionResult(
        canonicalMeal: canonicalMeal,
        items: items.map((i) => i.normalizedUncertainty()).toList(),
        calories: NutritionItem._normalizeRange(calories),
        protein: NutritionItem._normalizeRange(protein),
        confidence: confidence,
        warnings: warnings,
        coachSummary: coachSummary,
        bestNextFoods: bestNextFoods,
        mealCategory: mealCategory,
        mealDensity: mealDensity,
        riskFlags: riskFlags,
        source: source,
        createdAt: createdAt,
        fallbackReason: fallbackReason,
        carbohydrates: carbohydrates != null ? NutritionItem._normalizeRange(carbohydrates!) : null,
        fat: fat != null ? NutritionItem._normalizeRange(fat!) : null,
        fiber: fiber != null ? NutritionItem._normalizeRange(fiber!) : null,
        sugar: sugar != null ? NutritionItem._normalizeRange(sugar!) : null,
        saturatedFat: saturatedFat != null ? NutritionItem._normalizeRange(saturatedFat!) : null,
        sodium: sodium != null ? NutritionItem._normalizeRange(sodium!) : null,
        mealQualityScore: mealQualityScore,
        mealQualityExplanation: mealQualityExplanation,
        mealQualityPositive: mealQualityPositive,
        mealQualityImprovement: mealQualityImprovement,
        macrosLockedByUser: macrosLockedByUser,
        estimationAudit: estimationAudit,
      );
  }

  NutritionResult rebuildFromIngredientsAndOverrides() {
    if (items.isEmpty) return this;

    bool hasOverride = false;
    final updatedItems = <NutritionItem>[];

    for (final item in items) {
      final override = UserNutritionMemory.instance.lookup(item.name);
      final storedUnit = UserNutritionMemory.instance.storedUnit(item.name);
      
      if (override != null &&
          (storedUnit == null || UnitNormalizer.sameCategory(storedUnit, item.unit))) {
        hasOverride = true;
        final scale = item.quantity.clamp(0.0, double.infinity);
        final finalScale = scale > 0 ? scale : 1.0;

        final calVal = override.calories.min * finalScale;
        final proVal = override.protein.min * finalScale;
        final carbVal = override.carbohydrates != null ? override.carbohydrates!.min * finalScale : null;
        final fatVal = override.fat != null ? override.fat!.min * finalScale : null;
        final fiberVal = override.fiber != null ? override.fiber!.min * finalScale : null;

        updatedItems.add(NutritionItem(
          name: item.name,
          quantity: item.quantity,
          unit: item.unit,
          estimated: false,
          mode: item.mode,
          calories: NutrientRange(min: calVal, max: calVal),
          protein: NutrientRange(min: proVal, max: proVal),
          carbohydrates: carbVal != null ? NutrientRange(min: carbVal, max: carbVal) : null,
          fat: fatVal != null ? NutrientRange(min: fatVal, max: fatVal) : null,
          fiber: fiberVal != null ? NutrientRange(min: fiberVal, max: fiberVal) : null,
          sugar: item.sugar,
          saturatedFat: item.saturatedFat,
          sodium: item.sodium,
          eatingPatternScalarApplied: true,
        ));
      } else {
        updatedItems.add(item);
      }
    }

    if (!hasOverride) return this;

    double sumCalMin = 0, sumCalMax = 0;
    double sumProMin = 0, sumProMax = 0;
    double? carbMin, carbMax, fatMin, fatMax, fibMin, fibMax;

    for (final item in updatedItems) {
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
    }

    final midCal = (sumCalMin + sumCalMax) / 2;
    final midPro = (sumProMin + sumProMax) / 2;
    final score = NutritionResult.calculateLocalQualityScore(
      midCal,
      midPro,
      canonicalMeal,
      carbs: carbMin != null && carbMax != null ? (carbMin + carbMax) / 2 : null,
      fat: fatMin != null && fatMax != null ? (fatMin + fatMax) / 2 : null,
      fiber: fibMin != null && fibMax != null ? (fibMin + fibMax) / 2 : null,
    );

    return NutritionResult(
      canonicalMeal: canonicalMeal,
      items: updatedItems,
      calories: NutrientRange(min: sumCalMin, max: sumCalMax),
      protein: NutrientRange(min: sumProMin, max: sumProMax),
      confidence: 1.0,
      warnings: const [],
      source: 'user_override',
      createdAt: createdAt,
      fallbackReason: null,
      carbohydrates: carbMin != null ? NutrientRange(min: carbMin, max: carbMax!) : null,
      fat: fatMin != null ? NutrientRange(min: fatMin, max: fatMax!) : null,
      fiber: fibMin != null ? NutrientRange(min: fibMin, max: fibMax!) : null,
      sugar: sugar,
      saturatedFat: saturatedFat,
      sodium: sodium,
      mealQualityScore: score,
      mealQualityExplanation: NutritionResult.getLocalQualityExplanation(score, canonicalMeal),
      mealQualityPositive: NutritionResult.getLocalQualityPositive(score, canonicalMeal),
      mealQualityImprovement: NutritionResult.getLocalQualityImprovement(score, canonicalMeal),
      macrosLockedByUser: true,
      userCorrected: true,
      estimationAudit: estimationAudit,
    );
  }


  double get primaryCaloriesEstimate => ((calories.min + calories.max) / 2);
  double get primaryProteinEstimate => ((protein.min + protein.max) / 2);
  bool get hasMeaningfulCalorieRange => (calories.max - calories.min).abs() >= 20;
  bool get hasMeaningfulProteinRange => (protein.max - protein.min).abs() >= 4;
  bool get shouldShowRange => confidence < 0.84 || hasMeaningfulCalorieRange || hasMeaningfulProteinRange;

  String get confidenceLabel {
    if (confidence >= 0.86) return 'High confidence';
    if (confidence >= 0.62) return 'Approximate';
    return 'Lower confidence';
  }

  String get estimateLabel => confidence >= 0.84 ? 'Realistic estimate' : 'Approximate estimate';

  List<String> get userFacingWarnings {
    final mapped = <String>[];
    for (final warning in warnings) {
      if (warning.startsWith('Applied milk floor')) {
        mapped.add('Milk quantity was counted conservatively.');
      } else if (warning.contains('paneer-thali')) {
        mapped.add('Paneer-heavy meals were treated as calorie-dense.');
      } else if (warning.startsWith('Applied paneer floor')) {
        mapped.add('Paneer was treated as fully eaten.');
      } else if (warning.contains('creamy-gravy') || warning.contains('gravy floor')) {
        mapped.add('Rich gravy dishes were estimated conservatively.');
      } else if (warning.contains('biryani floor')) {
        mapped.add('Biryani was treated as a calorie-dense mixed meal.');
      } else if (warning.contains('fried-food')) {
        mapped.add('Fried food was estimated conservatively.');
      } else if (warning.contains('peanut-butter')) {
        mapped.add('Peanut butter was counted using dense serving defaults.');
      } else if (warning.contains('restaurant uplift')) {
        mapped.add('Restaurant food was estimated more conservatively.');
      } else if (warning.contains('meal-density floor')) {
        mapped.add('This looked denser than a typical home-style portion.');
      } else if (warning.startsWith('Estimated one item')) {
        mapped.add('One item used a typical serving size.');
      } else if (warning.startsWith('Used standard portions')) {
        mapped.add('Some parts of this meal used standard serving assumptions.');
      } else if (warning.startsWith('Small portion')) {
        mapped.add('Small quantity wording was taken into account.');
      } else if (warning.startsWith('Large portion')) {
        mapped.add('Larger quantity wording was taken into account.');
      } else if (!warning.startsWith('Applied ')) {
        mapped.add(warning);
      }
    }
    return mapped.toSet().toList(growable: false);
  }

  // ── Bridge to legacy EstimationResult ──────────────────────────────────────

  EstimationResult toEstimationResult() => EstimationResult(
        items: items
            .map((i) => FoodItem(
                  name:     i.name,
                  calories: i.calories,
                  protein:  i.protein,
                ))
            .toList(),
        calories:   calories,
        protein:    protein,
        confidence: confidence,
        warnings:   warnings,
      );

  // ── Local Fallback Estimations ───────────────────────────────────────────

  static NutrientRange estimateCarbsLocally(double cal, double pro, String text) {
    final lowerText = text.toLowerCase();
    double ratio = 0.55; // default 55% of remaining calories to carbs
    if (lowerText.contains('rice') || lowerText.contains('roti') || lowerText.contains('bread') || lowerText.contains('banana') || lowerText.contains('oats')) {
      ratio = 0.75;
    } else if (lowerText.contains('paneer') || lowerText.contains('oil') || lowerText.contains('butter') || lowerText.contains('avocado')) {
      ratio = 0.30;
    }
    final remainingCal = (cal - pro * 4).clamp(0.0, double.infinity);
    final carbsGrams = (remainingCal * ratio / 4).clamp(0.0, double.infinity);
    return NutrientRange(min: _safe(carbsGrams * 0.9), max: _safe(carbsGrams * 1.1));
  }

  static NutrientRange estimateFatLocally(double cal, double pro, String text) {
    final lowerText = text.toLowerCase();
    double ratio = 0.45; // default 45% of remaining calories to fat
    if (lowerText.contains('rice') || lowerText.contains('roti') || lowerText.contains('bread') || lowerText.contains('banana') || lowerText.contains('oats')) {
      ratio = 0.25;
    } else if (lowerText.contains('paneer') || lowerText.contains('oil') || lowerText.contains('butter') || lowerText.contains('avocado') || lowerText.contains('cheese')) {
      ratio = 0.70;
    }
    final remainingCal = (cal - pro * 4).clamp(0.0, double.infinity);
    final fatGrams = (remainingCal * ratio / 9).clamp(0.0, double.infinity);
    return NutrientRange(min: _safe(fatGrams * 0.9), max: _safe(fatGrams * 1.1));
  }

  static NutrientRange estimateFiberLocally(double cal, String text) {
    final lowerText = text.toLowerCase();
    double fiberGrams = 1.5;
    if (lowerText.contains('salad') || lowerText.contains('broccoli') || lowerText.contains('vegetable') || lowerText.contains('greens')) {
      fiberGrams = 6.0;
    } else if (lowerText.contains('oats') || lowerText.contains('apple') || lowerText.contains('lentils') || lowerText.contains('beans')) {
      fiberGrams = 4.5;
    } else if (cal > 500) {
      fiberGrams = 3.0;
    }
    return NutrientRange(min: _safe(fiberGrams * 0.8), max: _safe(fiberGrams * 1.2));
  }

  static int calculateLocalQualityScore(
    double cal,
    double pro,
    String text, {
    double? carbs,
    double? fat,
    double? fiber,
  }) {
    if (cal <= 0) {
      debugPrint('[calculateLocalQualityScore] Warning: Quality score calculated for zero/low calorie entry (text: "$text").');
    }
    final lowerText = text.toLowerCase();
    double score = 55.0; // base score

    if (cal > 0) {
      final proteinCalRatio = (pro * 4) / cal;
      if (proteinCalRatio >= 0.3) {
        score += 20.0; // protein bonus
      } else if (proteinCalRatio >= 0.2) {
        score += 10.0;
      } else if (proteinCalRatio >= 0.15) {
        score += 5.0;
      }
    }

    if (fiber != null) {
      if (fiber >= 5.0) {
        score += 10.0;
      } else if (fiber >= 3.0) {
        score += 5.0;
      }
    }

    if (lowerText.contains('salad') ||
        lowerText.contains('vegetable') ||
        lowerText.contains('veg') || // handles veggies, vegetables, etc.
        lowerText.contains('sabzi') ||
        lowerText.contains('broccoli') ||
        lowerText.contains('spinach') ||
        lowerText.contains('greens')) {
      score += 10.0;
    }

    if (lowerText.contains('chicken') ||
        lowerText.contains('fish') ||
        lowerText.contains('tofu') ||
        lowerText.contains('paneer') ||
        lowerText.contains('egg') ||
        lowerText.contains('oats') ||
        lowerText.contains('whey') ||
        lowerText.contains('protein') ||
        lowerText.contains('sprouts')) {
      score += 5.0;
    }

    double penalties = 0.0;
    if (lowerText.contains('pizza')) {
      penalties += 30.0;
    }
    if (lowerText.contains('burger')) {
      penalties += 25.0;
    }
    if (lowerText.contains('fries') || lowerText.contains('fried')) {
      penalties += 20.0;
    }
    if (lowerText.contains('soda') ||
        lowerText.contains('coke') ||
        lowerText.contains('cola') ||
        lowerText.contains('pepsi')) {
      penalties += 15.0;
    }
    if (lowerText.contains('sugar') ||
        lowerText.contains('cookie') ||
        lowerText.contains('chocolate') ||
        lowerText.contains('cake') ||
        lowerText.contains('donut') ||
        lowerText.contains('candy') ||
        lowerText.contains('sweet') ||
        lowerText.contains('ice cream')) {
      penalties += 15.0;
    }

    if (penalties > 35.0) {
      penalties = 35.0;
    }
    score -= penalties;

    return score.clamp(20.0, 100.0).round();
  }

  static String getLocalQualityExplanation(int score, String text) {
    final lowerText = text.toLowerCase();
    if (score >= 90) {
      return 'Exceptional choice! Highly nutritious, protein-dense, and rich in whole foods.';
    } else if (score >= 75) {
      return 'Balanced meal with a solid macronutrient profile and good nutritional value.';
    } else if (score >= 50) {
      return 'Moderate nutrition score. Consider adding more lean protein or vegetables to improve balance.';
    } else {
      if (lowerText.contains('pizza') || lowerText.contains('burger') || lowerText.contains('fries')) {
        return 'High in saturated fats and fast-digesting carbohydrates. Pair with a high-protein source next time.';
      }
      return 'Lower nutritional quality. High in processed ingredients, simple sugars, or refined fats. Try to replace with whole grains or lean protein options.';
    }
  }

  static String getLocalQualityPositive(int score, String text) {
    final lowerText = text.toLowerCase();
    if (lowerText.contains('salad') || lowerText.contains('vegetable') || lowerText.contains('broccoli')) {
      return 'Contains micronutrient-rich vegetables.';
    }
    if (lowerText.contains('egg') || lowerText.contains('chicken') || lowerText.contains('fish') || lowerText.contains('protein')) {
      return 'High in high-quality protein to support muscle synthesis.';
    }
    if (lowerText.contains('oats') || lowerText.contains('apple') || lowerText.contains('beans')) {
      return 'Includes complex carbohydrates and healthy dietary fiber.';
    }
    if (score >= 75) {
      return 'Good macronutrient balance with clean fuel.';
    }
    return 'Quick energy source to fuel your immediate activities.';
  }

  static String getLocalQualityImprovement(int score, String text) {
    final lowerText = text.toLowerCase();
    if (lowerText.contains('pizza') || lowerText.contains('burger') || lowerText.contains('fries') || lowerText.contains('fried')) {
      return 'Reduce intake of deep-fried items to lower saturated fat consumption.';
    }
    if (lowerText.contains('sugar') || lowerText.contains('soda') || lowerText.contains('cookie') || lowerText.contains('chocolate')) {
      return 'Limit added sugars to prevent glycemic spikes and crashes.';
    }
    if (!lowerText.contains('chicken') && !lowerText.contains('egg') && !lowerText.contains('fish') && !lowerText.contains('paneer') && !lowerText.contains('whey') && !lowerText.contains('tofu')) {
      return 'Add a lean protein source (e.g. egg whites, chicken, tofu) to boost protein density.';
    }
    if (!lowerText.contains('salad') && !lowerText.contains('vegetable') && !lowerText.contains('broccoli')) {
      return 'Incorporate some leafy green vegetables for crucial fiber and micronutrients.';
    }
    return 'Control portion size to align perfectly with your daily targets.';
  }

  factory NutritionResult.fromEstimationResult(
    EstimationResult r,
    String rawInput,
  ) {
    final calVal = r.calories.mid;
    final proVal = r.protein.mid;
    final carbs = estimateCarbsLocally(calVal, proVal, rawInput);
    final fat = estimateFatLocally(calVal, proVal, rawInput);
    final fiber = estimateFiberLocally(calVal, rawInput);
    final score = calculateLocalQualityScore(
      calVal,
      proVal,
      rawInput,
      carbs: carbs.mid,
      fat: fat.mid,
      fiber: fiber.mid,
    );
    
    return NutritionResult(
      canonicalMeal: rawInput,
      items: r.items
          .map((fi) => NutritionItem(
                name:      fi.name,
                quantity:  1,
                unit:      'serving',
                estimated: true,
                mode:      EstimationMode.contextualIntake,
                calories:  fi.calories,
                protein:   fi.protein,
                carbohydrates: estimateCarbsLocally(fi.calories.mid, fi.protein.mid, fi.name),
                fat:           estimateFatLocally(fi.calories.mid, fi.protein.mid, fi.name),
                fiber:         estimateFiberLocally(fi.calories.mid, fi.name),
              ))
          .toList(),
      calories:   r.calories,
      protein:    r.protein,
      confidence: r.confidence,
      warnings:   r.warnings,
      source:     'local_fallback',
      createdAt:  DateTime.now(),
      carbohydrates: carbs,
      fat:            fat,
      fiber:          fiber,
      mealQualityScore: score,
      mealQualityExplanation: getLocalQualityExplanation(score, rawInput),
      mealQualityPositive: getLocalQualityPositive(score, rawInput),
      mealQualityImprovement: getLocalQualityImprovement(score, rawInput),
      userCorrected: false,
    );
  }

  factory NutritionResult.createCustom({
    required String canonicalMeal,
    required double calories,
    required double protein,
    double? carbohydrates,
    double? fat,
    double? fiber,
    required String source,
    bool userCorrected = true,
    List<NutritionItem>? items,
  }) {
    final carbsRange = carbohydrates != null
        ? NutrientRange(min: carbohydrates, max: carbohydrates)
        : estimateCarbsLocally(calories, protein, canonicalMeal);
    final fatRange = fat != null
        ? NutrientRange(min: fat, max: fat)
        : estimateFatLocally(calories, protein, canonicalMeal);
    final fiberRange = fiber != null
        ? NutrientRange(min: fiber, max: fiber)
        : estimateFiberLocally(calories, canonicalMeal);

    final score = calculateLocalQualityScore(
      calories,
      protein,
      canonicalMeal,
      carbs: carbsRange.mid,
      fat: fatRange.mid,
      fiber: fiberRange.mid,
    );

    return NutritionResult(
      canonicalMeal: canonicalMeal,
      items: items ?? [
        NutritionItem(
          name:      canonicalMeal,
          quantity:  1,
          unit:      'serving',
          estimated: false,
          mode:      EstimationMode.packagedKnown,
          calories:  NutrientRange(min: calories, max: calories),
          protein:   NutrientRange(min: protein,  max: protein),
          carbohydrates: carbsRange,
          fat:           fatRange,
          fiber:         fiberRange,
        ),
      ],
      calories:      NutrientRange(min: calories, max: calories),
      protein:       NutrientRange(min: protein,  max: protein),
      confidence:    1.0,
      warnings:      const [],
      source:        source,
      createdAt:     DateTime.now(),
      carbohydrates: carbsRange,
      fat:            fatRange,
      fiber:          fiberRange,
      mealQualityScore: score,
      mealQualityExplanation: getLocalQualityExplanation(score, canonicalMeal),
      mealQualityPositive: getLocalQualityPositive(score, canonicalMeal),
      mealQualityImprovement: getLocalQualityImprovement(score, canonicalMeal),
      macrosLockedByUser: userCorrected,
      userCorrected: userCorrected,
    );
  }

  // ── JSON serialization (for SharedPreferences) ────────────────────────────

  Map<String, dynamic> toJson() => {
        'canonicalMeal': canonicalMeal,
        'items':         items.map((i) => i.toJson()).toList(),
        'calories':      {'min': calories.min, 'max': calories.max},
        'protein':       {'min': protein.min,  'max': protein.max},
        if (coachSummary != null) 'coachSummary': coachSummary,
        if (bestNextFoods.isNotEmpty) 'bestNextFoods': bestNextFoods,
        if (mealCategory != null) 'mealCategory': mealCategory,
        if (mealDensity != null) 'mealDensity': mealDensity,
        if (riskFlags.isNotEmpty) 'riskFlags': riskFlags,
        'confidence':    confidence,
        'warnings':      warnings,
        'source':        source,
        'createdAt':     createdAt.toIso8601String(),
        if (fallbackReason != null) 'fallbackReason': fallbackReason,
        if (carbohydrates != null) 'carbohydrates': {'min': carbohydrates!.min, 'max': carbohydrates!.max},
        if (fat != null) 'fat': {'min': fat!.min, 'max': fat!.max},
        if (fiber != null) 'fiber': {'min': fiber!.min, 'max': fiber!.max},
        if (sugar != null) 'sugar': {'min': sugar!.min, 'max': sugar!.max},
        if (saturatedFat != null) 'saturatedFat': {'min': saturatedFat!.min, 'max': saturatedFat!.max},
        if (sodium != null) 'sodium': {'min': sodium!.min, 'max': sodium!.max},
        if (mealQualityScore != null) 'mealQualityScore': mealQualityScore,
        if (mealQualityExplanation != null) 'mealQualityExplanation': mealQualityExplanation,
        if (mealQualityPositive != null) 'mealQualityPositive': mealQualityPositive,
        if (mealQualityImprovement != null) 'mealQualityImprovement': mealQualityImprovement,
        if (macrosLockedByUser) 'macrosLockedByUser': true,
        if (userCorrected) 'userCorrected': true,
        if (estimationAudit != null) 'estimationAudit': estimationAudit!.toJson(),
      };

  factory NutritionResult.fromJson(Map<String, dynamic> j) {
    final cal = j['calories'] as Map<String, dynamic>? ?? {};
    final pro = j['protein']  as Map<String, dynamic>? ?? {};
    final calories = NutrientRange(
      min: (cal['min'] as num?)?.toDouble() ?? 0,
      max: (cal['max'] as num?)?.toDouble() ?? 0,
    );
    final protein = NutrientRange(
      min: (pro['min'] as num?)?.toDouble() ?? 0,
      max: (pro['max'] as num?)?.toDouble() ?? 0,
    );

    final items = (j['items'] as List<dynamic>? ?? [])
        .map((e) => NutritionItem.fromJson(e as Map<String, dynamic>))
        .toList();

    double carbMin = 0, carbMax = 0;
    double fatMin = 0, fatMax = 0;
    double fiberMin = 0, fiberMax = 0;
    double sugarMin = 0, sugarMax = 0;
    double satMin = 0, satMax = 0;
    double sodMin = 0, sodMax = 0;

    for (final item in items) {
      carbMin += item.carbohydrates?.min ?? 0;
      carbMax += item.carbohydrates?.max ?? 0;
      fatMin += item.fat?.min ?? 0;
      fatMax += item.fat?.max ?? 0;
      fiberMin += item.fiber?.min ?? 0;
      fiberMax += item.fiber?.max ?? 0;
      sugarMin += item.sugar?.min ?? 0;
      sugarMax += item.sugar?.max ?? 0;
      satMin += item.saturatedFat?.min ?? 0;
      satMax += item.saturatedFat?.max ?? 0;
      sodMin += item.sodium?.min ?? 0;
      sodMax += item.sodium?.max ?? 0;
    }

    final locked = j['macrosLockedByUser'] as bool? ?? false;
    final userCorr = j['userCorrected'] as bool? ?? false;
    final carbsRange = j['carbohydrates'] != null
        ? NutritionItem._range(j['carbohydrates'])
        : (locked ? null : NutrientRange(min: carbMin, max: carbMax));
    final fatRange = j['fat'] != null
        ? NutritionItem._range(j['fat'])
        : (locked ? null : NutrientRange(min: fatMin, max: fatMax));
    final fiberRange = j['fiber'] != null
        ? NutritionItem._range(j['fiber'])
        : (locked ? null : NutrientRange(min: fiberMin, max: fiberMax));

    final canonicalMeal = j['canonicalMeal'] as String? ?? '';
    final calMid = (calories.min + calories.max) / 2;
    final proMid = (protein.min + protein.max) / 2;
    final score = j['mealQualityScore'] as int? ??
        NutritionResult.calculateLocalQualityScore(
          calMid,
          proMid,
          canonicalMeal,
          carbs: carbsRange?.mid,
          fat: fatRange?.mid,
          fiber: fiberRange?.mid,
        );

    return NutritionResult(
      canonicalMeal:  canonicalMeal,
      items:          items,
      calories:       calories,
      protein:        protein,
      confidence:     (j['confidence'] as num?)?.toDouble() ?? 0,
      warnings:       List<String>.from(j['warnings'] as List<dynamic>? ?? []),
      coachSummary:   j['coachSummary'] as String?,
      bestNextFoods:  List<String>.from(j['bestNextFoods'] as List<dynamic>? ?? const []),
      mealCategory:   j['mealCategory'] as String?,
      mealDensity:    j['mealDensity'] as String?,
      riskFlags:      List<String>.from(j['riskFlags'] as List<dynamic>? ?? const []),
      source:         j['source']    as String? ?? 'local_fallback',
      createdAt:      DateTime.tryParse(j['createdAt'] as String? ?? '') ??
                      DateTime.now(),
      fallbackReason: j['fallbackReason'] as String?,
      carbohydrates:  carbsRange,
      fat:            fatRange,
      fiber:          fiberRange,
      sugar:          j['sugar'] != null ? NutritionItem._range(j['sugar']) : NutrientRange(min: sugarMin, max: sugarMax),
      saturatedFat:   j['saturatedFat'] != null ? NutritionItem._range(j['saturatedFat']) : NutrientRange(min: satMin, max: satMax),
      sodium:         j['sodium'] != null ? NutritionItem._range(j['sodium']) : NutrientRange(min: sodMin, max: sodMax),
      mealQualityScore: score,
      mealQualityExplanation: j['mealQualityExplanation'] as String? ?? NutritionResult.getLocalQualityExplanation(score, canonicalMeal),
      mealQualityPositive: j['mealQualityPositive'] as String? ?? NutritionResult.getLocalQualityPositive(score, canonicalMeal),
      mealQualityImprovement: j['mealQualityImprovement'] as String? ?? NutritionResult.getLocalQualityImprovement(score, canonicalMeal),
      macrosLockedByUser: locked,
      userCorrected: userCorr,
      estimationAudit: j['estimationAudit'] != null ? EstimationAudit.fromJson(j['estimationAudit'] as Map<String, dynamic>) : null,
    ).normalizedUncertainty().rebuildFromIngredientsAndOverrides();
  }

  String toJsonString() => jsonEncode(toJson());
  factory NutritionResult.fromJsonString(String s) =>
      NutritionResult.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
