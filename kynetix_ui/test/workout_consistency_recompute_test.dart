// Regression tests for workout consistency calculation.
//
// Root cause fixed: InsightsEngine.computeWeek / computeMonth / evaluateAchievements /
// computeProgress all gated gym-day counting behind `log.isEmpty`, so any day where
// the user set Gym=Yes but logged no meals was silently excluded from gymDaysCount.
//
// Fix: gym-day determination now runs BEFORE the meal-log guard using the unified rule:
//   isGymDay = (log?.gymDay?.didGym == true) || (session != null && !session.isEmpty)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/models/workout_session.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/services/insights_engine.dart';
import 'package:kynetix/screens/onboarding_screen.dart'; // UserProfile
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/services/mock_estimation_service.dart' show NutrientRange;
import 'package:kynetix/screens/insights_screen.dart';
import 'package:kynetix/services/insights_report_service.dart';
import 'package:kynetix/services/persistence_service.dart';
import 'package:kynetix/services/workout_service.dart';
import 'package:kynetix/services/profile_service.dart';
import 'package:kynetix/services/nutrition_hydration_guard.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

UserProfile _defaultProfile({int gymDaysMin = 4, int gymDaysMax = 5}) =>
    UserProfile(
      name: 'Test User',
      age: 25,
      gender: 'Male',
      height: 175.0,
      weight: 75.0,
      workoutDaysMin: gymDaysMin,
      workoutDaysMax: gymDaysMax,
      goal: 'Fat Loss',
    );

/// Creates a DayLog with optional meal entries and gym toggle.
DayLog _makeLog({
  required DateTime date,
  bool didGym = false,
  bool withMeals = true,
}) {
  final log = DayLog();
  if (didGym) {
    log.gymDay = const GymDay(didGym: true);
  }
  if (withMeals) {
    // Add a single generic meal so the log is non-empty for nutrition tracking.
    log.add(
      MealSection.breakfast,
      MealEntry(
        rawInput: 'Eggs',
        result: NutritionResult(
          canonicalMeal: 'Eggs',
          items: [
            NutritionItem(
              name: 'Eggs',
              quantity: 1,
              unit: 'serving',
              estimated: false,
              mode: EstimationMode.packagedKnown,
              calories: NutrientRange(min: 300, max: 300),
              protein: NutrientRange(min: 25, max: 25),
            ),
          ],
          calories: NutrientRange(min: 300, max: 300),
          protein: NutrientRange(min: 25, max: 25),
          confidence: 0.95,
          warnings: const [],
          source: 'test',
          createdAt: date,
        ),
        addedAt: date,
        section: MealSection.breakfast,
        dayOfWeek: date.weekday,
        parsedFoods: const ['Eggs'],
        finalSavedInput: 'Eggs',
      ),
    );
  }
  return log;
}

/// Creates a minimal completed WorkoutSession for a given date.
WorkoutSession _makeSession(DateTime date) => WorkoutSession(
      id: 'session-${date.toIso8601String()}',
      date: date,
      splitDayName: 'Push',
      entries: [
        ExerciseEntry(
          exercise: const Exercise(
            id: 'bench-press',
            name: 'Bench Press',
            muscleGroup: 'Chest',
            type: ExerciseType.barbellCompound,
          ),
          sets: [
            const SetEntry(weight: 80, reps: 8),
          ],
        ),
      ],
      status: WorkoutStatus.completed,
    );

// ─── computeWeek regression tests ─────────────────────────────────────────────

