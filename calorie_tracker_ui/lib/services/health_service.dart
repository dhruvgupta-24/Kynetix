import 'package:health/health.dart';

// ─── Result types ──────────────────────────────────────────────────────────────

enum ActivityTier {
  sedentary, // < 4 000 steps
  light,     // 4 000 – 7 000
  moderate,  // 7 000 – 10 000
  high;      // 10 000+

  String get displayName => switch (this) {
        ActivityTier.sedentary => 'Sedentary',
        ActivityTier.light     => 'Light',
        ActivityTier.moderate  => 'Moderate',
        ActivityTier.high      => 'High',
      };

  String get emoji => switch (this) {
        ActivityTier.sedentary => '🪑',
        ActivityTier.light     => '🚶',
        ActivityTier.moderate  => '🏃',
        ActivityTier.high      => '⚡',
      };
}

ActivityTier _tierFromSteps(double steps) {
  if (steps < 4000)  return ActivityTier.sedentary;
  if (steps < 7000)  return ActivityTier.light;
  if (steps < 10000) return ActivityTier.moderate;
  return ActivityTier.high;
}

class HealthSyncResult {
  final double?       averageDailySteps14d;
  final double?       averageDailySteps30d;
  final double?       effectiveAverageSteps;
  final ActivityTier  activityTier;
  final DateTime      syncedAt;
  final String?       error;

  const HealthSyncResult({
    this.averageDailySteps14d,
    this.averageDailySteps30d,
    this.effectiveAverageSteps,
    this.activityTier = ActivityTier.sedentary,
    required this.syncedAt,
    this.error,
  });

  bool get hasData  => effectiveAverageSteps != null;
  bool get hasError => error != null;

  /// TDEE step-correction offset (kcal) based on effective daily steps.
  int get stepCalorieOffset {
    final steps = effectiveAverageSteps;
    if (steps == null) return 0;
    if (steps < 4000)  return -150;
    if (steps < 7000)  return 0;
    if (steps < 10000) return 120;
    return 220;
  }
}

// ─── Service ──────────────────────────────────────────────────────────────────

class HealthService {
  static final HealthService _instance = HealthService._();
  factory HealthService() => _instance;
  HealthService._();

  final _health = Health();

  static const _types = [HealthDataType.STEPS];
  static const _permissions = [HealthDataAccess.READ];

  // ── Public API ─────────────────────────────────────────────────────────────

  /// True if Health Connect is installed and usable on this device.
  Future<bool> isAvailable() async {
    try {
      final state = await _health.getHealthConnectSdkStatus();
      return state == HealthConnectSdkStatus.sdkAvailable;
    } catch (_) {
      return false;
    }
  }

  /// True if READ_STEPS permission is already granted.
  Future<bool> hasPermission() async {
    try {
      final granted = await _health.hasPermissions(_types, permissions: _permissions);
      return granted == true;
    } catch (_) {
      return false;
    }
  }

  /// Opens the Health Connect permission dialog.
  /// Returns true if the user granted READ_STEPS.
  Future<bool> requestPermission() async {
    try {
      return await _health.requestAuthorization(_types, permissions: _permissions);
    } catch (_) {
      return false;
    }
  }

  /// Reads step history and returns a [HealthSyncResult].
  /// Never throws — errors are captured in result.error.
  Future<HealthSyncResult> sync() async {
    final now = DateTime.now();

    try {
      final hasPerm = await hasPermission();
      if (!hasPerm) {
        return HealthSyncResult(
          syncedAt: now,
          error: 'Permission not granted. Tap Connect to authorise.',
        );
      }

      final avg14 = await _computeAvgSteps(now, 14);
      final avg30 = await _computeAvgSteps(now, 30);

      // Prefer 30-day average; fall back to 14-day.
      final effective = avg30 ?? avg14;

      return HealthSyncResult(
        averageDailySteps14d:  avg14,
        averageDailySteps30d:  avg30,
        effectiveAverageSteps: effective,
        activityTier: effective != null ? _tierFromSteps(effective) : ActivityTier.sedentary,
        syncedAt: now,
      );
    } catch (e) {
      return HealthSyncResult(
        syncedAt: now,
        error: 'Sync failed: ${e.toString().split('\n').first}',
      );
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  /// Fetches total steps per day over the past [days] days.
  /// Ignores days with zero steps (device off / not worn).
  /// Returns null if no valid days found.
  Future<double?> _computeAvgSteps(DateTime now, int days) async {
    final totals = <double>[];

    for (int i = 0; i < days; i++) {
      final dayStart = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: i));
      final dayEnd = dayStart.add(const Duration(days: 1));

      try {
        final steps = await _health.getTotalStepsInInterval(dayStart, dayEnd);
        if (steps != null && steps > 0) {
          totals.add(steps.toDouble());
        }
      } catch (_) {
        // Skip days that error (e.g. historical data not available)
      }
    }

    if (totals.isEmpty) return null;
    final sum = totals.fold<double>(0, (a, b) => a + b);
    return double.parse((sum / totals.length).toStringAsFixed(0));
  }
}
