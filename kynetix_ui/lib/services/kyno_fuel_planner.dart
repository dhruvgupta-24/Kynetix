// What should I eat to land on my targets?
//
// Pure planning over two pools: foods the user has actually logged (with the
// macros they logged them at) and a curated catalog of everyday Indian foods
// they may never have tried in the app. It ranks single foods and builds
// 1-3 item combinations that close the remaining protein without blowing the
// remaining calories. Kyno shows the result as tappable cards and hands the
// same list to the model so its advice uses real numbers.

import 'dart:math' as math;

import '../data/kyno_food_catalog.dart';
import '../models/day_log.dart';

/// What's left of the day's targets (never negative except [kcal], which is
/// negative when the user is already over).
class FuelGap {
  const FuelGap({
    required this.kcal,
    required this.protein,
    this.carbs,
    this.fat,
  });

  final double kcal;
  final double protein;
  final double? carbs;
  final double? fat;

  bool get caloriesDone => kcal < 120;
  bool get proteinDone => protein < 8;
  bool get done => caloriesDone && proteinDone;
}

/// One food with the macros of one serving.
class FuelFood {
  const FuelFood({
    required this.name,
    required this.serving,
    required this.kcal,
    required this.protein,
    this.carbs = 0,
    this.fat = 0,
    this.timesLogged = 0,
    this.fromHistory = false,
    this.diet = FoodDiet.veg,
    this.noCook = false,
    this.lastLogged,
    String? logAs,
  }) : _logAs = logAs;

  factory FuelFood.fromCatalog(CatalogFood c) => FuelFood(
        logAs: c.logText,
        name: c.name,
        serving: c.serving,
        kcal: c.kcal,
        protein: c.protein,
        carbs: c.carbs,
        fat: c.fat,
        diet: c.diet,
        noCook: c.noCook,
      );

  final String name;

  /// "200 g", "1 katori", or "as you logged it" for history foods.
  final String serving;
  final double kcal;
  final double protein;
  final double carbs;
  final double fat;
  final int timesLogged;
  final bool fromHistory;
  final FoodDiet diet;
  final bool noCook;
  final DateTime? lastLogged;

  final String? _logAs;

  /// What goes into the meal box when the user taps it.
  String get logText => fromHistory ? name : (_logAs ?? '$serving $name');

  double get proteinShare => kcal <= 0 ? 0 : (protein * 4 / kcal).clamp(0.0, 1.0);

  Map<String, dynamic> toJson() => {
        'name': name,
        if (!fromHistory) 'serving': serving,
        'kcal': kcal.round(),
        'protein_g': protein.round(),
        'carbs_g': carbs.round(),
        'fat_g': fat.round(),
        if (fromHistory) 'times_logged': timesLogged,
      };
}

class FuelPick {
  const FuelPick(this.food, this.score);
  final FuelFood food;
  final double score;
}

class FuelCombo {
  const FuelCombo(this.items, this.error);
  final List<FuelFood> items;

  /// Lower is closer to the gap.
  final double error;

  double get kcal => items.fold(0.0, (s, f) => s + f.kcal);
  double get protein => items.fold(0.0, (s, f) => s + f.protein);
  double get carbs => items.fold(0.0, (s, f) => s + f.carbs);
  double get fat => items.fold(0.0, (s, f) => s + f.fat);

  Map<String, dynamic> toJson() => {
        'items': [for (final f in items) f.logText],
        'kcal': kcal.round(),
        'protein_g': protein.round(),
      };
}

class FuelPlan {
  const FuelPlan({
    required this.gap,
    required this.headline,
    required this.yours,
    required this.newIdeas,
    required this.combos,
  });

  final FuelGap gap;

  /// One plain sentence: what to aim for.
  final String headline;

  /// Foods from the user's own log that fit.
  final List<FuelPick> yours;

  /// Foods they may never have logged that fit.
  final List<FuelPick> newIdeas;

  /// Ready-made combinations that land near the gap, best first.
  final List<FuelCombo> combos;

  bool get isEmpty => yours.isEmpty && newIdeas.isEmpty && combos.isEmpty;

