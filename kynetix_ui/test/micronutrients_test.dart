import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kynetix/data/kyno_food_catalog.dart';
import 'package:kynetix/data/micronutrient_library.dart';
import 'package:kynetix/models/barcode_product.dart';
import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/models/user_profile.dart';
import 'package:kynetix/services/barcode_food_service.dart';
import 'package:kynetix/services/kyno_brief_service.dart';
import 'package:kynetix/services/kyno_fuel_planner.dart';
import 'package:kynetix/services/micronutrient_service.dart';
import 'package:kynetix/services/micronutrient_targets.dart';
import 'package:kynetix/services/mock_estimation_service.dart' show NutrientRange;
import 'package:kynetix/services/profile_service.dart';
import 'package:kynetix/services/workout_service.dart';

NutrientRange _r(double v) => NutrientRange(min: v, max: v);

NutritionItem item(String name, double kcal, {Micronutrients? micros}) => NutritionItem(
      name: name,
      quantity: 1,
      unit: 'serving',
      estimated: false,
      mode: EstimationMode.directQuantity,
      calories: _r(kcal),
      protein: _r(5),
      micros: micros,
    );

MealEntry entry(List<NutritionItem> items, DateTime at, {MealSection s = MealSection.lunch}) {
  final kcal = items.fold(0.0, (a, i) => a + i.calories.mid);
  final name = items.map((i) => i.name).join(' + ');
  return MealEntry(
    rawInput: name,
    finalSavedInput: name,
    section: s,
    addedAt: at,
    dayOfWeek: at.weekday,
    parsedFoods: [for (final i in items) i.name],
    result: NutritionResult(
      canonicalMeal: name,
      items: items,
      calories: _r(kcal),
      protein: _r(10),
      confidence: 0.9,
      warnings: const [],
      source: 'test',
      createdAt: at,
    ),
  );
}

/// Library-stamped item, as the pipeline would log it.
NutritionItem logged(String name, double kcal) =>
    item(name, kcal, micros: MicronutrientLibrary.instance.estimate(name, kcal));

