import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/kyno_fitness_snapshot.dart';
import '../models/workout_session.dart';
import '../models/day_log.dart';
import 'workout_service.dart';
import 'profile_service.dart';
import 'user_session_coordinator.dart';
import 'kyno_context_service.dart';
import 'meal_memory.dart';

enum KynoAnalysisIntent {
  strengthPlateau,
  trainingConsistency,
  muscleBuilding,
  proteinAdherence,
  badWorkout,
  weightProgression,
  overtraining,
  broadAudit,
  general,
}

class KynoAnalysisResult {
  final KynoAnalysisIntent intent;
  final String headline;
  final List<KynoInsightItem> insights;
  final List<String> mostLikelyContributors;
  final List<String> recommendedChanges;
  final List<String> watchItems;

  const KynoAnalysisResult({
    required this.intent,
    required this.headline,
    required this.insights,
    this.mostLikelyContributors = const [],
    this.recommendedChanges = const [],
    this.watchItems = const [],
  });
}

/// Central Longitudinal Personal Fitness Analyst + Coach engine.
/// Evaluates multi-week historical workout and nutrition records to reason
/// over progressive overload, plateaus, consistency, and nutrition bottlenecks.
class KynoHistoricalAnalysisService {
  KynoHistoricalAnalysisService._();
  static final KynoHistoricalAnalysisService instance = KynoHistoricalAnalysisService._();

  KynoUserFitnessSnapshot? _cachedSnapshot;
  String? _cachedUserId;
  DateTime? _lastSnapshotTime;

  /// Resets in-memory snapshot on logout or account switch.
  void clearMemory() {
    _cachedSnapshot = null;
    _cachedUserId = null;
    _lastSnapshotTime = null;
  }

  void invalidate() {
    _cachedSnapshot = null;
    _lastSnapshotTime = null;
  }

  /// Classifies user question into specific analysis intent.
  KynoAnalysisIntent classifyIntent(String query) {
    final q = query.toLowerCase().trim();

    if (q.contains('strength') && (q.contains('not') || q.contains('stuck') || q.contains('plateau') || q.contains('increase') || q.contains('flat') || q.contains('stall') || q.contains('why'))) {
      return KynoAnalysisIntent.strengthPlateau;
    }
    if ((q.contains('stuck') || q.contains('plateau') || q.contains('stalled')) && (q.contains('weight') || q.contains('lift') || q.contains('bench') || q.contains('press') || q.contains('squat') || q.contains('curl'))) {
      return KynoAnalysisIntent.strengthPlateau;
    }
    if (q.contains('consisten') || (q.contains('often') && (q.contains('train') || q.contains('workout') || q.contains('gym')))) {
      return KynoAnalysisIntent.trainingConsistency;
    }
    if ((q.contains('muscle') || q.contains('mass') || q.contains('gains') || q.contains('hypertrophy')) && (q.contains('not') || q.contains('why') || q.contains('gain') || q.contains('build'))) {
      return KynoAnalysisIntent.muscleBuilding;
    }
    if (q.contains('protein') && (q.contains('enough') || q.contains('hit') || q.contains('trend') || q.contains('intake') || q.contains('target'))) {
      return KynoAnalysisIntent.proteinAdherence;
    }
    if ((q.contains('bad') || q.contains('weak') || q.contains('poor') || q.contains('terrible') || q.contains('heavy')) && (q.contains('workout') || q.contains('today') || q.contains('session'))) {
      return KynoAnalysisIntent.badWorkout;
    }
    if ((q.contains('should') || q.contains('can')) && (q.contains('increase') || q.contains('add') || q.contains('up') || q.contains('raise')) && (q.contains('weight') || q.contains('kg') || q.contains('load'))) {
      return KynoAnalysisIntent.weightProgression;
    }
    if (q.contains('overtrain') || q.contains('too much') || q.contains('burnout') || q.contains('fried')) {
      return KynoAnalysisIntent.overtraining;
    }
    if (q.contains('what am i doing wrong') || q.contains('audit') || q.contains('what should i change') || q.contains('review my progress')) {
      return KynoAnalysisIntent.broadAudit;
    }

    return KynoAnalysisIntent.general;
  }

