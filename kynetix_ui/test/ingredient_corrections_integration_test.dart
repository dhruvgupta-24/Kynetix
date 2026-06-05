import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/screens/add_meal_screen.dart';
import 'package:kynetix/services/user_nutrition_memory.dart';
import 'package:kynetix/services/meal_memory.dart';
import 'package:kynetix/services/ai_nutrition_service.dart';
import 'package:kynetix/services/nutrition_hydration_guard.dart';
import 'package:kynetix/services/mock_estimation_service.dart' show NutrientRange;
import 'package:kynetix/services/personal_nutrition_memory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://mock.supabase.co',
      anonKey: 'mock-anon-key',
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'cached_owner_user_id_v1': 'test-user-uuid',
    });
    NutritionHydrationGuard.instance.reset();
    NutritionHydrationGuard.instance.currentUserIdOverride = 'test-user-uuid';
    NutritionHydrationGuard.instance.markComplete('test-user-uuid');
    
    // Clear stores
    await UserNutritionMemory.instance.clearAll();
    await UserNutritionMemory.instance.init();
    await PersonalNutritionMemory.instance.clearAll();
    await PersonalNutritionMemory.instance.init();
    await MealMemory.instance.clearAll();
    await MealMemory.instance.init();
    dayLogStore.clear();

    // Mock AI estimation service
    AiNutritionService.instance.mockEstimate = (rawInput, {context}) async {
      return NutritionResult(
        canonicalMeal: rawInput,
        items: [
          NutritionItem(
            name: 'egg',
            quantity: 2,
            unit: 'serving',
            estimated: true,
            mode: EstimationMode.directQuantity,
            calories: const NutrientRange(min: 140, max: 140),
            protein: const NutrientRange(min: 12, max: 12),
          ),
          NutritionItem(
            name: 'toast',
            quantity: 1,
            unit: 'serving',
            estimated: true,
            mode: EstimationMode.directQuantity,
            calories: const NutrientRange(min: 80, max: 80),
            protein: const NutrientRange(min: 3, max: 3),
          )
        ],
        calories: const NutrientRange(min: 220, max: 220),
        protein: const NutrientRange(min: 15, max: 15),
        confidence: 0.9,
        warnings: const [],
        source: 'ai',
        createdAt: DateTime.now(),
      );
    };
  });

  tearDown(() {
    AiNutritionService.instance.mockEstimate = null;
    NutritionHydrationGuard.instance.reset();
  });

  testWidgets('1. Setting ingredient overrides in UserNutritionMemory and loading a meal log automatically rebuilds totals', (WidgetTester tester) async {
    // Save an override for egg (e.g. egg has 200 calories per unit instead of 70)
    await UserNutritionMemory.instance.saveOverride(
      'egg',
      200.0,
      15.0,
      referenceQuantity: 1.0,
      referenceUnit: 'serving',
    );

    // Create a meal result with egg (quantity: 2) and toast (quantity: 1)
    final result = NutritionResult(
      canonicalMeal: '2 eggs and toast',
      items: [
        NutritionItem(
          name: 'egg',
          quantity: 2,
          unit: 'serving',
          estimated: true,
          mode: EstimationMode.directQuantity,
          calories: const NutrientRange(min: 140, max: 140),
          protein: const NutrientRange(min: 12, max: 12),
        ),
        NutritionItem(
          name: 'toast',
          quantity: 1,
          unit: 'serving',
          estimated: true,
          mode: EstimationMode.directQuantity,
          calories: const NutrientRange(min: 80, max: 80),
          protein: const NutrientRange(min: 3, max: 3),
        )
      ],
      calories: const NutrientRange(min: 220, max: 220),
      protein: const NutrientRange(min: 15, max: 15),
      confidence: 0.9,
      warnings: const [],
      source: 'ai',
      createdAt: DateTime.now(),
    );

    // Call rebuild
    final rebuilt = result.rebuildFromIngredientsAndOverrides();

    // egg is overridden to 200 kcal * 2 = 400 kcal. toast is original 80 kcal.
    // Total should be 480 kcal.
    expect(rebuilt.calories.min, equals(480));
    expect(rebuilt.protein.min, equals(33)); // 15*2 (egg) + 3 (toast) = 33
    expect(rebuilt.source, equals('user_override'));
  });

  testWidgets('2. Modifying ingredient values live updates the totals card in AddMealScreen', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AddMealScreen(
          section: MealSection.breakfast,
          date: DateTime.now(),
          initialText: '2 eggs and toast',
        ),
      ),
    );

    // Let initState run and auto-calculate complete
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // The screen should now show ingredient containers for egg and toast.
    // Let's verify that the running totals card shows initial total calories: 230 kcal (150 egg + 80 toast).
    expect(find.textContaining('230 kcal'), findsOneWidget);

    // Find the textfield for egg calories. The text should be '150'.
    // Let's enter a new value for egg calories: '400'.
    final calFields = find.byWidgetPredicate((widget) =>
        widget is TextField &&
        widget.controller != null &&
        widget.controller!.text == '150');
    expect(calFields, findsOneWidget);

    await tester.enterText(calFields, '400');
    await tester.pump();

    // Verify running totals card updated live to 480 kcal (400 egg + 80 toast).
    expect(find.textContaining('480 kcal'), findsOneWidget);
  });
}
