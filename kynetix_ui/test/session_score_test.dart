import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/workout_session.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/services/session_score.dart';

const _bench = Exercise(
  id: 'bench',
  name: 'Bench Press',
  muscleGroup: 'Chest',
  type: ExerciseType.barbellCompound,
  defaultTargetSets: 3,
  defaultRepMin: 6,
  defaultRepMax: 8,
);
const _row = Exercise(
  id: 'row',
  name: 'Barbell Row',
  muscleGroup: 'Back',
  type: ExerciseType.barbellCompound,
  defaultTargetSets: 3,
  defaultRepMin: 6,
  defaultRepMax: 8,
);
const _plank = Exercise(
  id: 'plank',
  name: 'Plank',
  muscleGroup: 'Core',
  type: ExerciseType.bodyweight,
  defaultTargetSets: 2,
  executionMode: ExerciseExecutionMode.timed,
);
const _run = Exercise(
  id: 'run',
  name: 'Treadmill Run',
  muscleGroup: 'Cardio',
  type: ExerciseType.bodyweight,
  defaultTargetSets: 1,
  executionMode: ExerciseExecutionMode.cardio,
);
const _pullup = Exercise(
  id: 'pullup',
  name: 'Pull-Up',
  muscleGroup: 'Back',
  type: ExerciseType.bodyweight,
  defaultTargetSets: 3,
  defaultRepMin: 6,
  executionMode: ExerciseExecutionMode.bodyweightReps,
);

ExerciseEntry _e(Exercise ex, List<SetEntry> sets, {bool skipped = false}) =>
    ExerciseEntry(exercise: ex, sets: sets, isSkipped: skipped);

SetEntry _w(double kg, int reps) => SetEntry(weight: kg, reps: reps);
SetEntry _bw(int reps) => SetEntry(weight: 0, reps: reps, externalLoadKg: 0);
const _hold = SetEntry(weight: 0, reps: 1, durationSeconds: 60);

WorkoutSession _session(List<ExerciseEntry> entries) =>
    WorkoutSession(id: 'prev', date: DateTime(2026, 11, 1), splitDayName: 'Push', entries: entries);

bool _never(String _, SetEntry _) => false;