  /// Extracts comprehensive multi-window user fitness snapshot.
  KynoUserFitnessSnapshot getFitnessSnapshot({bool forceRefresh = false}) {
    final currentUserId = UserSessionCoordinator.instance.currentUserId;
    final now = DateTime.now();

    if (!forceRefresh &&
        _cachedSnapshot != null &&
        _cachedUserId == currentUserId &&
        _lastSnapshotTime != null &&
        now.difference(_lastSnapshotTime!).inSeconds < 15) {
      return _cachedSnapshot!;
    }

    final p = ProfileService.instance.currentUserProfile;
    final profileName = p?.name.isNotEmpty == true ? p!.name : 'Athlete';
    final profileGoal = p?.goal ?? 'Muscle Building & Strength';
    final profileWeight = p?.weight;
    final targetCalories = p?.weight != null && p!.weight > 0 ? p.weight * 32.0 : 2200.0;
    final targetProtein = p?.weight != null && p!.weight > 0 ? p.weight * 2.0 : 150.0;

    // ── 1. Authoritative Workout Analysis ──────────────────────────────────
    final ws = WorkoutService.instance;
    final allSessions = List<WorkoutSession>.from(ws.sessions);

    // Include the active in-progress draft session if it contains logged sets
    // and is not already represented in ws.sessions for today.
    final draft = ws.draftSession;
    if (draft != null && !draft.isEmpty && draft.entries.any((e) => e.sets.isNotEmpty)) {
      final draftDateKey = '${draft.date.year}-${draft.date.month.toString().padLeft(2, '0')}-${draft.date.day.toString().padLeft(2, '0')}';
      final alreadyPresent = allSessions.any((s) {
        final sKey = '${s.date.year}-${s.date.month.toString().padLeft(2, '0')}-${s.date.day.toString().padLeft(2, '0')}';
        return sKey == draftDateKey && s.splitDayName == draft.splitDayName;
      });
      if (!alreadyPresent) {
        allSessions.add(draft);
      }
    }
    allSessions.sort((a, b) => b.date.compareTo(a.date)); // newest first

    final d14 = now.subtract(const Duration(days: 14));
    final d60 = now.subtract(const Duration(days: 60));

    final sessionsLast14Days = allSessions.where((s) => s.date.isAfter(d14)).toList();
    final sessionsBaseline = allSessions.where((s) => s.date.isAfter(d60) && !s.date.isAfter(d14)).toList();

    final workoutsPerWeek14 = (sessionsLast14Days.length / 2.0);
    final baselineWeeks = 6.5; // ~46 days / 7
    final workoutsPerWeekBase = sessionsBaseline.isNotEmpty ? (sessionsBaseline.length / baselineWeeks) : workoutsPerWeek14;

    int daysSinceLastWorkout = 999;
    if (allSessions.isNotEmpty) {
      daysSinceLastWorkout = now.difference(allSessions.first.date).inDays;
    }

    final recentSessionSummaries = allSessions.take(5).map((s) {
      final dateStr = '${s.date.month}/${s.date.day}';
      final names = s.entries.where((e) => !e.isSkipped && e.sets.isNotEmpty).map((e) => e.exercise.name).toList();
      return '$dateStr ${s.splitDayName}: ${names.take(3).join(", ")} (${s.totalWorkingVolume.toStringAsFixed(0)} kg)';
    }).toList();

    // Group workout entries by exercise to analyze progressive overload & plateaus
    final Map<String, List<ExerciseEntry>> exerciseEntriesMap = {};
    final Map<String, DateTime> exerciseLastDateMap = {};
    for (final session in allSessions) {
      for (final entry in session.entries) {
        if (entry.isSkipped || entry.sets.isEmpty) continue;
        final key = entry.exercise.name.toLowerCase().trim();
        exerciseEntriesMap.putIfAbsent(key, () => []).add(entry);
        exerciseLastDateMap.putIfAbsent(key, () => session.date);
      }
    }

    final Map<String, ExerciseProgressSummary> exerciseSummaries = {};
    final List<String> detectedPlateaus = [];
    final List<String> detectedImprovements = [];

    for (final entryGroup in exerciseEntriesMap.entries) {
      final entries = entryGroup.value; // newest first
      if (entries.isEmpty) continue;

      final canonicalName = entries.first.exercise.name;
      final muscle = entries.first.exercise.muscleGroup;
      final totalSessions = entries.length;

      final recentSetsStr = <String>[];
      final recentWeights = <double>[];
      final recentReps = <int>[];
      final e1rms = <double>[];

      for (final e in entries.take(5)) {
        final top = e.topWorkingSet ?? e.topSet;
        if (top != null) {
          recentWeights.add(top.weight);
          recentReps.add(top.reps);
          recentSetsStr.add('${top.weight.toStringAsFixed(top.weight == top.weight.truncateToDouble() ? 0 : 1)}kg × ${top.reps}');
          if (top.estimatedOneRepMax > 0) {
            e1rms.add(top.estimatedOneRepMax);
          }
        }
      }

      final highestE1rm = e1rms.isNotEmpty ? e1rms.reduce(max) : null;

      // Plateau detection: 3+ consecutive sessions at identical weight and reps
      bool isStalled = false;
      String? stallReason;
      if (recentWeights.length >= 3) {
        final w0 = recentWeights[0];
        final r0 = recentReps[0];
        final w1 = recentWeights[1];
        final r1 = recentReps[1];
        final w2 = recentWeights[2];
        final r2 = recentReps[2];

        if (w0 == w1 && w1 == w2 && r0 == r1 && r1 == r2) {
          isStalled = true;
          stallReason = 'Stalled at ${w0.toStringAsFixed(w0 == w0.truncateToDouble() ? 0 : 1)}kg × $r0 for $totalSessions sessions without rep or load progression';
          detectedPlateaus.add('$canonicalName: $stallReason');
        }
      }

      // Trend detection
      String trend = 'insufficient_data';
      if (e1rms.length >= 3) {
        if (e1rms[0] > e1rms[2] * 1.03) {
          trend = 'improving';
          detectedImprovements.add('$canonicalName: e1RM increased from ${e1rms[2].toStringAsFixed(1)}kg to ${e1rms[0].toStringAsFixed(1)}kg');
        } else if (e1rms[0] < e1rms[2] * 0.97) {
          trend = 'declining';
        } else {
          trend = 'flat';
        }
      } else if (entries.isNotEmpty) {
        trend = 'flat';
      }

      exerciseSummaries[entryGroup.key] = ExerciseProgressSummary(
        exerciseId: entries.first.exercise.id,
        canonicalName: canonicalName,
        muscleGroup: muscle,
        totalSessions: totalSessions,
        recentWorkingSets: recentSetsStr,
        recentWeights: recentWeights,
        recentReps: recentReps,
        e1rmHistory: e1rms,
        highestE1rm: highestE1rm,
        isStalled: isStalled,
        stallReason: stallReason,
        trend: trend,
        lastTrainedDate: exerciseLastDateMap[entryGroup.key],
      );
    }

    // ── 2. Authoritative Nutrition Analysis ────────────────────────────────
    final d7 = now.subtract(const Duration(days: 7));

    final logsLast7 = <DayLog>[];
    final logsLast14 = <DayLog>[];
    int totalLoggedDays = 0;

    double calSum7 = 0.0;
    double proSum7 = 0.0;
    double calSum14 = 0.0;
    double proSum14 = 0.0;
    int lowProDays7 = 0;
    int lowProDays14 = 0;

    DateTime? oldestNutDate;
    DateTime? newestNutDate;

    for (final item in dayLogStore.entries) {
      final date = DateTime.tryParse(item.key);
      if (date == null) continue;
      final l = item.value;

      if (l.allEntries.isNotEmpty || l.totalCaloriesMid > 0) {
        totalLoggedDays++;
        if (oldestNutDate == null || date.isBefore(oldestNutDate)) oldestNutDate = date;
        if (newestNutDate == null || date.isAfter(newestNutDate)) newestNutDate = date;

        final cal = l.totalCaloriesMid;
        final pro = l.totalProteinMid;
        final dayTargetPro = l.targetProtein ?? targetProtein;

        if (date.isAfter(d14)) {
          logsLast14.add(l);
          calSum14 += cal;
          proSum14 += pro;
          if (pro < dayTargetPro * 0.75) {
            lowProDays14++;
          }

          if (date.isAfter(d7)) {
            logsLast7.add(l);
            calSum7 += cal;
            proSum7 += pro;
            if (pro < dayTargetPro * 0.75) {
              lowProDays7++;
            }
          }
        }
      }
    }

    final avgCal7 = logsLast7.isNotEmpty ? calSum7 / logsLast7.length : 0.0;
    final avgPro7 = logsLast7.isNotEmpty ? proSum7 / logsLast7.length : 0.0;
    final avgCal14 = logsLast14.isNotEmpty ? calSum14 / logsLast14.length : 0.0;
    final avgPro14 = logsLast14.isNotEmpty ? proSum14 / logsLast14.length : 0.0;

    final proAdherence14 = targetProtein > 0 ? (avgPro14 / targetProtein) : 1.0;
    final calDelta14 = avgCal14 > 0 ? (avgCal14 - targetCalories) : 0.0;

    final recurring = MealMemory.instance.recurringMeals.map((m) => m.rawInput).toList();

    // ── 3. Unmeasured Variables ────────────────────────────────────────────
    final unmeasured = const [
      'Sleep duration and sleep recovery quality are untracked.',
      'Daily stress levels and subjective fatigue are untracked.',
      'Lifting biomechanics, technique, and tempo are untracked.',
      'Hydration and micronutrient intake are untracked.',
    ];

    final snapshot = KynoUserFitnessSnapshot(
      userId: currentUserId,
      computedAt: now,
      userName: profileName,
      userGoal: profileGoal,
      userWeightKg: profileWeight,
      targetDailyCalories: targetCalories,
      targetDailyProtein: targetProtein,
      totalWorkoutsLogged: allSessions.length,
      workoutsPerWeekLast14Days: workoutsPerWeek14,
      workoutsPerWeekBaseline: workoutsPerWeekBase,
      daysSinceLastWorkout: daysSinceLastWorkout,
      recentWorkoutsSummary: recentSessionSummaries,
      exerciseSummaries: exerciseSummaries,
      detectedPlateaus: detectedPlateaus,
      detectedImprovements: detectedImprovements,
      totalDaysWithMealsLogged: totalLoggedDays,
      avgCaloriesLast7Days: avgCal7,
      avgCaloriesLast14Days: avgCal14,
      avgProteinLast7Days: avgPro7,
      avgProteinLast14Days: avgPro14,
      proteinAdherencePct14Days: proAdherence14,
      lowProteinDaysLast7Days: lowProDays7,
      lowProteinDaysLast14Days: lowProDays14,
      calorieDelta14Days: calDelta14,
      recurringMeals: recurring,
      unmeasuredMetrics: unmeasured,
    );

    _cachedSnapshot = snapshot;
    _cachedUserId = currentUserId;
    _lastSnapshotTime = now;

    final oldestSessionDate = allSessions.isNotEmpty ? allSessions.last.date.toIso8601String() : 'none';
    final newestSessionDate = allSessions.isNotEmpty ? allSessions.first.date.toIso8601String() : 'none';
    final oldestNutritionDate = oldestNutDate != null ? oldestNutDate.toIso8601String() : 'none';
    final newestNutritionDate = newestNutDate != null ? newestNutDate.toIso8601String() : 'none';

    debugPrint('[KYNO_HISTORY]');
    debugPrint('userId=$currentUserId');
    debugPrint('workoutSessionsLoaded=true');
    debugPrint('workoutSessionCount=${allSessions.length}');
    debugPrint('oldestSession=$oldestSessionDate');
    debugPrint('newestSession=$newestSessionDate');

    debugPrint('[KYNO_HISTORY]');
    debugPrint('nutritionDaysLoaded=true');
    debugPrint('nutritionDayCount=$totalLoggedDays');
    debugPrint('oldestNutritionDay=$oldestNutritionDate');
    debugPrint('newestNutritionDay=$newestNutritionDate');

    return snapshot;
  }

