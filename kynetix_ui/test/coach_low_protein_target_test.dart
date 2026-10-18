import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/models/user_profile.dart';
import 'package:kynetix/services/coach_service.dart';
import 'package:kynetix/services/mock_estimation_service.dart';
import 'package:kynetix/services/nutrition_target_engine.dart';

/// Regression: a protein target under ~80 g made the protein plan's clamp()
/// bounds invert (lower > upper), which threw and broke the day screen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  DayLog logWith(double kcal, double protein) {
    final log = DayLog();
    log.add(
      MealSection.breakfast,
      MealEntry(
        rawInput: 'dal rice',
        finalSavedInput: 'dal rice',
        section: MealSection.breakfast,
        addedAt: DateTime(2026, 10, 17, 9),
        dayOfWeek: 6,
        parsedFoods: const ['dal rice'],
        result: NutritionResult(
          canonicalMeal: 'dal rice',
          items: const [],
          calories: NutrientRange(min: kcal, max: kcal),
          protein: NutrientRange(min: protein, max: protein),
          confidence: 0.9,
          warnings: const [],
          source: 'test',
          createdAt: DateTime(2026, 10, 17),
        ),
      ),
    );
    return log;
  }

  for (final targetProtein in [40.0, 55.0, 70.0, 79.0]) {
    test('protein target ${targetProtein.round()} g does not throw', () {
      const profile = UserProfile(
        name: 'Test', age: 30, gender: 'male', height: 175, weight: 70,
        goal: 'Fat Loss', workoutDaysMin: 3, workoutDaysMax: 4,
      );
      final target = DayTarget(
        calories: 1800,
        protein: targetProtein,
        isTrainingDay: true,
        label: 'Training Day',
        note: 'test',
      );
      expect(
        () => CoachService.instance.insightsForDay(
          logWith(500, 12),
          target,
          profile: profile,
          now: DateTime(2026, 10, 17, 13),
        ),
        returnsNormally,
      );
    });
  }
}
