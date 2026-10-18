import '../models/workout_session.dart';
import 'workout_service.dart';

/// Which kind of record a set broke.
enum PrType {
  /// Best estimated one-rep max (the app's headline PR rule).
  e1rm,

  /// Heaviest weight ever moved for exactly this many reps.
  heaviestAtReps,

  /// Most reps ever done at exactly this weight.
  mostRepsAtWeight,
}

extension PrTypeX on PrType {
  String get title => switch (this) {
        PrType.e1rm => 'Estimated 1RM record',
        PrType.heaviestAtReps => 'Heaviest for the reps',
        PrType.mostRepsAtWeight => 'Most reps at this weight',
      };
}

/// The records a set broke, best first, plus the numbers to show.
class PrResult {
  final List<PrType> types;
  final SetEntry set;
  final double? previousE1rm;
  final double? previousWeightAtReps;
  final int? previousRepsAtWeight;

  const PrResult({
    required this.types,
    required this.set,
    this.previousE1rm,
    this.previousWeightAtReps,
    this.previousRepsAtWeight,
  });

  bool get isPr => types.isNotEmpty;
  PrType? get primary => types.isEmpty ? null : types.first;

  static const none = PrResult(types: [], set: SetEntry(weight: 0, reps: 0));
}

/// Classifies a just-logged set against everything that came before it:
/// earlier sessions ([history]) plus the sets already logged today
/// ([earlierToday]), so the third heavy set of a session only celebrates if
/// it beats the first two as well.
///
/// Rules:
/// * Only working sets can be records (warm-ups and drops never are).
/// * Never on the first-ever log of an exercise: with no earlier working set
///   there is nothing to beat (matches [WorkoutService.beatsPreviousBest]).
/// * Rep and weight records need an earlier set at that exact rep count /
///   weight, so a never-tried rep count is not a "record".
abstract class PrClassifier {
  static const double _eps = 0.01;

  static PrResult classify({
    required SetEntry set,
    required Iterable<SetEntry> history,
    Iterable<SetEntry> earlierToday = const [],
  }) {
    if (!set.isMainWorkingSet || set.reps <= 0) return PrResult.none;
    // Timed/cardio sets have no load record semantics.
    if (set.durationSeconds != null) return PrResult.none;

    final prior = [...history, ...earlierToday]
        .where((s) => s.isMainWorkingSet && s.reps > 0 && s.durationSeconds == null)
        .toList();
    if (prior.isEmpty) return PrResult.none;

    final load = _load(set);
    final types = <PrType>[];

    // 1. e1RM: the same rule the rest of the app uses.
    SetEntry? best;
    for (final s in prior) {
      if (best == null || s.estimatedOneRepMax > best.estimatedOneRepMax) best = s;
    }
    if (WorkoutService.beatsPreviousBest(set, best)) types.add(PrType.e1rm);

    // 2. Heaviest at this exact rep count.
    double? prevAtReps;
    for (final s in prior.where((s) => s.reps == set.reps)) {
      final l = _load(s);
      if (prevAtReps == null || l > prevAtReps) prevAtReps = l;
    }
    if (prevAtReps != null && load > prevAtReps + _eps && load > 0) {
      types.add(PrType.heaviestAtReps);
    }

    // 3. Most reps at this exact weight.
    int? prevRepsAtWeight;
    for (final s in prior.where((s) => (_load(s) - load).abs() < _eps)) {
      if (prevRepsAtWeight == null || s.reps > prevRepsAtWeight) prevRepsAtWeight = s.reps;
    }
    if (prevRepsAtWeight != null && set.reps > prevRepsAtWeight) {
      types.add(PrType.mostRepsAtWeight);
    }

    return PrResult(
      types: types,
      set: set,
      previousE1rm: best?.estimatedOneRepMax,
      previousWeightAtReps: prevAtReps,
      previousRepsAtWeight: prevRepsAtWeight,
    );
  }

  /// The load that matters for records: added load on bodyweight movements,
  /// the bar weight otherwise.
  static double _load(SetEntry s) => s.externalLoadKg ?? s.weight;
}
