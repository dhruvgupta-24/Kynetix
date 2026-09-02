import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/services/user_nutrition_memory.dart';
import 'package:kynetix/services/quick_add_service.dart';
import 'package:kynetix/services/persistence_service.dart';
import 'package:kynetix/services/nutrition_hydration_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://xyz.supabase.co',
      anonKey: 'anon-key-1234',
    );
  });

  setUp(() async {
    await PersistenceService.load();
    NutritionHydrationGuard.instance.markComplete('guest');
    await UserNutritionMemory.instance.init();
  });

  test('Ingredient list totals and MealEntry.result summary are 100% synchronized in Quick Add and Edit Screen', () async {
    const mealName = '4 egg whites + 400ml milk';

    // 1. Seed user nutrition memory for ingredients
    await UserNutritionMemory.instance.saveOverride('egg whites', 17.0, 3.6, carbohydratesPerUnit: 0.2, fatPerUnit: 0.1, fiberPerUnit: 0.0);
    await UserNutritionMemory.instance.saveOverride('milk', 0.71, 0.029, carbohydratesPerUnit: 0.048, fatPerUnit: 0.0465, fiberPerUnit: 0.005);

    // 2. Perform Quick Add with preset item carrying 328 kcal / 27g pro
    final date = DateTime.now();
    final entry = await QuickAddService.instance.addMealToDay(
      date: date,
      name: mealName,
      calories: 328.0,
      protein: 27.0,
      section: MealSection.breakfast,
    );

    // 3. Inspect MealEntry.result top-level summary vs ingredient list
    final result = entry.result;
    final items = result.items;

    double sumCal = 0, sumPro = 0, sumCarb = 0, sumFat = 0, sumFib = 0;
    for (final item in items) {
      sumCal += item.calories.mid;
      sumPro += item.protein.mid;
      sumCarb += item.carbohydrates?.mid ?? 0.0;
      sumFat += item.fat?.mid ?? 0.0;
      sumFib += item.fiber?.mid ?? 0.0;
    }

    // 4. Simulate Edit Screen initial calculation (reading rows & summing ingredient totals)
    final editScreenRunningCal = sumCal;
    final editScreenRunningPro = sumPro;
    final editScreenRunningCarb = sumCarb;
    final editScreenRunningFat = sumFat;
    final editScreenRunningFib = sumFib;

    final summaryBeforeCalculate = result;

    // 5. Simulate Calculate action (re-generating NutritionResult from rows)
    final summaryAfterCalculate = NutritionResult.createCustom(
      canonicalMeal: mealName,
      calories: editScreenRunningCal,
      protein: editScreenRunningPro,
      carbohydrates: editScreenRunningCarb,
      fat: editScreenRunningFat,
      fiber: editScreenRunningFib,
      source: 'user_override',
      items: items,
    );

    // 6. Print mandatory runtime trace
    print('''

=================== INGREDIENT & MEAL SUMMARY TRACE ===================
  - Meal Input                   : "$mealName"
  - MealEntry.result Top-Level   : Calories=${result.calories.mid}, Pro=${result.protein.mid}, Carbs=${result.carbohydrates?.mid}, Fat=${result.fat?.mid}, Fib=${result.fiber?.mid}, Score=${result.mealQualityScore}
  - Ingredient List              :
${items.map((i) => '      * ${i.name} (qty: ${i.quantity} ${i.unit}) -> Cal=${i.calories.mid}, Pro=${i.protein.mid}, Carb=${i.carbohydrates?.mid}, Fat=${i.fat?.mid}, Fib=${i.fiber?.mid}').join('\n')}
  - Ingredient Totals (Sum)      : Calories=$sumCal, Pro=$sumPro, Carbs=$sumCarb, Fat=$sumFat, Fib=$sumFib
  - Edit Screen Running Total    : Calories=$editScreenRunningCal, Pro=$editScreenRunningPro, Carbs=$editScreenRunningCarb, Fat=$editScreenRunningFat, Fib=$editScreenRunningFib
  - Meal Summary Before Calculate: Calories=${summaryBeforeCalculate.calories.mid}, Pro=${summaryBeforeCalculate.protein.mid}, Carbs=${summaryBeforeCalculate.carbohydrates?.mid}, Fat=${summaryBeforeCalculate.fat?.mid}, Fib=${summaryBeforeCalculate.fiber?.mid}
  - Meal Summary After Calculate : Calories=${summaryAfterCalculate.calories.mid}, Pro=${summaryAfterCalculate.protein.mid}, Carbs=${summaryAfterCalculate.carbohydrates?.mid}, Fat=${summaryAfterCalculate.fat?.mid}, Fib=${summaryAfterCalculate.fiber?.mid}
  - Divergence (Summary - Sum)   : ${(result.calories.mid - sumCal).abs().toStringAsFixed(2)} kcal
=======================================================================
''');

    // Assert 100% synchronization: zero divergence!
    expect((result.calories.mid - sumCal).abs(), equals(0.0), reason: 'Top-level calories must match sum of ingredients');
    expect((result.protein.mid - sumPro).abs(), equals(0.0), reason: 'Top-level protein must match sum of ingredients');
    expect(result.calories.mid, equals(summaryAfterCalculate.calories.mid));
    expect(result.protein.mid, equals(summaryAfterCalculate.protein.mid));
  });
}
