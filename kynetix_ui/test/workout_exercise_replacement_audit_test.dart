import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/workout_split.dart';
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

  testWidgets('Verify replacing an exercise maintains single canonical active list of 6 exercises and displays EXERCISE 3 OF 6', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const ex1 = Exercise(id: 'ex_1', name: 'Bench Press', muscleGroup: 'Chest', type: ExerciseType.barbellCompound, defaultTargetSets: 3);
    const ex2 = Exercise(id: 'ex_2', name: 'Incline Dumbbell Press', muscleGroup: 'Chest', type: ExerciseType.dumbbell, defaultTargetSets: 3);
    const ex3 = Exercise(id: 'ex_3', name: 'Cable Fly', muscleGroup: 'Chest', type: ExerciseType.isolation, defaultTargetSets: 3);
    const ex4 = Exercise(id: 'ex_4', name: 'Triceps Pushdown', muscleGroup: 'Triceps', type: ExerciseType.isolation, defaultTargetSets: 3);
    const ex5 = Exercise(id: 'ex_5', name: 'Overhead Extension', muscleGroup: 'Triceps', type: ExerciseType.isolation, defaultTargetSets: 3);
    const ex6 = Exercise(id: 'ex_6', name: 'Dips', muscleGroup: 'Triceps', type: ExerciseType.bodyweight, defaultTargetSets: 3);

    const replacementEx3 = Exercise(id: 'ex_3_rep', name: 'Pec Deck Fly', muscleGroup: 'Chest', type: ExerciseType.isolation, defaultTargetSets: 3);

    const splitDay = SplitDay(
      weekday: 1,
      name: 'Chest & Triceps Day',
      exercises: [ex1, ex2, ex3, ex4, ex5, ex6],
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

    // Verify initial state: 6 exercises, header EXERCISE 1 OF 6
    expect(find.text('EXERCISE 1 OF 6'), findsOneWidget);

    // Call replacement method directly: replace ex3 (Cable Fly) with replacementEx3 (Pec Deck Fly)
    state.replaceExerciseForTest('ex_3', replacementEx3);
    await tester.pumpAndSettle();

    // Verify after replacement: 6 active exercises, header EXERCISE 3 OF 6
    expect(find.text('EXERCISE 3 OF 6'), findsOneWidget);
    expect(find.text('EXERCISE 3 OF 7'), findsNothing);

    // Verify exercise list count in state
    final activeExercises = state.activeSessionExercisesForTest as List<Exercise>;
    expect(activeExercises.length, equals(6));
    expect(activeExercises.map((e) => e.id).toList(), equals(['ex_1', 'ex_2', 'ex_3_rep', 'ex_4', 'ex_5', 'ex_6']));

    // Undo replacement
    state.undoReplacementForTest('ex_3');
    await tester.pumpAndSettle();

    // Verify after undo: 6 active exercises, header EXERCISE 3 OF 6 with original exercise ex3
    expect(find.text('EXERCISE 3 OF 6'), findsOneWidget);
    final revertedExercises = state.activeSessionExercisesForTest as List<Exercise>;
    expect(revertedExercises.length, equals(6));
    expect(revertedExercises.map((e) => e.id).toList(), equals(['ex_1', 'ex_2', 'ex_3', 'ex_4', 'ex_5', 'ex_6']));
  });
}
