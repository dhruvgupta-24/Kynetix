import 'dart:math' show max;
import '../models/workout_session.dart';
import '../models/workout_split.dart';
import '../services/workout_service.dart';
import '../services/achievement_engine.dart' show AchievementInfo, AchievementEngine;

enum TimeRangeFilter {
  last7Days,
  last30Days,
  last90Days,
  thisYear,
  allTime,
}

extension TimeRangeFilterExtension on TimeRangeFilter {
  String get label => switch (this) {
        TimeRangeFilter.last7Days => '7 Days',
        TimeRangeFilter.last30Days => '30 Days',
        TimeRangeFilter.last90Days => '90 Days',
        TimeRangeFilter.thisYear => 'This Year',
        TimeRangeFilter.allTime => 'All Time',
      };
}

class WorkoutHistoryViewModel {
  final TimeRangeFilter filter;
  final List<WorkoutSession> allSessions;

  // ── First-Class Analytics
  final List<WorkoutSession> filteredSessions;
  final int totalWorkouts;
  final int totalSets;
  final double totalVolume;
  final double totalHours;
  final double averageDuration;
  final int currentStreak;
  final int longestStreak;
  final int totalPrs;
  final String mostTrainedMuscle;
  final String mostPerformedExercise;

  // ── Chronological Grouped Sessions
  final Map<String, List<WorkoutSession>> chronologicalGroups;

  // ── Heatmap Data
  final List<HeatmapDay> heatmapDays;
  final double maxDailyVolume;
  final double percentileVolume90;

  // ── Muscle Analytics
  final Map<String, int> muscleFrequencies;
  final Map<String, double> muscleVolumes;
  Map<String, double> get muscleVolumeBreakdown => muscleVolumes;
  final double pushPullRatio; // 0.0 to 1.0 (pushSets / total)
  final double upperLowerRatio; // 0.0 to 1.0 (upperSets / total)
  final double pushPullBalanceScore; // 0.0 to 100.0
  final String pushPullBalanceLabel;
  final double upperLowerBalanceScore; // 0.0 to 100.0
  final String upperLowerBalanceLabel;
  final List<MuscleNeglectInfo> neglectedMuscles;

  // ── Exercise Analytics
  final List<ExerciseAnalyticInfo> exerciseAnalytics;

  // ── Consistency Analytics
  final double workoutsPerWeek;
  final double averageDaysBetweenWorkouts;
  final int missedPlannedWorkouts;
  final String mostCommonTrainingDay;

  // ── Exercise Rankings
  final ExerciseAnalyticInfo? mostTrainedExercise;
  final ExerciseAnalyticInfo? highestVolumeExercise;
  final ExerciseAnalyticInfo? strongestExercise;
  final ExerciseAnalyticInfo? fastestGrowingExercise;

  // ── Achievements
  final List<AchievementInfo> achievements;

  WorkoutHistoryViewModel({
    required this.filter,
    required this.allSessions,
    required this.filteredSessions,
    required this.totalWorkouts,
    required this.totalSets,
    required this.totalVolume,
    required this.totalHours,
    required this.averageDuration,
    required this.currentStreak,
    required this.longestStreak,
    required this.totalPrs,
    required this.mostTrainedMuscle,
    required this.mostPerformedExercise,
    required this.chronologicalGroups,
    required this.heatmapDays,
    required this.maxDailyVolume,
    required this.percentileVolume90,
    required this.muscleFrequencies,
    required this.muscleVolumes,
    required this.pushPullRatio,
    required this.upperLowerRatio,
    required this.pushPullBalanceScore,
    required this.pushPullBalanceLabel,
    required this.upperLowerBalanceScore,
    required this.upperLowerBalanceLabel,
    required this.neglectedMuscles,
    required this.exerciseAnalytics,
    required this.workoutsPerWeek,
    required this.averageDaysBetweenWorkouts,
    required this.missedPlannedWorkouts,
    required this.mostCommonTrainingDay,
    this.mostTrainedExercise,
    this.highestVolumeExercise,
    this.strongestExercise,
    this.fastestGrowingExercise,
    required this.achievements,
  });

