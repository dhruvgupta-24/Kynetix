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
    test('Saving a DayLog with meals and null gymDay auto-populates scheduled training day', () async {
      // Monday June 1, 2026 is a training day in the default split (Chest + Triceps)
      final monday = DateTime(2026, 6, 1);
      final log = _makeLoggedDay();
      
      expect(log.gymDay, isNull);
      
      dayLogStore['2026-06-01'] = log;
      
      // Save Monday
      await PersistenceService.saveDay(monday);
      
      // Verify gymDay was populated with default training split day info
      expect(log.gymDay, isNotNull);
      expect(log.gymDay!.didGym, isTrue);
      expect(log.gymDay!.splitDayName, equals('Chest + Triceps'));
      expect(log.gymDay!.splitOverridden, isFalse);
    });

    test('Saving a DayLog with meals and null gymDay auto-populates rest day on rest day', () async {
      // Sunday June 7, 2026 is a rest day in the default split
      final sunday = DateTime(2026, 6, 7);
      final log = _makeLoggedDay();
      
      expect(log.gymDay, isNull);
      
      dayLogStore['2026-06-07'] = log;
      
      // Save Sunday
      await PersistenceService.saveDay(sunday);
      
      // Verify gymDay was populated as rest day (didGym = false)
      expect(log.gymDay, isNotNull);
      expect(log.gymDay!.didGym, isFalse);
      expect(log.gymDay!.splitOverridden, isFalse);
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

    test('One-time historical repair migration backfills existing null gymDays on training days', () async {
      // Setup old data: Monday (training) and Friday (training) have null gymDays but have meals
      final monday = DateTime(2026, 6, 1);
      final friday = DateTime(2026, 6, 5);
      
      final mondayLog = _makeLoggedDay();
      final fridayLog = _makeLoggedDay();
      
      dayLogStore['2026-06-01'] = mondayLog;
      dayLogStore['2026-06-05'] = fridayLog;
      
      expect(mondayLog.gymDay, isNull);
      expect(fridayLog.gymDay, isNull);
      
      // Run the migration
      await PersistenceService.runHistoricalRepairMigration();
      
      // Verify both are backfilled correctly using their split training day names
      expect(mondayLog.gymDay, isNotNull);
      expect(mondayLog.gymDay!.didGym, isTrue);
      expect(mondayLog.gymDay!.splitDayName, equals('Chest + Triceps'));
      
      expect(fridayLog.gymDay, isNotNull);
      expect(fridayLog.gymDay!.didGym, isTrue);
      expect(fridayLog.gymDay!.splitDayName, equals('Push'));
    });
  });
}
