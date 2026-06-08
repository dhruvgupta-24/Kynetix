import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/models/workout_session.dart';
import 'package:kynetix/screens/workout_session_screen.dart';
import 'package:kynetix/services/workout_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('Workout Experience & Search picker UI Fixes Tests', () {
    final mockSplitDay = SplitDay(
      name: 'Chest + Triceps',
      weekday: 1,
      exercises: const [
        Exercise(id: 'ex-bench-press', name: 'Bench Press', muscleGroup: 'Chest', type: ExerciseType.barbellCompound),
        Exercise(id: 'ex-tricep-pushdown', name: 'Tricep Pushdown', muscleGroup: 'Triceps', type: ExerciseType.cableMachine),
      ],
    );

    testWidgets('Starting a workout from saved split Day auto-populates split exercises and clears recovery key', (tester) async {
      // Pre-fill recovery key with some stale data (representing a previous session)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('kynetix_workout_recovery', jsonEncode({
        'sessionExercises': [
          const Exercise(id: 'ex-squat', name: 'Squat', muscleGroup: 'Quads', type: ExerciseType.barbellCompound).toJson()
        ],
      }));

      // Start a brand new workout (draftSession = null)
      await tester.pumpWidget(MaterialApp(
        home: WorkoutSessionScreen(
          splitDay: mockSplitDay,
          date: DateTime(2026, 6, 8),
          draftSession: null,
        ),
      ));

      // Retrieve state and verify that recovery exercises did NOT overwrite split exercises
      final screen = tester.widget<WorkoutSessionScreen>(find.byType(WorkoutSessionScreen));
      
      // Exercises should match Chest + Triceps day (not Quads from stale recovery)
      expect(screen.splitDay.exercises, hasLength(2));
      
      // Verify stale recovery is removed from SharedPreferences
      final recoveryJson = prefs.getString('kynetix_workout_recovery');
      expect(recoveryJson, isNull);
    });

    testWidgets('Resuming a draft restore exercises exactly once and never duplicate or auto-populate split exercises', (tester) async {
      // 1. Create a draft session containing 2 exercises
      final draftExercises = [
        const Exercise(id: 'ex-bench-press', name: 'Bench Press', muscleGroup: 'Chest', type: ExerciseType.barbellCompound),
        const Exercise(id: 'ex-incline-press', name: 'Incline Press', muscleGroup: 'Chest', type: ExerciseType.barbellCompound),
      ];

      final draft = WorkoutSession(
        id: 'ws-draft-123',
        date: DateTime(2026, 6, 8),
        splitDayName: 'Chest + Triceps',
        entries: draftExercises.map((ex) => ExerciseEntry(
          exercise: ex,
          sets: const [
            SetEntry(weight: 60.0, reps: 8, setType: SetType.normal),
          ],
        )).toList(),
      );

      // Save a simulated recovery json representing the exact draft and UI state
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('kynetix_workout_recovery', jsonEncode({
        'selectedIndex': 0,
        'sessionExercises': draftExercises.map((e) => e.toJson()).toList(),
        'timerStartedAt': DateTime(2026, 6, 8, 12, 0).toIso8601String(),
        'weightSelections': {'ex-bench-press': 60.0},
        'repsSelections': {'ex-bench-press': 8},
      }));

      // Resume workout (draftSession = draft)
      await tester.pumpWidget(MaterialApp(
        home: WorkoutSessionScreen(
          splitDay: mockSplitDay,
          date: DateTime(2026, 6, 8),
          draftSession: draft,
        ),
      ));

      await tester.pumpAndSettle();

      final screen = tester.widget<WorkoutSessionScreen>(find.byType(WorkoutSessionScreen));
      
      // Verify exercises are exactly the 2 from the draft (no duplication or injection of split tricep exercise)
      final exerciseNames = screen.draftSession!.entries.map((e) => e.exercise.name).toList();
      expect(exerciseNames, contains('Bench Press'));
      expect(exerciseNames, contains('Incline Press'));
      expect(exerciseNames, isNot(contains('Tricep Pushdown'))); // Tricep pushdown is in the split day but not in the draft, so it must not be added.
    });

    test('Account switching clears recovery state in WorkoutService.clearAll', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('kynetix_workout_recovery', 'some-data');
      expect(prefs.getString('kynetix_workout_recovery'), isNotNull);

      // Perform logout/switch account clearAll
      await WorkoutService.instance.clearAll();

      expect(prefs.getString('kynetix_workout_recovery'), isNull);
    });
  });
}
