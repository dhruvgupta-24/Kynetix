// Micronutrient totals, coverage and "where to get more" from the day logs.
//
// Coverage honesty: an item contributes only when it carries micros. A meal
// counts as tracked for a nutrient when items carrying it make up at least
// [MicronutrientService.trackedShare] of the meal's calories; a day counts
// toward an average under the same rule. Untracked never means zero, so old
// entries (logged before micros existed) show up as "not tracked".

import 'dart:math' as math;

import '../data/kyno_food_catalog.dart';
import '../data/micronutrient_library.dart';
import '../models/day_log.dart';
import '../models/micronutrients.dart';
import '../models/user_profile.dart';
import 'kyno_fuel_planner.dart';
import 'micronutrient_targets.dart';

/// One nutrient over one meal, day or window.
class MicroAmount {
  const MicroAmount({
    required this.amount,
    required this.trackedKcal,
    required this.totalKcal,
  });

  /// Sum over items that carry this nutrient.
  final double amount;
  final double trackedKcal;
  final double totalKcal;

  /// Share of calories whose micros are known (1.0 when nothing was eaten).
  double get coverage => totalKcal <= 0 ? 0 : (trackedKcal / totalKcal).clamp(0.0, 1.0);
  bool get isTracked => totalKcal > 0 && coverage >= MicronutrientService.trackedShare;
}

/// Today's (or any day's) picture for one nutrient.
class MicroDay {
  const MicroDay({required this.amount, required this.trackedMeals, required this.meals, required this.coverage});

  /// Known amount (a floor when some meals aren't tracked).
  final double amount;
  final int trackedMeals;
  final int meals;

  /// Calorie share of the day with known values.
  final double coverage;

  bool get isTracked => meals > 0 && coverage >= MicronutrientService.trackedShare;
  bool get hasAny => trackedMeals > 0 || amount > 0;
}

/// One row on the nutrients screen.
class MicroStatus {
  const MicroStatus({
    required this.micro,
    required this.target,
    required this.today,
    required this.avg7,
    required this.avgDays,
  });

  final Micro micro;
  final MicroTarget target;
  final MicroDay today;

  /// Average over the previous 7 days that were tracked; null when none were.
  final double? avg7;

  /// How many of the previous 7 days fed [avg7].
  final int avgDays;

  double get todayRatio => target.amount <= 0 ? 0 : today.amount / target.amount;
  double? get avgRatio => avg7 == null || target.amount <= 0 ? null : avg7! / target.amount;

  /// Below 70% of the RDA on average (or above the limit, for sodium).
  bool get isLow => !micro.isLimit && (avgRatio ?? 1) < 0.7;
  bool get isOver => micro.isLimit && (avgRatio ?? 0) > 1.0;
}

class MicroSummary {
  const MicroSummary({
    required this.statuses,
    required this.mealsToday,
    required this.trackedMealsToday,
    required this.diets,
  });

  final List<MicroStatus> statuses;
  final int mealsToday;

  /// Meals today whose micros are known (tracked for at least one nutrient
  /// beyond sodium, i.e. a real micro record rather than nothing).
  final int trackedMealsToday;
  final Set<FoodDiet> diets;

  MicroStatus of(Micro m) => statuses.firstWhere((s) => s.micro == m);

  /// The nutrient furthest below target on the 7-day average; falls back to
  /// today's tracked total when there is no history yet. Null when nothing
  /// is tracked at all.
  MicroStatus? get lowest {
    MicroStatus? best;
    double bestRatio = double.infinity;
    for (final s in statuses) {
      if (s.micro.isLimit) continue;
      final r = s.avgRatio ?? (s.today.isTracked ? s.todayRatio : null);
      if (r == null) continue;
      if (r < bestRatio) {
        bestRatio = r;
        best = s;
      }
    }
    return best;
  }

  bool get hasHistory => statuses.any((s) => s.avg7 != null);
}

/// A food rich in one nutrient.
class MicroFoodPick {
  const MicroFoodPick({
    required this.name,
    required this.serving,
    required this.amount,
    required this.kcal,
    required this.fromHistory,
    required this.logText,
  });

  final String name;
  final String serving;
  final double amount;
  final double kcal;
  final bool fromHistory;
  final String logText;
}

class MicronutrientService {
  MicronutrientService._();
  static final MicronutrientService instance = MicronutrientService._();

  /// Calorie share that must be known before a meal or day counts as tracked.
  static const double trackedShare = 0.8;

  // ── Aggregation ────────────────────────────────────────────────────────────

  /// One meal, one nutrient.
  static MicroAmount ofEntry(MealEntry e, Micro m) {
    final items = e.result.items;
    final total = math.max(e.calMid, 0.0);
    if (items.isEmpty) return MicroAmount(amount: 0, trackedKcal: 0, totalKcal: total);
    var amount = 0.0, tracked = 0.0, itemKcal = 0.0;
    for (final i in items) {
      final k = math.max(i.calories.mid, 0.0);
      itemKcal += k;
      final v = i.micros?[m];
      if (v == null) continue;
      amount += v;
      tracked += k;
    }
    // Items don't always sum to the entry (edited totals); judge coverage on
    // the items, report against the entry.
    final share = itemKcal <= 0 ? (tracked > 0 ? 1.0 : 0.0) : tracked / itemKcal;
    return MicroAmount(amount: amount, trackedKcal: share * total, totalKcal: total);
  }

