import '../models/user_profile.dart' show PortionAnchor;
import 'profile_service.dart';
import 'food_role_classifier.dart';
import 'eating_pattern_service.dart';

// ─── ConsumedPortionEngine ────────────────────────────────────────────────────
//
// Behavior-based consumed portion estimator for Indian hostel/mess meals.
//
// CORE PRINCIPLE:
//   Amount consumed = f(carb_load, dish_type, context)
//   NOT a fixed percentage of what was served.
//
// CARB LOAD MODEL:
//   Each roti   = 1.0 carb unit
//   Each rice ladle = 0.8 carb units
//   Carb load primarily drives how much curry/sabzi/dal is consumed alongside.
//
// PANEER IS SPECIAL:
//   Paneer chunks are eaten fully (independent of carb load).
//   Only the surrounding gravy/oil usage scales with carb load.
//
// CALIBRATION (IFCT 2017 / USDA cooked-dish densities, home/mess cooking):
//   2 roti + 1 ladle rice + rajma     → rajma component: ~118g, ~125–140 kcal, ~6–6.5g protein
//   2 roti + rajma                     → rajma component: ~84g,  ~90–100 kcal,  ~4–4.6g protein
//   3 comp. paneer + 2r + 1.5l.r      → paneer component: ~340–380 kcal, 18–20g protein ✓
//   2 roti + thin dal                  → dal component:    ~120ml, ~60–70 kcal, ~3–3.6g protein
//
// USAGE (from NutritionGuardrails):
//   final floor = ConsumedPortionEngine.instance.estimate(rawInput);
//   if (floor != null) { apply floor.caloriesMax / floor.proteinMin etc. }

class ConsumedPortionEngine {
  ConsumedPortionEngine._();
  static final ConsumedPortionEngine instance = ConsumedPortionEngine._();

  /// Estimate the consumed portion of the DISH COMPONENT (curry/sabzi/dal/paneer).
  /// Returns null when no recognizable Indian dish is detected.
  /// The carb component (roti/rice) is handled separately by NutritionGuardrails.
  ConsumedFloor? estimate(String rawInput) {
    final lc = rawInput.toLowerCase();
    final ctx = _MealCtx.parse(lc);
    if (ctx.profile == null) return null;
    return _compute(ctx);
  }

  ConsumedFloor _compute(_MealCtx ctx) {
    // Effective carb load: 1 roti = 1.0 unit, 1 ladle rice = 0.8 units.
    // If user ate no carbs (just had the dish alone), use 2.0 as a reasonable
    // standalone serving assumption — not zero, which would collapse estimates.
    final carbLoad = ctx.rotiCount * 1.0 + ctx.riceLadles * 0.8;
    final effectiveCarbLoad = carbLoad < 0.5 ? 2.0 : carbLoad;

    // ── Portion anchor scalar ───────────────────────────────────────────────────
    // Adjusts how much curry/dal/sabzi the engine estimates the user consumed
    // alongside their carbs, based on their self-reported eating behaviour.
    //
    //   carbAnchored:  0.78x — uses dal/sabzi as a condiment (fewer ml/g per roti)
    //   balanced:      1.00x — default calibrated midpoint (unchanged behaviour)
    //   curryAnchored: 1.30x — eats curry as the main dish, finishes a full katori
    //
    // The scalar is only applied when the user has explicitly chosen an anchor.
    // Null anchor = balanced = no change to existing behaviour.
    final anchorScalar = switch (ProfileService.instance.currentUserProfile?.portionAnchor) {
      PortionAnchor.carbAnchored  => 0.78,
      PortionAnchor.balanced      => 1.00,
      PortionAnchor.curryAnchored => 1.30,
      null                        => 1.00,  // not set, keep existing calibration
    };

    // Clamp the scalar for safety in case of unexpected enum additions.
    final safeScalar = anchorScalar.clamp(0.5, 2.0);

    final FoodRole targetRole = switch (ctx.profile!) {
      _DishProfile.paneer => FoodRole.protein,
      _DishProfile.soya   => FoodRole.protein,
      _                   => FoodRole.accompaniment,
    };
    final patternScalar = EatingPatternService.instance.getScalar(
      targetRole,
      contextRole: FoodRole.primary,
    ) ?? 1.0;

    final combinedScalar = (safeScalar * patternScalar).clamp(0.3, 2.5);
    final scaledCarbLoad = (effectiveCarbLoad * combinedScalar).clamp(0.5, 12.0);

    return switch (ctx.profile!) {
      _DishProfile.paneer      => _paneer(ctx, scaledCarbLoad),
      _DishProfile.lentilDal   => _dal(ctx, scaledCarbLoad, kind: _DalKind.thin),
      _DishProfile.enrichedDal => _dal(ctx, scaledCarbLoad, kind: _DalKind.tadka),
      _DishProfile.dalMakhani  => _dal(ctx, scaledCarbLoad, kind: _DalKind.makhani),
      _DishProfile.beans       => _beans(ctx, scaledCarbLoad),
      _DishProfile.drySabzi    => _drySabzi(ctx, scaledCarbLoad),
      _DishProfile.gravySabzi  => _gravySabzi(ctx, scaledCarbLoad),
      _DishProfile.soya        => _soya(ctx, scaledCarbLoad),
      _DishProfile.kadhi       => _kadhi(ctx, scaledCarbLoad),
    };
  }

