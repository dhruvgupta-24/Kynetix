import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/onboarding_screen.dart';
import '../models/day_log.dart';
import '../services/cloud_sync_service.dart';
import '../services/user_nutrition_memory.dart';

// ─── PersistenceService ───────────────────────────────────────────────────────
//
// Single source of truth for all SharedPreferences writes.
// Call PersistenceService.load() once in main() before runApp().

class PersistenceService {
  PersistenceService._();

  static const _kProfile    = 'user_profile_v2';
  static const _kOnboarding = 'onboarding_done_v1';
  static const _kDayLogs    = 'day_logs_v1';

  static bool _onboardingDone = false;

  static bool get isOnboardingDone => _onboardingDone;

  // ── Startup load ─────────────────────────────────────────────────────────

  /// Restore all persisted state. Must be awaited before runApp().
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      _onboardingDone = prefs.getBool(_kOnboarding) ?? false;

      final profileRaw = prefs.getString(_kProfile);
      if (profileRaw != null) {
        currentUserProfile = UserProfile.fromJson(
            jsonDecode(profileRaw) as Map<String, dynamic>);
      }

      final logsRaw = prefs.getString(_kDayLogs);
      if (logsRaw != null) {
        final map = jsonDecode(logsRaw) as Map<String, dynamic>;
        for (final e in map.entries) {
          dayLogStore[e.key] =
              DayLog.fromJson(e.value as Map<String, dynamic>);
        }
      }
      // Load recurring nutrition memory from SharedPreferences.
      // This makes memory available offline, before cloud hydration runs.
      await UserNutritionMemory.instance.init();
    } catch (_) {
      // Corrupt prefs — start fresh (user re-onboards once).
      _onboardingDone = false;
    }
  }

  // ── Write helpers ─────────────────────────────────────────────────────────

  static Future<void> saveProfile(UserProfile p) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kProfile, jsonEncode(p.toJson()));
    } catch (_) {}
  }

  static Future<void> setOnboardingDone() async {
    _onboardingDone = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kOnboarding, true);
    } catch (_) {}
  }

  /// Persist all day logs, pruning entries older than 90 days.
  static Future<void> saveDayLogs() async {
    try {
      final cutoff = DateTime.now().subtract(const Duration(days: 90));
      final pruned = <String, dynamic>{};
      for (final e in dayLogStore.entries) {
        final d = DateTime.tryParse(e.key);
        if (d != null && d.isAfter(cutoff)) {
          pruned[e.key] = e.value.toJson();
        }
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kDayLogs, jsonEncode(pruned));
      
      // Fire-and-forget sync to Supabase
      CloudSyncService.instance.syncDayLogsBackground();
    } catch (_) {}
  }

  /// Convenience alias — saves all logs (a single JSON blob is atomic).
  static Future<void> saveDay(DateTime _) => saveDayLogs();

  /// Wipe all persisted data (for settings / reset flow).
  static Future<void> reset() async {
    _onboardingDone = false;
    currentUserProfile = null;
    dayLogStore.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kProfile);
      await prefs.remove(_kOnboarding);
      await prefs.remove(_kDayLogs);
      await prefs.remove('user_meal_overrides_v1'); // nutrition memory
    } catch (_) {}
  }
}
