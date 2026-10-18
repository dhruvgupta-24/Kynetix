import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/day_log.dart' show dateKey;
import 'health_service.dart' show WeightReading;

/// One day's weigh-in. [waterMl] is kept only so water logged by older app
/// versions survives a round trip; the app no longer tracks water.
class BodyDay {
  final int waterMl;
  final double? weightKg;
  final DateTime updatedAt;

  const BodyDay({this.waterMl = 0, this.weightKg, required this.updatedAt});

  bool get isEmpty => waterMl == 0 && weightKg == null;

  BodyDay copyWith({int? waterMl, double? weightKg, bool clearWeight = false, DateTime? updatedAt}) => BodyDay(
        waterMl: waterMl ?? this.waterMl,
        weightKg: clearWeight ? null : (weightKg ?? this.weightKg),
        updatedAt: updatedAt ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'w': waterMl,
        if (weightKg != null) 'kg': weightKg,
        'u': updatedAt.toIso8601String(),
      };

  factory BodyDay.fromJson(Map<String, dynamic> j) => BodyDay(
        waterMl: (j['w'] as num?)?.toInt() ?? 0,
        weightKg: (j['kg'] as num?)?.toDouble(),
        updatedAt: DateTime.tryParse(j['u'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// A point on the weight chart: what the scale said and the smoothed trend.
class WeightPoint {
  final DateTime day;
  final double scaleKg;
  final double trendKg;
  final bool manual;
  const WeightPoint(this.day, this.scaleKg, this.trendKg, {required this.manual});
}

/// Weight trend over a window: the smoothed number and how fast it moves.
class WeightTrend {
  final List<WeightPoint> points;
  const WeightTrend(this.points);

  bool get isEmpty => points.isEmpty;
  WeightPoint? get latest => points.isEmpty ? null : points.last;

  /// kg per week from the smoothed line over the last ~2 weeks (needs 2+
  /// weigh-ins at least 5 days apart).
  double? get weeklyRateKg {
    if (points.length < 2) return null;
    final last = points.last;
    final from = last.day.subtract(const Duration(days: 14));
    final start = points.firstWhere((p) => !p.day.isBefore(from), orElse: () => points.first);
    final days = last.day.difference(start.day).inDays;
    if (days < 5) return null;
    return (last.trendKg - start.trendKg) / days * 7;
  }
}

/// Manual weigh-ins. Local-first per user, backed up to the
/// `body_metrics` table. Health Connect readings are merged in when the trend
/// is read, never copied into this store.
class BodyMetricsService {
  BodyMetricsService._();
  static final BodyMetricsService instance = BodyMetricsService._();

  static const _kStore = 'body_metrics_v1';
  /// How much a new weigh-in moves the trend (Hacker's Diet style smoothing).
  static const trendAlpha = 0.15;

  final Map<String, BodyDay> _days = {};
  String? _userId;
  SharedPreferences? _prefs;

  /// Bumps on every change; screens listen to repaint.
  final ValueNotifier<int> changes = ValueNotifier(0);

  String get _key => '${_kStore}_$_userId';

  Future<void> initForUser(String userId, {SharedPreferences? prefsOverride}) async {
    _userId = userId;
    _days.clear();
    _prefs = prefsOverride ?? await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_key);
    if (raw != null) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        map.forEach((k, v) => _days[k] = BodyDay.fromJson(v as Map<String, dynamic>));
      } catch (e) {
        debugPrint('[BodyMetrics] Could not read local store: $e');
      }
    }
    changes.value++;
  }

  void clearMemory() {
    _days.clear();
    _userId = null;
    changes.value++;
  }

  // ── Reads ──────────────────────────────────────────────────────────────────

  double? weightFor(DateTime date) => _days[dateKey(date)]?.weightKg;

  /// Most recent manual weigh-in on or before [date].
  ({DateTime day, double kg})? lastWeightOnOrBefore(DateTime date) {
    final limit = dateKey(date);
    String? best;
    for (final e in _days.entries) {
      if (e.value.weightKg == null || e.key.compareTo(limit) > 0) continue;
      if (best == null || e.key.compareTo(best) > 0) best = e.key;
    }
    if (best == null) return null;
    return (day: DateTime.parse(best), kg: _days[best]!.weightKg!);
  }

  /// Manual weigh-ins as readings (newest first), for screens that chart
  /// Health Connect data.
  List<WeightReading> manualReadings() {
    final out = <WeightReading>[];
    _days.forEach((k, v) {
      final kg = v.weightKg;
      if (kg != null) out.add(WeightReading(kg: kg, recordedAt: DateTime.parse(k).add(const Duration(hours: 8)), source: 'Kynetix'));
    });
    out.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return out;
  }

  /// Health Connect readings with manual weigh-ins merged in; a manual
  /// weigh-in replaces any Health Connect reading on the same day.
  List<WeightReading> mergedReadings(List<WeightReading>? external) {
    final manual = manualReadings();
    final manualDays = {for (final r in manual) dateKey(r.recordedAt)};
    final out = [
      ...manual,
      ...?external?.where((r) => !manualDays.contains(dateKey(r.recordedAt))),
    ]..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return out;
  }

  /// Weigh-ins over the last [days] days, manual ones winning over Health
  /// Connect on the same day, smoothed into a trend line.
  WeightTrend trend({int days = 60, List<WeightReading> external = const [], DateTime? now}) {
    final today = _dayOnly(now ?? DateTime.now());
    final from = today.subtract(Duration(days: days));
    final byDay = <String, ({double kg, bool manual})>{};
    // Health Connect: the day's first reading (morning weigh-ins are the
    // most comparable).
    final sortedExt = [...external]..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
    for (final r in sortedExt) {
      final d = _dayOnly(r.recordedAt);
      if (d.isBefore(from) || d.isAfter(today)) continue;
      byDay.putIfAbsent(dateKey(d), () => (kg: r.kg, manual: false));
    }
    _days.forEach((k, v) {
      final kg = v.weightKg;
      if (kg == null) return;
      final d = DateTime.parse(k);
      if (d.isBefore(from) || d.isAfter(today)) return;
      byDay[k] = (kg: kg, manual: true);
    });
    final keys = byDay.keys.toList()..sort();
    final points = <WeightPoint>[];
    double? t;
    DateTime? prevDay;
    for (final k in keys) {
      final v = byDay[k]!;
      final d = DateTime.parse(k);
      if (t == null) {
        t = v.kg;
      } else {
        // Gaps count: a week without weighing pulls harder on the next one.
        final gap = math.max(1, d.difference(prevDay!).inDays);
        final a = 1 - math.pow(1 - trendAlpha, gap).toDouble();
        t = t + a * (v.kg - t);
      }
      prevDay = d;
      points.add(WeightPoint(d, v.kg, t, manual: v.manual));
    }
    return WeightTrend(points);
  }

  // ── Writes ─────────────────────────────────────────────────────────────────

  Future<void> logWeight(DateTime date, double kg) async {
    if (kg < 20 || kg > 400) throw ArgumentError.value(kg, 'kg', 'outside 20-400');
    final k = dateKey(date);
    final cur = _days[k] ?? BodyDay(updatedAt: DateTime.now());
    await _put(k, cur.copyWith(weightKg: (kg * 10).round() / 10));
  }

  Future<void> clearWeight(DateTime date) async {
    final k = dateKey(date);
    final cur = _days[k];
    if (cur == null) return;
    await _put(k, cur.copyWith(clearWeight: true));
  }

  Future<void> _put(String key, BodyDay day) async {
    final owner = _userId;
    if (owner == null) return;
    _days[key] = day;
    changes.value++;
    try {
      await (_prefs ?? await SharedPreferences.getInstance()).setString(
        '${_kStore}_$owner',
        jsonEncode(_days.map((k, v) => MapEntry(k, v.toJson()))),
      );
    } catch (e) {
      debugPrint('[BodyMetrics] Local save failed: $e');
    }
    _upload(owner, key, day).ignore();
  }

  // ── Cloud ──────────────────────────────────────────────────────────────────

  SupabaseClient? get _db {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null; // Not initialised (tests).
    }
  }

