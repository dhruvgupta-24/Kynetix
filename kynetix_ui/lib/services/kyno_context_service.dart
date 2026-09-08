import '../models/day_log.dart';
import 'profile_service.dart';
import 'workout_service.dart';
import 'exercise_media_service.dart';
import 'saved_meal_service.dart';

// ─── Fact vs Inference Models ────────────────────────────────────────────────

enum KynoInformationType {
  fact,
  calculation,
  inference,
  recommendation,
}

class KynoInsightItem {
  final KynoInformationType type;
  final String title;
  final String detail;

  const KynoInsightItem({
    required this.type,
    required this.title,
    required this.detail,
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'title': title,
        'detail': detail,
      };
}

// ─── Structured Context Snapshots ────────────────────────────────────────────

class UserProfileContext {
  final String name;
  final String goal;
  final double? weightKg;
  final double? heightCm;
  final int? age;
  final int workoutDaysMin;
  final int workoutDaysMax;

  const UserProfileContext({
    required this.name,
    required this.goal,
    this.weightKg,
    this.heightCm,
    this.age,
    required this.workoutDaysMin,
    required this.workoutDaysMax,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'goal': goal,
        'weight_kg': weightKg,
        'height_cm': heightCm,
        'age': age,
        'workout_days_min': workoutDaysMin,
        'workout_days_max': workoutDaysMax,
      };
}

class ExerciseHistoryContext {
  final String canonicalName;
  final String muscleGroup;
  final int totalSessions;
  final int totalSets;
  final double totalVolumeKg;
  final String? lifetimeBest;
  final String? recentBest;
  final double? highestEstimated1Rm;
  final List<String> recentWorkingSets;
  final List<double> estimated1RmTrend;

  const ExerciseHistoryContext({
    required this.canonicalName,
    required this.muscleGroup,
    required this.totalSessions,
    required this.totalSets,
    required this.totalVolumeKg,
    this.lifetimeBest,
    this.recentBest,
    this.highestEstimated1Rm,
    required this.recentWorkingSets,
    required this.estimated1RmTrend,
  });

  Map<String, dynamic> toJson() => {
        'canonical_name': canonicalName,
        'muscle_group': muscleGroup,
        'total_sessions': totalSessions,
        'total_sets': totalSets,
        'total_volume_kg': totalVolumeKg,
        'lifetime_best': lifetimeBest,
        'recent_best': recentBest,
        'highest_estimated_1rm': highestEstimated1Rm,
        'recent_working_sets': recentWorkingSets,
        'estimated_1rm_trend': estimated1RmTrend,
      };
}

class TrainingContext {
  final String? todaySplitDayName;
  final bool hasWorkoutToday;
  final bool isWorkoutDraftActive;
  final int totalCompletedSessions;
  final double averageSessionsPerWeek;
  final List<String> exercisesTrainedToday;
  final double volumeTrainedTodayKg;
  final int setsLoggedToday;
  final List<String> recentWorkoutsSummary;

  const TrainingContext({
    this.todaySplitDayName,
    required this.hasWorkoutToday,
    required this.isWorkoutDraftActive,
    required this.totalCompletedSessions,
    required this.averageSessionsPerWeek,
    required this.exercisesTrainedToday,
    required this.volumeTrainedTodayKg,
    required this.setsLoggedToday,
    required this.recentWorkoutsSummary,
  });

  Map<String, dynamic> toJson() => {
        'today_split_day_name': todaySplitDayName,
        'has_workout_today': hasWorkoutToday,
        'is_workout_draft_active': isWorkoutDraftActive,
        'total_completed_sessions': totalCompletedSessions,
        'average_sessions_per_week': averageSessionsPerWeek,
        'exercises_trained_today': exercisesTrainedToday,
        'volume_trained_today_kg': volumeTrainedTodayKg,
        'sets_logged_today': setsLoggedToday,
        'recent_workouts_summary': recentWorkoutsSummary,
      };
}

class NutritionContext {
  final double consumedCalories;
  final double consumedProtein;
  final double consumedCarbs;
  final double consumedFat;
  final double consumedFiber;
  final double targetCalories;
  final double targetProtein;
  final double remainingCalories;
  final double remainingProtein;
  final List<String> mealsLoggedToday;
  final List<String> topSavedMeals;

  const NutritionContext({
    required this.consumedCalories,
    required this.consumedProtein,
    required this.consumedCarbs,
    required this.consumedFat,
    required this.consumedFiber,
    required this.targetCalories,
    required this.targetProtein,
    required this.remainingCalories,
    required this.remainingProtein,
    required this.mealsLoggedToday,
    required this.topSavedMeals,
  });

