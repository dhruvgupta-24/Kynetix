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

// ─── HealthDailyRecord ───────────────────────────────────────────────

/// A daily step log from Health Connect.
class HealthDailyRecord {
  final DateTime date;
  final double steps;
  final bool usedByKynetix;

  const HealthDailyRecord({
    required this.date,
    required this.steps,
    required this.usedByKynetix,
  });
}

// ─── WeightQualityReport ─────────────────────────────────────────────

/// Data-quality assessment for a set of [WeightReading]s.
///
/// Used by Kyno to decide how confidently it can reason about weight trends.
/// If quality is poor, Kyno should avoid strong weight-based recommendations.
class WeightQualityReport {
  /// Total deduplicated readings in the 90-day window.
  final int totalReadings;

  /// Readings within the last 7 days.
  final int readingsLast7d;

  /// Readings within the last 30 days.
  final int readingsLast30d;

  /// Largest gap between consecutive readings (null when < 2 readings).
  final Duration? largestGapBetweenReadings;

  /// Age of the most recent reading from now.
  final Duration staleness;

  /// Whether the most recent reading is older than 7 days.
  bool get isStale => staleness.inDays > 7;

  /// True when there are at least 2 readings within 30 days — minimum
  /// needed for a meaningful trend.
  bool get hasSufficientTrendData => readingsLast30d >= 2;

  /// Qualitative confidence label for prompt injection.
  /// high   → ≥4 readings in 30d, not stale, gap < 14d
  /// medium → ≥2 readings in 30d but sparse or mildly stale
  /// low    → insufficient or stale data
  String get confidenceLabel {
    if (!hasSufficientTrendData || isStale) return 'low';
    if (readingsLast30d >= 4 &&
        (largestGapBetweenReadings == null ||
            largestGapBetweenReadings!.inDays < 14)) {
      return 'high';
    }
    return 'medium';
  }

  const WeightQualityReport({
    required this.totalReadings,
    required this.readingsLast7d,
    required this.readingsLast30d,
    required this.largestGapBetweenReadings,
    required this.staleness,
  });
}

// ─── WeightContext ────────────────────────────────────────────────────

/// Compact weight summary passed to Kyno.
///
/// Contains only the 4 scalar fields needed for coaching reasoning plus a
/// quality report that gates how confidently the AI should rely on the data.
/// Raw weight history is NEVER serialised into prompts.
class WeightContext {
  final double?            latestWeightKg;
  final double?            delta7dKg;
  final double?            delta30dKg;

  /// 'gaining' | 'losing' | 'stable' | 'unknown'
  final String             trendDirection;

  final WeightQualityReport quality;

  const WeightContext({
    required this.latestWeightKg,
    required this.delta7dKg,
    required this.delta30dKg,
    required this.trendDirection,
    required this.quality,
  });

  // ── Factory ─────────────────────────────────────────────────────────

  /// Builds a [WeightContext] from a list of deduplicated readings
  /// (most-recent-first, as returned by [HealthService.syncWeight]).
  ///
  /// Returns null when the list is empty — the caller should omit the
  /// weight block from the prompt entirely.
  static WeightContext? fromHistory(List<WeightReading> history) {
    if (history.isEmpty) return null;

    final now    = DateTime.now();
    final latest = history.first;

    // ── Deltas ──────────────────────────────────────────────────────
    double? delta7d;
    double? delta30d;

    if (history.length >= 2) {
      final cut7d  = latest.recordedAt.subtract(const Duration(days: 8));
      final cut30d = latest.recordedAt.subtract(const Duration(days: 31));

      // First reading OLDER than the cutoff is the reference point.
      final ref7d  = history.firstWhere(
        (r) => r.recordedAt.isBefore(cut7d),
        orElse: () => history.last,
      );
      final ref30d = history.firstWhere(
        (r) => r.recordedAt.isBefore(cut30d),
        orElse: () => history.last,
      );

      if (ref7d  != history.first) delta7d  = latest.kg - ref7d.kg;
      if (ref30d != history.first) delta30d = latest.kg - ref30d.kg;
    }

    // ── Trend direction ─────────────────────────────────────────────
    // Prefer the 7-day delta for recency; fall back to 30-day.
    final primaryDelta = delta7d ?? delta30d;
    final trendDirection = switch (primaryDelta) {
      null                          => 'unknown',
      double d when d < -0.3        => 'losing',
      double d when d >  0.3        => 'gaining',
      _                             => 'stable',
    };

    // ── Quality report ──────────────────────────────────────────────
    final r7d  = history.where(
        (r) => r.recordedAt.isAfter(now.subtract(const Duration(days: 7)))).length;
    final r30d = history.where(
        (r) => r.recordedAt.isAfter(now.subtract(const Duration(days: 30)))).length;

    Duration? largestGap;
    for (var i = 0; i < history.length - 1; i++) {
      final gap = history[i].recordedAt.difference(history[i + 1].recordedAt).abs();
      if (largestGap == null || gap > largestGap) largestGap = gap;
    }

    final quality = WeightQualityReport(
      totalReadings:            history.length,
      readingsLast7d:           r7d,
      readingsLast30d:          r30d,
      largestGapBetweenReadings: largestGap,
      staleness:                now.difference(latest.recordedAt),
    );

    return WeightContext(
      latestWeightKg: latest.kg,
      delta7dKg:      delta7d,
      delta30dKg:     delta30d,
      trendDirection: trendDirection,
      quality:        quality,
    );
  }