  // ── Dal ─────────────────────────────────────────────────────────
  // Thin hostel dal (toor/moong/masoor/urad): ~58 kcal/100ml, ~3g protein/100ml.
  // Dal tadka / dal fry (thicker, tempered):  ~105 kcal/100ml, ~4.5g protein/100ml.
  // Dal makhani (urad + rajma, butter/cream): ~140 kcal/100ml, ~5.5g protein/100ml.

  ConsumedFloor _dal(_MealCtx ctx, double carbLoad, {required _DalKind kind}) {
    final mlPerUnit = kind == _DalKind.thin ? 60.0 : 55.0;
    final consumed  = carbLoad * mlPerUnit;
    final (kcalPer, proPer) = switch (kind) {
      _DalKind.thin    => ( 58.0, 3.0),
      _DalKind.tadka   => (105.0, 4.5),
      _DalKind.makhani => (140.0, 5.5),
    };
    // Floors: roughly what one roti's worth of that dal would give.
    final (calFloorMin, calFloorMax, proFloorMin, proFloorMax) = switch (kind) {
      _DalKind.thin    => ( 50.0,  65.0, 2.5, 3.5),
      _DalKind.tadka   => ( 90.0, 105.0, 3.5, 4.5),
      _DalKind.makhani => (120.0, 140.0, 4.5, 5.5),
    };
    final multiplier = ctx.isRestaurant ? 1.35 : 1.0;
    final label = switch (kind) {
      _DalKind.thin    => 'Thin',
      _DalKind.tadka   => 'Tadka',
      _DalKind.makhani => 'Makhani',
    };
    return ConsumedFloor(
      caloriesMin: ((consumed * kcalPer / 100) * multiplier * 0.85).clamp(calFloorMin, 600.0).toDouble(),
      caloriesMax: ((consumed * kcalPer / 100) * multiplier       ).clamp(calFloorMax, 700.0).toDouble(),
      proteinMin:  ((consumed * proPer  / 100) * multiplier * 0.85).clamp(proFloorMin, 40.0).toDouble(),
      proteinMax:  ((consumed * proPer  / 100) * multiplier       ).clamp(proFloorMax, 50.0).toDouble(),
      rationale: '$label dal: ~${consumed.toInt()}ml consumed '
                 '(${carbLoad.toStringAsFixed(1)} carb units × ${mlPerUnit.toInt()}ml/unit)',
    );
  }