  /// Resolves a question using real longitudinal analysis.
  KynoAnalysisResult analyzeQuery(String query) {
    final snapshot = getFitnessSnapshot(forceRefresh: true);
    final intent = classifyIntent(query);
    debugPrint('[KYNO_QUERY]');
    debugPrint('intent=${intent.name}');

    switch (intent) {
      case KynoAnalysisIntent.strengthPlateau:
        return _analyzeStrengthPlateau(snapshot, query);
      case KynoAnalysisIntent.trainingConsistency:
        return _analyzeTrainingConsistency(snapshot);
      case KynoAnalysisIntent.muscleBuilding:
        return _analyzeMuscleBuilding(snapshot);
      case KynoAnalysisIntent.proteinAdherence:
        return _analyzeProteinAdherence(snapshot);
      case KynoAnalysisIntent.badWorkout:
        return _analyzeBadWorkout(snapshot);
      case KynoAnalysisIntent.weightProgression:
        return _analyzeWeightProgression(snapshot, query);
      case KynoAnalysisIntent.overtraining:
        return _analyzeOvertraining(snapshot);
      case KynoAnalysisIntent.broadAudit:
      case KynoAnalysisIntent.general:
        return _analyzeBroadAudit(snapshot);
    }
  }

  // ─── Question-Specific Analyzers ──────────────────────────────────────────

