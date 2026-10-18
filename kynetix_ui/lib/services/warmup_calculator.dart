import '../models/workout_session.dart';
import '../models/workout_split.dart';
import '../widgets/barbell_plate_calculator.dart';

/// One generated warm-up set.
class WarmUpStep {
  final double weight;
  final int reps;
  const WarmUpStep(this.weight, this.reps);

  SetEntry toSetEntry() => SetEntry(weight: weight, reps: reps, setType: SetType.warmUp);

  @override
  bool operator ==(Object other) =>
      other is WarmUpStep && other.weight == weight && other.reps == reps;

  @override
  int get hashCode => Object.hash(weight, reps);

  @override
  String toString() => 'WarmUpStep($weight × $reps)';
}

/// Builds a warm-up ramp to a working weight.
///
/// Barbell: empty bar × 10, then 40 % × 8, 60 % × 5, 80 % × 3, each rounded
/// to a loadable plate weight (2.5 kg steps via [BarbellPlateCalculator]).
/// Any step at or under the empty bar is dropped (the bar set covers it),
/// steps that round to the same weight collapse, and nothing reaches the
/// working weight.
///
/// Dumbbells / machines / cables: 40 / 60 / 80 % with no bar, rounded to the
/// rack's step (2 kg or 2.5 kg for dumbbells, 2.5 kg otherwise).
///
/// Bodyweight movements get no ramp.
abstract class WarmUpCalculator {
  static const List<({double pct, int reps})> ramp = [
    (pct: 0.40, reps: 8),
    (pct: 0.60, reps: 5),
    (pct: 0.80, reps: 3),
  ];

  static const double defaultBarKg = 20.0;

  /// The dumbbell step that fits [workingWeight]: 2.5 kg racks when the
  /// working weight sits on a 2.5 grid, otherwise 2 kg racks.
  static double dumbbellIncrementFor(double workingWeight) {
    final onQuarter = ((workingWeight / 2.5) - (workingWeight / 2.5).round()).abs() < 1e-6;
    return onQuarter ? 2.5 : 2.0;
  }

  static List<WarmUpStep> generate({
    required double workingWeight,
    required ExerciseType type,
    double barWeight = defaultBarKg,
  }) {
    if (workingWeight <= 0 || type == ExerciseType.bodyweight) return const [];

    final usesBar = type == ExerciseType.barbellCompound;
    final steps = <WarmUpStep>[];

    if (usesBar) {
      // Too light to ramp: the working weight is the bar (or less).
      if (workingWeight <= barWeight) return const [];
      steps.add(WarmUpStep(barWeight, 10));
      for (final r in ramp) {
        final w = BarbellPlateCalculator.roundToLoadable(
          workingWeight * r.pct,
          barWeightKg: barWeight,
        );
        if (w <= barWeight) continue; // below or equal to the empty bar
        if (w >= workingWeight) continue;
        if (steps.any((s) => s.weight == w)) continue;
        steps.add(WarmUpStep(w, r.reps));
      }
      return steps;
    }

    final inc = type == ExerciseType.dumbbell ? dumbbellIncrementFor(workingWeight) : 2.5;
    for (final r in ramp) {
      final raw = workingWeight * r.pct;
      final w = (raw / inc).round() * inc;
      final rounded = (w * 100).round() / 100.0;
      if (rounded < inc) continue; // lighter than the smallest step
      if (rounded >= workingWeight) continue;
      if (steps.any((s) => s.weight == rounded)) continue;
      steps.add(WarmUpStep(rounded, r.reps));
    }
    return steps;
  }

  /// Best guess at today's working weight: the heaviest working set already
  /// logged today, else last session's top working set, else [fallback].
  static double? suggestWorkingWeight({
    required List<SetEntry> todaySets,
    List<SetEntry> lastSessionSets = const [],
    double? fallback,
  }) {
    double? best(List<SetEntry> sets) {
      final working = sets.where((s) => s.isMainWorkingSet && s.weight > 0);
      if (working.isEmpty) return null;
      return working.map((s) => s.weight).reduce((a, b) => a > b ? a : b);
    }

    return best(todaySets) ?? best(lastSessionSets) ?? (fallback != null && fallback > 0 ? fallback : null);
  }
}
