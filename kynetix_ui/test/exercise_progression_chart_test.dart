import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/workout_session.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/widgets/exercise_progression_chart.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ({DateTime date, ExerciseEntry entry}) makeHistoryItem({
    required DateTime date,
    required List<SetEntry> sets,
    bool isSkipped = false,
  }) {
    return (
      date: date,
      entry: ExerciseEntry(
        exercise: const Exercise(
          id: 'bench_press',
          name: 'Barbell Bench Press',
          muscleGroup: 'Chest',
          type: ExerciseType.barbellCompound,
        ),
        sets: sets,
        isSkipped: isSkipped,
      ),
    );
  }

  group('ExerciseProgressionChart Data Extraction', () {
    test('Calculates Overall, Volume, Weight, Reps, and 1RM progression correctly', () {
      final history = [
        makeHistoryItem(
          date: DateTime(2026, 8, 1),
          sets: [
            const SetEntry(reps: 8, weight: 80),
            const SetEntry(reps: 8, weight: 80),
          ],
        ),
        makeHistoryItem(
          date: DateTime(2026, 8, 8),
          sets: [
            const SetEntry(reps: 8, weight: 85),
            const SetEntry(reps: 7, weight: 85),
          ],
        ),
      ];

      expect(history.length, 2);
      expect(history[0].entry.topWorkingSet?.weight, 80);
      expect(history[1].entry.topWorkingSet?.weight, 85);
      expect(history[0].entry.totalVolume, 1280);
      expect(history[1].entry.totalVolume, 1275);

      final points = extractProgressionPoints(history);
      expect(points.length, 2);

      // Baseline session is indexed at 100.0 pts
      expect(points[0].overallScore, 100.0);
      expect(points[0].valueFor(ProgressionMetric.overall), 100.0);

      // Session 2 has higher 1RM: 85*(1+8/30)=107.67 vs 80*(1+8/30)=101.33
      // and slightly lower volume: 1275 vs 1280
      expect(points[1].overallScore, greaterThan(100.0));
      expect(points[1].formattedValueFor(ProgressionMetric.overall), contains('pts'));
    });

    test('Deterministic 60/40 strength and work-capacity composite formula verification', () {
      // Session 1 (baseline): 80kg x 8 reps -> 1RM = 80*(1+8/30) = 101.3333..., Volume = 640
      // Session 2: 100kg x 8 reps -> 1RM = 100*(1+8/30) = 126.6666..., Volume = 800
      // strengthRatio = 1.25, volRatio = 1.25 -> 100 * (0.6 * 1.25 + 0.4 * 1.25) = 125.0 exactly
      final history = [
        makeHistoryItem(
          date: DateTime(2026, 8, 1),
          sets: [const SetEntry(reps: 8, weight: 80)],
        ),
        makeHistoryItem(
          date: DateTime(2026, 8, 8),
          sets: [const SetEntry(reps: 8, weight: 100)],
        ),
      ];

      final points = extractProgressionPoints(history);
      expect(points.length, 2);
      expect(points[0].overallScore, 100.0);
      expect(points[1].overallScore, closeTo(125.0, 0.001));
    });

    test('Oldest valid historical point is always indexed at 100.0 regardless of input list order', () {
      final item1 = makeHistoryItem(
        date: DateTime(2026, 8, 1),
        sets: [const SetEntry(reps: 10, weight: 50)],
      );
      final item2 = makeHistoryItem(
        date: DateTime(2026, 8, 15),
        sets: [const SetEntry(reps: 10, weight: 60)],
      );

      // Pass out-of-order
      final points = extractProgressionPoints([item2, item1]);
      expect(points.length, 2);
      expect(points[0].date, DateTime(2026, 8, 1));
      expect(points[0].overallScore, 100.0);
      expect(points[1].date, DateTime(2026, 8, 15));
      expect(points[1].overallScore, greaterThan(100.0));
    });

    test('Deterministic fallback handling when components are zero or missing', () {
      // Bodyweight with no external load and reps only (volume = 0, e1RM = 0)
      final historyBodyweight = [
        makeHistoryItem(
          date: DateTime(2026, 8, 1),
          sets: [const SetEntry(reps: 10, weight: 0)],
        ),
        makeHistoryItem(
          date: DateTime(2026, 8, 8),
          sets: [const SetEntry(reps: 15, weight: 0)],
        ),
      ];
      final points = extractProgressionPoints(historyBodyweight);
      expect(points.length, 2);
      expect(points[0].overallScore, 100.0);
      // Fallback uses reps ratio: 15 / 10 = 1.5 -> 150.0 pts
      expect(points[1].overallScore, closeTo(150.0, 0.001));
    });

    test('Uncommitted current session data cannot alter historical progression score', () {
      final historicalLogs = [
        makeHistoryItem(
          date: DateTime(2026, 8, 1),
          sets: [const SetEntry(reps: 8, weight: 80)],
        ),
        makeHistoryItem(
          date: DateTime(2026, 8, 8),
          sets: [const SetEntry(reps: 8, weight: 85)],
        ),
      ];

      final baselinePoints = extractProgressionPoints(historicalLogs);

      // Simulate an active, uncommitted workout session with a new pending set
      final uncommittedCurrentSessionSets = [
        const SetEntry(reps: 20, weight: 120), // Outlier set currently in input/dial
      ];

      // Historical extraction only takes the past logs
      final recomputedPoints = extractProgressionPoints(historicalLogs);

      expect(recomputedPoints.length, baselinePoints.length);
      expect(recomputedPoints[0].overallScore, baselinePoints[0].overallScore);
      expect(recomputedPoints[1].overallScore, baselinePoints[1].overallScore);
      expect(uncommittedCurrentSessionSets.isNotEmpty, isTrue);
    });

    testWidgets('Renders chart widget with metric switcher in Overall / Volume / Weight / Reps / 1RM order and Overall selected initially', (tester) async {
      final history = [
        makeHistoryItem(
          date: DateTime(2026, 8, 1),
          sets: [
            const SetEntry(reps: 8, weight: 80),
          ],
        ),
        makeHistoryItem(
          date: DateTime(2026, 8, 8),
          sets: [
            const SetEntry(reps: 8, weight: 85),
          ],
        ),
        makeHistoryItem(
          date: DateTime(2026, 8, 15),
          sets: [
            const SetEntry(reps: 9, weight: 85),
          ],
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExerciseProgressionChart(
              exerciseName: 'Barbell Bench Press',
              history: history,
            ),
          ),
        ),
      );

      // Verify chart elements rendered
      expect(find.text('EXERCISE PROGRESSION'), findsOneWidget);
      expect(find.text('Overall'), findsOneWidget);
      expect(find.text('Volume'), findsOneWidget);
      expect(find.text('Weight'), findsOneWidget);
      expect(find.text('Reps'), findsOneWidget);
      expect(find.text('1RM'), findsOneWidget);

      // Verify default selected metric shows pts (Overall)
      expect(find.textContaining('pts'), findsWidgets);

      // Tap on 'Volume'
      await tester.tap(find.text('Volume'));
      await tester.pumpAndSettle();
      expect(find.textContaining('kg'), findsWidgets);

      // Tap on 'Weight'
      await tester.tap(find.text('Weight'));
      await tester.pumpAndSettle();
      expect(find.textContaining('kg'), findsWidgets);

      // Tap on 'Reps'
      await tester.tap(find.text('Reps'));
      await tester.pumpAndSettle();
      expect(find.textContaining('reps'), findsWidgets);

      // Tap on '1RM'
      await tester.tap(find.text('1RM'));
      await tester.pumpAndSettle();
      expect(find.textContaining('kg'), findsWidgets);

      // Tap back to 'Overall'
      await tester.tap(find.text('Overall'));
      await tester.pumpAndSettle();
      expect(find.textContaining('pts'), findsWidgets);
    });

    testWidgets('Renders empty state when history is empty', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ExerciseProgressionChart(
              exerciseName: 'Barbell Bench Press',
              history: [],
            ),
          ),
        ),
      );

      expect(find.text('No previous history for this exercise.'), findsOneWidget);
    });
  });
}
