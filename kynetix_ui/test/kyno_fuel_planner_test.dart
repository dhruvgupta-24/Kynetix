import 'package:flutter_test/flutter_test.dart';

import 'package:kynetix/data/kyno_food_catalog.dart';
import 'package:kynetix/services/kyno_fuel_planner.dart';

void main() {
  const paneerBhurji = FuelFood(
    name: 'paneer bhurji with 2 roti',
    serving: 'as you log it',
    kcal: 520,
    protein: 26,
    carbs: 40,
    fat: 28,
    timesLogged: 9,
    fromHistory: true,
  );
  const wheyShake = FuelFood(
    name: '1 scoop whey in water',
    serving: 'as you log it',
    kcal: 120,
    protein: 24,
    carbs: 3,
    fat: 1.5,
    timesLogged: 14,
    fromHistory: true,
  );
  const gulabJamun = FuelFood(
    name: '2 gulab jamun',
    serving: 'as you log it',
    kcal: 300,
    protein: 4,
    carbs: 45,
    fat: 12,
    timesLogged: 3,
    fromHistory: true,
  );
  const chickenTikka = FuelFood(
    name: 'chicken tikka',
    serving: 'as you log it',
    kcal: 290,
    protein: 40,
    timesLogged: 4,
    fromHistory: true,
    diet: FoodDiet.nonVeg,
  );

  final history = [paneerBhurji, wheyShake, gulabJamun, chickenTikka];

  test('a big protein gap ranks protein-dense foods first and skips sweets', () {
    final plan = KynoFuelPlanner.plan(
      gap: const FuelGap(kcal: 600, protein: 60),
      history: history,
    );
    expect(plan.yours.first.food.name, '1 scoop whey in water');
    expect(plan.yours.map((p) => p.food.name), isNot(contains('2 gulab jamun')));
    expect(plan.newIdeas, isNotEmpty);
    // Vegetarian log: no meat in the pool.
    expect(plan.yours.map((p) => p.food.name), isNot(contains('chicken tikka')));
    for (final p in plan.newIdeas) {
      expect(p.food.diet, FoodDiet.veg);
    }
  });

  test('combos close the protein gap without going far over calories', () {
    const gap = FuelGap(kcal: 650, protein: 55);
    final plan = KynoFuelPlanner.plan(gap: gap, history: history);
    expect(plan.combos, isNotEmpty);
    final best = plan.combos.first;
    expect(best.kcal, lessThanOrEqualTo(gap.kcal + 40));
    expect(best.protein, greaterThanOrEqualTo(gap.protein * 0.8));
  });

  test('calories done but protein left: only lean protein', () {
    final plan = KynoFuelPlanner.plan(
      gap: const FuelGap(kcal: 90, protein: 25),
      history: history,
    );
    for (final p in [...plan.yours, ...plan.newIdeas]) {
      expect(p.food.kcal, lessThanOrEqualTo(180));
      expect(p.food.protein, greaterThanOrEqualTo(10));
    }
    expect(plan.headline, contains('protein'));
  });

  test('on target: nothing to suggest', () {
    final plan = KynoFuelPlanner.plan(
      gap: const FuelGap(kcal: 40, protein: 3),
      history: history,
    );
    expect(plan.isEmpty, isTrue);
    expect(plan.headline, contains('on target'));
  });

  test('diet is inferred from the log', () {
    expect(KynoFuelPlanner.inferDiets(['dal rice', 'paneer roll']), {FoodDiet.veg});
    expect(KynoFuelPlanner.inferDiets(['2 boiled eggs', 'dal']), {FoodDiet.veg, FoodDiet.egg});
    expect(
      KynoFuelPlanner.inferDiets(['chicken curry']),
      {FoodDiet.veg, FoodDiet.egg, FoodDiet.nonVeg},
    );
  });

  test('a new idea never repeats a food the user already logs', () {
    const loggedGreek = FuelFood(
      name: 'Greek yogurt (plain)',
      serving: 'as you log it',
      kcal: 146,
      protein: 20,
      timesLogged: 2,
      fromHistory: true,
    );
    final plan = KynoFuelPlanner.plan(
      gap: const FuelGap(kcal: 500, protein: 50),
      history: [loggedGreek],
    );
    expect(plan.newIdeas.map((p) => p.food.name), isNot(contains('Greek yogurt (plain)')));
  });

  test('catalog values are internally consistent (kcal ≈ 4P + 4C + 9F)', () {
    for (final c in kynoFoodCatalog) {
      final atwater = c.protein * 4 + c.carbs * 4 + c.fat * 9;
      expect((atwater - c.kcal).abs() / c.kcal, lessThan(0.22), reason: c.name);
    }
  });
}
