import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/services/kyno_progression_engine.dart';
import 'package:kynetix/widgets/exercise_media_widget.dart';
import 'package:kynetix/widgets/kyno_stage_slot.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  debugPrint('[MEDIA_TEST] app/test binding initialized');
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('KynoStageSlot Single Bounded Stage & Progression Reveal Tests', () {
    setUp(() {
      ExerciseMediaWidget.disableNetworkForTesting = true;
    });

    tearDown(() {
      ExerciseMediaWidget.disableNetworkForTesting = false;
    });

    const benchPress = Exercise(
      id: 'bench_press',
      name: 'Barbell Bench Press',
      muscleGroup: 'Chest',
      type: ExerciseType.barbellCompound,
      defaultTargetSets: 3,
    );

    debugPrint('[MEDIA_TEST] progression advice calculated');
    final mockAdvice = KynoProgressionAdvice(
      action: '+2.5 kg next session',
      summary: 'Solid ceiling hit: 3 sets completed across consecutive exposures. Advance load safely.',
      evidence: [
        'Completed 3/3 target working sets at 80.0 kg for 8 reps',
        'Multi-session ceiling met without failure indicators',
      ],
      todayTarget: '82.5 kg × 8 reps',
      nextMilestone: 'Establish 82.5 kg across 3 working sets',
      confidence: 'High Confidence',
      spark1RmTrend: [95.0, 97.5, 100.0, 102.5],
      styleLabel: 'Double Progression',
    );

    testWidgets(
      '1. Initial state: Renders compact media demo in ~195px slot, no attribution, targetLoops=2',
      (tester) async {
        debugPrint('[MEDIA_TEST] media stage mounted');
        final controller = ExerciseDemoPlaybackController(targetLoops: 2);

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: KynoStageSlot(
                exercise: benchPress,
                advice: mockAdvice,
                height: 195.0,
                playbackController: controller,
              ),
            ),
          ),
        );

        await tester.pump(const Duration(milliseconds: 50));

        // 1. Media Demo view is active
        expect(find.byKey(const ValueKey('demo_view')), findsOneWidget);
        expect(find.byKey(const ValueKey('progression_view')), findsNothing);

        // 2. ExerciseMediaWidget properties
        final mediaWidget = tester.widget<ExerciseMediaWidget>(find.byType(ExerciseMediaWidget));
        expect(mediaWidget.showAttribution, isFalse, reason: 'No GymVisual URL or overlay should be shown');
        expect(mediaWidget.interactiveZoom, isFalse, reason: 'Zoom overlay disabled in workout slot');
        expect(mediaWidget.targetLoops, equals(2), reason: 'Must loop exactly 2 times');

        // 3. Slot size is strictly bounded
        final slotBox = tester.renderObject<RenderBox>(find.byType(KynoStageSlot));
        expect(slotBox.size.height, equals(195.0));

        // 4. No loading spinner or "Analyzing Progression..."
        expect(find.text('Analyzing Progression...'), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);

        debugPrint('[MEDIA_TEST] test cleanup started');
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 20));
        debugPrint('[MEDIA_TEST] test cleanup completed');
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    testWidgets(
      '2. Loop completion: Smoothly switches to Progression card with zero loading delay',
      (tester) async {
        final controller = ExerciseDemoPlaybackController(targetLoops: 2);

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: KynoStageSlot(
                exercise: benchPress,
                advice: mockAdvice,
                height: 195.0,
                playbackController: controller,
              ),
            ),
          ),
        );

        await tester.pump(const Duration(milliseconds: 50));

        // Initially demo_view is mounted
        expect(find.byKey(const ValueKey('demo_view')), findsOneWidget);
        expect(find.byKey(const ValueKey('progression_view')), findsNothing);

        // Deterministically simulate loop 1
        debugPrint('[MEDIA_TEST] loop 1 simulated');
        controller.recordLoop();
        await tester.pump(const Duration(milliseconds: 20));
        expect(find.byKey(const ValueKey('demo_view')), findsOneWidget);
        expect(find.byKey(const ValueKey('progression_view')), findsNothing);

        // Deterministically simulate loop 2
        debugPrint('[MEDIA_TEST] loop 2 simulated');
        controller.recordLoop();
        expect(controller.isCompleted, isTrue);

        // Advance animation (600ms transition)
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 650));

        debugPrint('[MEDIA_TEST] progression stage revealed');
        expect(find.byKey(const ValueKey('progression_view')), findsOneWidget);
        expect(find.byKey(const ValueKey('demo_view')), findsNothing);

        debugPrint('[MEDIA_TEST] recommendation rendered');
        expect(find.text('PROGRESSION RECOMMENDATION'), findsOneWidget);
        expect(find.text('+2.5 kg next session'), findsOneWidget);
        expect(find.text('DOUBLE PROGRESSION'), findsOneWidget);
        expect(find.textContaining('Today\'s target: 82.5 kg × 8 reps'), findsOneWidget);
        expect(find.textContaining('Solid ceiling hit'), findsOneWidget);
        expect(find.text('1RM: 102.5 kg'), findsOneWidget);
        expect(find.text('Demo'), findsOneWidget);

        debugPrint('[MEDIA_TEST] test cleanup started');
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 20));
        debugPrint('[MEDIA_TEST] test cleanup completed');
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    testWidgets(
      '3. Demo replay button switches back to demonstration view',
      (tester) async {
        final controller = ExerciseDemoPlaybackController(targetLoops: 2);

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: KynoStageSlot(
                exercise: benchPress,
                advice: mockAdvice,
                height: 195.0,
                playbackController: controller,
              ),
            ),
          ),
        );

        await tester.pump(const Duration(milliseconds: 50));

        // Complete loops to reveal progression
        controller.completeLoops();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 650));

        expect(find.byKey(const ValueKey('progression_view')), findsOneWidget);

        // Tap the [Demo] replay button
        final replayFinder = find.text('Demo');
        expect(replayFinder, findsOneWidget);
        await tester.tap(replayFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 650));

        // Successfully switched back to demo view, and controller was reset
        expect(find.byKey(const ValueKey('demo_view')), findsOneWidget);
        expect(find.byKey(const ValueKey('progression_view')), findsNothing);
        expect(controller.isCompleted, isFalse);
        expect(controller.completedLoops, equals(0));

        debugPrint('[MEDIA_TEST] test cleanup started');
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 20));
        debugPrint('[MEDIA_TEST] test cleanup completed');
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    testWidgets(
      '4. Expandable "Why?" drawer reveals evidence and next milestone',
      (tester) async {
        final controller = ExerciseDemoPlaybackController(targetLoops: 2);

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: KynoStageSlot(
                exercise: benchPress,
                advice: mockAdvice,
                height: 195.0,
                playbackController: controller,
              ),
            ),
          ),
        );

        await tester.pump(const Duration(milliseconds: 50));

        // Transition to progression card
        controller.completeLoops();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 650));

        // Tap "Why?" button
        final whyFinder = find.text('Why?');
        expect(whyFinder, findsOneWidget);
        await tester.tap(whyFinder);
        await tester.pump();

        // Expanded evidence view is visible
        expect(find.text('EVIDENCE & NEXT MILESTONE'), findsOneWidget);
        expect(find.textContaining('Completed 3/3 target working sets'), findsOneWidget);
        expect(find.textContaining('NEXT: Establish 82.5 kg'), findsOneWidget);
        expect(find.text('Close'), findsOneWidget);

        // Tap Close button
        await tester.tap(find.text('Close'));
        await tester.pump();

        // Collapsed back to compact card view
        expect(find.text('PROGRESSION RECOMMENDATION'), findsOneWidget);
        expect(find.text('Why?'), findsOneWidget);

        debugPrint('[MEDIA_TEST] test cleanup started');
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 20));
        debugPrint('[MEDIA_TEST] test cleanup completed');
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    testWidgets(
      '5. Exercise change resets slot back to demonstration view',
      (tester) async {
        final controller = ExerciseDemoPlaybackController(targetLoops: 2);

        const inclinePress = Exercise(
          id: 'incline_dumbbell_press',
          name: 'Incline Dumbbell Press',
          muscleGroup: 'Chest',
          type: ExerciseType.dumbbell,
          defaultTargetSets: 3,
        );

        final otherAdvice = KynoProgressionAdvice(
          action: 'Maintain & solidify',
          summary: 'Volume accumulation phase.',
          evidence: ['First exposure recorded'],
          todayTarget: '24.0 kg × 10 reps',
          nextMilestone: 'Reach 12 reps on all sets',
          confidence: 'Baseline Calibration',
          spark1RmTrend: [28.0],
          styleLabel: 'Linear Reps',
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: KynoStageSlot(
                exercise: benchPress,
                advice: mockAdvice,
                height: 195.0,
                playbackController: controller,
              ),
            ),
          ),
        );

        await tester.pump(const Duration(milliseconds: 50));

        // Advance to progression
        controller.completeLoops();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 650));
        expect(find.byKey(const ValueKey('progression_view')), findsOneWidget);

        // Now update widget with a different exercise
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: KynoStageSlot(
                exercise: inclinePress,
                advice: otherAdvice,
                height: 195.0,
                playbackController: controller,
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 650));

        // Automatically reset back to demo_view for new exercise
        expect(find.byKey(const ValueKey('demo_view')), findsOneWidget);
        expect(find.byKey(const ValueKey('progression_view')), findsNothing);
        expect(controller.isCompleted, isFalse);

        debugPrint('[MEDIA_TEST] test cleanup started');
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 20));
        debugPrint('[MEDIA_TEST] test cleanup completed');
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );
  });
}
