import '../models/workout_split.dart';
import '../models/workout_session.dart';

/// Represents the current round status in a superset cluster.
class SupersetRoundStatus {
  final String supersetGroupId;
  final List<Exercise> exercises;
  final int currentRound;
  final int totalRounds;
  final int currentExerciseIndexInGroup;
  final bool isCompleted;

  const SupersetRoundStatus({
    required this.supersetGroupId,
    required this.exercises,
    required this.currentRound,
    required this.totalRounds,
    required this.currentExerciseIndexInGroup,
    required this.isCompleted,
  });

  Exercise? get currentExercise =>
      (currentExerciseIndexInGroup >= 0 && currentExerciseIndexInGroup < exercises.length)
          ? exercises[currentExerciseIndexInGroup]
          : null;

  Exercise? get nextExercise {
    if (isCompleted) return null;
    final nextIndex = (currentExerciseIndexInGroup + 1) % exercises.length;
    return exercises[nextIndex];
  }

  String get label => 'Round $currentRound / $totalRounds';
}

/// Superset Round Traversal and Management Engine for Kynetix.
class SupersetFlowService {
  /// Analyzes the active session exercises and calculates round progression for [supersetGroupId].
  static SupersetRoundStatus? getStatusForGroup({
    required String supersetGroupId,
    required List<Exercise> allExercises,
    required Map<String, ExerciseEntry> entriesMap,
  }) {
    final groupExercises = allExercises.where((e) => e.supersetGroupId == supersetGroupId).toList();
    if (groupExercises.isEmpty) return null;

    final maxTargetSets = groupExercises.map((e) => e.targetSets).fold(0, (max, s) => s > max ? s : max);
    if (maxTargetSets == 0) return null;

    // Find the earliest uncompleted round across group exercises
    for (int round = 1; round <= maxTargetSets; round++) {
      for (int i = 0; i < groupExercises.length; i++) {
        final ex = groupExercises[i];
        final entry = entriesMap[ex.id];
        final completedSets = entry?.completedWorkingSetsCount ?? 0;
        if (completedSets < round && completedSets < ex.targetSets && !(entry?.isSkipped ?? false)) {
          return SupersetRoundStatus(
            supersetGroupId: supersetGroupId,
            exercises: groupExercises,
            currentRound: round,
            totalRounds: maxTargetSets,
            currentExerciseIndexInGroup: i,
            isCompleted: false,
          );
        }
      }
    }

    return SupersetRoundStatus(
      supersetGroupId: supersetGroupId,
      exercises: groupExercises,
      currentRound: maxTargetSets,
      totalRounds: maxTargetSets,
      currentExerciseIndexInGroup: groupExercises.length - 1,
      isCompleted: true,
    );
  }
}
