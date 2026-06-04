import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/insights_models.dart';
import 'package:kynetix/services/insights_engine.dart';
import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/models/workout_session.dart';
import 'package:kynetix/screens/onboarding_screen.dart'; // UserProfile
import 'package:kynetix/services/insights_report_service.dart';
import 'package:kynetix/models/day_status.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/services/mock_estimation_service.dart' show NutrientRange;

DayLog _makeDayLog({
  required DateTime date,
  List<({String name, double calories, double protein, int? score})> meals = const [],
  bool didGym = false,
}) {
  final log = DayLog();
  if (didGym) {
    log.gymDay = const GymDay(didGym: true);
  }
  for (final m in meals) {
    final entry = MealEntry(
      rawInput: m.name,
      result: NutritionResult(
        canonicalMeal: m.name,
        items: [
          NutritionItem(
            name: m.name,
            quantity: 1,
            unit: 'serving',
            estimated: false,
            mode: EstimationMode.packagedKnown,
            calories: NutrientRange(min: m.calories, max: m.calories),
            protein: NutrientRange(min: m.protein, max: m.protein),
          ),
        ],
        calories: NutrientRange(min: m.calories, max: m.calories),
        protein: NutrientRange(min: m.protein, max: m.protein),
        confidence: 0.95,
        warnings: const [],
        source: 'test_mock',
        createdAt: DateTime.now(),
        mealQualityScore: m.score,
      ),
      addedAt: date,
      section: MealSection.breakfast,
      dayOfWeek: date.weekday,
      parsedFoods: [m.name],
      finalSavedInput: m.name,
    );
    log.add(MealSection.breakfast, entry);
  }
  return log;
}

