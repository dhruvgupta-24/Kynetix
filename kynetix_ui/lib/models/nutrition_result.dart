import 'dart:convert';
import '../services/mock_estimation_service.dart'
    show NutrientRange, FoodItem, EstimationResult;
import '../services/user_nutrition_memory.dart';
import '../services/unit_normalizer.dart';
import 'micronutrients.dart';

export 'micronutrients.dart' show Micro, Micronutrients;


double _safe(double v, [int precision = 1]) {
  if (v.isNaN || v.isInfinite) return 0.0;
  return double.tryParse(v.toStringAsFixed(precision)) ?? 0.0;
}

// ─── Estimation mode ──────────────────────────────────────────────────────────

enum EstimationMode {
  directQuantity,     // explicit qty, 400ml milk, 4 egg whites
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

  /// Known micronutrients for this item (food library, pack label or Kyno's
  /// estimate). Null means not tracked, never zero. Stored under 'micros'
  /// only when present, so older JSON reads and writes unchanged.
  final Micronutrients? micros;

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
    this.micros,
  });

  /// A copy with [micros] replaced (null clears them).
  NutritionItem withMicros(Micronutrients? micros) => NutritionItem(
        name: name,
        quantity: quantity,
        unit: unit,
        estimated: estimated,
        mode: mode,
        calories: calories,
        protein: protein,
        carbohydrates: carbohydrates,
        fat: fat,
        fiber: fiber,
        sugar: sugar,
        saturatedFat: saturatedFat,
        sodium: sodium,
        eatingPatternScalarApplied: eatingPatternScalarApplied,
        micros: micros == null || micros.isEmpty ? null : micros,
      );

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
        if (micros != null && !micros!.isEmpty) 'micros': micros!.toJson(),
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
      micros: Micronutrients.fromJson(j['micros']),
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
        micros: micros,
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
      micros: micros?.scaled(scalar),
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
    List<NutritionItem>? items,
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
        items:          items ?? this.items,
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
          // Same food, same amount: a calorie correction doesn't change
          // what minerals it carries.
          micros: item.micros,
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
    final quality = NutritionResult.assessItems(
      midCal,
      midPro,
      canonicalMeal,
      updatedItems,
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
      mealQualityScore: quality.score,
      mealQualityExplanation: quality.explanation,
      mealQualityPositive: quality.positive,
      mealQualityImprovement: quality.improvement,
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

  // ── Meal quality keywords ────────────────────────────────────────────────
  // Matched as whole words (plural s/es allowed) on a normalised copy of the
  // meal text, so "chocolate" is not "cola", "pancake" is not "cake" and
  // "eggplant" is not "egg". Phrases that cancel a keyword ("sugar free",
  // "sweet potato", "air fried", "diet coke") are removed first.

  static RegExp _wordsRe(List<String> words) => RegExp(
        r'\b(?:' + words.map(RegExp.escape).join('|') + r')(?:s|es)?\b',
      );

  /// Phrases that look like a penalty keyword but are not one.
  static final RegExp _qualityNeutral = RegExp(
    r'\b(?:no added sugar|no sugar|without sugar|zero sugar|sugar ?free|sugarless|unsweetened'
    r'|diet (?:coke|pepsi|soda|cola)|(?:coke|pepsi|sprite|thums up) zero'
    r'|air ?fried|air ?fryer|stir ?fried|stir ?fry|rice cakes?|bhel puri)\b',
  );

  /// "sweet potato" is a potato, "sweet corn" is corn.
  static final RegExp _sweetVeg = RegExp(r'\bsweet (?=potato|corn|lime)');

  static final RegExp _qualityVeg = _wordsRe(const [
    'salad', 'vegetable', 'veggie', 'mix veg', 'mixed veg', 'sabzi', 'sabji', 'subzi',
    'broccoli', 'spinach', 'palak', 'greens', 'bhindi', 'okra', 'gobi', 'cauliflower',
    'cabbage', 'lauki', 'tinda', 'karela', 'methi', 'baingan', 'brinjal', 'eggplant',
    'capsicum', 'mushroom', 'cucumber', 'carrot', 'beans', 'sambar', 'avial', 'poriyal', 'thoran',
  ]);

  static final RegExp _qualityProtein = _wordsRe(const [
    'chicken', 'fish', 'tofu', 'paneer', 'egg', 'egg white', 'oats', 'whey', 'protein',
    'sprouts', 'soya', 'soy', 'soyabean', 'curd', 'dahi', 'yogurt', 'yoghurt',
    'mutton', 'prawn', 'salmon', 'tuna',
    // Dal and pulses are the protein in most Indian vegetarian plates.
    'dal', 'daal', 'rajma', 'chana', 'chole', 'moong', 'lentil', 'lentils', 'sambar',
  ]);

  static final RegExp _qualityPizza = _wordsRe(const ['pizza']);
  static final RegExp _qualityBurger = _wordsRe(const ['burger']);
  static final RegExp _qualityFried = _wordsRe(const [
    'fried', 'fries', 'french fries', 'fritter', 'nugget', 'chips', 'samosa', 'pakora',
    'pakoda', 'pakode', 'bhaji', 'bhajji', 'bhajiya', 'kachori', 'puri', 'poori',
    // Fried sweets (jalebi, gulab jamun) count once, as sweets.
    'bhatura', 'bhature', 'vada', 'wada', 'namkeen', 'bhujia', 'mathri',
  ]);
  static final RegExp _qualitySoda = _wordsRe(const [
    'soda', 'coke', 'cola', 'pepsi', 'sprite', 'fanta', 'thums up', 'limca',
    'mountain dew', 'cold drink', 'soft drink', 'energy drink', 'red bull', 'frooti', 'maaza',
  ]);
  static final RegExp _qualitySweet = _wordsRe(const [
    'sugar', 'cookie', 'biscuit', 'chocolate', 'cake', 'cupcake', 'cheesecake', 'pastry',
    'pastries', 'brownie', 'donut', 'doughnut', 'candy', 'candies', 'sweet', 'ice cream',
    'dessert', 'mithai', 'gulab jamun', 'jalebi', 'imarti', 'ladoo', 'laddu', 'laddoo',
    'barfi', 'burfi', 'halwa', 'kheer', 'rasgulla', 'rasmalai', 'ras malai', 'peda',
    'katli', 'soan papdi', 'payasam', 'shrikhand', 'kulfi', 'falooda', 'rabri',
    'malpua', 'sandesh',
  ]);
  static final RegExp _qualityComplexCarb = _wordsRe(const [
    'oats', 'apple', 'beans', 'rajma', 'chana', 'chole', 'dal', 'daal', 'lentil',
    'moong', 'millet', 'ragi', 'bajra', 'jowar', 'quinoa', 'brown rice',
  ]);

  /// Foods whose salt the words alone give away. In Indian diets most of a
  /// day's sodium hides in these more than in home cooking.
  static final RegExp _qualitySalty = _wordsRe(const [
    'pickle', 'achar', 'achaar', 'papad', 'papadum', 'poppadom', 'maggi', 'instant noodle',
    'cup noodle', 'ramen', 'chips', 'crisps', 'kurkure', 'namkeen', 'bhujia', 'sev',
    'chakna', 'nachos', 'soy sauce', 'salted',
  ]);

  /// Sugar here is the food's own (fruit, milk, curd), not added sugar.
  static final RegExp _qualityNaturalSugar = _wordsRe(const [
    'fruit', 'banana', 'kela', 'apple', 'seb', 'mango', 'aam', 'papaya', 'papita', 'orange',
    'santra', 'mosambi', 'guava', 'amrood', 'grape', 'watermelon', 'melon', 'muskmelon',
    'pomegranate', 'anar', 'pear', 'kiwi', 'berry', 'berries', 'strawberry', 'pineapple',
    'chikoo', 'chiku', 'sapota', 'date', 'khajur', 'raisin', 'kishmish', 'fig', 'anjeer',
    'milk', 'doodh', 'curd', 'dahi', 'yogurt', 'yoghurt', 'chaas', 'buttermilk',
  ]);

  /// Fat here is from whole nuts and seeds, never nudged on fat alone.
  static final RegExp _qualityWholeFat = _wordsRe(const [
    'nut', 'almond', 'badam', 'walnut', 'akhrot', 'cashew', 'kaju', 'pista', 'pistachio',
    'peanut', 'moongphali', 'groundnut', 'seed', 'chia', 'flax', 'avocado', 'makhana',
    'dry fruit', 'trail mix',
  ]);

  /// The meal text as the keyword matchers see it: lower case, words only,
  /// with cancelling phrases removed.
  static String _qualityText(String text) {
    var t = text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
    t = t.replaceAll(_sweetVeg, '');
    return t.replaceAll(_qualityNeutral, ' ');
  }

  static bool _isSweetText(String t) => _qualitySweet.hasMatch(t) || _qualitySoda.hasMatch(t);

  /// 20 to 100. A pure function of the numbers and the words, so the same
  /// meal logged the same way always gets the same score (an AI-suggested
  /// score is never used: it drifts between calls). See [assessQuality].
  static int calculateLocalQualityScore(
    double cal,
    double pro,
    String text, {
    double? fat,
    double? fiber,
    double? sugar,
    double? saturatedFat,
    double? sodium,
  }) =>
      assessQuality(cal, pro, text,
              fat: fat, fiber: fiber, sugar: sugar, saturatedFat: saturatedFat, sodium: sodium)
          .score;

  /// One meal's quality: the score and the three lines shown with it, built
  /// from one set of inputs so the words never disagree with the number.
  ///
  /// Fat, sugar and salt each count once, as the larger of what the words
  /// give away ("fried", "jalebi", "pickle") and what the numbers show.
  /// [sugar], [saturatedFat] (g) and [sodium] (mg) come from pack labels,
  /// Kyno and the food library, summed by [qualityNutrients]. A meal without
  /// them is judged on its words and macros alone.
  static MealQuality assessQuality(
    double cal,
    double pro,
    String text, {
    double? fat,
    double? fiber,
    double? sugar,
    double? saturatedFat,
    double? sodium,
  }) {
    final t = _qualityText(text);
    final f = _QualityFactors.of(cal, pro, t,
        fat: fat, sugar: sugar, saturatedFat: saturatedFat, sodium: sodium);
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

    if (_qualityVeg.hasMatch(t)) score += 10.0;
    if (_qualityProtein.hasMatch(t)) score += 5.0;

    score -= f.penalty;

    final s = score.clamp(20.0, 100.0).round();
    return MealQuality(
      score: s,
      explanation: _explain(s, f),
      positive: getLocalQualityPositive(s, text),
      improvement: _improve(s, t, f, sodium),
    );
  }

  /// Sugar, saturated fat and sodium the items carry, for [assessQuality].
  /// Each is the sum over the items that list it, so with gaps it is a floor
  /// and a nudge built on it can only under-count, never over-count. Null
  /// when no item lists it. Sugar in plain fruit, milk and curd is natural
  /// and left out; sodium prefers the cited library value over a model's.
  static ({double? sugar, double? saturatedFat, double? sodium}) qualityNutrients(
      Iterable<NutritionItem> items) {
    double? sugar, sat, sodium;
    for (final i in items) {
      final s = i.sugar?.mid;
      if (s != null && s > 0) {
        final t = _qualityText(i.name);
        final natural = _qualityNaturalSugar.hasMatch(t) && !_isSweetText(t);
        if (!natural) sugar = (sugar ?? 0) + s;
      }
      final sf = i.saturatedFat?.mid;
      if (sf != null && sf > 0) sat = (sat ?? 0) + sf;
      final na = i.micros?[Micro.sodium] ?? i.sodium?.mid;
      if (na != null && na > 0) sodium = (sodium ?? 0) + na;
    }
    return (sugar: sugar, saturatedFat: sat, sodium: sodium);
  }

  /// [assessQuality] over a meal's items: macros as given, sugar, saturated
  /// fat and sodium from the items.
  static MealQuality assessItems(
    double cal,
    double pro,
    String text,
    Iterable<NutritionItem> items, {
    double? fat,
    double? fiber,
  }) {
    final n = qualityNutrients(items);
    return assessQuality(cal, pro, text,
        fat: fat, fiber: fiber, sugar: n.sugar, saturatedFat: n.saturatedFat, sodium: n.sodium);
  }

  // Copy follows docs/VOICE.md: encourage without guilt, no exclamation
  // marks, no emoji, no dashes. Teens read these too, so food is never
  // "bad" or "junk"; a fried, sweet or salty meal gets a calm nudge, not a
  // verdict. The bands match the day-detail colours: 80+ good, 60 to 79
  // neutral, under 60 a nudge.

  /// The explanation for a stored [score], judged on the words alone (the
  /// numbers behind an old score are not kept). New meals get theirs from
  /// [assessQuality].
  static String getLocalQualityExplanation(int score, String text) =>
      _explain(score, _QualityFactors.of(0, 0, _qualityText(text)));

  static String getLocalQualityPositive(int score, String text) {
    final t = _qualityText(text);
    if (_qualityVeg.hasMatch(t)) return 'Brings vegetables and fiber.';
    if (_qualityProtein.hasMatch(t)) return 'Good protein to help your muscles recover.';
    if (_qualityComplexCarb.hasMatch(t)) return 'Complex carbs and fiber for steady energy.';
    if (score >= 75) return 'Well balanced fuel.';
    return 'Quick energy for the day.';
  }

  /// The improvement line for a stored [score], from the words alone. New
  /// meals get theirs from [assessQuality].
  static String getLocalQualityImprovement(int score, String text) {
    final t = _qualityText(text);
    return _improve(score, t, _QualityFactors.of(0, 0, t), null);
  }

  static String _explain(int score, _QualityFactors f) {
    if (score >= 90) return 'Top-tier plate. Plenty of protein and real food in there.';
    if (score >= 80) return 'Strong meal. Good protein and a solid mix.';
    if (score >= 60) return 'Decent meal. One small change would round it out.';
    return switch (f.top) {
      _Concern.fat => f.friedWords > 0
          ? 'Fried and filling. Fine now and then; some protein alongside next time keeps the day balanced.'
          : 'Rich and filling. Fine now and then; something lighter alongside next time keeps the day balanced.',
      _Concern.sweet => f.sweetWords > 0
          ? 'A sweet treat. Enjoy it; protein-rich meals around it keep the day on track.'
          : 'Sweeter than it looks. Fine now and then; protein-rich meals around it keep the day on track.',
      _Concern.salt =>
        'On the salty side. Fine now and then; a simple home-cooked meal next keeps the day balanced.',
      null => 'Mostly quick energy. Add dal, curd, paneer or eggs alongside to balance it.',
    };
  }

  static String _improve(int score, String t, _QualityFactors f, double? sodium) {
    switch (f.top) {
      case _Concern.fat:
        return f.friedWords > 0
            ? 'Next time, try it grilled, roasted or air fried.'
            : 'Next time, go lighter on cream, butter and oil.';
      case _Concern.sweet:
        return f.sweetWords > 0
            ? 'Keep sweets as a side, not the main event.'
            : 'Pick an unsweetened version next time, or keep it to a small side.';
      case _Concern.salt:
        if (f.saltNumbers > f.saltWords && sodium != null) {
          return 'About ${_mgLabel(sodium)} mg sodium here, over half the day\'s limit. Go lighter on salt in the next meal.';
        }
        return 'Pickle, papad, namkeen and instant noodles carry a lot of salt. Keep them to a small side.';
      case null:
        break;
    }
    // A protein tip only when the plate is short on it: by the numbers when
    // known (a 33 g protein paratha plate is not), by the words otherwise.
    final lowProtein = f.proteinRatio != null ? f.proteinRatio! < 0.2 : !_qualityProtein.hasMatch(t);
    if (score < 80 && lowProtein) {
      return 'Add some protein: dal, curd, paneer, eggs or chicken.';
    }
    if (!_qualityVeg.hasMatch(t)) return 'Add a side of sabzi or salad for fiber.';
    return 'Nicely put together. Keep portions in line with your targets.';
  }

  /// The improvement line for a stored [score], from the meal's own numbers
  /// and items where it has them (a saved meal keeps its score, but its tip
  /// follows the current rules).
  static String improvementFor(
    int score,
    String text, {
    double cal = 0,
    double pro = 0,
    Iterable<NutritionItem> items = const [],
    double? fat,
  }) {
    final t = _qualityText(text);
    final n = qualityNutrients(items);
    final f = _QualityFactors.of(cal, pro, t,
        fat: fat, sugar: n.sugar, saturatedFat: n.saturatedFat, sodium: n.sodium);
    return _improve(score, t, f, n.sodium);
  }

  /// Lines this app writes as improvement tips, now or before. A stored tip
  /// that is one of these is rebuilt on load; anything else is kept.
  static const Set<String> _builtInImprovements = {
    'Next time, try it grilled, roasted or air fried.',
    'Next time, go lighter on cream, butter and oil.',
    'Keep sweets as a side, not the main event.',
    'Pick an unsweetened version next time, or keep it to a small side.',
    'Pickle, papad, namkeen and instant noodles carry a lot of salt. Keep them to a small side.',
    'Add some protein: dal, curd, paneer, eggs or chicken.',
    'Add a side of sabzi or salad for fiber.',
    'Nicely put together. Keep portions in line with your targets.',
  };

  static bool _isBuiltInImprovement(Object? stored) {
    final s = stored is String ? stored.trim() : '';
    return s.isEmpty ||
        _legacyQualityCopy.contains(s) ||
        _builtInImprovements.contains(s) ||
        (s.startsWith('About ') && s.contains(' mg sodium here'));
  }

  /// "1,250": a sodium estimate rounded to 50 mg, with a thousands comma.
  static String _mgLabel(double mg) {
    final v = ((mg / 50).round() * 50).toString();
    return v.length > 3 ? '${v.substring(0, v.length - 3)},${v.substring(v.length - 3)}' : v;
  }

  /// Copy older app versions stored with a meal. A stored explanation that
  /// is one of these is replaced with the current copy on load; anything
  /// else (an edit, an AI line) is kept.
  static const Set<String> _legacyQualityCopy = {
    // The 60 to 79 line before the improvement tip was shown beside it.
    'Decent meal. A little more protein or veg would round it out.',
    'Exceptional choice! Highly nutritious, protein-dense, and rich in whole foods.',
    'Balanced meal with a solid macronutrient profile and good nutritional value.',
    'Moderate nutrition score. Consider adding more lean protein or vegetables to improve balance.',
    'High in saturated fats and fast-digesting carbohydrates. Pair with a high-protein source next time.',
    'Lower nutritional quality. High in processed ingredients, simple sugars, or refined fats. Try to replace with whole grains or lean protein options.',
    'Contains micronutrient-rich vegetables.',
    'High in high-quality protein to support muscle synthesis.',
    'Includes complex carbohydrates and healthy dietary fiber.',
    'Good macronutrient balance with clean fuel.',
    'Quick energy source to fuel your immediate activities.',
    'Reduce intake of deep-fried items to lower saturated fat consumption.',
    'Limit added sugars to prevent glycemic spikes and crashes.',
    'Add a lean protein source (e.g. egg whites, chicken, tofu) to boost protein density.',
    'Incorporate some leafy green vegetables for crucial fiber and micronutrients.',
    'Control portion size to align perfectly with your daily targets.',
  };

  static String _storedOr(Object? stored, String Function() current) {
    final s = stored is String ? stored.trim() : '';
    return s.isEmpty || _legacyQualityCopy.contains(s) ? current() : s;
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
    double effectiveCal = calories;
    double effectivePro = protein;
    double? effectiveCarb = carbohydrates;
    double? effectiveFat = fat;
    double? effectiveFib = fiber;

    if (items != null && items.isNotEmpty && items.length > 1) {
      double sumCal = 0, sumPro = 0, sumCarb = 0, sumFat = 0, sumFib = 0;
      for (final it in items) {
        sumCal += it.calories.mid;
        sumPro += it.protein.mid;
        sumCarb += it.carbohydrates?.mid ?? 0;
        sumFat += it.fat?.mid ?? 0;
        sumFib += it.fiber?.mid ?? 0;
      }
      effectiveCal = sumCal;
      effectivePro = sumPro;
      effectiveCarb = sumCarb;
      effectiveFat = sumFat;
      effectiveFib = sumFib;
    }

    final carbsRange = effectiveCarb != null
        ? NutrientRange(min: effectiveCarb, max: effectiveCarb)
        : estimateCarbsLocally(effectiveCal, effectivePro, canonicalMeal);
    final fatRange = effectiveFat != null
        ? NutrientRange(min: effectiveFat, max: effectiveFat)
        : estimateFatLocally(effectiveCal, effectivePro, canonicalMeal);
    final fiberRange = effectiveFib != null
        ? NutrientRange(min: effectiveFib, max: effectiveFib)
        : estimateFiberLocally(effectiveCal, canonicalMeal);

    final quality = assessItems(
      effectiveCal,
      effectivePro,
      canonicalMeal,
      items ?? const <NutritionItem>[],
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
          calories:  NutrientRange(min: effectiveCal, max: effectiveCal),
          protein:   NutrientRange(min: effectivePro, max: effectivePro),
          carbohydrates: carbsRange,
          fat:           fatRange,
          fiber:         fiberRange,
        ),
      ],
      calories:      NutrientRange(min: effectiveCal, max: effectiveCal),
      protein:       NutrientRange(min: effectivePro, max: effectivePro),
      confidence:    1.0,
      warnings:      const [],
      source:        source,
      createdAt:     DateTime.now(),
      carbohydrates: carbsRange,
      fat:            fatRange,
      fiber:          fiberRange,
      mealQualityScore: quality.score,
      mealQualityExplanation: quality.explanation,
      mealQualityPositive: quality.positive,
      mealQualityImprovement: quality.improvement,
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
    // Tolerant: a score stored as 72.0 (JSON from another writer) still loads.
    final storedScore = j['mealQualityScore'];
    final computed = storedScore is num && storedScore.isFinite
        ? null
        : NutritionResult.assessItems(calMid, proMid, canonicalMeal, items,
            fat: fatRange?.mid, fiber: fiberRange?.mid);
    final score = computed?.score ?? (storedScore as num).round().clamp(0, 100);

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
      mealQualityExplanation: _storedOr(j['mealQualityExplanation'],
          () => computed?.explanation ?? NutritionResult.getLocalQualityExplanation(score, canonicalMeal)),
      mealQualityPositive: _storedOr(j['mealQualityPositive'],
          () => computed?.positive ?? NutritionResult.getLocalQualityPositive(score, canonicalMeal)),
      mealQualityImprovement: _isBuiltInImprovement(j['mealQualityImprovement'])
          ? (computed?.improvement ??
              NutritionResult.improvementFor(score, canonicalMeal,
                  cal: calMid, pro: proMid, items: items, fat: fatRange?.mid))
          : (j['mealQualityImprovement'] as String).trim(),
      macrosLockedByUser: locked,
      userCorrected: userCorr,
      estimationAudit: j['estimationAudit'] != null ? EstimationAudit.fromJson(j['estimationAudit'] as Map<String, dynamic>) : null,
    ).normalizedUncertainty().rebuildFromIngredientsAndOverrides();
  }

  String toJsonString() => jsonEncode(toJson());
  factory NutritionResult.fromJsonString(String s) =>
      NutritionResult.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

