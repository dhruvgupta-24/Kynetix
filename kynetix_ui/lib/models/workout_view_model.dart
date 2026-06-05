// ─── WorkoutDashboardViewModel ────────────────────────────────────────────────
//
// Memoized view model for the WorkoutScreen dashboard.
//
// All heavy analytics computations (session iteration, trend calculation,
// PR detection) are performed ONCE in the factory constructor, which is called
// from _WorkoutScreenState._onServiceChange() — i.e., only when WorkoutService
// notifies listeners (a data write), NOT during scroll or build.
//
// Widget build methods read pre-computed fields directly — O(1) field access.
// This ensures 60fps scrolling on lower-end Android devices.

import '../models/workout_session.dart';
import '../models/workout_split.dart';
import '../services/workout_service.dart';
import '../services/recovery_service.dart';

class WorkoutDashboardViewModel {
  // ── Weekly stats ────────────────────────────────────────────────────────────
  final int workoutsThisWeek;
  final double totalVolumeThisWeek;
  final int totalSetsThisWeek;
  final int currentStreak;
  final List<String> musclesThisWeek;
  final int totalPrsAllTime;

  // ── Split completion ─────────────────────────────────────────────────────────
  final Map<String, bool> splitCompletion;
  final int trainingDaysInSplit;      // denominator for the progress ring
  final int completedDaysThisWeek;    // numerator for the progress ring

  // ── Trends (6 weeks) ─────────────────────────────────────────────────────────
  final List<double> volumeTrend;
  final List<int> consistencyTrend;

  // ── PR / highlights ──────────────────────────────────────────────────────────
  final ({String title, String detail})? latestPr;
  final List<String> recentHighlights;

  // ── Recovery ─────────────────────────────────────────────────────────────────
  final RecoveryReport recovery;

  // ── Recent sessions (pre-sliced) ─────────────────────────────────────────────
  final List<WorkoutSession> recentSessions;

  // ── Consistency label ────────────────────────────────────────────────────────
  final String consistencyLabel;

  const WorkoutDashboardViewModel({
    required this.workoutsThisWeek,
    required this.totalVolumeThisWeek,
    required this.totalSetsThisWeek,
    required this.currentStreak,
    required this.musclesThisWeek,
    required this.totalPrsAllTime,
    required this.splitCompletion,
    required this.trainingDaysInSplit,
    required this.completedDaysThisWeek,
    required this.volumeTrend,
    required this.consistencyTrend,
    required this.latestPr,
    required this.recentHighlights,
    required this.recovery,
    required this.recentSessions,
    required this.consistencyLabel,
  });

  // ── Factory ──────────────────────────────────────────────────────────────────
  //
  // Called once per WorkoutService.notifyListeners() event.
  // Never call this inside widget build() methods.

  factory WorkoutDashboardViewModel.from(WorkoutService svc) {
    final completion = svc.splitCompletionThisWeek();
    final trainingDays = svc.trainingDays.length;
    final completedDays = completion.values.where((v) => v).length;

    final recovery = RecoveryService.compute(
      RecoveryInput(sessions: svc.sessions.toList()),
    );

    // Compute total PRs all-time
    int totalPrs = 0;
    for (final session in svc.sessions) {
      for (final entry in session.entries) {
        final top = entry.topProgressionSet ?? entry.topWorkingSet ?? entry.topSet;
        if (top == null) continue;
        final prevBest = svc.bestSetBefore(entry.exercise.id, session.date);
        if (prevBest == null || top.estimatedOneRepMax > prevBest.estimatedOneRepMax + 0.01) {
          totalPrs++;
        }
      }
    }

    return WorkoutDashboardViewModel(
      workoutsThisWeek: svc.workoutsThisWeek,
      totalVolumeThisWeek: svc.totalVolumeThisWeek,
      totalSetsThisWeek: svc.totalSetsThisWeek,
      currentStreak: svc.currentStreak,
      musclesThisWeek: svc.muscleGroupsTrainedThisWeek,
      totalPrsAllTime: totalPrs,
      splitCompletion: completion,
      trainingDaysInSplit: trainingDays,
      completedDaysThisWeek: completedDays,
      volumeTrend: svc.weeklyVolumeTrend(weeks: 6),
      consistencyTrend: svc.weeklyWorkoutCounts(weeks: 6),
      latestPr: svc.latestPersonalBest(),
      recentHighlights: svc.recentImprovementHighlights(limit: 2),
      recovery: recovery,
      recentSessions: svc.recentSessions(limit: 5),
      consistencyLabel: svc.consistencyLabel(),
    );
  }

  // ── Helpers for the progress ring ────────────────────────────────────────────

  /// 0.0–1.0 fraction of this week's training plan completed.
  double get weekCompletionFraction =>
      trainingDaysInSplit == 0 ? 0 : completedDaysThisWeek / trainingDaysInSplit;

  /// Human-readable completion string, e.g. "3 / 5 days".
  String get weekCompletionLabel =>
      '$completedDaysThisWeek / $trainingDaysInSplit days';
}
