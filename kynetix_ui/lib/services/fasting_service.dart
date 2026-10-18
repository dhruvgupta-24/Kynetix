// Fasting timer: intermittent fasting windows and Indian religious fasts.
//
// A fast is a start time and a planned end. Intermittent fasts (14:10, 16:8,
// 18:6) run for a fixed number of hours. Clock fasts end at a time of day:
// sunrise to sunset, roza (iftar), Karva Chauth (moonrise), Navratri (after
// the evening puja) and Ekadashi (next morning). The user can move any end.
//
// Logging a meal ends a no-food fast (that meal is the break-fast). Navratri
// and Ekadashi allow phalahar (fruit, milk, sabudana, kuttu…), so logging a
// meal doesn't end those; Kyno suggests vrat foods instead. A fast ended by a
// mis-timed log can be resumed.
//
// Per user, on this device, keyed like the other per-user stores.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/day_log.dart';
import 'persistence_service.dart';

enum FastKind { intermittent, sunriseSunset, navratri, ekadashi, roza, karvaChauth }

enum FastEndReason { manual, meal }

class FastPreset {
  const FastPreset({
    required this.id,
    required this.label,
    required this.kind,
    required this.subtitle,
    this.hours,
    this.endHour,
    this.endMinute = 0,
    this.endNextDay = false,
    this.allowsVratFoods = false,
  });

  final String id;
  final String label;
  final FastKind kind;
  final String subtitle;

  /// Fixed length (intermittent fasting).
  final int? hours;

  /// Default clock end (sunset, moonrise…), editable when starting.
  final int? endHour;
  final int endMinute;

  /// Ends the morning after (Ekadashi parana).
  final bool endNextDay;

  /// Phalahar allowed: logging a meal doesn't end the fast.
  final bool allowsVratFoods;

  bool get isReligious => kind != FastKind.intermittent && kind != FastKind.sunriseSunset;
  bool get endsOnMeal => !allowsVratFoods;
  bool get endsAtClock => hours == null;

  /// The planned end for a fast starting at [start].
  DateTime plannedEnd(DateTime start) {
    if (hours != null) return start.add(Duration(hours: hours!));
    var end = DateTime(start.year, start.month, start.day, endHour ?? 19, endMinute);
    if (endNextDay) end = end.add(const Duration(days: 1));
    if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
    return end;
  }
}

const List<FastPreset> fastPresets = [
  FastPreset(id: 'if_16_8', label: '16:8', kind: FastKind.intermittent, hours: 16, subtitle: '16 hours fasting, 8 hours eating'),
  FastPreset(id: 'if_14_10', label: '14:10', kind: FastKind.intermittent, hours: 14, subtitle: 'A gentle start: 14 hours fasting'),
  FastPreset(id: 'if_18_6', label: '18:6', kind: FastKind.intermittent, hours: 18, subtitle: '18 hours fasting, 6 hours eating'),
  FastPreset(id: 'sunrise_sunset', label: 'Sunrise to sunset', kind: FastKind.sunriseSunset, endHour: 18, endMinute: 45, subtitle: 'Ends at sunset. Set your own time'),
  FastPreset(id: 'navratri', label: 'Navratri', kind: FastKind.navratri, endHour: 20, allowsVratFoods: true, subtitle: 'Phalahar allowed. Kyno suggests vrat foods'),
  FastPreset(id: 'ekadashi', label: 'Ekadashi', kind: FastKind.ekadashi, endHour: 7, endNextDay: true, allowsVratFoods: true, subtitle: 'Until parana the next morning'),
  FastPreset(id: 'roza', label: 'Roza', kind: FastKind.roza, endHour: 18, endMinute: 45, subtitle: 'Sehri to iftar. Logging iftar ends it'),
  FastPreset(id: 'karva_chauth', label: 'Karva Chauth', kind: FastKind.karvaChauth, endHour: 20, endMinute: 30, subtitle: 'Nirjala until moonrise'),
];

FastPreset? presetById(String id) {
  for (final p in fastPresets) {
    if (p.id == id) return p;
  }
  return null;
}

class FastSession {
  const FastSession({
    required this.presetId,
    required this.startedAt,
    required this.plannedEnd,
    this.endedAt,
    this.endReason,
    this.mealGraceUntil,
  });

