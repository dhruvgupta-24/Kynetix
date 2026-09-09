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
import 'kyno_meal_drilldown_service.dart';

enum KynoAnalysisIntent {
  strengthPlateau,
  trainingConsistency,
  muscleBuilding,
  proteinAdherence,
  badWorkout,
  weightProgression,
  overtraining,
  broadAudit,
  yesterdayNutrition,
  historicalMealQuery,
  lateNightEating,
  weightGain,
  bodyComposition,
  fatLossPlateau,
  recoveryAssessment,
  dietAdjustment,
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

    // 1. Late Night Eating (e.g. "Did I eat anything late last night?", "late snack")
    final hasLateWord = RegExp(r'\blate\b').hasMatch(q);
    final hasEatWord = RegExp(r'\b(eat|ate|eating|food|snack)\b').hasMatch(q);
    if ((hasLateWord && (q.contains('night') || hasEatWord)) ||
        q.contains('late night') ||
        q.contains('midnight snack')) {
      return KynoAnalysisIntent.lateNightEating;
    }

    // 2. Historical Meal Query (e.g. "What did I eat yesterday?", "list what I ate")
    if (q.contains('what did i eat') ||
        q.contains('what i ate') ||
        q.contains('list my meals') ||
        q.contains('meals yesterday') ||
        (q.contains('what') && hasEatWord && q.contains('yesterday'))) {
      return KynoAnalysisIntent.historicalMealQuery;
    }

    // 3. Yesterday Nutrition / Calorie breakdown (e.g. "Why were my calories high yesterday?", "How was my nutrition yesterday?", "Why was my diet bad yesterday?")
    if (q.contains('yesterday') &&
        (q.contains('nutrition') || q.contains('calorie') || q.contains('calories') || q.contains('food') || q.contains('diet') || q.contains('macro') || q.contains('macros') || q.contains('bad') || q.contains('eating'))) {
      return KynoAnalysisIntent.yesterdayNutrition;
    }

    // 4. Body Composition / Belly Fat / Spot Reduction
    // e.g. "Why is my belly not reducing?", "How to lose belly fat?", "Why is my stomach not shrinking?"
    if (q.contains('belly') ||
        q.contains('stomach') ||
        q.contains('waist') ||
        q.contains('love handle') ||
        q.contains('midsection') ||
        q.contains('visceral fat') ||
        q.contains('spot reduc') ||
        q.contains('abs') ||
        q.contains('abdominal') ||
        q.contains('crunches') ||
        ((q.contains('lose') || q.contains('burn') || q.contains('shed') || q.contains('drop') || q.contains('cut') || q.contains('reduce')) &&
            (q.contains('fat') || q.contains('body fat')) &&
            !q.contains('weight'))) {
      return KynoAnalysisIntent.bodyComposition;
    }

    // 5. Weight Loss Plateau / Stall (e.g. "Why am I not losing weight?", "Why is the scale not moving?", "Why is my weight plateauing?")
    final isLiftingExercise = q.contains('bench') ||
        q.contains('press') ||
        q.contains('squat') ||
        q.contains('deadlift') ||
        q.contains('curl') ||
        q.contains('lift') ||
        q.contains('strength') ||
        q.contains('dumbbell') ||
        q.contains('barbell') ||
        q.contains('overhead');

    if ((q.contains('not') || q.contains('cant') || q.contains("can't") || q.contains('stuck') || q.contains('plateau') || q.contains('stall') || q.contains('why') || q.contains('stop')) &&
        (q.contains('losing weight') ||
            q.contains('lose weight') ||
            q.contains('dropping weight') ||
            q.contains('drop weight') ||
            q.contains('shedding weight') ||
            (q.contains('weight') && (q.contains('plateau') || q.contains('stuck') || q.contains('stall')) && !isLiftingExercise) ||
            (q.contains('scale') && (q.contains('move') || q.contains('drop') || q.contains('budge') || q.contains('down') || q.contains('stuck') || q.contains('plateau'))))) {
      return KynoAnalysisIntent.fatLossPlateau;
    }

    // 6. Weight Gain (e.g. "Why am I gaining weight?")
    if ((q.contains('gain') || q.contains('gaining') || q.contains('heavier') || q.contains('put on')) &&
        (q.contains('weight') || q.contains('scale') || q.contains('mass')) &&
        (q.contains('why') || q.contains('reason') || q.contains('am i'))) {
      return KynoAnalysisIntent.weightGain;
    }