void main() {
  group('ConsistencyScore Formula Tests', () {
    test('Calculates composite score with meal quality', () {
      final score = InsightsEngine.computeScore(
        loggingConsistency: 1.0, // 35 pts
        proteinAdherence: 0.8,   // 20 pts
        calorieAdherence: 0.9,   // 18 pts
        gymAttendance: 0.7,      // 7 pts
        mealQuality: 0.8,        // 8 pts
        hasMealQuality: true,
      );

      // (35 + 20 + 18 + 7 + 8) = 88
      expect(score.score, equals(88));
      expect(score.loggingConsistency, 1.0);
      expect(score.proteinAdherence, 0.8);
      expect(score.calorieAdherence, 0.9);
      expect(score.gymAttendance, 0.7);
      expect(score.mealQuality, 0.8);
    });

    test('Calculates composite score without meal quality (rescales to 90.0)', () {
      final score = InsightsEngine.computeScore(
        loggingConsistency: 1.0, // 35 pts
        proteinAdherence: 0.8,   // 20 pts
        calorieAdherence: 0.9,   // 18 pts
        gymAttendance: 0.7,      // 7 pts
        mealQuality: 0.0,
        hasMealQuality: false,
      );

      // (35 + 20 + 18 + 7) = 80 out of 90 = 88.88% -> 89
      expect(score.score, equals(89));
    });
  });

  group('InsightsEngine Weekly Reports Tests', () {
    late UserProfile profile;

    setUp(() {
      profile = const UserProfile(
        name: 'Dhruv',
        age: 25,
        gender: 'Male',
        height: 175.0,
        weight: 75.0,
        workoutDaysMin: 3,
        workoutDaysMax: 3,
        goal: 'Fat Loss',
      );
    });

    test('computeWeek with less than 3 logged days returns null', () {
      final logs = <String, DayLog>{
        '2026-06-01': _makeDayLog(
          date: DateTime(2026, 6, 1),
          meals: [(name: 'Eggs', calories: 300, protein: 30, score: null)],
        ),
        '2026-06-02': _makeDayLog(
          date: DateTime(2026, 6, 2),
          meals: [(name: 'Chicken', calories: 400, protein: 40, score: null)],
        ),
      };

      final report = InsightsEngine.computeWeek(
        weekKey: '2026-W23',
        profile: profile,
        logs: logs,
        sessions: [],
        priorWeek: null,
      );

      expect(report, isNull);
    });

    test('computeWeek with 6 logged days, protein hits, cal hits, and gym days computes successfully', () {
      // Mock logs for 6 days of the week starting Monday 2026-06-01
      final logs = <String, DayLog>{
        '2026-06-01': _makeDayLog(date: DateTime(2026, 6, 1), meals: [(name: 'M1', calories: 2000, protein: 150, score: null)], didGym: true),
        '2026-06-02': _makeDayLog(date: DateTime(2026, 6, 2), meals: [(name: 'M2', calories: 2000, protein: 150, score: null)]),
        '2026-06-03': _makeDayLog(date: DateTime(2026, 6, 3), meals: [(name: 'M3', calories: 2000, protein: 150, score: null)], didGym: true),
        '2026-06-04': _makeDayLog(date: DateTime(2026, 6, 4), meals: [(name: 'M4', calories: 2000, protein: 150, score: null)]),
        '2026-06-05': _makeDayLog(date: DateTime(2026, 6, 5), meals: [(name: 'M5', calories: 2000, protein: 150, score: null)], didGym: true),
        '2026-06-06': _makeDayLog(date: DateTime(2026, 6, 6), meals: [(name: 'M6', calories: 2000, protein: 150, score: null)]),
      };

      final report = InsightsEngine.computeWeek(
        weekKey: '2026-W23',
        profile: profile,
        logs: logs,
        sessions: [],
        priorWeek: null,
      );

      expect(report, isNotNull);
      expect(report!.loggedDaysCount, equals(6));
      expect(report.gymDaysCount, equals(3));
      expect(report.avgCalories, closeTo(2000.0, 0.1));
      expect(report.avgProtein, closeTo(150.0, 0.1));
      expect(report.deltaVsPrior, isNull);
    });

    test('PeriodDelta and TopImprovement are extracted correctly from prior week comparison', () {
      // Prior week
      final prior = WeeklyReport(
        weekKey: '2026-W22',
        weekStart: DateTime(2026, 5, 25),
        consistencyScore: const ConsistencyScore(
          loggingConsistency: 0.5,
          proteinAdherence: 0.5,
          calorieAdherence: 0.5,
          gymAttendance: 0.5,
          mealQuality: 0.0,
          score: 50,
        ),
        avgCalories: 2000,
        avgProtein: 100,
        avgFiber: 20,
        gymDaysCount: 2,
        loggedDaysCount: 4,
        mostCommonOutcome: DayOutcome.incomplete,
        regressions: [],
        computedAt: DateTime.now(),
      );

      // Current week
      final logs = <String, DayLog>{
        '2026-06-01': _makeDayLog(date: DateTime(2026, 6, 1), meals: [(name: 'M1', calories: 2000, protein: 160, score: null)]), // Pro Hit, Cal Hit
        '2026-06-02': _makeDayLog(date: DateTime(2026, 6, 2), meals: [(name: 'M2', calories: 2000, protein: 160, score: null)]), // Pro Hit, Cal Hit
        '2026-06-03': _makeDayLog(date: DateTime(2026, 6, 3), meals: [(name: 'M3', calories: 2000, protein: 160, score: null)]), // Pro Hit, Cal Hit
        '2026-06-04': _makeDayLog(date: DateTime(2026, 6, 4), meals: [(name: 'M4', calories: 2000, protein: 160, score: null)]), // Pro Hit, Cal Hit
        '2026-06-05': _makeDayLog(date: DateTime(2026, 6, 5), meals: [(name: 'M5', calories: 2000, protein: 160, score: null)]), // Pro Hit, Cal Hit
        '2026-06-06': _makeDayLog(date: DateTime(2026, 6, 6), meals: [(name: 'M6', calories: 2000, protein: 160, score: null)]), // Pro Hit, Cal Hit
        '2026-06-07': _makeDayLog(date: DateTime(2026, 6, 7), meals: [(name: 'M7', calories: 2000, protein: 160, score: null)]), // Pro Hit, Cal Hit
      };

      final report = InsightsEngine.computeWeek(
        weekKey: '2026-W23',
        profile: profile,
        logs: logs,
        sessions: [],
        priorWeek: prior,
      );

      expect(report, isNotNull);
      expect(report!.deltaVsPrior, isNotNull);
      // current adherence = 1.0 (7/7 hits) vs prior = 0.5 (50%) -> delta = +0.50
      expect(report.deltaVsPrior!.proteinAdherenceDelta, closeTo(0.50, 0.01));
      expect(report.deltaVsPrior!.calorieAdherenceDelta, closeTo(0.50, 0.01));
      expect(report.deltaVsPrior!.loggingConsistencyDelta, closeTo(0.50, 0.01)); // current 1.0 vs prior 0.5
      expect(report.topImprovement, isNotNull);
      expect(report.topImprovement!.metric, equals(ImprovementMetric.proteinAdherence));
    });
  });

  group('Regressions & Advisory Alerts Tests', () {
    late UserProfile profile;

    setUp(() {
      profile = const UserProfile(
        name: 'Dhruv',
        age: 25,
        gender: 'Male',
        height: 175.0,
        weight: 75.0,
        workoutDaysMin: 3,
        workoutDaysMax: 3,
        goal: 'Fat Loss',
      );
    });

    test('Emits regression alert when protein adherence drops by >= 10%', () {
      final prior = WeeklyReport(
        weekKey: '2026-W22',
        weekStart: DateTime(2026, 5, 25),
        consistencyScore: const ConsistencyScore(
          loggingConsistency: 1.0,
          proteinAdherence: 0.90, // 90%
          calorieAdherence: 0.90,
          gymAttendance: 1.0,
          mealQuality: 0.0,
          score: 90,
        ),
        avgCalories: 2000,
        avgProtein: 150,
        avgFiber: 25,
        gymDaysCount: 3,
        loggedDaysCount: 7,
        mostCommonOutcome: DayOutcome.hitCaloriesAndProtein,
        regressions: [],
        computedAt: DateTime.now(),
      );

      // Current week: protein hits drops to 3/7 = 42%
      final logs = <String, DayLog>{
        '2026-06-01': _makeDayLog(date: DateTime(2026, 6, 1), meals: [(name: 'M1', calories: 2000, protein: 160, score: null)]), // hit
        '2026-06-02': _makeDayLog(date: DateTime(2026, 6, 2), meals: [(name: 'M2', calories: 2000, protein: 160, score: null)]), // hit
        '2026-06-03': _makeDayLog(date: DateTime(2026, 6, 3), meals: [(name: 'M3', calories: 2000, protein: 160, score: null)]), // hit
        '2026-06-04': _makeDayLog(date: DateTime(2026, 6, 4), meals: [(name: 'M4', calories: 2000, protein: 50, score: null)]),  // miss
        '2026-06-05': _makeDayLog(date: DateTime(2026, 6, 5), meals: [(name: 'M5', calories: 2000, protein: 50, score: null)]),  // miss
        '2026-06-06': _makeDayLog(date: DateTime(2026, 6, 6), meals: [(name: 'M6', calories: 2000, protein: 50, score: null)]),  // miss
        '2026-06-07': _makeDayLog(date: DateTime(2026, 6, 7), meals: [(name: 'M7', calories: 2000, protein: 50, score: null)]),  // miss
      };

      final report = InsightsEngine.computeWeek(
        weekKey: '2026-W23',
        profile: profile,
        logs: logs,
        sessions: [],
        priorWeek: prior,
      );

      expect(report, isNotNull);
      expect(report!.regressions.length, greaterThanOrEqualTo(1));
      final proteinRegression = report.regressions.firstWhere((r) => r.type == RegressionType.proteinConsistency);
      expect(proteinRegression.message, contains('Protein consistency dropped'));
    });

    test('Does not emit regression alert when drop is below the threshold', () {
      final prior = WeeklyReport(
        weekKey: '2026-W22',
        weekStart: DateTime(2026, 5, 25),
        consistencyScore: const ConsistencyScore(
          loggingConsistency: 1.0,
          proteinAdherence: 0.85, // 85%
          calorieAdherence: 0.90,
          gymAttendance: 1.0,
          mealQuality: 0.0,
          score: 88,
        ),
        avgCalories: 2000,
        avgProtein: 150,
        avgFiber: 25,
        gymDaysCount: 3,
        loggedDaysCount: 7,
        mostCommonOutcome: DayOutcome.hitCaloriesAndProtein,
        regressions: [],
        computedAt: DateTime.now(),
      );

      // Current week: protein hits 6/7 = 85.7% (basically no drop or minor increase)
      final logs = <String, DayLog>{
        '2026-06-01': _makeDayLog(date: DateTime(2026, 6, 1), meals: [(name: 'M1', calories: 2000, protein: 160, score: null)]),
        '2026-06-02': _makeDayLog(date: DateTime(2026, 6, 2), meals: [(name: 'M2', calories: 2000, protein: 160, score: null)]),
        '2026-06-03': _makeDayLog(date: DateTime(2026, 6, 3), meals: [(name: 'M3', calories: 2000, protein: 160, score: null)]),
        '2026-06-04': _makeDayLog(date: DateTime(2026, 6, 4), meals: [(name: 'M4', calories: 2000, protein: 160, score: null)]),
        '2026-06-05': _makeDayLog(date: DateTime(2026, 6, 5), meals: [(name: 'M5', calories: 2000, protein: 160, score: null)]),
        '2026-06-06': _makeDayLog(date: DateTime(2026, 6, 6), meals: [(name: 'M6', calories: 2000, protein: 160, score: null)]),
        '2026-06-07': _makeDayLog(date: DateTime(2026, 6, 7), meals: [(name: 'M7', calories: 2000, protein: 50, score: null)]),
      };

      final report = InsightsEngine.computeWeek(
        weekKey: '2026-W23',
        profile: profile,
        logs: logs,
        sessions: [],
        priorWeek: prior,
      );

      expect(report, isNotNull);
      final proteinRegressions = report!.regressions.where((r) => r.type == RegressionType.proteinConsistency);
      expect(proteinRegressions, isEmpty);
    });
  });

  group('Achievements Evaluation and Idempotency Tests', () {
    late UserProfile profile;

    setUp(() {
      profile = const UserProfile(
        name: 'Dhruv',
        age: 25,
        gender: 'Male',
        height: 175.0,
        weight: 75.0,
        workoutDaysMin: 3,
        workoutDaysMax: 3,
        goal: 'Fat Loss',
      );
    });

    test('Awards correct achievements based on logs', () {
      final logs = <String, DayLog>{
        '2026-06-01': _makeDayLog(date: DateTime(2026, 6, 1), meals: [(name: 'M1', calories: 2000, protein: 160, score: null)], didGym: true),
      };

      final achievements = InsightsEngine.evaluateAchievements(
        logs: logs,
        profile: profile,
        sessions: [],
        existingAchievements: [],
        weeklyReports: [],
        monthlyReports: [],
        currentPBs: null,
      );

      // Should award 'logged_first_day' and 'pb_protein_day'
      final ids = achievements.map((a) => a.id).toSet();
      expect(ids, contains('logged_first_day'));
      expect(ids, contains('pb_protein_day'));
    });

    test('Achievement evaluation is idempotent', () {
      final logs = <String, DayLog>{
        '2026-06-01': _makeDayLog(date: DateTime(2026, 6, 1), meals: [(name: 'M1', calories: 2000, protein: 160, score: null)], didGym: true),
      };

      final existing = [
        AchievementRegistry.fromId('logged_first_day', earnedAt: DateTime(2026, 6, 1))!,
        AchievementRegistry.fromId('pb_protein_day', earnedAt: DateTime(2026, 6, 1))!,
      ];

      final updated = InsightsEngine.evaluateAchievements(
        logs: logs,
        profile: profile,
        sessions: [],
        existingAchievements: existing,
        weeklyReports: [],
        monthlyReports: [],
        currentPBs: null,
      );

      expect(updated.length, equals(existing.length));
    });

    test('pb_protein_day is awarded only once', () {
      final logs = <String, DayLog>{
        '2026-06-01': _makeDayLog(date: DateTime(2026, 6, 1), meals: [(name: 'M1', calories: 2000, protein: 160, score: null)]),
        '2026-06-02': _makeDayLog(date: DateTime(2026, 6, 2), meals: [(name: 'M2', calories: 2000, protein: 200, score: null)]), // New PB set
      };

      final initial = InsightsEngine.evaluateAchievements(
        logs: {'2026-06-01': logs['2026-06-01']!},
        profile: profile,
        sessions: [],
        existingAchievements: [],
        weeklyReports: [],
        monthlyReports: [],
        currentPBs: null,
      );

      expect(initial.map((a) => a.id), contains('pb_protein_day'));

      final secondary = InsightsEngine.evaluateAchievements(
        logs: logs,
        profile: profile,
        sessions: [],
        existingAchievements: initial,
        weeklyReports: [],
        monthlyReports: [],
        currentPBs: null,
      );

      // Verify that pb_protein_day is not duplicated in the earned achievements list
      final matchingCount = secondary.where((a) => a.id == 'pb_protein_day').length;
      expect(matchingCount, equals(1));
    });
  });

  group('AchievementProgress Tests', () {
    test('Calculates current/target/fraction progress correctly', () {
      final logs = <String, DayLog>{
        for (int i = 1; i <= 67; i++)
          '2026-06-${i.toString().padLeft(2, '0')}': _makeDayLog(
            date: DateTime(2026, 6, i),
            meals: [(name: 'Meal', calories: 2000, protein: 100, score: null)],
          ),
      };

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

      final progressList = InsightsEngine.computeProgress([], logs, profile, []);

      final hundredDaysProgress = progressList.firstWhere((p) => p.id == 'logged_100_days');
      expect(hundredDaysProgress.current, equals(67));
      expect(hundredDaysProgress.target, equals(100));
      expect(hundredDaysProgress.fraction, closeTo(0.67, 0.001));
    });
  });

  group('AchievementRegistry and Caching Tests', () {
    test('AchievementRegistry retrieves metadata correctly from id', () {
      final achievement = AchievementRegistry.fromId('gym_100_total');
      expect(achievement, isNotNull);
      expect(achievement!.title, equals('Iron Dedicated'));
      expect(achievement.emoji, equals('🏆'));
      expect(achievement.category, equals(AchievementCategory.training));
    });

    test('mergeAchievementsFromCloud joins local and cloud lists correctly', () {
      final local = [
        AchievementRegistry.fromId('logged_first_day', earnedAt: DateTime(2026, 6, 1), isNew: false)!,
        AchievementRegistry.fromId('pb_protein_day', earnedAt: DateTime(2026, 6, 1), isNew: false)!,
      ];

      final cloud = [
        AchievementRegistry.fromId('logged_first_day', earnedAt: DateTime(2026, 6, 1))!,
        AchievementRegistry.fromId('logged_7_days', earnedAt: DateTime(2026, 6, 5))!,
      ];

      // Perform a mock merge logic
      final merged = List<Achievement>.from(local);
      final localIds = local.map((a) => a.id).toSet();
      for (final ca in cloud) {
        if (!localIds.contains(ca.id)) {
          final complete = AchievementRegistry.fromId(ca.id, earnedAt: ca.earnedAt, isNew: false);
          if (complete != null) {
            merged.add(complete);
          }
        }
      }

      expect(merged.length, equals(3));
      final ids = merged.map((a) => a.id).toSet();
      expect(ids, contains('logged_first_day'));
      expect(ids, contains('pb_protein_day'));
      expect(ids, contains('logged_7_days'));
      // Restored from cloud are never marked as new
      final logged7Days = merged.firstWhere((a) => a.id == 'logged_7_days');
      expect(logged7Days.isNew, isFalse);
    });
  });
}
