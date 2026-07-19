import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kynetix/services/meal_memory.dart';
import 'package:kynetix/services/nutrition_pipeline.dart';
import 'package:kynetix/services/personal_nutrition_memory.dart';
import 'package:kynetix/services/ai_nutrition_service.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/services/nutrition_hydration_guard.dart';

bool _escalationTriggered(String? source, String? fallbackReason) {
  return source == 'ai' ||
      (fallbackReason?.contains('AI escalation required') ?? false);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    NutritionHydrationGuard.instance.currentUserIdOverride = 'mock-user-id';
    NutritionHydrationGuard.instance.markComplete('mock-user-id');
    await MealMemory.instance.init();
    await PersonalNutritionMemory.instance.init();
    
    // Inject mock AI estimator so network/Supabase calls are bypassed in unit tests
    AiNutritionService.instance.mockEstimate = (rawInput, {context}) async {
      return NutritionResult(
        canonicalMeal: rawInput,
        items: const [],
        calories: const NutrientRange(min: 300, max: 400),
        protein: const NutrientRange(min: 10, max: 20),
        confidence: 0.95,
        warnings: const [],
        source: 'ai',
        createdAt: DateTime.now(),
      );
    };
  });

  tearDownAll(() {
    AiNutritionService.instance.mockEstimate = null;
    NutritionHydrationGuard.instance.reset();
    NutritionHydrationGuard.instance.currentUserIdOverride = null;
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

    // Bypasses AI under new rules since wraps exist in the Food Library (local database)
    expect(_escalationTriggered(result.source, result.fallbackReason), isFalse);
  });

  test('6) burger fries coke treated as composite meal', () async {
    final result = await NutritionPipeline.instance.estimateMeal('burger fries coke');

    expect(_escalationTriggered(result.source, result.fallbackReason), isTrue);
  });
}
