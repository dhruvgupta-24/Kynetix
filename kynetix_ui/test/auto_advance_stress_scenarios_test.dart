import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/screens/workout_session_screen.dart';
import 'package:kynetix/services/workout_service.dart';
import 'package:kynetix/services/exercise_media_service.dart';
import 'package:kynetix/widgets/exercise_media_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        anonKey: 'mock-anon-key',
      );
    } catch (_) {}
  });

  Future<void> resetState() async {
    SharedPreferences.setMockInitialValues({});
    ExerciseMediaWidget.disableNetworkForTesting = true;
    await WorkoutService.instance.clearAll();
    WorkoutService.instance.resetReadyForTesting();
    await WorkoutService.instance.init();
  }

  setUp(() async {
    await resetState();
  });

  tearDown(() {
    ExerciseMediaWidget.disableNetworkForTesting = false;
  });

  final testSplitDay = SplitDay(
    name: 'Push Day',
    weekday: 1,
    exercises: const [
      Exercise(
        id: 'ex1_bench',
        name: 'Bench Press',
        muscleGroup: 'Chest',
        type: ExerciseType.barbellCompound,
        defaultTargetSets: 1, // 1 set so logging set 1 triggers auto-advance!
      ),
      Exercise(
        id: 'ex2_incline',
        name: 'Incline Dumbbell Press',
        muscleGroup: 'Chest',
        type: ExerciseType.dumbbell,
        defaultTargetSets: 2,
      ),
      Exercise(
        id: 'ex3_lateral',
        name: 'Lateral Raise',
        muscleGroup: 'Shoulders',
        type: ExerciseType.dumbbell,
        defaultTargetSets: 2,
      ),
    ],
  );

  Widget createTestWidget() {
    return MaterialApp(
      theme: ThemeData.dark(),
      home: WorkoutSessionScreen(
        splitDay: testSplitDay,
        date: DateTime(2026, 6, 8),
        draftSession: null,
      ),
    );
  }

  group('Requirement 2: Original Auto-Advance Stress Tests (>= 5 Runs per Scenario)', () {
    // -------------------------------------------------------------
    // Scenario A: Rapid Double-Tap LOG SET on Final Set
    // -------------------------------------------------------------
    testWidgets('Stress Scenario A: Double-tap LOG SET on final set (5 iterations)', (tester) async {
      for (int run = 1; run <= 5; run++) {
        await resetState();
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('EXERCISE 1 OF 3'), findsOneWidget);
        final logSetBtn = find.text('LOG SET 1');
        expect(logSetBtn, findsOneWidget);

        // Rapid double tap at the button's screen coordinates
        final point = tester.getCenter(logSetBtn);
        await tester.tapAt(point);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tapAt(point);
        await tester.pump(const Duration(milliseconds: 50));

        // Let 600ms timer and animation settle
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();

        // Must cleanly auto-advance to Exercise 2 without crashing or locking
        expect(find.text('EXERCISE 2 OF 3'), findsOneWidget);
        expect(find.text('Incline Dumbbell Press'), findsWidgets);

        // Reset for next run
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    });

    // -------------------------------------------------------------
    // Scenario B: User Swipes PageView during the 600ms Timer Delay
    // -------------------------------------------------------------
    testWidgets('Stress Scenario B: User swipes PageView during 600ms delay (5 iterations)', (tester) async {
      for (int run = 1; run <= 5; run++) {
        await resetState();
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('EXERCISE 1 OF 3'), findsOneWidget);
        final logSetBtn = find.text('LOG SET 1');
        await tester.tap(logSetBtn);

        // Advance timer partially (200ms into the 600ms delay)
        await tester.pump(const Duration(milliseconds: 200));

        // User manually swipes PageView left to Exercise 2
        await tester.drag(find.byType(PageView), const Offset(-400, 0));
        await tester.pumpAndSettle();

        // Timer should have been cancelled by page change, gesture completed cleanly
        expect(find.text('EXERCISE 2 OF 3'), findsOneWidget);
        expect(find.text('Incline Dumbbell Press'), findsWidgets);

        // Ensure no pending timers crash the widget tree
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    });

    // -------------------------------------------------------------
    // Scenario C: User Taps Another Exercise Capsule during 600ms Delay
    // -------------------------------------------------------------
    testWidgets('Stress Scenario C: User taps another exercise capsule during delay (5 iterations)', (tester) async {
      for (int run = 1; run <= 5; run++) {
        await resetState();
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('EXERCISE 1 OF 3'), findsOneWidget);
        final logSetBtn = find.text('LOG SET 1');
        await tester.tap(logSetBtn);

        // Advance 150ms into delay
        await tester.pump(const Duration(milliseconds: 150));

        // User explicitly taps Exercise 3 ("Lateral Raise") pill
        final ex3Pills = find.text('Lateral Raise');
        expect(ex3Pills, findsWidgets);
        await tester.tap(ex3Pills.first);
        await tester.pumpAndSettle();

        // Navigated directly to Exercise 3, auto-advance timer to Exercise 2 was safely cancelled
        expect(find.text('EXERCISE 3 OF 3'), findsOneWidget);

        // Advance time to verify old timer does not fire and jump back to Exercise 2
        await tester.pump(const Duration(milliseconds: 700));
        await tester.pumpAndSettle();
        expect(find.text('EXERCISE 3 OF 3'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    });

    // -------------------------------------------------------------
    // Scenario D: Rapid Back/Forth Navigation
    // -------------------------------------------------------------
    testWidgets('Stress Scenario D: Rapid back/forth navigation (5 iterations)', (tester) async {
      for (int run = 1; run <= 5; run++) {
        await resetState();
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Rapidly swipe between PageViews 6 times
        for (int s = 0; s < 3; s++) {
          await tester.drag(find.byType(PageView), const Offset(-400, 0));
          await tester.pump(const Duration(milliseconds: 50));
          await tester.drag(find.byType(PageView), const Offset(400, 0));
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.pumpAndSettle();

        // PageView controller stays responsive, no lockups
        expect(find.byType(PageView), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    });

    // -------------------------------------------------------------
    // Scenario E: Log Set Immediately Upon Arrival on Exercise 2
    // -------------------------------------------------------------
    testWidgets('Stress Scenario E: Log set immediately upon arrival on Exercise 2 (5 iterations)', (tester) async {
      for (int run = 1; run <= 5; run++) {
        await resetState();
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Log final set on Exercise 1
        await tester.tap(find.text('LOG SET 1'));
        await tester.pump(const Duration(milliseconds: 650));
        await tester.pumpAndSettle();

        // Immediately upon arrival, tap LOG SET 1 on Exercise 2
        expect(find.text('EXERCISE 2 OF 3'), findsOneWidget);
        final logSet2Btn = find.text('LOG SET 1');
        await tester.tap(logSet2Btn);
        await tester.pumpAndSettle();

        // Set logged cleanly, next set is now LOG SET 2
        expect(find.text('LOG SET 2'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    });
  });
}
