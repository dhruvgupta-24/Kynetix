import '../models/workout_split.dart';
import 'workout_service.dart';
import 'exercise_media_service.dart';

/// Structured, rich progression recommendation produced by Kyno.
class KynoProgressionAdvice {
  final String action; // e.g. "KEEP 70.0 KG" or "INCREASE TO 72.5 KG"
  final String styleLabel; // e.g. "Double Progression"
  final String todayTarget; // e.g. "70.0 kg • 4 sets • 8–10 reps"
  final String summary; // Clear, non-truncated primary coaching recommendation
  final List<String> evidence; // Explicit factual bullet points (reps, volume, history)
  final String nextMilestone; // Explicit criteria to trigger the next progression
  final String confidence; // "High", "Moderate", "Safety Priority", "Deload"
  final bool isDeload;
  final List<double> spark1RmTrend;

  const KynoProgressionAdvice({
    required this.action,
    required this.styleLabel,
    required this.todayTarget,
    required this.summary,
    required this.evidence,
    required this.nextMilestone,
    required this.confidence,
    this.isDeload = false,
    required this.spark1RmTrend,
  });

  /// Formatted weight helper
  static String fmtWeight(double w) =>
      w == w.truncateToDouble() ? '${w.toInt()} kg' : '${w.toStringAsFixed(1)} kg';
}

/// Centralized Personal Progression Recommendation Engine.
/// Derives actionable, multi-session progression guidance from complete app history.
class KynoProgressionEngine {
  KynoProgressionEngine._();
  static final KynoProgressionEngine instance = KynoProgressionEngine._();