  KynoAnalysisResult _analyzeStrengthPlateau(KynoUserFitnessSnapshot snapshot, String query) {
    debugPrint('[KYNO_ANALYSIS]');
    debugPrint('analysis=strength_plateau');
    debugPrint('training_sessions_used=${snapshot.totalWorkoutsLogged}');
    debugPrint('nutrition_days_used=${snapshot.totalDaysWithMealsLogged}');

    final insights = <KynoInsightItem>[];
    final contributors = <String>[];
    final recommendations = <String>[];
    final watchItems = <String>[];

    // Find the most relevant stalled or queried exercise
    ExerciseProgressSummary? targetSummary;
    final q = query.toLowerCase();

    for (final e in snapshot.exerciseSummaries.values) {
      if (q.contains(e.canonicalName.toLowerCase()) || q.contains(e.exerciseId.toLowerCase())) {
        targetSummary = e;
        break;
      }
    }
    // If not explicitly mentioned, pick an exercise with a detected plateau or the first compound exercise
    if (targetSummary == null && snapshot.detectedPlateaus.isNotEmpty) {
      final firstPlatName = snapshot.detectedPlateaus.first.split(':').first.trim().toLowerCase();
      targetSummary = snapshot.exerciseSummaries[firstPlatName];
    }
    targetSummary ??= snapshot.exerciseSummaries.values.isNotEmpty ? snapshot.exerciseSummaries.values.first : null;

    if (!snapshot.hasSufficientTrainingHistory || targetSummary == null) {
      insights.add(KynoInsightItem(
        type: KynoInformationType.fact,
        title: 'Logged Training History',
        detail: 'You have ${snapshot.totalWorkoutsLogged} recorded workout sessions in total.',
      ));
      insights.add(KynoInsightItem(
        type: KynoInformationType.calculation,
        title: 'Evidence Base',
        detail: 'Insufficient multi-week data to reliably establish whether strength has plateaued.',
      ));
      insights.add(KynoInsightItem(
        type: KynoInformationType.unknown,
        title: 'Longitudinal Trend',
        detail: 'At least 3-4 consistent sessions per exercise are required to detect a true strength plateau.',
      ));
      insights.add(KynoInsightItem(
        type: KynoInformationType.recommendation,
        title: 'Next Steps',
        detail: 'Log your upcoming sessions with exact weights and reps to establish a baseline.',
      ));

      return KynoAnalysisResult(
        intent: KynoAnalysisIntent.strengthPlateau,
        headline: 'Limited training history recorded to diagnose a strength plateau.',
        insights: insights,
        recommendedChanges: ['Log the next 3 workouts consistently to build your progression baseline.'],
      );
    }

    final exName = targetSummary.canonicalName;
    final recentSets = targetSummary.recentWorkingSets;
    final isStalled = targetSummary.isStalled;

    // 1. FACT: Training history for the exercise
    insights.add(KynoInsightItem(
      type: KynoInformationType.fact,
      title: 'Exercise Performance ($exName)',
      detail: 'Recorded ${targetSummary.totalSessions} sessions.\n'
          'Recent logged working sets: ${recentSets.take(4).join(" | ")}.',
    ));

    // 2. FACT: Nutrition history
    insights.add(KynoInsightItem(
      type: KynoInformationType.fact,
      title: 'Nutrition Record (14-Day Average)',
      detail: 'Averaged ${snapshot.avgProteinLast14Days.toStringAsFixed(0)}g protein and ${snapshot.avgCaloriesLast14Days.toStringAsFixed(0)} kcal/day across ${snapshot.totalDaysWithMealsLogged} logged days.',
    ));

    // 3. CALCULATION: Performance & Nutrition Deltas
    final proDeficit = (snapshot.targetDailyProtein - snapshot.avgProteinLast14Days).clamp(0.0, 999.0);
    final proPct = (snapshot.proteinAdherencePct14Days * 100).toInt();

    insights.add(KynoInsightItem(
      type: KynoInformationType.calculation,
      title: 'Longitudinal Math',
      detail: '• Protein adherence: $proPct% (${proDeficit.toStringAsFixed(0)}g below daily ${snapshot.targetDailyProtein.toStringAsFixed(0)}g target on average).\n'
          '• Days below 75% protein target: ${snapshot.lowProteinDaysLast14Days} of last 14 days.\n'
          '• Training frequency: ${snapshot.workoutsPerWeekLast14Days.toStringAsFixed(1)} sessions/week (vs ${snapshot.workoutsPerWeekBaseline.toStringAsFixed(1)} baseline).',
    ));

    // 4. INFERENCE: Root Cause Attribution
    final inferences = <String>[];
    if (isStalled) {
      inferences.add('Performance on $exName has stalled: you have hit the identical load and reps without advancing reps or load.');
      contributors.add('No progressive overload stimulus applied (hitting identical reps/load repeatedly).');
    }

    if (proDeficit > 20.0) {
      inferences.add('Consistently low protein intake ($proPct% of target) is likely restricting myofibrillar protein synthesis and neuromuscular recovery.');
      contributors.add('Consistent protein deficit averaging ${proDeficit.toStringAsFixed(0)}g/day below target.');
    }

    if (snapshot.calorieDelta14Days < -350.0) {
      inferences.add('You are running a substantial calorie deficit (~${snapshot.calorieDelta14Days.abs().toStringAsFixed(0)} kcal below maintenance target), which significantly suppresses strength gain.');
      contributors.add('Steep calorie deficit suppressing maximal strength output.');
    }

    if (snapshot.workoutsPerWeekLast14Days < 2.0) {
      inferences.add('Training frequency has dropped to ${snapshot.workoutsPerWeekLast14Days.toStringAsFixed(1)} sessions/week, causing training stimuli to decay before supercompensation occurs.');
      contributors.add('Insufficient session frequency to maintain neuromuscular adaptation.');
    }

    insights.add(KynoInsightItem(
      type: KynoInformationType.inference,
      title: 'Longitudinal Diagnostic',
      detail: inferences.join('\n\n'),
    ));

    // 5. RECOMMENDATIONS: Actionable Concrete Adjustments
    if (isStalled) {
      final topWeight = targetSummary.recentWeights.isNotEmpty ? targetSummary.recentWeights.first : 20.0;
      final topReps = targetSummary.recentReps.isNotEmpty ? targetSummary.recentReps.first : 8;
      recommendations.add('Rep Progression Rule: In your next session, keep ${topWeight.toStringAsFixed(topWeight == topWeight.truncateToDouble() ? 0 : 1)}kg and aim for ${topReps + 1} to ${topReps + 2} reps on your first working set before attempting to increase the load.');
    }

    if (proDeficit > 15.0) {
      recommendations.add('Protein Consistency: Raise daily intake to at least ${(snapshot.targetDailyProtein * 0.9).toStringAsFixed(0)}g consistently for the next 2-3 weeks to support recovery.');
    }

    recommendations.add('Micro-Loading: If reps are capped, use 0.5kg or 1kg increments rather than forcing a 2.5kg jump.');

    insights.add(KynoInsightItem(
      type: KynoInformationType.recommendation,
      title: 'Action Plan',
      detail: recommendations.map((r) => '• $r').join('\n'),
    ));

    // 6. UNKNOWN: Explicitly State Untracked Parameters
    insights.add(KynoInsightItem(
      type: KynoInformationType.unknown,
      title: 'Untracked Variables',
      detail: 'I do not have sleep data, subjective stress scores, or video lifting technique, so I cannot determine if CNS fatigue or form breakdown are contributing.',
    ));

    watchItems.add('Track reps on set 1 of $exName next session.');
    watchItems.add('Track 7-day average protein adherence.');

    final headline = isStalled
        ? 'Your strength appears to have plateaued on $exName over recent sessions.'
        : 'Analysis of your strength trends and recovery balance:';

    return KynoAnalysisResult(
      intent: KynoAnalysisIntent.strengthPlateau,
      headline: headline,
      insights: insights,
      mostLikelyContributors: contributors,
      recommendedChanges: recommendations,
      watchItems: watchItems,
    );
  }