  // ── Beans (Rajma / Chole / Black Chana) ─────────────────────────
  // Home/mess bean CURRY (beans + gravy), not plain boiled beans:
  //   rajma / lobia curry: ~120 kcal/100g, ~5.5g protein/100g
  //   chole (kabuli chana): ~150 kcal/100g, ~6g protein/100g
  //   kala chana curry:     ~135 kcal/100g, ~6g protein/100g

  ConsumedFloor _beans(_MealCtx ctx, double carbLoad) {
    final gPerUnit = ctx.isBlackChana ? 38.0 : 42.0;
    final consumed = carbLoad * gPerUnit;
    final isRajma  = !ctx.isBlackChana &&
        _MealCtx._hasAny(ctx.lc, ['rajma', 'rajmah', 'kidney bean', 'lobia']);
    final kcalPer  = ctx.isBlackChana ? 135.0 : isRajma ? 120.0 : 150.0;
    final proPer   = ctx.isBlackChana ?   6.0 : isRajma ?   5.5 :   6.0;
    final multiplier = ctx.isRestaurant ? 1.30 : 1.0;
    return ConsumedFloor(
      caloriesMin: ((consumed * kcalPer / 100) * multiplier * 0.88).clamp(80.0,  500.0).toDouble(),
      caloriesMax: ((consumed * kcalPer / 100) * multiplier       ).clamp(100.0, 600.0).toDouble(),
      proteinMin:  ((consumed * proPer  / 100) * multiplier * 0.88).clamp(3.5,   40.0).toDouble(),
      proteinMax:  ((consumed * proPer  / 100) * multiplier       ).clamp(4.5,   50.0).toDouble(),
      rationale: 'Beans: ~${consumed.toInt()}g consumed '
                 '(${carbLoad.toStringAsFixed(1)} units × ${gPerUnit.toInt()}g/unit)',
    );
  }

  // ── Paneer ──────────────────────────────────────────────────────
  // SPECIAL MODEL: chunks eaten fully (independent), gravy scales with carbs.
  //
  // Paneer chunk weight:
  //   Thali/compartment: ~35–45g per small compartment
  //   Mess plate serving: ~55–70g per serving
  //   Restaurant:         ~80–110g per serving
  //
  // Paneer kcal density: 265 kcal/100g, 18g protein/100g.
  // Gravy consumed per carb unit: ~28 ml (mess), ~38 ml (restaurant).
  // Gravy kcal density: ~85 kcal/100ml standard, ~130 kcal/100ml for makhani.

  ConsumedFloor _paneer(_MealCtx ctx, double carbLoad) {
    final isHeavyGravy = ctx.lc.contains('makhani') ||
        ctx.lc.contains('butter') || ctx.lc.contains('cream') ||
        ctx.lc.contains('malai') || ctx.lc.contains('korma');

    // ─ Paneer chunks ─────────────────────────────────────────────
    double chunkGMin, chunkGMax;
    if (ctx.isThali) {
      final n = ctx.compartmentCount;
      // Small thali compartment: 35–45g paneer chunks each
      chunkGMin = n * 33.0;
      chunkGMax = n * 44.0;
    } else if (ctx.isRestaurant) {
      chunkGMin = 80.0;
      chunkGMax = 115.0;
    } else {
      // Standard mess plate serving
      chunkGMin = 50.0;
      chunkGMax = 70.0;
    }

    final chunkKcalMin = chunkGMin * 2.65;
    final chunkKcalMax = chunkGMax * 2.65;
    final chunkProMin  = chunkGMin * 0.18;
    final chunkProMax  = chunkGMax * 0.18;

    // ─ Gravy/oil consumed alongside carbs ────────────────────────
    final gravyMlPerUnit = ctx.isRestaurant ? 38.0 : 28.0;
    final gravyConsumed  = carbLoad * gravyMlPerUnit;
    final gravyKcalPer   = isHeavyGravy ? 130.0 : 88.0;
    final gravyKcal      = gravyConsumed * gravyKcalPer / 100;

    final calMin = (chunkKcalMin + gravyKcal).clamp(
      ctx.isThali ? ctx.compartmentCount * 130.0 : 180.0, 1500.0).toDouble();
    final calMax = (chunkKcalMax + gravyKcal).clamp(
      ctx.isThali ? ctx.compartmentCount * 160.0 : 220.0, 1500.0).toDouble();

    return ConsumedFloor(
      caloriesMin: calMin,
      caloriesMax: calMax,
      proteinMin:  chunkProMin.clamp(
          ctx.isThali ? ctx.compartmentCount * 5.0 : 9.0, 80.0).toDouble(),
      proteinMax:  chunkProMax.clamp(
          ctx.isThali ? ctx.compartmentCount * 7.0 : 12.0, 80.0).toDouble(),
      rationale: 'Paneer: ${chunkGMin.toInt()}-${chunkGMax.toInt()}g chunks '
                 '+ ${gravyConsumed.toInt()}ml gravy/'
                 '${isHeavyGravy ? "heavy" : "regular"} '
                 '(${carbLoad.toStringAsFixed(1)} carb units)',
    );
  }

