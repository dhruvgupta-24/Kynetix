import 'dart:math' show max;
import '../models/workout_session.dart';
import '../models/workout_split.dart';
import '../services/workout_service.dart';

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

  // ── Heatmap Data
  final List<HeatmapDay> heatmapDays;
  final double maxDailyVolume;

  // ── Muscle Analytics
  final Map<String, int> muscleFrequencies;
  final Map<String, double> muscleVolumes;
  final double pushPullRatio; // 0.0 to 1.0 (pushSets / total)
  final double upperLowerRatio; // 0.0 to 1.0 (upperSets / total)
  final List<MuscleNeglectInfo> neglectedMuscles;

  // ── Exercise Analytics
  final List<ExerciseAnalyticInfo> exerciseAnalytics;

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
    required this.heatmapDays,
    required this.maxDailyVolume,
    required this.muscleFrequencies,
    required this.muscleVolumes,
    required this.pushPullRatio,
    required this.upperLowerRatio,
    required this.neglectedMuscles,
    required this.exerciseAnalytics,
    required this.achievements,
  });

  // ── Factory Constructor for dynamic calculations
  factory WorkoutHistoryViewModel.compute({
    required WorkoutService service,
    required TimeRangeFilter filter,
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
        if (entry.isEmpty) continue;
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

    // Neglect Detection: Days since last trained
    final muscleLastTrained = <String, DateTime>{};
    for (final session in all) {
      for (final entry in session.entries) {
        if (entry.isEmpty) continue;
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
        if (entry.isEmpty) continue;
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

    // 7. Heatmap calculations (Last 52 weeks, aligned to Mon-Sun grids)
    final heatmapDays = <HeatmapDay>[];
    double maxDailyVolume = 0.0;

    final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
    final startDate = startOfWeek.subtract(const Duration(days: 364)); // 52 weeks ago Mon

    // Group sessions by exact date key YYYY-MM-DD
    final sessionsByDate = <String, List<WorkoutSession>>{};
    for (final s in all) {
      final key = _dateKey(s.date);
      sessionsByDate.putIfAbsent(key, () => []).add(s);
    }

    for (int i = 0; i <= 370; i++) {
      final date = startDate.add(Duration(days: i));
      if (date.isAfter(today)) break; // stop at today
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

    // 8. Exercise Analytics
    final uniqueExercises = <String, Exercise>{};
    for (final session in all) {
      for (final entry in session.entries) {
        if (!entry.isEmpty) {
          uniqueExercises[entry.exercise.id] = entry.exercise;
        }
      }
    }

    final exerciseAnalytics = <ExerciseAnalyticInfo>[];
    for (final exercise in uniqueExercises.values) {
      final exSessions = all.where((s) => s.entries.any((e) => e.exercise.id == exercise.id && !e.isEmpty)).toList();
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
      if (daysSinceTrained > 10) {
        insightsList.add('${exercise.name} has not been trained in $daysSinceTrained days.');
      } else if (prev30DayTrendPct > 5.0) {
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

    // 9. Achievements List
    final totalAllTimeWorkouts = all.length;
    final totalAllTimeVolume = all.fold<double>(0.0, (sum, s) => sum + s.totalWorkingVolume);
    final totalAllTimePrs = all.fold<int>(0, (sum, s) {
      int sPr = 0;
      for (final entry in s.entries) {
        final top = entry.topProgressionSet ?? entry.topWorkingSet ?? entry.topSet;
        if (top == null) continue;
        final prevBest = service.bestSetBefore(entry.exercise.id, s.date);
        if (prevBest == null || top.estimatedOneRepMax > prevBest.estimatedOneRepMax + 0.01) {
          sPr++;
        }
      }
      return sum + sPr;
    });

    final achievements = [
      AchievementInfo(
        title: 'First Workout',
        description: 'Completed your very first logged session.',
        icon: '🚀',
        achieved: totalAllTimeWorkouts >= 1,
      ),
      AchievementInfo(
        title: '7-Day Streak',
        description: 'Trained on 7 consecutive days.',
        icon: '🔥',
        achieved: longestStreak >= 7,
      ),
      AchievementInfo(
        title: '30-Day Streak',
        description: 'Trained on 30 consecutive days.',
        icon: '👑',
        achieved: longestStreak >= 30,
      ),
      AchievementInfo(
        title: 'Century Club',
        description: 'Logged 100 total workouts.',
        icon: '💯',
        achieved: totalAllTimeWorkouts >= 100,
      ),
      AchievementInfo(
        title: 'Heavy Lifter',
        description: 'Moved 10,000 kg of working volume.',
        icon: '🏋️',
        achieved: totalAllTimeVolume >= 10000.0,
      ),
      AchievementInfo(
        title: 'Record Breaker',
        description: 'Achieved your first Personal Record.',
        icon: '🏆',
        achieved: totalAllTimePrs >= 1,
      ),
    ];

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
      heatmapDays: heatmapDays,
      maxDailyVolume: maxDailyVolume,
      muscleFrequencies: muscleFreqs,
      muscleVolumes: muscleVols,
      pushPullRatio: pushPullRatio,
      upperLowerRatio: upperLowerRatio,
      neglectedMuscles: neglectedMuscles,
      exerciseAnalytics: exerciseAnalytics,
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

class AchievementInfo {
  final String title;
  final String description;
  final String icon;
  final bool achieved;

  AchievementInfo({
    required this.title,
    required this.description,
    required this.icon,
    required this.achieved,
  });
}
