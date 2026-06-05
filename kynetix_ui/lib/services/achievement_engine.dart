import '../models/workout_session.dart';
import 'workout_service.dart';

class AchievementInfo {
  final String title;
  final String description;
  final String icon;
  final bool achieved;
  final double currentProgress;
  final double targetProgress;
  final String progressLabel;

  AchievementInfo({
    required this.title,
    required this.description,
    required this.icon,
    required this.achieved,
    this.currentProgress = 0,
    this.targetProgress = 0,
    this.progressLabel = '',
  });
}

class AchievementEngine {
  static List<AchievementInfo> evaluate(List<WorkoutSession> sessions, WorkoutService service) {
    final totalWorkouts = sessions.length;
    final longestStreak = _calculateLongestStreak(sessions);
    final lifetimeVolume = sessions.fold<double>(0.0, (sum, s) => sum + s.totalWorkingVolume);

    int totalPrs = 0;
    for (final session in sessions) {
      for (final entry in session.entries) {
        final top = entry.topProgressionSet ?? entry.topWorkingSet ?? entry.topSet;
        if (top == null) continue;
        final prevBest = service.bestSetBefore(entry.exercise.id, session.date);
        if (prevBest == null || top.estimatedOneRepMax > prevBest.estimatedOneRepMax + 0.01) {
          totalPrs++;
        }
      }
    }

    return [
      AchievementInfo(
        title: 'First Workout',
        description: 'Completed your very first logged session.',
        icon: '🚀',
        achieved: totalWorkouts >= 1,
        currentProgress: totalWorkouts >= 1 ? 1 : 0,
        targetProgress: 1,
        progressLabel: totalWorkouts >= 1 ? 'Completed' : '0 / 1 workout',
      ),
      AchievementInfo(
        title: '7-Day Streak',
        description: 'Trained on 7 consecutive days.',
        icon: '🔥',
        achieved: longestStreak >= 7,
        currentProgress: longestStreak.toDouble(),
        targetProgress: 7,
        progressLabel: '${longestStreak.clamp(0, 7)} / 7 days',
      ),
      AchievementInfo(
        title: '30-Day Streak',
        description: 'Trained on 30 consecutive days.',
        icon: '👑',
        achieved: longestStreak >= 30,
        currentProgress: longestStreak.toDouble(),
        targetProgress: 30,
        progressLabel: '${longestStreak.clamp(0, 30)} / 30 days',
      ),
      AchievementInfo(
        title: 'Century Club',
        description: 'Logged 100 total workouts.',
        icon: '💯',
        achieved: totalWorkouts >= 100,
        currentProgress: totalWorkouts.toDouble(),
        targetProgress: 100,
        progressLabel: '$totalWorkouts / 100 workouts',
      ),
      AchievementInfo(
        title: 'Heavy Lifter',
        description: 'Moved 10,000 kg of working volume.',
        icon: '🏋️',
        achieved: lifetimeVolume >= 10000.0,
        currentProgress: lifetimeVolume,
        targetProgress: 10000.0,
        progressLabel: '${(lifetimeVolume / 1000).toStringAsFixed(1)}k / 10k kg',
      ),
      AchievementInfo(
        title: 'Record Breaker',
        description: 'Achieved your first Personal Record.',
        icon: '🏆',
        achieved: totalPrs >= 1,
        currentProgress: totalPrs.toDouble(),
        targetProgress: 1,
        progressLabel: totalPrs >= 1 ? 'Achieved' : '0 / 1 PR',
      ),
    ];
  }

  static int _calculateLongestStreak(List<WorkoutSession> sessions) {
    if (sessions.isEmpty) return 0;
    final dates = sessions
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
