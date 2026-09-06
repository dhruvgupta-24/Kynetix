import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/models/workout_session.dart';
import 'package:kynetix/services/superset_flow_service.dart';

void main() {
  group('SupersetFlowService Tests', () {
    const exA = Exercise(
      id: 'ex-a',
      name: 'Bench Press',
      muscleGroup: 'Chest',
      type: ExerciseType.barbellCompound,
      defaultTargetSets: 3,
      supersetGroupId: 'SS_CHEST_BACK',
    );

    const exB = Exercise(
      id: 'ex-b',
      name: 'Barbell Row',
      muscleGroup: 'Back',
      type: ExerciseType.barbellCompound,
      defaultTargetSets: 3,
      supersetGroupId: 'SS_CHEST_BACK',
    );

    test('initial superset status starts at Round 1 with Exercise A', () {
      final status = SupersetFlowService.getStatusForGroup(
        supersetGroupId: 'SS_CHEST_BACK',
        allExercises: [exA, exB],
        entriesMap: {},
      );

      expect(status, isNotNull);
      expect(status!.currentRound, equals(1));
      expect(status.totalRounds, equals(3));
      expect(status.currentExercise?.id, equals('ex-a'));
      expect(status.nextExercise?.id, equals('ex-b'));
      expect(status.isCompleted, isFalse);
    });

    test('after completing 1 set of Exercise A, advances to Exercise B in Round 1', () {
      final entryA = ExerciseEntry(
        exercise: exA,
        sets: [const SetEntry(weight: 80, reps: 8)],
      );

      final status = SupersetFlowService.getStatusForGroup(
        supersetGroupId: 'SS_CHEST_BACK',
        allExercises: [exA, exB],
        entriesMap: {'ex-a': entryA},
      );

      expect(status, isNotNull);
      expect(status!.currentRound, equals(1));
      expect(status.currentExercise?.id, equals('ex-b'));
      expect(status.nextExercise?.id, equals('ex-a'));
      expect(status.isCompleted, isFalse);
    });

    test('after completing 1 set of each, advances to Round 2 Exercise A', () {
      final entryA = ExerciseEntry(
        exercise: exA,
        sets: [const SetEntry(weight: 80, reps: 8)],
      );
      final entryB = ExerciseEntry(
        exercise: exB,
        sets: [const SetEntry(weight: 70, reps: 8)],
      );

      final status = SupersetFlowService.getStatusForGroup(
        supersetGroupId: 'SS_CHEST_BACK',
        allExercises: [exA, exB],
        entriesMap: {'ex-a': entryA, 'ex-b': entryB},
      );

      expect(status, isNotNull);
      expect(status!.currentRound, equals(2));
      expect(status.currentExercise?.id, equals('ex-a'));
      expect(status.isCompleted, isFalse);
    });

    test('after completing all 3 sets of each, marks superset as completed', () {
      final entryA = ExerciseEntry(
        exercise: exA,
        sets: [
          const SetEntry(weight: 80, reps: 8),
          const SetEntry(weight: 80, reps: 8),
          const SetEntry(weight: 80, reps: 8),
        ],
      );
      final entryB = ExerciseEntry(
        exercise: exB,
        sets: [
          const SetEntry(weight: 70, reps: 8),
          const SetEntry(weight: 70, reps: 8),
          const SetEntry(weight: 70, reps: 8),
        ],
      );

      final status = SupersetFlowService.getStatusForGroup(
        supersetGroupId: 'SS_CHEST_BACK',
        allExercises: [exA, exB],
        entriesMap: {'ex-a': entryA, 'ex-b': entryB},
      );

      expect(status, isNotNull);
      expect(status!.isCompleted, isTrue);
    });
  });
}
