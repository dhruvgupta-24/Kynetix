import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kynetix/services/meal_memory.dart';
import 'package:kynetix/services/nutrition_pipeline.dart';
import 'package:kynetix/services/personal_nutrition_memory.dart';

bool _escalationTriggered(String? source, String? fallbackReason) {
  return source == 'ai' ||
      (fallbackReason?.contains('AI escalation required') ?? false);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await MealMemory.instance.init();
    await PersonalNutritionMemory.instance.init();
  });

  test('1) 1 scoop whey stays fast and local', () async {
    final result = await NutritionPipeline.instance.estimateMeal('1 scoop whey');

    expect(result.source, isNot('ai'));
    expect(_escalationTriggered(result.source, result.fallbackReason), isFalse);
  });

  test('2) 400 ml milk stays fast and local', () async {
    final result = await NutritionPipeline.instance.estimateMeal('400 ml milk');

    expect(result.source, isNot('ai'));
    expect(_escalationTriggered(result.source, result.fallbackReason), isFalse);
  });

  test('3) 2 roti + rajma uses local strong logic', () async {
    final result = await NutritionPipeline.instance.estimateMeal('2 roti + rajma');

    expect(result.source, isNot('ai'));
    expect(_escalationTriggered(result.source, result.fallbackReason), isFalse);
    expect(result.calories.max, greaterThan(0));
  });

  test('4) half roll + half roll + coke requests deeper refinement', () async {
    const input =
        'half cottage cheese roll and half paneer makhani roll and half can of regular 330ml coke';
    final result = await NutritionPipeline.instance.estimateMeal(input);

    expect(_escalationTriggered(result.source, result.fallbackReason), isTrue);
  });

  test('5) half chicken wrap and half paneer wrap does not local-short-circuit',
      () async {
    final result = await NutritionPipeline.instance
        .estimateMeal('half chicken wrap and half paneer wrap');

    expect(_escalationTriggered(result.source, result.fallbackReason), isTrue);
  });

  test('6) burger fries coke treated as composite meal', () async {
    final result = await NutritionPipeline.instance.estimateMeal('burger fries coke');

    expect(_escalationTriggered(result.source, result.fallbackReason), isTrue);
  });
}
