import '../models/day_log.dart';
import '../models/workout_session.dart';
import 'profile_service.dart';
import 'workout_service.dart';
import 'exercise_media_service.dart';
import 'saved_meal_service.dart';
import 'meal_memory.dart';
import 'user_nutrition_memory.dart';
import 'user_session_coordinator.dart';

// ─── Fact vs Inference Models ────────────────────────────────────────────────

enum KynoInformationType {
  fact,
  calculation,
  inference,
  recommendation,
  unknown,
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
  final bool isGymDayScheduled;
  final int totalCompletedSessions;
  final double averageSessionsPerWeek;
  final List<String> exercisesTrainedToday;
  final List<String> todayDetailedEntries;
  final double volumeTrainedTodayKg;
  final int setsLoggedToday;
  final int workingSetsLoggedToday;
  final int warmupSetsLoggedToday;
  final String? previousSessionOfSameSplit;
  final List<String> recentWorkoutsSummary;

  const TrainingContext({
    this.todaySplitDayName,
    required this.hasWorkoutToday,
    required this.isWorkoutDraftActive,
    required this.isGymDayScheduled,
    required this.totalCompletedSessions,
    required this.averageSessionsPerWeek,
    required this.exercisesTrainedToday,
    required this.todayDetailedEntries,
    required this.volumeTrainedTodayKg,
    required this.setsLoggedToday,
    required this.workingSetsLoggedToday,
    required this.warmupSetsLoggedToday,
    this.previousSessionOfSameSplit,
    required this.recentWorkoutsSummary,
  });

  Map<String, dynamic> toJson() => {
        'today_split_day_name': todaySplitDayName,
        'has_workout_today': hasWorkoutToday,
        'is_workout_draft_active': isWorkoutDraftActive,
        'is_gym_day_scheduled': isGymDayScheduled,
        'total_completed_sessions': totalCompletedSessions,
        'average_sessions_per_week': averageSessionsPerWeek,
        'exercises_trained_today': exercisesTrainedToday,
        'today_detailed_entries': todayDetailedEntries,
        'volume_trained_today_kg': volumeTrainedTodayKg,
        'sets_logged_today': setsLoggedToday,
        'working_sets_logged_today': workingSetsLoggedToday,
        'warmup_sets_logged_today': warmupSetsLoggedToday,
        'previous_session_of_same_split': previousSessionOfSameSplit,
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
  final double? proteinPerKg;
  final List<String> mealsLoggedToday;
  final Map<String, List<String>> mealsBySection;
  final List<String> topSavedMeals;
  final List<String> recurringMeals;
  final int rememberedOverridesCount;

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
    this.proteinPerKg,
    required this.mealsLoggedToday,
    required this.mealsBySection,
    required this.topSavedMeals,
    required this.recurringMeals,
    required this.rememberedOverridesCount,
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
        'protein_per_kg': proteinPerKg,
        'meals_logged_today': mealsLoggedToday,
        'meals_by_section': mealsBySection,
        'top_saved_meals': topSavedMeals,
        'recurring_meals': recurringMeals,
        'remembered_overrides_count': rememberedOverridesCount,
      };
}

class CrossDomainRecoveryContext {
  final bool trainedToday;
  final String? workoutTrained;
  final double totalVolumeKg;
  final double proteinConsumedG;
  final double proteinTargetG;
  final double proteinDeficitG;
  final double? proteinPerKg;
  final String recoveryStatus;
  final String nutritionAdvice;
  final String recoveryDemand;

  const CrossDomainRecoveryContext({
    required this.trainedToday,
    this.workoutTrained,
    required this.totalVolumeKg,
    required this.proteinConsumedG,
    required this.proteinTargetG,
    required this.proteinDeficitG,
    this.proteinPerKg,
    required this.recoveryStatus,
    required this.nutritionAdvice,
    required this.recoveryDemand,
  });

  Map<String, dynamic> toJson() => {
        'trained_today': trainedToday,
        'workout_trained': workoutTrained,
        'total_volume_kg': totalVolumeKg,
        'protein_consumed_g': proteinConsumedG,
        'protein_target_g': proteinTargetG,
        'protein_deficit_g': proteinDeficitG,
        'protein_per_kg': proteinPerKg,
        'recovery_status': recoveryStatus,
        'nutrition_advice': nutritionAdvice,
        'recovery_demand': recoveryDemand,
      };
}

class KynoContextSnapshot {
  final String? userId;
  final DateTime timestamp;
  final UserProfileContext profile;
  final TrainingContext training;
  final NutritionContext nutrition;
  final CrossDomainRecoveryContext crossDomain;
  final List<KynoInsightItem> structuredInsights;

