import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/services/user_nutrition_memory.dart';
import 'package:kynetix/services/quick_add_service.dart';
import 'package:kynetix/services/meal_memory.dart';
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

  test('Quick Add preserves exact stored NutritionResult without field-mixing or score recalculation', () async {
    const mealName = '4 egg whites + 400ml milk';

    // 1. Save user's stored custom values (352 kcal, 26g pro, 20g carbs, 18g fat, quality 70)
    await UserNutritionMemory.instance.saveOverride(
      mealName,
      352.0,
      26.0,
      carbohydratesPerUnit: 20.0,
      fatPerUnit: 18.0,
      fiberPerUnit: 2.0,
    );

    final storedMemoryResult = NutritionResult.createCustom(
      canonicalMeal: mealName,
      calories: 352.0,
      protein: 26.0,
      carbohydrates: 20.0,
      fat: 18.0,
      fiber: 2.0,
      source: 'user_corrected',
      userCorrected: true,
    );
    await MealMemory.instance.store(mealName, storedMemoryResult);

    // 2. Perform Quick Add with QuickAddItem carrying different preset values (328 kcal, 27g pro)
    final date = DateTime.now();
    final entry = await QuickAddService.instance.addMealToDay(
      date: date,
      name: mealName,
      calories: 328.0, // QuickAddItem carried 328
      protein: 27.0,  // QuickAddItem carried 27
      section: MealSection.breakfast,
    );

    // 3. Verify atomic NutritionResult: MUST use stored memory (352 kcal, 26g pro, 20g carbs, 18g fat, quality 70)
    expect(entry.result.calories.mid, equals(352.0), reason: 'Calories must come from stored memory');
    expect(entry.result.protein.mid, equals(26.0), reason: 'Protein must come from stored memory');
    expect(entry.result.carbohydrates?.mid, equals(20.0), reason: 'Carbs must come from stored memory');
    expect(entry.result.fat?.mid, equals(18.0), reason: 'Fat must come from stored memory');
    expect(entry.result.mealQualityScore, equals(70), reason: 'Meal quality must come from stored memory (not re-calculated to 80!)');

    // 4. Reload from disk and verify 100% zero mutations
    final dayLog = logFor(date);
    final reloaded = dayLog.entriesFor(MealSection.breakfast).firstWhere((e) => e.rawInput == mealName);
    expect(reloaded.result.calories.mid, equals(352.0));
    expect(reloaded.result.protein.mid, equals(26.0));
    expect(reloaded.result.carbohydrates?.mid, equals(20.0));
    expect(reloaded.result.fat?.mid, equals(18.0));
    expect(reloaded.result.mealQualityScore, equals(70));
  });
}
