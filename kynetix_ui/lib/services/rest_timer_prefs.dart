import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/workout_session.dart';
import '../models/workout_split.dart';
import 'user_session_coordinator.dart';

/// Remembered rest durations, one per exercise, scoped to the signed-in user.
///
/// Stored the way WorkoutService scopes its data: a base key suffixed with the
/// current user id (`<base>_<userId>`), so two accounts on one phone never see
/// each other's rest settings. Reads are synchronous from an in-memory cache
/// (the rest timer starts on the commit frame of a logged set), writes are
/// fire-and-forget to SharedPreferences.
class RestTimerPrefs {
  RestTimerPrefs._();
  static final RestTimerPrefs instance = RestTimerPrefs._();

  static const String baseKey = 'kynetix_rest_durations_v1';
  static const String _askedKeyBase = 'kynetix_rest_notif_asked_v1';

  /// Shortest and longest rest the picker offers.
  static const int minSeconds = 30;
  static const int maxSeconds = 300;

  /// Choices offered by the rest picker (30s to 5m).
  static const List<int> presets = [30, 45, 60, 75, 90, 120, 150, 180, 240, 300];

  /// The user-scoped key. A signed-out session uses the bare base key, same
  /// as WorkoutService's `_currentPrefKey`.
  static String keyFor(String? userId) =>
      (userId != null && userId.isNotEmpty) ? '${baseKey}_$userId' : baseKey;

  static String askedKeyFor(String? userId) =>
      (userId != null && userId.isNotEmpty) ? '${_askedKeyBase}_$userId' : _askedKeyBase;

  /// Default rest when nothing is remembered: heavy compounds get longer.
  static int defaultFor(ExerciseType type) =>
      type == ExerciseType.barbellCompound ? 90 : 60;

  /// Clamp to the picker range and snap to 15 s steps.
  static int normalize(int seconds) {
    final clamped = seconds.clamp(minSeconds, maxSeconds);
    return ((clamped / 15).round() * 15).clamp(minSeconds, maxSeconds);
  }

  /// The rest timer must not run between a set and the drop that follows it:
  /// if the next set is queued as a drop, the lifter goes straight into it.
  static bool shouldStartRest({required SetType nextSetType}) =>
      nextSetType != SetType.dropSet;

  String? _loadedFor;
  bool _loaded = false;
  final Map<String, int> _durations = {};
  bool _notificationAsked = false;

  /// Overridable in tests; production reads the session coordinator.
  @visibleForTesting
  String? Function() userIdProvider = () => UserSessionCoordinator.instance.currentUserId;

  bool get notificationAsked => _notificationAsked;

  /// Loads the current user's durations (no-op when already loaded for them).
  Future<void> load({SharedPreferences? prefsOverride}) async {
    final uid = userIdProvider();
    if (_loaded && _loadedFor == uid) return;
    try {
      final prefs = prefsOverride ?? await SharedPreferences.getInstance();
      _durations.clear();
      final raw = prefs.getString(keyFor(uid));
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((k, v) {
            if (k is String && v is num) _durations[k] = normalize(v.toInt());
          });
        }
      }
      _notificationAsked = prefs.getBool(askedKeyFor(uid)) ?? false;
      _loadedFor = uid;
      _loaded = true;
    } catch (e) {
      debugPrint('[REST_PREFS] load failed: $e');
    }
  }

  /// Rest for [exercise]: the remembered value, else the type default.
  int durationFor(Exercise exercise) {
    if (_loadedFor != userIdProvider()) {
      // A different account signed in since the last load; never leak its
      // values. Fall back to defaults until load() runs again.
      return defaultFor(exercise.type);
    }
    return _durations[exercise.id] ?? defaultFor(exercise.type);
  }

  /// Whether [exerciseId] has a remembered (non-default) duration.
  bool hasCustom(String exerciseId) =>
      _loadedFor == userIdProvider() && _durations.containsKey(exerciseId);

  /// Remember [seconds] for [exerciseId] for the current user.
  Future<void> setDuration(String exerciseId, int seconds, {SharedPreferences? prefsOverride}) async {
    final uid = userIdProvider();
    if (_loadedFor != uid) {
      _loaded = false;
      await load(prefsOverride: prefsOverride);
    }
    _durations[exerciseId] = normalize(seconds);
    try {
      final prefs = prefsOverride ?? await SharedPreferences.getInstance();
      await prefs.setString(keyFor(uid), jsonEncode(_durations));
    } catch (e) {
      debugPrint('[REST_PREFS] save failed: $e');
    }
  }

  /// Record that the notification permission prompt was shown once.
  Future<void> markNotificationAsked({SharedPreferences? prefsOverride}) async {
    _notificationAsked = true;
    try {
      final prefs = prefsOverride ?? await SharedPreferences.getInstance();
      await prefs.setBool(askedKeyFor(userIdProvider()), true);
    } catch (_) {}
  }

  @visibleForTesting
  void resetForTest() {
    _loaded = false;
    _loadedFor = null;
    _durations.clear();
    _notificationAsked = false;
  }
}

/// "1:30", "45s", "5 min" style label for a rest duration.
String restLabel(int seconds) {
  if (seconds < 60) return '${seconds}s';
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return s == 0 ? '$m min' : '$m:${s.toString().padLeft(2, '0')}';
}
