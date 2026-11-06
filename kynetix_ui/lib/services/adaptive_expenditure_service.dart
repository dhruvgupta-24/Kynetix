import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/day_log.dart';
import 'body_metrics_service.dart';
import 'health_service.dart';

// ─── Adaptive expenditure ─────────────────────────────────────────────────────
//
// The formula (BMR × activity + steps) is a population guess. What the user
// actually burns shows in two things they already log: what they ate and
// where their weight trend went. Over a few weeks:
//
//   burned per day ≈ average intake − (trend change in kg × 7700) / days
//
// The observed number is only trusted as far as the data backs it: it is
// blended with the formula by a confidence built from how many days were
// logged and how many weigh-ins there are, and it can never sit more than
// 30% from the formula. Targets move at most once a week, so they never
// jitter day to day, and every move comes with its reasons in plain words.

/// One read of "what does this person really burn".
class ExpenditureEstimate {
  const ExpenditureEstimate({
    required this.formulaKcal,
    required this.windowDays,
    required this.loggedDays,
    required this.weighIns,
    this.avgIntakeKcal,
    this.trendChangeKg,
    this.trendSpanDays,
    this.observedKcal,
    this.confidence = 0,
    this.clamped = false,
  });

  /// The formula's maintenance (BMR × activity + steps).
  final double formulaKcal;

  /// Days looked at (ending yesterday) and how many of them were logged.
  final int windowDays;
  final int loggedDays;

  /// Weigh-ins in the window, manual and Health Connect.
  final int weighIns;

  final double? avgIntakeKcal;
  final double? trendChangeKg;
  final int? trendSpanDays;

  /// What the intake and the trend say, before blending. Null until there is
  /// enough data.
  final double? observedKcal;

  /// 0 to 1: how far the observed number is trusted.
  final double confidence;

  /// The observed number was pulled back inside 30% of the formula.
  final bool clamped;

  static const minLoggedDays = 14;
  static const minWeighIns = 4;
  static const minSpanDays = 14;

  bool get ready => observedKcal != null;

  /// The maintenance to use: the formula, moved toward the observed number as
  /// far as [confidence] allows.
  double get blendedKcal {
    final o = observedKcal;
    if (o == null) return formulaKcal;
    return ((formulaKcal + (o - formulaKcal) * confidence) / 10).round() * 10;
  }

  /// What is still missing before the estimate can be made.
  String get missing {
    final parts = <String>[];
    if (loggedDays < minLoggedDays) {
      final n = minLoggedDays - loggedDays;
      parts.add('$n more logged ${n == 1 ? 'day' : 'days'}');
    }
    if (weighIns < minWeighIns) {
      final n = minWeighIns - weighIns;
      parts.add('$n more ${n == 1 ? 'weigh-in' : 'weigh-ins'}');
    }
    if (parts.isEmpty && (trendSpanDays ?? 0) < minSpanDays) {
      parts.add('weigh-ins spread over at least two weeks');
    }
    return parts.join(' and ');
  }

  /// Why the number is what it is, in one or two sentences.
  String get explanation {
    if (!ready) return 'Needs $missing in the last $windowDays days.';
    final change = trendChangeKg!;
    final dir = change.abs() < 0.05
        ? 'held steady'
        : change < 0
            ? 'dropped ${change.abs().toStringAsFixed(1)} kg'
            : 'rose ${change.toStringAsFixed(1)} kg';
    final s = StringBuffer(
      'You ate about ${avgIntakeKcal!.round()} kcal a day on $loggedDays logged days, '
      'and your trend weight $dir over $trendSpanDays days. ',
    );
    s.write('That points to about ${observedKcal!.round()} kcal a day');
    if (clamped) s.write(' (kept within 30% of the formula until more data agrees)');
    s.write('.');
    return s.toString();
  }
}

class AdaptiveExpenditureService {
  AdaptiveExpenditureService._();
  static final AdaptiveExpenditureService instance = AdaptiveExpenditureService._();

  /// Energy in a kilogram of body-weight change (mixed fat and lean).
  static const kcalPerKg = 7700.0;

  /// A day under this is treated as not fully logged and left out.
  static const minLoggedKcal = 800.0;

  static const windowDays = 28;

