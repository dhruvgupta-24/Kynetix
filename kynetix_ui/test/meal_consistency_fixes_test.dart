import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/services/persistence_service.dart';
import 'package:kynetix/services/insights_report_service.dart';
import 'package:kynetix/services/mock_estimation_service.dart' show NutrientRange, FoodItem, EstimationResult;
import 'package:kynetix/screens/onboarding_screen.dart' show UserProfile, currentUserProfile;
import 'package:kynetix/services/nutrition_hydration_guard.dart';
import 'package:kynetix/services/meal_memory.dart';
import 'package:kynetix/services/nutrition_target_engine.dart';

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
    NutritionHydrationGuard.instance.reset();
    NutritionHydrationGuard.instance.currentUserIdOverride = 'test-user-uuid';
    NutritionHydrationGuard.instance.markComplete('test-user-uuid');
    await MealMemory.instance.clearAll();
    await MealMemory.instance.init();
    dayLogStore.clear();
  });

  group('Meal Consistency, Quick Add, and Manual Edits Tests', () {
    test('1. NutritionResult.createCustom correctly calculates missing macros and quality scores', () {
      final result = NutritionResult.createCustom(
        canonicalMeal: 'Chicken and Rice',
        calories: 500,
        protein: 40,
        source: 'quick_add',
        userCorrected: true,
      );

      // Verify canonical name and source
      expect(result.canonicalMeal, equals('Chicken and Rice'));
      expect(result.source, equals('quick_add'));
      expect(result.userCorrected, isTrue);
      expect(result.macrosLockedByUser, isTrue);

      // Verify that missing macros are estimated locally and are not null/zero
      expect(result.carbohydrates, isNotNull);
      expect(result.fat, isNotNull);
      expect(result.fiber, isNotNull);

      expect(result.carbohydrates!.mid, greaterThan(0));
      expect(result.fat!.mid, greaterThan(0));

      // Quality score should be computed locally
      expect(result.mealQualityScore, isNotNull);
      expect(result.mealQualityScore, greaterThan(0));
      expect(result.mealQualityExplanation, isNotNull);
      expect(result.mealQualityPositive, isNotNull);
      expect(result.mealQualityImprovement, isNotNull);
    });

    test('2. MealEntry & NutritionResult serialization/deserialization persists userCorrected flag', () {
      final result = NutritionResult.createCustom(
        canonicalMeal: 'Protein Shake',
        calories: 300,
        protein: 30,
        source: 'user_override',
        userCorrected: true,
      );

      final entry = MealEntry(
        rawInput: 'Protein Shake',
        result: result,
        addedAt: DateTime(2026, 6, 5, 12, 0),
        section: MealSection.breakfast,
        dayOfWeek: 5,
        parsedFoods: const ['Protein Shake'],
        finalSavedInput: 'Protein Shake',
        userCorrected: true,
      );

      // Serialize to JSON
      final json = entry.toJson();
      expect(json['userCorrected'], isTrue);
      expect(json['result']['userCorrected'], isTrue);

      // Deserialize from JSON
      final deserialized = MealEntry.fromJson(json);
      expect(deserialized.userCorrected, isTrue);
      expect(deserialized.result.userCorrected, isTrue);
      expect(deserialized.result.macrosLockedByUser, isTrue);
      expect(deserialized.result.calories.min, equals(300));
      expect(deserialized.result.protein.min, equals(30));
    });

    test('3. Targeted insights recomputation (recomputeForDate) updates only affected boundaries', () async {
      final profile = const UserProfile(
        name: 'Dhruv',
        age: 25,
        gender: 'Male',
        height: 175.0,
        weight: 75.0,
        workoutDaysMin: 3,
        workoutDaysMax: 3,
        goal: 'Fat Loss',
      );
      currentUserProfile = profile;

      final testDate = DateTime(2026, 6, 5); // A Friday
      final testDateStr = '2026-06-05';

      // Setup 60 logged days total (20 days per month for April, May, and June) for valid yearly, monthly, and weekly reports
      void logDays(int year, int month, int count) {
        for (int i = 1; i <= count; i++) {
          final date = DateTime(year, month, i);
          final dateStr = '$year-${month.toString().padLeft(2, '0')}-${i.toString().padLeft(2, '0')}';
          final log = DayLog();
          log.add(
            MealSection.breakfast,
            MealEntry(
              rawInput: 'Healthy eggs',
              result: NutritionResult.createCustom(
                canonicalMeal: 'Eggs',
                calories: 400,
                protein: 30,
                source: 'test',
              ),
              addedAt: date,
              section: MealSection.breakfast,
              dayOfWeek: date.weekday,
              parsedFoods: const ['Eggs'],
              finalSavedInput: 'Eggs',
            ),
          );
          dayLogStore[dateStr] = log;
        }
      }

      logDays(2026, 4, 20);
      logDays(2026, 5, 20);
      logDays(2026, 6, 20);

      // Add meal to the target date
      final targetLog = DayLog();
      targetLog.add(
        MealSection.lunch,
        MealEntry(
          rawInput: 'Chicken Salad',
          result: NutritionResult.createCustom(
            canonicalMeal: 'Chicken Salad',
            calories: 600,
            protein: 50,
            source: 'quick_add',
          ),
          addedAt: testDate,
          section: MealSection.lunch,
          dayOfWeek: testDate.weekday,
          parsedFoods: const ['Chicken Salad'],
          finalSavedInput: 'Chicken Salad',
        ),
      );
      dayLogStore[testDateStr] = targetLog;

      // Run full initial computation first to populate historical insights cache
      await InsightsReportService.instance.forceRecompute(profile);

      // Verify that reports are computed for that period
      final weekKey = '2026-W23'; // Week containing June 5, 2026
      final monthKey = '2026-06';
      
      final weekReport = InsightsReportService.instance.weeklyFor(weekKey);
      final monthReport = InsightsReportService.instance.monthlyFor(monthKey);
      final yearReport = InsightsReportService.instance.yearlyFor('2026');

      expect(weekReport, isNotNull);
      expect(monthReport, isNotNull);
      expect(yearReport, isNotNull);

      // Now edit the target date's meals
      final newTargetLog = DayLog();
      newTargetLog.add(
        MealSection.lunch,
        MealEntry(
          rawInput: 'Chicken Salad',
          result: NutritionResult.createCustom(
            canonicalMeal: 'Chicken Salad',
            calories: 800, // Calories increased
            protein: 60,
            source: 'user_override',
            userCorrected: true,
          ),
          addedAt: testDate,
          section: MealSection.lunch,
          dayOfWeek: testDate.weekday,
          parsedFoods: const ['Chicken Salad'],
          finalSavedInput: 'Chicken Salad',
          userCorrected: true,
        ),
      );
      dayLogStore[testDateStr] = newTargetLog;

      // Recompute again
      await InsightsReportService.instance.recomputeForDate(testDate, profile);

      final updatedWeekReport = InsightsReportService.instance.weeklyFor(weekKey);
      expect(updatedWeekReport, isNotNull);
      // Average calories should have increased in the week report
      expect(updatedWeekReport!.avgCalories, greaterThan(weekReport!.avgCalories));
    });

    test('4. Saving meal logs via PersistenceService.saveDay updates logs and triggers targeted refresh', () async {
      final profile = const UserProfile(
        name: 'Dhruv',
        age: 25,
        gender: 'Male',
        height: 175.0,
        weight: 75.0,
        workoutDaysMin: 3,
        workoutDaysMax: 3,
        goal: 'Fat Loss',
      );
      currentUserProfile = profile;

      final testDate = DateTime(2026, 6, 5);
      final testDateStr = '2026-06-05';

      // Setup 10 logged days again
      for (int i = 1; i <= 10; i++) {
        final date = DateTime(2026, 6, i);
        final dateStr = '2026-06-${i.toString().padLeft(2, '0')}';
        final log = DayLog();
        log.add(
          MealSection.breakfast,
          MealEntry(
            rawInput: 'Healthy eggs',
            result: NutritionResult.createCustom(
              canonicalMeal: 'Eggs',
              calories: 400,
              protein: 30,
              source: 'test',
            ),
            addedAt: date,
            section: MealSection.breakfast,
            dayOfWeek: date.weekday,
            parsedFoods: const ['Eggs'],
            finalSavedInput: 'Eggs',
          ),
        );
        dayLogStore[dateStr] = log;
      }

      final log = DayLog();
      log.add(
        MealSection.breakfast,
        MealEntry(
          rawInput: 'Toast',
          result: NutritionResult.createCustom(
            canonicalMeal: 'Toast',
            calories: 150,
            protein: 4,
            source: 'quick_add',
          ),
          addedAt: testDate,
          section: MealSection.breakfast,
          dayOfWeek: testDate.weekday,
          parsedFoods: const ['Toast'],
          finalSavedInput: 'Toast',
        ),
      );
      dayLogStore[testDateStr] = log;

      // Call saveDay which triggers saveDayLogs + recomputeForDate
      await PersistenceService.saveDay(testDate);

      // Verify week report was computed
      final weekKey = '2026-W23';
      final weekReport = InsightsReportService.instance.weeklyFor(weekKey);
      expect(weekReport, isNotNull);
      expect(weekReport!.loggedDaysCount, equals(7));
    });

    test('5. Historical meals without userCorrected or quality scores upgrade correctly during deserialization', () {
      final oldJson = {
        'canonicalMeal': 'Historic Chicken Rice',
        'items': [
          {
            'name': 'Historic Chicken Rice',
            'quantity': 1.0,
            'unit': 'serving',
            'estimated': false,
            'estimationMode': 'packagedKnown',
            'calories': {'min': 600.0, 'max': 600.0},
            'protein': {'min': 45.0, 'max': 45.0},
            'carbohydrates': {'min': 50.0, 'max': 50.0},
            'fat': {'min': 12.0, 'max': 12.0},
            'fiber': {'min': 4.0, 'max': 4.0},
          }
        ],
        'calories': {'min': 600.0, 'max': 600.0},
        'protein': {'min': 45.0, 'max': 45.0},
        'confidence': 1.0,
        'warnings': [],
        'source': 'user_override',
        'createdAt': '2026-06-01T12:00:00.000Z',
      };

      // Deserialize
      final result = NutritionResult.fromJson(oldJson);

      // Verify that missing fields default correctly and do not crash
      expect(result.userCorrected, isFalse);
      expect(result.macrosLockedByUser, isFalse);
      expect(result.mealQualityScore, isNotNull);
      expect(result.mealQualityScore, greaterThan(0));
      expect(result.mealQualityExplanation, isNotNull);
      expect(result.mealQualityPositive, isNotNull);
      expect(result.mealQualityImprovement, isNotNull);

      // Verify general macros are retained
      expect(result.calories.min, equals(600.0));
      expect(result.protein.min, equals(45.0));
    });

    test('6. Quality score calibration tests for different meal types', () {
      // 1. Pure protein meal: "2 scoops whey"
      final wheyResult = NutritionResult.createCustom(
        canonicalMeal: '2 scoops whey',
        calories: 240,
        protein: 50,
        source: 'quick_add',
      );
      expect(wheyResult.mealQualityScore, greaterThanOrEqualTo(75));

      // 2. Pure carb meal: "3 bananas"
      final bananaResult = NutritionResult.createCustom(
        canonicalMeal: '3 bananas',
        calories: 300,
        protein: 3,
        source: 'quick_add',
      );
      expect(bananaResult.mealQualityScore, lessThan(65));

      // 3. Junk-food meal: "large fries"
      final friesResult = NutritionResult.createCustom(
        canonicalMeal: 'large fries',
        calories: 400,
        protein: 4,
        source: 'quick_add',
      );
      expect(friesResult.mealQualityScore, lessThanOrEqualTo(40));

      // 4. Mixed meal: "paneer and roti"
      final mixedResult = NutritionResult.createCustom(
        canonicalMeal: 'paneer and roti',
        calories: 500,
        protein: 20,
        source: 'quick_add',
      );
      expect(mixedResult.mealQualityScore, greaterThanOrEqualTo(60));
      expect(mixedResult.mealQualityScore, lessThan(85));

      // Verify that explanations, positives, and improvements are all non-empty strings
      for (final r in [wheyResult, bananaResult, friesResult, mixedResult]) {
        expect(r.mealQualityExplanation, isNotEmpty);
        expect(r.mealQualityPositive, isNotEmpty);
        expect(r.mealQualityImprovement, isNotEmpty);
      }
    });

    test('7. End-to-end data propagation and consistency verification', () async {
      final profile = const UserProfile(
        name: 'Dhruv',
        age: 25,
        gender: 'Male',
        height: 175.0,
        weight: 75.0,
        workoutDaysMin: 3,
        workoutDaysMax: 3,
        goal: 'Fat Loss',
      );
      currentUserProfile = profile;

      final testDate = DateTime(2026, 6, 5);
      final testDateStr = '2026-06-05';

      // Setup June 3 and June 4 logs (400 kcal each) to satisfy the 3-day weekly report requirement
      for (int i = 3; i <= 4; i++) {
        final date = DateTime(2026, 6, i);
        final dateStr = '2026-06-0${i}';
        final l = DayLog();
        l.add(
          MealSection.breakfast,
          MealEntry(
            rawInput: 'Eggs and Toast',
            result: NutritionResult.createCustom(
              canonicalMeal: 'Eggs and Toast',
              calories: 400,
              protein: 25,
              source: 'quick_add',
            ),
            addedAt: date,
            section: MealSection.breakfast,
            dayOfWeek: date.weekday,
            parsedFoods: const ['Eggs', 'Toast'],
            finalSavedInput: 'Eggs and Toast',
          ),
        );
        dayLogStore[dateStr] = l;
      }

      // 1. Log meal (400 kcal)
      final initialEntry = MealEntry(
        rawInput: 'Eggs and Toast',
        result: NutritionResult.createCustom(
          canonicalMeal: 'Eggs and Toast',
          calories: 400,
          protein: 25,
          source: 'quick_add',
        ),
        addedAt: testDate,
        section: MealSection.breakfast,
        dayOfWeek: testDate.weekday,
        parsedFoods: const ['Eggs', 'Toast'],
        finalSavedInput: 'Eggs and Toast',
      );
      
      final log = DayLog();
      log.add(MealSection.breakfast, initialEntry);
      dayLogStore[testDateStr] = log;

      // 2. Verify Day View total is initial
      expect(dayLogStore[testDateStr]!.totalCaloriesMid, equals(400.0));

      // 3. Edit meal from 400 kcal to 1200 kcal
      final editedResult = NutritionResult.createCustom(
        canonicalMeal: 'Eggs and Toast',
        calories: 1200,
        protein: 60,
        source: 'user_override',
        userCorrected: true,
      );

      final editedEntry = MealEntry(
        rawInput: 'Eggs and Toast',
        result: editedResult,
        addedAt: testDate,
        section: MealSection.breakfast,
        dayOfWeek: testDate.weekday,
        parsedFoods: const ['Eggs', 'Toast'],
        finalSavedInput: 'Eggs and Toast',
        userCorrected: true,
      );

      // Perform replace
      dayLogStore[testDateStr]!.replace(MealSection.breakfast, initialEntry, editedEntry);

      // Save day to trigger persistence and targeted insights
      await PersistenceService.saveDay(testDate);

      // 4. Verify Day View total updated immediately
      expect(dayLogStore[testDateStr]!.totalCaloriesMid, equals(1200.0));

      // 5. Verify Insights Report updated
      final weekKey = '2026-W23';
      final weekReport = InsightsReportService.instance.weeklyFor(weekKey);
      expect(weekReport, isNotNull);
      // Average calories for the week should reflect the edited 1200 kcal meal
      expect(weekReport!.avgCalories, closeTo(666.67, 0.05));

      // 6. Simulate Close App and Reopen (Serialization / Deserialization check)
      final serializedJson = dayLogStore[testDateStr]!.toJson();
      final deserializedLog = DayLog.fromJson(serializedJson);

      // Verify deserialized totals match
      expect(deserializedLog.totalCaloriesMid, equals(1200.0));
      
      final deserializedEntry = deserializedLog.entriesFor(MealSection.breakfast).first;
      expect(deserializedEntry.result.userCorrected, isTrue);
      expect(deserializedEntry.result.calories.min, equals(1200.0));
    });

    test('8. Custom meal creations and Quick Add meals default to userCorrected = true and locked', () {
      // Create custom meal
      final custom = NutritionResult.createCustom(
        canonicalMeal: 'Custom Steak',
        calories: 800,
        protein: 70,
        source: 'custom_flow',
      );
      expect(custom.userCorrected, isTrue);
      expect(custom.macrosLockedByUser, isTrue);

      // Create quick add meal via JSON or direct call
      final quickAdd = NutritionResult.createCustom(
        canonicalMeal: 'Quick Apple',
        calories: 90,
        protein: 0,
        source: 'quick_add',
      );
      expect(quickAdd.userCorrected, isTrue);
      expect(quickAdd.macrosLockedByUser, isTrue);
    });

    test('9. Fiber target is calculated dynamically based on daily target calories (14g per 1000 kcal) clamped between 20g and 60g', () {
      final engine = NutritionTargetEngine.instance;

      // 1. Very low calories: 1000 kcal -> 14g -> clamped to 20g
      final profileLow = const UserProfile(
        name: 'Dhruv',
        age: 25,
        gender: 'Male',
        height: 170.0,
        weight: 60.0,
        workoutDaysMin: 0,
        workoutDaysMax: 0,
        goal: 'Fat Loss',
        useCustomTargets: true,
        customTrainingDayCalories: 1000,
        customRestDayCalories: 1000,
        customProteinTarget: 100,
      );
      final planLow = engine.weeklyPlan(profileLow);
      expect(planLow.fiberTargetG, equals(20.0));

      // 2. Normal calories: 2000 kcal -> 28g fiber
      final profileNormal = const UserProfile(
        name: 'Dhruv',
        age: 25,
        gender: 'Male',
        height: 175.0,
        weight: 75.0,
        workoutDaysMin: 0,
        workoutDaysMax: 0,
        goal: 'Fat Loss',
        useCustomTargets: true,
        customTrainingDayCalories: 2000,
        customRestDayCalories: 2000,
        customProteinTarget: 130,
      );
      final planNormal = engine.weeklyPlan(profileNormal);
      expect(planNormal.fiberTargetG, equals(28.0));

      // 3. Extremely high calories: 5000 kcal -> 70g -> clamped to 60g
      final profileHigh = const UserProfile(
        name: 'Dhruv',
        age: 25,
        gender: 'Male',
        height: 190.0,
        weight: 100.0,
        workoutDaysMin: 0,
        workoutDaysMax: 0,
        goal: 'Bulk',
        useCustomTargets: true,
        customTrainingDayCalories: 5000,
        customRestDayCalories: 5000,
        customProteinTarget: 180,
      );
      final planHigh = engine.weeklyPlan(profileHigh);
      expect(planHigh.fiberTargetG, equals(60.0));
    });

    test('10. Edited meals cache correctly in MealMemory and are retrievable by rawInput, finalSavedInput, and canonicalMeal', () async {
      final customResult = NutritionResult.createCustom(
        canonicalMeal: 'Aloo Paratha',
        calories: 350,
        protein: 8,
        source: 'user_override',
        userCorrected: true,
      );

      // Store in memory under raw input "2 aloo paratha" but with canonical "Aloo Paratha" and final input "2 Aloo Parathas"
      await MealMemory.instance.store(
        '2 aloo paratha',
        customResult,
        finalSavedInput: '2 Aloo Parathas',
        canonicalMeal: 'Aloo Paratha',
      );

      // Retrieve via rawInput
      final rawMatch = MealMemory.instance.lookup('2 aloo paratha');
      expect(rawMatch, isNotNull);
      expect(rawMatch!.calories.min, equals(350));
      expect(rawMatch.userCorrected, isTrue);

      // Retrieve via finalSavedInput
      final savedMatch = MealMemory.instance.lookup('2 Aloo Parathas');
      expect(savedMatch, isNotNull);
      expect(savedMatch!.calories.min, equals(350));

      // Retrieve via canonicalMeal
      final canonicalMatch = MealMemory.instance.lookup('Aloo Paratha');
      expect(canonicalMatch, isNotNull);
      expect(canonicalMatch!.calories.min, equals(350));
    });
  });
}
