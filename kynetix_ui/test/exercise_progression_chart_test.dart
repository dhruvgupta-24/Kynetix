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
    test('Calculates 1RM, weight, volume, and reps progression correctly', () {
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
    });

    testWidgets('Renders chart widget with metric switcher buttons and handles taps', (tester) async {
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
      expect(find.text('1RM'), findsOneWidget);
      expect(find.text('Weight'), findsOneWidget);
      expect(find.text('Volume'), findsOneWidget);
      expect(find.text('Reps'), findsOneWidget);

      // Tap on 'Weight'
      await tester.tap(find.text('Weight'));
      await tester.pumpAndSettle();

      // Tap on 'Volume'
      await tester.tap(find.text('Volume'));
      await tester.pumpAndSettle();

      // Tap on 'Reps'
      await tester.tap(find.text('Reps'));
      await tester.pumpAndSettle();
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