    // 7. Protein Adherence (e.g. "Why am I not hitting protein?", "Am I eating enough protein?")
    if (q.contains('protein') &&
        (q.contains('enough') || q.contains('hit') || q.contains('trend') || q.contains('intake') || q.contains('target') || q.contains('not') || q.contains('miss') || q.contains('low') || q.contains('why'))) {
      return KynoAnalysisIntent.proteinAdherence;
    }

    // 8. Recovery Assessment (e.g. "How is my recovery?", "Am I recovered?", "How is my fatigue?")
    if ((q.contains('recover') || q.contains('readiness') || q.contains('fatigue') || q.contains('soreness') || q.contains('sore')) &&
        (q.contains('how') || q.contains('my') || q.contains('status') || q.contains('am i') || q.contains('ready') || q.contains('rest') || q.contains('state') || q.contains('check'))) {
      return KynoAnalysisIntent.recoveryAssessment;
    }

    // 9. Diet Adjustment (e.g. "What should I change about my diet?", "How can I improve my nutrition?", "How can I fix my food intake?")
    if ((q.contains('what should i change') || q.contains('what to change') || q.contains('how should i change') || q.contains('how can i improve') || q.contains('fix my') || q.contains('adjust my') || q.contains('fix') || q.contains('adjust') || q.contains('change')) &&
        (q.contains('diet') || q.contains('nutrition') || q.contains('eating') || q.contains('food') || q.contains('macros') || q.contains('food intake') || q.contains('meal plan') || q.contains('intake'))) {
      return KynoAnalysisIntent.dietAdjustment;
    }