  Map<String, dynamic> toJson() => {
        'remaining': {
          'kcal': gap.kcal.round(),
          'protein_g': gap.protein.round(),
          if (gap.carbs != null) 'carbs_g': gap.carbs!.round(),
          if (gap.fat != null) 'fat_g': gap.fat!.round(),
        },
        'from_their_log': [for (final p in yours) p.food.toJson()],
        'new_ideas': [for (final p in newIdeas) p.food.toJson()],
        'combos': [for (final c in combos) c.toJson()],
      };
}

abstract final class KynoFuelPlanner {
  /// Meals worth suggesting are a snack to a full plate.
  static const double _minKcal = 30;
  static const double _maxKcal = 1200;

  static FuelPlan plan({
    required FuelGap gap,
    required List<FuelFood> history,
    List<CatalogFood> catalog = kynoFoodCatalog,
    Set<FoodDiet> diets = const {FoodDiet.veg},
    FoodSlot? slot,
    int maxEach = 4,
    bool fastingOnly = false,
    DateTime? today,
  }) {
    if (gap.done) {
      return FuelPlan(
        gap: gap,
        headline: gap.kcal < -150
            ? "You're past today's calories. If you're hungry, keep it to lean protein or veg."
            : "You're on target for today. Nothing more needed.",
        yours: const [],
        newIdeas: const [],
        combos: const [],
      );
    }

    bool eatenToday(FuelFood f) {
      final l = f.lastLogged;
      return today != null && l != null && l.year == today.year && l.month == today.month && l.day == today.day;
    }

    final usable = history
        .where((f) => f.kcal >= _minKcal && f.kcal <= _maxKcal && diets.contains(f.diet))
        // Already had it today: suggesting it again reads as a repeat.
        .where((f) => !eatenToday(f))
        // On a vrat day only foods allowed on the fast.
        .where((f) => !fastingOnly || isFastingFriendlyName(f.name))
        .toList();
    final fresh = [
      for (final c in catalog)
        if (diets.contains(c.diet) &&
            (fastingOnly ? c.isFasting : (slot == null || c.slots.contains(slot))))
          FuelFood.fromCatalog(c),
    ];
    // Don't suggest a "new" food the user already logs.
    final known = {for (final f in usable) _norm(f.name)};
    fresh.removeWhere((f) => known.contains(_norm(f.name)));

    final rankedYours = _rank(usable, gap);
    final rankedNew = _rank(fresh, gap);

    final pool = <FuelFood>[
      ...rankedYours.take(10).map((p) => p.food),
      ...rankedNew.take(12).map((p) => p.food),
    ];
    final combos = _combos(pool, gap);

    return FuelPlan(
      gap: gap,
      headline: _headline(gap),
      yours: rankedYours.where((p) => p.score > 0.45).take(maxEach).toList(),
      newIdeas: rankedNew.where((p) => p.score > 0.45).take(maxEach).toList(),
      combos: combos,
    );
  }

  /// Infers what the user eats from their log: egg and meat words widen the
  /// pool; a log with neither stays vegetarian.
  static Set<FoodDiet> inferDiets(Iterable<String> loggedNames) {
    var egg = false;
    var meat = false;
    for (final raw in loggedNames) {
      final n = raw.toLowerCase();
      if (_meatWords.any(n.contains)) meat = true;
      if (_eggWords.any(n.contains)) egg = true;
      if (meat && egg) break;
    }
    return {
      FoodDiet.veg,
      if (egg || meat) FoodDiet.egg,
      if (meat) FoodDiet.nonVeg,
    };
  }

  static FoodDiet dietOf(String name) {
    final n = name.toLowerCase();
    if (_meatWords.any(n.contains)) return FoodDiet.nonVeg;
    if (_eggWords.any(n.contains)) return FoodDiet.egg;
    return FoodDiet.veg;
  }

  /// The meal slot for a time of day.
  static FoodSlot slotAt(DateTime t) {
    final h = t.hour;
    if (h < 11) return FoodSlot.breakfast;
    if (h >= 22 || h < 4) return FoodSlot.late;
    if ((h >= 11 && h < 15) || (h >= 19 && h < 22)) return FoodSlot.main;
    return FoodSlot.snack;
  }