  final String presetId;
  final DateTime startedAt;
  final DateTime plannedEnd;
  final DateTime? endedAt;
  final FastEndReason? endReason;

  /// Meals logged at or before this don't end the fast (set on resume).
  final DateTime? mealGraceUntil;

  FastPreset get preset => presetById(presetId) ?? fastPresets.first;
  Duration get plannedLength => plannedEnd.difference(startedAt);
  bool get completed => endedAt != null && !endedAt!.isBefore(plannedEnd);

  FastSession copyWith({
    DateTime? plannedEnd,
    DateTime? endedAt,
    FastEndReason? endReason,
    DateTime? mealGraceUntil,
    bool clearEnd = false,
  }) =>
      FastSession(
        presetId: presetId,
        startedAt: startedAt,
        plannedEnd: plannedEnd ?? this.plannedEnd,
        endedAt: clearEnd ? null : (endedAt ?? this.endedAt),
        endReason: clearEnd ? null : (endReason ?? this.endReason),
        mealGraceUntil: mealGraceUntil ?? this.mealGraceUntil,
      );

  Map<String, dynamic> toJson() => {
        'preset': presetId,
        'start': startedAt.toIso8601String(),
        'end': plannedEnd.toIso8601String(),
        if (endedAt != null) 'ended': endedAt!.toIso8601String(),
        if (endReason != null) 'reason': endReason!.name,
        if (mealGraceUntil != null) 'grace': mealGraceUntil!.toIso8601String(),
      };

  static FastSession? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final start = DateTime.tryParse('${raw['start']}');
    final end = DateTime.tryParse('${raw['end']}');
    final preset = raw['preset']?.toString();
    if (start == null || end == null || preset == null) return null;
    FastEndReason? reason;
    for (final r in FastEndReason.values) {
      if (r.name == raw['reason']) reason = r;
    }
    return FastSession(
      presetId: preset,
      startedAt: start,
      plannedEnd: end,
      endedAt: raw['ended'] == null ? null : DateTime.tryParse('${raw['ended']}'),
      endReason: reason,
      mealGraceUntil: raw['grace'] == null ? null : DateTime.tryParse('${raw['grace']}'),
    );
  }
}

/// Where a running fast stands at a moment.
class FastStatus {
  const FastStatus(this.session, this.now);
  final FastSession session;
  final DateTime now;

  Duration get elapsed {
    final d = now.difference(session.startedAt);
    return d.isNegative ? Duration.zero : d;
  }

  Duration get remaining {
    final d = session.plannedEnd.difference(now);
    return d.isNegative ? Duration.zero : d;
  }

  bool get goalReached => !now.isBefore(session.plannedEnd);

  double get progress {
    final total = session.plannedLength.inSeconds;
    if (total <= 0) return 1;
    return (elapsed.inSeconds / total).clamp(0.0, 1.0);
  }
}

class FastingState {
  const FastingState({this.active, this.scheduled, this.history = const [], this.lastPresetId});

  final FastSession? active;

  /// A fast set to start later (e.g. tomorrow's Ekadashi).
  final FastSession? scheduled;

  /// Ended fasts, newest first.
  final List<FastSession> history;
  final String? lastPresetId;

  static const FastingState empty = FastingState();

  FastingState copyWith({
    FastSession? active,
    FastSession? scheduled,
    List<FastSession>? history,
    String? lastPresetId,
    bool clearActive = false,
    bool clearScheduled = false,
  }) =>
      FastingState(
        active: clearActive ? null : (active ?? this.active),
        scheduled: clearScheduled ? null : (scheduled ?? this.scheduled),
        history: history ?? this.history,
        lastPresetId: lastPresetId ?? this.lastPresetId,
      );

  Map<String, dynamic> toJson() => {
        if (active != null) 'active': active!.toJson(),
        if (scheduled != null) 'scheduled': scheduled!.toJson(),
        'history': [for (final h in history) h.toJson()],
        if (lastPresetId != null) 'last': lastPresetId,
      };

  static FastingState fromJson(dynamic raw) {
    if (raw is! Map) return empty;
    final hist = <FastSession>[];
    if (raw['history'] is List) {
      for (final h in raw['history'] as List) {
        final s = FastSession.fromJson(h);
        if (s != null) hist.add(s);
      }
    }
    return FastingState(
      active: FastSession.fromJson(raw['active']),
      scheduled: FastSession.fromJson(raw['scheduled']),
      history: hist,
      lastPresetId: raw['last']?.toString(),
    );
  }
}