  // ── Dry Sabzi ───────────────────────────────────────────────────
  // Dry veg (aloo, bhindi, gobi, aloo matar dry):
  // ~90 kcal/100g, ~2g protein/100g.
  // More fully consumed than liquid dishes — less waste.

  ConsumedFloor _drySabzi(_MealCtx ctx, double carbLoad) {
    final gPerUnit = 52.0;
    final consumed = carbLoad * gPerUnit;
    return ConsumedFloor(
      caloriesMin: (consumed * 0.90 * 0.88).clamp(60.0, 400.0).toDouble(),
      caloriesMax: (consumed * 0.90       ).clamp(80.0, 500.0).toDouble(),
      proteinMin:  (consumed * 0.020 * 0.88).clamp(1.0, 20.0).toDouble(),
      proteinMax:  (consumed * 0.020       ).clamp(2.0, 25.0).toDouble(),
      rationale: 'Dry sabzi: ~${consumed.toInt()}g consumed',
    );
  }

  // ── Gravy Sabzi (mixed veg, methi, etc.) ────────────────────────
  ConsumedFloor _gravySabzi(_MealCtx ctx, double carbLoad) {
    final mlPerUnit = 48.0;
    final consumed  = carbLoad * mlPerUnit;
    final multiplier = ctx.isRestaurant ? 1.2 : 1.0;
    return ConsumedFloor(
      caloriesMin: ((consumed * 0.78) * multiplier * 0.85).clamp(60.0, 400.0).toDouble(),
      caloriesMax: ((consumed * 0.78) * multiplier       ).clamp(80.0, 500.0).toDouble(),
      proteinMin:  ((consumed * 0.016) * multiplier * 0.85).clamp(1.0, 20.0).toDouble(),
      proteinMax:  ((consumed * 0.016) * multiplier       ).clamp(2.0, 25.0).toDouble(),
      rationale: 'Gravy sabzi: ~${consumed.toInt()}ml consumed',
    );
  }

  // ── Soya ────────────────────────────────────────────────────────
  // Soya chunk curry (hydrated chunks + gravy): ~135 kcal/100g, ~12g protein/100g.
  // Chilli soya / kadai soya — chunk-based, more fully eaten than dal.

  ConsumedFloor _soya(_MealCtx ctx, double carbLoad) {
    final gPerUnit = 46.0;
    final consumed  = carbLoad * gPerUnit;
    return ConsumedFloor(
      caloriesMin: (consumed * 1.35 * 0.88).clamp(110.0, 500.0).toDouble(),
      caloriesMax: (consumed * 1.35       ).clamp(130.0, 600.0).toDouble(),
      proteinMin:  (consumed * 0.12 * 0.88).clamp(9.0,  50.0).toDouble(),
      proteinMax:  (consumed * 0.12       ).clamp(11.0, 60.0).toDouble(),
      rationale: 'Soya: ~${consumed.toInt()}g consumed',
    );
  }