  Map<String, dynamic> toJson() => {
        'consumed_calories': consumedCalories,
        'consumed_protein': consumedProtein,
        'consumed_carbs': consumedCarbs,
        'consumed_fat': consumedFat,
        'consumed_fiber': consumedFiber,
        'target_calories': targetCalories,
        'target_protein': targetProtein,
        'remaining_calories': remainingCalories,
        'remaining_protein': remainingProtein,
        'meals_logged_today': mealsLoggedToday,
        'top_saved_meals': topSavedMeals,
      };
}

class CrossDomainRecoveryContext {
  final bool trainedToday;
  final String? workoutTrained;
  final double totalVolumeKg;
  final double proteinConsumedG;
  final double proteinTargetG;
  final double proteinDeficitG;
  final String recoveryStatus;
  final String nutritionAdvice;

  const CrossDomainRecoveryContext({
    required this.trainedToday,
    this.workoutTrained,
    required this.totalVolumeKg,
    required this.proteinConsumedG,
    required this.proteinTargetG,
    required this.proteinDeficitG,
    required this.recoveryStatus,
    required this.nutritionAdvice,
  });

  Map<String, dynamic> toJson() => {
        'trained_today': trainedToday,
        'workout_trained': workoutTrained,
        'total_volume_kg': totalVolumeKg,
        'protein_consumed_g': proteinConsumedG,
        'protein_target_g': proteinTargetG,
        'protein_deficit_g': proteinDeficitG,
        'recovery_status': recoveryStatus,
        'nutrition_advice': nutritionAdvice,
      };
}

class KynoContextSnapshot {
  final DateTime timestamp;
  final UserProfileContext profile;
  final TrainingContext training;
  final NutritionContext nutrition;
  final CrossDomainRecoveryContext crossDomain;
  final List<KynoInsightItem> structuredInsights;

  const KynoContextSnapshot({
    required this.timestamp,
    required this.profile,
    required this.training,
    required this.nutrition,
    required this.crossDomain,
    required this.structuredInsights,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'profile': profile.toJson(),
        'training': training.toJson(),
        'nutrition': nutrition.toJson(),
        'cross_domain': crossDomain.toJson(),
        'structured_insights': structuredInsights.map((i) => i.toJson()).toList(),
      };
}

// ─── KynoContextService ──────────────────────────────────────────────────────

/// Central Personal Fitness Intelligence Context Service.
/// Aggregates real persisted data from Training, Nutrition, and Profile.
class KynoContextService {
  KynoContextService._();
  static final KynoContextService instance = KynoContextService._();

  KynoContextSnapshot? _cachedSnapshot;
  DateTime? _lastSnapshotComputedAt;

  /// Returns a rich, structured snapshot of the user's complete context.
  /// Cached for 20 seconds unless [forceRefresh] is true.
  KynoContextSnapshot getSnapshot({DateTime? forDate, bool forceRefresh = false}) {
    final now = DateTime.now();
    if (!forceRefresh &&
        _cachedSnapshot != null &&
        _lastSnapshotComputedAt != null &&
        now.difference(_lastSnapshotComputedAt!).inSeconds < 20) {
      return _cachedSnapshot!;
    }

    final date = forDate ?? now;
    final profile = _buildProfileContext();
    final training = _buildTrainingContext(date);
    final nutrition = _buildNutritionContext(date, profile);
    final crossDomain = _buildCrossDomainContext(training, nutrition);
    final insights = _buildStructuredInsights(profile, training, nutrition, crossDomain);

    final snapshot = KynoContextSnapshot(
      timestamp: now,
      profile: profile,
      training: training,
      nutrition: nutrition,
      crossDomain: crossDomain,
      structuredInsights: insights,
    );

    _cachedSnapshot = snapshot;
    _lastSnapshotComputedAt = now;
    return snapshot;
  }

  UserProfileContext _buildProfileContext() {
    final p = ProfileService.instance.currentUserProfile;
    return UserProfileContext(
      name: p?.name.isNotEmpty == true ? p!.name : 'Athlete',
      goal: p?.goal ?? 'Muscle Building & Strength',
      weightKg: p?.weight,
      heightCm: p?.height,
      age: p?.age,
      workoutDaysMin: p?.workoutDaysMin ?? 3,
      workoutDaysMax: p?.workoutDaysMax ?? 5,
    );
  }

