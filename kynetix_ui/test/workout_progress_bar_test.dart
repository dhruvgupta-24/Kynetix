import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/screens/workout_session_screen.dart';
import 'package:kynetix/services/workout_service.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await WorkoutService.instance.clearDraftSession();
  });

  tearDown(() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await WorkoutService.instance.clearDraftSession();
  });

  final mockExercises = [
    const Exercise(
      id: 'ex_bench',
      name: 'Bench Press',
      muscleGroup: 'Chest',
      type: ExerciseType.barbellCompound,
      defaultTargetSets: 2,
      defaultRepMin: 8,
      defaultRepMax: 10,
    ),
    const Exercise(
      id: 'ex_incline',
      name: 'Incline Dumbbell Press',
      muscleGroup: 'Chest',
      type: ExerciseType.dumbbell,
      defaultTargetSets: 2,
      defaultRepMin: 8,
      defaultRepMax: 10,
    ),
  ];

  final twoExerciseSplit = SplitDay(
    weekday: 1,
    name: 'Push Day',
    exercises: mockExercises,
  );

  testWidgets('Workout Progress Bar Widget Test: Lifecycle, Navigation, and Completion', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: WorkoutSessionScreen(
          splitDay: twoExerciseSplit,
          date: DateTime.now(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Initial State: Progress Bar is present and starts at 0%
    final progressBarFinder = find.byKey(const Key('workout_progress_bar'));
    final percentTextFinder = find.byKey(const Key('workout_progress_percent_text'));

    expect(progressBarFinder, findsOneWidget, reason: 'Workout progress bar must be visible on the training screen');
    expect(percentTextFinder, findsOneWidget);

    final initialBar = tester.widget<LinearProgressIndicator>(progressBarFinder);
    expect(initialBar.value, 0.0);
    expect(find.text('0%'), findsOneWidget);

    // 2. Log Set 1 on Exercise 1 (Bench Press)
    expect(find.text('LOG SET 1'), findsOneWidget);
    await tester.tap(find.text('LOG SET 1'));
    await tester.pumpAndSettle();

    // Progress should increase from 0% (1 of 2 sets in 1 of 2 exercises = ~25%)
    final afterSet1Bar = tester.widget<LinearProgressIndicator>(progressBarFinder);
    expect(afterSet1Bar.value, greaterThan(0.0));
    expect(find.text('25%'), findsOneWidget);

    // 3. Log Set 2 on Exercise 1 (Bench Press)
    expect(find.text('LOG SET 2'), findsOneWidget);
    await tester.tap(find.text('LOG SET 2'));
    await tester.pumpAndSettle();

    // Exercise 1 complete: 50% of the entire workout is completed
    final afterSet2Bar = tester.widget<LinearProgressIndicator>(progressBarFinder);
    expect(afterSet2Bar.value, closeTo(0.5, 0.05));
    expect(find.text('50%'), findsOneWidget);

    // 4. PageView Navigation: Swipe to Exercise 2
    // Navigation must NOT corrupt or change the progress bar
    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();

    final afterNavBar = tester.widget<LinearProgressIndicator>(progressBarFinder);
    expect(afterNavBar.value, closeTo(0.5, 0.05), reason: 'PageView navigation must not corrupt progress');
    expect(find.text('50%'), findsOneWidget);

    // Navigate back to Exercise 1
    await tester.drag(find.byType(PageView), const Offset(500, 0));
    await tester.pumpAndSettle();

    final afterNavBackBar = tester.widget<LinearProgressIndicator>(progressBarFinder);
    expect(afterNavBackBar.value, closeTo(0.5, 0.05));
    expect(find.text('50%'), findsOneWidget);

    // 5. Navigate to Exercise 2 and Skip it
    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();

    // Tap more options menu on exercise card
    final moreOptionsFinder = find.byKey(const Key('exercise_more_options_button'));
    if (moreOptionsFinder.evaluate().isNotEmpty) {
      await tester.tap(moreOptionsFinder);
      await tester.pumpAndSettle();

      final skipOption = find.text('Skip Exercise');
      if (skipOption.evaluate().isNotEmpty) {
        await tester.tap(skipOption);
        await tester.pumpAndSettle();

        // 6. Final progress should reach 100% after all exercises are completed/skipped
        final finalBar = tester.widget<LinearProgressIndicator>(progressBarFinder);
        expect(finalBar.value, 1.0, reason: 'Progress should reach 1.0 when all exercises are completed or skipped');
        expect(find.text('100%'), findsOneWidget);
      }
    }
  });
}