  /// Whether a meal carries any micro record at all.
  static bool entryHasMicros(MealEntry e) => e.result.items.any((i) => i.micros != null && !i.micros!.isEmpty);

  static MicroDay ofDay(DayLog? log, Micro m) {
    if (log == null) return const MicroDay(amount: 0, trackedMeals: 0, meals: 0, coverage: 0);
    var amount = 0.0, tracked = 0.0, total = 0.0;
    var meals = 0, trackedMeals = 0;
    for (final e in log.allEntries) {
      final a = ofEntry(e, m);
      meals++;
      amount += a.amount;
      tracked += a.trackedKcal;
      total += a.totalKcal;
      if (a.isTracked) trackedMeals++;
    }
    return MicroDay(
      amount: amount,
      trackedMeals: trackedMeals,
      meals: meals,
      coverage: total <= 0 ? 0 : (tracked / total).clamp(0.0, 1.0),
    );
  }

  /// Average daily amount over the [days] days before [today], counting only
  /// days that were tracked. Returns (average, daysUsed).
  static (double?, int) average(Map<String, DayLog> store, Micro m, DateTime today, {int days = 7}) {
    final d0 = DateTime(today.year, today.month, today.day);
    var sum = 0.0;
    var n = 0;
    for (var i = 1; i <= days; i++) {
      final d = ofDay(store[dateKey(d0.subtract(Duration(days: i)))], m);
      if (!d.isTracked) continue;
      sum += d.amount;
      n++;
    }
    return (n == 0 ? null : sum / n, n);
  }

  MicroSummary summarize({
    required Map<String, DayLog> store,
    required DateTime today,
    UserProfile? profile,
  }) {
    final targets = MicronutrientTargets.forProfile(profile);
    final todayLog = store[dateKey(today)];
    final statuses = <MicroStatus>[];
    for (final m in Micro.values) {
      final (avg, n) = average(store, m, today);
      statuses.add(MicroStatus(
        micro: m,
        target: targets[m]!,
        today: ofDay(todayLog, m),
        avg7: avg,
        avgDays: n,
      ));
    }
    final entries = todayLog?.allEntries ?? const <MealEntry>[];
    final history = KynoFuelPlanner.historyFrom(store, today: today);
    return MicroSummary(
      statuses: statuses,
      mealsToday: entries.length,
      trackedMealsToday: entries.where(entryHasMicros).length,
      diets: KynoFuelPlanner.inferDiets(history.map((f) => f.name)),
    );
  }

  // ── Oracle: where to get more ──────────────────────────────────────────────

  /// Foods rich in [m]: first ones the user already eats (from their logged
  /// items that carry micros), then catalog foods that fit their diet.
  /// Each pick carries the amount in one serving as eaten or as listed.
  List<MicroFoodPick> richFoods(
    Micro m, {
    required Map<String, DayLog> store,
    required DateTime today,
    required Set<FoodDiet> diets,
    required double target,
    int maxEach = 3,
    int historyDays = 60,
    bool fastingOnly = false,
  }) {
    final minUseful = target * 0.08;

    // From their log: per food name, the average amount per logged portion.
    final cutoff = DateTime(today.year, today.month, today.day).subtract(Duration(days: historyDays));
    final groups = <String, _MicroAgg>{};
    store.forEach((key, log) {
      final date = DateTime.tryParse(key);
      if (date == null || date.isBefore(cutoff)) return;
      for (final e in log.allEntries) {
        for (final i in e.result.items) {
          final v = i.micros?[m];
          if (v == null || v <= 0) continue;
          final name = i.name.trim();
          if (name.isEmpty) continue;
          if (!diets.contains(KynoFuelPlanner.dietOf(name))) continue;
          if (fastingOnly && !isFastingFriendlyName(name)) continue;
          groups.putIfAbsent(_norm(name), () => _MicroAgg(name, i.quantity, i.unit)).add(v, i.calories.mid);
        }
      }
    });
    final yours = [
      for (final g in groups.values)
        if (g.avg >= minUseful)
          MicroFoodPick(
            name: g.name,
            serving: g.servingLabel,
            amount: g.avg,
            kcal: g.kcal,
            fromHistory: true,
            logText: g.logText,
          ),
    ]..sort((a, b) => b.amount.compareTo(a.amount));

    // From the catalog, scaled to its listed serving.
    final seen = {for (final p in yours) _norm(p.name)};
    final fresh = <MicroFoodPick>[];
    for (final c in kynoFoodCatalog) {
      if (!diets.contains(c.diet)) continue;
      if (fastingOnly && !c.isFasting) continue;
      if (seen.contains(_norm(c.name))) continue;
      final micros = MicronutrientLibrary.instance.estimate(c.name, c.kcal);
      final v = micros?[m];
      if (v == null || v < minUseful) continue;
      fresh.add(MicroFoodPick(
        name: c.name,
        serving: c.serving,
        amount: v,
        kcal: c.kcal,
        fromHistory: false,
        logText: c.logText,
      ));
    }
    fresh.sort((a, b) => b.amount.compareTo(a.amount));

    return [...yours.take(maxEach), ...fresh.take(maxEach)];
  }

