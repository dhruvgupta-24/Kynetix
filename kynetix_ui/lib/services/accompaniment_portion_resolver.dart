import 'dart:math' as math;

import '../data/indian_curry_table.dart';
import '../models/nutrition_result.dart';
import '../models/user_profile.dart' show PortionAnchor;
import 'mock_estimation_service.dart' show NutrientRange;

// ─── AccompanimentPortionResolver ─────────────────────────────────────────────
//
// Sizes the dal, sabzi, chole or gravy in a meal by the roti and rice it was
// eaten with, and by the person's eater type.
//
//   "2 roti with white chane"               → chole to finish 2 roti
//   "3 roti with white chane"               → one roti's worth more
//   "3 roti + 1 ladle rice with white chane" → plus a ladle of rice's worth
//
// A carb first eater uses the curry as a condiment (about 35 g of chole per
// roti); a curry first eater finishes a fuller katori. Rice takes more of a
// liquid dal than a roti does and less of a dry sabzi, so every curry family
// has its own grams per roti and per rice ladle ([CurryFamily.gramsPer]).
//
// Rules:
//   • An amount the person typed always wins: "1 katori dal", "150 g rajma",
//     "2 ladle chole" log exactly that, never scaled.
//   • Several curries share the carbs: together they come to a bit more than
//     one would (1 + 0.3 per extra curry), split by each one's own size.
//   • A curry with no roti or rice is one katori (150 g) per serving.
//   • Items the person pinned (their own saved values, a scanned pack) are
//     left alone.
//   • The stated roti and rice counts are never changed.
//
// Each sized curry is rewritten as "<grams> g" with macros from
// [IndianCurryTable], so the meal shows exactly what was counted.

class AccompanimentPortionResolver {
  const AccompanimentPortionResolver._();

  /// One katori of curry.
  static const double katoriGrams = 150;

  /// Several curries together: how much more than one curry is eaten in
  /// total, per extra curry.
  static const double extraCurryShare = 0.3;

  /// Resolves [items]. [pinned] holds lower case names whose values came
  /// from the person and must not change.
  static List<NutritionItem> resolve(
    List<NutritionItem> items, {
    required PortionAnchor anchor,
    Set<String> pinned = const {},
  }) {
    if (items.isEmpty) return items;

    // ── Carbs on the plate
    var rotiUnits = 0.0;
    var riceLadles = 0.0;
    final carbIdx = <int>{};
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      final roti = _rotiUnits(it);
      if (roti != null) {
        rotiUnits += roti;
        carbIdx.add(i);
        continue;
      }
      final rice = _riceLadles(it);
      if (rice != null) {
        riceLadles += rice;
        carbIdx.add(i);
      }
    }
    final hasCarbs = rotiUnits + riceLadles > 0;

    // Plain rice with a stated amount ("1 plate rice", "2 ladle rice") is
    // counted from cooked rice per 100 g, so a plate is never a ladle.
    items = [
      for (var i = 0; i < items.length; i++)
        carbIdx.contains(i) && !pinned.contains(items[i].name.toLowerCase().trim())
            ? (_plainRiceByAmount(items[i]) ?? items[i])
            : items[i],
    ];

    // ── Curries: explicit amounts first, then the ones sized by the carbs
    final dishes = <int, CurryDish>{};
    final explicitGrams = <int, double>{};
    for (var i = 0; i < items.length; i++) {
      if (carbIdx.contains(i)) continue;
      final it = items[i];
      if (pinned.contains(it.name.toLowerCase().trim())) continue;
      final dish = IndianCurryTable.match(it.name);
      if (dish == null) continue;
      dishes[i] = dish;
      final g = explicitGramsOf(it);
      if (g != null) explicitGrams[i] = g;
    }
    if (dishes.isEmpty) return _lockCarbs(items, carbIdx);

    final sized = [for (final i in dishes.keys) if (!explicitGrams.containsKey(i)) i];
    // Raita rides alongside the curries rather than sharing their carbs.
    final sharing = sized.where((i) => dishes[i]!.family != CurryFamily.raita).length;
    final share = sharing <= 1 ? 1.0 : (1 + extraCurryShare * (sharing - 1)) / sharing;

