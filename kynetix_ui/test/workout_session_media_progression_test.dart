import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/models/workout_session.dart';
import 'package:kynetix/widgets/exercise_media_widget.dart';
import 'package:kynetix/screens/workout_session_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WorkoutSessionScreen Media & Progression Reveal Tests', () {
    final splitDay = SplitDay(
      name: 'Push Day',
      weekday: 1,
      exercises: [
        const Exercise(
          id: 'bench_press',
          name: 'Barbell Bench Press',
          muscleGroup: 'Chest',
          type: ExerciseType.barbellCompound,
          defaultTargetSets: 3,
        ),
        const Exercise(
          id: 'face_pull',
          name: 'Face Pull',
          muscleGroup: 'Shoulders',
          type: ExerciseType.cableMachine,
          defaultTargetSets: 3,
        ),
      ],
    );

    testWidgets('Renders canonical media widget directly under exercise header and reserves progression layout', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: WorkoutSessionScreen(
            splitDay: splitDay,
            date: DateTime.now(),
          ),
        ),
      );

      // Deterministic wait for initial frame
      await tester.pump(const Duration(milliseconds: 100));

      // 1. ExerciseMediaWidget must be mounted directly on the screen
      expect(find.byType(ExerciseMediaWidget), findsOneWidget);

      // 2. Initial state: Analyzing progression indicator is visible in reserved layout
      expect(find.text('Analyzing Progression...'), findsOneWidget);

      // 3. Dials and CTA are interactive immediately while GIF is playing
      expect(find.text('Barbell Bench Press'), findsOneWidget);
      expect(find.textContaining('LOG SET'), findsOneWidget);

      // 4. Exercise header and insights icons are present
      expect(find.byIcon(Icons.insights_rounded), findsOneWidget);
      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);

      // Cleanly unmount to cancel timers
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