/// A meal's quality score and the three lines shown with it.
class MealQuality {
  const MealQuality({
    required this.score,
    required this.explanation,
    required this.positive,
    required this.improvement,
  });

  final int score;
  final String explanation;
  final String positive;
  final String improvement;
}

enum _Concern { fat, sweet, salt }

/// The three things the quality score nudges on, each from the words and from
/// the numbers. A concern counts once, at the larger of its two, so "fried
/// chips" with a high fat number is not nudged twice for the same fat.
class _QualityFactors {
  const _QualityFactors({
    required this.friedWords,
    required this.richNumbers,
    required this.sweetWords,
    required this.sugarNumbers,
    required this.saltWords,
    required this.saltNumbers,
    this.proteinRatio,
  });

  /// [t] is the meal text as [NutritionResult._qualityText] returns it.
  factory _QualityFactors.of(
    double cal,
    double pro,
    String t, {
    double? fat,
    double? sugar,
    double? saturatedFat,
    double? sodium,
  }) {
    var fried = 0.0;
    if (NutritionResult._qualityPizza.hasMatch(t)) fried += 30;
    if (NutritionResult._qualityBurger.hasMatch(t)) fried += 25;
    if (NutritionResult._qualityFried.hasMatch(t)) fried += 20;
    var sweet = 0.0;
    if (NutritionResult._qualitySoda.hasMatch(t)) sweet += 15;
    if (NutritionResult._qualitySweet.hasMatch(t)) sweet += 15;
    final saltWords = NutritionResult._qualitySalty.hasMatch(t) ? 5.0 : 0.0;

    var rich = 0.0, sugary = 0.0;
    if (cal >= 100) {
      // Saturated fat when a label or Kyno gives it (WHO: under 10% of
      // energy). Otherwise total fat, only for a plate that is mostly fat
      // with little protein (cream, butter, malai), never nuts and seeds.
      if (saturatedFat != null && saturatedFat > 0) {
        final share = saturatedFat * 9 / cal;
        if (share >= 0.15 && saturatedFat >= 8) {
          rich = 10;
        } else if (share >= 0.10 && saturatedFat >= 5) {
          rich = 5;
        }
      } else if (fat != null && fat >= 15 && !NutritionResult._qualityWholeFat.hasMatch(t)) {
        if (fat * 9 / cal >= 0.55 && pro * 4 / cal < 0.15) rich = 10;
      }
      // Added sugar: a cup of chai (8 to 10 g) stays clear; a cola, a sweet
      // lassi or a frosted cereal bowl does not.
      if (sugar != null) {
        final share = sugar * 4 / cal;
        if (sugar >= 25 && share >= 0.20) {
          sugary = 15;
        } else if (sugar >= 15 && share >= 0.15) {
          sugary = 8;
        }
      }
    }
    // Against the 2,000 mg daily limit (ICMR-NIN 2020): half the day in one
    // meal is a nudge, most of it a firmer one.
    var salty = 0.0;
    if (sodium != null) {
      if (sodium >= 1800) {
        salty = 10;
      } else if (sodium >= 1000) {
        salty = 5;
      }
    }

    return _QualityFactors(
      friedWords: fried,
      richNumbers: rich,
      sweetWords: sweet,
      sugarNumbers: sugary,
      saltWords: saltWords,
      saltNumbers: salty,
      proteinRatio: cal > 0 ? pro * 4 / cal : null,
    );
  }

  final double friedWords, richNumbers;
  final double sweetWords, sugarNumbers;
  final double saltWords, saltNumbers;

  /// Share of calories from protein; null when the numbers are unknown.
  final double? proteinRatio;

  double get fat => friedWords > richNumbers ? friedWords : richNumbers;
  double get sweet => sweetWords > sugarNumbers ? sweetWords : sugarNumbers;
  double get salt => saltWords > saltNumbers ? saltWords : saltNumbers;

  /// Taken off the score; capped so a mixed plate still lands above the floor.
  double get penalty {
    final p = fat + sweet + salt;
    return p > 35 ? 35 : p;
  }

  /// The biggest concern, fat first on a tie, then sweet; null when none.
  _Concern? get top {
    if (fat <= 0 && sweet <= 0 && salt <= 0) return null;
    if (fat >= sweet && fat >= salt) return _Concern.fat;
    if (sweet >= salt) return _Concern.sweet;
    return _Concern.salt;
  }
}
