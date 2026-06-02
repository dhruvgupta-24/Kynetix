import 'package:health/health.dart';

// ─── WeightReading ───────────────────────────────────────────────────

/// A single weight measurement from Health Connect.
class WeightReading {
  final double   kg;          // body mass in kilograms
  final DateTime recordedAt;  // local time of the measurement
  final String   source;      // source app package name

  const WeightReading({
    required this.kg,
    required this.recordedAt,
    required this.source,
  });
}

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

  /// Per-day step counts for days D-1 to D-30 (all 30 completed days,
  /// inclusive of the most-recent 14-day window). Null if unavailable.
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

  /// Weight readings from the last 90 days (most recent first).
  /// Null if weight permission was not granted or no data is available.
  final List<WeightReading>? weightHistory;

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
    this.weightHistory,
    this.activityTier = ActivityTier.sedentary,
    required this.syncedAt,
    this.error,
  });

  bool get hasData  => effectiveAverageSteps != null;
  bool get hasError => error != null;

  /// Latest weight reading, or null if none available.
  WeightReading? get latestWeight =>
      (weightHistory != null && weightHistory!.isNotEmpty)
          ? weightHistory!.first
          : null;

  /// Weight delta over the last 7 days (negative = lost weight).
  /// Returns null when fewer than 2 readings within 8 days exist.
  double? get weightDelta7d {
    final history = weightHistory;
    if (history == null || history.length < 2) return null;
    final now = latestWeight!.recordedAt;
    final cutoff = now.subtract(const Duration(days: 8));
    final recent = history.where((r) => r.recordedAt.isAfter(cutoff)).toList();
    if (recent.length < 2) return null;
    return recent.first.kg - recent.last.kg;
  }

  /// Weight delta over the last 30 days (negative = lost weight).
  /// Returns null when fewer than 2 readings within 31 days exist.
  double? get weightDelta30d {
    final history = weightHistory;
    if (history == null || history.length < 2) return null;
    final now = latestWeight!.recordedAt;
    final cutoff = now.subtract(const Duration(days: 31));
    final older = history.lastWhere(
        (r) => r.recordedAt.isAfter(cutoff),
        orElse: () => history.last,
    );
    return latestWeight!.kg - older.kg;
  }

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

  static const _stepTypes       = [HealthDataType.STEPS];
  static const _stepPermissions = [HealthDataAccess.READ];
  static const _weightTypes       = [HealthDataType.WEIGHT];
  static const _weightPermissions = [HealthDataAccess.READ];

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
      final granted = await _health.hasPermissions(_stepTypes, permissions: _stepPermissions);
      return granted == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestPermission() async {
    try {
      return await _health.requestAuthorization(_stepTypes, permissions: _stepPermissions);
    } catch (_) {
      return false;
    }
  }

  /// Returns true if weight (BODY_MASS) permission has been granted.
  Future<bool> hasWeightPermission() async {
    try {
      final granted = await _health.hasPermissions(_weightTypes, permissions: _weightPermissions);
      return granted == true;
    } catch (_) {
      return false;
    }
  }

  /// Requests permission to read BODY_MASS from Health Connect.
  /// Handled separately from steps so a weight denial does not block step sync.
  Future<bool> requestWeightPermission() async {
    try {
      return await _health.requestAuthorization(_weightTypes, permissions: _weightPermissions);
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
  /// Timezone note: [DateTime.now()] returns the device's local time.
  /// [getTotalStepsInInterval] passes DateTime objects to Health Connect, which
  /// on Android API ≥26 correctly interprets them as local time. No UTC
  /// conversion is needed on the client side.
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
      // DateTime(y, m, d) produces local midnight, which is correct.
      final todayStart = DateTime(now.year, now.month, now.day);


      // ── Parallel fetch for 30 days using native aggregation ───────────────
      // We must use getTotalStepsInInterval because it leverages Health Connect's
      // native deduplication. getHealthDataFromTypes returns overlapping raw points
      // from multiple apps, causing massively inflated step counts.
      // We run them in parallel to avoid slow sequential loops.
      final daysToFetch = 30;
      final stepFutures = List.generate(daysToFetch, (i) {
        final dayStart = todayStart.subtract(Duration(days: i + 1));
        final dayEnd   = dayStart.add(const Duration(days: 1));
        return _health.getTotalStepsInInterval(dayStart, dayEnd).catchError((_) => null);
      });

      final results = await Future.wait(stepFutures);

      // ── Build ordered per-day lists (most recent = index 0) ──────────────
      final List<double> last14 = [];
      final List<double> last30 = [];

      for (int i = 0; i < daysToFetch; i++) {
        final val = (results[i] ?? 0).toDouble();

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

  // ── Weight sync ──────────────────────────────────────────────────────────────────

  /// Fetches up to 90 days of body mass (weight) data from Health Connect.
  ///
  /// Returns a list of [WeightReading] sorted most-recent-first.
  ///
  /// Deduplication: readings within 2 minutes of each other are collapsed
  /// to the later one (protects against apps writing duplicate readings).
  ///
  /// Returns an empty list if permission is not granted or no data exists.
  /// Never throws.
  Future<List<WeightReading>> syncWeight() async {
    try {
      final hasPerm = await hasWeightPermission();
      if (!hasPerm) return [];

      final now      = DateTime.now();
      final start    = now.subtract(const Duration(days: 90));

      final points = await _health.getHealthDataFromTypes(
        types:     _weightTypes,
        startTime: start,
        endTime:   now,
      );

      if (points.isEmpty) return [];

      // Filter WEIGHT data in KILOGRAM only.
      final kgPoints = points.where((p) =>
          p.type == HealthDataType.WEIGHT &&
          p.unit == HealthDataUnit.KILOGRAM,
      ).toList();

      if (kgPoints.isEmpty) return [];

      // Sort descending by date (most recent first).
      kgPoints.sort((a, b) => b.dateFrom.compareTo(a.dateFrom));

      // Deduplicate: collapse readings within 2 minutes of each other.
      final readings = <WeightReading>[];
      DateTime? lastKept;
      for (final p in kgPoints) {
        final ts  = p.dateFrom;
        final val = (p.value as NumericHealthValue).numericValue.toDouble();
        if (val <= 0 || val > 300) continue; // sanity guard
        if (lastKept != null &&
            lastKept.difference(ts).abs() < const Duration(minutes: 2)) {
          continue; // duplicate within 2-minute window
        }
        readings.add(WeightReading(
          kg:         val,
          recordedAt: ts.toLocal(),
          source:     p.sourceName,
        ));
        lastKept = ts;
      }

      return readings;
    } catch (_) {
      return [];
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
