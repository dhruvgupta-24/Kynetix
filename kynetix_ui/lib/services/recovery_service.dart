// ─── RecoveryService ──────────────────────────────────────────────────────────
//
// Pure computation layer for muscle group recovery and readiness scoring.
//
// Design principles:
//   • Stateless — compute() is a pure function with no side effects.
//   • Extensible — RecoveryInput has nullable future fields (sleep, HRV, HR)
//     that can be populated as those data sources become available.
//   • Immutable inputs — accepts List<WorkoutSession> (the read-only history)
//     and never modifies it.
//
// Current computation (session-based heuristics):
//   < 24h since training → Recovering  (score ≈ 0.3)
//   24–48h               → Ready       (score ≈ 0.7)
//   > 48h                → Well rested (score ≈ 1.0)
//
// Future expansion: Add SleepData, HrvData, double restingHeartRate to
// RecoveryInput. The compute() method can then apply weighted scoring.

import '../models/workout_session.dart';

// ─── Wearable scoring engines ──────────────────────────────────────────────────

/// Configurable target range for sleep duration with linear decay outside the range.
class SleepTarget {
  final double minHours;
  final double maxHours;
  /// Linear decay per hour outside the range (e.g. 0.2 means score drops by 20% per hour)
  final double decayRate;

  const SleepTarget({
    this.minHours = 7.5,
    this.maxHours = 9.0,
    this.decayRate = 0.2,
  });

  double calculateScore(double hours) {
    if (hours >= minHours && hours <= maxHours) {
      return 1.0;
    }
    if (hours < minHours) {
      final diff = minHours - hours;
      return (1.0 - diff * decayRate).clamp(0.0, 1.0);
    } else {
      final diff = hours - maxHours;
      return (1.0 - diff * decayRate).clamp(0.0, 1.0);
    }
  }
}

/// Configurable score calculator for HRV RMSSD baseline deviation.
class HrvScorer {
  /// Ratio threshold below which score starts declining
  final double thresholdRatio;

  const HrvScorer({
    this.thresholdRatio = 1.0,
  });

  double calculateScore(double latestHrv, double baselineHrv) {
    if (baselineHrv <= 0) return 1.0;
    final ratio = latestHrv / baselineHrv;
    if (ratio >= thresholdRatio) return 1.0;
    return ratio.clamp(0.0, 1.0);
  }
}

// ─── Data model stubs ──────────────────────────────────────────────────────────

/// Sleep quality data from Health Connect.
class SleepData {
  final double? durationHours;
  final double? deepSleepPercent;  // 0.0–1.0
  final double? sleepQualityScore; // 0.0–1.0
  const SleepData({this.durationHours, this.deepSleepPercent, this.sleepQualityScore});
}

/// HRV data from Health Connect.
class HrvData {
  final double? rmssd;      // ms — standard HRV metric
  final double? sdnn;       // ms
  final double? baselineRmssd; // user's personal baseline for scoring
  const HrvData({this.rmssd, this.sdnn, this.baselineRmssd});
}

// ─── Recovery Models ──────────────────────────────────────────────────────────

enum RecoveryState {
  recovering,  // < 24h; muscle still adapting
  ready,       // 24–48h; standard recovery complete
  wellRested,  // > 48h; fully recovered
}

extension RecoveryStateX on RecoveryState {
  String get label => switch (this) {
    RecoveryState.recovering => 'Recovering',
    RecoveryState.ready      => 'Ready',
    RecoveryState.wellRested => 'Well rested',
  };

  String get emoji => switch (this) {
    RecoveryState.recovering => '🔴',
    RecoveryState.ready      => '🟡',
    RecoveryState.wellRested => '🟢',
  };
}

class MuscleGroupRecovery {
  final String muscleGroup;
  final int hoursSinceLastTraining; // -1 if never trained
  final RecoveryState state;

  /// Score 0.0–1.0. Used for visual indicators and future AI scoring.
  final double score;

  const MuscleGroupRecovery({
    required this.muscleGroup,
    required this.hoursSinceLastTraining,
    required this.state,
    required this.score,
  });

  String get label => state.label;
  String get emoji => state.emoji;
}

class RecoveryReport {
  final List<MuscleGroupRecovery> muscles;
  final double overallReadiness; // 0.0–1.0 weighted average
  final String readinessLabel;
  final int? daysSinceLastWorkout; // null if no sessions
  final double? sleepScore;
  final double? hrvScore;

  // Future fields — populated when sleep/HRV data is available
  final double? fatigueScore;       // 0.0–1.0 (future: HRV-derived)
  final String? aiRecommendation;   // future: AI-generated suggestion

  const RecoveryReport({
    required this.muscles,
    required this.overallReadiness,
    required this.readinessLabel,
    this.daysSinceLastWorkout,
    this.sleepScore,
    this.hrvScore,
    this.fatigueScore,
    this.aiRecommendation,
  });
}