  KynoAnalysisResult _analyzeTrainingConsistency(KynoUserFitnessSnapshot snapshot) {
    debugPrint('[KYNO_ANALYSIS]');
    debugPrint('analysis=training_consistency');
    debugPrint('training_sessions_used=${snapshot.totalWorkoutsLogged}');
    debugPrint('nutrition_days_used=${snapshot.totalDaysWithMealsLogged}');

    final insights = <KynoInsightItem>[];

    insights.add(KynoInsightItem(
      type: KynoInformationType.fact,
      title: 'Workout Frequency Log',
      detail: 'Total workouts recorded: ${snapshot.totalWorkoutsLogged}.\n'
          'Workouts last 14 days: ${(snapshot.workoutsPerWeekLast14Days * 2).toInt()} sessions (${snapshot.workoutsPerWeekLast14Days.toStringAsFixed(1)} / week).\n'
          'Days since last logged workout: ${snapshot.daysSinceLastWorkout}.',
    ));

    final freqDiff = snapshot.workoutsPerWeekLast14Days - snapshot.workoutsPerWeekBaseline;
    insights.add(KynoInsightItem(
      type: KynoInformationType.calculation,
      title: 'Consistency Trend',
      detail: freqDiff.abs() < 0.3
          ? 'Training frequency has remained steady at ~${snapshot.workoutsPerWeekLast14Days.toStringAsFixed(1)} sessions/week.'
          : freqDiff > 0
              ? 'Training frequency increased by ${freqDiff.toStringAsFixed(1)} sessions/week compared to baseline.'
              : 'Training frequency decreased by ${freqDiff.abs().toStringAsFixed(1)} sessions/week compared to baseline.',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.inference,
      title: 'Consistency Impact',
      detail: snapshot.workoutsPerWeekLast14Days >= 3.0
          ? 'Consistency is sufficient for progressive athletic adaptation.'
          : 'Low workout frequency (< 3 days/week) causes neuromuscular adaptations to detrain between workouts.',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.recommendation,
      title: 'Target Schedule',
      detail: 'Lock in 3 dedicated workout days per week with at least 48 hours recovery between sessions of the same muscle group.',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.unknown,
      title: 'Untracked Life Factors',
      detail: 'Travel, work schedules, and physical fatigue are not recorded in Kynetix.',
    ));

    return KynoAnalysisResult(
      intent: KynoAnalysisIntent.trainingConsistency,
      headline: 'Training consistency analysis over the last 14 days:',
      insights: insights,
    );
  }

