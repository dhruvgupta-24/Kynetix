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
  final NutrientRange? carbohydrates;
  final NutrientRange? fat;
  final NutrientRange? fiber;
  final NutrientRange? sugar;
  final NutrientRange? saturatedFat;
  final NutrientRange? sodium;

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
      };

  factory NutritionItem.fromJson(Map<String, dynamic> j) => NutritionItem(
        name:      j['name']     as String? ?? '',
        quantity:  (j['quantity'] as num?)?.toDouble() ?? 1.0,
        unit:      j['unit']     as String? ?? 'serving',
        estimated: j['estimated'] as bool? ?? false,
        mode:      EstimationMode.fromString(j['estimationMode'] as String? ?? ''),
        calories:  _range(j['calories']),
        protein:   _range(j['protein']),
        carbohydrates: j['carbohydrates'] != null ? _range(j['carbohydrates']) : null,
        fat:           j['fat'] != null ? _range(j['fat']) : null,
        fiber:         j['fiber'] != null ? _range(j['fiber']) : null,
        sugar:         j['sugar'] != null ? _range(j['sugar']) : null,
        saturatedFat:  j['saturatedFat'] != null ? _range(j['saturatedFat']) : null,
        sodium:        j['sodium'] != null ? _range(j['sodium']) : null,
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
        carbohydrates: carbohydrates != null ? _normalizeRange(carbohydrates!) : null,
        fat: fat != null ? _normalizeRange(fat!) : null,
        fiber: fiber != null ? _normalizeRange(fiber!) : null,
        sugar: sugar != null ? _normalizeRange(sugar!) : null,
        saturatedFat: saturatedFat != null ? _normalizeRange(saturatedFat!) : null,
        sodium: sodium != null ? _normalizeRange(sodium!) : null,
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
  });

  NutritionResult copyWith({
    String? source,
    String? fallbackReason,
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
      );

  /// Guardrails-specific copy — replaces macros + warnings without touching items.
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

  // ── Local Fallback Estimations ───────────────────────────────────────────

  static NutrientRange _estimateCarbsLocally(double cal, double pro, String text) {
    final lowerText = text.toLowerCase();
    double ratio = 0.55; // default 55% of remaining calories to carbs
    if (lowerText.contains('rice') || lowerText.contains('roti') || lowerText.contains('bread') || lowerText.contains('banana') || lowerText.contains('oats')) {
      ratio = 0.75;
    } else if (lowerText.contains('paneer') || lowerText.contains('oil') || lowerText.contains('butter') || lowerText.contains('avocado')) {
      ratio = 0.30;
    }
    final remainingCal = (cal - pro * 4).clamp(0.0, double.infinity);
    final carbsGrams = (remainingCal * ratio / 4).clamp(0.0, double.infinity);
    return NutrientRange(min: double.parse((carbsGrams * 0.9).toStringAsFixed(1)), max: double.parse((carbsGrams * 1.1).toStringAsFixed(1)));
  }

  static NutrientRange _estimateFatLocally(double cal, double pro, String text) {
    final lowerText = text.toLowerCase();
    double ratio = 0.45; // default 45% of remaining calories to fat
    if (lowerText.contains('rice') || lowerText.contains('roti') || lowerText.contains('bread') || lowerText.contains('banana') || lowerText.contains('oats')) {
      ratio = 0.25;
    } else if (lowerText.contains('paneer') || lowerText.contains('oil') || lowerText.contains('butter') || lowerText.contains('avocado') || lowerText.contains('cheese')) {
      ratio = 0.70;
    }
    final remainingCal = (cal - pro * 4).clamp(0.0, double.infinity);
    final fatGrams = (remainingCal * ratio / 9).clamp(0.0, double.infinity);
    return NutrientRange(min: double.parse((fatGrams * 0.9).toStringAsFixed(1)), max: double.parse((fatGrams * 1.1).toStringAsFixed(1)));
  }

  static NutrientRange _estimateFiberLocally(double cal, String text) {
    final lowerText = text.toLowerCase();
    double fiberGrams = 1.5;
    if (lowerText.contains('salad') || lowerText.contains('broccoli') || lowerText.contains('vegetable') || lowerText.contains('greens')) {
      fiberGrams = 6.0;
    } else if (lowerText.contains('oats') || lowerText.contains('apple') || lowerText.contains('lentils') || lowerText.contains('beans')) {
      fiberGrams = 4.5;
    } else if (cal > 500) {
      fiberGrams = 3.0;
    }
    return NutrientRange(min: double.parse((fiberGrams * 0.8).toStringAsFixed(1)), max: double.parse((fiberGrams * 1.2).toStringAsFixed(1)));
  }

  static int _calculateLocalQualityScore(double cal, double pro, String text) {
    final lowerText = text.toLowerCase();
    double score = 70.0; // base score

    if (cal > 0) {
      final proteinCalRatio = (pro * 4) / cal;
      if (proteinCalRatio >= 0.3) {
        score += 15.0; // protein bonus
      } else if (proteinCalRatio >= 0.2) {
        score += 8.0;
      }
    }

    if (lowerText.contains('salad') || lowerText.contains('vegetable') || lowerText.contains('broccoli') || lowerText.contains('spinach')) {
      score += 10.0;
    }
    if (lowerText.contains('oats') || lowerText.contains('egg') || lowerText.contains('chicken breast') || lowerText.contains('fish')) {
      score += 5.0;
    }

    if (lowerText.contains('pizza') || lowerText.contains('burger') || lowerText.contains('soda') || lowerText.contains('fries') || lowerText.contains('fried') || lowerText.contains('coke')) {
      score -= 25.0;
    } else if (lowerText.contains('sugar') || lowerText.contains('cookie') || lowerText.contains('chocolate') || lowerText.contains('cake') || lowerText.contains('donut')) {
      score -= 15.0;
    }

    return score.clamp(0.0, 100.0).round();
  }

  static String _getLocalQualityExplanation(int score, String text) {
    final lowerText = text.toLowerCase();
    if (score >= 85) {
      return 'Nutritious whole food choice with excellent protein density and clean ingredients.';
    } else if (score >= 70) {
      return 'Balanced meal with decent macronutrient profile, suitable for daily fuel.';
    } else if (score >= 50) {
      return 'Moderate nutrition score. Could be improved by adding fresh vegetables or high-quality lean protein.';
    } else {
      if (lowerText.contains('pizza') || lowerText.contains('burger') || lowerText.contains('fries')) {
        return 'High in saturated fats and fast-digesting carbohydrates. Pair with a high-protein source next time.';
      }
      return 'Higher processed content or sugar level. Try to replace with whole grains or lean protein options.';
    }
  }

  static String _getLocalQualityPositive(int score, String text) {
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

  static String _getLocalQualityImprovement(int score, String text) {
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

  /// Build a NutritionResult from the legacy local fallback.
  factory NutritionResult.fromEstimationResult(
    EstimationResult r,
    String rawInput,
  ) {
    final calVal = r.calories.mid;
    final proVal = r.protein.mid;
    final carbs = _estimateCarbsLocally(calVal, proVal, rawInput);
    final fat = _estimateFatLocally(calVal, proVal, rawInput);
    final fiber = _estimateFiberLocally(calVal, rawInput);
    final score = _calculateLocalQualityScore(calVal, proVal, rawInput);
    
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
                carbohydrates: _estimateCarbsLocally(fi.calories.mid, fi.protein.mid, fi.name),
                fat:           _estimateFatLocally(fi.calories.mid, fi.protein.mid, fi.name),
                fiber:         _estimateFiberLocally(fi.calories.mid, fi.name),
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
      mealQualityExplanation: _getLocalQualityExplanation(score, rawInput),
      mealQualityPositive: _getLocalQualityPositive(score, rawInput),
      mealQualityImprovement: _getLocalQualityImprovement(score, rawInput),
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
      carbohydrates:  j['carbohydrates'] != null ? NutritionItem._range(j['carbohydrates']) : null,
      fat:            j['fat'] != null ? NutritionItem._range(j['fat']) : null,
      fiber:          j['fiber'] != null ? NutritionItem._range(j['fiber']) : null,
      sugar:          j['sugar'] != null ? NutritionItem._range(j['sugar']) : null,
      saturatedFat:   j['saturatedFat'] != null ? NutritionItem._range(j['saturatedFat']) : null,
      sodium:         j['sodium'] != null ? NutritionItem._range(j['sodium']) : null,
      mealQualityScore: j['mealQualityScore'] as int?,
      mealQualityExplanation: j['mealQualityExplanation'] as String?,
      mealQualityPositive: j['mealQualityPositive'] as String?,
      mealQualityImprovement: j['mealQualityImprovement'] as String?,
    ).normalizedUncertainty();
  }

  String toJsonString() => jsonEncode(toJson());
  factory NutritionResult.fromJsonString(String s) =>
      NutritionResult.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