  /// Foods from the last [days] of logs, grouped by name with the average
  /// macros they were logged at.
  static List<FuelFood> historyFrom(
    Map<String, DayLog> store, {
    required DateTime today,
    int days = 60,
  }) {
    final cutoff = DateTime(today.year, today.month, today.day).subtract(Duration(days: days));
    final groups = <String, _Agg>{};
    store.forEach((key, log) {
      final date = DateTime.tryParse(key);
      if (date == null || date.isBefore(cutoff)) return;
      for (final e in log.allEntries) {
        final name = (e.finalSavedInput.isNotEmpty ? e.finalSavedInput : e.rawInput).trim();
        if (name.isEmpty) continue;
        final r = e.result;
        final kcal = e.calMid;
        if (kcal <= 0) continue;
        final agg = groups.putIfAbsent(_norm(name), () => _Agg(name));
        agg.add(
          kcal: kcal,
          protein: e.protMid,
          carbs: r.carbohydrates == null ? 0 : (r.carbohydrates!.min + r.carbohydrates!.max) / 2,
          fat: r.fat == null ? 0 : (r.fat!.min + r.fat!.max) / 2,
          at: date,
        );
      }
    });
    final out = [for (final a in groups.values) a.toFood()];
    out.sort((a, b) => b.timesLogged.compareTo(a.timesLogged));
    return out;
  }

  // ── Scoring ────────────────────────────────────────────────────────────────

  static List<FuelPick> _rank(List<FuelFood> foods, FuelGap gap) {
    final picks = [for (final f in foods) FuelPick(f, _score(f, gap))];
    picks.sort((a, b) => b.score.compareTo(a.score));
    return picks;
  }

  static double _score(FuelFood f, FuelGap gap) {
    final kcalLeft = math.max(gap.kcal, 0.0);
    // Calories done but protein isn't: only lean protein makes sense.
    if (gap.caloriesDone) {
      if (f.kcal > 180 || f.protein < 10) return 0;
      return (f.proteinShare).clamp(0.0, 1.0);
    }
    // How much of the remaining calories should be protein.
    final need = (gap.protein * 4 / kcalLeft).clamp(0.0, 1.0);
    // Leaner than needed is a real miss; denser than needed only costs a
    // little (it frees calories for later).
    final share = f.proteinShare;
    final match = share >= need
        ? 1 - 0.4 * math.min(1.0, (share - need) / (1.15 - need))
        : 1 - math.min(1.0, (need - share) / math.max(need, 0.15));
    final size = f.kcal / kcalLeft;
    final double sizeScore;
    if (size <= 1.05) {
      sizeScore = size >= 0.2 ? 1.0 : size / 0.2;
    } else {
      sizeScore = math.max(0.0, 1 - (size - 1.05) * 3);
    }
    final familiar = f.fromHistory ? math.min(1.0, f.timesLogged / 5) : (f.noCook ? 0.4 : 0.2);
    var score = 0.6 * match + 0.25 * sizeScore + 0.15 * familiar;
    // Fat already used up: lean options first.
    final fatLeft = gap.fat;
    if (fatLeft != null && fatLeft < 5 && f.fat > 8) score -= 0.2;
    return score;
  }

