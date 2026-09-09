import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/models/user_profile.dart';
import 'package:kynetix/models/workout_session.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/services/mock_estimation_service.dart' show NutrientRange;
import 'package:kynetix/services/workout_service.dart';
import 'package:kynetix/services/profile_service.dart';
import 'package:kynetix/services/user_session_coordinator.dart';
import 'package:kynetix/services/kyno_coaching_insight_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await UserSessionCoordinator.instance.clearAllUserServices();
  });

  tearDown(() async {
    await UserSessionCoordinator.instance.clearAllUserServices();
  });

  const benchPress = Exercise(
    id: 'bench_press',
    name: 'Barbell Bench Press',
    muscleGroup: 'Chest',
    type: ExerciseType.barbellCompound,
    defaultTargetSets: 3,
    defaultRepMin: 6,
    defaultRepMax: 8,
  );

  WorkoutSession _createBenchSession(DateTime date, double weight, int reps) {
    return WorkoutSession(
      id: 'session_${date.millisecondsSinceEpoch}',
      date: date,
      splitDayName: 'Chest Day',
      durationMinutes: 45,
      entries: [
        ExerciseEntry(
          exercise: benchPress,
          sets: [
            SetEntry(weight: weight, reps: reps, setType: SetType.normal),
            SetEntry(weight: weight, reps: reps, setType: SetType.normal),
          ],
        ),
      ],
    );
  }

  void _populateNutrition(int daysCount, double avgProtein, double avgCalories, {double targetProtein = 140.0}) {
    final now = DateTime.now();
    for (int i = 1; i <= daysCount; i++) {
      final date = now.subtract(Duration(days: i));
      final dateKey = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final log = DayLog()
        ..gymDay = GymDay(didGym: i % 2 == 0)
        ..targetProtein = targetProtein
        ..targetCalories = 2200.0;
      final entry = MealEntry(
        rawInput: 'meal',
        result: NutritionResult(
          canonicalMeal: 'Meal',
          items: [],
          calories: NutrientRange(min: avgCalories, max: avgCalories),
          protein: NutrientRange(min: avgProtein, max: avgProtein),
          confidence: 1.0,
          warnings: [],
          source: 'test',
          createdAt: date,
        ),
        addedAt: date,
        section: MealSection.lunch,
        dayOfWeek: date.weekday,
        parsedFoods: ['meal'],
        finalSavedInput: 'Meal',
      );
      log.add(MealSection.lunch, entry);
      dayLogStore[dateKey] = log;
    }
  }

  group('Kyno Coaching Insights Engine Tests', () {
    test('1. Low protein adherence triggers needsAttention coaching card', () async {
      ProfileService.instance.currentUserProfile = const UserProfile(
        name: 'Dhruv',
        age: 25,
        gender: 'male',
        height: 175,
        weight: 70,
        workoutDaysMin: 3,
        workoutDaysMax: 4,
        goal: 'Strength & Hypertrophy',
      );

      // 14 days of low protein (60g vs 140g target)
      _populateNutrition(14, 60.0, 1800.0, targetProtein: 140.0);

      final insights = KynoCoachingInsightService.instance.evaluateInsightsForCurrentUser();

      expect(insights.any((i) => i.severity == KynoInsightSeverity.needsAttention && i.title.contains('Protein')), isTrue);
      final proCard = insights.firstWhere((i) => i.title.contains('Protein'));
      expect(proCard.evidence, contains('60g'));
      expect(proCard.recommendation, contains('protein'));
    });

    test('2. Exercise plateau triggers coaching card', () async {
      final now = DateTime.now();
      ProfileService.instance.currentUserProfile = const UserProfile(
        name: 'Dhruv',
        age: 25,
        gender: 'male',
        height: 175,
        weight: 70,
        workoutDaysMin: 3,
        workoutDaysMax: 4,
        goal: 'Strength',
      );

      // 3 consecutive sessions at 80kg x 6
      final s1 = _createBenchSession(now.subtract(const Duration(days: 8)), 80.0, 6);
      final s2 = _createBenchSession(now.subtract(const Duration(days: 5)), 80.0, 6);
      final s3 = _createBenchSession(now.subtract(const Duration(days: 1)), 80.0, 6);
      for (final s in [s1, s2, s3]) {
        await WorkoutService.instance.saveSession(s);
      }

      final insights = KynoCoachingInsightService.instance.evaluateInsightsForCurrentUser();

      expect(insights.any((i) => i.severity == KynoInsightSeverity.coaching && i.title.contains('Bench Press Plateau')), isTrue);
      final card = insights.firstWhere((i) => i.title.contains('Bench Press Plateau'));
      expect(card.explanation.toLowerCase(), contains('progressive overload'));
    });

    test('3. Strength progression triggers progress card', () async {
      final now = DateTime.now();
      ProfileService.instance.currentUserProfile = const UserProfile(
        name: 'Dhruv',
        age: 25,
        gender: 'male',
        height: 175,
        weight: 70,
        workoutDaysMin: 3,
        workoutDaysMax: 4,
        goal: 'Strength',
      );

      // 3 consecutive sessions progressing: 70kg -> 75kg -> 80kg
      final s1 = _createBenchSession(now.subtract(const Duration(days: 8)), 70.0, 6);
      final s2 = _createBenchSession(now.subtract(const Duration(days: 5)), 75.0, 6);
      final s3 = _createBenchSession(now.subtract(const Duration(days: 1)), 80.0, 6);
      for (final s in [s1, s2, s3]) {
        await WorkoutService.instance.saveSession(s);
      }

      final insights = KynoCoachingInsightService.instance.evaluateInsightsForCurrentUser();

      expect(insights.any((i) => i.severity == KynoInsightSeverity.progress && i.title.contains('Bench Press Progressive Overload')), isTrue);
    });

    test('4. Duplicate suppression during 24h cooldown', () async {
      ProfileService.instance.currentUserProfile = const UserProfile(
        name: 'Dhruv',
        age: 25,
        gender: 'male',
        height: 175,
        weight: 70,
        workoutDaysMin: 3,
        workoutDaysMax: 4,
        goal: 'Strength',
      );
      _populateNutrition(14, 50.0, 1800.0, targetProtein: 140.0);

      // First evaluation produces 1 insight
      final firstRun = KynoCoachingInsightService.instance.evaluateInsightsForCurrentUser();
      expect(firstRun.length, 1);

      // Second immediate evaluation does not generate duplicates
      final secondRun = KynoCoachingInsightService.instance.evaluateInsightsForCurrentUser();
      expect(secondRun.length, 1);
      expect(secondRun.first.id, firstRun.first.id);
    });

    test('5. Dismissing an insight removes it from active list', () async {
      ProfileService.instance.currentUserProfile = const UserProfile(
        name: 'Dhruv',
        age: 25,
        gender: 'male',
        height: 175,
        weight: 70,
        workoutDaysMin: 3,
        workoutDaysMax: 4,
        goal: 'Strength',
      );
      _populateNutrition(14, 50.0, 1800.0, targetProtein: 140.0);

      final activeBefore = KynoCoachingInsightService.instance.getActiveInsights(forceEvaluate: true);
      expect(activeBefore.length, 1);

      KynoCoachingInsightService.instance.dismissInsight(activeBefore.first.id);

      final activeAfter = KynoCoachingInsightService.instance.getActiveInsights();
      expect(activeAfter.isEmpty, isTrue);
    });

    test('6. UserSessionCoordinator.clearAllUserServices() flushes all insights (User Isolation)', () async {
      ProfileService.instance.currentUserProfile = const UserProfile(
        name: 'Dhruv',
        age: 25,
        gender: 'male',
        height: 175,
        weight: 70,
        workoutDaysMin: 3,
        workoutDaysMax: 4,
        goal: 'Strength',
      );
      _populateNutrition(14, 50.0, 1800.0, targetProtein: 140.0);

      final active = KynoCoachingInsightService.instance.evaluateInsightsForCurrentUser();
      expect(active.isNotEmpty, isTrue);

      // Logout / flush
      await UserSessionCoordinator.instance.clearAllUserServices();

      // Ensure active insights are empty
      expect(KynoCoachingInsightService.instance.getActiveInsights().isEmpty, isTrue);
    });
  });
}
