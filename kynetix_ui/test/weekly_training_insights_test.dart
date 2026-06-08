import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/insights_models.dart';
import 'package:kynetix/services/insights_engine.dart';
import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/models/workout_session.dart';
import 'package:kynetix/models/user_profile.dart';
import 'package:kynetix/models/day_status.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/services/mock_estimation_service.dart' show NutrientRange;

DayLog _makeDummyLog(DateTime date, {bool didGym = false}) {
  final log = DayLog();
  if (didGym) {
    log.gymDay = const GymDay(didGym: true);
  }
  log.add(
    MealSection.breakfast,
    MealEntry(
      rawInput: 'Dummy Meal',
      result: NutritionResult(
        canonicalMeal: 'Dummy Meal',
        items: [],
        calories: NutrientRange(min: 300, max: 300),
        protein: NutrientRange(min: 25, max: 25),
        confidence: 0.9,
        warnings: const [],
        source: 'test',
        createdAt: date,
      ),
      addedAt: date,
      section: MealSection.breakfast,
      dayOfWeek: date.weekday,
      parsedFoods: const ['Dummy Meal'],
      finalSavedInput: 'Dummy Meal',
    ),
  );
  return log;
}

void main() {
  group('Weekly Training Review & Insights Engine Tests', () {
    late UserProfile profile;

    setUp(() {
      profile = const UserProfile(
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

    test('Undertrained muscle group detection (sets < 6)', () {
      // Setup a week where chest is only trained for 2 hard sets (below 6 sets)
      final date = DateTime(2026, 6, 1);
      final session = WorkoutSession(
        id: 'ws-chest-under',
        date: date,
        splitDayName: 'Push Day',
        entries: [
          ExerciseEntry(
            exercise: const Exercise(
              id: 'ex-bench-press',
              name: 'Bench Press',
              muscleGroup: 'Chest',
              type: ExerciseType.barbellCompound,
            ),
            sets: const [
              SetEntry(weight: 60.0, reps: 8, setType: SetType.normal),
              SetEntry(weight: 60.0, reps: 8, setType: SetType.normal),
            ],
          ),
        ],
      );

      final logs = {
        '2026-06-01': _makeDummyLog(DateTime(2026, 6, 1), didGym: true),
        '2026-06-02': _makeDummyLog(DateTime(2026, 6, 2)),
        '2026-06-03': _makeDummyLog(DateTime(2026, 6, 3)),
        '2026-06-04': DayLog(),
        '2026-06-05': DayLog(),
        '2026-06-06': DayLog(),
        '2026-06-07': DayLog(),
      };

      final report = InsightsEngine.computeWeek(
        weekKey: '2026-W23',
        profile: profile,
        logs: logs,
        sessions: [session],
        priorWeek: null,
      );

      expect(report, isNotNull);
      
      // Verify Training Volume Score deductions
      expect(report!.trainingVolumeScore, lessThan(100));
      expect(report.trainingVolumeExplanation, contains('Chest'));
      expect(report.coachingNeedsImprovement, anyElement(contains('Chest volume below recommended range.')));
      expect(report.coachingRecommendations, anyElement(contains('Add 2-4 sets for Chest next week.')));
    });

    test('Overtrained muscle group detection (consecutive days training / sets > 20)', () {
      // Setup a week where chest is trained on 2 consecutive days, and also has > 20 hard sets
      final date1 = DateTime(2026, 6, 1);
      final date2 = DateTime(2026, 6, 2);

      final session1 = WorkoutSession(
        id: 'ws-chest-over-1',
        date: date1,
        splitDayName: 'Push Day 1',
        entries: [
          ExerciseEntry(
            exercise: const Exercise(
              id: 'ex-bench-press',
              name: 'Bench Press',
              muscleGroup: 'Chest',
              type: ExerciseType.barbellCompound,
            ),
            sets: List.generate(12, (_) => const SetEntry(weight: 60.0, reps: 8, setType: SetType.normal)),
          ),
        ],
      );

      final session2 = WorkoutSession(
        id: 'ws-chest-over-2',
        date: date2,
        splitDayName: 'Push Day 2',
        entries: [
          ExerciseEntry(
            exercise: const Exercise(
              id: 'ex-incline-press',
              name: 'Incline Press',
              muscleGroup: 'Chest',
              type: ExerciseType.barbellCompound,
            ),
            sets: List.generate(12, (_) => const SetEntry(weight: 60.0, reps: 8, setType: SetType.normal)),
          ),
        ],
      );

      final logs = {
        '2026-06-01': _makeDummyLog(DateTime(2026, 6, 1), didGym: true),
        '2026-06-02': _makeDummyLog(DateTime(2026, 6, 2), didGym: true),
        '2026-06-03': _makeDummyLog(DateTime(2026, 6, 3)),
        '2026-06-04': DayLog(),
        '2026-06-05': DayLog(),
        '2026-06-06': DayLog(),
        '2026-06-07': DayLog(),
      };

      final report = InsightsEngine.computeWeek(
        weekKey: '2026-W23',
        profile: profile,
        logs: logs,
        sessions: [session1, session2],
        priorWeek: null,
      );

      expect(report, isNotNull);
      
      // Verify spacing/recovery score deductions
      expect(report!.trainingRecoveryScore, lessThan(100));
      expect(report.trainingRecoveryExplanation, contains('Chest was trained on consecutive days.'));
      expect(report.coachingNeedsImprovement, anyElement(contains('Insufficient recovery windows detected on consecutive training days.')));

      // Verify volume score overtraining detection
      expect(report.trainingVolumeExplanation, contains('Overtrained muscles: Chest'));
      expect(report.coachingNeedsImprovement, anyElement(contains('Chest received unusually high weekly volume.')));
    });

    test('Push/Pull imbalance detection (push sets > 2 * pull sets)', () {
      // Setup a week where push sets (Chest, Shoulders, Triceps) = 15, and pull sets (Back, Rear Delts, Biceps) = 4
      final date = DateTime(2026, 6, 1);
      final session = WorkoutSession(
        id: 'ws-imbalance',
        date: date,
        splitDayName: 'Imbalance Day',
        entries: [
          ExerciseEntry(
            exercise: const Exercise(id: 'ex-1', name: 'Bench', muscleGroup: 'Chest', type: ExerciseType.barbellCompound),
            sets: List.generate(15, (_) => const SetEntry(weight: 60.0, reps: 8, setType: SetType.normal)),
          ),
          ExerciseEntry(
            exercise: const Exercise(id: 'ex-2', name: 'Row', muscleGroup: 'Back', type: ExerciseType.barbellCompound),
            sets: List.generate(4, (_) => const SetEntry(weight: 60.0, reps: 8, setType: SetType.normal)),
          ),
        ],
      );

      final logs = {
        '2026-06-01': _makeDummyLog(DateTime(2026, 6, 1), didGym: true),
        '2026-06-02': _makeDummyLog(DateTime(2026, 6, 2)),
        '2026-06-03': _makeDummyLog(DateTime(2026, 6, 3)),
        '2026-06-04': DayLog(),
        '2026-06-05': DayLog(),
        '2026-06-06': DayLog(),
        '2026-06-07': DayLog(),
      };

      final report = InsightsEngine.computeWeek(
        weekKey: '2026-W23',
        profile: profile,
        logs: logs,
        sessions: [session],
        priorWeek: null,
      );

      expect(report, isNotNull);
      
      // Verify Balance score deduction
      expect(report!.trainingBalanceScore, lessThan(100));
      expect(report.trainingBalanceExplanation, contains('Push volume'));
      expect(report.trainingBalanceExplanation, contains('is much higher than pull volume'));
    });

    test('Progressive Overload Achievement tracking', () {
      // Prior week
      final priorSession = WorkoutSession(
        id: 'ws-prior',
        date: DateTime(2026, 5, 25),
        splitDayName: 'Push',
        entries: [
          ExerciseEntry(
            exercise: const Exercise(id: 'ex-overload', name: 'Bench Press', muscleGroup: 'Chest', type: ExerciseType.barbellCompound),
            sets: const [
              SetEntry(weight: 60.0, reps: 8, setType: SetType.normal),
            ],
          ),
        ],
      );

      // Current week: weight increased to 65 kg
      final currentSession = WorkoutSession(
        id: 'ws-current',
        date: DateTime(2026, 6, 1),
        splitDayName: 'Push',
        entries: [
          ExerciseEntry(
            exercise: const Exercise(id: 'ex-overload', name: 'Bench Press', muscleGroup: 'Chest', type: ExerciseType.barbellCompound),
            sets: const [
              SetEntry(weight: 65.0, reps: 8, setType: SetType.normal),
            ],
          ),
        ],
      );

      final priorReport = WeeklyReport(
        weekKey: '2026-W22',
        weekStart: DateTime(2026, 5, 25),
        consistencyScore: const ConsistencyScore(score: 70, loggingConsistency: 1.0, proteinAdherence: 1.0, calorieAdherence: 1.0, gymAttendance: 1.0, mealQuality: 0.0),
        avgCalories: 2000, avgProtein: 150, avgFiber: 25, gymDaysCount: 3, loggedDaysCount: 7, regressions: const [], computedAt: DateTime.now(),
        mostCommonOutcome: DayOutcome.veryGoodFatLoss,
      );

      final logs = {
        '2026-06-01': _makeDummyLog(DateTime(2026, 6, 1), didGym: true),
        '2026-06-02': _makeDummyLog(DateTime(2026, 6, 2)),
        '2026-06-03': _makeDummyLog(DateTime(2026, 6, 3)),
        '2026-06-04': DayLog(),
        '2026-06-05': DayLog(),
        '2026-06-06': DayLog(),
        '2026-06-07': DayLog(),
      };

      final report = InsightsEngine.computeWeek(
        weekKey: '2026-W23',
        profile: profile,
        logs: logs,
        sessions: [currentSession],
        priorWeek: priorReport,
        // We need to pass the prior week's sessions too.
        // Let's pass the prior week sessions inside the sessions list, but filtered correctly by date in computeWeek!
        // Yes, computeWeek filters sessions using weekStart. Here we pass both sessions!
      );

      final reportWithPriorSessions = InsightsEngine.computeWeek(
        weekKey: '2026-W23',
        profile: profile,
        logs: logs,
        sessions: [priorSession, currentSession],
        priorWeek: priorReport,
      );

      expect(reportWithPriorSessions, isNotNull);
      expect(reportWithPriorSessions!.coachingWhatWentWell, anyElement(contains('Progressive overload achieved on Bench Press (increased weight to 65 kg from 60 kg).')));
    });
  });
}
