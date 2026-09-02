import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/services/user_nutrition_memory.dart';
import 'package:kynetix/services/meal_memory.dart';
import 'package:kynetix/services/quick_add_service.dart';
import 'package:kynetix/services/persistence_service.dart';
import 'package:kynetix/services/nutrition_hydration_guard.dart';
import 'package:kynetix/services/nutrition_pipeline.dart';

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

  test('Real Runtime Quick Add & Edit Screen Flow (Zero Divergence)', () async {
    const mealName = '4 egg whites + 400ml milk';

    // 1. Seed saved ingredients in UserNutritionMemory/FoodLibrary
    await UserNutritionMemory.instance.saveOverride(
      'egg whites',
      17.0,
      3.6,
      carbohydratesPerUnit: 0.2,
      fatPerUnit: 0.1,
      fiberPerUnit: 0.0,
    );
    await UserNutritionMemory.instance.saveOverride(
      'milk',
      0.71,
      0.029,
      carbohydratesPerUnit: 0.048,
      fatPerUnit: 0.0465,
      fiberPerUnit: 0.005,
    );

    final date = DateTime.now();

    // Step 1: Pre-lookup state check
    final userMemBefore = UserNutritionMemory.instance.lookup(mealName);
    final mealMemBefore = MealMemory.instance.lookupExactKnownFood(mealName) ?? MealMemory.instance.lookupRecurring(mealName);

    // Step 2: Tap Quick Add
    final entry = await QuickAddService.instance.addMealToDay(
      date: date,
      name: mealName,
      calories: 328.0,
      protein: 27.0,
      section: MealSection.breakfast,
    );

    final selectedResult = entry.result;
    final mealEntryBeforeSave = entry;

    // Step 3: Persisted check
    final reloadedLog = logFor(date);
    final reloadedEntry = reloadedLog.entriesFor(MealSection.breakfast).firstWhere((e) => e.rawInput == mealName);

    // Step 4: Detail Sheet values (reads reloadedEntry.result)
    final detailSheetCals = reloadedEntry.result.calories.mid;
    final detailSheetPro = reloadedEntry.result.protein.mid;
    final detailSheetCarb = reloadedEntry.result.carbohydrates?.mid ?? 0.0;
    final detailSheetFat = reloadedEntry.result.fat?.mid ?? 0.0;
    final detailSheetFib = reloadedEntry.result.fiber?.mid ?? 0.0;

    // Step 5: Edit Screen Running Totals (simulating row initialization & summation)
    final items = reloadedEntry.result.items;
    double editScreenCal = 0, editScreenPro = 0, editScreenCarb = 0, editScreenFat = 0, editScreenFib = 0;
    for (final it in items) {
      editScreenCal += it.calories.mid;
      editScreenPro += it.protein.mid;
      editScreenCarb += it.carbohydrates?.mid ?? 0.0;
      editScreenFat += it.fat?.mid ?? 0.0;
      editScreenFib += it.fiber?.mid ?? 0.0;
    }

    // Step 6: Press Calculate (re-estimating or rebuilding NutritionResult from rows)
    final calculatedResult = await NutritionPipeline.instance.estimateMeal(mealName);
    final entryAfterCalculate = MealEntry(
      rawInput: mealName,
      finalSavedInput: mealName,
      section: MealSection.breakfast,
      addedAt: entry.addedAt,
      dayOfWeek: date.weekday,
      parsedFoods: items.map((i) => i.name).toList(),
      userCorrected: true,
      result: calculatedResult,
    );

    // Step 7: Print required 8-point runtime trace
    print('''

=================== REAL RUNTIME FLOW TRACE ===================
  1. UserNutritionMemory lookup result : ${userMemBefore != null ? 'Calories=${userMemBefore.calories.mid}, Pro=${userMemBefore.protein.mid}' : 'NULL'}
  2. MealMemory lookup result          : ${mealMemBefore != null ? 'Calories=${mealMemBefore.calories.mid}, Pro=${mealMemBefore.protein.mid}' : 'NULL'}
  3. Selected NutritionResult          : Calories=${selectedResult.calories.mid}, Pro=${selectedResult.protein.mid}, Carbs=${selectedResult.carbohydrates?.mid}, Fat=${selectedResult.fat?.mid}, Fiber=${selectedResult.fiber?.mid}, Source=${selectedResult.source}
  4. MealEntry.result before save      : Calories=${mealEntryBeforeSave.result.calories.mid}, Pro=${mealEntryBeforeSave.result.protein.mid}, Carbs=${mealEntryBeforeSave.result.carbohydrates?.mid}, Fat=${mealEntryBeforeSave.result.fat?.mid}
  5. Persisted MealEntry.result        : Calories=${reloadedEntry.result.calories.mid}, Pro=${reloadedEntry.result.protein.mid}, Carbs=${reloadedEntry.result.carbohydrates?.mid}, Fat=${reloadedEntry.result.fat?.mid}
  6. Detail sheet values               : Calories=$detailSheetCals, Pro=$detailSheetPro, Carbs=$detailSheetCarb, Fat=$detailSheetFat, Fiber=$detailSheetFib
  7. Edit screen running totals        : Calories=$editScreenCal, Pro=$editScreenPro, Carbs=$editScreenCarb, Fat=$editScreenFat, Fiber=$editScreenFib
  8. MealEntry.result after Calculate  : Calories=${entryAfterCalculate.result.calories.mid}, Pro=${entryAfterCalculate.result.protein.mid}, Carbs=${entryAfterCalculate.result.carbohydrates?.mid}, Fat=${entryAfterCalculate.result.fat?.mid}
===============================================================
''');

    // Assert zero divergence across Detail Sheet, Edit Screen, and Post-Calculate result
    expect(detailSheetCals, equals(editScreenCal), reason: 'Detail sheet and Edit screen running totals must match');
    expect(detailSheetCals, equals(entryAfterCalculate.result.calories.mid), reason: 'Detail sheet and post-calculate result must match');
  });
}