  // ── Compact prompt string ────────────────────────────────────────────

  /// Produces a short, multi-line block for injection into the Kyno system
  /// prompt. Raw history is never included — only computed scalars.
  ///
  /// Example output:
  /// ```
  /// WEIGHT CONTEXT (confidence: medium)
  /// - Current weight: 74.5 kg
  /// - 7-day change: −0.8 kg (losing)
  /// - 30-day change: −1.6 kg
  /// - Data: 6 readings over 30d, latest 2d ago
  /// NOTE: Weight data is sparse. Avoid strong weight-based assertions.
  /// ```
  String toPromptString() {
    final q = quality;
    final buf = StringBuffer();

    buf.writeln('WEIGHT CONTEXT (confidence: ${q.confidenceLabel})');
    if (latestWeightKg != null) {
      buf.writeln('- Current weight: ${latestWeightKg!.toStringAsFixed(1)} kg');
    }
    if (delta7dKg != null) {
      final sign = delta7dKg! >= 0 ? '+' : '';
      buf.writeln('- 7-day change: $sign${delta7dKg!.toStringAsFixed(1)} kg ($trendDirection)');
    } else {
      buf.writeln('- 7-day change: insufficient data ($trendDirection)');
    }
    if (delta30dKg != null) {
      final sign = delta30dKg! >= 0 ? '+' : '';
      buf.writeln('- 30-day change: $sign${delta30dKg!.toStringAsFixed(1)} kg');
    }

    final stalenessLabel = q.staleness.inDays == 0
        ? 'today'
        : '${q.staleness.inDays}d ago';
    buf.writeln(
      '- Data: ${q.readingsLast30d} readings over 30d, latest $stalenessLabel',
    );

    if (q.confidenceLabel == 'low') {
      buf.write(
        'NOTE: Weight data is sparse or stale. '
        'Avoid strong weight-based recommendations.',
      );
    } else if (q.confidenceLabel == 'medium') {
      buf.write(
        'NOTE: Weight data is moderate quality. '
        'Use trend direction as a signal, not a precise measure.',
      );
    }

    return buf.toString().trim();
  }
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

  /// List of structured daily records for the 30-day query window.
  final List<HealthDailyRecord>? dailyRecords;

  /// Simple 7-day average (winsorized, displayed in logs).
  final double?       averageDailySteps7d;

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
    this.dailyRecords,
    this.averageDailySteps7d,
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
      final List<double> last7 = [];
      final List<double> last14 = [];
      final List<double> last30 = [];
      final List<HealthDailyRecord> dailyRecords = [];

      for (int i = 0; i < daysToFetch; i++) {
        final dayStart = todayStart.subtract(Duration(days: i + 1));
        final rawVal = results[i];

        if (rawVal != null) {
          final val = rawVal.toDouble();
          if (i < 7) last7.add(val);
          if (i < 14) last14.add(val);
          last30.add(val);

          dailyRecords.add(HealthDailyRecord(
            date: dayStart,
            steps: val,
            usedByKynetix: true,
          ));
        } else {
          // Failed daily query (timeout/permission/SDK error) is excluded from averages
          dailyRecords.add(HealthDailyRecord(
            date: dayStart,
            steps: 0.0,
            usedByKynetix: false,
          ));
        }
      }

      // Require at least 1 successful day to complete sync
      if (last14.isEmpty && last30.isEmpty) {
        return HealthSyncResult(
          syncedAt: now,
          error: 'No step data available. Verify your Health Connect settings.',
        );
      }

      // ── Calculate strict arithmetic averages ──────────────────────────────
      final avg7 = last7.isNotEmpty ? _arithmeticMean(last7) : null;
      final avg14 = last14.isNotEmpty ? _arithmeticMean(last14) : null;
      final avg30 = last30.isNotEmpty ? _arithmeticMean(last30) : null;

      // ── Weighted effective average ────────────────────────────────────────
      final double? effective;
      if (avg14 != null && avg30 != null) {
        effective = avg14 * 0.70 + avg30 * 0.30;
      } else {
        effective = avg14 ?? avg30;
      }

      return HealthSyncResult(
        dailySteps14d:        last14.isEmpty ? null : last14,
        dailySteps30d:        last30.isEmpty ? null : last30,
        dailyRecords:         dailyRecords,
        averageDailySteps7d:  avg7,
        effectiveAverageSteps: effective,
        averageDailySteps14d:  avg14,
        averageDailySteps30d:  avg30,
        medianDailySteps14d:   avg14, // median falls back to simple average now
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

  // ── Arithmetic helper ───────────────────────────────────────────────────────

  double _arithmeticMean(List<double> values) {
    if (values.isEmpty) return 0.0;
    final sum = values.fold<double>(0, (a, b) => a + b);
    final avg = sum / values.length;
    if (avg.isNaN || avg.isInfinite) return 0.0;
    return double.tryParse(avg.toStringAsFixed(0)) ?? 0.0;
  }
}