  const KynoContextSnapshot({
    this.userId,
    required this.timestamp,
    required this.profile,
    required this.training,
    required this.nutrition,
    required this.crossDomain,
    required this.structuredInsights,
  });

  Map<String, dynamic> toJson() => {
        'user_id': userId,
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
  KynoContextService._() {
    WorkoutService.instance.addListener(invalidate);
  }
  static final KynoContextService instance = KynoContextService._();

  KynoContextSnapshot? _cachedSnapshot;
  DateTime? _lastSnapshotComputedAt;

  /// Resets the context snapshot when user logs out or switches accounts.
  void reset() {
    print('[KYNO_CONTEXT] Resetting context cache.');
    _cachedSnapshot = null;
    _lastSnapshotComputedAt = null;
  }

  /// Invalidates any cached snapshot so subsequent queries reflect live state immediately.
  void invalidate() {
    print('[KYNO_CONTEXT_REFRESH] Invalidation triggered. Clearing cached snapshot.');
    _cachedSnapshot = null;
    _lastSnapshotComputedAt = null;
  }

  /// Returns a rich, structured snapshot of the user's complete context.
  /// Cached for 20 seconds unless [forceRefresh] is true.
  KynoContextSnapshot getSnapshot({DateTime? forDate, bool forceRefresh = false}) {
    final currentUserId = UserSessionCoordinator.instance.currentUserId;
    final now = DateTime.now();
    if (!forceRefresh &&
        _cachedSnapshot != null &&
        _cachedSnapshot!.userId == currentUserId &&
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
      userId: currentUserId,
      timestamp: now,
      profile: profile,
      training: training,
      nutrition: nutrition,
      crossDomain: crossDomain,
      structuredInsights: insights,
    );

    _cachedSnapshot = snapshot;
    _lastSnapshotComputedAt = now;

    print('[KYNO_CONTEXT] Refreshed snapshot for user: $currentUserId, date: ${date.toIso8601String().substring(0, 10)}. Training: ${training.hasWorkoutToday ? "${training.setsLoggedToday} sets (${training.workingSetsLoggedToday} working)" : "none"}, Nutrition: ${nutrition.consumedCalories.toStringAsFixed(0)} kcal / ${nutrition.consumedProtein.toStringAsFixed(1)}g pro');

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
    final scheduledDay = ws.splitDayFor(date);
    final isGymDay = scheduledDay != null && !scheduledDay.isRestDay;
    final splitName = activeOrCompleted?.splitDayName ?? scheduledDay?.name;

    final exercisesTrained = <String>[];
    final detailedEntries = <String>[];
    double volumeToday = 0.0;
    int setsToday = 0;
    int workingSetsToday = 0;
    int warmupSetsToday = 0;

    if (activeOrCompleted != null) {
      for (final e in activeOrCompleted.entries) {
        if (e.isSkipped || e.sets.isEmpty) continue;
        exercisesTrained.add(e.exercise.name);
        volumeToday += e.workingVolume;
        setsToday += e.sets.length;

        final working = e.sets.where((s) => s.isMainWorkingSet).toList();
        final warmups = e.sets.where((s) => s.setType == SetType.warmUp).toList();
        workingSetsToday += working.length;
        warmupSetsToday += warmups.length;

        final setsSummary = e.sets.map((s) => '${s.weight.toStringAsFixed(s.weight == s.weight.truncateToDouble() ? 0 : 1)}kg × ${s.reps}').join(', ');
        detailedEntries.add('${e.exercise.name}: ${e.sets.length} sets ($setsSummary)');
      }
    }

    final allSessions = ws.sessions;
    double avgFreq = 0.0;
    if (allSessions.isNotEmpty) {
      final firstDate = allSessions.first.date;
      final daysBetween = DateTime.now().difference(firstDate).inDays.clamp(7, 3650);
      avgFreq = (allSessions.length / (daysBetween / 7.0));
    }

    // Previous session of same split
    String? prevSplitSummary;
    if (splitName != null) {
      final matches = allSessions.where((s) => s.splitDayName == splitName && s.id != activeOrCompleted?.id).toList();
      if (matches.isNotEmpty) {
        final prev = matches.first;
        prevSplitSummary = '${prev.splitDayName} on ${prev.date.month}/${prev.date.day}: ${prev.totalWorkingVolume.toStringAsFixed(0)} kg volume across ${prev.entries.length} exercises';
      }
    }

    final recentSummaries = allSessions.take(5).map((s) {
      final performed = s.entries.where((e) => !e.isSkipped && e.sets.isNotEmpty).map((e) => e.exercise.name).toList();
      return '${s.splitDayName}: ${performed.take(3).join(", ")}${performed.length > 3 ? " +${performed.length - 3}" : ""} (${s.totalWorkingVolume.toStringAsFixed(0)} kg)';
    }).toList();

    return TrainingContext(
      todaySplitDayName: splitName,
      hasWorkoutToday: hasWorkoutToday,
      isWorkoutDraftActive: draft != null,
      isGymDayScheduled: isGymDay,
      totalCompletedSessions: allSessions.length,
      averageSessionsPerWeek: double.parse(avgFreq.toStringAsFixed(1)),
      exercisesTrainedToday: exercisesTrained,
      todayDetailedEntries: detailedEntries,
      volumeTrainedTodayKg: volumeToday,
      setsLoggedToday: setsToday,
      workingSetsLoggedToday: workingSetsToday,
      warmupSetsLoggedToday: warmupSetsToday,
      previousSessionOfSameSplit: prevSplitSummary,
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
    final proPerKg = profile.weightKg != null && profile.weightKg! > 0 ? proConsumed / profile.weightKg! : null;

    final mealsLogged = <String>[];
    final sectionMap = <String, List<String>>{};

    for (final e in log.allEntries) {
      final name = e.finalSavedInput.isNotEmpty ? e.finalSavedInput : e.rawInput;
      final entryStr = '$name (${e.calMid.toStringAsFixed(0)} kcal, ${e.protMid.toStringAsFixed(1)}g pro)';
      mealsLogged.add('${e.section.displayName}: $entryStr');
      sectionMap.putIfAbsent(e.section.displayName, () => []).add(entryStr);
    }

    final topSaved = SavedMealService.instance.search('a', limit: 5).map((m) => '${m.title} (${m.calories.toStringAsFixed(0)} kcal)').toList();
    final recurring = MealMemory.instance.recurringMeals.map((m) => '${m.rawInput} (${m.result.calories.mid.toStringAsFixed(0)} kcal)').toList();
    final rememberedCount = UserNutritionMemory.instance.allOverrides.length;

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
      proteinPerKg: proPerKg,
      mealsLoggedToday: mealsLogged,
      mealsBySection: sectionMap,
      topSavedMeals: topSaved,
      recurringMeals: recurring,
      rememberedOverridesCount: rememberedCount,
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
    final proPerKg = nutrition.proteinPerKg;

    String demand;
    String status;
    String advice;

    if (!trained) {
      demand = 'low';
      if (deficit <= 10.0) {
        status = 'Rest day nutrition on track.';
        advice = 'Protein target is met for baseline cellular maintenance.';
      } else {
        status = 'Rest day recovery.';
        advice = '${deficit.toStringAsFixed(0)}g protein remaining to hit daily baseline.';
      }
    } else {
      if (training.volumeTrainedTodayKg > 5000 || training.setsLoggedToday >= 15) {
        demand = 'very_high';
      } else if (training.volumeTrainedTodayKg > 2000 || training.setsLoggedToday >= 8) {
        demand = 'high';
      } else {
        demand = 'moderate';
      }

      if (deficit <= 5.0) {
        status = 'Daily protein target met; training recovery supported.';
        advice = 'Daily target fulfilled. Maintain hydration and quality sleep to support recovery from ${training.volumeTrainedTodayKg.toStringAsFixed(0)} kg volume.';
      } else if (deficit <= 30.0) {
        status = 'Moderate protein remaining to reach target.';
        advice = 'Distribute remaining ${deficit.toStringAsFixed(0)}g protein across upcoming meals to hit your daily target.';
      } else {
        status = 'Training volume logged; protein target pending.';
        advice = 'Trained ${training.todaySplitDayName ?? "session"} (${training.workingSetsLoggedToday} working sets, ${training.volumeTrainedTodayKg.toStringAsFixed(0)} kg volume). Distribute your remaining ${deficit.toStringAsFixed(0)}g protein across your remaining meals today to meet your daily target.';
      }
    }

    return CrossDomainRecoveryContext(
      trainedToday: trained,
      workoutTrained: training.todaySplitDayName,
      totalVolumeKg: training.volumeTrainedTodayKg,
      proteinConsumedG: proConsumed,
      proteinTargetG: proTarget,
      proteinDeficitG: deficit,
      proteinPerKg: proPerKg,
      recoveryStatus: status,
      nutritionAdvice: advice,
      recoveryDemand: demand,
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
        detail: 'Logged ${training.setsLoggedToday} sets (${training.workingSetsLoggedToday} working) across ${training.exercisesTrainedToday.length} exercises (${training.volumeTrainedTodayKg.toStringAsFixed(0)} kg volume).',
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
