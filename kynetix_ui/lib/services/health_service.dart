import 'package:health/health.dart';

// ─── Activity tiers ───────────────────────────────────────────────────────────

enum ActivityTier {
  sedentary, // < 4 000 steps
  light,     // 4 000 – 7 000
  moderate,  // 7 000 – 10 000
  active,    // 10 000 – 13 000
  veryActive; // 13 000+

  String get displayName => switch (this) {
        ActivityTier.sedentary  => 'Sedentary',
        ActivityTier.light      => 'Light',
        ActivityTier.moderate   => 'Moderate',
        ActivityTier.active     => 'Active',
        ActivityTier.veryActive => 'Very Active',
      };

  String get emoji => switch (this) {
        ActivityTier.sedentary  => '🪑',
        ActivityTier.light      => '🚶',
        ActivityTier.moderate   => '🏃',
        ActivityTier.active     => '⚡',
        ActivityTier.veryActive => '🔥',
      };
}

ActivityTier _tierFromSteps(double steps) {
  if (steps < 4000)  return ActivityTier.sedentary;
  if (steps < 7000)  return ActivityTier.light;
  if (steps < 10000) return ActivityTier.moderate;
  if (steps < 13000) return ActivityTier.active;
  return ActivityTier.veryActive;
}

// ─── Result ───────────────────────────────────────────────────────────────────

class HealthSyncResult {
  /// Per-day step counts for the last 14 completed days (most recent first).
  /// Null if not enough data was available.
  final List<double>? dailySteps14d;

  /// Per-day step counts for days 15–30 (for 30-day average). Null if unavailable.
  final List<double>? dailySteps30d;

  /// Weighted average: 70% from 14d data, 30% from 30d data.
  /// This is the primary signal passed to the TDEE engine.
  final double?       effectiveAverageSteps;

  /// Simple 14-day average (displayed in UI).
  final double?       averageDailySteps14d;

  /// Simple 30-day average (displayed in UI).
  final double?       averageDailySteps30d;

  /// Median step count from the 14-day window (outlier-robust estimate).
  final double?       medianDailySteps14d;

  final ActivityTier  activityTier;
  final DateTime      syncedAt;
  final String?       error;

  const HealthSyncResult({
    this.dailySteps14d,
    this.dailySteps30d,
    this.effectiveAverageSteps,
    this.averageDailySteps14d,
    this.averageDailySteps30d,
    this.medianDailySteps14d,
    this.activityTier = ActivityTier.sedentary,
    required this.syncedAt,
    this.error,
  });

  bool get hasData  => effectiveAverageSteps != null;
  bool get hasError => error != null;

