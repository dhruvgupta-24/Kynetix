import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/models/workout_session.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/services/mock_estimation_service.dart' show NutrientRange;
import 'package:kynetix/services/user_session_coordinator.dart';
import 'package:kynetix/services/workout_service.dart';
import 'package:kynetix/services/user_nutrition_memory.dart';
import 'package:kynetix/services/nutrition_hydration_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testUserId = 'dhruv-test-uuid-ff27ad41';

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://mock.supabase.co',
      anonKey: 'mock-anon-key',
    );
  });

  setUp(() async {
    await UserSessionCoordinator.instance.clearAllUserServices();
  });

  group('Data Preservation & Migration Audit Tests', () {
    test('Pre-migration snapshot, non-destructive migration, and field-by-field verification', () async {
      // 1. Arrange: populate realistic historical unscoped local persistence
      final originalDayLog = DayLog()
        ..targetCalories = 2450.0
        ..targetProtein = 165.0
        ..gymDay = const GymDay(didGym: true, splitDayName: 'Push A');

      originalDayLog.add(
        MealSection.breakfast,
        MealEntry(
          rawInput: '3 eggs and toast',
          addedAt: DateTime(2026, 3, 1, 8, 30),
          section: MealSection.breakfast,
          dayOfWeek: 7,
          parsedFoods: ['eggs', 'toast'],
          finalSavedInput: '3 eggs and toast',
          result: NutritionResult(
            canonicalMeal: 'eggs and toast',
            items: const [
              NutritionItem(
                name: 'eggs',
                quantity: 3.0,
                unit: 'piece',
                estimated: false,
                mode: EstimationMode.directQuantity,
                calories: NutrientRange(min: 240, max: 240),
                protein: NutrientRange(min: 18, max: 18),
                carbohydrates: NutrientRange(min: 2, max: 2),
                fat: NutrientRange(min: 15, max: 15),
                fiber: NutrientRange(min: 0, max: 0),
              ),
              NutritionItem(
                name: 'toast',
                quantity: 1.0,
                unit: 'slice',
                estimated: false,
                mode: EstimationMode.directQuantity,
                calories: NutrientRange(min: 140, max: 140),
                protein: NutrientRange(min: 4.5, max: 4.5),
                carbohydrates: NutrientRange(min: 24, max: 24),
                fat: NutrientRange(min: 2, max: 2),
                fiber: NutrientRange(min: 1.5, max: 1.5),
              ),
            ],
            calories: const NutrientRange(min: 380, max: 380),
            protein: const NutrientRange(min: 22.5, max: 22.5),
            carbohydrates: const NutrientRange(min: 26, max: 26),
            fat: const NutrientRange(min: 17, max: 17),
            fiber: const NutrientRange(min: 1.5, max: 1.5),
            confidence: 0.95,
            warnings: [],
            source: 'test',
            createdAt: DateTime(2026, 3, 1),
          ),
        ),
      );

      originalDayLog.add(
        MealSection.lunch,
        MealEntry(
          rawInput: 'chicken breast and rice',
          addedAt: DateTime(2026, 3, 1, 13, 0),
          section: MealSection.lunch,
          dayOfWeek: 7,
          parsedFoods: ['chicken breast', 'rice'],
          finalSavedInput: 'chicken breast and rice',
          result: NutritionResult(
            canonicalMeal: 'chicken breast and rice',
            items: const [
              NutritionItem(
                name: 'chicken breast',
                quantity: 200.0,
                unit: 'g',
                estimated: false,
                mode: EstimationMode.directQuantity,
                calories: NutrientRange(min: 330, max: 330),
                protein: NutrientRange(min: 44, max: 44),
                carbohydrates: NutrientRange(min: 0, max: 0),
                fat: NutrientRange(min: 7, max: 7),
                fiber: NutrientRange(min: 0, max: 0),
              ),
            ],
            calories: const NutrientRange(min: 550, max: 550),
            protein: const NutrientRange(min: 50, max: 50),
            carbohydrates: const NutrientRange(min: 45, max: 45),
            fat: const NutrientRange(min: 8, max: 8),
            fiber: const NutrientRange(min: 1, max: 1),
            confidence: 0.95,
            warnings: [],
            source: 'test',
            createdAt: DateTime(2026, 3, 1),
          ),
        ),
      );

      final originalDayLogsJson = jsonEncode({
        '2026-03-01': originalDayLog.toJson(),
      });

      const benchPress = Exercise(
        id: 'barbell_bench_press',
        name: 'Barbell Bench Press',
        muscleGroup: 'Chest',
        type: ExerciseType.barbellCompound,
      );

      final originalWorkoutSession = WorkoutSession(
        id: 'session_001',
        splitDayName: 'Push A',
        date: DateTime(2026, 3, 1, 17, 30),
        durationMinutes: 60,
        entries: [
          ExerciseEntry(
            exercise: benchPress,
            logicalSets: [
              const LogicalSetGroup(
                mainSet: SetEntry(weight: 80.0, reps: 8, setType: SetType.normal),
              ),
              const LogicalSetGroup(
                mainSet: SetEntry(weight: 85.0, reps: 6, setType: SetType.normal),
              ),
            ],
          ),
        ],
      );

      const originalWorkoutSplit = WorkoutSplit(
        id: 'split_001',
        name: 'PPL',
        days: [
          SplitDay(
            weekday: 1,
            name: 'Push A',
            exercises: [benchPress],
          ),
        ],
      );

      final originalWorkoutJson = jsonEncode({
        'split': originalWorkoutSplit.toJson(),
        'sessions': [originalWorkoutSession.toJson()],
        'setupDone': true,
        'customExercises': [],
        'additionAcceptedCounts': {},
        'additionIgnoredCounts': {},
      });

      final originalOverridesList = [
        jsonEncode({
          'canonicalMeal': 'homemade protein shake',
          'caloriesPerUnit': 350.0,
          'proteinPerUnit': 40.0,
          'carbohydratesPerUnit': 20.0,
          'fatPerUnit': 5.0,
          'fiberPerUnit': 3.0,
          'referenceUnit': 'serving',
          'referenceQuantity': 1.0,
          'correctionCount': 3,
          'savedAt': DateTime(2026, 2, 20).toIso8601String(),
        }),
      ];

      final originalMealMemoryJson = jsonEncode([
        {
          'rawInput': 'whey protein',
          'result': {
            'canonicalMeal': 'whey protein',
            'items': [],
            'calories': {'min': 120.0, 'max': 120.0},
            'protein': {'min': 24.0, 'max': 24.0},
            'carbohydrates': {'min': 2.0, 'max': 2.0},
            'fat': {'min': 1.5, 'max': 1.5},
            'fiber': {'min': 0.0, 'max': 0.0},
            'confidence': 0.98,
            'warnings': [],
          },
          'timesLogged': 12,
          'lastLogged': DateTime(2026, 3, 1).toIso8601String(),
        }
      ]);

      SharedPreferences.setMockInitialValues({
        'day_logs_v1': originalDayLogsJson,
        'workout_data_v2': originalWorkoutJson,
        'user_meal_overrides_v1': originalOverridesList,
        'meal_memory_v1': originalMealMemoryJson,
        'user_profile_v2': jsonEncode({
          'name': 'Dhruv',
          'goal': 'Muscle Building',
          'weight': 75.0,
          'height': 178.0,
          'age': 25,
          'workout_days_min': 4,
          'workout_days_max': 5,
        }),
      });

      final prefs = await SharedPreferences.getInstance();

      // 2. Act: Initialize user-scoped services for the authenticated user
      await UserSessionCoordinator.instance.initializeForUser(testUserId, prefsOverride: prefs);

      // 3. Assert: Verify Migration Audit Report
      final report = UserSessionCoordinator.instance.lastAuditReport;
      expect(report, isNotNull);
      expect(report!.isVerified, isTrue);
      expect(report.userId, equals(testUserId));

      // Strict Zero-Loss / Zero-Mutation Verification
      expect(report.historicalNutritionRecordsScanned, equals(2));
      expect(report.historicalNutritionRecordsChanged, equals(0), reason: 'Zero nutrition records changed');
      expect(report.historicalNutritionRecordsDeleted, equals(0), reason: 'Zero nutrition records deleted');
      expect(report.historicalNutritionRecordsLost, equals(0), reason: 'Zero nutrition records lost');

      expect(report.workoutSessionsScanned, equals(1));
      expect(report.workoutSessionsChanged, equals(0), reason: 'Zero workout sessions changed');
      expect(report.workoutSessionsDeleted, equals(0), reason: 'Zero workout sessions deleted');
      expect(report.workoutSessionsLost, equals(0), reason: 'Zero workout sessions lost');

      expect(report.overridesScanned, equals(1));
      expect(report.overridesLost, equals(0), reason: 'Zero overrides lost');

      expect(report.mealMemoryScanned, equals(1));
      expect(report.mealMemoryLost, equals(0), reason: 'Zero meal memory items lost');

      // 4. Assert: Pre-migration snapshots exist and match original data byte-for-byte
      expect(prefs.getString('backup_pre_migration_day_logs_v1'), equals(originalDayLogsJson));
      expect(prefs.getString('backup_pre_migration_workout_data_v2'), equals(originalWorkoutJson));
      expect(prefs.getStringList('backup_pre_migration_user_meal_overrides_v1'), equals(originalOverridesList));
      expect(prefs.getString('backup_pre_migration_meal_memory_v1'), equals(originalMealMemoryJson));

      // 5. Assert: Original unscoped keys are kept intact as rollback safety
      expect(prefs.getString('day_logs_v1'), equals(originalDayLogsJson));
      expect(prefs.getString('workout_data_v2'), equals(originalWorkoutJson));
      expect(prefs.getStringList('user_meal_overrides_v1'), equals(originalOverridesList));
      expect(prefs.getString('meal_memory_v1'), equals(originalMealMemoryJson));

      // 6. Assert: Scoped stores contain exact data and are loaded into active services
      expect(dayLogStore.containsKey('2026-03-01'), isTrue);
      final loadedLog = dayLogStore['2026-03-01']!;
      expect(loadedLog.targetCalories, equals(2450.0));
      expect(loadedLog.targetProtein, equals(165.0));
      expect(loadedLog.gymDay?.didGym, isTrue);
      expect(loadedLog.gymDay?.splitDayName, equals('Push A'));

      // Check breakfast items field-by-field
      final breakfastEntries = loadedLog.entriesFor(MealSection.breakfast);
      expect(breakfastEntries.length, equals(1));
      final bf = breakfastEntries.first;
      expect(bf.calMid, equals(380.0));
      expect(bf.protMid, equals(22.5));
      expect(bf.result.carbohydrates?.mid, equals(26.0));
      expect(bf.result.fat?.mid, equals(17.0));
      expect(bf.result.fiber?.mid, equals(1.5));
      expect(bf.result.items.length, equals(2));
      expect(bf.result.items[0].name, equals('eggs'));
      expect(bf.result.items[0].quantity, equals(3.0));
      expect(bf.result.items[0].calories.mid, equals(240.0));
      expect(bf.result.items[0].protein.mid, equals(18.0));
      expect(bf.result.items[1].name, equals('toast'));
      expect(bf.result.items[1].calories.mid, equals(140.0));

      // Check workout session in service
      final loadedSessions = WorkoutService.instance.sessions;
      expect(loadedSessions.length, equals(1));
      final session = loadedSessions.first;
      expect(session.splitDayName, equals('Push A'));
      expect(session.entries.length, equals(1));
      expect(session.entries.first.exercise.id, equals('barbell_bench_press'));
      expect(session.entries.first.sets.length, equals(2));
      expect(session.entries.first.sets[0].weight, equals(80.0));
      expect(session.entries.first.sets[0].reps, equals(8));
      expect(session.entries.first.sets[1].weight, equals(85.0));
      expect(session.entries.first.sets[1].reps, equals(6));

      // Check user override in service
      final loadedOverrides = UserNutritionMemory.instance.allOverrides;
      expect(loadedOverrides.length, equals(1));
      expect(loadedOverrides.first.canonicalMeal, equals('protein shake'));
      expect(loadedOverrides.first.caloriesPerUnit, equals(350.0));
      expect(loadedOverrides.first.proteinPerUnit, equals(40.0));

      // Check hydration guard is open for this user
      expect(NutritionHydrationGuard.instance.isReadyForCurrentUser, isTrue);
    });
  });
}
