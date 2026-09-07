import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/models/workout_session.dart';
import 'package:kynetix/widgets/exercise_media_widget.dart';
import 'package:kynetix/screens/workout_session_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WorkoutSessionScreen Single Shared Slot & Progression Reveal Tests', () {
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

    testWidgets('Initial state: Renders compact media demo in shared slot, no Analyzing placeholder, no GymVisual URL', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: WorkoutSessionScreen(
            splitDay: splitDay,
            date: DateTime.now(),
          ),
        ),
      );

      // Deterministic initial frame
      await tester.pump(const Duration(milliseconds: 100));

      // 1. Media Demo view is mounted in the shared slot
      expect(find.byKey(const ValueKey('demo_view')), findsOneWidget);
      final mediaWidget = tester.widget<ExerciseMediaWidget>(find.byType(ExerciseMediaWidget));
      expect(mediaWidget.showAttribution, isFalse, reason: 'Attribution/branding overlay must not be visible on workout screen');
      expect(mediaWidget.interactiveZoom, isFalse, reason: 'Interactive zoom overlay should be disabled in workout view');
      expect(mediaWidget.targetLoops, equals(2), reason: 'Must be configured for exactly 2 loops');

      // 2. No giant "Analyzing Progression..." area exists
      expect(find.text('Analyzing Progression...'), findsNothing);

      // 3. Primary set logging UI is visible immediately above the fold
      expect(find.text('Barbell Bench Press'), findsOneWidget);
      expect(find.textContaining('LOG SET'), findsOneWidget);

      // 4. Exercise header and actions are present
      expect(find.byIcon(Icons.insights_rounded), findsOneWidget);
      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);

      // Clean unmount
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('Loop completion triggers transition to compact progression card with replay ability', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: WorkoutSessionScreen(
            splitDay: splitDay,
            date: DateTime.now(),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      // Initially demo view is active
      expect(find.byKey(const ValueKey('demo_view')), findsOneWidget);
      expect(find.byKey(const ValueKey('progression_view')), findsNothing);

      // Trigger 2-loops completion via ExerciseMediaWidget callback
      final mediaWidget = tester.widget<ExerciseMediaWidget>(find.byType(ExerciseMediaWidget));
      expect(mediaWidget.onTwoLoopsCompleted, isNotNull);
      mediaWidget.onTwoLoopsCompleted!();

      // Pump animation frame
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // complete AnimatedSwitcher transition

      // Progression card is now mounted in the exact same slot
      expect(find.byKey(const ValueKey('progression_view')), findsOneWidget);
      expect(
        find.text('PROGRESSION RECOMMENDATION').evaluate().isNotEmpty ||
            find.text('TRAINING ADVICE').evaluate().isNotEmpty,
        isTrue,
      );

      // Replay button is present
      final replayFinder = find.byIcon(Icons.play_arrow_rounded);
      expect(replayFinder, findsOneWidget);

      // Tap replay button to return to demo view
      await tester.tap(replayFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Successfully switched back to demo view
      expect(find.byKey(const ValueKey('demo_view')), findsOneWidget);

      // Clean unmount
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
