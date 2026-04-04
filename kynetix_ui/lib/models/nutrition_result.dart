import 'dart:convert';
import '../services/mock_estimation_service.dart'
    show NutrientRange, FoodItem, EstimationResult;

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

// ─── NutritionItem ────────────────────────────────────────────────────────────

class NutritionItem {
  final String         name;
  final double         quantity;
  final String         unit;
  final bool           estimated;
  final EstimationMode mode;
  final NutrientRange  calories;
  final NutrientRange  protein;

  const NutritionItem({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.estimated,
    required this.mode,
    required this.calories,
    required this.protein,
  });

  Map<String, dynamic> toJson() => {
        'name':           name,
        'quantity':       quantity,
        'unit':           unit,
        'estimated':      estimated,
        'estimationMode': mode.toJson(),
        'calories':       {'min': calories.min, 'max': calories.max},
        'protein':        {'min': protein.min,  'max': protein.max},
      };

  factory NutritionItem.fromJson(Map<String, dynamic> j) => NutritionItem(
        name:      j['name']     as String? ?? '',
        quantity:  (j['quantity'] as num?)?.toDouble() ?? 1.0,
        unit:      j['unit']     as String? ?? 'serving',
        estimated: j['estimated'] as bool? ?? false,
        mode:      EstimationMode.fromString(j['estimationMode'] as String? ?? ''),
        calories:  _range(j['calories']),
        protein:   _range(j['protein']),
      );

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
      );

  static NutrientRange _normalizeRange(NutrientRange r) {
    final diff = (r.max - r.min).abs();
    final meaningful = diff >= 5 && (r.max <= 0 || diff / r.max >= 0.04);
    if (meaningful) return r;
    final mid = ((r.min + r.max) / 2);
    final collapsed = double.parse(mid.toStringAsFixed(1));
    return NutrientRange(min: collapsed, max: collapsed);
  }
}

// ─── NutritionResult ─────────────────────────────────────────────────────────

class NutritionResult {
  final String              canonicalMeal;
  final List<NutritionItem> items;
  final NutrientRange       calories;
  final NutrientRange       protein;
  final double              confidence;
  final List<String>        warnings;
  final String?             coachSummary;
  final List<String>        bestNextFoods;
  final String?             mealCategory;
  final String?             mealDensity;
  final List<String>        riskFlags;
  /// 'ai', 'cache', or 'local_fallback'
  final String              source;
  final DateTime            createdAt;
  /// Only set when source == 'local_fallback'. Explains why Gemini was skipped.
  final String?             fallbackReason;

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
  });

  NutritionResult copyWith({String? source, String? fallbackReason}) => NutritionResult(
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
        source:         source ?? this.source,
        createdAt:      createdAt,
        fallbackReason: fallbackReason ?? this.fallbackReason,
      );

  /// Guardrails-specific copy — replaces macros + warnings without touching items.
  NutritionResult copyWithMacros({
    required NutrientRange calories,
    required NutrientRange protein,
    required List<String>  warnings,
  }) => NutritionResult(
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
      );

  NutritionResult normalizedUncertainty() => NutritionResult(
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
      );

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

  /// Build a NutritionResult from the legacy local fallback.
  factory NutritionResult.fromEstimationResult(
    EstimationResult r,
    String rawInput,
  ) =>
      NutritionResult(
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
                ))
            .toList(),
        calories:   r.calories,
        protein:    r.protein,
        confidence: r.confidence,
        warnings:   r.warnings,
        source:     'local_fallback',
        createdAt:  DateTime.now(),
      );

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
      };

  factory NutritionResult.fromJson(Map<String, dynamic> j) {
    final cal = j['calories'] as Map<String, dynamic>? ?? {};
    final pro = j['protein']  as Map<String, dynamic>? ?? {};
    return NutritionResult(
      canonicalMeal:  j['canonicalMeal'] as String? ?? '',
      items: (j['items'] as List<dynamic>? ?? [])
          .map((e) => NutritionItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      calories:   NutrientRange(
        min: (cal['min'] as num?)?.toDouble() ?? 0,
        max: (cal['max'] as num?)?.toDouble() ?? 0,
      ),
      protein:    NutrientRange(
        min: (pro['min'] as num?)?.toDouble() ?? 0,
        max: (pro['max'] as num?)?.toDouble() ?? 0,
      ),
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
    ).normalizedUncertainty();
  }

  String toJsonString() => jsonEncode(toJson());
  factory NutritionResult.fromJsonString(String s) =>
      NutritionResult.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
