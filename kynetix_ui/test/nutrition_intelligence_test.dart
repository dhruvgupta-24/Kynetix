import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kynetix/services/food_role_classifier.dart';
import 'package:kynetix/services/eating_pattern_service.dart';
import 'package:kynetix/services/user_nutrition_memory.dart';
import 'package:kynetix/services/item_parser.dart';
import 'package:kynetix/services/nutrition_pipeline.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/screens/day_detail_screen.dart';

import 'package:kynetix/services/nutrition_hydration_guard.dart';

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
    SharedPreferences.setMockInitialValues({});
    NutritionHydrationGuard.instance.currentUserIdOverride = 'test-user-id';
    NutritionHydrationGuard.instance.markComplete('test-user-id');
    await UserNutritionMemory.instance.init();
    await EatingPatternService.instance.load();
    EatingPatternService.instance.resetAll();
  });

  group('FoodRoleClassifier tests', () {
    test('Classify basic foods correctly', () {
      expect(FoodRoleClassifier.classify('roti'), FoodRole.primary);
      expect(FoodRoleClassifier.classify('rice'), FoodRole.primary);
      expect(FoodRoleClassifier.classify('chicken'), FoodRole.protein);
      expect(FoodRoleClassifier.classify('paneer'), FoodRole.protein);
      expect(FoodRoleClassifier.classify('dal'), FoodRole.accompaniment);
      expect(FoodRoleClassifier.classify('butter'), FoodRole.addOn);
      expect(FoodRoleClassifier.classify('pizza'), FoodRole.completeMeal);
    });

    test('Classify unknown foods defaults to completeMeal', () {
      expect(FoodRoleClassifier.classify('some random unknown food'), FoodRole.completeMeal);
    });
  });

  group('EatingPatternService tests', () {
    test('Does not return scalar if sample count < 3', () {
      // Let's add 2 records
      EatingPatternService.instance.recordIngredientCorrection(
        correctedItemRole: FoodRole.accompaniment,
        mealHasPrimary: true,
        pipelineCalEstimate: 200.0,
        userCorrectedCal: 100.0, // ratio = 0.5
      );
      EatingPatternService.instance.recordIngredientCorrection(
        correctedItemRole: FoodRole.accompaniment,
        mealHasPrimary: true,
        pipelineCalEstimate: 200.0,
        userCorrectedCal: 100.0, // ratio = 0.5
      );

      final scalar = EatingPatternService.instance.getScalar(
        FoodRole.accompaniment,
        contextRole: FoodRole.primary,
      );
      expect(scalar, isNull);
      expect(EatingPatternService.instance.getSampleCount(FoodRole.accompaniment, contextRole: FoodRole.primary), 2);
    });

    test('Returns recency-weighted scalar if sample count >= 3', () {
      // Let's add 3 records
      EatingPatternService.instance.recordIngredientCorrection(
        correctedItemRole: FoodRole.accompaniment,
        mealHasPrimary: true,
        pipelineCalEstimate: 200.0,
        userCorrectedCal: 100.0, // ratio = 0.5
      );
      EatingPatternService.instance.recordIngredientCorrection(
        correctedItemRole: FoodRole.accompaniment,
        mealHasPrimary: true,
        pipelineCalEstimate: 200.0,
        userCorrectedCal: 100.0, // ratio = 0.5
      );
      EatingPatternService.instance.recordIngredientCorrection(
        correctedItemRole: FoodRole.accompaniment,
        mealHasPrimary: true,
        pipelineCalEstimate: 200.0,
        userCorrectedCal: 100.0, // ratio = 0.5
      );

      final scalar = EatingPatternService.instance.getScalar(
        FoodRole.accompaniment,
        contextRole: FoodRole.primary,
      );
      expect(scalar, isNotNull);
      expect(scalar, closeTo(0.5, 0.01));
      
      final confidence = EatingPatternService.instance.getConfidence(
        FoodRole.accompaniment,
        contextRole: FoodRole.primary,
      );
      expect(confidence, greaterThan(0));
    });

    test('No scalar applied if target role is completeMeal', () {
      EatingPatternService.instance.recordIngredientCorrection(
        correctedItemRole: FoodRole.completeMeal,
        mealHasPrimary: true,
        pipelineCalEstimate: 200.0,
        userCorrectedCal: 100.0,
      );
      EatingPatternService.instance.recordIngredientCorrection(
        correctedItemRole: FoodRole.completeMeal,
        mealHasPrimary: true,
        pipelineCalEstimate: 200.0,
        userCorrectedCal: 100.0,
      );
      EatingPatternService.instance.recordIngredientCorrection(
        correctedItemRole: FoodRole.completeMeal,
        mealHasPrimary: true,
        pipelineCalEstimate: 200.0,
        userCorrectedCal: 100.0,
      );

      final scalar = EatingPatternService.instance.getScalar(
        FoodRole.completeMeal,
        contextRole: FoodRole.primary,
      );
      expect(scalar, isNull);
    });

    test('Wipe and reset works', () {
      EatingPatternService.instance.recordIngredientCorrection(
        correctedItemRole: FoodRole.accompaniment,
        mealHasPrimary: true,
        pipelineCalEstimate: 200.0,
        userCorrectedCal: 100.0,
      );
      EatingPatternService.instance.resetAll();
      expect(EatingPatternService.instance.getSampleCount(FoodRole.accompaniment, contextRole: FoodRole.primary), 0);
    });
  });

  group('UserNutritionMemory tests', () {
    test('Save and lookup overrides with source', () async {
      await UserNutritionMemory.instance.saveOverride(
        'Special Bread',
        2.5, // 2.5 kcal per gram
        0.1, // 0.1g protein per gram
        carbohydratesPerUnit: 0.5,
        fatPerUnit: 0.02,
        fiberPerUnit: 0.03,
        referenceQuantity: 10.0,
        referenceUnit: 'g',
      );

      final (result, source) = UserNutritionMemory.instance.lookupWithSource('Special Bread');
      expect(result, isNotNull);
      expect(source, OverrideSource.userCorrected);

    });
  });

  group('ItemParser tests', () {
    test('Splits composite meals correctly into atomic ingredients', () {
      final breadPeanut = ItemParser.parse("4 bread slices with 40g peanut butter");
      expect(breadPeanut.length, 2);
      expect(breadPeanut[0].normalizedName, "bread");
      expect(breadPeanut[0].quantity, 4.0);
      expect(breadPeanut[0].unit, "slices");
      expect(breadPeanut[1].normalizedName, "peanut butter");
      expect(breadPeanut[1].quantity, 40.0);
      expect(breadPeanut[1].unit, "g");

      final rotiChanna = ItemParser.parse("2 roti + channa");
      expect(rotiChanna.length, 2);
      expect(rotiChanna[0].normalizedName, "roti");
      expect(rotiChanna[1].normalizedName, "channa");

      final riceDal = ItemParser.parse("rice + dal");
      expect(riceDal.length, 2);
      expect(riceDal[0].normalizedName, "rice");
      expect(riceDal[1].normalizedName, "dal");

      final rajmaChawal = ItemParser.parse("rajma chawal");
      expect(rajmaChawal.length, 2);
      expect(rajmaChawal[0].normalizedName, "rajma");
      expect(rajmaChawal[1].normalizedName, "chawal");

      final oatsMilk = ItemParser.parse("oats + milk");
      expect(oatsMilk.length, 2);
      expect(oatsMilk[0].normalizedName, "oats");
      expect(oatsMilk[1].normalizedName, "milk");

      final chickenRice = ItemParser.parse("chicken + rice");
      expect(chickenRice.length, 2);
      expect(chickenRice[0].normalizedName, "chicken");
      expect(chickenRice[1].normalizedName, "rice");

      final paneerRoti = ItemParser.parse("paneer + roti");
      expect(paneerRoti.length, 2);
      expect(paneerRoti[0].normalizedName, "paneer");
      expect(paneerRoti[1].normalizedName, "roti");

      final pastaSauce = ItemParser.parse("pasta + sauce");
      expect(pastaSauce.length, 2);
      expect(pastaSauce[0].normalizedName, "pasta");
      expect(pastaSauce[1].normalizedName, "sauce");

      final sandwichMayo = ItemParser.parse("sandwich + mayo");
      expect(sandwichMayo.length, 2);
      expect(sandwichMayo[0].normalizedName, "sandwich");
      expect(sandwichMayo[1].normalizedName, "mayo");
    });
  });

  group('Nutrition Intelligence Audit Fix tests', () {
    test('Fractional quantity scaling behaves correctly', () async {
      // Clear overrides
      await UserNutritionMemory.instance.clearAll();
      await UserNutritionMemory.instance.init();
      
      // Save an override for "whey protein" with a fractional quantity (0.5)
      // Total calories is 60 kcal. So per-unit calories should be 60 / 0.5 = 120.
      await UserNutritionMemory.instance.saveOverride(
        'whey protein',
        60.0 / 0.5,
        12.0 / 0.5,
        referenceQuantity: 0.5,
        referenceUnit: 'scoop',
      );

      final lookupRes = UserNutritionMemory.instance.lookup('whey protein');
      expect(lookupRes, isNotNull);
      // Stored per-unit values should be 120 kcal
      expect(lookupRes!.calories.min, 120.0);
      expect(lookupRes.protein.min, 24.0);

      // Now query the pipeline with "1 scoop whey protein"
      final pipelineRes = NutritionPipeline.instance.fastMemoryLookupSync('1 scoop whey protein');
      expect(pipelineRes, isNotNull);
      // Scaled by 1 scoop should be 120 kcal
      expect(pipelineRes!.calories.min, 120.0);
      expect(pipelineRes.protein.min, 24.0);

      // Now query the pipeline with "0.5 scoop whey protein"
      final pipelineResHalf = NutritionPipeline.instance.fastMemoryLookupSync('0.5 scoop whey protein');
      expect(pipelineResHalf, isNotNull);
      // Scaled by 0.5 scoop should be 60 kcal
      expect(pipelineResHalf!.calories.min, 60.0);
      expect(pipelineResHalf.protein.min, 12.0);
    });

    test('Conflict resolution (newer wins) works correctly', () async {
      await UserNutritionMemory.instance.clearAll();
      await UserNutritionMemory.instance.init();

      final now = DateTime.now();

      // Create a local override that was updated 5 minutes ago
      final localOverride = UserMealOverride(
        canonicalMeal: 'whey protein',
        caloriesPerUnit: 120.0,
        proteinPerUnit: 24.0,
        referenceQuantity: 1.0,
        referenceUnit: 'scoop',
        savedAt: now.subtract(const Duration(minutes: 5)),
      );

      // Save it directly (inject to local memory list to bypass sync calls in saveOverride)
      await UserNutritionMemory.instance.mergeFromCloud([localOverride]);

      // 1. Remote override is older (updated 10 minutes ago)
      final remoteOlder = UserMealOverride(
        canonicalMeal: 'whey protein',
        caloriesPerUnit: 150.0,
        proteinPerUnit: 30.0,
        referenceQuantity: 1.0,
        referenceUnit: 'scoop',
        savedAt: now.subtract(const Duration(minutes: 10)),
      );

      // Merge remote older - local should win!
      await UserNutritionMemory.instance.mergeFromCloud([remoteOlder]);
      var lookup = UserNutritionMemory.instance.lookup('whey protein');
      expect(lookup!.calories.min, 120.0); // Local won!

      // 2. Remote override is newer (updated 1 minute ago)
      final remoteNewer = UserMealOverride(
        canonicalMeal: 'whey protein',
        caloriesPerUnit: 150.0,
        proteinPerUnit: 30.0,
        referenceQuantity: 1.0,
        referenceUnit: 'scoop',
        savedAt: now.subtract(const Duration(minutes: 1)),
      );

      // Merge remote newer - cloud should win!
      await UserNutritionMemory.instance.mergeFromCloud([remoteNewer]);
      lookup = UserNutritionMemory.instance.lookup('whey protein');
      expect(lookup!.calories.min, 150.0); // Cloud won!
    });

    test('Unit category mismatch blocks override and skips to estimation', () async {
      await UserNutritionMemory.instance.clearAll();
      await UserNutritionMemory.instance.init();

      // Stored unit: 'serving' (non-metric)
      await UserNutritionMemory.instance.saveOverride(
        'my custom peanut butter',
        200.0,
        8.0,
        referenceQuantity: 1.0,
        referenceUnit: 'serving',
      );

      // Query with metric weight: "40g my custom peanut butter"
      // Since 'serving' and 'g' are incompatible categories, fast memory lookup should skip it
      final res = NutritionPipeline.instance.fastMemoryLookupSync('40g my custom peanut butter');
      expect(res, isNull); // Skipped/returned null because of unit category mismatch!
    });
  });

  group('Meal Quality Score Calibration', () {
    test('Verify plain burger + fries + cola', () {
      final score = NutritionResult.calculateLocalQualityScore(
        700.0,
        15.0,
        'Plain burger + fries + cola',
        carbs: 90.0,
        fat: 35.0,
        fiber: 1.0,
      );
      expect(score, 20);
    });

    test('Verify pizza meal', () {
      final score = NutritionResult.calculateLocalQualityScore(
        800.0,
        20.0,
        'Pizza meal',
        carbs: 100.0,
        fat: 40.0,
        fiber: 2.0,
      );
      expect(score, 25);
    });

    test('Verify Indian home meal (roti + dal + sabzi)', () {
      final score = NutritionResult.calculateLocalQualityScore(
        400.0,
        13.0,
        'Roti + dal + sabzi',
        carbs: 65.0,
        fat: 10.0,
        fiber: 6.0,
      );
      expect(score, 75);
    });

    test('Verify paneer + roti meal', () {
      final score = NutritionResult.calculateLocalQualityScore(
        450.0,
        16.0,
        'Paneer + roti meal',
        carbs: 55.0,
        fat: 18.0,
        fiber: 4.0,
      );
      expect(score, 65);
    });

    test('Verify chicken breast + rice + vegetables', () {
      final score = NutritionResult.calculateLocalQualityScore(
        500.0,
        40.0,
        'Chicken breast + rice + vegetables',
        carbs: 50.0,
        fat: 8.0,
        fiber: 4.0,
      );
      expect(score, 95);
    });

    test('Verify salad with lean protein', () {
      final score = NutritionResult.calculateLocalQualityScore(
        350.0,
        30.0,
        'Salad with lean protein',
        carbs: 15.0,
        fat: 12.0,
        fiber: 6.0,
      );
      expect(score, 100);
    });

    test('Verify protein shake only', () {
      final score = NutritionResult.calculateLocalQualityScore(
        130.0,
        25.0,
        'Protein shake only',
        carbs: 3.0,
        fat: 1.5,
        fiber: 0.0,
      );
      expect(score, 80);
    });
  });

  group('Midnight Meal Assignment Edge Cases', () {
    test('12:30 AM logging for yesterday -> Late Night', () {
      final now = DateTime(2026, 6, 5, 0, 30); // 12:30 AM
      final targetDate = DateTime(2026, 6, 4); // Yesterday
      final section = DayDetailScreen.getSectionForTimeAndDate(now, targetDate);
      expect(section, MealSection.lateNight);
    });

    test('2:00 AM logging for yesterday -> Late Night', () {
      final now = DateTime(2026, 6, 5, 2, 0); // 2:00 AM
      final targetDate = DateTime(2026, 6, 4); // Yesterday
      final section = DayDetailScreen.getSectionForTimeAndDate(now, targetDate);
      expect(section, MealSection.lateNight);
    });

    test('4:59 AM logging for yesterday -> Late Night', () {
      final now = DateTime(2026, 6, 5, 4, 59); // 4:59 AM
      final targetDate = DateTime(2026, 6, 4); // Yesterday
      final section = DayDetailScreen.getSectionForTimeAndDate(now, targetDate);
      expect(section, MealSection.lateNight);
    });

    test('5:00 AM logging for yesterday -> Breakfast', () {
      final now = DateTime(2026, 6, 5, 5, 0); // 5:00 AM
      final targetDate = DateTime(2026, 6, 4); // Yesterday
      final section = DayDetailScreen.getSectionForTimeAndDate(now, targetDate);
      expect(section, MealSection.breakfast);
    });

    test('Logging a meal 3 days in the past at 1 AM -> Late Night', () {
      final now = DateTime(2026, 6, 5, 1, 0); // 1:00 AM
      final targetDate = DateTime(2026, 6, 2); // 3 Days Ago
      final section = DayDetailScreen.getSectionForTimeAndDate(now, targetDate);
      expect(section, MealSection.lateNight);
    });

    test('Logging a meal for current day after midnight -> Breakfast', () {
      final now = DateTime(2026, 6, 5, 1, 0); // 1:00 AM
      final targetDate = DateTime(2026, 6, 5); // Current Day
      final section = DayDetailScreen.getSectionForTimeAndDate(now, targetDate);
      expect(section, MealSection.breakfast);
    });
  });
}