  KynoAnalysisResult _analyzeProteinAdherence(KynoUserFitnessSnapshot snapshot) {
    debugPrint('[KYNO_ANALYSIS]');
    debugPrint('analysis=protein_adherence');
    debugPrint('training_sessions_used=${snapshot.totalWorkoutsLogged}');
    debugPrint('nutrition_days_used=${snapshot.totalDaysWithMealsLogged}');

    final insights = <KynoInsightItem>[];

    insights.add(KynoInsightItem(
      type: KynoInformationType.fact,
      title: 'Protein Logs',
      detail: '• 7-Day Average: ${snapshot.avgProteinLast7Days.toStringAsFixed(1)}g / day\n'
          '• 14-Day Average: ${snapshot.avgProteinLast14Days.toStringAsFixed(1)}g / day\n'
          '• Configured Target: ${snapshot.targetDailyProtein.toStringAsFixed(0)}g / day',
    ));

    final deficit = (snapshot.targetDailyProtein - snapshot.avgProteinLast14Days).clamp(0.0, 999.0);
    final pct = (snapshot.proteinAdherencePct14Days * 100).toInt();

    insights.add(KynoInsightItem(
      type: KynoInformationType.calculation,
      title: 'Deficit Analysis',
      detail: deficit <= 5.0
          ? 'Protein target is met consistently ($pct% adherence).'
          : 'Averaging a ${deficit.toStringAsFixed(0)}g deficit ($pct% adherence). Below target on ${snapshot.lowProteinDaysLast14Days} of the last 14 logged days.',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.inference,
      title: 'Physiological Implication',
      detail: deficit <= 10.0
          ? 'Optimal nitrogen balance for muscle tissue repair and hypertrophy.'
          : 'Chronic protein shortfall limits fractional synthetic rate of muscle tissue and delays inter-session recovery.',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.recommendation,
      title: 'Nutrition Strategy',
      detail: deficit <= 10.0
          ? 'Maintain your current daily routine.'
          : 'Anchor 30-40g protein into your first meal of the day, and utilize a convenient source (whey, Greek yogurt, chicken) to close the ${deficit.toStringAsFixed(0)}g gap.',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.unknown,
      title: 'Protein Quality & Timing',
      detail: 'Bioavailability and precise leucine threshold timing per meal are not explicitly tracked.',
    ));

    return KynoAnalysisResult(
      intent: KynoAnalysisIntent.proteinAdherence,
      headline: 'Longitudinal protein intake analysis across recorded meals:',
      insights: insights,
    );
  }