  // ── Factory Constructor for dynamic calculations
  factory WorkoutHistoryViewModel.compute({
    required WorkoutService service,
    required TimeRangeFilter filter,
    int? heatmapYear,
  }) {
    // 1. Get all non-empty sessions sorted oldest-to-newest for chronological stats
    final all = service.sessions.where((s) => !s.isEmpty).toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    // 2. Apply time range filter
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final filtered = all.where((s) {
      final sDate = DateTime(s.date.year, s.date.month, s.date.day);
      switch (filter) {
        case TimeRangeFilter.last7Days:
          return sDate.isAfter(today.subtract(const Duration(days: 7)));
        case TimeRangeFilter.last30Days:
          return sDate.isAfter(today.subtract(const Duration(days: 30)));
        case TimeRangeFilter.last90Days:
          return sDate.isAfter(today.subtract(const Duration(days: 90)));
        case TimeRangeFilter.thisYear:
          return sDate.year == now.year;
        case TimeRangeFilter.allTime:
          return true;
      }
    }).toList();

    // 3. Simple Stats
    final totalWorkouts = filtered.length;
    final totalSets = filtered.fold<int>(0, (sum, s) => sum + s.totalSets);
    final totalVolume = filtered.fold<double>(0.0, (sum, s) => sum + s.totalWorkingVolume);
    final totalHours = filtered.fold<double>(
      0.0,
      (sum, s) => sum + (s.durationMinutes ?? 45) / 60.0,
    );

    final sessionsWithDuration = filtered.where((s) => s.durationMinutes != null).toList();
    final averageDuration = sessionsWithDuration.isEmpty
        ? 0.0
        : sessionsWithDuration.fold<double>(0.0, (sum, s) => sum + s.durationMinutes!) /
            sessionsWithDuration.length;

    // 4. Streaks (calculated globally across all sessions)
    final currentStreak = service.currentStreak;
    final longestStreak = _calculateLongestStreak(all);

    // 5. Total PRs achieved within the filtered sessions
    int totalPrs = 0;
    for (final session in filtered) {
      for (final entry in session.entries) {
        if (entry.isSkipped) continue;
        final top = entry.topProgressionSet ?? entry.topWorkingSet ?? entry.topSet;
        if (top == null) continue;
        final prevBest = service.bestSetBefore(entry.exercise.id, session.date);
        if (prevBest == null || top.estimatedOneRepMax > prevBest.estimatedOneRepMax + 0.01) {
          totalPrs++;
        }
      }
    }

    // 6. Muscle Group Frequency and Volumes
    final muscleFreqs = <String, int>{};
    final muscleVols = <String, double>{};
    int pushSets = 0;
    int pullSets = 0;
    int upperSets = 0;
    int lowerSets = 0;

    for (final session in filtered) {
      for (final entry in session.entries) {
        if (entry.isEmpty || entry.isSkipped) continue;
        final muscle = entry.exercise.muscleGroup.trim().toLowerCase();
        final setsCount = entry.sets.length;
        final vol = entry.workingVolume;

        muscleFreqs[entry.exercise.muscleGroup] =
            (muscleFreqs[entry.exercise.muscleGroup] ?? 0) + setsCount;
        muscleVols[entry.exercise.muscleGroup] =
            (muscleVols[entry.exercise.muscleGroup] ?? 0) + vol;

        // Categorize
        if (_isPush(muscle)) {
          pushSets += setsCount;
        } else if (_isPull(muscle)) {
          pullSets += setsCount;
        }

        if (_isUpper(muscle)) {
          upperSets += setsCount;
        } else if (_isLower(muscle)) {
          lowerSets += setsCount;
        }
      }
    }

    final totalPushPull = pushSets + pullSets;
    final pushPullRatio = totalPushPull == 0 ? 0.5 : pushSets / totalPushPull;

    final totalUpperLower = upperSets + lowerSets;
    final upperLowerRatio = totalUpperLower == 0 ? 0.5 : upperSets / totalUpperLower;

    // Muscle balance scores (100 is perfectly symmetric, decreases as it skews)
    final pushPullBalanceScore = totalPushPull == 0 ? 100.0 : (100.0 - (pushPullRatio - 0.5).abs() * 200.0).clamp(0.0, 100.0);
    final pushPullBalanceLabel = pushPullBalanceScore >= 90
        ? 'Perfect Symmetry'
        : pushPullBalanceScore >= 75
            ? 'Good Balance'
            : 'Imbalanced training';

    final upperLowerBalanceScore = totalUpperLower == 0 ? 100.0 : (100.0 - (upperLowerRatio - 0.5).abs() * 200.0).clamp(0.0, 100.0);
    final upperLowerBalanceLabel = upperLowerBalanceScore >= 90
        ? 'Perfect Symmetry'
        : upperLowerBalanceScore >= 75
            ? 'Good Balance'
            : 'Imbalanced training';

    // Neglect Detection: Days since last trained
    final muscleLastTrained = <String, DateTime>{};
    for (final session in all) {
      for (final entry in session.entries) {
        if (entry.isEmpty || entry.isSkipped) continue;
        final currentLast = muscleLastTrained[entry.exercise.muscleGroup];
        if (currentLast == null || session.date.isAfter(currentLast)) {
          muscleLastTrained[entry.exercise.muscleGroup] = session.date;
        }
      }
    }

    // List of standard muscles to check neglect
    final allKnownMuscles = {
      'Chest',
      'Back',
      'Shoulders',
      'Quads',
      'Hamstrings',
      'Biceps',
      'Triceps',
      'Abs',
      'Calves',
      'Glutes'
    };
    final neglectedMuscles = <MuscleNeglectInfo>[];
    for (final m in allKnownMuscles) {
      final lastDate = muscleLastTrained[m];
      final days = lastDate == null ? 999 : today.difference(lastDate).inDays;
      neglectedMuscles.add(MuscleNeglectInfo(muscleGroup: m, daysSinceLastTrained: days));
    }
    neglectedMuscles.sort((a, b) => b.daysSinceLastTrained.compareTo(a.daysSinceLastTrained));

    // Most trained muscle
    String mostTrainedMuscle = 'N/A';
    int maxMuscleSets = -1;
    muscleFreqs.forEach((m, count) {
      if (count > maxMuscleSets) {
        maxMuscleSets = count;
        mostTrainedMuscle = m;
      }
    });

    // Most performed exercise
    final exerciseCounts = <String, int>{};
    for (final session in filtered) {
      for (final entry in session.entries) {
        if (entry.isEmpty || entry.isSkipped) continue;
        exerciseCounts[entry.exercise.name] = (exerciseCounts[entry.exercise.name] ?? 0) + 1;
      }
    }
    String mostPerformedExercise = 'N/A';
    int maxExCount = -1;
    exerciseCounts.forEach((ex, count) {
      if (count > maxExCount) {
        maxExCount = count;
        mostPerformedExercise = ex;
      }
    });

    // 7. Heatmap calculations (Year-based Mon-Sun grid)
    final heatmapDays = <HeatmapDay>[];
    double maxDailyVolume = 0.0;

    final year = heatmapYear ?? now.year;
    final yearStart = DateTime(year, 1, 1);
    final yearEnd = DateTime(year, 12, 31);
    final startMonday = yearStart.subtract(Duration(days: yearStart.weekday - 1));
    final endSunday = yearEnd.add(Duration(days: 7 - yearEnd.weekday));
    final limitDate = year == now.year ? today : endSunday;

    // Group sessions by exact date key YYYY-MM-DD
    final sessionsByDate = <String, List<WorkoutSession>>{};
    for (final s in all) {
      final key = _dateKey(s.date);
      sessionsByDate.putIfAbsent(key, () => []).add(s);
    }

    final daysToGenerate = limitDate.difference(startMonday).inDays;
    for (int i = 0; i <= daysToGenerate; i++) {
      final date = startMonday.add(Duration(days: i));
      final key = _dateKey(date);
      final daysSessions = sessionsByDate[key] ?? [];
      final vol = daysSessions.fold<double>(0.0, (sum, s) => sum + s.totalWorkingVolume);
      if (vol > maxDailyVolume) maxDailyVolume = vol;

      heatmapDays.add(HeatmapDay(
        date: date,
        sessions: daysSessions,
        totalVolume: vol,
      ));
    }

    // 90th percentile daily volume calculation for scaling colors
    final activeVolumes = heatmapDays
        .map((d) => d.totalVolume)
        .where((v) => v > 0)
        .toList()
      ..sort();
    double percentileVolume90 = 0.0;
    if (activeVolumes.isNotEmpty) {
      final index = (activeVolumes.length * 0.9).floor().clamp(0, activeVolumes.length - 1);
      percentileVolume90 = activeVolumes[index];
    }
    if (percentileVolume90 <= 0.0) {
      percentileVolume90 = maxDailyVolume > 0 ? maxDailyVolume : 1000.0;
    }

    // 8. Exercise Analytics
    final uniqueExercises = <String, Exercise>{};
    for (final session in all) {
      for (final entry in session.entries) {
        if (!entry.isEmpty && !entry.isSkipped) {
          uniqueExercises[entry.exercise.id] = entry.exercise;
        }
      }
    }

    final exerciseAnalytics = <ExerciseAnalyticInfo>[];
    for (final exercise in uniqueExercises.values) {
      final exSessions = all.where((s) => s.entries.any((e) => e.exercise.id == exercise.id && !e.isEmpty && !e.isSkipped)).toList();
      if (exSessions.isEmpty) continue;

      final lifetimeVolume = exSessions.fold<double>(0.0, (sum, s) {
        final entry = s.entries.firstWhere((e) => e.exercise.id == exercise.id);
        return sum + entry.workingVolume;
      });

      final totalExSets = exSessions.fold<int>(0, (sum, s) {
        final entry = s.entries.firstWhere((e) => e.exercise.id == exercise.id);
        return sum + entry.sets.length;
      });

      final bestSet = service.bestSetEver(exercise.id);
      final bestE1rm = bestSet?.estimatedOneRepMax ?? 0.0;

      // Trends
      final currentTrend = service.exerciseTrendDelta(exercise.id);

      // Volume last 30 days vs 30 days before that
      final start30 = today.subtract(const Duration(days: 30));
      final start60 = today.subtract(const Duration(days: 60));

      double volLast30 = 0.0;
      double volPrev30 = 0.0;

      for (final s in exSessions) {
        final sDate = DateTime(s.date.year, s.date.month, s.date.day);
        final entry = s.entries.firstWhere((e) => e.exercise.id == exercise.id);
        if (sDate.isAfter(start30)) {
          volLast30 += entry.workingVolume;
        } else if (sDate.isAfter(start60)) {
          volPrev30 += entry.workingVolume;
        }
      }

      double prev30DayTrendPct = 0.0;
      if (volPrev30 > 0) {
        prev30DayTrendPct = ((volLast30 - volPrev30) / volPrev30) * 100.0;
      }

      final lastSession = exSessions.last;

      // Smart Dynamic Insights
      final insightsList = <String>[];
      final daysSinceTrained = today.difference(lastSession.date).inDays;
      if (daysSinceTrained >= 7) {
        insightsList.add('${exercise.name} has not been trained in $daysSinceTrained days.');
      }
      
      if (prev30DayTrendPct > 5.0) {
        insightsList.add('${exercise.name} volume is up ${prev30DayTrendPct.toStringAsFixed(0)}% over the last 30 days.');
      } else if (prev30DayTrendPct < -5.0) {
        insightsList.add('${exercise.name} volume is down ${prev30DayTrendPct.abs().toStringAsFixed(0)}% over the last 30 days.');
      }

      if (currentTrend > 1.5) {
        insightsList.add('e1RM is trending upward (+${currentTrend.toStringAsFixed(1)} kg recently).');
      }

      exerciseAnalytics.add(ExerciseAnalyticInfo(
        exercise: exercise,
        lifetimeVolume: lifetimeVolume,
        totalSets: totalExSets,
        totalSessions: exSessions.length,
        bestSet: bestSet,
        bestE1rm: bestE1rm,
        currentTrend: currentTrend,
        prev30DayTrendPct: prev30DayTrendPct,
        lastPerformed: lastSession.date,
        insights: insightsList,
      ));
    }

    // Evaluate rankings
    ExerciseAnalyticInfo? mostTrained;
    ExerciseAnalyticInfo? highestVolume;
    ExerciseAnalyticInfo? strongest;
    ExerciseAnalyticInfo? fastestGrowing;

    for (final info in exerciseAnalytics) {
      if (mostTrained == null || info.totalSessions > mostTrained.totalSessions) {
        mostTrained = info;
      }
      if (highestVolume == null || info.lifetimeVolume > highestVolume.lifetimeVolume) {
        highestVolume = info;
      }
      if (strongest == null || info.bestE1rm > strongest.bestE1rm) {
        strongest = info;
      }
      if (info.currentTrend > 0.0) {
        if (fastestGrowing == null || info.currentTrend > fastestGrowing.currentTrend) {
          fastestGrowing = info;
        }
      }
    }

    // Evaluate Consistency Metrics
    double filterWeeks = 1.0;
    DateTime filterStartDate = today;
    switch (filter) {
      case TimeRangeFilter.last7Days:
        filterStartDate = today.subtract(const Duration(days: 7));
        filterWeeks = 1.0;
      case TimeRangeFilter.last30Days:
        filterStartDate = today.subtract(const Duration(days: 30));
        filterWeeks = 30.0 / 7.0;
      case TimeRangeFilter.last90Days:
        filterStartDate = today.subtract(const Duration(days: 90));
        filterWeeks = 90.0 / 7.0;
      case TimeRangeFilter.thisYear:
        filterStartDate = DateTime(now.year, 1, 1);
        final elapsedDays = today.difference(filterStartDate).inDays + 1;
        filterWeeks = max(1.0, elapsedDays / 7.0);
      case TimeRangeFilter.allTime:
        filterStartDate = all.isEmpty ? today : all.first.date;
        final elapsedDays = today.difference(filterStartDate).inDays + 1;
        filterWeeks = max(1.0, elapsedDays / 7.0);
    }
    final workoutsPerWeek = totalWorkouts / filterWeeks;

    // Average days between workouts
    double averageDaysBetweenWorkouts = 0.0;
    if (filtered.length >= 2) {
      int totalGapDays = 0;
      for (int i = 1; i < filtered.length; i++) {
        totalGapDays += filtered[i].date.difference(filtered[i - 1].date).inDays;
      }
      averageDaysBetweenWorkouts = totalGapDays / (filtered.length - 1);
    }

    // Missed planned workouts
    int missedPlannedWorkouts = 0;
    final normalizedFilterStartDate = DateTime(filterStartDate.year, filterStartDate.month, filterStartDate.day);
    final plannedTrainingWeekdays = service.trainingDays.map((d) => d.weekday).toSet();
    final sessionDateKeys = all.map((s) => _dateKey(s.date)).toSet();

    if (plannedTrainingWeekdays.isNotEmpty) {
      final daysDiff = today.difference(normalizedFilterStartDate).inDays;
      for (int i = 0; i <= daysDiff; i++) {
        final dateToCheck = normalizedFilterStartDate.add(Duration(days: i));
        if (dateToCheck.isAfter(today)) break;
        if (plannedTrainingWeekdays.contains(dateToCheck.weekday)) {
          if (!sessionDateKeys.contains(_dateKey(dateToCheck))) {
            missedPlannedWorkouts++;
          }
        }
      }
    }

    // Most common training day
    final weekdayCounts = <int, int>{};
    for (final s in filtered) {
      final wd = s.date.weekday;
      weekdayCounts[wd] = (weekdayCounts[wd] ?? 0) + 1;
    }
    int bestWd = -1;
    int maxWdCount = -1;
    weekdayCounts.forEach((wd, count) {
      if (count > maxWdCount) {
        maxWdCount = count;
        bestWd = wd;
      }
    });
    final mostCommonTrainingDay = bestWd == -1
        ? 'N/A'
        : switch (bestWd) {
            1 => 'Monday',
            2 => 'Tuesday',
            3 => 'Wednesday',
            4 => 'Thursday',
            5 => 'Friday',
            6 => 'Saturday',
            7 => 'Sunday',
            _ => 'N/A',
          };

    // Evaluate Grouped Sessions for Sessions Tab
    final chronologicalGroups = <String, List<WorkoutSession>>{
      'Today': [],
      'Yesterday': [],
      'This Week': [],
      'Last Week': [],
      'Older': [],
    };

    final yesterday = today.subtract(const Duration(days: 1));
    final thisMonday = today.subtract(Duration(days: today.weekday - 1));
    final lastMonday = thisMonday.subtract(const Duration(days: 7));

    for (final s in all.reversed) {
      final sDate = DateTime(s.date.year, s.date.month, s.date.day);
      if (sDate == today) {
        chronologicalGroups['Today']!.add(s);
      } else if (sDate == yesterday) {
        chronologicalGroups['Yesterday']!.add(s);
      } else if (!sDate.isBefore(thisMonday)) {
        chronologicalGroups['This Week']!.add(s);
      } else if (!sDate.isBefore(lastMonday)) {
        chronologicalGroups['Last Week']!.add(s);
      } else {
        chronologicalGroups['Older']!.add(s);
      }
    }

    chronologicalGroups.removeWhere((key, list) => list.isEmpty);

    // Evaluate Achievements
    final achievements = AchievementEngine.evaluate(all, service);

    return WorkoutHistoryViewModel(
      filter: filter,
      allSessions: all.reversed.toList(), // Chronological list newest-first
      filteredSessions: filtered,
      totalWorkouts: totalWorkouts,
      totalSets: totalSets,
      totalVolume: totalVolume,
      totalHours: totalHours,
      averageDuration: averageDuration,
      currentStreak: currentStreak,
      longestStreak: longestStreak,
      totalPrs: totalPrs,
      mostTrainedMuscle: mostTrainedMuscle,
      mostPerformedExercise: mostPerformedExercise,
      chronologicalGroups: chronologicalGroups,
      heatmapDays: heatmapDays,
      maxDailyVolume: maxDailyVolume,
      percentileVolume90: percentileVolume90,
      muscleFrequencies: muscleFreqs,
      muscleVolumes: muscleVols,
      pushPullRatio: pushPullRatio,
      upperLowerRatio: upperLowerRatio,
      pushPullBalanceScore: pushPullBalanceScore,
      pushPullBalanceLabel: pushPullBalanceLabel,
      upperLowerBalanceScore: upperLowerBalanceScore,
      upperLowerBalanceLabel: upperLowerBalanceLabel,
      neglectedMuscles: neglectedMuscles,
      exerciseAnalytics: exerciseAnalytics,
      workoutsPerWeek: workoutsPerWeek,
      averageDaysBetweenWorkouts: averageDaysBetweenWorkouts,
      missedPlannedWorkouts: missedPlannedWorkouts,
      mostCommonTrainingDay: mostCommonTrainingDay,
      mostTrainedExercise: mostTrained,
      highestVolumeExercise: highestVolume,
      strongestExercise: strongest,
      fastestGrowingExercise: fastestGrowing,
      achievements: achievements,
    );
  }