void main() {
  group('Workout Consistency — computeWeek gym-day counting', () {
    // Week of 2026-06-01 (Monday) to 2026-06-07 (Sunday) = ISO week 23.
    const weekKey = '2026-W23';

    test(
        'Gym-only day (Gym=Yes, no meals) is counted in gymDaysCount '
        '[regression: was silently skipped]', () {
      final monday = DateTime(2026, 6, 1);

      // Monday: Gym=Yes, NO meals → previously caused the day to be skipped.
      // Tue–Thu: meals logged (enough to reach the 3-day minimum for a report).
      final logs = <String, DayLog>{
        '2026-06-01': _makeLog(date: monday, didGym: true, withMeals: false),
        '2026-06-03': _makeLog(date: DateTime(2026, 6, 3), withMeals: true),
        '2026-06-04': _makeLog(date: DateTime(2026, 6, 4), withMeals: true),
        '2026-06-05': _makeLog(date: DateTime(2026, 6, 5), withMeals: true),
      };

      final report = InsightsEngine.computeWeek(
        weekKey: weekKey,
        profile: _defaultProfile(),
        logs: logs,
        sessions: [],
        priorWeek: null,
      );

      expect(report, isNotNull, reason: 'Enough logged days for a weekly report');
      // Monday must be counted as a gym day even though no meals were logged.
      expect(report!.gymDaysCount, equals(1),
          reason: 'Gym=Yes day with no meals should still count');
    });

    test(
        'Gym day logged via meal toggle AND a gym-only day both count correctly', () {
      final logs = <String, DayLog>{
        // Tuesday: Gym=Yes WITH meals
        '2026-06-02': _makeLog(date: DateTime(2026, 6, 2), didGym: true, withMeals: true),
        // Wednesday: Gym=Yes but NO meals (the bug scenario)
        '2026-06-03': _makeLog(date: DateTime(2026, 6, 3), didGym: true, withMeals: false),
        // Thursday, Friday: just meals, no gym
        '2026-06-04': _makeLog(date: DateTime(2026, 6, 4), withMeals: true),
        '2026-06-05': _makeLog(date: DateTime(2026, 6, 5), withMeals: true),
      };

      final report = InsightsEngine.computeWeek(
        weekKey: weekKey,
        profile: _defaultProfile(),
        logs: logs,
        sessions: [],
        priorWeek: null,
      );

      expect(report, isNotNull);
      // Both Tue (with meals) and Wed (no meals) should be counted.
      expect(report!.gymDaysCount, equals(2));
      // loggedDaysCount should only include days with meals (3: Tue, Thu, Fri).
      expect(report.loggedDaysCount, equals(3));
    });

    test(
        'Completed workout session on a day with no meals counts as gym day '
        'even without meal-log gym toggle', () {
      final friday = DateTime(2026, 6, 5);

      final logs = <String, DayLog>{
        '2026-06-02': _makeLog(date: DateTime(2026, 6, 2), withMeals: true),
        '2026-06-03': _makeLog(date: DateTime(2026, 6, 3), withMeals: true),
        '2026-06-04': _makeLog(date: DateTime(2026, 6, 4), withMeals: true),
        // Friday: NO meals, NO gym toggle — but has a WorkoutSession.
        // (No entry in logs map at all.)
      };

      final report = InsightsEngine.computeWeek(
        weekKey: weekKey,
        profile: _defaultProfile(),
        logs: logs,
        sessions: [_makeSession(friday)],
        priorWeek: null,
      );

      expect(report, isNotNull);
      expect(report!.gymDaysCount, equals(1),
          reason: 'Completed workout session should count as gym day');
    });

    test('Empty gym day does NOT inflate gymDaysCount', () {
      // Gym=Yes on Monday + three ordinary meal days.
      final logs = <String, DayLog>{
        // Monday: Gym=Yes, with meals
        '2026-06-01': _makeLog(date: DateTime(2026, 6, 1), didGym: false, withMeals: true),
        '2026-06-02': _makeLog(date: DateTime(2026, 6, 2), withMeals: true),
        '2026-06-03': _makeLog(date: DateTime(2026, 6, 3), withMeals: true),
        '2026-06-04': _makeLog(date: DateTime(2026, 6, 4), withMeals: true),
      };

      final report = InsightsEngine.computeWeek(
        weekKey: weekKey,
        profile: _defaultProfile(),
        logs: logs,
        sessions: [],
        priorWeek: null,
      );

      expect(report, isNotNull);
      expect(report!.gymDaysCount, equals(0));
    });
  });

  // ─── computeMonth regression tests ──────────────────────────────────────────

  group('Workout Consistency — computeMonth gym-day counting', () {
    test(
        'Gym-only days (Gym=Yes, no meals) are counted in totalGymDays '
        '[regression: was silently skipped]', () {
      final profile = _defaultProfile(gymDaysMin: 4, gymDaysMax: 5);

      // Build June 2026: 14 days with meals, 2 gym-only days (no meals).
      final logs = <String, DayLog>{};
      for (int day = 1; day <= 14; day++) {
        logs['2026-06-${day.toString().padLeft(2, '0')}'] =
            _makeLog(date: DateTime(2026, 6, day), withMeals: true);
      }
      // June 15 and 16: gym=yes, NO meals — previously skipped.
      logs['2026-06-15'] =
          _makeLog(date: DateTime(2026, 6, 15), didGym: true, withMeals: false);
      logs['2026-06-16'] =
          _makeLog(date: DateTime(2026, 6, 16), didGym: true, withMeals: false);

      final report = InsightsEngine.computeMonth(
        monthKey: '2026-06',
        profile: profile,
        logs: logs,
        sessions: [],
        priorMonth: null,
      );

      expect(report, isNotNull);
      expect(report!.totalGymDays, equals(2),
          reason: 'Gym-only days must be counted in monthly gym total');
    });
  });

  // ─── evaluateAchievements regression tests ───────────────────────────────────

  group('Workout Consistency — evaluateAchievements gym-day counting', () {
    test(
        'Gym-only days count toward the gym_30_total achievement '
        '[regression: was silently skipped]', () {
      final profile = _defaultProfile();

      // 29 days: meals + gym. 1 day: gym only (no meals).
      final logs = <String, DayLog>{};
      for (int i = 1; i <= 29; i++) {
        logs['2026-01-${i.toString().padLeft(2, '0')}'] = _makeLog(
          date: DateTime(2026, 1, i),
          didGym: true,
          withMeals: true,
        );
      }
      // Day 30: gym=yes, NO meals. Must still trigger the achievement.
      logs['2026-01-30'] =
          _makeLog(date: DateTime(2026, 1, 30), didGym: true, withMeals: false);

      final achievements = InsightsEngine.evaluateAchievements(
        logs: logs,
        profile: profile,
        sessions: [],
        existingAchievements: [],
        weeklyReports: [],
        monthlyReports: [],
        currentPBs: null,
      );

      final ids = achievements.map((a) => a.id).toSet();
      expect(ids, contains('gym_30_total'),
          reason:
              'gym_30_total should be awarded when the 30th gym day has no meals');
    });
  });

  // ─── computeProgress regression tests ────────────────────────────────────────

  group('Workout Consistency — computeProgress gym-day counting', () {
    test(
        'Gym-only days count toward gym progress tracker '
        '[regression: was silently skipped]', () {
      final profile = _defaultProfile();

      final logs = <String, DayLog>{
        // 10 days with meals + gym
        for (int i = 1; i <= 10; i++)
          '2026-02-${i.toString().padLeft(2, '0')}': _makeLog(
            date: DateTime(2026, 2, i),
            didGym: true,
            withMeals: true,
          ),
        // Day 11: gym=yes, NO meals — should still count.
        '2026-02-11': _makeLog(
            date: DateTime(2026, 2, 11), didGym: true, withMeals: false),
      };

      final progress = InsightsEngine.computeProgress([], logs, profile, []);

      final gym30 = progress.firstWhere((p) => p.id == 'gym_30_total');
      expect(gym30.current, equals(11),
          reason:
              'Gym-only day must contribute to the gym_30_total progress tracker');
    });
  });

  // ─── Exact user scenario regression ──────────────────────────────────────────

  group('Exact user scenario — June 2026 W23', () {
    // User scenario:
    //   Mon Jun 1: went to gym, no meal log     → should show ✅
    //   Tue Jun 2: gym + meals                  → ✅
    //   Wed Jun 3: gym + meals                  → ✅
    //   Thu Jun 4: rest                         → ❌
    //   Fri Jun 5: Gym=Yes, meals logged         → ✅ (was incorrectly ❌)
    //   Sat Jun 6: gym + meals                  → ✅
    //   Sun Jun 7: rest                         → ❌
    test('gymDaysCount reflects user scenario correctly', () {
      final logs = <String, DayLog>{
        // Mon: gym-only (no meals)
        '2026-06-01': _makeLog(
            date: DateTime(2026, 6, 1), didGym: true, withMeals: false),
        // Tue: gym + meals
        '2026-06-02': _makeLog(
            date: DateTime(2026, 6, 2), didGym: true, withMeals: true),
        // Wed: gym + meals
        '2026-06-03': _makeLog(
            date: DateTime(2026, 6, 3), didGym: true, withMeals: true),
        // Thu: meals, no gym
        '2026-06-04': _makeLog(
            date: DateTime(2026, 6, 4), didGym: false, withMeals: true),
        // Fri: Gym=Yes, meals logged (the bug day — was ❌)
        '2026-06-05': _makeLog(
            date: DateTime(2026, 6, 5), didGym: true, withMeals: true),
        // Sat: gym + meals
        '2026-06-06': _makeLog(
            date: DateTime(2026, 6, 6), didGym: true, withMeals: true),
        // Sun: meals, no gym
        '2026-06-07': _makeLog(
            date: DateTime(2026, 6, 7), didGym: false, withMeals: true),
      };

      final report = InsightsEngine.computeWeek(
        weekKey: '2026-W23',
        profile: _defaultProfile(),
        logs: logs,
        sessions: [],
        priorWeek: null,
      );

      expect(report, isNotNull);
      // Mon, Tue, Wed, Fri, Sat = 5 gym days.
      expect(report!.gymDaysCount, equals(5));
      // loggedDaysCount = days with meals = Tue–Sun = 6.
      expect(report.loggedDaysCount, equals(6));
    });

    test(
        'Friday June 5 with Gym=Yes and meals is counted as gym day '
        '[regression: was shown as ❌ in the UI]', () {
      final friday = DateTime(2026, 6, 5);
      final fridayLog = DayLog();
      fridayLog.gymDay = const GymDay(didGym: true);
      // Add a meal so the log is non-empty.
      fridayLog.add(
        MealSection.lunch,
        MealEntry(
          rawInput: 'Chicken Rice',
          result: NutritionResult(
            canonicalMeal: 'Chicken Rice',
            items: [
              NutritionItem(
                name: 'Chicken Rice',
                quantity: 1,
                unit: 'bowl',
                estimated: false,
                mode: EstimationMode.packagedKnown,
                calories: NutrientRange(min: 600, max: 600),
                protein: NutrientRange(min: 45, max: 45),
              ),
            ],
            calories: NutrientRange(min: 600, max: 600),
            protein: NutrientRange(min: 45, max: 45),
            confidence: 0.95,
            warnings: const [],
            source: 'test',
            createdAt: friday,
          ),
          addedAt: friday,
          section: MealSection.lunch,
          dayOfWeek: friday.weekday,
          parsedFoods: const ['Chicken Rice'],
          finalSavedInput: 'Chicken Rice',
        ),
      );

      // Verify gymDay is persisted correctly on the log model.
      expect(fridayLog.gymDay?.didGym, isTrue,
          reason: 'Friday gym toggle must be set on the log');
      expect(fridayLog.isEmpty, isFalse,
          reason: 'Friday log must not be empty (meal was added)');

      // Now run computeWeek including Friday.
      final logs = <String, DayLog>{
        '2026-06-03': _makeLog(date: DateTime(2026, 6, 3), withMeals: true),
        '2026-06-04': _makeLog(date: DateTime(2026, 6, 4), withMeals: true),
        '2026-06-05': fridayLog,
        '2026-06-06': _makeLog(date: DateTime(2026, 6, 6), withMeals: true),
      };

      final report = InsightsEngine.computeWeek(
        weekKey: '2026-W23',
        profile: _defaultProfile(),
        logs: logs,
        sessions: [],
        priorWeek: null,
      );

      expect(report, isNotNull);
      expect(report!.gymDaysCount, equals(1),
          reason: 'Friday (Gym=Yes + meal) must be counted as a gym day');
    });
  });

  group('Insights Screen UI Regression - Stale Data', () {
    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      try {
        await Supabase.initialize(
          url: 'https://mock.supabase.co',
          anonKey: 'mock-anon-key',
        );
      } catch (_) {}
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await PersistenceService.reset();
      await WorkoutService.instance.clearAll();
      WorkoutService.instance.resetReadyForTesting();
      await WorkoutService.instance.init();
      
      NutritionHydrationGuard.instance.reset();
      NutritionHydrationGuard.instance.currentUserIdOverride = 'test-user-id';
      NutritionHydrationGuard.instance.markComplete('test-user-id');
      
      currentUserProfile = UserProfile(
        name: 'Dhruv',
        age: 25,
        gender: 'Male',
        height: 180.0,
        weight: 80.0,
        workoutDaysMin: 4,
        workoutDaysMax: 5,
        goal: 'Fat Loss',
      );
      ProfileService.instance.currentUserProfile = currentUserProfile;
    });

    testWidgets('Insights screen opens with correct values immediately, refresh changes nothing', (WidgetTester tester) async {
      final monday = DateTime(2026, 6, 1);
      final friday = DateTime(2026, 6, 5);

      // Save workout sessions via WorkoutService (updates lastWorkoutsChangedAt)
      await WorkoutService.instance.saveSession(_makeSession(monday));
      await WorkoutService.instance.saveSession(_makeSession(friday));
      
      // Seed day logs in dayLogStore and call saveDayLogs (updates lastLogsChangedAt)
      dayLogStore.clear();
      dayLogStore['2026-06-01'] = _makeLog(date: monday, didGym: true, withMeals: true);
      dayLogStore['2026-06-02'] = _makeLog(date: DateTime(2026, 6, 2), withMeals: true)..gymDay = const GymDay(didGym: false);
      dayLogStore['2026-06-03'] = _makeLog(date: DateTime(2026, 6, 3), withMeals: true)..gymDay = const GymDay(didGym: false);
      dayLogStore['2026-06-04'] = _makeLog(date: DateTime(2026, 6, 4), withMeals: true)..gymDay = const GymDay(didGym: false);
      dayLogStore['2026-06-05'] = _makeLog(date: friday, didGym: true, withMeals: true);
      dayLogStore['2026-06-06'] = _makeLog(date: DateTime(2026, 6, 6), withMeals: true)..gymDay = const GymDay(didGym: false);
      dayLogStore['2026-06-07'] = _makeLog(date: DateTime(2026, 6, 7), withMeals: true)..gymDay = const GymDay(didGym: false);
      await PersistenceService.saveDayLogs();

      // Open the Insights screen for the first time
      await tester.pumpWidget(MaterialApp(
        home: const InsightsScreen(),
      ));
      
      // Let any asynchronous microtasks and timer run
      await tester.pumpAndSettle();

      // Verify Monday and Friday workouts show correctly in gym attendance row immediately
      // The row displays 'M', 'T', 'W', 'T', 'F', 'S', 'S'.
      // We expect 2 green checkmarks (didGym = true) and 5 crosses.
      // Let's verify we have exactly 2 Icons.check_rounded.
      final checkmarkFinder = find.byIcon(Icons.check_rounded);
      expect(checkmarkFinder, findsNWidgets(2));

      // Let's capture the initial consistency score text
      final scoreTextFinder = find.textContaining('/100');
      expect(scoreTextFinder, findsOneWidget);
      final Text scoreTextWidget = tester.widget<Text>(scoreTextFinder);
      final initialScoreText = scoreTextWidget.data;

      // Click the manual refresh button
      final refreshButton = find.byIcon(Icons.refresh_rounded);
      expect(refreshButton, findsOneWidget);
      await tester.tap(refreshButton);
      await tester.pumpAndSettle();

      // Verify that after refresh, gym attendance checkmarks and consistency score remain identical
      expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));
      expect(find.textContaining('/100'), findsOneWidget);
      final Text postRefreshScoreWidget = tester.widget<Text>(find.textContaining('/100'));
      final postRefreshScoreText = postRefreshScoreWidget.data;
      expect(postRefreshScoreText, equals(initialScoreText));

      // Advance clock by 5 seconds to let the achievements viewed timer fire and dispose cleanly
      await tester.pump(const Duration(seconds: 5));
    });

    test('mergeCacheFromCloud sets lastComputed to null to force local recompute', () async {
      final service = InsightsReportService.instance;
      
      // 1. Manually set lastComputed to a valid non-null time
      await service.forceRecompute(currentUserProfile!);
      expect(service.lastComputed, isNotNull);
      
      // 2. Call mergeCacheFromCloud with a mock cache
      await service.mergeCacheFromCloud({
        'weekly_json': {},
        'monthly_json': {},
        'yearly_json': {},
        'personal_bests_json': null,
        'updated_at': DateTime.now().toIso8601String(),
      });
      
      // 3. Verify lastComputed is null, forcing the next maybeRecompute to recompute
      expect(service.lastComputed, isNull);
    });
  });
}
