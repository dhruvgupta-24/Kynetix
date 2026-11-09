import '../models/workout_session.dart';
import '../models/workout_split.dart';

/// How the "effort" part of a session score was measured.
enum EffortBasis {
  /// Working volume (kg x reps) against last time's.
  volume,

  /// Working reps against last time's (bodyweight, or no kilos either side).
  reps,

  /// Nothing comparable from last time: the planned work done stands in.
  plan,
}

/// The live workout score (0 to 100) and the four parts it is made of.
///
/// | Part     | Max | Measures                                              |
/// |----------|-----|-------------------------------------------------------|
/// | plan     |  30 | sets done x reps reached, per exercise not skipped    |
/// | effort   |  30 | work against last time (see [EffortBasis])            |
/// | sets     |  25 | working sets logged against the target                |
/// | records  |  15 | 5 per exercise with a new best (any set), up to 3     |
///
/// Skipped exercises earn nothing: skipping the whole day scores 0, not
/// "complete". Warm-ups and drop sets never count.
class SessionScoreBreakdown {
  const SessionScoreBreakdown({
    required this.plan,
    required this.effort,
    required this.sets,
    required this.records,
    required this.effortBasis,
    required this.recordExercises,
  });

  static const zero = SessionScoreBreakdown(
    plan: 0,
    effort: 0,
    sets: 0,
    records: 0,
    effortBasis: EffortBasis.plan,
    recordExercises: 0,
  );

  static const planMax = 30;
  static const effortMax = 30;
  static const setsMax = 25;
  static const recordsMax = 15;

  final int plan;
  final int effort;
  final int sets;
  final int records;
  final EffortBasis effortBasis;

  /// Exercises with a new best today (each worth 5, capped at 3).
  final int recordExercises;

  int get total => (plan + effort + sets + records).clamp(0, 100);
}

abstract final class SessionScore {
  /// Timed holds and cardio are judged by sets alone; their "reps" field is
  /// not a rep count.
  static bool _repBased(Exercise e) {
    final m = e.effectiveExecutionMode;
    return m != ExerciseExecutionMode.timed && m != ExerciseExecutionMode.cardio;
  }

  /// How much of one exercise's prescription is done, 0 to 1: the lower of
  /// sets done over target and reps reached (each working set counts up to
  /// the bottom of the rep range). Skipped counts as done for progress.
  static double exerciseCompletion(ExerciseEntry entry) {
    if (entry.isSkipped) return 1.0;
    final target = entry.exercise.targetSets;
    if (target <= 0) return 1.0;
    final setRatio = (entry.completedWorkingSetsCount / target).clamp(0.0, 1.0);
    if (!_repBased(entry.exercise)) return setRatio;
    final repMin = entry.exercise.targetRepMin;
    var repScore = 0.0;
    for (final g in entry.logicalSets) {
      if (!g.isWorkingSet) continue;
      repScore += repMin > 0 ? (g.mainSet.reps / repMin).clamp(0.0, 1.0) : 1.0;
    }
    final repRatio = (repScore / target).clamp(0.0, 1.0);
    return setRatio < repRatio ? setRatio : repRatio;
  }

  /// The session's progress bar, 0 to 1. Skipped exercises count as done
  /// (nothing is left to do on them).
  static double progress(List<ExerciseEntry> entries) {
    if (entries.isEmpty) return 0.0;
    final sum = entries.fold<double>(0, (a, e) => a + exerciseCompletion(e));
    return (sum / entries.length).clamp(0.0, 1.0);
  }

  /// Working reps of rep-based sets (not timed holds or cardio).
  static int workingReps(Iterable<ExerciseEntry> entries) {
    var n = 0;
    for (final e in entries) {
      if (e.isSkipped || !_repBased(e.exercise)) continue;
      for (final g in e.logicalSets) {
        if (g.isWorkingSet && !g.mainSet.isTimeOrDistance) n += g.mainSet.reps;
      }
    }
    return n;
  }

  /// Scores the session so far. [isRecord] says whether a working set of
  /// an exercise beats every earlier session's best for it.
  static SessionScoreBreakdown compute({
    required List<ExerciseEntry> entries,
    WorkoutSession? previous,
    required bool Function(String exerciseId, SetEntry set) isRecord,
  }) {
    final active = entries.where((e) => !e.isSkipped).toList();
    final anyWork = active.any((e) => e.completedWorkingSetsCount > 0);
    if (active.isEmpty || !anyWork) return SessionScoreBreakdown.zero;

    final planRatio =
        active.fold<double>(0, (a, e) => a + exerciseCompletion(e)) / active.length;

    var setsRatio = 0.0;
    for (final e in active) {
      final target = e.exercise.targetSets > 0 ? e.exercise.targetSets : 3;
      setsRatio += (e.completedWorkingSetsCount / target).clamp(0.0, 1.0);
    }
    setsRatio /= active.length;

    // Effort: like for like with last time.
    final curVolume = active.fold<double>(0, (a, e) => a + e.primaryWorkingVolume);
    final prevEntries = previous?.entries.where((e) => !e.isSkipped).toList() ?? const <ExerciseEntry>[];
    final prevVolume = prevEntries.fold<double>(0, (a, e) => a + e.primaryWorkingVolume);
    final curReps = workingReps(active);
    final prevReps = workingReps(prevEntries);
    EffortBasis basis;
    double effortRatio;
    if (curVolume > 0 && prevVolume > 0) {
      basis = EffortBasis.volume;
      effortRatio = curVolume / prevVolume;
    } else if (curReps > 0 && prevReps > 0) {
      basis = EffortBasis.reps;
      effortRatio = curReps / prevReps;
    } else {
      basis = EffortBasis.plan;
      effortRatio = planRatio;
    }

    var recordExercises = 0;
    for (final e in active) {
      final hit = e.logicalSets.any((g) => g.isWorkingSet && isRecord(e.exercise.id, g.mainSet));
      if (hit) recordExercises++;
    }

    return SessionScoreBreakdown(
      plan: (planRatio * SessionScoreBreakdown.planMax).round(),
      effort: (effortRatio.clamp(0.0, 1.0) * SessionScoreBreakdown.effortMax).round(),
      sets: (setsRatio * SessionScoreBreakdown.setsMax).round(),
      records: (recordExercises * 5).clamp(0, SessionScoreBreakdown.recordsMax),
      effortBasis: basis,
      recordExercises: recordExercises,
    );
  }
}
