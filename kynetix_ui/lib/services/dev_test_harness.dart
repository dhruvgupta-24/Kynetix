import 'package:flutter/foundation.dart';
import '../models/day_log.dart';
import 'mock_estimation_service.dart';
import '../models/nutrition_result.dart';
import '../models/user_profile.dart';
import '../models/workout_session.dart';
import '../models/workout_split.dart';
import 'persistence_service.dart';
import 'profile_service.dart';
import 'workout_service.dart';

/// Strictly development- and test-only harness for seeding reproducible test fixtures.
///
/// Cannot be invoked in release/production builds (`kDebugMode` assertion).
/// Cannot be invoked for real user accounts (strictly enforced `dev_` prefix check).
class DevTestHarness {
  const DevTestHarness._();

  /// Seeds a designated developer test user with a deterministic training plateau
  /// and multi-meal nutrition history.
  ///
  /// Throws [StateError] if run outside of debug mode.
  /// Throws [ArgumentError] if the userId is not a developer test account.
  static Future<void> seedDevTesterData(String userId) async {
    if (!kDebugMode) {
      throw StateError('DevTestHarness cannot be executed in production or release mode.');
    }
    if (!userId.startsWith('dev_')) {
      throw ArgumentError(
        'DevTestHarness can only seed test accounts prefixed with "dev_". '
        'Refusing to seed account: $userId to prevent overwriting production user data.',
      );
    }

    if (ProfileService.instance.currentUserProfile == null) {
      await PersistenceService.saveProfile(
        const UserProfile(
          name: 'Dev Tester',
          age: 25,
          gender: 'male',
          height: 175,
          weight: 75,
          workoutDaysMin: 4,
          workoutDaysMax: 6,
          goal: 'maintain',
        ),
      );
    }
    await PersistenceService.setOnboardingDone();
    await WorkoutService.instance.saveSplit(defaultWorkoutSplit);

    // Seed realistic multi-week history for dev test user if empty
    if (WorkoutService.instance.sessions.isEmpty) {
      final now = DateTime.now();
      const shoulderPress = Exercise(
        id: 'db_shoulder_press',
        name: 'DB Shoulder Press',
        muscleGroup: 'Shoulders',
        type: ExerciseType.dumbbell,
        defaultTargetSets: 3,
        defaultRepMin: 8,
        defaultRepMax: 10,
      );

      // 3 consecutive historical workouts stalling at 25kg x 8
      final s1 = WorkoutSession(
        id: 'ws_hist_dev_1',
        date: now.subtract(const Duration(days: 10)),
        splitDayName: 'Shoulders',
        durationMinutes: 48,
        entries: [
          ExerciseEntry(
            exercise: shoulderPress,
            sets: [
              SetEntry(weight: 25.0, reps: 8, rpe: 8.5),
              SetEntry(weight: 25.0, reps: 8, rpe: 8.5),
              SetEntry(weight: 25.0, reps: 8, rpe: 9.0),
            ],
          ),
        ],
      );
      final s2 = WorkoutSession(
        id: 'ws_hist_dev_2',
        date: now.subtract(const Duration(days: 6)),
        splitDayName: 'Shoulders',
        durationMinutes: 45,
        entries: [
          ExerciseEntry(
            exercise: shoulderPress,
            sets: [
              SetEntry(weight: 25.0, reps: 8, rpe: 8.5),
              SetEntry(weight: 25.0, reps: 8, rpe: 9.0),
              SetEntry(weight: 25.0, reps: 8, rpe: 9.0),
            ],
          ),
        ],
      );
      final s3 = WorkoutSession(
        id: 'ws_hist_dev_3',
        date: now.subtract(const Duration(days: 2)),
        splitDayName: 'Shoulders',
        durationMinutes: 52,
        entries: [
          ExerciseEntry(
            exercise: shoulderPress,
            sets: [
              SetEntry(weight: 25.0, reps: 8, rpe: 9.0),
              SetEntry(weight: 25.0, reps: 8, rpe: 9.0),
              SetEntry(weight: 25.0, reps: 8, rpe: 9.5),
            ],
          ),
        ],
      );
      await WorkoutService.instance.saveSession(s1);
      await WorkoutService.instance.saveSession(s2);
      await WorkoutService.instance.saveSession(s3);

      // 14 days of nutrition history (averaging 73g protein, 882 kcal vs 150g target)
      for (int i = 1; i <= 14; i++) {
        final d = now.subtract(Duration(days: i));
        final dLog = DayLog()
          ..targetProtein = 150.0
          ..targetCalories = 2300.0
          ..gymDay = GymDay(didGym: i % 2 == 0);

        if (i == 1) {
          // Deterministic multi-meal test fixture day for yesterday
          // Test Data: 5 realistic meals across the day including late-night calorie-dense item
          final bDate = DateTime(d.year, d.month, d.day, 8, 15);
          final lDate = DateTime(d.year, d.month, d.day, 13, 15);
          final sDate = DateTime(d.year, d.month, d.day, 17, 30);
          final dinDate = DateTime(d.year, d.month, d.day, 20, 15);
          final lnDate = DateTime(d.year, d.month, d.day, 22, 45);

          dLog.add(
            MealSection.breakfast,
            MealEntry(
              rawInput: 'Oatmeal with Blueberries & Honey',
              result: NutritionResult(
                canonicalMeal: 'Oatmeal with Blueberries & Honey',
                items: [],
                calories: NutrientRange(min: 420, max: 420),
                protein: NutrientRange(min: 8, max: 8),
                carbohydrates: NutrientRange(min: 78, max: 78),
                fat: NutrientRange(min: 6, max: 6),
                confidence: 1.0,
                warnings: [],
                source: 'test_fixture_multimeal',
                createdAt: bDate,
              ),
              addedAt: bDate,
              section: MealSection.breakfast,
              dayOfWeek: d.weekday,
              parsedFoods: ['oatmeal', 'blueberries', 'honey'],
              finalSavedInput: 'Oatmeal with Blueberries & Honey',
            ),
          );

          dLog.add(
            MealSection.lunch,
            MealEntry(
              rawInput: 'Grilled Chicken Breast with Jasmine Rice',
              result: NutritionResult(
                canonicalMeal: 'Grilled Chicken Breast with Jasmine Rice',
                items: [],
                calories: NutrientRange(min: 680, max: 680),
                protein: NutrientRange(min: 52, max: 52),
                carbohydrates: NutrientRange(min: 65, max: 65),
                fat: NutrientRange(min: 14, max: 14),
                confidence: 1.0,
                warnings: [],
                source: 'test_fixture_multimeal',
                createdAt: lDate,
              ),
              addedAt: lDate,
              section: MealSection.lunch,
              dayOfWeek: d.weekday,
              parsedFoods: ['grilled chicken breast', 'jasmine rice'],
              finalSavedInput: 'Grilled Chicken Breast with Jasmine Rice',
            ),
          );

          dLog.add(
            MealSection.eveningSnack,
            MealEntry(
              rawInput: 'Salted Pretzels & Iced Latte',
              result: NutritionResult(
                canonicalMeal: 'Salted Pretzels & Iced Latte',
                items: [],
                calories: NutrientRange(min: 310, max: 310),
                protein: NutrientRange(min: 4, max: 4),
                carbohydrates: NutrientRange(min: 56, max: 56),
                fat: NutrientRange(min: 6, max: 6),
                confidence: 1.0,
                warnings: [],
                source: 'test_fixture_multimeal',
                createdAt: sDate,
              ),
              addedAt: sDate,
              section: MealSection.eveningSnack,
              dayOfWeek: d.weekday,
              parsedFoods: ['pretzels', 'latte'],
              finalSavedInput: 'Salted Pretzels & Iced Latte',
            ),
          );

          dLog.add(
            MealSection.dinner,
            MealEntry(
              rawInput: 'Vegetable Stir-Fry with Tofu',
              result: NutritionResult(
                canonicalMeal: 'Vegetable Stir-Fry with Tofu',
                items: [],
                calories: NutrientRange(min: 650, max: 650),
                protein: NutrientRange(min: 16, max: 16),
                carbohydrates: NutrientRange(min: 85, max: 85),
                fat: NutrientRange(min: 22, max: 22),
                confidence: 1.0,
                warnings: [],
                source: 'test_fixture_multimeal',
                createdAt: dinDate,
              ),
              addedAt: dinDate,
              section: MealSection.dinner,
              dayOfWeek: d.weekday,
              parsedFoods: ['tofu', 'vegetables', 'soy sauce', 'rice noodles'],
              finalSavedInput: 'Vegetable Stir-Fry with Tofu',
            ),
          );

          dLog.add(
            MealSection.lateNight,
            MealEntry(
              rawInput: 'Ben & Jerry\'s Half Baked Ice Cream',
              result: NutritionResult(
                canonicalMeal: 'Ben & Jerry\'s Half Baked Ice Cream',
                items: [],
                calories: NutrientRange(min: 540, max: 540),
                protein: NutrientRange(min: 6, max: 6),
                carbohydrates: NutrientRange(min: 66, max: 66),
                fat: NutrientRange(min: 28, max: 28),
                confidence: 1.0,
                warnings: [],
                source: 'test_fixture_multimeal',
                createdAt: lnDate,
              ),
              addedAt: lnDate,
              section: MealSection.lateNight,
              dayOfWeek: d.weekday,
              parsedFoods: ['ice cream', 'fudge', 'cookie dough'],
              finalSavedInput: 'Ben & Jerry\'s Half Baked Ice Cream',
            ),
          );
        } else {
          dLog.add(
            MealSection.lunch,
            MealEntry(
              rawInput: 'Chicken Rice Bowl',
              result: NutritionResult(
                canonicalMeal: 'Chicken Rice Bowl',
                items: [],
                calories: NutrientRange(min: 750, max: 750),
                protein: NutrientRange(min: 72, max: 72),
                confidence: 1.0,
                warnings: [],
                source: 'dev_seed',
                createdAt: d,
              ),
              addedAt: d,
              section: MealSection.lunch,
              dayOfWeek: d.weekday,
              parsedFoods: ['chicken', 'rice'],
              finalSavedInput: 'Chicken Rice Bowl',
            ),
          );
        }
        final dKey = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        dayLogStore[dKey] = dLog;
      }
      await PersistenceService.saveDayLogs();
    }
  }
}