  /// Science-based step-to-calorie offset vs a 7,000-step sedentary baseline.
  ///
  /// Formula: kcal ≈ steps × (bodyWeight_kg × 0.000415)
  ///   • 0.04 kcal/step at ~65 kg (validated against doubly-labelled water studies)
  ///   • Baseline is 7,000 steps (~280 kcal for 65 kg) — typical desk person
  ///   • The offset is how many MORE or FEWER calories vs baseline
  ///
  /// Because we don't know user weight here, we use a conservative 65 kg proxy.
  /// The engine uses the actual user weight (see NutritionTargetEngine._stepCorrectionKcal).
  int get stepCalorieOffsetAt65kg {
    final steps = effectiveAverageSteps;
    if (steps == null) return 0;
    const baseline = 7000.0;
    const kcalPerStep = 0.04; // at 65 kg
    return ((steps - baseline) * kcalPerStep).round();
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

  Future<bool> isAvailable() async {
    try {
      final state = await _health.getHealthConnectSdkStatus();
      return state == HealthConnectSdkStatus.sdkAvailable;
    } catch (_) {
      return false;
    }
  }

  Future<bool> hasPermission() async {
    try {
      final granted = await _health.hasPermissions(_types, permissions: _permissions);
      return granted == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestPermission() async {
    try {
      return await _health.requestAuthorization(_types, permissions: _permissions);
    } catch (_) {
      return false;
    }
  }

  /// Reads 30 days of step history and returns a rich [HealthSyncResult].
  ///
  /// Data collection strategy:
  ///   1. Fetches ALL step data points for the last 30 days in ONE batch call.
  ///   2. Aggregates points into per-calendar-day totals.
  ///   3. Filters out wear-gap days (< 500 steps) — too low to be real data.
  ///   4. Trims outliers (Winsorize at 5th/95th percentile) before averaging.
  ///   5. Computes 14-day and 30-day averages plus a weighted effective steps.
  ///
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

      // Anchor on yesterday midnight — today is partial, would skew averages low.
      final todayStart = DateTime(now.year, now.month, now.day);
      final windowEnd   = todayStart; // exclusive: up to but not including today
      final windowStart = windowEnd.subtract(const Duration(days: 30));

      // ── Single batch fetch for 30 days ──────────────────────────────────────
      // This is one network call instead of 30+ sequential calls.
      List<HealthDataPoint> rawPoints;
      try {
        rawPoints = await _health.getHealthDataFromTypes(
          startTime: windowStart,
          endTime:   windowEnd,
          types:     _types,
        );
      } catch (e) {
        return HealthSyncResult(
          syncedAt: now,
          error: 'Could not read step data: ${e.toString().split('\n').first}',
        );
      }

      // ── Aggregate into per-day totals ────────────────────────────────────
      final Map<String, double> dayTotals = {};

      for (final point in rawPoints) {
        // Use the date of the data point's start time (device local time bucket)
        final date = point.dateFrom;
        final key  = '${date.year}-${date.month.toString().padLeft(2,'0')}-${date.day.toString().padLeft(2,'0')}';

        double value = 0;
        final v = point.value;
        if (v is NumericHealthValue) {
          value = v.numericValue.toDouble();
        }
        dayTotals[key] = (dayTotals[key] ?? 0) + value;
      }

      // ── Build ordered per-day lists (most recent = index 0) ──────────────
      final List<double> last14 = [];
      final List<double> last30 = [];

      for (int i = 0; i < 30; i++) {
        final d   = todayStart.subtract(Duration(days: i + 1)); // i+1 skips today
        final key = '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
        final val = dayTotals[key] ?? 0;

        // Only include days with meaningful step data.
        // < 500 steps = phone not worn / left at home. Excluded to avoid dragging
        // the average down unfairly.
        final valid = val >= 500;

        if (i < 14) {
          if (valid) last14.add(val);
        }
        last30.add(valid ? val : 0); // keep slot for 30d but mark as 0 if invalid
      }

      // Filter out the zero placeholders from last30 for averaging.
      final last30Valid = last30.where((s) => s >= 500).toList();

      // Require at least 5 valid days for 14d, at least 7 for 30d.
      if (last14.length < 5 && last30Valid.length < 7) {
        return HealthSyncResult(
          syncedAt: now,
          error: 'Not enough step data (need at least 5 days). Keep your phone with you.',
        );
      }

      // ── Winsorize outliers before averaging ──────────────────────────────
      // Clips extreme values (1 brutal day of hiking OR sick in bed)
      // to the 5th/95th percentile. The average is then much more stable.
      final avg14 = last14.length >= 5 ? _winsorizedMean(last14) : null;
      final avg30 = last30Valid.length >= 7 ? _winsorizedMean(last30Valid) : null;

      final median14 = last14.length >= 3 ? _median(last14) : null;

      // ── Weighted effective average ────────────────────────────────────────
      // 14-day data reflects current habits better (e.g. after a job change,
      // move to new city). 30-day smooths out anomalous weeks.
      // Weight: 70% recent (14d), 30% long-term (30d).
      final double? effective;
      if (avg14 != null && avg30 != null) {
        effective = avg14 * 0.70 + avg30 * 0.30;
      } else {
        effective = avg14 ?? avg30;
      }

      return HealthSyncResult(
        dailySteps14d:        last14.isEmpty ? null : last14,
        dailySteps30d:        last30Valid.isEmpty ? null : last30Valid,
        effectiveAverageSteps: effective,
        averageDailySteps14d:  avg14,
        averageDailySteps30d:  avg30,
        medianDailySteps14d:   median14,
        activityTier: effective != null
            ? _tierFromSteps(effective)
            : ActivityTier.sedentary,
        syncedAt: now,
      );
    } catch (e) {
      return HealthSyncResult(
        syncedAt: now,
        error: 'Sync failed: ${e.toString().split('\n').first}',
      );
    }
  }

  // ── Statistical helpers ───────────────────────────────────────────────────

  /// Winsorized mean: clips values below the 10th and above the 90th
  /// percentile before averaging.  Robust against outlier days.
  double _winsorizedMean(List<double> values) {
    if (values.isEmpty) return 0;
    if (values.length == 1) return values.first;

    final sorted = List<double>.from(values)..sort();
    final n     = sorted.length;

    // Clip to 10th/90th percentile
    final lo = sorted[(n * 0.10).floor().clamp(0, n - 1)];
    final hi = sorted[(n * 0.90).ceil().clamp(0, n - 1)];

    final clipped = sorted.map((v) => v.clamp(lo, hi)).toList();
    final sum = clipped.fold<double>(0, (a, b) => a + b);
    return double.parse((sum / clipped.length).toStringAsFixed(0));
  }

  double _median(List<double> values) {
    final sorted = List<double>.from(values)..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return (sorted[mid - 1] + sorted[mid]) / 2;
  }
}