  static List<FuelCombo> _combos(List<FuelFood> pool, FuelGap gap) {
    if (pool.isEmpty) return const [];
    final kcalLeft = math.max(gap.kcal, 0.0);
    final scored = <FuelCombo>[];

    double err(List<FuelFood> items) {
      final k = items.fold(0.0, (s, f) => s + f.kcal);
      final p = items.fold(0.0, (s, f) => s + f.protein);
      final fat = items.fold(0.0, (s, f) => s + f.fat);
      var e = 0.0;
      e += (math.max(0.0, gap.protein - p)) / math.max(gap.protein, 10) * 1.2;
      e += (math.max(0.0, p - gap.protein - 15)) / 40 * 0.3;
      e += math.max(0.0, k - kcalLeft - 40) / math.max(kcalLeft, 100) * 2.0;
      e += math.max(0.0, kcalLeft - k) / math.max(kcalLeft, 100) * 0.5;
      final fatLeft = gap.fat;
      if (fatLeft != null) e += math.max(0.0, fat - fatLeft - 8) / 25 * 0.4;
      e += 0.06 * (items.length - 1);
      e -= 0.04 * items.where((f) => f.fromHistory).length;
      return e;
    }

    // Foods from the log can be whole meals ("50 g oats + 1 scoop whey"), so
    // two of them may share a part. A combo never repeats a part, however
    // it is measured: "1 scoop whey" and "whey" are the same food.
    final partsOf = [for (final f in pool) _parts('${f.name},${f.logText}')];
    bool clash(int a, int b) {
      for (final x in partsOf[a]) {
        for (final y in partsOf[b]) {
          if (x == y || ' $x '.contains(' $y ') || ' $y '.contains(' $x ')) return true;
        }
      }
      return false;
    }

    final n = pool.length;
    for (var i = 0; i < n; i++) {
      scored.add(FuelCombo([pool[i]], err([pool[i]])));
      for (var j = i + 1; j < n; j++) {
        if (clash(i, j)) continue;
        final two = [pool[i], pool[j]];
        scored.add(FuelCombo(two, err(two)));
        for (var k = j + 1; k < n; k++) {
          if (clash(i, k) || clash(j, k)) continue;
          final three = [pool[i], pool[j], pool[k]];
          scored.add(FuelCombo(three, err(three)));
        }
      }
    }
    scored.sort((a, b) => a.error.compareTo(b.error));

    // Three combos that don't repeat each other's lead food.
    final out = <FuelCombo>[];
    final usedLeads = <String>{};
    for (final c in scored) {
      if (c.kcal > kcalLeft + 120) continue;
      final lead = _norm(c.items.first.name);
      if (usedLeads.contains(lead)) continue;
      usedLeads.add(lead);
      out.add(c);
      if (out.length == 3) break;
    }
    return out;
  }

  static String _headline(FuelGap gap) {
    final k = gap.kcal.round();
    final p = gap.protein.round();
    if (gap.caloriesDone && !gap.proteinDone) {
      return 'Calories are basically done. Close the last $p g of protein with something lean.';
    }
    if (gap.proteinDone) {
      return 'Protein is covered. You have about $k kcal left for whatever you like.';
    }
    return 'You have $k kcal and $p g of protein left today.';
  }

  /// The foods in a name, without amounts: "50 g oats + 1 scoop whey in
  /// milk" gives {oats, whey in milk}.
  static Set<String> _parts(String name) => {
        for (final p in name.split(RegExp(r'[+,&]|\band\b|\bwith\b')))
          if (_core(p).isNotEmpty) _core(p),
      };

  static final _amount = RegExp(
    r'\b(\d+(\.\d+)?|half|one|two|three|a|an|of|g|gm|gms|grams?|kg|ml|l|scoops?|katoris?|cups?|bowls?|'
    r'pieces?|pcs?|slices?|tbsp|tsp|servings?|plates?|glass(es)?|small|medium|large|big)\b',
  );

  static String _core(String s) =>
      _norm(_norm(s).replaceAll(_amount, ' '));

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  static const _meatWords = [
    'chicken', 'mutton', 'fish', 'prawn', 'shrimp', 'tuna', 'salmon', 'keema',
    'beef', 'pork', 'lamb', 'turkey', 'crab', 'basa', 'rohu', 'biryani chicken',
  ];
  static const _eggWords = ['egg', 'omelette', 'omelet', 'anda', 'bhurji egg'];
}

class _Agg {
  _Agg(this.name);
  final String name;
  double kcal = 0, protein = 0, carbs = 0, fat = 0;
  int count = 0;
  DateTime? last;

  void add({
    required double kcal,
    required double protein,
    required double carbs,
    required double fat,
    required DateTime at,
  }) {
    this.kcal += kcal;
    this.protein += protein;
    this.carbs += carbs;
    this.fat += fat;
    count++;
    if (last == null || at.isAfter(last!)) last = at;
  }

  FuelFood toFood() => FuelFood(
        name: name,
        serving: 'as you log it',
        kcal: kcal / count,
        protein: protein / count,
        carbs: carbs / count,
        fat: fat / count,
        timesLogged: count,
        fromHistory: true,
        diet: KynoFuelPlanner.dietOf(name),
        lastLogged: last,
      );
}