// ─── Input ────────────────────────────────────────────────────────────────────

class RecoveryInput {
  final List<WorkoutSession> sessions;

  // Future data sources — all nullable, gracefully ignored when absent.
  final SleepData? sleepData;
  final HrvData? hrvData;
  final double? restingHeartRate; // bpm

  final SleepTarget? sleepTarget;
  final HrvScorer? hrvScorer;

  const RecoveryInput({
    required this.sessions,
    this.sleepData,
    this.hrvData,
    this.restingHeartRate,
    this.sleepTarget,
    this.hrvScorer,
  });
}

// ─── Service ──────────────────────────────────────────────────────────────────

class RecoveryService {
  const RecoveryService._();

  /// Computes a full [RecoveryReport] from [input].
  ///
  /// Pure function — no state, no side effects.
  static RecoveryReport compute(RecoveryInput input) {
    final now = DateTime.now();

    // 1. Find the last training date for each muscle group
    final lastTrainedAt = <String, DateTime>{};
    for (final session in input.sessions) {
      if (session.isEmpty) continue;
      for (final entry in session.entries) {
        final muscle = entry.exercise.muscleGroup;
        if (!entry.isEmpty) {
          final existing = lastTrainedAt[muscle];
          if (existing == null || session.date.isAfter(existing)) {
            lastTrainedAt[muscle] = session.date;
          }
        }
      }
    }

    // 2. Compute per-muscle recovery
    final muscleRecoveries = lastTrainedAt.entries.map((e) {
      final hours = now.difference(e.value).inHours;
      final state = _stateFromHours(hours);
      final score = _scoreFromHours(hours);
      return MuscleGroupRecovery(
        muscleGroup: e.key,
        hoursSinceLastTraining: hours,
        state: state,
        score: score,
      );
    }).toList()
      ..sort((a, b) => a.hoursSinceLastTraining.compareTo(b.hoursSinceLastTraining));

    // 3. Overall muscle recovery score (mean score across all trained muscles)
    final muscleScore = muscleRecoveries.isEmpty
        ? 1.0
        : muscleRecoveries.fold<double>(0, (s, m) => s + m.score) /
            muscleRecoveries.length;

    // 4. Days since last workout (any session)
    final sortedSessions = input.sessions.where((s) => !s.isEmpty).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final daysSince = sortedSessions.isEmpty
        ? null
        : now.difference(sortedSessions.first.date).inDays;

    // 5. Apply sleep/HRV weighting with weight redistribution
    double totalWeight = 0.4;
    double weightedScore = muscleScore * 0.4;

    double? sleepScore;
    if (input.sleepData != null && input.sleepData!.durationHours != null) {
      final target = input.sleepTarget ?? const SleepTarget();
      sleepScore = target.calculateScore(input.sleepData!.durationHours!);
      weightedScore += sleepScore * 0.3;
      totalWeight += 0.3;
    }

    double? hrvScore;
    if (input.hrvData != null && input.hrvData!.rmssd != null && input.hrvData!.baselineRmssd != null) {
      final scorer = input.hrvScorer ?? const HrvScorer();
      hrvScore = scorer.calculateScore(input.hrvData!.rmssd!, input.hrvData!.baselineRmssd!);
      weightedScore += hrvScore * 0.3;
      totalWeight += 0.3;
    }

    final overall = totalWeight > 0 ? (weightedScore / totalWeight).clamp(0.0, 1.0) : 1.0;

    return RecoveryReport(
      muscles: muscleRecoveries,
      overallReadiness: overall,
      readinessLabel: _readinessLabel(overall, daysSince),
      daysSinceLastWorkout: daysSince,
      sleepScore: sleepScore,
      hrvScore: hrvScore,
    );
  }

  static RecoveryState _stateFromHours(int hours) {
    if (hours < 24) return RecoveryState.recovering;
    if (hours < 48) return RecoveryState.ready;
    return RecoveryState.wellRested;
  }

  static double _scoreFromHours(int hours) {
    if (hours < 24) return 0.0 + (hours / 24.0) * 0.4; // 0.0 → 0.4
    if (hours < 48) return 0.4 + ((hours - 24) / 24.0) * 0.4; // 0.4 → 0.8
    return (0.8 + ((hours - 48) / 24.0) * 0.2).clamp(0.8, 1.0); // 0.8 → 1.0
  }

  static String _readinessLabel(double overall, int? daysSince) {
    if (daysSince == null) return 'No training history yet';
    if (overall >= 0.8) return 'Fully recovered';
    if (overall >= 0.6) return 'Ready to train';
    if (overall >= 0.4) return 'Partial recovery';
    return 'Still recovering';
  }
}
