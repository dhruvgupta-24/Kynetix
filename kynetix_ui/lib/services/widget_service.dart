import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/day_log.dart';
import '../models/user_profile.dart';
import 'health_service.dart';
import 'profile_service.dart';
import '../services/nutrition_target_engine.dart';

// Logging in this file is debug-only: release builds skip the console I/O.
void _debugLog(String? message, {int? wrapWidth}) {
  if (kDebugMode) debugPrint(message, wrapWidth: wrapWidth);
}

/// Feeds the Android home-screen widget (KynetixWidgetProvider.kt).
///
/// Payload contract (JSON under SharedPreferences key `widget_data_v1`, which
/// the native side reads as `flutter.widget_data_v1`):
///
/// ```
/// {
///   "v": 2,
///   "date_key": "2026-10-17",         // the day these numbers belong to
///   "last_update_date": "2026-10-17", // legacy alias of date_key
///   "last_update_time": "14:05",
///   "calories_consumed": 1240,        // sum of each meal's rounded kcal
///   "calories_target": 2140,          // rounded engine target (with health)
///   "calories_remaining": 900,
///   "protein_consumed": 82,
///   "protein_target": 140,
///   "protein_remaining": 58,
///   "is_training_day": true,
///   "day_label": "Push Day",
///   "next_day": {                     // tomorrow, so the widget is right
///     "date_key": "2026-10-18",       // after midnight without the app
///     "calories_target": 1980,
///     "protein_target": 132,
///     "is_training_day": false,
///     "day_label": "Rest Day"
///   }
/// }
/// ```
///
/// When there is no signed-in profile the key is removed and the widget
/// shows its "Open Kynetix" state; there is never a hard-coded fallback.
class WidgetService {
  WidgetService._();

  static const _channel = MethodChannel('com.kynetix.app/widget');
  static const prefsKey = 'widget_data_v1';
  static const payloadVersion = 2;

  /// The same totals the dashboard prints: every meal row shows its rounded
  /// kcal / protein, and the total is the sum of those printed numbers.
  /// Mirrors `displayKcal` / `displayProtein` in dashboard_screen.dart (kept
  /// local so this service does not import a screen).
  @visibleForTesting
  static int displayKcalFor(DayLog log) =>
      log.allEntries.fold<int>(0, (s, e) => s + e.calMid.round());

  @visibleForTesting
  static int displayProteinFor(DayLog log) =>
      log.allEntries.fold<int>(0, (s, e) => s + e.result.protein.mid.round());

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Builds the widget payload for [now]. Pure apart from reading the global
  /// day-log store (read-only: it never creates a log entry).
  @visibleForTesting
  static Map<String, Object?> buildPayload({
    required DateTime now,
    required UserProfile profile,
    HealthSyncResult? health,
    NutritionTargetEngine? engine,
  }) {
    final eng = engine ?? NutritionTargetEngine();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = DateTime(now.year, now.month, now.day + 1);

    final log = dayLogStore[dateKey(today)] ?? DayLog();
    final consumedCalories = displayKcalFor(log);
    final consumedProtein = displayProteinFor(log);

    // Same call the dashboard makes (dashboard_screen.dart _effectiveDayTarget).
    // The log is passed explicitly so a missing day resolves against an empty
    // log (what logFor would return) without inserting one into the store.
    final target = eng.effectiveTargetForDate(today,
        profile: profile, health: health, log: log);
    final next = eng.effectiveTargetForDate(tomorrow,
        profile: profile,
        health: health,
        log: dayLogStore[dateKey(tomorrow)] ?? DayLog());

    final targetCalories = target.calories.round();
    final targetProtein = target.protein.round();

    return {
      'v': payloadVersion,
      'date_key': _dateKey(today),
      'last_update_date': _dateKey(today),
      'last_update_time':
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
      'calories_consumed': consumedCalories,
      'calories_target': targetCalories,
      'calories_remaining': targetCalories - consumedCalories,
      'protein_consumed': consumedProtein,
      'protein_target': targetProtein,
      'protein_remaining': targetProtein - consumedProtein,
      'is_training_day': target.isTrainingDay,
      'day_label': target.label,
      'next_day': {
        'date_key': _dateKey(tomorrow),
        'calories_target': next.calories.round(),
        'protein_target': next.protein.round(),
        'is_training_day': next.isTrainingDay,
        'day_label': next.label,
      },
      // The week ahead, so the widget shows the right targets (with nothing
      // eaten yet) even on days the app has not been opened.
      'days': [
        for (var i = 1; i <= 7; i++)
          () {
            final d = DateTime(now.year, now.month, now.day + i);
            final t = eng.effectiveTargetForDate(d,
                profile: profile, health: health, log: dayLogStore[dateKey(d)] ?? DayLog());
            return {
              'date_key': _dateKey(d),
              'calories_target': t.calories.round(),
              'protein_target': t.protein.round(),
              'is_training_day': t.isTrainingDay,
              'day_label': t.label,
            };
          }(),
      ],
    };
  }

  /// Recalculates today's consumed and target macros and saves them into the
  /// shared preferences under a unified JSON string for the widget.
  static Future<void> updateWidgetData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final profile = ProfileService.instance.currentUserProfile;
      if (profile == null) {
        _debugLog('[WidgetService] Profile not found, clearing widget data');
        await prefs.remove(prefsKey);
        await _refreshNative();
        return;
      }

      final payload = buildPayload(
        now: DateTime.now(),
        profile: profile,
        // The dashboard passes the result of HealthService().sync(), which is
        // the value cached here.
        health: HealthService().lastSyncResult,
      );

      // Throttle: skip when nothing but the timestamp changed.
      final oldJson = prefs.getString(prefsKey);
      if (oldJson != null) {
        try {
          final oldMap = Map<String, Object?>.from(jsonDecode(oldJson) as Map)
            ..remove('last_update_time');
          final newMap = Map<String, Object?>.from(payload)..remove('last_update_time');
          if (jsonEncode(oldMap) == jsonEncode(newMap)) {
            _debugLog('[WidgetService] Widget data unchanged, skipping update');
            return;
          }
        } catch (_) {}
      }

      await prefs.setString(prefsKey, jsonEncode(payload));
      await _refreshNative();
      _debugLog('[WidgetService] Widget data updated successfully: $payload');
    } catch (e, stack) {
      _debugLog('[WidgetService] Failed to update widget data: $e\n$stack');
    }
  }

  static Future<void> _refreshNative() async {
    try {
      await _channel.invokeMethod('updateWidget');
    } on MissingPluginException {
      // Tests / platforms without the widget channel.
    }
  }
}
