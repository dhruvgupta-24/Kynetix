import '../services/mock_estimation_service.dart' show NutrientRange;
import 'nutrition_result.dart';

// ─── BarcodeServing ───────────────────────────────────────────────────────────

/// One portion the pack itself describes: the stated serving, the whole pack,
/// or a plain 100 g fallback. Grams is the only thing that matters downstream —
/// the label is for the chip the user taps.
class BarcodeServing {
  final String label;
  final String unit;
  final double grams;

  const BarcodeServing({
    required this.label,
    required this.unit,
    required this.grams,
  });

  Map<String, dynamic> toJson() => {
        'label': label,
        'unit':  unit,
        'grams': grams,
      };

  factory BarcodeServing.fromJson(Map<String, dynamic> j) => BarcodeServing(
        label: j['label'] as String? ?? '100 g',
        unit:  j['unit']  as String? ?? 'g',
        grams: (j['grams'] as num?)?.toDouble() ?? 100.0,
      );
}

// ─── BarcodeNutriments ────────────────────────────────────────────────────────

/// Composition per 100 g, exactly as printed on the label.
///
/// Every other nutrition path in this app estimates twice — what the food is,
/// then how much of it there is. A barcode removes both guesses: a laboratory
/// measured this and the pack states its own weight, so what is left is
/// multiplication. That is why these are stored per 100 g and scaled at the
/// point of use rather than being baked into a portion here.
class BarcodeNutriments {
  final double calories;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double fiberG;
  final double sugarG;

  const BarcodeNutriments({
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.fiberG,
    required this.sugarG,
  });

  Map<String, dynamic> toJson() => {
        'calories': calories,
        'proteinG': proteinG,
        'carbsG':   carbsG,
        'fatG':     fatG,
        'fiberG':   fiberG,
        'sugarG':   sugarG,
      };

  factory BarcodeNutriments.fromJson(Map<String, dynamic> j) => BarcodeNutriments(
        calories: (j['calories'] as num?)?.toDouble() ?? 0,
        proteinG: (j['proteinG'] as num?)?.toDouble() ?? 0,
        carbsG:   (j['carbsG']   as num?)?.toDouble() ?? 0,
        fatG:     (j['fatG']     as num?)?.toDouble() ?? 0,
        fiberG:   (j['fiberG']   as num?)?.toDouble() ?? 0,
        sugarG:   (j['sugarG']   as num?)?.toDouble() ?? 0,
      );
}

// ─── BarcodeProduct ───────────────────────────────────────────────────────────

/// A packaged product resolved from a scanned barcode.
class BarcodeProduct {
  final String                barcode;
  final String                name;
  final String?               brand;
  final BarcodeNutriments     per100g;
  final List<BarcodeServing>  servings;

  const BarcodeProduct({
    required this.barcode,
    required this.name,
    required this.per100g,
    required this.servings,
    this.brand,
  });

  /// The serving the sheet selects first: the pack's own stated serving when it
  /// has one, since that is what a person actually eats.
  BarcodeServing get defaultServing => servings.first;

  /// Grams for [servingIdx] repeated [quantity] times.
  double gramsFor(int servingIdx, double quantity) {
    final serving = servingIdx >= 0 && servingIdx < servings.length
        ? servings[servingIdx]
        : defaultServing;
    return serving.grams * quantity;
  }

  double _scaled(double per100, double grams) {
    final v = per100 * grams / 100.0;
    return double.parse(v.toStringAsFixed(1));
  }

  /// Build the display name a logged entry carries, e.g.
  /// "Amul Butter (100 g)". The gram weight lives in the name rather than in
  /// the item's quantity/unit on purpose: [AddMealScreen] reconstructs a row's
  /// text from quantity + unit + name, and re-parses that text on blur. Keeping
  /// quantity at 1 "serving" makes the reconstructed text identical to the name,
  /// so an untouched barcode row is never re-estimated over the label figures.
  String displayNameFor(int servingIdx, double quantity) {
    final grams = gramsFor(servingIdx, quantity);
    final g = grams == grams.roundToDouble()
        ? grams.round().toString()
        : grams.toStringAsFixed(1);
    return '$name ($g g)';
  }

