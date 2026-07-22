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

  testWidgets('Verify Cases A, B, C, D, and E exercise completion behavior', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // Exercise A: 3 working sets, no warmup (Default target 3)
    final exCaseA = const Exercise(
      id: 'ex_case_a',
      name: 'Exercise Case A',
      muscleGroup: 'Chest',
      type: ExerciseType.barbellCompound,
      defaultTargetSets: 3,
    );

    // Exercise B: 1 warmup + 3 working sets (Default target 3)
    final exCaseB = const Exercise(
      id: 'ex_case_b',
      name: 'Exercise Case B',
      muscleGroup: 'Chest',
      type: ExerciseType.dumbbell,
      defaultTargetSets: 3,
    );

    // Exercise C: 1 drop set + 3 working sets (Default target 3)
    final exCaseC = const Exercise(
      id: 'ex_case_c',
      name: 'Exercise Case C',
      muscleGroup: 'Chest',
      type: ExerciseType.cableMachine,
      defaultTargetSets: 3,
    );

    // Exercise D: Barbell compound with 3 prescribed sets
    final exCaseD = const Exercise(
      id: 'ex_case_d',
      name: 'Barbell Prescribed 3',
      muscleGroup: 'Chest',
      type: ExerciseType.barbellCompound,
      defaultTargetSets: 3,
    );

    // Exercise E: Barbell compound with 4 prescribed sets
    final exCaseE = const Exercise(
      id: 'ex_case_e',
      name: 'Barbell Prescribed 4',
      muscleGroup: 'Chest',
      type: ExerciseType.barbellCompound,
      defaultTargetSets: 4,
    );

    final splitDay = SplitDay(
      weekday: 1,
      name: 'Test Day',
      exercises: [exCaseA, exCaseB, exCaseC, exCaseD, exCaseE],
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

    // CASE A: 3 working sets, no warmup -> complete
    print('--- TESTING CASE A ---');
    for (int i = 0; i < 3; i++) {
      await tester.tap(find.text('LOG SET ${i + 1}'));
      await tester.pumpAndSettle();
    }
    final entryA = state.buildEntry(exCaseA);
    print('Case A: isCompleted = ${entryA.isCompleted}, workingSets = ${entryA.completedWorkingSetsCount}, target = ${exCaseA.targetSets}');
    expect(entryA.isCompleted, isTrue);

    // Wait for auto-advance to Exercise B
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();

    // CASE B: 1 warmup + 3 working sets -> complete
    print('--- TESTING CASE B ---');
    await tester.tap(find.text('Warm-up'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('LOG SET 1'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Working'));
    await tester.pumpAndSettle();
    for (int i = 0; i < 3; i++) {
      await tester.tap(find.text('LOG SET ${i + 2}'));
      await tester.pumpAndSettle();
    }
    final entryB = state.buildEntry(exCaseB);
    print('Case B: isCompleted = ${entryB.isCompleted}, workingSets = ${entryB.completedWorkingSetsCount}, target = ${exCaseB.targetSets}');
    expect(entryB.isCompleted, isTrue);

    // Wait for auto-advance to Exercise C
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();

    // CASE C: 1 drop set + 3 working sets -> complete
    print('--- TESTING CASE C ---');
    await tester.tap(find.text('Drop'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('LOG SET 1'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Working'));
    await tester.pumpAndSettle();
    for (int i = 0; i < 3; i++) {
      await tester.tap(find.text('LOG SET ${i + 2}'));
      await tester.pumpAndSettle();
    }
    final entryC = state.buildEntry(exCaseC);
    print('Case C: isCompleted = ${entryC.isCompleted}, workingSets = ${entryC.completedWorkingSetsCount}, target = ${exCaseC.targetSets}');
    expect(entryC.isCompleted, isTrue);

    // Wait for auto-advance to Exercise D
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();

    // CASE D: Barbell compound with 3 prescribed sets -> complete
    print('--- TESTING CASE D ---');
    for (int i = 0; i < 3; i++) {
      await tester.tap(find.text('LOG SET ${i + 1}'));
      await tester.pumpAndSettle();
    }
    final entryD = state.buildEntry(exCaseD);
    print('Case D: isCompleted = ${entryD.isCompleted}, workingSets = ${entryD.completedWorkingSetsCount}, target = ${exCaseD.targetSets}');
    expect(entryD.isCompleted, isTrue);

    // Wait for auto-advance to Exercise E
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();

    // CASE E: Barbell compound with 4 prescribed sets -> requires 4 working sets (3 working sets -> incomplete)
    print('--- TESTING CASE E ---');
    for (int i = 0; i < 3; i++) {
      await tester.tap(find.text('LOG SET ${i + 1}'));
      await tester.pumpAndSettle();
    }
    final entryE_3sets = state.buildEntry(exCaseE);
    print('Case E (3 sets logged): isCompleted = ${entryE_3sets.isCompleted}, workingSets = ${entryE_3sets.completedWorkingSetsCount}, target = ${exCaseE.targetSets}');
    expect(entryE_3sets.isCompleted, isFalse);

    // Log 4th working set
    await tester.tap(find.text('LOG SET 4'));
    await tester.pumpAndSettle();
    final entryE_4sets = state.buildEntry(exCaseE);
    print('Case E (4 sets logged): isCompleted = ${entryE_4sets.isCompleted}, workingSets = ${entryE_4sets.completedWorkingSetsCount}, target = ${exCaseE.targetSets}');
    expect(entryE_4sets.isCompleted, isTrue);

    // Drain pending PR toast timers
    await tester.pump(const Duration(seconds: 5));
  });
}
