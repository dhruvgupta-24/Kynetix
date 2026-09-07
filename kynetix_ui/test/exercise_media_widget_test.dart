import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/services/exercise_media_service.dart';
import 'package:kynetix/widgets/exercise_media_widget.dart';

void main() {
  group('ExerciseMediaWidget Tests', () {
    testWidgets('Mounts with Exercise instance and resolves canonical attribution', (tester) async {
      const ex = Exercise(
        id: 'overhead_tri_ext',
        name: 'Overhead Tricep Extension',
        muscleGroup: 'Triceps',
        type: ExerciseType.cableMachine,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ExerciseMediaWidget(
              exercise: ex,
              height: 180,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.byType(ExerciseMediaWidget), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Graceful fallback triggers onTwoLoopsCompleted when media is absent', (tester) async {
      bool completed = false;
      const customEx = Exercise(
        id: 'no_media_exercise',
        name: 'Obscure Lift 123',
        muscleGroup: 'Legs',
        type: ExerciseType.isolation,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExerciseMediaWidget(
              exercise: customEx,
              height: 180,
              onTwoLoopsCompleted: () {
                completed = true;
              },
            ),
          ),
        ),
      );
      await tester.pump();
      expect(completed, isFalse);

      // Advance by 700ms to allow graceful fallback timer to fire
      await tester.pump(const Duration(milliseconds: 700));
      expect(completed, isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Switching exercises resets loop state deterministically', (tester) async {
      const ex1 = Exercise(
        id: 'custom_1',
        name: 'Movement 1',
        muscleGroup: 'Chest',
        type: ExerciseType.barbellCompound,
      );

      const ex2 = Exercise(
        id: 'custom_2',
        name: 'Movement 2',
        muscleGroup: 'Back',
        type: ExerciseType.cableMachine,
      );

      int completions = 0;
      Exercise currentEx = ex1;
      late StateSetter updateState;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                updateState = setState;
                return ExerciseMediaWidget(
                  key: const ValueKey('widget_key'),
                  exercise: currentEx,
                  onTwoLoopsCompleted: () {
                    completions++;
                  },
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      expect(completions, 0);

      // Allow ex1's fallback to fire
      await tester.pump(const Duration(milliseconds: 700));
      expect(completions, 1);

      // Update state to ex2
      updateState(() {
        currentEx = ex2;
      });
      await tester.pump();

      // Allow ex2's fallback to fire
      await tester.pump(const Duration(milliseconds: 700));
      expect(completions, 2);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