  // ── Helpers
  static bool _isPush(String muscle) => const {
        'chest',
        'shoulders',
        'triceps',
        'quads',
        'calves'
      }.contains(muscle);

  static bool _isPull(String muscle) => const {
        'back',
        'biceps',
        'hamstrings',
        'lats'
      }.contains(muscle);

  static bool _isUpper(String muscle) => const {
        'chest',
        'back',
        'shoulders',
        'biceps',
        'triceps',
        'forearms',
        'traps',
        'lats'
      }.contains(muscle);

  static bool _isLower(String muscle) => const {
        'quads',
        'hamstrings',
        'glutes',
        'calves',
        'legs',
        'abs',
        'core'
      }.contains(muscle);

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static int _calculateLongestStreak(List<WorkoutSession> sortedChronologically) {
    if (sortedChronologically.isEmpty) return 0;
    final dates = sortedChronologically
        .map((s) => DateTime(s.date.year, s.date.month, s.date.day))
        .toSet()
        .toList()
      ..sort((a, b) => a.compareTo(b));

    int maxStreak = 0;
    int current = 0;
    DateTime? prev;

    for (final d in dates) {
      if (prev == null) {
        current = 1;
      } else {
        final diff = d.difference(prev).inDays;
        if (diff == 1) {
          current++;
        } else if (diff > 1) {
          if (current > maxStreak) maxStreak = current;
          current = 1;
        }
      }
      prev = d;
    }
    if (current > maxStreak) maxStreak = current;
    return maxStreak;
  }
}

class HeatmapDay {
  final DateTime date;
  final List<WorkoutSession> sessions;
  final double totalVolume;

  HeatmapDay({
    required this.date,
    required this.sessions,
    required this.totalVolume,
  });
}

class MuscleNeglectInfo {
  final String muscleGroup;
  final int daysSinceLastTrained;

  MuscleNeglectInfo({
    required this.muscleGroup,
    required this.daysSinceLastTrained,
  });
}

class ExerciseAnalyticInfo {
  final Exercise exercise;
  final double lifetimeVolume;
  final int totalSets;
  final int totalSessions;
  final SetEntry? bestSet;
  final double bestE1rm;
  final double currentTrend;
  final double prev30DayTrendPct;
  final DateTime lastPerformed;
  final List<String> insights;

  ExerciseAnalyticInfo({
    required this.exercise,
    required this.lifetimeVolume,
    required this.totalSets,
    required this.totalSessions,
    required this.bestSet,
    required this.bestE1rm,
    required this.currentTrend,
    required this.prev30DayTrendPct,
    required this.lastPerformed,
    required this.insights,
  });
}