  KynoAnalysisResult _analyzeMuscleBuilding(KynoUserFitnessSnapshot snapshot) {
    return _analyzeStrengthPlateau(snapshot, 'muscle');
  }

  KynoAnalysisResult _analyzeBadWorkout(KynoUserFitnessSnapshot snapshot) {
    final insights = <KynoInsightItem>[];

    insights.add(KynoInsightItem(
      type: KynoInformationType.fact,
      title: 'Recent Sessions',
      detail: snapshot.recentWorkoutsSummary.take(2).join('\n'),
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.fact,
      title: 'Preceding Nutrition',
      detail: 'Averaged ${snapshot.avgCaloriesLast7Days.toStringAsFixed(0)} kcal and ${snapshot.avgProteinLast7Days.toStringAsFixed(0)}g protein over the last 7 days.',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.calculation,
      title: 'Recovery Metrics',
      detail: 'Days since previous session: ${snapshot.daysSinceLastWorkout} days.',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.inference,
      title: 'Contextual Assessment',
      detail: 'Day-to-day performance fluctuations of ±5-10% are standard neuromuscular variance. An isolated low-energy session is normal and does not represent an athletic plateau.',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.unknown,
      title: 'Unmeasured Influences',
      detail: 'Sleep quality, pre-workout hydration, caffeine timing, and occupational stress are not tracked.',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.recommendation,
      title: 'Guidance',
      detail: 'Prioritize restorative sleep tonight and do not reduce weights prematurely based on one session.',
    ));

    return KynoAnalysisResult(
      intent: KynoAnalysisIntent.badWorkout,
      headline: 'Assessment of recent session and recovery context:',
      insights: insights,
    );
  }