  TrainingContext _buildTrainingContext(DateTime date) {
    final ws = WorkoutService.instance;
    final draft = ws.draftSession;
    final completedToday = ws.sessionFor(date);

    final activeOrCompleted = draft ?? completedToday;
    final hasWorkoutToday = activeOrCompleted != null;
    final splitName = activeOrCompleted?.splitDayName ?? ws.splitDayFor(date)?.name;

    final exercisesTrained = <String>[];
    double volumeToday = 0.0;
    int setsToday = 0;

    if (activeOrCompleted != null) {
      for (final e in activeOrCompleted.entries) {
        if (e.isSkipped || e.sets.isEmpty) continue;
        exercisesTrained.add(e.exercise.name);
        volumeToday += e.workingVolume;
        setsToday += e.sets.length;
      }
    }

    final allSessions = ws.sessions;
    double avgFreq = 0.0;
    if (allSessions.isNotEmpty) {
      final firstDate = allSessions.first.date;
      final daysBetween = DateTime.now().difference(firstDate).inDays.clamp(7, 3650);
      avgFreq = (allSessions.length / (daysBetween / 7.0));
    }

    final recentSummaries = allSessions.take(5).map((s) {
      final performed = s.entries.where((e) => !e.isSkipped && e.sets.isNotEmpty).map((e) => e.exercise.name).toList();
      return '${s.splitDayName}: ${performed.take(3).join(", ")}${performed.length > 3 ? " +${performed.length - 3}" : ""} (${s.totalWorkingVolume.toStringAsFixed(0)} kg)';
    }).toList();

    return TrainingContext(
      todaySplitDayName: splitName,
      hasWorkoutToday: hasWorkoutToday,
      isWorkoutDraftActive: draft != null,
      totalCompletedSessions: allSessions.length,
      averageSessionsPerWeek: double.parse(avgFreq.toStringAsFixed(1)),
      exercisesTrainedToday: exercisesTrained,
      volumeTrainedTodayKg: volumeToday,
      setsLoggedToday: setsToday,
      recentWorkoutsSummary: recentSummaries,
    );
  }

  NutritionContext _buildNutritionContext(DateTime date, UserProfileContext profile) {
    final log = logFor(date);
    final calConsumed = log.totalCaloriesMid;
    final proConsumed = log.totalProteinMid;
    final carbConsumed = log.totalCarbsMid;
    final fatConsumed = log.totalFatMid;
    final fibConsumed = log.totalFiberMid;

    // Daily targets from log frozen target or profile default
    final targetCal = log.targetCalories ?? (profile.weightKg != null ? profile.weightKg! * 32.0 : 2200.0);
    final targetPro = log.targetProtein ?? (profile.weightKg != null ? profile.weightKg! * 2.0 : 150.0);

    final mealsLogged = log.allEntries.map((e) {
      final name = e.finalSavedInput.isNotEmpty ? e.finalSavedInput : e.rawInput;
      return '${e.section.displayName}: $name (${e.calMid.toStringAsFixed(0)} kcal, ${e.protMid.toStringAsFixed(1)}g pro)';
    }).toList();

    final topSaved = SavedMealService.instance.search('a', limit: 5).map((m) => '${m.title} (${m.calories.toStringAsFixed(0)} kcal)').toList();

    return NutritionContext(
      consumedCalories: calConsumed,
      consumedProtein: proConsumed,
      consumedCarbs: carbConsumed,
      consumedFat: fatConsumed,
      consumedFiber: fibConsumed,
      targetCalories: targetCal,
      targetProtein: targetPro,
      remainingCalories: (targetCal - calConsumed).clamp(0.0, 9999.0),
      remainingProtein: (targetPro - proConsumed).clamp(0.0, 999.0),
      mealsLoggedToday: mealsLogged,
      topSavedMeals: topSaved,
    );
  }

  CrossDomainRecoveryContext _buildCrossDomainContext(
    TrainingContext training,
    NutritionContext nutrition,
  ) {
    final trained = training.hasWorkoutToday;
    final proConsumed = nutrition.consumedProtein;
    final proTarget = nutrition.targetProtein;
    final deficit = (proTarget - proConsumed).clamp(0.0, 999.0);

    String status;
    String advice;

    if (!trained) {
      if (deficit <= 10.0) {
        status = 'Rest day nutrition on track.';
        advice = 'Protein target is met for cellular repair and maintenance.';
      } else {
        status = 'Rest day recovery.';
        advice = '${deficit.toStringAsFixed(0)}g protein remaining to hit daily baseline.';
      }
    } else {
      if (deficit <= 5.0) {
        status = 'Optimal post-workout recovery fueled.';
        advice = 'Protein target achieved to repair ${training.volumeTrainedTodayKg.toStringAsFixed(0)} kg training volume.';
      } else if (deficit <= 30.0) {
        status = 'Moderate recovery window.';
        advice = 'Complete remaining ${deficit.toStringAsFixed(0)}g protein tonight to maximize muscle protein synthesis.';
      } else {
        status = 'High recovery demand remaining.';
        advice = 'Trained ${training.todaySplitDayName ?? "hard"} today with ${training.setsLoggedToday} sets. Prioritize a high-protein meal (${deficit.toStringAsFixed(0)}g needed).';
      }
    }

    return CrossDomainRecoveryContext(
      trainedToday: trained,
      workoutTrained: training.todaySplitDayName,
      totalVolumeKg: training.volumeTrainedTodayKg,
      proteinConsumedG: proConsumed,
      proteinTargetG: proTarget,
      proteinDeficitG: deficit,
      recoveryStatus: status,
      nutritionAdvice: advice,
    );
  }

