import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/exercise_definition.dart';
import 'package:kynetix/models/workout_session.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/services/kyno_coach_planner.dart';

const bench = Exercise(
  id: 'bench_press',
  name: 'Barbell Bench Press',
  muscleGroup: 'Chest',
  type: ExerciseType.barbellCompound,
  defaultRepMin: 6,
  defaultRepMax: 10,
  defaultTargetSets: 3,
);

const pullUp = Exercise(
  id: 'pull_up',
  name: 'Pull-up',
  muscleGroup: 'Back',
  type: ExerciseType.bodyweight,
  defaultRepMin: 6,
  defaultRepMax: 10,
  executionMode: ExerciseExecutionMode.bodyweightReps,
);

final now = DateTime(2026, 10, 19, 18);

/// Sessions newest first; each is a list of (kg, reps).
List<({DateTime date, ExerciseEntry entry})> hist(Exercise ex, List<List<(double, int)>> sessions,
    {int everyDays = 4, bool bw = false}) => [
      for (var i = 0; i < sessions.length; i++)
        (
          date: now.subtract(Duration(days: i * everyDays)),
          entry: ExerciseEntry(exercise: ex, sets: [
            for (final (w, r) in sessions[i])
              bw ? SetEntry(weight: 0, reps: r, externalLoadKg: w) : SetEntry(weight: w, reps: r),
          ]),
        ),
    ];