  /// Pure estimate from logs and a weight trend. [now] defaults to today; the
  /// window ends yesterday, since today isn't finished.
  static ExpenditureEstimate estimate({
    required double formulaKcal,
    required Map<String, DayLog> logs,
    required WeightTrend trend,
    DateTime? now,
    int window = windowDays,
  }) {
    final today = DateTime((now ?? DateTime.now()).year, (now ?? DateTime.now()).month, (now ?? DateTime.now()).day);
    final end = today.subtract(const Duration(days: 1));
    final start = today.subtract(Duration(days: window));

    var logged = 0;
    var intake = 0.0;
    for (var i = 0; i < window; i++) {
      final d = start.add(Duration(days: i));
      final kcal = logs[dateKey(d)]?.totalCaloriesMid ?? 0;
      if (kcal >= minLoggedKcal) {
        logged++;
        intake += kcal;
      }
    }

    final pts = trend.points.where((p) => !p.day.isBefore(start) && !p.day.isAfter(end)).toList();
    final weighIns = pts.length;
    final span = pts.length >= 2 ? pts.last.day.difference(pts.first.day).inDays : 0;

    final base = ExpenditureEstimate(
      formulaKcal: formulaKcal,
      windowDays: window,
      loggedDays: logged,
      weighIns: weighIns,
      trendSpanDays: span,
    );
    if (logged < ExpenditureEstimate.minLoggedDays ||
        weighIns < ExpenditureEstimate.minWeighIns ||
        span < ExpenditureEstimate.minSpanDays) {
      return base;
    }

    final avgIntake = intake / logged;
    final change = pts.last.trendKg - pts.first.trendKg;
    var observed = avgIntake - change * kcalPerKg / span;
    final lo = formulaKcal * 0.7, hi = formulaKcal * 1.3;
    final clamped = observed < lo || observed > hi;
    observed = observed.clamp(lo, hi);

    // Trust grows with logging coverage and weigh-in density; never fully
    // replaces the formula.
    final coverage = logged / window;
    final density = math.min(1.0, weighIns / 10);
    final confidence = (coverage * density).clamp(0.0, 0.85);

    return ExpenditureEstimate(
      formulaKcal: formulaKcal,
      windowDays: window,
      loggedDays: logged,
      weighIns: weighIns,
      avgIntakeKcal: avgIntake,
      trendChangeKg: change,
      trendSpanDays: span,
      observedKcal: observed,
      confidence: confidence.toDouble(),
      clamped: clamped,
    );
  }

  // ── Applied value (per user, moves at most weekly) ──────────────────────────

  String? _userId;
  SharedPreferences? _prefs;
  bool _enabled = false;
  double? _applied;
  DateTime? _appliedAt;

  /// Bumps when the switch or the applied value changes.
  final ValueNotifier<int> changes = ValueNotifier(0);

  bool get enabled => _enabled;

  /// The maintenance the target engine should use, or null for the formula.
  double? get appliedKcal => _enabled ? _applied : null;
  DateTime? get appliedAt => _appliedAt;

  String _k(String name) => 'adaptive_tdee_${name}_$_userId';

  Future<void> initForUser(String userId, {SharedPreferences? prefsOverride}) async {
    _userId = userId;
    _prefs = prefsOverride ?? await SharedPreferences.getInstance();
    _enabled = _prefs!.getBool(_k('on')) ?? false;
    _applied = _prefs!.getDouble(_k('kcal'));
    final at = _prefs!.getString(_k('at'));
    _appliedAt = at == null ? null : DateTime.tryParse(at);
    changes.value++;
  }

  void clearMemory() {
    _userId = null;
    _enabled = false;
    _applied = null;
    _appliedAt = null;
    changes.value++;
  }

  /// The estimate from the current logs, weigh-ins and Health Connect weight.
  ExpenditureEstimate current(double formulaKcal, {DateTime? now}) => estimate(
        formulaKcal: formulaKcal,
        logs: dayLogStore,
        trend: BodyMetricsService.instance.trend(
          days: windowDays + 7,
          external: HealthService().lastSyncResult?.weightHistory ?? const [],
          now: now,
        ),
        now: now,
      );

  /// Turns adaptive targets on or off. Turning on applies the current
  /// estimate at once.
  Future<void> setEnabled(bool on, double formulaKcal) async {
    _enabled = on;
    await _prefs?.setBool(_k('on'), on);
    if (on) {
      await refresh(formulaKcal, force: true);
    } else {
      changes.value++;
    }
  }

  /// Re-reads the estimate and applies it if a week has passed since the last
  /// change (or [force]). Returns whether the applied value moved.
  Future<bool> refresh(double formulaKcal, {bool force = false, DateTime? now}) async {
    if (!_enabled || _userId == null) return false;
    final t = now ?? DateTime.now();
    if (!force && _appliedAt != null && t.difference(_appliedAt!).inDays < 7) return false;
    final e = current(formulaKcal, now: t);
    if (!e.ready) {
      final had = _applied != null;
      _applied = null;
      await _prefs?.remove(_k('kcal'));
      if (had) changes.value++;
      return had;
    }
    final next = e.blendedKcal;
    if (_applied == next) return false;
    _applied = next;
    _appliedAt = t;
    await _prefs?.setDouble(_k('kcal'), next);
    await _prefs?.setString(_k('at'), t.toIso8601String());
    changes.value++;
    return true;
  }

  @visibleForTesting
  void setForTesting({required bool enabled, double? applied}) {
    _enabled = enabled;
    _applied = applied;
  }
}