  List<KynoInsightItem> _buildStructuredInsights(
    UserProfileContext profile,
    TrainingContext training,
    NutritionContext nutrition,
    CrossDomainRecoveryContext crossDomain,
  ) {
    final list = <KynoInsightItem>[];

    // Facts
    if (training.hasWorkoutToday) {
      list.add(KynoInsightItem(
        type: KynoInformationType.fact,
        title: 'Today\'s Training',
        detail: 'Logged ${training.setsLoggedToday} sets across ${training.exercisesTrainedToday.length} exercises (${training.volumeTrainedTodayKg.toStringAsFixed(0)} kg volume).',
      ));
    }
    list.add(KynoInsightItem(
      type: KynoInformationType.fact,
      title: 'Today\'s Nutrition',
      detail: '${nutrition.consumedCalories.toStringAsFixed(0)} kcal • ${nutrition.consumedProtein.toStringAsFixed(1)}g protein logged.',
    ));

    // Calculations
    list.add(KynoInsightItem(
      type: KynoInformationType.calculation,
      title: 'Remaining Targets',
      detail: '${nutrition.remainingCalories.toStringAsFixed(0)} kcal & ${nutrition.remainingProtein.toStringAsFixed(0)}g protein remaining today.',
    ));

    // Inferences
    list.add(KynoInsightItem(
      type: KynoInformationType.inference,
      title: 'Recovery State',
      detail: crossDomain.recoveryStatus,
    ));

    // Recommendations
    list.add(KynoInsightItem(
      type: KynoInformationType.recommendation,
      title: 'Kyno Coaching',
      detail: crossDomain.nutritionAdvice,
    ));

    return list;
  }

  /// Canonical exercise resolver: combines alias matching with full session history.
  ExerciseHistoryContext getCanonicalExerciseHistory(String exerciseNameOrId) {
    final ws = WorkoutService.instance;
    final allExercises = ws.allExercises;

    // Resolve canonical exercise ID using ExerciseMediaService
    final canonicalId = ExerciseMediaService.instance.getCanonicalId(exerciseNameOrId);
    final matchingExercises = allExercises.where((e) {
      return e.id == canonicalId ||
          e.name.toLowerCase() == exerciseNameOrId.toLowerCase() ||
          ExerciseMediaService.instance.getCanonicalId(e.name) == canonicalId;
    }).toList();

    final targetId = matchingExercises.isNotEmpty ? matchingExercises.first.id : canonicalId;
    final targetName = matchingExercises.isNotEmpty ? matchingExercises.first.name : exerciseNameOrId;
    final muscle = matchingExercises.isNotEmpty ? matchingExercises.first.muscleGroup : 'General';

    // Gather history from all matching exercise IDs
    final historyItems = ws.historyFor(targetId, limit: 12);
    final bestSet = ws.bestSetEver(targetId);

    int totalSets = 0;
    double totalVol = 0.0;
    final recentWorking = <String>[];
    final sparkTrend = <double>[];

    for (final h in historyItems) {
      final entry = h.entry;
      if (entry.isSkipped) continue;
      totalSets += entry.sets.length;
      totalVol += entry.workingVolume;

      final top = entry.topWorkingSet ?? entry.topSet;
      if (top != null && top.estimatedOneRepMax > 0) {
        sparkTrend.add(top.estimatedOneRepMax);
      }
    }

    if (historyItems.isNotEmpty) {
      final latest = historyItems.first.entry;
      for (final s in latest.sets.where((s) => s.isMainWorkingSet)) {
        recentWorking.add('${s.weight.toStringAsFixed(s.weight == s.weight.truncateToDouble() ? 0 : 1)} × ${s.reps}');
      }
    }

    String? bestStr;
    if (bestSet != null) {
      bestStr = '${bestSet.weight.toStringAsFixed(bestSet.weight == bestSet.weight.truncateToDouble() ? 0 : 1)} kg × ${bestSet.reps}';
    }

    double? max1Rm;
    if (sparkTrend.isNotEmpty) {
      max1Rm = sparkTrend.reduce((a, b) => a > b ? a : b);
    }

    return ExerciseHistoryContext(
      canonicalName: targetName,
      muscleGroup: muscle,
      totalSessions: historyItems.length,
      totalSets: totalSets,
      totalVolumeKg: totalVol,
      lifetimeBest: bestStr,
      recentBest: recentWorking.isNotEmpty ? recentWorking.first : null,
      highestEstimated1Rm: max1Rm,
      recentWorkingSets: recentWorking,
      estimated1RmTrend: sparkTrend.reversed.toList(),
    );
  }
}
