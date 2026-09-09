import '../models/day_log.dart';
import 'kyno_historical_analysis_service.dart';
import 'user_session_coordinator.dart';

enum KynoInsightSeverity {
  needsAttention,
  coaching,
  progress,
  resolved,
}

class KynoCoachingInsight {
  final String id;
  final String deduplicationKey;
  final KynoInsightSeverity severity;
  final String title;
  final String evidence;
  final String explanation;
  final String recommendation;
  final String datePeriod;
  final DateTime createdAt;
  bool isRead;
  bool isDismissed;
  bool isResolved;

  KynoCoachingInsight({
    required this.id,
    required this.deduplicationKey,
    required this.severity,
    required this.title,
    required this.evidence,
    required this.explanation,
    required this.recommendation,
    required this.datePeriod,
    required this.createdAt,
    this.isRead = false,
    this.isDismissed = false,
    this.isResolved = false,
  });

  String get categoryLabel => switch (severity) {
        KynoInsightSeverity.needsAttention => 'NEEDS ATTENTION',
        KynoInsightSeverity.coaching => 'COACHING',
        KynoInsightSeverity.progress => 'PROGRESS',
        KynoInsightSeverity.resolved => 'RESOLVED',
      };
}

/// In-App Kyno Coaching & Insight Engine.
/// Proactively evaluates the user's historical fitness snapshot to surface high-priority
/// coaching check-ins without push notifications or spam. Strictly user-scoped.
class KynoCoachingInsightService {
  KynoCoachingInsightService._();
  static final KynoCoachingInsightService instance = KynoCoachingInsightService._();

  // In-memory cache keyed by userId
  final Map<String, List<KynoCoachingInsight>> _userInsights = {};
  final Map<String, DateTime> _lastGeneratedTimeByKey = {};

  static const Duration _cooldownDuration = Duration(hours: 24);

  /// Clears in-memory insights on logout or account switch.
  void clearMemory() {
    _userInsights.clear();
    _lastGeneratedTimeByKey.clear();
  }

  /// Returns active coaching insights for the current authenticated user.
  List<KynoCoachingInsight> getActiveInsights({bool forceEvaluate = false}) {
    final userId = UserSessionCoordinator.instance.currentUserId ?? 'local_user';

    if (forceEvaluate || !_userInsights.containsKey(userId)) {
      evaluateInsightsForCurrentUser();
    }

    final list = _userInsights[userId] ?? [];
    return list.where((i) => !i.isDismissed).toList();
  }