    // 10. Strength Plateau & Performance (e.g. "Why am I not getting stronger?", "Why is my bench stuck?", "Why am I plateauing on bench press?")
    if ((q.contains('strength') || q.contains('stronger') || q.contains('strong')) &&
        (q.contains('not') || q.contains('why') || q.contains('stuck') || q.contains('plateau') || q.contains('stall') || q.contains('increase') || q.contains('flat') || q.contains('gain') || q.contains('cant') || q.contains("can't"))) {
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
    if ((q.contains('bad') || q.contains('weak') || q.contains('poor') || q.contains('terrible') || q.contains('heavy')) && (q.contains('workout') || q.contains('today') || q.contains('session'))) {
      return KynoAnalysisIntent.badWorkout;
    }
    if ((q.contains('should') || q.contains('can')) && (q.contains('increase') || q.contains('add') || q.contains('up') || q.contains('raise')) && (q.contains('weight') || q.contains('kg') || q.contains('load'))) {
      return KynoAnalysisIntent.weightProgression;
    }
    if (q.contains('overtrain') || q.contains('too much') || q.contains('burnout') || q.contains('fried')) {
      return KynoAnalysisIntent.overtraining;
    }
    if (q.contains('what am i doing wrong') || q.contains('audit') || q.contains('what should i change') || q.contains('review my progress') || q.contains('hurting my progress') || q.contains('holding me back')) {
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
    // Strict date-window contract: Longitudinal multi-day metrics evaluate completed
    // calendar days ending yesterday midnight [todayMidnight - 14 days, todayMidnight).
    // Today's partial day data is intentionally excluded from multi-day rolling averages
    // to prevent incomplete day logging from skewing 14-day daily averages.
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final windowStart14 = todayMidnight.subtract(const Duration(days: 14));
    final windowStart7 = todayMidnight.subtract(const Duration(days: 7));

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

        // Completed days window: [todayMidnight - 14 days, todayMidnight)
        if (!date.isBefore(windowStart14) && date.isBefore(todayMidnight)) {
          logsLast14.add(l);
          calSum14 += cal;
          proSum14 += pro;
          if (pro < dayTargetPro * 0.75) {
            lowProDays14++;
          }

          if (!date.isBefore(windowStart7)) {
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

    // Fallback: If user has 0 completed days (e.g. Day 1 user logging today),
    // evaluate available logs so they are not left with an empty snapshot.
    if (logsLast14.isEmpty && dayLogStore.isNotEmpty) {
      for (final item in dayLogStore.entries) {
        final date = DateTime.tryParse(item.key);
        if (date == null) continue;
        final l = item.value;
        if (l.allEntries.isNotEmpty || l.totalCaloriesMid > 0) {
          final cal = l.totalCaloriesMid;
          final pro = l.totalProteinMid;
          final dayTargetPro = l.targetProtein ?? targetProtein;
          logsLast14.add(l);
          calSum14 += cal;
          proSum14 += pro;
          if (pro < dayTargetPro * 0.75) lowProDays14++;
          if (date.isAfter(now.subtract(const Duration(days: 7)))) {
            logsLast7.add(l);
            calSum7 += cal;
            proSum7 += pro;
            if (pro < dayTargetPro * 0.75) lowProDays7++;
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
      nutritionDaysIn14DayWindow: logsLast14.length,
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
        if (query.toLowerCase().contains('why') ||
            query.toLowerCase().contains('not') ||
            query.toLowerCase().contains('miss') ||
            query.toLowerCase().contains('meal')) {
          return KynoMealDrilldownService.instance.analyzeProteinDeficitAndMeals(snapshot);
        }
        return _analyzeProteinAdherence(snapshot);
      case KynoAnalysisIntent.yesterdayNutrition:
        if (query.toLowerCase().contains('calorie') ||
            query.toLowerCase().contains('high') ||
            query.toLowerCase().contains('why')) {
          return KynoMealDrilldownService.instance.analyzeYesterdayCalories(snapshot);
        }
        return KynoMealDrilldownService.instance.analyzeYesterdaySummary(snapshot);
      case KynoAnalysisIntent.historicalMealQuery:
        return KynoMealDrilldownService.instance.analyzeChronologicalMeals();
      case KynoAnalysisIntent.lateNightEating:
        return KynoMealDrilldownService.instance.analyzeLateNightEating();
      case KynoAnalysisIntent.weightGain:
        return KynoMealDrilldownService.instance.analyzeWeightGain(snapshot);
      case KynoAnalysisIntent.bodyComposition:
        return _analyzeBodyComposition(snapshot, query);
      case KynoAnalysisIntent.fatLossPlateau:
        return _analyzeFatLossPlateau(snapshot, query);
      case KynoAnalysisIntent.recoveryAssessment:
        return _analyzeRecoveryAssessment(snapshot, query);
      case KynoAnalysisIntent.dietAdjustment:
        return _analyzeDietAdjustment(snapshot, query);
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
      detail: 'Recorded ${targetSummary.totalSessions} comparable sessions.\n'
          'Logged working sets: ${recentSets.take(4).join(" | ")}.',
    ));

    // 2. CALCULATION: Performance progression
    insights.add(KynoInsightItem(
      type: KynoInformationType.calculation,
      title: 'Load & Rep Progression',
      detail: isStalled
          ? 'No increase in load or reps was recorded across those comparable sessions (${recentSets.first} repeatedly).'
          : 'Progression recorded: recent working sets advanced to ${recentSets.first}.',
    ));

    // 3. INFERENCE: Performance Plateau
    insights.add(KynoInsightItem(
      type: KynoInformationType.inference,
      title: 'Performance Status',
      detail: isStalled
          ? 'Your $exName appears stalled; this repeated performance without load or rep increase is consistent with a performance plateau.'
          : 'Performance on $exName is progressing along expected overload progression.',
    ));

    // 4. FACT: Nutrition history
    insights.add(KynoInsightItem(
      type: KynoInformationType.fact,
      title: 'Nutrition Record (14-Day Average)',
      detail: 'Averaged ${snapshot.avgProteinLast14Days.toStringAsFixed(0)}g protein and ${snapshot.avgCaloriesLast14Days.toStringAsFixed(0)} kcal/day across ${snapshot.nutritionDaysIn14DayWindow} logged days against your configured ${snapshot.targetDailyProtein.toStringAsFixed(0)}g/day target.',
    ));

    // 5. CALCULATION: Performance & Nutrition Deltas
    final proDeficit = (snapshot.targetDailyProtein - snapshot.avgProteinLast14Days).clamp(0.0, 999.0);
    final proPct = (snapshot.proteinAdherencePct14Days * 100).toInt();

    final calcLines = <String>[
      '• Average protein intake was $proPct% of configured target (${proDeficit.toStringAsFixed(0)}g below daily ${snapshot.targetDailyProtein.toStringAsFixed(0)}g target on average).',
      '• Days below 75% protein target: ${snapshot.lowProteinDaysLast14Days} of last ${snapshot.nutritionDaysIn14DayWindow} logged days.',
      '• Training frequency: ${snapshot.workoutsPerWeekLast14Days.toStringAsFixed(1)} sessions/week (vs ${snapshot.workoutsPerWeekBaseline.toStringAsFixed(1)} baseline).',
    ];
    if (snapshot.calorieDelta14Days < -200.0) {
      calcLines.add('• Logged intake averaged approximately ${snapshot.calorieDelta14Days.abs().toStringAsFixed(0)} kcal below your configured daily target (${snapshot.avgCaloriesLast14Days.toStringAsFixed(0)} kcal logged vs ${snapshot.targetDailyCalories.toStringAsFixed(0)} kcal target).');
    }

    // Contextual meal drill-down evidence: check if recent meal choices explain the nutrient deficit
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final recentMeals = KynoMealDrilldownService.instance.getMealsForDate(yesterday);
    if (recentMeals.isNotEmpty && (proDeficit > 15.0 || snapshot.calorieDelta14Days < -200.0)) {
      final lowPro = recentMeals.where((m) => m.protein < 15.0).toList();
      final anchors = recentMeals.where((m) => m.protein >= 30.0).toList();
      calcLines.add('• Recent meal evidence (${yesterday.month}/${yesterday.day}): ${recentMeals.length} logged meals (${anchors.length} anchor meal ≥30g, ${lowPro.length} low-protein selections <15g).');
    }

    insights.add(KynoInsightItem(
      type: KynoInformationType.calculation,
      title: 'Nutrition Adherence Math',
      detail: calcLines.join('\n'),
    ));

    // 6. INFERENCE: Plausible Contributors (Evidence-calibrated, no medical/biological causation)
    final inferences = <String>[];
    if (isStalled) {
      inferences.add('The clearest pattern in your data is that the lift has repeated without progression while your protein intake has also been consistently below configured target.');
      contributors.add('No progressive overload recorded (hitting identical reps and load across consecutive sessions).');
    }

    if (proDeficit > 20.0) {
      if (recentMeals.isNotEmpty) {
        final lowPro = recentMeals.where((m) => m.protein < 15.0).toList();
        if (lowPro.isNotEmpty) {
          inferences.add('Your multi-day protein shortfall ($proPct% of target) is reflected in your logged meal distribution: on your most recent completed day, ${lowPro.length} of ${recentMeals.length} meals (such as ${lowPro.take(2).map((m) => '"${m.mealName}" [${m.formattedTime}] with ${m.protein.toStringAsFixed(0)}g P').join(', ')}) contained minimal protein, contributing to a daily intake below target. While this protein shortfall is a plausible contributor that may make recovery or adaptation harder, Kyno cannot prove it is the sole cause and distinguishes observed intake patterns from direct causal proof.');
        } else {
          inferences.add('Your consistently low protein intake ($proPct% of target) is a plausible contributor that may make recovery or adaptation harder, but Kyno cannot prove it is the sole cause and distinguishes observed intake patterns from direct causal proof.');
        }
      } else {
        inferences.add('Your consistently low protein intake ($proPct% of target) is a plausible contributor that may make recovery or adaptation harder, but Kyno cannot prove it is the sole cause and distinguishes observed intake patterns from direct causal proof.');
      }
      contributors.add('Consistent protein intake below configured target (averaging ${proDeficit.toStringAsFixed(0)}g/day below target).');
    }

    if (snapshot.calorieDelta14Days < -350.0) {
      inferences.add('Your logged calorie intake is substantially below your configured daily target (~${snapshot.calorieDelta14Days.abs().toStringAsFixed(0)} kcal gap), which may make strength and weight-gain progress harder.');
      contributors.add('Substantial calorie deficit relative to configured daily target.');
    }

    if (snapshot.workoutsPerWeekLast14Days < 2.0) {
      inferences.add('Training frequency has averaged ${snapshot.workoutsPerWeekLast14Days.toStringAsFixed(1)} sessions/week, which provides fewer weekly progressive overload opportunities.');
      contributors.add('Low workout frequency providing fewer weekly progression stimuli.');
    }

    insights.add(KynoInsightItem(
      type: KynoInformationType.inference,
      title: 'Plausible Contributors',
      detail: inferences.join('\n\n'),
    ));

    // 7. RECOMMENDATIONS: Actionable Concrete Adjustments derived from user config
    if (isStalled) {
      final topWeight = targetSummary.recentWeights.isNotEmpty ? targetSummary.recentWeights.first : 20.0;
      final topReps = targetSummary.recentReps.isNotEmpty ? targetSummary.recentReps.first : 8;
      recommendations.add('Rep Progression: In your next session, keep ${topWeight.toStringAsFixed(topWeight == topWeight.truncateToDouble() ? 0 : 1)}kg and aim for ${topReps + 1} to ${topReps + 2} reps on your first working set before attempting to increase the load.');
      recommendations.add('Micro-Loading: If reps are capped, use small increments (0.5kg or 1kg) rather than forcing a 2.5kg jump.');
    }

    if (proDeficit > 15.0) {
      recommendations.add('Protein Target: Bring daily protein intake consistently closer to your configured target of ${snapshot.targetDailyProtein.toStringAsFixed(0)}g/day (currently averaging ${snapshot.avgProteinLast14Days.toStringAsFixed(0)}g/day).');
    }

    recommendations.add('Reassess: Evaluate progression after the next 2–3 comparable sessions.');

    insights.add(KynoInsightItem(
      type: KynoInformationType.recommendation,
      title: 'Action Plan',
      detail: recommendations.map((r) => '• $r').join('\n'),
    ));

    // 8. UNKNOWN: Explicitly State Untracked Parameters
    insights.add(KynoInsightItem(
      type: KynoInformationType.unknown,
      title: 'Untracked Variables',
      detail: 'I don\'t currently track sleep duration or recovery quality, subjective life stress, or lifting biomechanics/technique, so I cannot determine whether any of those unmeasured factors are contributing.',
    ));

    watchItems.add('Track reps on set 1 of $exName next session.');
    watchItems.add('Track 7-day average protein adherence.');

    final headline = isStalled
        ? 'Your $exName does look stalled right now.'
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
          : 'A training frequency below 3 days/week provides fewer weekly progressive overload stimuli.',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.recommendation,
      title: 'Target Schedule',
      detail: 'Lock in 3 dedicated workout days per week with at least 48 hours recovery between sessions of the same muscle group.',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.unknown,
      title: 'Untracked Life Factors',
      detail: 'Travel, work schedules, and outside physical fatigue are not recorded in Kynetix.',
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
          : 'Averaging a ${deficit.toStringAsFixed(0)}g gap below target ($pct% adherence). Below target on ${snapshot.lowProteinDaysLast14Days} of the last 14 logged days.',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.inference,
      title: 'Plausible Recovery Impact',
      detail: deficit <= 10.0
          ? 'Your logged protein intake consistently aligns with your configured target, supporting ongoing workout recovery.'
          : 'Your consistently low protein intake ($pct% of target) is a plausible contributor to slower recovery and adaptation between workouts.',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.recommendation,
      title: 'Nutrition Strategy',
      detail: deficit <= 10.0
          ? 'Maintain your current daily routine.'
          : 'Bring daily intake closer to your configured ${snapshot.targetDailyProtein.toStringAsFixed(0)}g target. Anchor 30–40g of protein into your primary meals to close the ${deficit.toStringAsFixed(0)}g gap.',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.unknown,
      title: 'Untracked Nutrition Factors',
      detail: 'Protein distribution across meals, micronutrient quality, and digestive absorption are not tracked.',
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
      detail: 'Day-to-day performance fluctuations of ±5-10% are standard training variance. An isolated low-energy session is normal and does not represent an athletic plateau.',
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
      title: 'Training Load Assessment',
      detail: snapshot.workoutsPerWeekLast14Days < 4.0
          ? 'At ${snapshot.workoutsPerWeekLast14Days.toStringAsFixed(1)} sessions/week, your logged workout frequency is well within standard recovery capacity. Feeling fatigued is often more closely correlated with calorie deficits, low protein, or untracked sleep and stress.'
          : 'High training frequency with fewer rest days may increase cumulative fatigue.',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.unknown,
      title: 'Untracked Recovery Markers',
      detail: 'Sleep duration and quality, non-gym physical activity, and subjective life stress are untracked.',
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
          ? 'Your primary logged bottleneck is protein consistency (${proDeficit.toStringAsFixed(0)}g below configured target on average). Bringing protein closer to your ${snapshot.targetDailyProtein.toStringAsFixed(0)}g target is a plausible opportunity to support your training.'
          : 'Your nutrition adherence is solid. Focus on progressive overload and hitting top rep targets on primary lifts.',
    ));

    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final recentMeals = KynoMealDrilldownService.instance.getMealsForDate(yesterday);
    if (recentMeals.isNotEmpty && proDeficit > 15.0) {
      final lowPro = recentMeals.where((m) => m.protein < 15.0).toList();
      if (lowPro.isNotEmpty) {
        insights.add(KynoInsightItem(
          type: KynoInformationType.inference,
          title: 'Meal-Level Bottleneck',
          detail: 'Recent meal logs show low-protein density across ${lowPro.length} of ${recentMeals.length} logged meals (such as ${lowPro.take(2).map((m) => '"${m.mealName}"').join(', ')}). This observed meal pattern is a plausible contributor that may make reaching your configured target harder, alongside other lifestyle variables.',
        ));
      }
    }

    insights.add(KynoInsightItem(
      type: KynoInformationType.unknown,
      title: 'Untracked Variables',
      detail: 'Sleep, stress, and lifting technique are not recorded.',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.recommendation,
      title: 'Prioritized Action Plan',
      detail: '1. Close the daily protein gap toward your ${snapshot.targetDailyProtein.toStringAsFixed(0)}g target.\n2. Ensure double progression is applied (add reps before adding weight).\n3. Maintain consistent 3-4 sessions/week frequency.',
    ));

    return KynoAnalysisResult(
      intent: KynoAnalysisIntent.broadAudit,
      headline: 'Complete longitudinal fitness audit based on your recorded history:',
      insights: insights,
    );
  }

  KynoAnalysisResult _analyzeBodyComposition(KynoUserFitnessSnapshot snapshot, String query) {
    final insights = <KynoInsightItem>[];
    final diff = snapshot.avgCaloriesLast14Days - snapshot.targetDailyCalories;
    final diffStr = diff >= 0 ? '+${diff.toStringAsFixed(0)}' : diff.toStringAsFixed(0);

    final headline = 'Your logged nutrition shows an average intake of ${snapshot.avgCaloriesLast14Days.toStringAsFixed(0)} kcal/day '
        'relative to your configured target of ${snapshot.targetDailyCalories.toStringAsFixed(0)} kcal/day ($diffStr kcal/day difference). '
        'However, Kynetix does not track waist or body composition measurements, and localized fat loss ("spot reduction") '
        'cannot be specifically targeted through diet or abdominal training.';

    insights.add(KynoInsightItem(
      type: KynoInformationType.fact,
      title: 'Logged Nutrition & Training Baseline',
      detail: '• 14-Day Average Intake: ${snapshot.avgCaloriesLast14Days.toStringAsFixed(0)} kcal/day across ${snapshot.nutritionDaysIn14DayWindow} logged days.\n'
          '• Configured Calorie Target: ${snapshot.targetDailyCalories.toStringAsFixed(0)} kcal/day.\n'
          '• 14-Day Average Protein: ${snapshot.avgProteinLast14Days.toStringAsFixed(0)}g/day (Target: ${snapshot.targetDailyProtein.toStringAsFixed(0)}g/day).\n'
          '• Training Frequency: ${snapshot.workoutsPerWeekLast14Days.toStringAsFixed(1)} workouts/week across ${snapshot.totalWorkoutsLogged} lifetime sessions.',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.calculation,
      title: 'Energy Intake Relative to Configured Target',
      detail: 'Logged average intake is $diffStr kcal/day relative to your configured daily target. '
          'Over a 14-day window, this represents a cumulative delta of ${(diff * 14).toStringAsFixed(0)} kcal compared to target planning.',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.inference,
      title: 'Physiological Fat Mobilization Principle',
      detail: 'Adipose tissue reduction occurs systemically across the entire body when an energy deficit is sustained over time. '
          'The sequence and rate at which specific fat stores (such as subcutaneous abdominal or visceral fat) are mobilized '
          'is determined by individual genetics, hormonal profile, and receptor distribution. '
          'Abdominal exercises strengthen underlying muscle tissue but do not preferentially burn overlying abdominal fat.',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.recommendation,
      title: 'Recommended Strategy',
      detail: '1. Adhere consistently to your configured caloric target for 3–4 continuous weeks.\n'
          '2. Maintain progressive overload in resistance training to preserve lean skeletal muscle mass.\n'
          '3. Measure waist circumference once per week at the navel under identical conditions (fasted upon waking).',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.unknown,
      title: 'Untracked Composition Variables',
      detail: 'Kynetix tracks logged food intake and workout sets, but does not record waist circumference, skinfold caliper measurements, DEXA body composition, or visceral fat indices. Localized tissue changes cannot be measured from logging data alone.',
    ));

    return KynoAnalysisResult(
      intent: KynoAnalysisIntent.bodyComposition,
      headline: headline,
      insights: insights,
      recommendedChanges: [
        'Maintain consistent caloric intake relative to your daily target.',
        'Take weekly waist circumference measurements to objectively monitor midsection changes.',
      ],
      watchItems: [
        'Avoid crash dieting or excessive ab workouts expecting localized fat reduction.',
      ],
    );
  }

  KynoAnalysisResult _analyzeFatLossPlateau(KynoUserFitnessSnapshot snapshot, String query) {
    final insights = <KynoInsightItem>[];
    final diff = snapshot.avgCaloriesLast14Days - snapshot.targetDailyCalories;
    final diffStr = diff >= 0 ? '+${diff.toStringAsFixed(0)}' : diff.toStringAsFixed(0);

    final headline = 'Your logged intake over the last 14 days has averaged ${snapshot.avgCaloriesLast14Days.toStringAsFixed(0)} kcal/day '
        'against your configured target of ${snapshot.targetDailyCalories.toStringAsFixed(0)} kcal/day ($diffStr kcal/day). '
        'If your scale weight has remained unchanged across multiple consecutive weeks, your actual total energy intake currently matches your real-world expenditure.';

    insights.add(KynoInsightItem(
      type: KynoInformationType.fact,
      title: 'Logged Intake History',
      detail: '• 14-Day Average Intake: ${snapshot.avgCaloriesLast14Days.toStringAsFixed(0)} kcal/day.\n'
          '• Configured Caloric Target: ${snapshot.targetDailyCalories.toStringAsFixed(0)} kcal/day.\n'
          '• Logged Days in 14-Day Window: ${snapshot.nutritionDaysIn14DayWindow} of 14 days.\n'
          '• Average Protein Intake: ${snapshot.avgProteinLast14Days.toStringAsFixed(0)}g/day.',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.calculation,
      title: 'Intake vs Configured Target Delta',
      detail: 'Intake differs from configured target by $diffStr kcal/day. '
          'A configured target is an initial mathematical estimate; real-world weight plateau indicates current energy equilibrium regardless of planned targets.',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.inference,
      title: 'Energy Balance & Plateau Analysis',
      detail: 'When body weight remains static over 2–3 weeks, true metabolic expenditure and caloric intake are in balance. '
          'Plateaus commonly result from unrecorded cooking oils/condiments, weekend intake fluctuations, or reduced non-exercise activity (NEAT) as the body defends energy reserves.',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.recommendation,
      title: 'Plateau Breaking Protocol',
      detail: '1. Weigh all foods with a digital kitchen scale for 7 consecutive days to verify accuracy.\n'
          '2. If strict logging confirms zero weight movement over 3 consecutive weeks, reduce your configured daily intake by 150–200 kcal.\n'
          '3. Keep daily step counts and resistance training volume consistent.',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.unknown,
      title: 'Unmeasured Physiological Factors',
      detail: 'Fluctuations in daily water retention (due to sodium intake, glycogen storage, or training-induced muscle inflammation), unlogged foods or beverages, and true daily metabolic expenditure are not tracked by Kynetix.',
    ));

    return KynoAnalysisResult(
      intent: KynoAnalysisIntent.fatLossPlateau,
      headline: headline,
      insights: insights,
      recommendedChanges: [
        'Strictly weigh portion sizes and condiments for 7 days.',
        'If weight remains flat for another 2 weeks, adjust daily calorie target downward by 150-200 kcal.',
      ],
    );
  }

  KynoAnalysisResult _analyzeRecoveryAssessment(KynoUserFitnessSnapshot snapshot, String query) {
    final insights = <KynoInsightItem>[];
    final proRatio = snapshot.targetDailyProtein > 0
        ? (snapshot.avgProteinLast7Days / snapshot.targetDailyProtein * 100).round()
        : 100;

    final headline = 'Over the last 7 days, you logged ${snapshot.totalWorkoutsLogged} workouts '
        'with an average protein intake of ${snapshot.avgProteinLast7Days.toStringAsFixed(0)}g/day ($proRatio% of your ${snapshot.targetDailyProtein.toStringAsFixed(0)}g configured target). '
        'Note that sleep duration, sleep quality, and biometric recovery markers are not tracked in Kynetix.';

    insights.add(KynoInsightItem(
      type: KynoInformationType.fact,
      title: 'Tracked Workload & Nutrition Baseline',
      detail: '• Logged Workouts (Last 14 Days): ${snapshot.workoutsPerWeekLast14Days.toStringAsFixed(1)} sessions/week.\n'
          '• Days Since Last Workout: ${snapshot.daysSinceLastWorkout == 999 ? "None logged recently" : "${snapshot.daysSinceLastWorkout} day(s)"}.\n'
          '• 7-Day Average Protein Intake: ${snapshot.avgProteinLast7Days.toStringAsFixed(0)}g/day (Target: ${snapshot.targetDailyProtein.toStringAsFixed(0)}g/day).\n'
          '• Low Protein Days (<75% target): ${snapshot.lowProteinDaysLast7Days} of the last 7 days.',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.calculation,
      title: 'Tracked Recovery Substrate Availability',
      detail: 'Protein target adherence is at $proRatio% over the last 7 days. '
          '${snapshot.lowProteinDaysLast7Days > 0 ? "You experienced ${snapshot.lowProteinDaysLast7Days} days with significant protein deficits that can impair muscle protein synthesis." : "Daily protein availability has met configured recovery requirements."}',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.inference,
      title: 'Training Load Assessment',
      detail: 'Based on tracked workout frequency and set volume, structural recovery is supported when rest days are scheduled between high-intensity sessions and protein requirements are met.',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.recommendation,
      title: 'Recovery Guidance',
      detail: snapshot.lowProteinDaysLast7Days > 0
          ? 'Focus on closing your daily protein deficit (${(snapshot.targetDailyProtein - snapshot.avgProteinLast7Days).clamp(0, 200).toStringAsFixed(0)}g remaining to target) to support muscle tissue remodeling.'
          : 'Maintain your current training-to-rest cadence and continue hitting your daily protein target.',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.unknown,
      title: 'Untracked Recovery Biometrics',
      detail: 'Sleep duration, sleep architecture (deep/REM sleep), heart rate variability (HRV), resting heart rate, and subjective central nervous system fatigue are NOT tracked in Kynetix and cannot be evaluated.',
    ));

    return KynoAnalysisResult(
      intent: KynoAnalysisIntent.recoveryAssessment,
      headline: headline,
      insights: insights,
      recommendedChanges: [
        if (snapshot.lowProteinDaysLast7Days > 0) 'Hit your protein target consistently on both training and rest days.',
        'Ensure at least 1-2 dedicated recovery days each week between heavy sessions.',
      ],
    );
  }

  KynoAnalysisResult _analyzeDietAdjustment(KynoUserFitnessSnapshot snapshot, String query) {
    final insights = <KynoInsightItem>[];
    final calDiff = snapshot.avgCaloriesLast14Days - snapshot.targetDailyCalories;
    final proDiff = snapshot.targetDailyProtein - snapshot.avgProteinLast14Days;

    final headline = 'Based on your logged nutrition history, your primary dietary adjustments are '
        '${proDiff > 10 ? "closing your ${proDiff.toStringAsFixed(0)}g daily protein gap" : "maintaining protein consistency"} and '
        'aligning daily calories with your ${snapshot.targetDailyCalories.toStringAsFixed(0)} kcal target.';

    insights.add(KynoInsightItem(
      type: KynoInformationType.fact,
      title: '14-Day Logged Nutrition Baseline',
      detail: '• Average Calories: ${snapshot.avgCaloriesLast14Days.toStringAsFixed(0)} kcal/day (Target: ${snapshot.targetDailyCalories.toStringAsFixed(0)} kcal).\n'
          '• Average Protein: ${snapshot.avgProteinLast14Days.toStringAsFixed(0)}g/day (Target: ${snapshot.targetDailyProtein.toStringAsFixed(0)}g).\n'
          '• Logged Days: ${snapshot.nutritionDaysIn14DayWindow} of 14 calendar days.\n'
          '• Days Below 75% Protein Target: ${snapshot.lowProteinDaysLast14Days} days.',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.calculation,
      title: 'Target Variance',
      detail: '• Caloric variance: ${calDiff >= 0 ? "+" : ""}${calDiff.toStringAsFixed(0)} kcal/day vs target.\n'
          '• Protein variance: ${proDiff <= 0 ? "Target met" : "-${proDiff.toStringAsFixed(0)}g/day below target"}.',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.inference,
      title: 'Nutritional Bottleneck Assessment',
      detail: proDiff > 15
          ? 'Sub-optimal daily protein intake is the most impactful nutritional variable limiting your muscular recovery and body composition progress.'
          : 'Caloric consistency across consecutive days is your main variable to regulate.',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.recommendation,
      title: 'Actionable Dietary Changes',
      detail: '1. Anchor each meal with 30–45g of protein (e.g. chicken breast, Greek yogurt, eggs/whites, whey).\n'
          '2. Plan your protein sources at the beginning of the day before filling remaining calories with complex carbs and healthy fats.\n'
          '3. Keep intake consistent across weekends to avoid weekly calorie spikes.',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.unknown,
      title: 'Untracked Variables',
      detail: 'Micronutrient levels (vitamins/minerals), dietary fiber breakdown, hydration/water intake, and food quality or GI response are not tracked in Kynetix.',
    ));

    return KynoAnalysisResult(
      intent: KynoAnalysisIntent.dietAdjustment,
      headline: headline,
      insights: insights,
      recommendedChanges: [
        'Anchor each meal with 30-45g of protein.',
        'Align daily calorie intake within ±100 kcal of your configured target.',
      ],
    );
  }
}