  /// Computes personalized progression advice for [exercise] within [splitDayName].
  KynoProgressionAdvice computeAdvice({
    required Exercise exercise,
    required String splitDayName,
  }) {
    final ws = WorkoutService.instance;
    final canonicalId = ExerciseMediaService.instance.getCanonicalId(exercise.id);

    // Retrieve full session history (using canonical ID)
    final history = ws.historyFor(canonicalId, limit: 12);
    final bestEver = ws.bestSetEver(canonicalId);
    final typicalSets = ws.typicalSetsForExercise(canonicalId, splitDayName);
    final lastEntry = ws.lastEntryFor(canonicalId, splitDayName);

    // 1RM sparkline data (reversed to chronological order)
    final sparkData = history.reversed
        .map((h) => h.entry.topWorkingSet?.estimatedOneRepMax ?? h.entry.topSet?.estimatedOneRepMax ?? 0.0)
        .where((v) => v > 0.0)
        .toList();

    // 1. Fatigue & Deload Check (3 consecutive declining sessions)
    if (ws.detectFatigueDecline(canonicalId)) {
      return KynoProgressionAdvice(
        action: 'DELOAD / REDUCE LOAD',
        styleLabel: 'Active Recovery',
        todayTarget: 'Reduce volume by 30–50%',
        summary: 'Fatigue accumulation detected. Your estimated 1RM has steadily declined across your last 3 consecutive sessions.',
        evidence: [
          'Estimated 1RM dropped across the last 3 sessions.',
          'Cumulative nervous system & muscular fatigue detected.',
          if (bestEver != null) 'Lifetime best on this movement is ${KynoProgressionAdvice.fmtWeight(bestEver.weight)} × ${bestEver.reps}.',
        ],
        nextMilestone: 'Complete 1 deload session at 60–70% load to allow systemic recovery before resuming progression.',
        confidence: 'Deload',
        isDeload: true,
        spark1RmTrend: sparkData,
      );
    }

    // 2. Safety Check (High RPE failure or low reps)
    final workingSetsLast = lastEntry?.sets.where((s) => s.isMainWorkingSet).toList() ?? [];
    final hasFailure = workingSetsLast.any((s) => (s.rpe != null && s.rpe! >= 10.0 && s.reps <= 4));
    if (hasFailure && workingSetsLast.isNotEmpty) {
      final curW = workingSetsLast.first.weight;
      return KynoProgressionAdvice(
        action: 'KEEP ${KynoProgressionAdvice.fmtWeight(curW).toUpperCase()}',
        styleLabel: 'Safety & Form Stabilization',
        todayTarget: '${KynoProgressionAdvice.fmtWeight(curW)} • $typicalSets sets • ${exercise.targetRepMin}–${exercise.targetRepMax} reps',
        summary: 'Safety limit triggered. Your last session reached technical failure with very high RPE. Hold load and focus on clean movement mechanics.',
        evidence: [
          'High RPE (10) or technical grind observed on recent set.',
          'Prioritize joint health and neuromuscular stabilization.',
          'Maintain current working weight until reps feel controlled (RPE ≤ 8.5).',
        ],
        nextMilestone: 'Achieve ${exercise.targetRepMin}+ clean reps without reaching absolute mechanical failure.',
        confidence: 'Safety Priority',
        isDeload: false,
        spark1RmTrend: sparkData,
      );
    }

    // 3. Increment calculation
    final increment = exercise.type == ExerciseType.barbellCompound
        ? 2.5
        : exercise.type == ExerciseType.cableMachine
            ? 5.0
            : 2.0;

    // 4. Progression Style Analysis
    final analysis = ws.detectProgressionStyle(canonicalId);
    final styleLabel = (exercise.targetRepMin < exercise.targetRepMax &&
            (analysis.style == ProgressionStyle.fixedWeight || analysis.style == ProgressionStyle.doubleProgression))
        ? 'Double Progression'
        : analysis.style.label;

    // 5. No History Case (First Exposure)
    if (workingSetsLast.isEmpty) {
      if (bestEver != null) {
        return KynoProgressionAdvice(
          action: 'START AT ${KynoProgressionAdvice.fmtWeight(bestEver.weight).toUpperCase()}',
          styleLabel: styleLabel,
          todayTarget: '${KynoProgressionAdvice.fmtWeight(bestEver.weight)} • $typicalSets sets • ${exercise.targetRepMin}–${exercise.targetRepMax} reps',
          summary: 'Re-establishing this exercise. Start at or slightly below your historical best weight to benchmark current strength.',
          evidence: [
            'Lifetime best is ${KynoProgressionAdvice.fmtWeight(bestEver.weight)} × ${bestEver.reps}.',
            'No sets logged in current or immediate prior session for this split day.',
          ],
          nextMilestone: 'Log a solid working set at this weight to calibrate your active progression curve.',
          confidence: 'Moderate',
          isDeload: false,
          spark1RmTrend: sparkData,
        );
      } else {
        return KynoProgressionAdvice(
          action: 'CALIBRATE BASELINE',
          styleLabel: styleLabel,
          todayTarget: '$typicalSets sets • ${exercise.targetRepMin}–${exercise.targetRepMax} reps (Moderate RPE 7-8)',
          summary: 'Use a controlled first session to find a stable working load that allows crisp form across all sets.',
          evidence: [
            'New exercise in active rotation.',
            'Target rep range is ${exercise.targetRepMin}–${exercise.targetRepMax} reps.',
          ],
          nextMilestone: 'Find a weight where you can complete $typicalSets sets leaving 1-2 reps in reserve.',
          confidence: 'Baseline',
          isDeload: false,
          spark1RmTrend: sparkData,
        );
      }
    }

    // 6. Active Progression Logic
    final currentWeight = workingSetsLast.first.weight;
    final topReps = workingSetsLast.first.reps;
    final minReps = exercise.targetRepMin;
    final maxReps = exercise.targetRepMax;

    // Did all working sets reach the top of the rep range?
    final allHitCeiling = workingSetsLast.length >= typicalSets &&
        workingSetsLast.every((s) => s.reps >= maxReps);

    final recentSetsFormatted = workingSetsLast.map((s) => '${KynoProgressionAdvice.fmtWeight(s.weight)} × ${s.reps}').toList();

    if (allHitCeiling) {
      final nextWeight = currentWeight + increment;
      return KynoProgressionAdvice(
        action: 'INCREASE TO ${KynoProgressionAdvice.fmtWeight(nextWeight).toUpperCase()}',
        styleLabel: styleLabel,
        todayTarget: '${KynoProgressionAdvice.fmtWeight(nextWeight)} • $typicalSets sets • $minReps–$maxReps reps',
        summary: 'Target ceiling reached! You achieved $maxReps reps across all $typicalSets working sets at ${KynoProgressionAdvice.fmtWeight(currentWeight)}. Increase load by ${KynoProgressionAdvice.fmtWeight(increment)} today.',
        evidence: [
          'All ${workingSetsLast.length} working sets hit or exceeded target ceiling ($maxReps reps).',
          'Recent sets: ${recentSetsFormatted.join(", ")}.',
          if (bestEver != null) 'Lifetime best: ${KynoProgressionAdvice.fmtWeight(bestEver.weight)} × ${bestEver.reps}.',
        ],
        nextMilestone: 'Achieve at least $minReps reps across all sets at ${KynoProgressionAdvice.fmtWeight(nextWeight)}.',
        confidence: 'High',
        isDeload: false,
        spark1RmTrend: sparkData,
      );
    } else {
      // User is building reps at current load (Double Progression / Standard)
      return KynoProgressionAdvice(
        action: 'KEEP ${KynoProgressionAdvice.fmtWeight(currentWeight).toUpperCase()}',
        styleLabel: styleLabel,
        todayTarget: '${KynoProgressionAdvice.fmtWeight(currentWeight)} • $typicalSets sets • $minReps–$maxReps reps',
        summary: 'Stay at ${KynoProgressionAdvice.fmtWeight(currentWeight)} today. Your recent sessions show you are handling this load well. Focus on bringing later sets up to $maxReps reps before increasing weight.',
        evidence: [
          'Recent performance: ${recentSetsFormatted.join(", ")}.',
          'Top set was $topReps reps, but later sets haven\'t yet reached $maxReps reps.',
          if (bestEver != null) 'Lifetime best: ${KynoProgressionAdvice.fmtWeight(bestEver.weight)} × ${bestEver.reps}.',
          'Target ceiling ($maxReps reps across all sets) has not yet been completed.',
        ],
        nextMilestone: 'Complete all $typicalSets sets at $maxReps reps at ${KynoProgressionAdvice.fmtWeight(currentWeight)} → then increase load.',
        confidence: analysis.confidence >= 0.70 ? 'High' : 'Moderate',
        isDeload: false,
        spark1RmTrend: sparkData,
      );
    }
  }
}