void main() {
  group('SetEntry: timed and cardio sets move no kilos', () {
    test('a hold or a run has no volume and no 1RM, whatever weight was stored', () {
      // Older builds saved the weight dial's 40 kg x 10 on planks and runs.
      const oldPlank = SetEntry(weight: 40, reps: 10, durationSeconds: 60);
      const oldRun = SetEntry(weight: 40, reps: 10, distanceMeters: 1000);
      expect(oldPlank.volume, 0);
      expect(oldPlank.estimatedOneRepMax, 0);
      expect(oldRun.volume, 0);
      expect(oldRun.estimatedOneRepMax, 0);
      expect(oldRun.isTimeOrDistance, isTrue);
      expect(_w(100, 5).isTimeOrDistance, isFalse);
    });
  });

  group('progress', () {
    test('timed holds count by sets, not by their 1 "rep"', () {
      final p = SessionScore.progress([_e(_plank, [_hold, _hold])]);
      expect(p, 1.0);
    });

    test('cardio done once is done', () {
      final p = SessionScore.progress([
        _e(_run, [const SetEntry(weight: 0, reps: 1, distanceMeters: 3000)]),
      ]);
      expect(p, 1.0);
    });

    test('short sets only count up to the bottom of the rep range', () {
      // 3 sets of 3 reps against a 6 rep minimum = half done.
      final p = SessionScore.progress([_e(_bench, [_w(100, 3), _w(100, 3), _w(100, 3)])]);
      expect(p, closeTo(0.5, 1e-9));
    });

    test('warm-ups never count and extra sets never pass 100%', () {
      final warm = const SetEntry(weight: 40, reps: 10, setType: SetType.warmUp);
      expect(SessionScore.progress([_e(_bench, [warm, warm, warm])]), 0.0);
      expect(SessionScore.progress([_e(_bench, List.filled(6, _w(100, 8)))]), 1.0);
    });

    test('skipped counts as nothing left to do; empty session is 0', () {
      expect(SessionScore.progress([_e(_bench, const [], skipped: true)]), 1.0);
      expect(SessionScore.progress(const []), 0.0);
    });
  });

  group('score', () {
    test('nothing logged scores 0, even with a bodyweight last session', () {
      final prev = _session([_e(_pullup, [_bw(8), _bw(8), _bw(8)])]);
      final s = SessionScore.compute(entries: [_e(_pullup, const [])], previous: prev, isRecord: _never);
      expect(s.total, 0);
    });

    test('skipping every exercise scores 0, not a free 55', () {
      final s = SessionScore.compute(
        entries: [_e(_bench, const [], skipped: true), _e(_row, const [], skipped: true)],
        previous: null,
        isRecord: _never,
      );
      expect(s.total, 0);
    });

    test('a skipped exercise does not count as done work in the score', () {
      final full = [_w(100, 8), _w(100, 8), _w(100, 8)];
      final s = SessionScore.compute(
        entries: [_e(_bench, full), _e(_row, const [], skipped: true)],
        previous: null,
        isRecord: _never,
      );
      // Bench fully done; the skipped row is left out, not averaged in as done.
      expect(s.plan, 30);
      expect(s.sets, 25);
    });

    test('first session ever: effort follows the plan, not a made-up 2000 kg', () {
      final full = [_w(60, 8), _w(60, 8), _w(60, 8)];
      final s = SessionScore.compute(entries: [_e(_bench, full)], previous: null, isRecord: _never);
      expect(s.effortBasis, EffortBasis.plan);
      expect(s.effort, 30);
      expect(s.total, 85);
    });

    test('matching last time by volume gives full effort; half gives half', () {
      final prev = _session([_e(_bench, [_w(100, 8), _w(100, 8), _w(100, 8)])]);
      final same = SessionScore.compute(
        entries: [_e(_bench, [_w(100, 8), _w(100, 8), _w(100, 8)])],
        previous: prev,
        isRecord: _never,
      );
      expect(same.effortBasis, EffortBasis.volume);
      expect(same.effort, 30);
      final half = SessionScore.compute(
        entries: [_e(_bench, [_w(50, 8), _w(50, 8), _w(50, 8)])],
        previous: prev,
        isRecord: _never,
      );
      expect(half.effort, 15);
    });

    test('bodyweight sessions compare reps with last time', () {
      final prev = _session([_e(_pullup, [_bw(10), _bw(10), _bw(10)])]);
      final s = SessionScore.compute(
        entries: [_e(_pullup, [_bw(10), _bw(10), _bw(10)])],
        previous: prev,
        isRecord: _never,
      );
      expect(s.effortBasis, EffortBasis.reps);
      expect(s.effort, 30);
      expect(s.total, 85);
    });

    test('a record counts once per exercise, like the scoreboard', () {
      final sets = [_w(110, 8), _w(110, 8), _w(110, 8)];
      final s = SessionScore.compute(
        entries: [_e(_bench, sets)],
        previous: null,
        isRecord: (id, set) => id == 'bench',
      );
      expect(s.recordExercises, 1);
      expect(s.records, 5);
    });

    test('three exercises with records reach 100', () {
      final s = SessionScore.compute(
        entries: [
          _e(_bench, [_w(100, 8), _w(100, 8), _w(100, 8)]),
          _e(_row, [_w(80, 8), _w(80, 8), _w(80, 8)]),
          _e(_pullup, [_bw(8), _bw(8), _bw(8)]),
        ],
        previous: null,
        isRecord: (_, _) => true,
      );
      expect(s.total, 100);
    });

    test('a timed-only session can still be fully done', () {
      final s = SessionScore.compute(entries: [_e(_plank, [_hold, _hold])], previous: null, isRecord: _never);
      expect(s.plan, 30);
      expect(s.sets, 25);
      expect(s.total, 85);
    });
  });
}