  /// Evaluates proactive coaching rules against the user's fitness snapshot.
  List<KynoCoachingInsight> evaluateInsightsForCurrentUser() {
    final userId = UserSessionCoordinator.instance.currentUserId ?? 'local_user';
    final snapshot = KynoHistoricalAnalysisService.instance.getFitnessSnapshot();
    final now = DateTime.now();

    final List<KynoCoachingInsight> existing = _userInsights[userId] ?? [];
    final List<KynoCoachingInsight> newlyGenerated = [];

    // ── Rule 1: Protein Adherence (Yesterday Deficit or Chronic Shortfall) ──
    final yesterday = now.subtract(const Duration(days: 1));
    final yKey = '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
    final yLog = dayLogStore[yKey];
    final yTargetProtein = yLog?.targetProtein ?? snapshot.targetDailyProtein;

    final hasYesterdayLog = yLog != null && (yLog.allEntries.isNotEmpty || yLog.totalProteinMid > 0);
    final isYesterdayLow = hasYesterdayLog && yLog.totalProteinMid < yTargetProtein * 0.75 && yTargetProtein > 0;

    final proDeficitKey = 'rule_protein_deficit_$userId';
    final hasChronicLowProtein = (snapshot.lowProteinDaysLast7Days >= 4 ||
            (snapshot.hasSufficientNutritionHistory && snapshot.proteinAdherencePct14Days < 0.75)) &&
        snapshot.targetDailyProtein > 0;

    if (isYesterdayLow || hasChronicLowProtein) {
      if (_canTrigger(proDeficitKey, now)) {
        if (isYesterdayLow) {
          final yProtein = yLog!.totalProteinMid;
          final yCal = yLog.totalCaloriesMid;
          final yDeficit = (yTargetProtein - yProtein).clamp(0.0, 999.0);

          final insight = KynoCoachingInsight(
            id: 'insight_${now.millisecondsSinceEpoch}_pro',
            deduplicationKey: proDeficitKey,
            severity: KynoInsightSeverity.needsAttention,
            title: 'Yesterday Protein Deficit Check-in',
            evidence: 'YESTERDAY: Protein: ${yProtein.toStringAsFixed(0)}g (Target: ${yTargetProtein.toStringAsFixed(0)}g, Deficit: -${yDeficit.toStringAsFixed(0)}g). Calories: ${yCal.toStringAsFixed(0)} kcal.\n'
                'PATTERN: Below target on ${snapshot.lowProteinDaysLast7Days} of last 7 logged days (7-day avg: ${snapshot.avgProteinLast7Days.toStringAsFixed(0)}g).',
            explanation: 'Protein was significantly below your target yesterday, and this has happened repeatedly this week. Don\'t let it become your normal pattern.',
            recommendation: 'Aim for ~30–40g protein in your next two meals today to restart positive nitrogen balance.',
            datePeriod: 'Yesterday ($yKey)',
            createdAt: now,
          );
          newlyGenerated.add(insight);
        } else {
          final insight = KynoCoachingInsight(
            id: 'insight_${now.millisecondsSinceEpoch}_pro',
            deduplicationKey: proDeficitKey,
            severity: KynoInsightSeverity.needsAttention,
            title: 'Protein Intake Below Target',
            evidence: 'Your protein intake averaged ${snapshot.avgProteinLast14Days.toStringAsFixed(0)}g against your ${snapshot.targetDailyProtein.toStringAsFixed(0)}g daily target. Below target on ${snapshot.lowProteinDaysLast7Days} of the last 7 logged days.',
            explanation: 'This is the most consistent recovery gap in your recent logs. Consistent low protein intake reduces muscle protein synthesis and limits strength adaptation.',
            recommendation: 'Anchor 30-40g protein into your first two meals today and add a protein-dense snack if needed.',
            datePeriod: 'Last 7–14 days',
            createdAt: now,
          );
          newlyGenerated.add(insight);
        }
        _lastGeneratedTimeByKey[proDeficitKey] = now;
      }
    } else if (snapshot.hasSufficientNutritionHistory && snapshot.proteinAdherencePct14Days >= 0.85) {
      // Check if user previously had a protein deficit insight that is now resolved
      final prevProInsight = existing.where((i) => i.deduplicationKey == proDeficitKey && !i.isResolved).firstOrNull;
      if (prevProInsight != null) {
        prevProInsight.isResolved = true;
        final resKey = 'rule_protein_resolved_$userId';
        if (_canTrigger(resKey, now)) {
          final resolvedInsight = KynoCoachingInsight(
            id: 'insight_${now.millisecondsSinceEpoch}_pro_res',
            deduplicationKey: resKey,
            severity: KynoInsightSeverity.resolved,
            title: 'Protein Adherence Recovered',
            evidence: 'Your protein adherence improved to ${(snapshot.proteinAdherencePct14Days * 100).toInt()}% (${snapshot.avgProteinLast14Days.toStringAsFixed(0)}g/day) over the last 14 days.',
            explanation: 'You successfully closed your protein deficit. This provides the amino acid pool needed for optimal muscular recovery.',
            recommendation: 'Maintain your current meal routine into next week.',
            datePeriod: 'Recent 14 days',
            createdAt: now,
          );
          newlyGenerated.add(resolvedInsight);
          _lastGeneratedTimeByKey[resKey] = now;
        }
      }
    }

    // ── Rule 2: Strength Plateau on Key Exercise ────────────────────────────
    for (final plateau in snapshot.detectedPlateaus) {
      final parts = plateau.split(':');
      final exName = parts.first.trim();
      final platKey = 'rule_plateau_${exName.toLowerCase().replaceAll(" ", "_")}_$userId';

      if (_canTrigger(platKey, now)) {
        final insight = KynoCoachingInsight(
          id: 'insight_${now.millisecondsSinceEpoch}_plat_${exName.hashCode.abs()}',
          deduplicationKey: platKey,
          severity: KynoInsightSeverity.coaching,
          title: '$exName Plateau Detected',
          evidence: plateau,
          explanation: 'You have logged the identical load and repetitions across consecutive sessions without rep progression. Progressive overload requires adding reps or load.',
          recommendation: 'For your next session on $exName, keep the same weight and strive to add 1–2 reps on your first working set.',
          datePeriod: 'Recent sessions',
          createdAt: now,
        );
        newlyGenerated.add(insight);
        _lastGeneratedTimeByKey[platKey] = now;
      }
    }

    // ── Rule 3: Positive Progress & Improvement ────────────────────────────
    for (final improvement in snapshot.detectedImprovements) {
      final parts = improvement.split(':');
      final exName = parts.first.trim();
      final impKey = 'rule_progress_${exName.toLowerCase().replaceAll(" ", "_")}_$userId';

      if (_canTrigger(impKey, now)) {
        final insight = KynoCoachingInsight(
          id: 'insight_${now.millisecondsSinceEpoch}_imp_${exName.hashCode.abs()}',
          deduplicationKey: impKey,
          severity: KynoInsightSeverity.progress,
          title: '$exName Progressive Overload',
          evidence: improvement,
          explanation: 'Your estimated 1RM and working set volume on $exName have progressed upwards.',
          recommendation: 'Keep following your double progression target until you hit the top of your rep range.',
          datePeriod: 'Recent workouts',
          createdAt: now,
        );
        newlyGenerated.add(insight);
        _lastGeneratedTimeByKey[impKey] = now;
      }
    }

    // ── Rule 4: Training Consistency Gap ───────────────────────────────────
    final gapKey = 'rule_gap_$userId';
    if (snapshot.hasSufficientTrainingHistory && snapshot.daysSinceLastWorkout >= 5) {
      if (_canTrigger(gapKey, now)) {
        final insight = KynoCoachingInsight(
          id: 'insight_${now.millisecondsSinceEpoch}_gap',
          deduplicationKey: gapKey,
          severity: KynoInsightSeverity.needsAttention,
          title: 'Training Consistency Gap',
          evidence: '${snapshot.daysSinceLastWorkout} days have elapsed since your last recorded workout.',
          explanation: 'Gaps longer than 5-7 days between sessions of the same muscle groups allow neuromuscular adaptations to regress.',
          recommendation: 'Get back into your split today with a standard session. Keep working loads moderate to ease back in.',
          datePeriod: '${snapshot.daysSinceLastWorkout} days',
          createdAt: now,
        );
        newlyGenerated.add(insight);
        _lastGeneratedTimeByKey[gapKey] = now;
      }
    }

    // Merge existing non-duplicates with newly generated
    final Set<String> existingKeys = existing.map((i) => i.deduplicationKey).toSet();
    final combined = List<KynoCoachingInsight>.from(existing);

    for (final n in newlyGenerated) {
      if (!existingKeys.contains(n.deduplicationKey)) {
        combined.insert(0, n);
      }
    }

    _userInsights[userId] = combined;
    return combined.where((i) => !i.isDismissed).toList();
  }

  void markAsRead(String insightId) {
    final userId = UserSessionCoordinator.instance.currentUserId ?? 'local_user';
    final list = _userInsights[userId];
    if (list != null) {
      for (final item in list) {
        if (item.id == insightId) {
          item.isRead = true;
          break;
        }
      }
    }
  }

  void dismissInsight(String insightId) {
    final userId = UserSessionCoordinator.instance.currentUserId ?? 'local_user';
    final list = _userInsights[userId];
    if (list != null) {
      for (final item in list) {
        if (item.id == insightId) {
          item.isDismissed = true;
          break;
        }
      }
    }
  }

  bool _canTrigger(String key, DateTime now) {
    final lastTime = _lastGeneratedTimeByKey[key];
    if (lastTime == null) return true;
    return now.difference(lastTime) > _cooldownDuration;
  }
}