class FastingService {
  FastingService._();
  static final FastingService instance = FastingService._();

  @visibleForTesting
  FastingService.forTest();

  static const _kState = 'fasting_state_v1';
  static const maxHistory = 30;

  final ValueNotifier<FastingState> state = ValueNotifier(FastingState.empty);
  String? _userId;
  SharedPreferences? _prefs;
  bool _listening = false;

  /// Injected clock for tests.
  DateTime Function() clock = DateTime.now;

  String? get userId => _userId;

  Future<void> initForUser(String userId, {SharedPreferences? prefsOverride}) async {
    _userId = userId;
    _prefs = prefsOverride ?? await SharedPreferences.getInstance();
    var loaded = FastingState.empty;
    final raw = _prefs!.getString('${_kState}_$userId');
    if (raw != null) {
      try {
        loaded = FastingState.fromJson(jsonDecode(raw));
      } catch (_) {}
    }
    if (_userId != userId) return; // switched while loading
    state.value = loaded;
    if (!_listening) {
      _listening = true;
      PersistenceService.dayLogNotifier.addListener(_onLogsChanged);
    }
    await refresh();
  }

  void clearMemory() {
    _userId = null;
    state.value = FastingState.empty;
  }

  void _onLogsChanged() {
    if (_userId == null) return;
    onMealsChanged(dayLogStore).ignore();
  }

  // ── Commands ───────────────────────────────────────────────────────────────

  /// Starts [presetId] now (or at [now]). [endAt] overrides the preset's end.
  Future<void> start(String presetId, {DateTime? now, DateTime? endAt}) async {
    final preset = presetById(presetId);
    if (preset == null) return;
    final t = now ?? clock();
    var cur = state.value;
    if (cur.active != null) cur = _ended(cur, t, FastEndReason.manual);
    final end = endAt != null && endAt.isAfter(t) ? endAt : preset.plannedEnd(t);
    await _set(cur.copyWith(
      active: FastSession(presetId: presetId, startedAt: t, plannedEnd: end),
      lastPresetId: presetId,
      clearScheduled: true,
    ));
  }

  /// Ends the running fast.
  Future<void> stop({DateTime? now, FastEndReason reason = FastEndReason.manual}) async {
    if (state.value.active == null) return;
    await _set(_ended(state.value, now ?? clock(), reason));
  }

  /// Moves the planned end of the running fast.
  Future<void> setEnd(DateTime end) async {
    final a = state.value.active;
    if (a == null || !end.isAfter(a.startedAt)) return;
    await _set(state.value.copyWith(active: a.copyWith(plannedEnd: end)));
  }

  /// Plans a fast to start at [startAt] (e.g. tomorrow's Ekadashi). It starts
  /// on its own the next time the app checks after that moment.
  Future<void> schedule(String presetId, DateTime startAt, {DateTime? endAt}) async {
    final preset = presetById(presetId);
    if (preset == null) return;
    final end = endAt != null && endAt.isAfter(startAt) ? endAt : preset.plannedEnd(startAt);
    await _set(state.value.copyWith(
      scheduled: FastSession(presetId: presetId, startedAt: startAt, plannedEnd: end),
      lastPresetId: presetId,
    ));
    await refresh();
  }

  Future<void> cancelSchedule() async {
    if (state.value.scheduled == null) return;
    await _set(state.value.copyWith(clearScheduled: true));
  }

  /// Puts back a fast that a meal log ended (logged by mistake, or a meal from
  /// before the fast logged late). Meals logged up to now won't end it again.
  Future<bool> resumeLast({DateTime? now}) async {
    final cur = state.value;
    if (cur.active != null || cur.history.isEmpty) return false;
    final last = cur.history.first;
    if (last.endReason != FastEndReason.meal) return false;
    final t = now ?? clock();
    await _set(cur.copyWith(
      active: last.copyWith(clearEnd: true, mealGraceUntil: t),
      history: cur.history.sublist(1),
    ));
    return true;
  }