  // ── Kadhi ───────────────────────────────────────────────────────
  // Kadhi (yogurt+besan gravy): ~58 kcal/100ml, ~2.3g protein/100ml.
  // With pakoda: adds ~100–150 kcal extra (2–3 fried besan pakodas).

  ConsumedFloor _kadhi(_MealCtx ctx, double carbLoad) {
    final mlPerUnit = 65.0;
    final consumed  = carbLoad * mlPerUnit;
    final hasPakoda = ctx.lc.contains('pakoda') || ctx.lc.contains('pakora');
    final pakodaKcalMin = hasPakoda ? 100.0 : 0.0;
    final pakodaKcalMax = hasPakoda ? 150.0 : 0.0;
    return ConsumedFloor(
      caloriesMin: ((consumed * 0.58) + pakodaKcalMin).clamp(100.0, 500.0).toDouble(),
      caloriesMax: ((consumed * 0.58) + pakodaKcalMax).clamp(130.0, 650.0).toDouble(),
      proteinMin:  (consumed * 0.023 * 0.88).clamp(3.0, 25.0).toDouble(),
      proteinMax:  (consumed * 0.023       ).clamp(4.0, 30.0).toDouble(),
      rationale: 'Kadhi: ~${consumed.toInt()}ml consumed'
                 '${hasPakoda ? " + pakoda" : ""}',
    );
  }
}

// ─── ConsumedFloor ────────────────────────────────────────────────────────────

class ConsumedFloor {
  final double caloriesMin;
  final double caloriesMax;
  final double proteinMin;
  final double proteinMax;
  final String rationale;

  const ConsumedFloor({
    required this.caloriesMin,
    required this.caloriesMax,
    required this.proteinMin,
    required this.proteinMax,
    required this.rationale,
  });
}

// ─── _DishProfile ─────────────────────────────────────────────────────────────

enum _DishProfile {
  paneer,
  lentilDal,   // toor / moong / masoor / plain urad dal (thin)
  enrichedDal, // dal tadka / dal fry (thicker, tempered)
  dalMakhani,  // dal makhani / black dal (butter + cream)
  beans,       // rajma, chole, black chana, lobia
  drySabzi,    // dry veg (aloo jeera, bhindi, gobi)
  gravySabzi,  // mixed veg curry, methi, aloo matar
  soya,        // soya chunks dishes
  kadhi,       // yogurt-based gravy
}

enum _DalKind { thin, tadka, makhani }

// ─── _MealCtx ─────────────────────────────────────────────────────────────────

class _MealCtx {
  final String lc;
  final _DishProfile? profile;
  final int    rotiCount;
  final double riceLadles;
  final bool   isThali;
  final bool   isRestaurant;
  final bool   isBlackChana;
  final int    compartmentCount;

  const _MealCtx({
    required this.lc,
    required this.profile,
    required this.rotiCount,
    required this.riceLadles,
    required this.isThali,
    required this.isRestaurant,
    required this.isBlackChana,
    required this.compartmentCount,
  });

  factory _MealCtx.parse(String lc) {
    final rotis = _countKw(lc, ['roti', 'chapati', 'chapatti', 'phulka']);
    final ladles = _parseLadles(lc);
    final isThali = _hasAny(lc, ['thali', 'compartment', 'compartments', 'tray', 'section']);
    final isRestaurant = _hasAny(lc, [
      'restaurant', 'outside', 'hotel', 'dhaba', 'fast food',
      'zomato', 'swiggy', 'cafe', 'kfc', 'domino',
    ]);
    final compartments = _parseCompartments(lc);

    // Detect the dish profile — checked in priority order.
    // Paneer takes priority over gravy-sabzi since both mention "sabzi".
    // Dal makhani / enriched dal checked before plain dal.
    final profile = _detectProfile(lc);

    return _MealCtx(
      lc:               lc,
      profile:          profile,
      rotiCount:        rotis,
      riceLadles:       ladles,
      isThali:          isThali,
      isRestaurant:     isRestaurant,
      isBlackChana:     _hasAny(lc, ['kala chana', 'kale chane', 'kale chana',
                                     'black chana', 'black channa']),
      compartmentCount: compartments,
    );
  }