  /// Convert a chosen portion into the same [NutritionResult] shape every other
  /// logging path produces, so a scanned product is edited, saved, remembered
  /// and synced by the existing machinery rather than a parallel one.
  NutritionResult toNutritionResult({
    required int servingIdx,
    required double quantity,
  }) {
    final grams = gramsFor(servingIdx, quantity);
    final label = displayNameFor(servingIdx, quantity);

    final cal  = _scaled(per100g.calories, grams);
    final pro  = _scaled(per100g.proteinG, grams);
    final carb = _scaled(per100g.carbsG,   grams);
    final fat  = _scaled(per100g.fatG,     grams);
    final fib  = _scaled(per100g.fiberG,   grams);
    final sug  = _scaled(per100g.sugarG,   grams);

    NutrientRange exact(double v) => NutrientRange(min: v, max: v);

    final item = NutritionItem(
      name:      label,
      quantity:  1,
      unit:      'serving',
      // Nothing here was inferred — the values come off a measured label.
      estimated: false,
      mode:      EstimationMode.packagedKnown,
      calories:      exact(cal),
      protein:       exact(pro),
      carbohydrates: exact(carb),
      fat:           exact(fat),
      fiber:         exact(fib),
      sugar:         exact(sug),
    );

    final score = NutritionResult.calculateLocalQualityScore(
      cal,
      pro,
      label,
      carbs: carb,
      fat:   fat,
      fiber: fib,
    );

    return NutritionResult(
      canonicalMeal: label,
      items:         [item],
      calories:      exact(cal),
      protein:       exact(pro),
      carbohydrates: exact(carb),
      fat:           exact(fat),
      fiber:         exact(fib),
      sugar:         exact(sug),
      // A label is not an estimate, so there is no range and no uncertainty to
      // show. Per the UX rules, a range of 235–235 is a fake range.
      confidence:    1.0,
      warnings:      const [],
      source:        'barcode',
      createdAt:     DateTime.now(),
      mealQualityScore:       score,
      mealQualityExplanation: NutritionResult.getLocalQualityExplanation(score, label),
      mealQualityPositive:    NutritionResult.getLocalQualityPositive(score, label),
      mealQualityImprovement: NutritionResult.getLocalQualityImprovement(score, label),
      estimationAudit: EstimationAudit(
        memoryMatchUsed:       'barcode: $barcode',
        portionAssumption:     '${servings[servingIdx.clamp(0, servings.length - 1)].label} × $quantity = ${grams.toStringAsFixed(0)} g',
        environmentAssumption: 'packaged product, composition from pack label',
        finalChoiceReason:     'Open Food Facts barcode lookup — measured, not estimated',
        uncertaintyFactors:    const [],
        pipelineConfidence:    1.0,
        memoryPriorityLevel:   'Branded Food',
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'barcode':  barcode,
        'name':     name,
        if (brand != null) 'brand': brand,
        'per100g':  per100g.toJson(),
        'servings': servings.map((s) => s.toJson()).toList(),
      };

  factory BarcodeProduct.fromJson(Map<String, dynamic> j) => BarcodeProduct(
        barcode: j['barcode'] as String? ?? '',
        name:    j['name']    as String? ?? '',
        brand:   j['brand']   as String?,
        per100g: BarcodeNutriments.fromJson(
          j['per100g'] as Map<String, dynamic>? ?? const {},
        ),
        servings: _servingsFromJson(j['servings']),
      );

  /// A product always has at least a plain 100 g portion, so callers can index
  /// [servings] without guarding against an empty list.
  static List<BarcodeServing> _servingsFromJson(dynamic raw) {
    final parsed = (raw as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(BarcodeServing.fromJson)
        .toList();
    return parsed.isEmpty ? const [hundredGrams] : parsed;
  }

  /// The portion every product falls back to when the pack states nothing else.
  static const hundredGrams = BarcodeServing(label: '100 g', unit: 'g', grams: 100);
}
