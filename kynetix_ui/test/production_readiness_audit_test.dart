import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/workout_session.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/models/exercise_definition.dart';
import 'package:kynetix/models/workout_history_view_model.dart';
import 'package:kynetix/services/exercise_library_service.dart';
import 'package:kynetix/services/superset_flow_service.dart';
import 'package:kynetix/widgets/barbell_plate_calculator.dart';
import 'package:kynetix/utils/svg_path_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Production Readiness Audit — Data Model & Backward Compatibility', () {
    test('Legacy flat-set JSON deserializes safely into hierarchical logical sets', () {
      final legacyJson = {
        'id': 'legacy-session-001',
        'date': '2025-01-15T10:00:00.000',
        'splitDayName': 'Chest Day',
        'entries': [
          {
            'exercise': {
              'id': 'bench_press',
              'name': 'Barbell Bench Press',
              'muscleGroup': 'Chest',
              'type': 'barbellCompound',
              'targetSets': 3,
            },
            'sets': [
              {'weight': 60.0, 'reps': 10, 'setType': 'warmUp'},
              {'weight': 100.0, 'reps': 8, 'setType': 'normal'},
              {'weight': 100.0, 'reps': 7, 'setType': 'normal'},
              {'weight': 100.0, 'reps': 6, 'setType': 'normal'},
              {'weight': 70.0, 'reps': 5, 'setType': 'dropSet'},
              {'weight': 50.0, 'reps': 6, 'setType': 'dropSet'},
            ],
          }
        ],
      };

      final session = WorkoutSession.fromJson(legacyJson);
      expect(session.entries.length, 1);
      final entry = session.entries.first;

      // 1 Warmup + 3 Working Sets (Set 3 has 2 drops) = 4 logical set groups
      expect(entry.logicalSets.length, 4);
      expect(entry.warmUpSetsCount, 1);
      expect(entry.completedWorkingSetsCount, 3);
      expect(entry.totalPhysicalSetsCount, 6);

      // Verify Set 3 has 2 nested drop sets
      final set3Group = entry.logicalSets[3];
      expect(set3Group.mainSet.weight, 100.0);
      expect(set3Group.mainSet.reps, 6);
      expect(set3Group.subSets.length, 2);
      expect(set3Group.subSets[0].weight, 70.0);
      expect(set3Group.subSets[1].weight, 50.0);

      // Volume Separation
      expect(entry.primaryWorkingVolume, (100 * 8) + (100 * 7) + (100 * 6)); // 2100.0 kg
      expect(entry.dropSetVolume, (70 * 5) + (50 * 6)); // 650.0 kg
      expect(entry.totalStimulusVolume, 2750.0);
      expect(session.totalWorkingSets, 3);
      expect(session.totalPhysicalSets, 6);
    });

    test('Malformed/unknown structure strings in LogicalSetGroup fallback safely', () {
      final json = {
        'mainSet': {'weight': 80.0, 'reps': 8, 'setType': 'normal'},
        'subSets': [
          {'weight': 60.0, 'reps': 5, 'setType': 'dropSet'}
        ],
        'phase': 'work',
        'structure': 'unknown_future_structure_variant',
      };

      final group = LogicalSetGroup.fromJson(json);
      expect(group.structure, SetStructure.dropSet); // Fallback detects non-empty subSets
      expect(group.isWorkingSet, isTrue);
    });

    test('Execution modes (timed, cardio, bodyweight) compute volume and stats accurately', () {
      const plankEx = Exercise(
        id: 'plank',
        name: 'Plank',
        muscleGroup: 'Core',
        type: ExerciseType.bodyweight,
        executionMode: ExerciseExecutionMode.timed,
      );

      final plankEntry = ExerciseEntry(
        exercise: plankEx,
        sets: [
          const SetEntry(weight: 0.0, reps: 1, durationSeconds: 60),
          const SetEntry(weight: 0.0, reps: 1, durationSeconds: 45),
        ],
      );

      expect(plankEntry.completedWorkingSetsCount, 2);
      expect(plankEntry.totalVolume, 0.0); // Timed zero-weight produces 0.0 kg volume

      const weightedPullupEx = Exercise(
        id: 'weighted_pullup',
        name: 'Weighted Pull-Up',
        muscleGroup: 'Back',
        type: ExerciseType.bodyweight,
        executionMode: ExerciseExecutionMode.weightedBodyweight,
      );

      final pullupEntry = ExerciseEntry(
        exercise: weightedPullupEx,
        sets: [
          const SetEntry(weight: 15.0, reps: 8),
          const SetEntry(weight: 15.0, reps: 6),
        ],
      );

      expect(pullupEntry.primaryWorkingVolume, (15.0 * 8) + (15.0 * 6)); // 210.0 kg added load
    });
  });

  group('Production Readiness Audit — Barbell Plate Calculator', () {
    test('Calculates exact symmetrical plates for standard benchmarks', () {
      // 100 kg on 20 kg bar = 40 kg/side -> 25 kg + 15 kg
      final r100 = BarbellPlateCalculator.calculate(targetWeightKg: 100.0);
      expect(r100.isExact, isTrue);
      expect(r100.weightPerSide, 40.0);
      expect(r100.platesPerSide, [25.0, 15.0]);
      expect(r100.summaryText, '25 + 15 kg / side');

      // 60 kg on 20 kg bar = 20 kg/side -> 20 kg
      final r60 = BarbellPlateCalculator.calculate(targetWeightKg: 60.0);
      expect(r60.isExact, isTrue);
      expect(r60.platesPerSide, [20.0]);

      // 142.5 kg on 20 kg bar = 61.25 kg/side -> 25 + 25 + 10 + 1.25
      final r142 = BarbellPlateCalculator.calculate(targetWeightKg: 142.5);
      expect(r142.isExact, isTrue);
      expect(r142.platesPerSide, [25.0, 25.0, 10.0, 1.25]);
    });

    test('Handles sub-bar weight and unreachable decimal remainder gracefully', () {
      // Bar only (20 kg)
      final r20 = BarbellPlateCalculator.calculate(targetWeightKg: 20.0);
      expect(r20.isExact, isTrue);
      expect(r20.platesPerSide, isEmpty);
      expect(r20.summaryText, '20 kg bar only');

      // Unreachable decimal (23.3 kg on 20 kg bar = 1.65 kg/side -> 1.25, remainder 0.4 kg)
      final r23 = BarbellPlateCalculator.calculate(targetWeightKg: 23.3);
      expect(r23.isExact, isFalse);
      expect(r23.remainder, closeTo(0.4, 0.05));
    });

    test('Assigns distinct Olympic color palette', () {
      expect(BarbellPlateCalculator.plateColor(25.0), const Color(0xFFDC2626)); // Red
      expect(BarbellPlateCalculator.plateColor(20.0), const Color(0xFF2563EB)); // Blue
      expect(BarbellPlateCalculator.plateColor(15.0), const Color(0xFFEAB308)); // Yellow
      expect(BarbellPlateCalculator.plateColor(10.0), const Color(0xFF16A34A)); // Green
      expect(BarbellPlateCalculator.plateColor(5.0), const Color(0xFFF1F5F9));  // White
      expect(BarbellPlateCalculator.plateColor(2.5), const Color(0xFF334155));  // Dark Slate
      expect(BarbellPlateCalculator.plateColor(1.25), const Color(0xFF94A3B8)); // Silver
    });
  });

  group('Production Readiness Audit — Superset Flow Traversal Engine', () {
    test('Handles asymmetric target sets across superset partners', () {
      const exA = Exercise(
        id: 'bicep_curl',
        name: 'Bicep Curl',
        muscleGroup: 'Arms',
        type: ExerciseType.isolation,
        defaultTargetSets: 2,
        supersetGroupId: 'ss_arms',
      );

      const exB = Exercise(
        id: 'tricep_pushdown',
        name: 'Tricep Pushdown',
        muscleGroup: 'Arms',
        type: ExerciseType.isolation,
        defaultTargetSets: 3,
        supersetGroupId: 'ss_arms',
      );

      final exercises = [exA, exB];

      // Round 1: Ex A set 1
      var entries = <String, ExerciseEntry>{
        'bicep_curl': ExerciseEntry(exercise: exA, sets: []),
        'tricep_pushdown': ExerciseEntry(exercise: exB, sets: []),
      };
      var status = SupersetFlowService.getStatusForGroup(
        supersetGroupId: 'ss_arms',
        allExercises: exercises,
        entriesMap: entries,
      );
      expect(status!.currentRound, 1);
      expect(status.currentExercise!.id, 'bicep_curl');

      // Round 3: Ex A has 2/2 completed, Ex B has 2/3 completed -> Next is Ex B in Round 3
      entries = <String, ExerciseEntry>{
        'bicep_curl': ExerciseEntry(
          exercise: exA,
          sets: [const SetEntry(weight: 15, reps: 10), const SetEntry(weight: 15, reps: 10)],
        ),
        'tricep_pushdown': ExerciseEntry(
          exercise: exB,
          sets: [const SetEntry(weight: 25, reps: 12), const SetEntry(weight: 25, reps: 12)],
        ),
      };
      status = SupersetFlowService.getStatusForGroup(
        supersetGroupId: 'ss_arms',
        allExercises: exercises,
        entriesMap: entries,
      );
      expect(status!.currentRound, 3);
      expect(status.currentExercise!.id, 'tricep_pushdown'); // Skips Ex A since 2/2 is reached
      expect(status.isCompleted, isFalse);

      // All completed
      entries['tricep_pushdown'] = ExerciseEntry(
        exercise: exB,
        sets: [
          const SetEntry(weight: 25, reps: 12),
          const SetEntry(weight: 25, reps: 12),
          const SetEntry(weight: 25, reps: 12),
        ],
      );
      status = SupersetFlowService.getStatusForGroup(
        supersetGroupId: 'ss_arms',
        allExercises: exercises,
        entriesMap: entries,
      );
      expect(status!.isCompleted, isTrue);
    });
  });

  group('Production Readiness Audit — SvgPathParser Robustness', () {
    test('Safely handles empty and irregular path tokens without throwing', () {
      final emptyPath = SvgPathParser.parse('');
      expect(emptyPath, isNotNull);

      const complexPath = 'M 10 10 H 90 V 90 H 10 Z';
      final path = SvgPathParser.parse(complexPath);
      final bounds = path.getBounds();
      expect(bounds.width, closeTo(80.0, 0.1));
      expect(bounds.height, closeTo(80.0, 0.1));
    });
  });

  group('Production Readiness Audit — Exercise Library & Custom Exercises', () {
    setUpAll(() async {
      await ExerciseLibraryService.instance.initialize();
    });

    test('Case-insensitive multi-token query matches across aliases and equipment', () {
      final results = ExerciseLibraryService.instance.search(query: 'INCLINE DB');
      expect(results.isNotEmpty, isTrue);
      expect(results.any((e) => e.name.toLowerCase().contains('incline')), isTrue);
    });

    test('Custom exercise creation does not mutate built-in catalogue', () {
      final initialCount = ExerciseLibraryService.instance.allDefinitions.length;

      const custom = Exercise(
        id: 'custom_hex_bar_deadlift',
        name: 'Trap Bar Deadlift (Custom)',
        muscleGroup: 'Back',
        type: ExerciseType.barbellCompound,
      );

      ExerciseLibraryService.instance.registerCustomExercises([custom]);

      expect(ExerciseLibraryService.instance.allDefinitions.length, initialCount + 1);
      final found = ExerciseLibraryService.instance.getById('custom_hex_bar_deadlift');
      expect(found, isNotNull);
      expect(found!.name, 'Trap Bar Deadlift (Custom)');

      // Clear customs
      ExerciseLibraryService.instance.registerCustomExercises([]);
      expect(ExerciseLibraryService.instance.allDefinitions.length, initialCount);
    });
  });
}
