import '../models/workout_session.dart';
import '../models/workout_split.dart';
import 'superset_flow_service.dart';

/// What the session should do after a set lands in a superset.
class SupersetStep {
  /// Exercise to move to next (null = stay put / group finished).
  final Exercise? goTo;

  /// True when the lifter is mid-round: go straight to the next exercise,
  /// no rest. Rest runs once a round is closed.
  final bool skipRest;

  const SupersetStep({this.goTo, this.skipRest = false});

  static const stay = SupersetStep();
}

/// Superset traversal: A1 → B1 (no rest) → rest → A2 → B2 → rest …
abstract class SupersetAdvance {
  static SupersetStep afterSet({
    required Exercise logged,
    required List<Exercise> allExercises,
    required Map<String, ExerciseEntry> entriesMap,
  }) {
    final groupId = logged.supersetGroupId;
    if (groupId == null || groupId.isEmpty) return SupersetStep.stay;

    final status = SupersetFlowService.getStatusForGroup(
      supersetGroupId: groupId,
      allExercises: allExercises,
      entriesMap: entriesMap,
    );
    if (status == null || status.isCompleted) return SupersetStep.stay;

    // The earliest unfinished slot is where the lifter goes next.
    final target = status.currentExercise;
    if (target == null || target.id == logged.id) return SupersetStep.stay;

    final loggedIdx = status.exercises.indexWhere((e) => e.id == logged.id);
    // Moving forward inside the group keeps the round going: no rest.
    // Wrapping back to an earlier exercise starts a new round: rest first.
    final midRound = loggedIdx != -1 && status.currentExerciseIndexInGroup > loggedIdx;
    return SupersetStep(goTo: target, skipRest: midRound);
  }
}
