import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/models/workout_session.dart';
import 'package:kynetix/screens/workout_session_screen.dart';
import 'package:kynetix/services/workout_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://mock.supabase.co',
      anonKey: 'mock-anon-key',
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await WorkoutService.instance.clearAll();
    WorkoutService.instance.resetReadyForTesting();
    await WorkoutService.instance.init();
  });

  testWidgets('Trace warm-up and working set completion values', (WidgetTester tester) async {
    // Set screen size to ensure all items are visible and hit-testable
    tester.view.physicalSize = const Size(1000, 1500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // Define an exercise with prescription target sets = 4
    final exerciseWith4Sets = Exercise(
      id: 'bench_press_4_sets',
      name: 'Bench Press',
      muscleGroup: 'Chest',
      type: ExerciseType.barbellCompound,
      defaultTargetSets: 4,
    );

    final secondExercise = Exercise(
      id: 'squat_4_sets',
      name: 'Squat',
      muscleGroup: 'Quads',
      type: ExerciseType.barbellCompound,
      defaultTargetSets: 4,
    );

    // SEED HISTORICAL WORKOUT: Bench Press with 1 warm-up set + 4 working sets (5 sets total)
    final historicalSession = WorkoutSession(
      id: 'ws-history-1',
      date: DateTime.now().subtract(const Duration(days: 7)),
      splitDayName: 'Chest Day',
      entries: [
        ExerciseEntry(
          exercise: exerciseWith4Sets,
          sets: const [
            SetEntry(weight: 20.0, reps: 10, setType: SetType.warmUp),
            SetEntry(weight: 60.0, reps: 8, setType: SetType.normal),
            SetEntry(weight: 60.0, reps: 8, setType: SetType.normal),
            SetEntry(weight: 60.0, reps: 8, setType: SetType.normal),
            SetEntry(weight: 60.0, reps: 8, setType: SetType.normal),
          ],
        ),
      ],
    );
    await WorkoutService.instance.saveSession(historicalSession);

    final splitDay = SplitDay(
      weekday: 1,
      name: 'Chest Day',
      exercises: [exerciseWith4Sets, secondExercise],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: WorkoutSessionScreen(
          splitDay: splitDay,
          date: DateTime.now(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final state = tester.state(find.byType(WorkoutSessionScreen)) as dynamic;

    print('--- STEP 0: INITIAL ---');
    await tester.pump();

    // Select "Warm Up" type
    print('--- STEP 1: CHANGE TYPE TO WARM UP ---');
    expect(find.text('Warm-up'), findsOneWidget);
    await tester.tap(find.text('Warm-up'));
    await tester.pumpAndSettle();

    // Log the warm-up set
    print('--- STEP 2: LOG WARM UP SET ---');
    await tester.tap(find.text('LOG SET 1'));
    await tester.pumpAndSettle();

    // Change type back to "W" (Working)
    print('--- STEP 3: CHANGE TYPE TO WORKING ---');
    expect(find.text('Working'), findsOneWidget);
    await tester.tap(find.text('Working'));
    await tester.pumpAndSettle();

    // Log 4 working sets
    for (int i = 0; i < 4; i++) {
      print('--- STEP 4.${i+1}: LOG WORKING SET ${i+1} ---');
      await tester.tap(find.text('LOG SET ${i + 2}'));
      await tester.pumpAndSettle();
    }

    // Wait for the 600ms auto-advance transition to complete
    print('--- WAITING FOR AUTO-ADVANCE ---');
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();

    // Verify auto-advance occurred: selectedIndex should be 1 (second exercise)
    expect(state.selectedIndex, equals(1));

    // Tap on the Bench Press capsule (index 0) to switch back to it and verify its final completed state
    print('--- SWITCHING BACK TO BENCH PRESS ---');
    await tester.tap(find.text('Bench Press').first);
    await tester.pumpAndSettle();
    expect(state.selectedIndex, equals(0));

    // 1. typicalSetsForExercise can still be 5
    final typicalSets = WorkoutService.instance.typicalSetsForExercise(exerciseWith4Sets.id, splitDay.name);
    print('VERIFY: typicalSetsForExercise is $typicalSets');
    expect(typicalSets, equals(5));

    // 2. exercise.targetSets is 4
    print('VERIFY: exercise.targetSets is ${exerciseWith4Sets.targetSets}');
    expect(exerciseWith4Sets.targetSets, equals(4));

    // 3. workingSetsCount is 4
    final entry = state.buildEntry(exerciseWith4Sets);
    final workingSetsCount = entry.completedWorkingSetsCount;
    print('VERIFY: workingSetsCount is $workingSetsCount');
    expect(workingSetsCount, equals(4));

    // 4. entry.isCompleted is true
    print('VERIFY: entry.isCompleted is ${entry.isCompleted}');
    expect(entry.isCompleted, isTrue);

    // 5. Green check icon is true (shown in progress capsules)
    print('VERIFY: Green check is true');
    expect(find.byIcon(Icons.check_circle_rounded), findsAtLeastNWidgets(1));

    // 6. Log Set button remains unlocked for extra sets
    print('VERIFY: Log Set button remains persistent for logging extra sets');
    expect(find.textContaining('LOG SET'), findsAtLeastNWidgets(1));

    // 7. Workout score (completion ratio) for this exercise remains 1.0
    final targetSetsVal = entry.exercise.targetSets;
    final scoreRatio = targetSetsVal > 0 ? entry.completedWorkingSetsCount / targetSetsVal : 1.0;
    print('VERIFY: Exercise score ratio is $scoreRatio');
    expect(scoreRatio, equals(1.0));

    // Remove the warm-up set (it should be index 0 in the list view of Bench Press)
    print('--- STEP 5: REMOVE WARM UP SET ---');
    final removeIcons = find.byIcon(Icons.remove_circle_rounded);
    expect(removeIcons, findsNWidgets(5)); // 1 warm-up + 4 working = 5 sets
    await tester.tap(removeIcons.at(0), warnIfMissed: false); // Remove first set (warm-up)
    await tester.pumpAndSettle();

    // Verify after removing warm-up, it is still complete
    final entryAfterRemoval = state.buildEntry(exerciseWith4Sets);
    print('VERIFY AFTER WARM UP REMOVAL: entry.isCompleted is ${entryAfterRemoval.isCompleted}');
    expect(entryAfterRemoval.isCompleted, isTrue);
    expect(find.textContaining('LOG SET'), findsAtLeastNWidgets(1));

    print('--- STEP 6: VERIFY FINAL STATE ---');
    await tester.pump(const Duration(seconds: 5));
  });
}