  Future<void> _upload(String owner, String key, BodyDay day) async {
    final db = _db;
    if (db == null || db.auth.currentUser?.id != owner) return;
    try {
      await db.from('body_metrics').upsert({
        'user_id': owner,
        'date_key': key,
        'water_ml': day.waterMl,
        'weight_kg': day.weightKg,
        'updated_at': day.updatedAt.toUtc().toIso8601String(),
      }, onConflict: 'user_id,date_key').timeout(const Duration(seconds: 20));
    } catch (e) {
      debugPrint('[BodyMetrics] Upload of $key failed, kept locally: $e');
    }
  }

  /// Pulls the cloud copy and keeps whichever side changed last, per day.
  Future<void> hydrateFromCloud() async {
    final owner = _userId;
    final db = _db;
    if (owner == null || db == null || db.auth.currentUser?.id != owner) return;
    try {
      final rows = await db
          .from('body_metrics')
          .select('date_key, water_ml, weight_kg, updated_at')
          .eq('user_id', owner)
          .timeout(const Duration(seconds: 20));
      if (_userId != owner) return;
      var changed = false;
      for (final r in rows) {
        final k = r['date_key'] as String;
        final remote = BodyDay(
          waterMl: (r['water_ml'] as num?)?.toInt() ?? 0,
          weightKg: (r['weight_kg'] as num?)?.toDouble(),
          updatedAt: DateTime.tryParse(r['updated_at'] as String? ?? '')?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0),
        );
        final local = _days[k];
        if (local == null || remote.updatedAt.isAfter(local.updatedAt)) {
          _days[k] = remote;
          changed = true;
        } else if (local.updatedAt.isAfter(remote.updatedAt)) {
          _upload(owner, k, local).ignore();
        }
      }
      for (final e in _days.entries) {
        if (!rows.any((r) => r['date_key'] == e.key) && !e.value.isEmpty) {
          _upload(owner, e.key, e.value).ignore();
        }
      }
      if (changed) {
        changes.value++;
        await (_prefs ?? await SharedPreferences.getInstance()).setString(
          '${_kStore}_$owner',
          jsonEncode(_days.map((k, v) => MapEntry(k, v.toJson()))),
        );
      }
    } catch (e) {
      debugPrint('[BodyMetrics] Cloud hydrate skipped: $e');
    }
  }

  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}
