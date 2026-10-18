import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/models/user_profile.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/models/workout_session.dart';
import 'package:kynetix/services/workout_service.dart';
import 'package:kynetix/services/persistence_service.dart';
import 'package:kynetix/services/insights_report_service.dart';
import 'package:kynetix/services/profile_service.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/services/mock_estimation_service.dart' show NutrientRange;
import 'package:kynetix/services/insights_engine.dart';

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
    dayLogStore.clear();
    await WorkoutService.instance.clearAll();
    WorkoutService.instance.resetReadyForTesting();
    await WorkoutService.instance.init();
    
    // Set a default user profile in ProfileService
    ProfileService.instance.currentUserProfile = const UserProfile(
      name: 'Dhruv',
      age: 25,
      gender: 'Male',
      height: 175.0,
      weight: 70.0,
      workoutDaysMin: 4,
      workoutDaysMax: 5,
      goal: 'Fat Loss',
    );
  });

  DayLog _makeLoggedDay() {
    final log = DayLog();
    log.add(
      MealSection.breakfast,
      MealEntry(
        rawInput: 'Eggs',
        result: NutritionResult(
          canonicalMeal: 'Eggs',
          items: const [],
          calories: NutrientRange(min: 300, max: 300),
          protein: NutrientRange(min: 25, max: 25),
          confidence: 0.95,
          warnings: const [],
          source: 'test',
          createdAt: DateTime(2026, 6, 1),
        ),
        addedAt: DateTime(2026, 6, 1),
        section: MealSection.breakfast,
        dayOfWeek: 1,
        parsedFoods: const ['Eggs'],
        finalSavedInput: 'Eggs',
      ),
    );
    return log;
  }

  group('Workout Consistency — Auto-persistence & Migration Fix A', () {
    // The day's training plan is resolved live (session > pick > split), so a
    // save no longer freezes the split into gymDay: editing the split later
    // updates days the user never touched, on every screen at once.
    test('Saving a DayLog with meals leaves gymDay unset; the split still decides', () async {
      // Monday June 1, 2026 is a training day in the default split (Chest + Triceps)
      final monday = DateTime(2026, 6, 1);
      final log = _makeLoggedDay();
      dayLogStore['2026-06-01'] = log;

      await PersistenceService.saveDay(monday);

      expect(log.gymDay, isNull);
      final plan = WorkoutService.instance.planFor(monday);
      expect(plan.isTraining, isTrue);
      expect(plan.name, equals('Chest + Triceps'));
      expect(plan.source, DayPlanSource.split);
    });

    test('A rest day in the split resolves to rest without a stored gymDay', () async {
      // Sunday June 7, 2026 is a rest day in the default split
      final sunday = DateTime(2026, 6, 7);
      final log = _makeLoggedDay();
      dayLogStore['2026-06-07'] = log;

      await PersistenceService.saveDay(sunday);

      expect(log.gymDay, isNull);
      expect(WorkoutService.instance.planFor(sunday).isTraining, isFalse);
    });

    test('Explicit user action (didGym=false) overrides split fallback', () async {
      final monday = DateTime(2026, 6, 1);
      final log = _makeLoggedDay();
      log.gymDay = const GymDay(didGym: false, splitOverridden: true);
      
      dayLogStore['2026-06-01'] = log;
      
      await PersistenceService.saveDay(monday);
      
      // Verify that user override is preserved and NOT auto-populated to true
      expect(log.gymDay, isNotNull);
      expect(log.gymDay!.didGym, isFalse);
    });

    test('Historical repair no longer back-fills gymDay; the split resolves those days', () async {
      final monday = DateTime(2026, 6, 1);
      final friday = DateTime(2026, 6, 5);
      final mondayLog = _makeLoggedDay();
      final fridayLog = _makeLoggedDay();
      dayLogStore['2026-06-01'] = mondayLog;
      dayLogStore['2026-06-05'] = fridayLog;

      await PersistenceService.runHistoricalRepairMigration();

      expect(mondayLog.gymDay, isNull);
      expect(fridayLog.gymDay, isNull);
      expect(WorkoutService.instance.planFor(monday).name, equals('Chest + Triceps'));
      expect(WorkoutService.instance.planFor(friday).name, equals('Push'));
    });
  });

  group('Workout Consistency Source of Truth - isGymDay Rules', () {
    test('Gym toggle YES with no workout session -> Gym Day = YES', () {
      final date = DateTime(2026, 6, 1);
      final log = DayLog();
      log.gymDay = const GymDay(didGym: true);
      
      final result = InsightsEngine.isGymDay(
        date: date,
        log: log,
        session: null,
      );
      
      expect(result, isTrue);
    });

    test('Workout session completed with toggle NO -> Gym Day = YES', () {
      final date = DateTime(2026, 6, 1);
      final log = DayLog();
      log.gymDay = const GymDay(didGym: false);
      
      final session = WorkoutSession(
        id: 'ws-123',
        date: date,
        splitDayName: 'Push',
        entries: [
          ExerciseEntry(
            exercise: const Exercise(id: 'ex-1', name: 'Bench Press', muscleGroup: 'Chest', type: ExerciseType.barbellCompound),
            sets: [
              const SetEntry(weight: 60.0, reps: 8, setType: SetType.normal),
            ],
          ),
        ],
      );
      
      final result = InsightsEngine.isGymDay(
        date: date,
        log: log,
        session: session,
      );
      
      expect(result, isTrue);
    });

    test('Both present -> Gym Day = YES', () {
      final date = DateTime(2026, 6, 1);
      final log = DayLog();
      log.gymDay = const GymDay(didGym: true);
      
      final session = WorkoutSession(
        id: 'ws-123',
        date: date,
        splitDayName: 'Push',
        entries: [
          ExerciseEntry(
            exercise: const Exercise(id: 'ex-1', name: 'Bench Press', muscleGroup: 'Chest', type: ExerciseType.barbellCompound),
            sets: [
              const SetEntry(weight: 60.0, reps: 8, setType: SetType.normal),
            ],
          ),
        ],
      );
      
      final result = InsightsEngine.isGymDay(
        date: date,
        log: log,
        session: session,
      );
      
      expect(result, isTrue);
    });

    test('Neither present -> Gym Day = NO', () {
      final date = DateTime(2026, 6, 1);
      final log = DayLog();
      
      final result1 = InsightsEngine.isGymDay(
        date: date,
        log: null,
        session: null,
      );
      expect(result1, isFalse);
      
      log.gymDay = const GymDay(didGym: false);
      final result2 = InsightsEngine.isGymDay(
        date: date,
        log: log,
        session: null,
      );
      expect(result2, isFalse);
    });
  });
}
