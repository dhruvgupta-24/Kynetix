import '../models/nutrition_result.dart';
import '../services/consumed_portion_engine.dart';
import '../services/meal_classifier.dart';
import '../services/mock_estimation_service.dart' show NutrientRange;

// ─── NutritionGuardrails ─────────────────────────────────────────────────────
//
// Post-AI sanity layer. Applied to every pipeline result after the AI responds.
// Rules are FLOOR-based: they never reduce a result, only raise it.
//
// ARCHITECTURE (v3, April 2026):
//
//   Section 1 — Determistic exact foods (milk, eggs)
//     These have known quantities and exact baselines. Additive floor.
//
//   Section 2 — Indian dish consumed-portion floor (delegates to ConsumedPortionEngine)
//     The engine computes a behavior-based floor for the curry/sabzi/protein component
//     based on carb load and dish type. This replaces old per-dish hardcoded blocks.
//
//   Section 3 — Carb component floors (roti + rice)
//     Independent floor, combined with engine floor for Indian meals.
//
//   Section 4 — Hard minimums for specific rich dishes that often get underestimated
//     Dal makhani, butter chicken, biryani, fried snacks, naan, peanut butter.
//     These are not covered by the engine (too specific / recipe-dependent).
//
//   Section 5 — Restaurant uplift
//     Multiplier applied when restaurant/outside context is detected.
//
//   Section 6 — Classification-based mixed-meal floor
//     Catches meals where no specific dish keyword fired.

class NutritionGuardrails {
  NutritionGuardrails._();