  static _DishProfile? _detectProfile(String lc) {
    if (_hasAny(lc, ['paneer', 'cottage cheese'])) {
      return _DishProfile.paneer;
    }
    if (_hasAny(lc, ['soya chunk', 'chilli soya', 'kadai soya',
                      'soya bhurji', 'soya sabzi'])) {
      return _DishProfile.soya;
    }
    if (_hasAny(lc, ['kadhi'])) {
      return _DishProfile.kadhi;
    }
    if (_hasAny(lc, ['dal makhani', 'makhani dal', 'black dal',
                      'dal makahani', 'maa ki dal'])) {
      return _DishProfile.dalMakhani;
    }
    if (_hasAny(lc, ['tadka dal', 'dal tadka', 'dal fry'])) {
      return _DishProfile.enrichedDal;
    }
    // Chana dal / roasted chana are not bean curries: blank them out before
    // the broad 'chana' bean keywords run.
    final beanLc = lc.replaceAll(
        RegExp(r'chann?a\s+daa?l|chan[ae]\s+ki\s+daa?l|roasted\s+chann?a|bhuna\s+chana'),
        ' ');
    if (_hasAny(beanLc, ['rajma', 'rajmah', 'chole', 'chana masala',
                          'chickpea', 'chhole', 'kala chana',
                          'black chana', 'kidney bean', 'chana', 'chane',
                          'channa', 'white chana', 'safed chana', 'kabuli',
                          'lobia'])) {
      return _DishProfile.beans;
    }
    if (_hasAny(lc, ['dal', 'daal', 'lentil', 'moong',
                      'masoor', 'arhar', 'toor'])) {
      return _DishProfile.lentilDal;
    }
    if (_hasAny(lc, ['aloo jeera', 'bhindi', 'gobhi', 'gobi',
                      'aloo sabzi', 'dry sabzi', 'aloo matar dry',
                      'baingan'])) {
      return _DishProfile.drySabzi;
    }
    if (_hasAny(lc, ['sabzi', 'curry', 'gravy', 'mixed veg',
                      'methi', 'palak', 'saag'])) {
      return _DishProfile.gravySabzi;
    }
    return null;
  }

  static int _countKw(String lc, List<String> kws) {
    int total = 0;
    for (final kw in kws) {
      final ms = RegExp(r'(\d+)\s+' + RegExp.escape(kw)).allMatches(lc);
      for (final m in ms) { total += int.tryParse(m.group(1)!) ?? 0; }
      if (total == 0 && lc.contains(kw)) total = 1;
    }
    return total;
  }

  static double _parseLadles(String lc) {
    if (!lc.contains('rice') && !lc.contains('chawal')) return 0;
    final m = RegExp(r'(\d+(?:\.\d+)?)\s*(?:ladle|ladles|scoop|scoops)')
        .firstMatch(lc);
    if (m != null) return double.tryParse(m.group(1)!) ?? 1.0;
    if (lc.contains('ladle') || lc.contains('scoop')) return 1.0;
    // Bowl/katori of rice = roughly 1.5 ladles
    if (_hasAny(lc, ['bowl rice', 'katori rice', 'bowl of rice'])) return 1.5;
    return 0;
  }

  static int _parseCompartments(String lc) {
    final m = RegExp(r'(\d+)\s*compartments?').firstMatch(lc);
    if (m != null) return (int.tryParse(m.group(1)!) ?? 1).clamp(1, 8);
    if (lc.contains('compartment')) return 1;
    return 1;
  }

  static bool _hasAny(String lc, List<String> needles) =>
      needles.any(lc.contains);
}