  KynoAnalysisResult _analyzeWeightProgression(KynoUserFitnessSnapshot snapshot, String query) {
    return _analyzeStrengthPlateau(snapshot, query);
  }

  KynoAnalysisResult _analyzeOvertraining(KynoUserFitnessSnapshot snapshot) {
    final insights = <KynoInsightItem>[];

    insights.add(KynoInsightItem(
      type: KynoInformationType.fact,
      title: 'Logged Volume & Frequency',
      detail: 'Frequency: ${snapshot.workoutsPerWeekLast14Days.toStringAsFixed(1)} workouts/week.\n'
          'Total sessions: ${snapshot.totalWorkoutsLogged}.',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.calculation,
      title: 'Workload Density',
      detail: snapshot.workoutsPerWeekLast14Days > 5.0
          ? 'High frequency (> 5 sessions/week) logged over the past fortnight.'
          : 'Moderate frequency (${snapshot.workoutsPerWeekLast14Days.toStringAsFixed(1)} sessions/week).',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.inference,
      title: 'Overtraining vs Under-Recovery',
      detail: snapshot.workoutsPerWeekLast14Days < 4.0
          ? 'At ${snapshot.workoutsPerWeekLast14Days.toStringAsFixed(1)} sessions/week, true systemic overtraining is rare. Feeling exhausted is more often caused by inadequate calories, low protein, or poor sleep.'
          : 'High training density with inadequate recovery days may cause systemic fatigue accumulation.',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.unknown,
      title: 'Systemic Fatigue Markers',
      detail: 'Resting heart rate, HRV (heart rate variability), sleep duration, and subjective soreness are untracked.',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.recommendation,
      title: 'Recovery Prescription',
      detail: 'Take 1 full rest day with target calorie intake and evaluate performance in the following workout.',
    ));

    return KynoAnalysisResult(
      intent: KynoAnalysisIntent.overtraining,
      headline: 'Overtraining and systemic fatigue analysis:',
      insights: insights,
    );
  }

  KynoAnalysisResult _analyzeBroadAudit(KynoUserFitnessSnapshot snapshot) {
    debugPrint('[KYNO_ANALYSIS]');
    debugPrint('analysis=broad_audit');
    debugPrint('training_sessions_used=${snapshot.totalWorkoutsLogged}');
    debugPrint('nutrition_days_used=${snapshot.totalDaysWithMealsLogged}');

    final insights = <KynoInsightItem>[];

    insights.add(KynoInsightItem(
      type: KynoInformationType.fact,
      title: 'Longitudinal Overview',
      detail: '• Workouts logged: ${snapshot.totalWorkoutsLogged} (${snapshot.workoutsPerWeekLast14Days.toStringAsFixed(1)}/wk recently)\n'
          '• Nutrition logged: ${snapshot.totalDaysWithMealsLogged} days\n'
          '• 14-day avg protein: ${snapshot.avgProteinLast14Days.toStringAsFixed(0)}g / day\n'
          '• Goal: ${snapshot.userGoal}',
    ));

    final proDeficit = (snapshot.targetDailyProtein - snapshot.avgProteinLast14Days).clamp(0.0, 999.0);
    insights.add(KynoInsightItem(
      type: KynoInformationType.calculation,
      title: 'Adherence Audit',
      detail: '• Protein target deficit: ${proDeficit.toStringAsFixed(0)}g (${(snapshot.proteinAdherencePct14Days * 100).toInt()}% adherence)\n'
          '• Detected plateaus: ${snapshot.detectedPlateaus.length} exercises\n'
          '• Detected improvements: ${snapshot.detectedImprovements.length} exercises',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.inference,
      title: 'Highest-Leverage Opportunities',
      detail: proDeficit > 20.0
          ? 'Your primary bottleneck is protein consistency (${proDeficit.toStringAsFixed(0)}g below target on average). Addressing nutrition will unlock greater return on your training volume.'
          : 'Your nutrition adherence is solid. Focus on progressive overload and hitting top rep targets on primary lifts.',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.unknown,
      title: 'Untracked Variables',
      detail: 'Sleep, stress, and lifting technique are not recorded.',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.recommendation,
      title: 'Prioritized Action Plan',
      detail: '1. Close the daily protein gap to >= 85% adherence.\n2. Ensure double progression is applied (add reps before adding weight).\n3. Maintain consistent 3-4 sessions/week frequency.',
    ));

    return KynoAnalysisResult(
      intent: KynoAnalysisIntent.broadAudit,
      headline: 'Complete longitudinal fitness audit based on your recorded history:',
      insights: insights,
    );
  }
}