    final out = List<NutritionItem>.of(items);
    for (final e in dishes.entries) {
      final i = e.key;
      final dish = e.value;
      final it = items[i];
      double grams;
      if (explicitGrams.containsKey(i)) {
        grams = explicitGrams[i]!;
      } else if (hasCarbs) {
        grams = rotiUnits * dish.family.gramsPer(anchor, perRoti: true) +
            riceLadles * dish.family.gramsPer(anchor, perRoti: false);
        if (dish.family != CurryFamily.raita) grams *= share;
        // An implicit "2 dal" still means two helpings' worth.
        grams *= math.max(1.0, it.quantity);
      } else {
        grams = katoriGrams * (it.quantity > 0 ? it.quantity : 1);
      }
      grams = (grams / 5).round() * 5.0;
      if (grams < 5) grams = 5;
      // A typed amount keeps its own words ("2 katori"); a sized one reads
      // in grams.
      final typed = explicitGrams.containsKey(i);
      out[i] = itemFor(dish, grams,
          name: it.name,
          mode: it.mode,
          micros: it.micros,
          oldKcal: it.calories.mid,
          quantity: typed ? it.quantity : null,
          unit: typed ? it.unit : null);
    }
    return _lockCarbs(out, carbIdx);
  }

  /// [dish] at [grams], with a ±10% range around the table value.
  static NutritionItem itemFor(
    CurryDish dish,
    double grams, {
    required String name,
    EstimationMode mode = EstimationMode.contextualIntake,
    Micronutrients? micros,
    double? oldKcal,
    double? quantity,
    String? unit,
  }) {
    NutrientRange r(double per100) {
      final mid = per100 * grams / 100;
      return NutrientRange(min: mid * 0.9, max: mid * 1.1);
    }

    final kcal = dish.kcal * grams / 100;
    return NutritionItem(
      name: name,
      quantity: quantity ?? grams,
      unit: unit ?? 'g',
      estimated: true,
      mode: mode == EstimationMode.directQuantity ? EstimationMode.contextualIntake : mode,
      calories: r(dish.kcal),
      protein: r(dish.protein),
      carbohydrates: r(dish.carbs),
      fat: r(dish.fat),
      fiber: r(dish.fiber),
      eatingPatternScalarApplied: true,
      // Micros follow the calories they came with.
      micros: micros == null || oldKcal == null || oldKcal <= 0 ? null : micros.scaled(kcal / oldKcal),
    );
  }

  // ── Amounts ─────────────────────────────────────────────────────────────────

  static final RegExp _katoriWord = RegExp(r'\b(katori|katoris|bowl|bowls)\b');
  static final RegExp _ladleWord = RegExp(r'\b(ladle|ladles|scoop|scoops)\b');
  static final RegExp _cupWord = RegExp(r'\b(cup|cups)\b');
  static final RegExp _plateWord = RegExp(r'\b(plate|plates)\b');

  /// Grams of a curry the person stated, or null when they gave only a dish
  /// name (to be sized by the carbs).
  static double? explicitGramsOf(NutritionItem it) {
    final unit = it.unit.toLowerCase().trim();
    final q = it.quantity > 0 ? it.quantity : 1.0;
    switch (unit) {
      case 'g' || 'gm' || 'gms' || 'gram' || 'grams' || 'ml':
        return q;
      case 'kg':
        return q * 1000;
      case 'l' || 'litre' || 'liter':
        return q * 1000;
      case 'katori' || 'katoris' || 'bowl' || 'bowls':
        return q * katoriGrams;
      case 'ladle' || 'ladles' || 'scoop' || 'scoops':
        return q * 100;
      case 'cup' || 'cups':
        return q * 200;
      case 'plate' || 'plates':
        return q * 250;
      case 'tbsp' || 'tablespoon' || 'tablespoons':
        return q * 15;
    }
    // "2 katori dal" parses as name "katori dal", unit serving.
    final lc = it.name.toLowerCase();
    if (_katoriWord.hasMatch(lc)) return q * katoriGrams;
    if (_ladleWord.hasMatch(lc)) return q * 100;
    if (_cupWord.hasMatch(lc)) return q * 200;
    if (_plateWord.hasMatch(lc)) return q * 250;
    return null;
  }

  // ── Carbs ───────────────────────────────────────────────────────────────────

  /// Breads by how much curry each takes, relative to a mess roti.
  static final List<(RegExp, double)> _breads = [
    (RegExp(r'\b(butter |garlic )?naans?\b'), 1.8),
    (RegExp(r'\b(laccha|lachha) parathas?\b'), 1.5),
    (RegExp(r'\b(aloo|gobi|paneer|mooli|methi) parathas?\b'), 1.0),
    (RegExp(r'\bparathas?\b|\bparanthas?\b'), 1.3),
    (RegExp(r'\b(kulchas?|bhature|bhaturas?)\b'), 1.5),
    (RegExp(r'\b(tandoori|missi|makki|bajra|jowar) (roti|rotis)\b'), 1.3),
    (RegExp(r'\b(phulka|phulkas)\b'), 0.8),
    (RegExp(r'\b(roti|rotis|rotiyan|chapati|chapatis|chapatti|chapattis|chapathi)\b'), 1.0),
    (RegExp(r'\b(puri|puris|poori|pooris)\b'), 0.6),
    (RegExp(r'\b(theplas?)\b'), 0.9),
    (RegExp(r'\b(pav|pao)\b'), 0.8),
    (RegExp(r'\bbread\b|\bslices?\b'), 0.6),
  ];

  // Rice that is eaten with a curry. Biryani, pulao, khichdi, fried, curd
  // and lemon rice are meals of their own.
  static final RegExp _rice =
      RegExp(r'\b(rice|chawal|chaawal)\b');
  static final RegExp _riceMeal =
      RegExp(r'\b(biryani|pulao|pulav|khichdi|khichri|fried|curd|lemon|tamarind|puliyogare|kheer|poha|flakes|cake|noodles?|paper)\b');

  /// Roti equivalents of [it], or null when it is not a bread eaten with curry.
  static double? _rotiUnits(NutritionItem it) {
    final lc = it.name.toLowerCase();
    if (IndianCurryTable.match(lc) != null) return null;
    for (final (re, factor) in _breads) {
      if (!re.hasMatch(lc)) continue;
      final unit = it.unit.toLowerCase().trim();
      final q = it.quantity > 0 ? it.quantity : 1.0;
      // A weighed roti: a mess roti is about 35 g cooked.
      if (unit == 'g' || unit == 'gram' || unit == 'grams') return q / 35 * factor;
      return q * factor;
    }
    return null;
  }

  /// Rice ladle equivalents (about 100 g cooked) of [it], or null when it is
  /// not plain rice.
  static double? _riceLadles(NutritionItem it) {
    final lc = it.name.toLowerCase();
    if (!_rice.hasMatch(lc) || _riceMeal.hasMatch(lc)) return null;
    final unit = it.unit.toLowerCase().trim();
    final q = it.quantity > 0 ? it.quantity : 1.0;
    switch (unit) {
      case 'ladle' || 'ladles' || 'scoop' || 'scoops':
        return q;
      case 'katori' || 'katoris' || 'bowl' || 'bowls' || 'cup' || 'cups':
        return q * 1.5;
      case 'plate' || 'plates':
        return q * 2.5;
      case 'g' || 'gram' || 'grams':
        return q / 100;
      case 'kg':
        return q * 10;
    }
    // No amount: size it by its calories (a ladle is about 130 kcal).
    final kcal = it.calories.mid;
    return kcal > 0 ? (kcal / 130).clamp(0.5, 6.0) : q;
  }

  static final RegExp _plainRice =
      RegExp(r'^(plain |white |steamed |boiled |sada )?(rice|chawal|chaawal)$');

  /// Cooked white rice per 100 g (IFCT / USDA): 130 kcal, 2.7 g protein,
  /// 28 g carbs, 0.3 g fat, 0.4 g fibre. A ladle is about 100 g.
  static NutritionItem? _plainRiceByAmount(NutritionItem it) {
    final unit = it.unit.toLowerCase().trim();
    const stated = {
      'ladle', 'ladles', 'scoop', 'scoops', 'katori', 'katoris', 'bowl', 'bowls',
      'cup', 'cups', 'plate', 'plates', 'g', 'gram', 'grams', 'kg',
    };
    if (!stated.contains(unit) || !_plainRice.hasMatch(it.name.toLowerCase().trim())) return null;
    final grams = (_riceLadles(it) ?? 0) * 100;
    if (grams <= 0) return null;
    NutrientRange r(double per100) {
      final mid = per100 * grams / 100;
      return NutrientRange(min: mid * 0.92, max: mid * 1.08);
    }

    return NutritionItem(
      name: it.name,
      quantity: it.quantity,
      unit: it.unit,
      estimated: it.estimated,
      mode: it.mode,
      calories: r(130),
      protein: r(2.7),
      carbohydrates: r(28.2),
      fat: r(0.3),
      fiber: r(0.4),
      eatingPatternScalarApplied: true,
      micros: it.micros == null || it.calories.mid <= 0 ? null : it.micros!.scaled(130 * grams / 100 / it.calories.mid),
    );
  }

  /// The stated roti and rice counts must never be rescaled by the later
  /// eater-type pass.
  static List<NutritionItem> _lockCarbs(List<NutritionItem> items, Set<int> carbIdx) {
    if (carbIdx.isEmpty) return items;
    return [
      for (var i = 0; i < items.length; i++)
        carbIdx.contains(i) && !items[i].eatingPatternScalarApplied ? items[i].withScalar(1.0) : items[i],
    ];
  }
}
