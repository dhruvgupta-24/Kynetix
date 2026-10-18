import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/services/mock_estimation_service.dart' show NutrientRange;
import 'package:kynetix/services/user_nutrition_memory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a food correction saved later does not change a meal already logged', () async {
    SharedPreferences.setMockInitialValues({});
    await UserNutritionMemory.instance.initForUser('u1', prefsOverride: await SharedPreferences.getInstance());
    NutrientRange n(double v) => NutrientRange(min: v, max: v);
    final entry = MealEntry(
      rawInput: '2 roti',
      finalSavedInput: '2 roti',
      section: MealSection.lunch,
      addedAt: DateTime(2026, 10, 1, 13),
      dayOfWeek: 4,
      parsedFoods: const ['roti'],
      result: NutritionResult(
        canonicalMeal: '2 roti',
        items: [
          NutritionItem(name: 'roti', quantity: 2, unit: 'piece', estimated: false,
              mode: EstimationMode.directQuantity, calories: n(240), protein: n(6)),
        ],
        calories: n(240),
        protein: n(6),
        confidence: 0.9,
        warnings: const [],
        source: 'test',
        createdAt: DateTime(2026, 10, 1),
      ),
    );
    await UserNutritionMemory.instance.saveOverride('roti', 150, 4, referenceUnit: 'piece', referenceQuantity: 1);
    expect(entry.calMid, 240);
    expect(entry.protMid, 6);
    expect(entry.toJson()['result'], isNotNull);
  });
}
