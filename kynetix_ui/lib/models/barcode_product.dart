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

  /// Micronutrients per 100 g when the label lists them (sodium, potassium,
  /// calcium, iron…), in mg / µg. Null when it lists none: not tracked.
  final Micronutrients? micros;

  const BarcodeNutriments({
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.fiberG,
    required this.sugarG,
    this.micros,
  });

  /// Exactly [amount] g (or ml) of a product with these per-100 figures.
  BarcodeNutriments scaledTo(double amount) {
    double f(double per100) =>
        double.parse((per100 * amount / 100.0).toStringAsFixed(1));
    return BarcodeNutriments(
      calories: f(calories),
      proteinG: f(proteinG),
      carbsG:   f(carbsG),
      fatG:     f(fatG),
      fiberG:   f(fiberG),
      sugarG:   f(sugarG),
      micros:   micros?.scaled(amount / 100.0),
    );
  }

  Map<String, dynamic> toJson() => {
        'calories': calories,
        'proteinG': proteinG,
        'carbsG':   carbsG,
        'fatG':     fatG,
        'fiberG':   fiberG,
        'sugarG':   sugarG,
        if (micros != null && !micros!.isEmpty) 'micros': micros!.toJson(),
      };

  factory BarcodeNutriments.fromJson(Map<String, dynamic> j) => BarcodeNutriments(
        calories: (j['calories'] as num?)?.toDouble() ?? 0,
        proteinG: (j['proteinG'] as num?)?.toDouble() ?? 0,
        carbsG:   (j['carbsG']   as num?)?.toDouble() ?? 0,
        fatG:     (j['fatG']     as num?)?.toDouble() ?? 0,
        fiberG:   (j['fiberG']   as num?)?.toDouble() ?? 0,
        sugarG:   (j['sugarG']   as num?)?.toDouble() ?? 0,
        micros:   Micronutrients.fromJson(j['micros']),
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

  /// Net contents of the whole pack in [unit] (grams or millilitres), or null
  /// when the pack does not say. For a multipack this is the total.
  final double?               netQuantity;

  /// 'g' or 'ml'. Liquids are labelled per 100 ml; the maths treats 1 ml as
  /// 1 g against those per-100 ml values, and the UI says "ml".
  final String                unit;

  /// For "6 x 35 g": 6 and 35. Null for a single pack.
  final int?                  packCount;
  final double?               innerQuantity;

  /// The label's own serving, in [unit], when stated.
  final double?               servingQuantity;

  /// Open Food Facts front image (small). Display only.
  final String?               imageUrl;

  /// Where the figures came from, for the provenance note.
  final BarcodeSource         source;

  const BarcodeProduct({
    required this.barcode,
    required this.name,
    required this.per100g,
    required this.servings,
    this.brand,
    this.netQuantity,
    this.unit = 'g',
    this.packCount,
    this.innerQuantity,
    this.servingQuantity,
    this.imageUrl,
    this.source = BarcodeSource.openFoodFacts,
  });

  bool get isLiquid => unit == 'ml';

  bool get isMultipack =>
      (packCount ?? 0) > 1 && (innerQuantity ?? 0) > 0;

  BarcodeProduct copyWith({
    String? name,
    String? brand,
    BarcodeNutriments? per100g,
    double? netQuantity,
    String? unit,
    double? servingQuantity,
    String? imageUrl,
    BarcodeSource? source,
  }) =>
      BarcodeProduct(
        barcode:         barcode,
        name:            name ?? this.name,
        brand:           brand ?? this.brand,
        per100g:         per100g ?? this.per100g,
        servings:        servings,
        netQuantity:     netQuantity ?? this.netQuantity,
        unit:            unit ?? this.unit,
        packCount:       packCount,
        innerQuantity:   innerQuantity,
        servingQuantity: servingQuantity ?? this.servingQuantity,
        imageUrl:        imageUrl ?? this.imageUrl,
        source:          source ?? this.source,
      );

  // ── Amounts ──────────────────────────────────────────────────────────────
  //
  // The rule that decides what a scan logs by default:
  //   1. A multipack ("6 x 35 g") → one inner pack. That is what gets opened.
  //   2. A known net size ≤ 250 g/ml → the whole pack. A 40 g pack of
  //      Parle-G is eaten as 40 g, never as the 100 g the label is printed per.
  //   3. Anything bigger (atta, rice, a family-size tub) → the label serving
  //      when it states one, else 100 g.
  //   0. Before all of that: things eaten a spoonful at a time (butter, ghee,
  //      oil, jam, ketchup, pickle, masala…) never default to the whole pack —
  //      a 200 g block of butter is not one portion. They default to the label
  //      serving, else 15 g (about a tablespoon).

  /// Default portion for spoon-portioned foods whose label states no serving.
  static const portionedFallbackGrams = 15.0;

  // Unambiguous "eaten by the spoonful" products. Flavour words such as
  // masala, salt or sugar are deliberately absent: "Magic Masala" chips and
  // "Classic Salted" crisps are whole-pack snacks.
  static final _portionedPattern = RegExp(
    r'\b(ghee|ketchup|mayonnaise|mayo|jam|jelly|marmalade|honey|pickle|'
    r'achar|chutney|vinegar|cooking oil|mustard oil|olive oil|'
    r'sunflower oil|groundnut oil|peanut butter|cheese spread|'
    r'chocolate spread|hazelnut spread)\b',
    caseSensitive: false,
  );

  // "Amul Butter" is portioned; "Butter Cookies" and "Butter Chicken" are not.
  static final _butterProduct = RegExp(r'\bbutter\b', caseSensitive: false);
  static final _butterAsFlavour = RegExp(
    r'\b(cookie|cookies|biscuit|biscuits|naan|chicken|paneer|popcorn|bread|'
    r'cake|toffee|crunch|bites?|murukku|chakli|masala|scotch|milk)\b',
    caseSensitive: false,
  );

  /// Eaten a spoonful at a time, not a pack at a time.
  bool get isPortionedFood =>
      _portionedPattern.hasMatch(name) ||
      (_butterProduct.hasMatch(name) && !_butterAsFlavour.hasMatch(name));

  /// Packs at or under this size default to "the whole pack".
  static const wholePackDefaultMax = 250.0;

  /// Above this a "whole pack" chip is not offered at all: nobody eats 5 kg
  /// of atta in one sitting, and a chip that suggests it invites a mis-tap.
  static const wholePackChipMax = 1000.0;

  /// Every portion the sheet offers as a chip, most likely first. The custom
  /// amount is not in this list; the sheet adds it.
  List<BarcodeAmountOption> get amountOptions {
    final out = <BarcodeAmountOption>[];
    void add(BarcodeAmountOption o) {
      if (o.grams <= 0 || !o.grams.isFinite) return;
      if (out.any((e) => (e.grams - o.grams).abs() < 0.05)) return;
      out.add(o);
    }

    if (isMultipack) {
      add(BarcodeAmountOption(
        kind: BarcodePortionKind.innerPack,
        grams: innerQuantity!,
        unit: unit,
      ));
    }
    final net = netQuantity;
    if (net != null && net > 0 && net <= wholePackChipMax) {
      add(BarcodeAmountOption(
        kind: BarcodePortionKind.wholePack,
        grams: net,
        unit: unit,
      ));
    }
    final serving = servingQuantity;
    if (serving != null && serving > 0) {
      add(BarcodeAmountOption(
        kind: BarcodePortionKind.serving,
        grams: serving,
        unit: unit,
      ));
    } else if (isPortionedFood) {
      add(BarcodeAmountOption(
        kind: BarcodePortionKind.serving,
        grams: portionedFallbackGrams,
        unit: unit,
      ));
    }
    add(BarcodeAmountOption(
      kind: BarcodePortionKind.hundred,
      grams: 100,
      unit: unit,
    ));
    return out;
  }

  /// The portion a scan selects first. See the rule above.
  BarcodeAmountOption get defaultAmount {
    final options = amountOptions;
    BarcodeAmountOption? find(BarcodePortionKind k) {
      for (final o in options) {
        if (o.kind == k) return o;
      }
      return null;
    }

    if (isPortionedFood) {
      final portion = find(BarcodePortionKind.serving);
      if (portion != null) return portion;
    }
    if (isMultipack) {
      final inner = find(BarcodePortionKind.innerPack);
      if (inner != null) return inner;
    }
    final net = netQuantity;
    if (net != null && net > 0 && net <= wholePackDefaultMax) {
      final whole = find(BarcodePortionKind.wholePack);
      if (whole != null) return whole;
    }
    return find(BarcodePortionKind.serving) ??
        find(BarcodePortionKind.hundred) ??
        options.first;
  }

  /// Macros for exactly [grams] (or ml) of this product: per 100 × grams / 100.
  BarcodeNutriments nutrimentsFor(double grams) => per100g.scaledTo(grams);

  /// "40 g" / "200 ml" / "12.5 g".
  String amountLabel(double grams) => formatAmount(grams, unit);

  /// The result a direct log records: one item whose quantity and unit are the
  /// real amount ("40" + "g"), so the day screen, the detail sheet and the
  /// editor all say "40 g". Values are exact, not ranges.
  NutritionResult resultForAmount(double grams, {DateTime? now}) {
    final g = _r1(grams);
    final n = nutrimentsFor(g);
    final text = entryText(g);

    NutrientRange exact(double v) => NutrientRange(min: v, max: v);

    final item = NutritionItem(
      name:      name,
      quantity:  g,
      unit:      unit,
      estimated: false,
      mode:      EstimationMode.packagedKnown,
      calories:      exact(n.calories),
      protein:       exact(n.proteinG),
      carbohydrates: exact(n.carbsG),
      fat:           exact(n.fatG),
      fiber:         exact(n.fiberG),
      sugar:         exact(n.sugarG),
      micros:        n.micros,
    );

    final score = NutritionResult.calculateLocalQualityScore(
      n.calories,
      n.proteinG,
      text,
      carbs: n.carbsG,
      fat:   n.fatG,
      fiber: n.fiberG,
    );

    return NutritionResult(
      canonicalMeal: text,
      items:         [item],
      calories:      exact(n.calories),
      protein:       exact(n.proteinG),
      carbohydrates: exact(n.carbsG),
      fat:           exact(n.fatG),
      fiber:         exact(n.fiberG),
      sugar:         exact(n.sugarG),
      confidence:    1.0,
      warnings:      const [],
      source:        'barcode',
      createdAt:     now ?? DateTime.now(),
      mealQualityScore:       score,
      mealQualityExplanation: NutritionResult.getLocalQualityExplanation(score, text),
      mealQualityPositive:    NutritionResult.getLocalQualityPositive(score, text),
      mealQualityImprovement: NutritionResult.getLocalQualityImprovement(score, text),
      estimationAudit: EstimationAudit(
        memoryMatchUsed:       'barcode: $barcode',
        portionAssumption:     '${amountLabel(g)} (${source.auditLabel})',
        environmentAssumption: 'packaged product, composition per 100 $unit from the label',
        finalChoiceReason:     source.auditReason,
        uncertaintyFactors:    const [],
        pipelineConfidence:    1.0,
        memoryPriorityLevel:   'Branded Food',
      ),
    );
  }

  /// The text a logged entry carries, e.g. "40 g Parle-G Original Gluco".
  /// Amount first, so the editor's parser reads it back as 40 g of the food.
  String entryText(double grams) => '${amountLabel(grams)} $name';

  static double _r1(double v) => double.parse(v.toStringAsFixed(1));

  /// "40 g", "200 ml", "12.5 g". Amounts stay in the label's own unit.
  static String formatAmount(double v, String unit) {
    final r = _r1(v);
    final s = r == r.roundToDouble() ? r.round().toString() : r.toStringAsFixed(1);
    return '$s $unit';
  }

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
      micros:        per100g.micros?.scaled(grams / 100.0),
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
        finalChoiceReason:     'Open Food Facts barcode lookup, measured, not estimated',
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
        if (netQuantity != null) 'netQuantity': netQuantity,
        'unit': unit,
        if (packCount != null) 'packCount': packCount,
        if (innerQuantity != null) 'innerQuantity': innerQuantity,
        if (servingQuantity != null) 'servingQuantity': servingQuantity,
        if (imageUrl != null) 'imageUrl': imageUrl,
        'source': source.name,
      };

  factory BarcodeProduct.fromJson(Map<String, dynamic> j) {
    final servings = _servingsFromJson(j['servings']);
    // Entries cached before pack sizes were stored only have the legacy
    // portion list; recover the serving and pack weight from it.
    double? legacy(String unit) {
      for (final s in servings) {
        if (s.unit == unit && s.grams > 0) return s.grams;
      }
      return null;
    }

    final hasNew = j.containsKey('unit');
    return BarcodeProduct(
      barcode: j['barcode'] as String? ?? '',
      name:    j['name']    as String? ?? '',
      brand:   j['brand']   as String?,
      per100g: BarcodeNutriments.fromJson(
        j['per100g'] as Map<String, dynamic>? ?? const {},
      ),
      servings: servings,
      netQuantity:     _pos(j['netQuantity']) ?? (hasNew ? null : legacy('pack')),
      unit:            j['unit'] == 'ml' ? 'ml' : 'g',
      packCount:       (j['packCount'] as num?)?.toInt(),
      innerQuantity:   _pos(j['innerQuantity']),
      servingQuantity: _pos(j['servingQuantity']) ?? (hasNew ? null : legacy('serving')),
      imageUrl:        j['imageUrl'] as String?,
      source: BarcodeSource.values.firstWhere(
        (s) => s.name == j['source'],
        orElse: () => BarcodeSource.openFoodFacts,
      ),
    );
  }

  static double? _pos(dynamic v) {
    final d = v is num ? v.toDouble() : null;
    return d != null && d.isFinite && d > 0 ? d : null;
  }

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