  /// Starts a due scheduled fast. Safe to call often.
  Future<void> refresh({DateTime? now}) async {
    final t = now ?? clock();
    final s = state.value.scheduled;
    if (s == null || s.startedAt.isAfter(t)) return;
    if (!s.plannedEnd.isAfter(t)) {
      // The whole window passed while the app was closed: drop it quietly.
      await _set(state.value.copyWith(clearScheduled: true));
      return;
    }
    if (state.value.active != null) return;
    await _set(state.value.copyWith(active: s, clearScheduled: true));
  }

  /// Ends a no-food fast when a meal is logged after it started. Looks only at
  /// the days the fast spans.
  Future<void> onMealsChanged(Map<String, DayLog> store, {DateTime? now}) async {
    final a = state.value.active;
    if (a == null || !a.preset.endsOnMeal) return;
    final t = now ?? clock();
    final after = a.mealGraceUntil != null && a.mealGraceUntil!.isAfter(a.startedAt) ? a.mealGraceUntil! : a.startedAt;
    DateTime? first;
    var day = DateTime(a.startedAt.year, a.startedAt.month, a.startedAt.day);
    final lastDay = DateTime(t.year, t.month, t.day);
    while (!day.isAfter(lastDay)) {
      final log = store[dateKey(day)];
      if (log != null) {
        for (final e in log.allEntries) {
          final at = e.addedAt;
          if (!at.isAfter(after) || at.isAfter(t.add(const Duration(minutes: 1)))) continue;
          if (first == null || at.isBefore(first)) first = at;
        }
      }
      day = day.add(const Duration(days: 1));
    }
    if (first == null) return;
    await _set(_ended(state.value, first, FastEndReason.meal));
  }

  // ── Queries ────────────────────────────────────────────────────────────────

  FastStatus? status({DateTime? now}) {
    final a = state.value.active;
    return a == null ? null : FastStatus(a, now ?? clock());
  }

  /// A phalahar fast is running: suggest vrat foods only.
  bool vratFoodsOnly({DateTime? now}) {
    final a = state.value.active;
    return a != null && a.preset.allowsVratFoods;
  }

  /// What Kyno sees. Null when there's nothing to say.
  Map<String, dynamic>? briefJson({DateTime? now}) {
    final t = now ?? clock();
    final s = state.value;
    final recent = s.history.where((h) => t.difference(h.startedAt).inDays < 14).toList();
    if (s.active == null && s.scheduled == null && recent.isEmpty) return null;
    String hm(DateTime d) => '${dateKey(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    double h(Duration d) => (d.inMinutes / 6).round() / 10;
    final out = <String, dynamic>{};
    final a = s.active;
    if (a != null) {
      final st = FastStatus(a, t);
      out['active'] = {
        'type': a.preset.label,
        'religious': a.preset.isReligious,
        'started': hm(a.startedAt),
        'planned_end': hm(a.plannedEnd),
        'elapsed_hours': h(st.elapsed),
        'remaining_hours': h(st.remaining),
        'goal_reached': st.goalReached,
        'vrat_foods_only': a.preset.allowsVratFoods,
        'logging_a_meal_ends_it': a.preset.endsOnMeal,
      };
    }
    final sc = s.scheduled;
    if (sc != null) {
      out['scheduled'] = {'type': sc.preset.label, 'starts': hm(sc.startedAt), 'ends': hm(sc.plannedEnd)};
    }
    if (recent.isNotEmpty) {
      out['fasts_last_14d'] = recent.length;
      out['completed_last_14d'] = recent.where((x) => x.completed).length;
    }
    return out;
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  FastingState _ended(FastingState cur, DateTime at, FastEndReason reason) {
    final a = cur.active;
    if (a == null) return cur;
    final endAt = at.isBefore(a.startedAt) ? a.startedAt : at;
    final done = a.copyWith(endedAt: endAt, endReason: reason);
    final hist = [done, ...cur.history];
    return cur.copyWith(
      clearActive: true,
      history: hist.length > maxHistory ? hist.sublist(0, maxHistory) : hist,
    );
  }

  Future<void> _set(FastingState next) async {
    state.value = next;
    final owner = _userId;
    if (owner == null) return;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    if (_userId != owner) return;
    await prefs.setString('${_kState}_$owner', jsonEncode(next.toJson()));
  }
}