void main() {
  group('targets (ICMR-NIN 2020)', () {
    test('men and women get the published adult values', () {
      final m = MicronutrientTargets.forPerson(sex: 'Male', age: 25);
      final f = MicronutrientTargets.forPerson(sex: 'Female', age: 25);
      expect(m[Micro.iron]!.amount, 19);
      expect(f[Micro.iron]!.amount, 29);
      expect(m[Micro.calcium]!.amount, 1000);
      expect(f[Micro.calcium]!.amount, 1000);
      expect(m[Micro.vitaminB12]!.amount, 2.5);
      expect(m[Micro.vitaminD]!.amount, 15);
      expect(m[Micro.potassium]!.amount, 3500);
      expect(m[Micro.magnesium]!.amount, 440);
      expect(f[Micro.magnesium]!.amount, 370);
      expect(m[Micro.zinc]!.amount, 17);
      expect(f[Micro.zinc]!.amount, 13.2);
    });

    test('sodium is a 2000 mg limit, not a target', () {
      final t = MicronutrientTargets.forPerson(sex: 'Male', age: 30)[Micro.sodium]!;
      expect(t.amount, 2000);
      expect(t.isLimit, isTrue);
      expect(Micro.values.where((m) => m.isLimit), [Micro.sodium]);
    });

    test('women 50+ need more calcium and less iron', () {
      final f = MicronutrientTargets.forPerson(sex: 'female', age: 55);
      expect(f[Micro.calcium]!.amount, 1200);
      expect(f[Micro.iron]!.amount, 19);
    });

    test('missing or unclear sex falls back to the male table', () {
      final t = MicronutrientTargets.forProfile(null);
      expect(t[Micro.iron]!.amount, 19);
      expect(MicronutrientTargets.forPerson(sex: 'Other')[Micro.zinc]!.amount, 17);
    });
  });

  group('model and JSON', () {
    test('old item JSON reads with micros null and writes without the key', () {
      final old = {
        'name': 'roti',
        'quantity': 2,
        'unit': 'piece',
        'calories': {'min': 200, 'max': 200},
        'protein': {'min': 6, 'max': 6},
      };
      final i = NutritionItem.fromJson(old);
      expect(i.micros, isNull);
      expect(i.toJson().containsKey('micros'), isFalse);
    });

    test('micros round-trip and scale with the portion', () {
      final i = logged('roti', 200);
      final back = NutritionItem.fromJson(jsonDecode(jsonEncode(i.toJson())) as Map<String, dynamic>);
      expect(back.micros, i.micros);
      expect(back.micros![Micro.iron], closeTo(2.4, 0.01));
      expect(i.withScalar(0.5).micros![Micro.iron], closeTo(1.2, 0.01));
      expect(i.normalizedUncertainty().micros, i.micros);
    });

    test('a stored meal without micros still loads and keeps its macros', () {
      final json = {
        'canonicalMeal': '2 roti + dal',
        'items': [
          {'name': 'roti', 'quantity': 2, 'unit': 'piece', 'calories': {'min': 200, 'max': 200}, 'protein': {'min': 6, 'max': 6}},
        ],
        'calories': {'min': 200, 'max': 200},
        'protein': {'min': 6, 'max': 6},
        'source': 'ai',
        'createdAt': '2026-10-01T13:00:00.000',
      };
      final r = NutritionResult.fromJson(json);
      expect(r.calories.mid, 200);
      expect(r.items.single.micros, isNull);
    });

    test('tolerant reader keeps known keys, drops junk, returns null when empty', () {
      final m = Micronutrients.fromJson({
        'iron_mg': 3.2,
        'B12': '1.1',
        'calcium': -5,
        'zinc_mg': 'lots',
        'sodium_mg': 99999,
        'unknown': 4,
      })!;
      expect(m[Micro.iron], 3.2);
      expect(m[Micro.vitaminB12], 1.1);
      expect(m.has(Micro.calcium), isFalse);
      expect(m.has(Micro.zinc), isFalse);
      expect(m.has(Micro.sodium), isFalse, reason: 'over the per-food cap');
      expect(Micronutrients.fromJson({'nope': 1}), isNull);
      expect(Micronutrients.fromJson(null), isNull);
    });
  });

  group('food library', () {
    final lib = MicronutrientLibrary.instance;

    test('longest name wins; compound names split', () {
      expect(lib.matches('palak paneer').map((f) => f.name), ['palak paneer']);
      expect(lib.matches('dal makhani').map((f) => f.name), ['dal makhani']);
      expect(lib.matches('2 rotis').map((f) => f.name), ['roti']);
      expect(lib.matches('egg whites').map((f) => f.name), ['egg white']);
      expect(lib.matches('paneer roti roll').map((f) => f.name), ['paneer', 'roti']);
      expect(lib.matches('protein bar'), isEmpty);
    });

    test('scales by calories and leaves unknown foods untracked', () {
      expect(lib.estimate('roti', 100)![Micro.iron], closeTo(1.2, 0.001));
      expect(lib.estimate('roti', 300)![Micro.iron], closeTo(3.6, 0.001));
      expect(lib.estimate('protein bar', 220), isNull);
      expect(lib.estimate('roti', 0), isNull);
    });

    test('library beats a model guess, a pack label beats the library', () {
      final guess = Micronutrients({Micro.iron: 9, Micro.vitaminD: 3});
      final viaModel = lib.enrich('milk', 150, guess)!;
      expect(viaModel[Micro.iron], closeTo(0.1, 0.001));
      expect(viaModel[Micro.calcium], 300);
      final label = Micronutrients({Micro.calcium: 360, Micro.vitaminD: 1.5});
      final viaLabel = lib.enrich('milk', 150, label, preferExisting: true)!;
      expect(viaLabel[Micro.calcium], 360);
      expect(viaLabel[Micro.vitaminD], 1.5);
      expect(viaLabel[Micro.potassium], 375, reason: 'gaps filled from the library');
      expect(lib.enrich('protein bar', 220, null), isNull);
    });

    test('every catalog food used by the oracle gets values from the library', () {
      final missing = [
        for (final c in kynoFoodCatalog)
          if (c.isFasting && lib.estimate(c.name, c.kcal) == null) c.name,
      ];
      expect(missing, isEmpty);
    });
  });

  group('aggregation and coverage', () {
    final today = DateTime(2026, 10, 17);
    DateTime at(int daysAgo, [int h = 13]) => today.subtract(Duration(days: daysAgo)).add(Duration(hours: h));

    test('a meal is tracked when known items cover 80% of its calories', () {
      final full = entry([logged('roti', 200), logged('dal', 120)], at(0));
      final half = entry([logged('roti', 200), item('protein bar', 200)], at(0));
      final old = entry([item('roti', 200)], at(0));
      expect(MicronutrientService.ofEntry(full, Micro.iron).isTracked, isTrue);
      expect(MicronutrientService.ofEntry(half, Micro.iron).isTracked, isFalse);
      expect(MicronutrientService.ofEntry(half, Micro.iron).amount, closeTo(2.4, 0.01));
      final o = MicronutrientService.ofEntry(old, Micro.iron);
      expect(o.isTracked, isFalse);
      expect(o.amount, 0);
    });

    test('day totals count tracked meals honestly', () {
      final log = DayLog()
        ..add(MealSection.breakfast, entry([logged('milk', 150)], at(0, 8), s: MealSection.breakfast))
        ..add(MealSection.lunch, entry([logged('roti', 200), logged('dal', 120)], at(0, 13)))
        ..add(MealSection.dinner, entry([item('pizza slice from a cafe', 600)], at(0, 20), s: MealSection.dinner));
      final d = MicronutrientService.ofDay(log, Micro.calcium);
      expect(d.meals, 3);
      expect(d.trackedMeals, 2);
      expect(d.isTracked, isFalse, reason: 'over half the calories are unknown');
      expect(d.amount, closeTo(300 + 20 + 22, 0.5));
    });

    test('7-day average skips untracked days and today', () {
      final store = <String, DayLog>{};
      for (var i = 1; i <= 7; i++) {
        final log = DayLog();
        if (i <= 3) {
          log.add(MealSection.lunch, entry([logged('roti', 300)], at(i)));
        } else {
          log.add(MealSection.lunch, entry([item('roti', 300)], at(i)));
        }
        store[dateKey(today.subtract(Duration(days: i)))] = log;
      }
      store[dateKey(today)] = DayLog()..add(MealSection.lunch, entry([logged('roti', 1000)], at(0)));
      final (avg, n) = MicronutrientService.average(store, Micro.iron, today);
      expect(n, 3);
      expect(avg, closeTo(3.6, 0.01));
    });

    test('summary names the lowest nutrient and the oracle stays vegetarian', () {
      final store = <String, DayLog>{};
      for (var i = 1; i <= 5; i++) {
        store[dateKey(today.subtract(Duration(days: i)))] = DayLog()
          ..add(MealSection.lunch, entry([logged('roti', 300), logged('palak', 90), logged('curd', 90)], at(i)));
      }
      final s = MicronutrientService.instance.summarize(
        store: store,
        today: today,
        profile: const UserProfile(
          name: 'V', age: 28, gender: 'Female', height: 160, weight: 55,
          workoutDaysMin: 3, workoutDaysMax: 4, goal: kLeanBulk,
        ),
      );
      expect(s.diets, {FoodDiet.veg});
      final low = s.lowest!;
      expect(low.micro, anyOf(Micro.vitaminB12, Micro.vitaminD));
      expect(low.avgDays, 5);
      expect(low.isLow, isTrue);

      final picks = MicronutrientService.instance.richFoods(
        Micro.iron, store: store, today: today, diets: s.diets, target: 29);
      expect(picks.first.fromHistory, isTrue);
      expect(picks.where((p) => p.fromHistory).map((p) => p.name), containsAll(['roti', 'palak']));
      expect(picks.map((p) => p.name), isNot(contains('curd')), reason: 'too little iron to suggest');
      final names = picks.map((p) => p.name.toLowerCase()).join(' ');
      expect(names, isNot(contains('chicken')));
      expect(names, isNot(contains('egg')));
      expect(picks.where((p) => !p.fromHistory), isNotEmpty);
    });

    test('fasting-only oracle suggests vrat foods', () {
      final picks = MicronutrientService.instance.richFoods(
        Micro.potassium,
        store: const {},
        today: today,
        diets: const {FoodDiet.veg},
        target: 3500,
        fastingOnly: true,
      );
      expect(picks, isNotEmpty);
      for (final p in picks) {
        expect(kynoFoodCatalog.firstWhere((c) => c.name == p.name).isFasting, isTrue, reason: p.name);
      }
    });

    test('tips are veg-aware for B12', () {
      expect(MicronutrientService.tipFor(Micro.vitaminB12, const {FoodDiet.veg}), contains('animal foods'));
      expect(MicronutrientService.tipFor(Micro.vitaminB12, const {FoodDiet.veg, FoodDiet.egg, FoodDiet.nonVeg}), contains('Eggs'));
    });
  });

  group('barcode micros (Open Food Facts)', () {
    test('converts grams per 100 g to mg / µg and falls back to salt', () {
      final n = <String, double>{'calcium': 0.12, 'iron': 0.004, 'vitamin-d': 0.0000012, 'salt': 1.0};
      final m = BarcodeFoodService.microsFromNutriments((k) => n[k])!;
      expect(m[Micro.calcium], closeTo(120, 0.01));
      expect(m[Micro.iron], closeTo(4, 0.01));
      expect(m[Micro.vitaminD], closeTo(1.2, 0.01));
      expect(m[Micro.sodium], closeTo(400, 0.01));
      expect(m.has(Micro.potassium), isFalse);
      expect(BarcodeFoodService.microsFromNutriments((_) => null), isNull);
    });

    test('label micros scale to the portion and survive JSON', () {
      final per100 = BarcodeNutriments(
        calories: 60, proteinG: 3, carbsG: 5, fatG: 3, fiberG: 0, sugarG: 5,
        micros: Micronutrients({Micro.calcium: 120}),
      );
      expect(per100.scaledTo(250).micros![Micro.calcium], closeTo(300, 0.01));
      final back = BarcodeNutriments.fromJson(jsonDecode(jsonEncode(per100.toJson())) as Map<String, dynamic>);
      expect(back.micros, per100.micros);
      const plain = BarcodeNutriments(calories: 60, proteinG: 3, carbsG: 5, fatG: 3, fiberG: 0, sugarG: 5);
      expect(plain.toJson().containsKey('micros'), isFalse);
    });
  });

  group('fuel planner on a vrat', () {
    test('fastingOnly keeps to tagged catalog foods and vrat-friendly history', () {
      final plan = KynoFuelPlanner.plan(
        gap: const FuelGap(kcal: 700, protein: 5),
        history: const [
          FuelFood(name: '2 roti + dal', serving: 'as you log it', kcal: 320, protein: 12, timesLogged: 9, fromHistory: true),
          FuelFood(name: 'sabudana khichdi', serving: 'as you log it', kcal: 350, protein: 4, timesLogged: 2, fromHistory: true),
        ],
        fastingOnly: true,
      );
      final names = [...plan.yours, ...plan.newIdeas].map((p) => p.food.name);
      expect(names, isNot(contains('2 roti + dal')));
      for (final p in plan.newIdeas) {
        expect(kynoFoodCatalog.firstWhere((c) => c.name == p.food.name).isFasting, isTrue);
      }
      expect(plan.newIdeas, isNotEmpty);
    });
  });

  group('Kyno brief', () {
    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      await Supabase.initialize(url: 'https://mock.supabase.co', anonKey: 'mockAnonKey');
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await WorkoutService.instance.clearAll();
      dayLogStore.clear();
      ProfileService.instance.currentUserProfile = const UserProfile(
        name: 'B', age: 24, gender: 'Male', height: 176, weight: 72,
        workoutDaysMin: 4, workoutDaysMax: 5, goal: kLeanBulk,
      );
    });

    test('carries 7-day micros vs targets when tracked, nothing when not', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 13);
      final y = today.subtract(const Duration(days: 1));
      dayLogStore[dateKey(y)] = DayLog()..add(MealSection.lunch, entry([item('roti', 300)], y));
      expect(KynoBriefService.instance.build(now: today).json.containsKey('micronutrients'), isFalse);

      dayLogStore[dateKey(y)] = DayLog()..add(MealSection.lunch, entry([logged('roti', 300), logged('dal', 120)], y));
      final m = KynoBriefService.instance.build(now: today).json['micronutrients'] as Map<String, dynamic>;
      final iron = (m['nutrients'] as List).cast<Map<String, dynamic>>().firstWhere((n) => n['name'] == 'Iron');
      expect(iron['target'], 19);
      expect(iron['avg_7d'], closeTo(4.8, 0.1));
      expect(iron['tracked_days_7d'], 1);
      expect(m['lowest'], isNotNull);
      expect(jsonEncode(m).length, lessThan(4000));
    });
  });
}