// ─── Provenance ───────────────────────────────────────────────────────────────

/// Where a product's figures came from. User-confirmed sources win over Open
/// Food Facts for that user.
enum BarcodeSource {
  openFoodFacts,
  labelPhoto,
  userEntered;

  bool get isUserConfirmed => this != BarcodeSource.openFoodFacts;

  /// The provenance note on the product sheet.
  String note(String unit) => switch (this) {
        BarcodeSource.openFoodFacts => 'From the label · per 100 $unit',
        BarcodeSource.labelPhoto    => 'From your label photo · per 100 $unit',
        BarcodeSource.userEntered   => 'You entered this · per 100 $unit',
      };

  String get auditLabel => switch (this) {
        BarcodeSource.openFoodFacts => 'Open Food Facts',
        BarcodeSource.labelPhoto    => 'label photo, confirmed',
        BarcodeSource.userEntered   => 'entered by you',
      };

  String get auditReason => switch (this) {
        BarcodeSource.openFoodFacts =>
          'Open Food Facts barcode lookup, measured, not estimated',
        BarcodeSource.labelPhoto =>
          'Label read from a photo and confirmed by the user',
        BarcodeSource.userEntered => 'Label values entered by the user',
      };
}

// ─── Amount options ───────────────────────────────────────────────────────────

enum BarcodePortionKind { wholePack, innerPack, serving, hundred, custom }

/// One chip on the product sheet: "Whole pack · 40 g", "1 serving · 30 g",
/// "100 g".
class BarcodeAmountOption {
  final BarcodePortionKind kind;
  final double grams;
  final String unit;

  const BarcodeAmountOption({
    required this.kind,
    required this.grams,
    required this.unit,
  });

  String get amount => BarcodeProduct.formatAmount(grams, unit);

  /// What one step of the count stepper is called: "2 packs", "1.5 servings".
  String get noun => switch (kind) {
        BarcodePortionKind.wholePack => 'pack',
        BarcodePortionKind.innerPack => 'pack',
        BarcodePortionKind.serving   => 'serving',
        BarcodePortionKind.hundred   => '',
        BarcodePortionKind.custom    => '',
      };

  String get chipLabel => switch (kind) {
        BarcodePortionKind.wholePack => 'Whole pack · $amount',
        BarcodePortionKind.innerPack => '1 pack · $amount',
        BarcodePortionKind.serving   => '1 serving · $amount',
        BarcodePortionKind.hundred   => amount,
        BarcodePortionKind.custom    => 'Custom',
      };
}