  /// One plain line on how to close the gap, aware of a vegetarian log.
  static String tipFor(Micro m, Set<FoodDiet> diets) {
    final veg = !diets.contains(FoodDiet.egg) && !diets.contains(FoodDiet.nonVeg);
    return switch (m) {
      Micro.iron => 'Pair iron foods with something sour like lemon or amla, and keep tea and coffee away from meals. They block absorption.',
      Micro.calcium => veg
          ? 'Curd, paneer, ragi and calcium-set tofu do the heavy lifting. A glass of milk is about 300 mg.'
          : 'Curd, paneer, milk and ragi do the heavy lifting. A glass of milk is about 300 mg.',
      Micro.vitaminB12 => veg
          ? 'B12 comes almost only from animal foods. Dairy helps, but many vegetarians still fall short. Worth asking a doctor about a test or supplement.'
          : 'Eggs, fish, chicken and dairy all carry B12. Fish and mutton carry the most.',
      Micro.vitaminD => "Food barely moves vitamin D. Midday sun on your arms helps most; if you're mostly indoors, a doctor can check your level.",
      Micro.sodium => 'Most sodium hides in packaged snacks, pickles, papad and instant noodles more than in home cooking.',
      Micro.potassium => 'Dal, rajma, chole, bananas, potatoes and curd are easy potassium wins.',
      Micro.magnesium => 'Nuts, seeds, whole grains and dals carry the most. Pumpkin seeds are a cheap shortcut.',
      Micro.zinc => veg
          ? 'Dals, chickpeas, paneer, seeds and whole grains. Soaking or sprouting dals helps you absorb more.'
          : 'Mutton, chicken, eggs, dals and seeds. Mutton carries the most.',
    };
  }

  // ── Brief (for Kyno) ───────────────────────────────────────────────────────

  /// Compact 7-day picture for the coach model. Null when nothing is tracked
  /// yet, so Kyno says it doesn't know rather than guessing.
  Map<String, dynamic>? briefJson({
    required Map<String, DayLog> store,
    required DateTime today,
    UserProfile? profile,
  }) {
    final s = summarize(store: store, today: today, profile: profile);
    final anyToday = s.statuses.any((x) => x.today.hasAny);
    if (!s.hasHistory && !anyToday) return null;
    final low = s.lowest;
    return {
      'source': MicronutrientTargets.citation,
      'note': 'Averages use only tracked days. Untracked meals are missing data, not zero.',
      'meals_today': s.mealsToday,
      'meals_today_with_micros': s.trackedMealsToday,
      'nutrients': [
        for (final x in s.statuses)
          {
            'name': x.micro.label,
            'unit': x.micro.unit,
            if (x.micro.isLimit) 'limit': _r1(x.target.amount) else 'target': _r1(x.target.amount),
            if (x.avg7 != null) 'avg_7d': _r1(x.avg7!),
            if (x.avgRatio != null) 'avg_pct_of_target': (x.avgRatio! * 100).round(),
            'tracked_days_7d': x.avgDays,
            'today_so_far': _r1(x.today.amount),
            'today_coverage_pct': (x.today.coverage * 100).round(),
          },
      ],
      if (low != null) 'lowest': low.micro.label,
      if (low != null)
        'rich_foods_for_lowest': [
          for (final p in richFoods(low.micro,
              store: store, today: today, diets: s.diets, target: low.target.amount))
            {
              'food': p.fromHistory ? p.name : '${p.serving} ${p.name}',
              'amount': _r1(p.amount),
              'unit': low.micro.unit,
              'from_their_log': p.fromHistory,
            },
        ],
    };
  }

  static double _r1(double v) => (v * 10).round() / 10;
  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

class _MicroAgg {
  _MicroAgg(this.name, this.quantity, this.unit);
  final String name;
  final double quantity;
  final String unit;
  double sum = 0, kcalSum = 0;
  int n = 0;

  void add(double v, double kcal) {
    sum += v;
    kcalSum += kcal;
    n++;
  }

  double get avg => n == 0 ? 0 : sum / n;
  double get kcal => n == 0 ? 0 : kcalSum / n;

  String get servingLabel {
    if (unit == 'serving' || unit.isEmpty) return 'as you log it';
    final q = quantity == quantity.roundToDouble() ? quantity.round().toString() : quantity.toStringAsFixed(1);
    return '$q $unit';
  }

  String get logText {
    if (unit == 'serving' || unit.isEmpty) return name;
    return '$servingLabel $name';
  }
}