void main() {
  group('pattern', () {
    test('straight sets below the ceiling: hold the load, add a rep', () {
      final p = KynoCoachPlanner.plan(exercise: bench, now: now, history: hist(bench, [
        [(60, 9), (60, 8), (60, 8)],
        [(60, 8), (60, 8), (60, 7)],
      ]));
      expect(p.pattern, LoadingPattern.straight);
      expect(p.action, CoachAction.addReps);
      expect(p.setsLine, '60×10, 60×9, 60×9');
    });

    test('straight sets at the ceiling: one plate step up, back to the bottom of the range', () {
      final p = KynoCoachPlanner.plan(exercise: bench, now: now, history: hist(bench, [
        [(60, 10), (60, 10), (60, 10)],
      ]));
      expect(p.action, CoachAction.increase);
      expect(p.setsLine, '62.5×6, 62.5×6, 62.5×6');
    });

    test('pyramid: the top set drives, the whole ramp moves up', () {
      final p = KynoCoachPlanner.plan(exercise: bench, now: now, history: hist(bench, [
        [(50, 12), (60, 10), (70, 8)],
        [(50, 12), (60, 10), (70, 7)],
      ]));
      expect(p.pattern, LoadingPattern.pyramid);
      expect(p.action, CoachAction.increase);
      expect(p.setsLine, '52.5×12, 62.5×10, 72.5×8');
    });

    test('reverse pyramid: top set first, back-offs keep their share', () {
      final p = KynoCoachPlanner.plan(exercise: bench, now: now, history: hist(bench, [
        [(80, 6), (72.5, 8), (65, 10)],
        [(80, 5), (72.5, 8), (65, 9)],
      ]));
      expect(p.pattern, LoadingPattern.reversePyramid);
      // Top set at 6 of a 6-8 ceiling band: keep 80, chase 7.
      expect(p.action, CoachAction.addReps);
      expect(p.sets.first.load, 80);
      expect(p.sets.first.reps, 7);
      expect(p.sets[1].load, 72.5);
    });

    test('top set + back-off moves the top set up when it hits the ceiling', () {
      final p = KynoCoachPlanner.plan(exercise: bench, now: now, history: hist(bench, [
        [(90, 8), (75, 10), (75, 10)],
      ]));
      expect(p.pattern, LoadingPattern.topSetBackOff);
      expect(p.action, CoachAction.increase);
      expect(p.sets.first.load, 92.5);
      expect(p.sets[1].load, 77.5); // same ~83% share, rounded to a plate step
    });

    test('bodyweight with a belt progresses the belt load', () {
      final p = KynoCoachPlanner.plan(exercise: pullUp, now: now, history: hist(pullUp, [
        [(10, 10), (10, 10), (10, 10)],
      ], bw: true));
      expect(p.action, CoachAction.increase);
      expect(p.sets.first.label, 'BW+12.5 × 6');
    });

    test('bodyweight without a belt adds reps, then a belt', () {
      final reps = KynoCoachPlanner.plan(exercise: pullUp, now: now, history: hist(pullUp, [
        [(0, 8), (0, 7), (0, 6)],
      ], bw: true));
      expect(reps.action, CoachAction.addReps);
      expect(reps.setsLine, 'BW×9, BW×8, BW×7');
      final belt = KynoCoachPlanner.plan(exercise: pullUp, now: now, history: hist(pullUp, [
        [(0, 12), (0, 12), (0, 12)],
      ], bw: true));
      expect(belt.action, CoachAction.increase);
      expect(belt.headline, contains('belt'));
    });
  });

  test('three declining sessions trigger a 10% deload', () {
    final p = KynoCoachPlanner.plan(exercise: bench, now: now, history: hist(bench, [
      [(70, 6), (70, 5), (70, 5)],
      [(70, 8), (70, 7), (70, 6)],
      [(70, 10), (70, 9), (70, 9)],
    ]));
    expect(p.action, CoachAction.deload);
    expect(p.sets.first.load, 62.5);
  });

  test('a stall over 3+ weeks names a swap for the same muscle', () {
    final library = [
      const ExerciseDefinition(
        id: 'incline_db_press', canonicalName: 'incline dumbbell press', displayName: 'Incline Dumbbell Press',
        category: 'Chest', bodyPart: 'Chest', equipment: 'Dumbbell', equipmentGroup: 'Dumbbell',
        targetMuscle: 'Chest', muscleGroup: 'Chest', secondaryMuscles: [], instructions: [], aliases: [],
        exerciseType: ExerciseType.dumbbell, defaultTargetSets: 3, defaultRepMin: 8, defaultRepMax: 12,
      ),
      const ExerciseDefinition(
        id: 'leg_press', canonicalName: 'leg press', displayName: 'Leg Press',
        category: 'Legs', bodyPart: 'Upper Legs', equipment: 'Machine', equipmentGroup: 'Machine',
        targetMuscle: 'Quads', muscleGroup: 'Legs', secondaryMuscles: [], instructions: [], aliases: [],
        exerciseType: ExerciseType.cableMachine, defaultTargetSets: 3, defaultRepMin: 8, defaultRepMax: 12,
      ),
    ];
    final p = KynoCoachPlanner.plan(
      exercise: bench,
      now: now,
      library: library,
      history: hist(bench, [
        for (var i = 0; i < 6; i++) [(70, 8), (70, 8), (70, 7)],
      ], everyDays: 8),
    );
    expect(p.stalled, isTrue);
    expect(p.swap?.name, 'Incline Dumbbell Press');
  });

  test('a weak session is traced to the food the day before', () {
    final p = KynoCoachPlanner.plan(
      exercise: bench,
      now: now,
      history: hist(bench, [
        [(70, 5), (70, 4), (70, 4)],
        [(70, 8), (70, 8), (70, 7)],
        [(70, 8), (70, 7), (70, 7)],
        [(67.5, 8), (67.5, 8), (67.5, 8)],
      ]),
      dietFor: (d) => d.day == now.day - 1
          ? const DietDay(calories: 1400, protein: 60, calorieTarget: 2400, proteinTarget: 140, logged: true)
          : const DietDay(calories: 2350, protein: 135, calorieTarget: 2400, proteinTarget: 140, logged: true),
      sleepHours: 5.5,
    );
    expect(p.verdict, SessionVerdict.belowPar);
    expect(p.verdictLine, startsWith('Today was below your level'));
    final findings = p.causes.map((c) => c.finding).join(' | ');
    expect(findings, contains('1400 of 2400 kcal the day before'));
    expect(findings, contains('Protein was 60 of 140 g the day before'));
    expect(findings, contains('slept 5.5 h'));
  });

  test('no history asks for a calibration session', () {
    final p = KynoCoachPlanner.plan(exercise: bench, now: now, history: const []);
    expect(p.action, CoachAction.calibrate);
    expect(p.sets, isEmpty);
  });
}
