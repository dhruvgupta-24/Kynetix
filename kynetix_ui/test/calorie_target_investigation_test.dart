import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/models/workout_session.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/models/user_profile.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/services/mock_estimation_service.dart' show NutrientRange;
import 'package:kynetix/services/profile_service.dart';
import 'package:kynetix/services/nutrition_target_engine.dart';
import 'package:kynetix/services/workout_service.dart';
import 'package:kynetix/services/persistence_service.dart';
import 'package:kynetix/services/insights_engine.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://mock.supabase.co',
      anonKey: 'mockAnonKey',
    );
    await WorkoutService.instance.clearAll();
    dayLogStore.clear();
  });

  group('Calorie Target Investigation & Regression Tests', () {
    // Standard profile that yields base training calories of 2430 kcal when rounded.
    final profile2430 = UserProfile(
      name: 'Dhruv',
      age: 25,
      gender: 'Male',
      height: 180.0,
      weight: 102.3,
      workoutDaysMin: 5,
      workoutDaysMax: 6,
      goal: kFatLoss,
    );

    test('Verify base training calorie target is 2430 kcal (rounded)', () {
      final engine = NutritionTargetEngine.instance;
      final plan = engine.weeklyPlan(profile2430);

      expect(plan.trainingDayCalories.round(), equals(2430));
      // Clamped to floor = BMR + 200 = 2028 + 200 = 2228 kcal
      expect(plan.restDayCalories.round(), equals(2228));
    });

    test('Verify Chest + Triceps day (Mon 8 Jun) session load bonus', () {
      final engine = NutritionTargetEngine.instance;

      // Construct a Chest + Triceps session.
      // We want score between 80 and 89 (inclusive).
      // total score = 85 (yields +160 kcal bonus)
      final chestSession = WorkoutSession(
        id: 'chest-triceps-mon',
        date: DateTime(2026, 6, 8),
        splitDayName: 'Chest + Triceps',
        durationMinutes: 54,
        entries: [
          for (int i = 0; i < 5; i++)
            ExerciseEntry(
              exercise: Exercise(
                id: 'ex-$i',
                name: 'Exercise $i',
                muscleGroup: 'Chest',
                type: ExerciseType.dumbbell,
              ),
              sets: [
                const SetEntry(weight: 60, reps: 8),
                const SetEntry(weight: 60, reps: 8),
                const SetEntry(weight: 55, reps: 8),
              ],
            ),
        ],
        status: WorkoutStatus.completed,
      );

      final target = engine.dayTarget(
        profile2430,
        isGymDay: true,
        session: chestSession,
        workoutTypeName: 'Chest + Triceps',
      );

      expect(target.calories.round(), equals(2430)); // workout load bonus removed
      expect(target.workoutLoadScore, equals(85));
      expect(target.workoutCalBonus, isNull);
    });

    test('Verify Back + Biceps day (Tue 9 Jun) session load bonus', () {
      final engine = NutritionTargetEngine.instance;

      // Construct a Back + Biceps session.
      // We want score >= 90.
      // total score = 100 (yields +200 kcal bonus)
      final backSession = WorkoutSession(
        id: 'back-biceps-tue',
        date: DateTime(2026, 6, 9),
        splitDayName: 'Back + Biceps',
        durationMinutes: 60,
        entries: [
          for (int i = 0; i < 4; i++)
            ExerciseEntry(
              exercise: Exercise(
                id: 'back-ex-$i',
                name: 'Back Exercise $i',
                muscleGroup: 'Back',
                type: ExerciseType.barbellCompound,
              ),
              sets: [
                const SetEntry(weight: 80, reps: 8),
                const SetEntry(weight: 80, reps: 8),
                const SetEntry(weight: 80, reps: 8),
                const SetEntry(weight: 72, reps: 8),
              ],
            ),
        ],
        status: WorkoutStatus.completed,
      );

      final target = engine.dayTarget(
        profile2430,
        isGymDay: true,
        session: backSession,
        workoutTypeName: 'Back + Biceps',
      );

      expect(target.calories.round(), equals(2430)); // workout load bonus removed
      expect(target.workoutLoadScore, equals(100));
      expect(target.workoutCalBonus, isNull);
    });

    test('Verify independence from today\'s workout split schedule', () {
      final engine = NutritionTargetEngine.instance;

      final historicalDate = DateTime(2026, 6, 8); // Monday
      final log = logFor(historicalDate);
      
      log.gymDay = const GymDay(
        didGym: true,
        workoutType: WorkoutType.push,
        splitDayName: 'Chest + Triceps',
        splitOverridden: false,
      );

      dayLogStore[dateKey(historicalDate)] = log;

      final savedGymDay = log.gymDay!;
      expect(savedGymDay.splitDayName, equals('Chest + Triceps'));
      expect(savedGymDay.didGym, isTrue);

      final isGymDay = savedGymDay.didGym;
      final workoutTypeName = savedGymDay.workoutType?.displayName ?? savedGymDay.splitDayName;

      final target = engine.dayTarget(
        profile2430,
        isGymDay: isGymDay,
        workoutTypeName: workoutTypeName,
        date: historicalDate,
      );

      expect(target.calories.round(), equals(2430)); // Training day target
      expect(target.label, equals('Push Day'));
    });

    test('Verify calorie target drift is prevented via date-based saved target loading', () {
      final engine = NutritionTargetEngine.instance;
      final historicalDate = DateTime(2026, 6, 8); // Monday
      
      // Create a log and add a meal to simulate a saved day log.
      final log = logFor(historicalDate);
      log.add(
        MealSection.breakfast,
        MealEntry(
          rawInput: 'Oats',
          addedAt: historicalDate,
          section: MealSection.breakfast,
          dayOfWeek: historicalDate.weekday,
          parsedFoods: const ['Oats'],
          finalSavedInput: 'Oats',
          result: NutritionResult(
            canonicalMeal: 'Oats',
            items: const [],
            calories: const NutrientRange(min: 300, max: 300),
            protein: const NutrientRange(min: 10, max: 10),
            confidence: 0.95,
            warnings: const [],
            source: 'test',
            createdAt: DateTime.now(),
          ),
        ),
      );

      // Verify saveDay populates split name and target calories
      // We will temporarily configure ProfileService currentUserProfile.
      final pService = ProfileService.instance;
      pService.currentUserProfile = profile2430;

      // Ensure split has Chest + Triceps on Monday
      final splitDay = WorkoutService.instance.splitDayFor(historicalDate);
      expect(splitDay?.name, equals('Chest + Triceps'));

      // Call saveDay to trigger target freezing.
      // We need to make sure log.gymDay is set up or saveDay does it.
      expect(log.targetCalories, isNull);
      
      // Calculate isGymDay: split training day is true.
      final isGymDayVal = (splitDay != null && !splitDay.isRestDay);
      final resolvedTarget = engine.dayTarget(
        profile2430,
        isGymDay: isGymDayVal,
        workoutTypeName: splitDay?.name,
      );
      
      log.targetCalories = resolvedTarget.calories;
      log.targetProtein = resolvedTarget.protein;
      log.gymDay = GymDay(
        didGym: true,
        workoutType: WorkoutType.fromSplitName(splitDay!.name),
        splitDayName: splitDay.name,
      );
      dayLogStore[dateKey(historicalDate)] = log;

      expect(log.targetCalories?.round(), equals(2430));

      // Now query targetCalories using dayTarget with the date parameter.
      final targetBefore = engine.dayTarget(
        profile2430,
        isGymDay: log.gymDay!.didGym,
        workoutTypeName: log.gymDay!.splitDayName,
        date: historicalDate,
      );
      expect(targetBefore.calories.round(), equals(2430));

      // Modify the UserProfile (e.g. increase weight to 120 kg).
      final modifiedProfile = profile2430.copyWith(weight: 120.0);

      // Query target again WITH the date parameter.
      final targetAfter = engine.dayTarget(
        modifiedProfile,
        isGymDay: log.gymDay!.didGym,
        workoutTypeName: log.gymDay!.splitDayName,
        date: historicalDate,
      );

      // Verify that the calorie target has NOT drifted (remains 2430 kcal).
      expect(targetAfter.calories.round(), equals(2430));
      expect(targetAfter.note, contains('Saved Target (Drift Protected)'));

      // Meanwhile, querying WITHOUT the date parameter should recalculate and drift:
      final targetRecalculated = engine.dayTarget(
        modifiedProfile,
        isGymDay: log.gymDay!.didGym,
        workoutTypeName: log.gymDay!.splitDayName,
      );
      expect(targetRecalculated.calories.round(), isNot(equals(2430)));
    });

    test('Verify mixed historical data: past frozen targets retain old logic, new targets use new logic, and reports behave correctly', () {
      final engine = NutritionTargetEngine.instance;

      // 1. Create a historical day log from "before the change" with frozen targets of 2590 kcal
      final oldDate = DateTime(2026, 6, 8); // Monday
      final oldKey = dateKey(oldDate);
      final oldLog = logFor(oldDate);
      oldLog.targetCalories = 2590.0;
      oldLog.targetProtein = 180.0;
      oldLog.gymDay = const GymDay(
        didGym: true,
        workoutType: WorkoutType.push,
        splitDayName: 'Chest + Triceps',
      );
      
      // Add a meal to make it non-empty so reports consider it logged
      oldLog.add(
        MealSection.breakfast,
        MealEntry(
          rawInput: 'Breakfast',
          addedAt: oldDate,
          section: MealSection.breakfast,
          dayOfWeek: oldDate.weekday,
          parsedFoods: const ['Eggs'],
          finalSavedInput: 'Eggs',
          result: NutritionResult(
            canonicalMeal: 'Eggs',
            items: const [],
            calories: const NutrientRange(min: 2000, max: 2000),
            protein: const NutrientRange(min: 150, max: 150),
            confidence: 0.95,
            warnings: const [],
            source: 'test',
            createdAt: DateTime.now(),
          ),
        ),
      );
      dayLogStore[oldKey] = oldLog;

      // 2. Create a new day log from "after the change" where targets recalculate to 2430 kcal
      final newDate = DateTime(2026, 6, 9); // Tuesday
      final newKey = dateKey(newDate);
      final newLog = logFor(newDate);
      newLog.gymDay = const GymDay(
        didGym: true,
        workoutType: WorkoutType.pull,
        splitDayName: 'Back + Biceps',
      );
      newLog.add(
        MealSection.breakfast,
        MealEntry(
          rawInput: 'Breakfast',
          addedAt: newDate,
          section: MealSection.breakfast,
          dayOfWeek: newDate.weekday,
          parsedFoods: const ['Eggs'],
          finalSavedInput: 'Eggs',
          result: NutritionResult(
            canonicalMeal: 'Eggs',
            items: const [],
            calories: const NutrientRange(min: 2000, max: 2000),
            protein: const NutrientRange(min: 150, max: 150),
            confidence: 0.95,
            warnings: const [],
            source: 'test',
            createdAt: DateTime.now(),
          ),
        ),
      );
      dayLogStore[newKey] = newLog;

      // 3. Create a third day log from Wednesday (June 10) to satisfy the 3-day minimum logging limit for weekly reports
      final thirdDate = DateTime(2026, 6, 10);
      final thirdKey = dateKey(thirdDate);
      final thirdLog = logFor(thirdDate);
      thirdLog.gymDay = const GymDay(didGym: false);
      thirdLog.add(
        MealSection.breakfast,
        MealEntry(
          rawInput: 'Breakfast',
          addedAt: thirdDate,
          section: MealSection.breakfast,
          dayOfWeek: thirdDate.weekday,
          parsedFoods: const ['Eggs'],
          finalSavedInput: 'Eggs',
          result: NutritionResult(
            canonicalMeal: 'Eggs',
            items: const [],
            calories: const NutrientRange(min: 2000, max: 2000),
            protein: const NutrientRange(min: 150, max: 150),
            confidence: 0.95,
            warnings: const [],
            source: 'test',
            createdAt: DateTime.now(),
          ),
        ),
      );
      dayLogStore[thirdKey] = thirdLog;

      // Query target for the old date WITH date parameter (should yield 2590)
      final targetOld = engine.dayTarget(
        profile2430,
        isGymDay: oldLog.gymDay!.didGym,
        workoutTypeName: oldLog.gymDay!.splitDayName,
        date: oldDate,
      );
      expect(targetOld.calories.round(), equals(2590)); // Frozen target preserved

      // Query target for the new date WITH date parameter (should yield 2430 since it is not frozen yet)
      final targetNew = engine.dayTarget(
        profile2430,
        isGymDay: newLog.gymDay!.didGym,
        workoutTypeName: newLog.gymDay!.splitDayName,
        date: newDate,
      );
      expect(targetNew.calories.round(), equals(2430)); // New logic (0 calorie bonus) applied

      // 4. Set the profile on ProfileService
      final pService = ProfileService.instance;
      pService.currentUserProfile = profile2430;

      // Verify that saveDay freezes Tuesday at 2430
      PersistenceService.saveDay(newDate);
      expect(newLog.targetCalories?.round(), equals(2430));

      // 5. Verify weekly report uses 2590 for Monday and 2430 for Tuesday
      final wKey = InsightsEngine.weekKeyOf(oldDate);
      final wReport = InsightsEngine.computeWeek(
        weekKey: wKey,
        profile: profile2430,
        logs: dayLogStore,
        sessions: const [],
        priorWeek: null,
      );
      
      expect(wReport, isNotNull);
      expect(wReport!.loggedDaysCount, equals(3));
      // Average consumed calories is 2000 for all three days, so average is 2000
      expect(wReport.avgCalories.round(), equals(2000));
    });
  });
}