  static NutritionResult apply(
    NutritionResult result,
    String rawInput, {
    MealClassification? classification,
  }) {
    // Allow 0 kcal items to pass through to be caught by floors

    final lc    = rawInput.toLowerCase();
    var calMin  = result.calories.min;
    var calMax  = result.calories.max;
    var proMin  = result.protein.min;
    var proMax  = result.protein.max;
    final warns = <String>[...result.warnings];

    // ── Carb base detection ───────────────────────────────────────────────────
    final rotis     = _count(lc, ['roti', 'chapati', 'chapatti', 'phulka']);
    final riceFloor = _riceCaloriesFloor(lc);   // kcal from rice component
    final rotiFloor = rotis * (_containsAny(lc, ['stacked', 'thick', 'ghee roti']) ? 115.0 : 100.0);
    final hasCarbBase = rotis > 0 || riceFloor > 0 ||
        _containsAny(lc, ['rice', 'chawal', 'naan', 'paratha', 'puri', 'poori']);

    // ── 1. Exact foods: milk + egg whites — additive floor ───────────────────
    //
    // Milk = Indian toned milk (58 kcal/100ml) unless specified otherwise.
    // ADDITIVE: total must cover BOTH milk floor AND egg white floor.

    final milkMl    = _milkQuantityMl(lc);
    final eggWhites = _eggWhiteCount(lc);

    if (milkMl != null && milkMl >= 100) {
      final milkCalFlr = milkMl * _milkKcalPerMl(lc);
      final milkProFlr = milkMl * _milkProteinPerMl(lc);
      final eggCalFlr  = eggWhites * 17.0;
      final eggProFlr  = eggWhites * 3.6;
      final reqCal = milkCalFlr + eggCalFlr;
      final reqPro = milkProFlr + eggProFlr;
      if (calMax < reqCal) {
        calMin = _r((reqCal * 0.92).clamp(0, double.infinity));
        calMax = _r(reqCal);
        proMin = _r(proMin.clamp(reqPro, double.infinity));
        proMax = _r(proMax.clamp(reqPro, double.infinity));
        warns.add('Applied milk+egg floor (${milkMl.toInt()} ml milk + $eggWhites whites).');
      }
    } else if (eggWhites > 0) {
      final eggCalFlr = eggWhites * 17.0;
      final eggProFlr = eggWhites * 3.6;
      if (calMax < eggCalFlr) {
        calMin = _r((eggCalFlr * 0.9).clamp(0, double.infinity));
        calMax = _r(eggCalFlr);
        proMin = _r(proMin.clamp(eggProFlr, double.infinity));
        proMax = _r(proMax.clamp(eggProFlr, double.infinity));
      }
    }

    // ── 2. Indian dish consumed-portion floor (ConsumedPortionEngine) ─────────
    //
    // The engine computes how much of the curry/sabzi/protein component was
    // likely consumed, based on carb load and dish type.
    //
    // Combined floor = carb floor (roti + rice) + dish component floor.
    // This correctly models the total meal floor without double-counting.

    final engineFloor = ConsumedPortionEngine.instance.estimate(rawInput);
    if (engineFloor != null) {
      final combinedCalMin = rotiFloor + riceFloor + engineFloor.caloriesMin;
      final combinedCalMax = rotiFloor + riceFloor + engineFloor.caloriesMax;
      final combinedProMin = engineFloor.proteinMin;
      final combinedProMax = engineFloor.proteinMax;

      if (calMax < combinedCalMax) {
        calMin = _r(calMin < combinedCalMin ? combinedCalMin : calMin);
        calMax = _r(combinedCalMax);
        proMin = _r(proMin.clamp(combinedProMin, double.infinity));
        proMax = _r(proMax.clamp(combinedProMax, double.infinity));
        warns.add('Applied consumed-portion floor (${combinedCalMax.toInt()} kcal): '
                  '${engineFloor.rationale}');
      }
    } else {
      // ── 3a. Carb-only floor (when no dish engine matched) ──────────────────
      // If the engine didn't fire (no curry/sabzi detected), still ensure
      // roti + rice are covered.
      final carbOnlyFloor = rotiFloor + riceFloor;
      if (carbOnlyFloor > 0 && calMax < carbOnlyFloor) {
        calMin = _r(calMin + (carbOnlyFloor - calMax) * 0.85);
        calMax = _r(carbOnlyFloor);
      }
    }

    // ── 4. Hard minimums for rich/specific dishes ────────────────────────────
    //
    // These are NOT covered by the engine because they're too recipe-specific
    // or the engine already handles the category with a different profile.
    // Apply as "clamp-up" floors — only raise, never lower.

    // Butter chicken / murgh makhani
    if (lc.contains('butter chicken') || lc.contains('murgh makhani')) {
      _clampUp(380, 320, calMax: calMax,
          setMin: (v) => calMin = v, setMax: (v) => calMax = v);
    }

    // Creamy / makhani dishes (broad catch for anything not already floored)
    if (_containsAny(lc, ['butter masala', 'korma', 'malai', 'cream gravy']) &&
        calMax < 300) {
      _clampUp(320, 260, calMax: calMax,
          setMin: (v) => calMin = calMin > v ? calMin : v,
          setMax: (v) => calMax = calMax > v ? calMax : v);
    }

    // Pav bhaji
    if (_containsAny(lc, ['pav bhaji', 'pao bhaji'])) {
      _clampUp(500, 400, calMax: calMax,
          setMin: (v) => calMin = calMin > v ? calMin : v,
          setMax: (v) => calMax = calMax > v ? calMax : v);
    }

    // Biryani
    if (_containsAny(lc, ['biryani', 'biriyani'])) {
      final isRestaurant = _isOutside(lc);
      _clampUp(isRestaurant ? 700 : 480, isRestaurant ? 580 : 420,
          calMax: calMax,
          setMin: (v) => calMin = v, setMax: (v) => calMax = v);
      proMin = _r(proMin.clamp(14, double.infinity));
      proMax = _r(proMax.clamp(18, double.infinity));
      warns.add('Applied biryani floor.');
    }

    // Fried snacks
    if (_containsAny(lc, ['samosa', 'kachori', 'pakora', 'pakoda', 'vada',
                           'chips', 'fries', 'fried snack'])) {
      _clampUp(200, 160, calMax: calMax,
          setMin: (v) => calMin = calMin > v ? calMin : v,
          setMax: (v) => calMax = calMax > v ? calMax : v);
    }

    // Naan (260 kcal each — different from roti)
    final naans = _count(lc, ['naan', 'nan']);
    if (naans > 0) {
      final flr = naans * 260.0;
      if (calMax < flr) {
        calMin = _r(calMin + (flr - calMax) * 0.88);
        calMax = _r(flr);
      }
    }

    // Peanut butter (95 kcal/tbsp)
    if (_containsAny(lc, ['peanut butter', ' pb '])) {
      final tbsp = _tbsp(lc);
      final flr  = tbsp * 95.0;
      if (calMax < flr) {
        calMin = _r(calMin + (flr - calMax) * 0.85);
        calMax = _r(flr);
        proMin = _r(proMin.clamp(tbsp * 3.5, double.infinity));
        proMax = _r(proMax.clamp(tbsp * 4.0, double.infinity));
        warns.add('Applied peanut-butter floor.');
      }
    }

    // Curd / tofu / bread+PB micro-floors
    if (_containsAny(lc, ['curd', 'dahi', 'yogurt', 'yoghurt']) && calMax < 55) {
      calMax = _r(55); calMin = _r(45);
    }
    if (lc.contains('tofu') && calMax < 130) {
      calMax = _r(140); calMin = _r(130);
    }

    // ── 4b. Wraps and Rolls ───────────────────────────────────────────────────
    final isWrap = _containsAny(lc, ['wrap', 'roll', 'kathi', 'frankie', 'fajita', 'burrito']);
    if (isWrap) {
      final isLight = _containsAny(lc, ['mini', 'very light', 'low calorie', 'diet', 'homemade light']);
      final isHeavySauce = _containsAny(lc, ['makhani', 'butter', 'creamy', 'cheesy', 'mayo', 'malai', 'loaded', 'tandoori mayo', 'spicy mayo', 'garlic mayo']);
      
      final wrapCount = _parseWrapCount(lc);
      if (wrapCount > 0) {
        final baseFloor = isLight ? 220.0 : 350.0;
        var anchor = wrapCount * baseFloor;
        if (isHeavySauce) anchor *= 1.35;

        if (calMax < anchor) {
          calMin = _r(calMin + (anchor - calMax) * 0.85);
          calMax = _r(anchor);
          warns.add('Applied wrap/roll dynamic floor ($wrapCount wrap${wrapCount == 1.0 ? "" : "s"}).');
        }

        var perWrapPro = 8.0;
        if (_containsAny(lc, ['chicken', 'murgh', 'meat', 'egg'])) {
          perWrapPro = 20.0;
        } else if (_containsAny(lc, ['paneer', 'cottage cheese', 'soya'])) {
          perWrapPro = 16.0;
        }
        final proAnchor = wrapCount * perWrapPro;
        if (proMax < proAnchor) {
          proMin = _r(proMin.clamp(proAnchor * 0.8, double.infinity));
          proMax = _r(proAnchor);
        }
      }
    }

    // ── 5. Restaurant uplift ──────────────────────────────────────────────────
    if (_isOutside(lc) && result.items.isNotEmpty) {
      final uplift = _containsAny(lc, ['thali', 'biryani', 'burger', 'pizza', 'roll'])
          ? 1.22 : 1.15;
      calMin = _r(calMin * uplift);
      calMax = _r(calMax * uplift);
      proMin = _r(proMin * 1.08);
      proMax = _r(proMax * 1.08);
      warns.add('Applied restaurant uplift (×${uplift.toStringAsFixed(2)}).');
    }

    // ── 6. Classification-based mixed-meal floor ──────────────────────────────
    // Catches meals with no specific keyword match but high-density signals.
    if (classification != null && classification.category != MealDensityCategory.light) {
      final floor = classification.recommendedMealFloor(hasCarbBase: hasCarbBase);
      if (calMax < floor.max) {
        calMin = _r(calMin < floor.min ? floor.min : calMin);
        calMax = _r(floor.max);
        warns.add('Applied ${classification.category.name} meal-density floor.');
      }
    }

    return result.copyWithMacros(
      calories: NutrientRange(
        min: _r(calMin.clamp(0, double.infinity)),
        max: _r(calMax.clamp(0, double.infinity)),
      ),
      protein: NutrientRange(
        min: _r(proMin.clamp(0, double.infinity)),
        max: _r(proMax.clamp(0, double.infinity)),
      ),
      warnings: warns,
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static double _r(double v) => double.parse(v.toStringAsFixed(1));

  static void _clampUp(double maxFloor, double minFloor, {
    required double calMax,
    required void Function(double) setMin,
    required void Function(double) setMax,
  }) {
    if (calMax < maxFloor) {
      setMin(minFloor);
      setMax(maxFloor);
    }
  }

  // ── Milk type-aware baselines ─────────────────────────────────────────────
  // Default: Indian toned milk (Amul Toned) = 58 kcal/100ml, 3.4g/100ml.

  static double _milkKcalPerMl(String lc) {
    if (_containsAny(lc, ['skim', 'skimmed', 'fat free', '0%'])) return 0.36;
    if (_containsAny(lc, ['double toned', 'double-toned', 'low fat'])) return 0.46;
    if (_containsAny(lc, ['buffalo', 'full fat', 'whole milk'])) return 0.72;
    if (_containsAny(lc, ['full cream', 'fullcream'])) return 0.65;
    return 0.58;
  }

  static double _milkProteinPerMl(String lc) {
    if (_containsAny(lc, ['skim', 'skimmed'])) return 0.036;
    if (_containsAny(lc, ['buffalo', 'full fat'])) return 0.032;
    return 0.034;
  }

  static int _eggWhiteCount(String lc) {
    final m = RegExp(r'(\d+)\s*(?:egg\s*whites?|whites?)').firstMatch(lc);
    if (m != null) return int.tryParse(m.group(1)!) ?? 0;
    if (lc.contains('egg white')) return 1;
    return 0;
  }

  static double? _milkQuantityMl(String lc) {
    final pat = RegExp(r'(\d+(?:\.\d+)?)\s*ml', caseSensitive: false);
    for (final kw in ['milk', 'doodh']) {
      final ki = lc.indexOf(kw);
      if (ki < 0) continue;
      for (final m in pat.allMatches(lc)) {
        if ((m.start - ki).abs() < 35) return double.tryParse(m.group(1)!);
      }
    }
    final litre = RegExp(r'(\d+(?:\.\d+)?)\s*(?:l|litre|liter)').firstMatch(lc);
    if (litre != null && _containsAny(lc, ['milk', 'doodh'])) {
      return (double.tryParse(litre.group(1)!) ?? 0) * 1000;
    }
    final glass = RegExp(r'(\d+)\s*glass(?:es)?\s*(?:of\s+)?(?:milk|doodh)').firstMatch(lc);
    if (glass != null) return (double.tryParse(glass.group(1)!) ?? 1) * 250;
    if (_containsAny(lc, ['milk', 'doodh']) && lc.contains('glass')) return 250;
    if (_containsAny(lc, ['milk', 'doodh']) && lc.contains('cup')) return 200;
    return null;
  }

  static int _count(String lc, List<String> kws) {
    int total = 0;
    for (final kw in kws) {
      final ms = RegExp(r'(\d+)\s+' + RegExp.escape(kw)).allMatches(lc);
      for (final m in ms) { total += int.tryParse(m.group(1)!) ?? 0; }
      if (total == 0 && lc.contains(kw)) total = 1;
    }
    return total;
  }

  static double _riceCaloriesFloor(String lc) {
    if (!lc.contains('rice') && !lc.contains('chawal')) return 0;
    final mFrac = RegExp(r'(\d+(?:\.\d+)?)\s*(?:ladle|ladles|scoop|scoops)').firstMatch(lc);
    if (mFrac != null) return (double.tryParse(mFrac.group(1)!) ?? 1.0) * 130.0;
    if (lc.contains('ladle') || lc.contains('scoop')) return 130.0;
    final bowls = RegExp(r'(\d+)\s*(?:bowls?|katoris?)\s*(?:of\s+)?(?:rice|chawal)').firstMatch(lc);
    if (bowls != null) return (double.tryParse(bowls.group(1)!) ?? 1) * 210.0;
    if (_containsAny(lc, ['bowl rice', 'katori rice', 'bowl of rice'])) return 210.0;
    return 0;
  }

  static int _tbsp(String lc) {
    final m = RegExp(r'(\d+)\s*(?:tbsp|tablespoon|spoon)').firstMatch(lc);
    return m != null ? (int.tryParse(m.group(1)!) ?? 1) : 1;
  }

  static double _parseWrapCount(String lc) {
    double total = 0.0;
    final pat = RegExp(r'(\d+(?:\.\d+)?)\s*(?:wrap|roll|kathi|frankie|fajita|burrito)s?');
    for (final m in pat.allMatches(lc)) {
      total += double.tryParse(m.group(1)!) ?? 0;
    }
    final halfPat = RegExp(r'half\s*(?:a\s*)?(?:wrap|roll|kathi|frankie|fajita|burrito)s?');
    for (final _ in halfPat.allMatches(lc)) {
      total += 0.5;
    }
    if (total == 0) {
      // If no explicit numbers, but half is mentioned outside of the explicit wrap string
      if (_containsAny(lc, ['half'])) {
        total = 0.5;
      } else {
        total = 1.0;
      }
    }
    return total;
  }

  static bool _isOutside(String lc) => const [
    'restaurant', 'outside', 'hotel', 'dhaba', 'fast food',
    'burger', 'pizza', 'roll', 'wrap', 'sandwich', 'subway',
    'kfc', 'domino', 'zomato', 'swiggy', 'cafe',
  ].any(lc.contains);

  static bool _containsAny(String lc, List<String> needles) =>
      needles.any(lc.contains);
}
