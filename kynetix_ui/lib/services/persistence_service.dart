import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';
import 'profile_service.dart';
import '../models/day_log.dart';
import '../services/cloud_sync_service.dart';
import '../services/user_nutrition_memory.dart';
import '../services/eating_pattern_service.dart';
import '../services/quick_add_service.dart';
import '../services/personal_nutrition_memory.dart';
import '../services/meal_memory.dart';
import '../services/nutrition_hydration_guard.dart';
import 'widget_service.dart';
import 'workout_service.dart';
import 'insights_report_service.dart';
import 'nutrition_target_engine.dart';

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
  static String? _cachedOwnerId;
  static DateTime lastLogsChangedAt = DateTime.now();
  static DateTime? lastDayLogsHydratedAt;
  static DateTime? lastHistoricalRepairCompletedAt;
  static final ValueNotifier<int> dayLogNotifier = ValueNotifier<int>(0);

  static void notifyLogsChanged() {
    lastLogsChangedAt = DateTime.now();
    dayLogNotifier.value++;
  }

  static String? get cachedOwnerId => _cachedOwnerId;

  static Future<void> setCachedOwnerId(String userId) async {
    _cachedOwnerId = userId;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_owner_user_id_v1', userId);
      // Synchronize in-memory owner IDs immediately
      UserNutritionMemory.instance.setOwnerId(userId);
      PersonalNutritionMemory.instance.setOwnerId(userId);
      MealMemory.instance.setOwnerId(userId);
    } catch (_) {}
  }

  static bool get isOnboardingDone => _onboardingDone;

  // ── Startup load ─────────────────────────────────────────────────────────

  /// Restore all persisted state. Must be awaited before runApp().
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      _onboardingDone = prefs.getBool(_kOnboarding) ?? false;
      _cachedOwnerId = prefs.getString('cached_owner_user_id_v1');

      // Hook hydration complete callback to save user ID
      NutritionHydrationGuard.instance.onHydrationComplete = (userId) {
        setCachedOwnerId(userId).ignore();
      };

      final profileRaw = prefs.getString(_kProfile);
      if (profileRaw != null) {
        ProfileService.instance.currentUserProfile = UserProfile.fromJson(
            jsonDecode(profileRaw) as Map<String, dynamic>);
      }

      // One-time quarantine: wipe legacy memory stores that may contain
      // pre-normalization corrupted values (total calories stored without
      // per-unit division, then double-scaled by _itemFromMemory).
      await _quarantineLegacyMemory(prefs);

      // Load recurring nutrition memory from SharedPreferences first so it is ready for day log loading.
      await UserNutritionMemory.instance.init();
      await EatingPatternService.instance.load();
      await QuickAddService.instance.init();
      await InsightsReportService.instance.init();

      final logsRaw = prefs.getString(_kDayLogs);
      if (logsRaw != null) {
        final map = jsonDecode(logsRaw) as Map<String, dynamic>;
        for (final e in map.entries) {
          dayLogStore[e.key] =
              DayLog.fromJson(e.value as Map<String, dynamic>);
        }
      }
    } catch (_) {
      // Corrupt prefs — start fresh (user re-onboards once).
      _onboardingDone = false;
    }
  }

  /// Quarantine legacy pre-normalization memory on first run.
  ///
  /// Problem: before the per-unit normalization architecture was introduced,
  /// MealMemory._store and UserNutritionMemory stored TOTAL calories.  The
  /// new pipeline's _itemFromPortionMemory no longer scales these, BUT old
  /// in-flight SharedPreferences values from before the fix may still be
  /// present.  Wiping them on first post-migration boot forces fresh
  /// AI/local estimation which will produce correct values.
  ///
  /// Keys wiped:
  ///   meal_memory_v1            – old recurring store (total calories, no unit)
  ///   meal_memory_candidates_v1 – promoted AI candidates (same issue)
  ///   known_food_memory_v1      – rebuilt from bootstrapDefaultKnownFoods
  ///   user_meal_overrides_v1    – old override blobs without caloriesPerUnit
  ///
  /// Day logs, profile, and onboarding are NOT touched.
  static Future<void> _quarantineLegacyMemory(SharedPreferences prefs) async {
    const migrationFlag = 'memory_schema_v2_migrated';
    if (prefs.getBool(migrationFlag) == true) return;

    // Wipe all old memory keys
    await prefs.remove('meal_memory_v1');
    await prefs.remove('meal_memory_candidates_v1');
    await prefs.remove('known_food_memory_v1');
    await prefs.remove('user_meal_overrides_v1');

    // Set migration flag so this never runs again
    await prefs.setBool(migrationFlag, true);

    debugPrint('[PersistenceService] ⚠️  Legacy memory quarantine complete '
        '(one-time migration to per-unit schema)');
  }

  // ── Write helpers ─────────────────────────────────────────────────────────

  static Future<void> saveProfile(UserProfile p) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final oldRaw = prefs.getString(_kProfile);
      UserProfile? oldProfile;
      if (oldRaw != null) {
        try {
          oldProfile = UserProfile.fromJson(jsonDecode(oldRaw) as Map<String, dynamic>);
        } catch (_) {}
      }

      final hasChanged = oldProfile == null ||
          oldProfile.goal != p.goal ||
          oldProfile.weight != p.weight ||
          oldProfile.height != p.height ||
          oldProfile.age != p.age ||
          oldProfile.gender != p.gender ||
          oldProfile.workoutDaysMin != p.workoutDaysMin ||
          oldProfile.workoutDaysMax != p.workoutDaysMax ||
          oldProfile.useCustomTargets != p.useCustomTargets ||
          oldProfile.customMaintenanceCalories != p.customMaintenanceCalories ||
          oldProfile.customTrainingDayCalories != p.customTrainingDayCalories ||
          oldProfile.customRestDayCalories != p.customRestDayCalories ||
          oldProfile.customProteinTarget != p.customProteinTarget;

      UserProfile finalProfile = p;
      if (hasChanged) {
        final record = TargetChangeRecord(
          timestamp: DateTime.now(),
          sourceType: p.useCustomTargets ? 'Custom Targets' : 'System Calculated',
          profileSnapshot: p.toSnapshotJson(),
        );

        final newHistory = List<TargetChangeRecord>.from(p.targetChangeHistory)..add(record);
        finalProfile = p.copyWith(targetChangeHistory: newHistory);
        ProfileService.instance.currentUserProfile = finalProfile;
      }

      await prefs.setString(_kProfile, jsonEncode(finalProfile.toJson()));
      WidgetService.updateWidgetData().ignore();
    } catch (_) {}
  }

  static Future<void> setOnboardingDone() async {
    _onboardingDone = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kOnboarding, true);
    } catch (_) {}
  }

  static Future<void> saveDayLogs() async {
    lastLogsChangedAt = DateTime.now();
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
    } catch (_) {}
  }

  static Future<void> runHistoricalRepairMigration() async {
    bool migrated = false;

    for (final entry in dayLogStore.entries) {
      final log = entry.value;
      final date = DateTime.tryParse(entry.key);
      if (date == null) continue;

      if (log.gymDay == null && !log.isEmpty) {
        final splitDay = WorkoutService.instance.splitDayFor(date);
        if (splitDay != null && !splitDay.isRestDay) {
          log.gymDay = GymDay(
            didGym: true,
            workoutType: WorkoutType.fromSplitName(splitDay.name),
            splitDayName: splitDay.name,
            splitOverridden: false,
          );
          migrated = true;
        } else {
          log.gymDay = const GymDay(didGym: false);
          migrated = true;
        }
      }

      // Freeze missing targets for any historical days that have null values
      if (log.targetCalories == null || log.targetProtein == null) {
        final profile = ProfileService.instance.currentUserProfile;
        if (profile != null) {
          final historicalProfile = profile.profileActiveOn(date);
          if (historicalProfile == null) {
            debugPrint('[PersistenceService] Skipping target freeze for $entry: insufficient timeline history');
            continue;
          }
          final resolvedTarget = NutritionTargetEngine.instance.effectiveTargetForDate(
            date,
            profile: historicalProfile,
            forceRecalculate: true,
          );
          log.targetCalories = resolvedTarget.calories;
          log.targetProtein = resolvedTarget.protein;
          migrated = true;
          debugPrint('[PersistenceService] Freezing targets on startup for $entry using historical profile: '
              '${resolvedTarget.calories} kcal / ${resolvedTarget.protein}g');
        }
      }
    }

    if (migrated) {
      await saveDayLogs();
      CloudSyncService.instance.syncDayLogsBackground().ignore();
    }
    lastHistoricalRepairCompletedAt = DateTime.now();
    debugPrint('[PersistenceService] Historical repair migration complete at: $lastHistoricalRepairCompletedAt');
  }

  static Future<void> saveDay(DateTime date) async {
    final dKey = dateKey(date);
    final log = dayLogStore[dKey];
    if (log != null) {
      if (log.gymDay == null && !log.isEmpty) {
        final splitDay = WorkoutService.instance.splitDayFor(date);
        if (splitDay != null && !splitDay.isRestDay) {
          log.gymDay = GymDay(
            didGym: true,
            workoutType: WorkoutType.fromSplitName(splitDay.name),
            splitDayName: splitDay.name,
            splitOverridden: false,
          );
        } else {
          log.gymDay = const GymDay(didGym: false);
        }
      }

      // Calculate and freeze targets on save to prevent retrospective drift if user profile changes later
      // Ensure: whenever a DayLog is actually persisted for any reason, if targetCalories or targetProtein are null,
      // compute them once, write them, and never overwrite them again.
      // Every newly created DayLog must freeze targets immediately using the historical profile active on that date.
      if (log.targetCalories == null || log.targetProtein == null) {
        final profile = ProfileService.instance.currentUserProfile;
        if (profile != null) {
          final historicalProfile = profile.profileActiveOn(date) ?? profile;
          final resolvedTarget = NutritionTargetEngine.instance.effectiveTargetForDate(
            date,
            profile: historicalProfile,
            forceRecalculate: true,
          );
          log.targetCalories = resolvedTarget.calories;
          log.targetProtein = resolvedTarget.protein;
        }
      }
    }

    await saveDayLogs();
    
    WidgetService.updateWidgetData().catchError((_) {}).ignore();
    
    // Fire-and-forget sync to Supabase
    try {
      CloudSyncService.instance.syncDayLogsBackground().catchError((_) {}).ignore();
    } catch (_) {}
    
    final profile = ProfileService.instance.currentUserProfile;
    if (profile != null) {
      InsightsReportService.instance.recomputeForDate(date, profile).ignore();
    }
  }

  /// Wipe all persisted data (for settings / reset flow).
  ///
  /// ACCOUNT SWITCH SEQUENCE (enforced):
  ///   1. NutritionHydrationGuard.reset()    ← FIRST (closes the gate)
  ///   2. PersonalNutritionMemory.clearAll()
  ///   3. MealMemory.clearAll()
  ///   4. UserNutritionMemory.clearAll()
  ///   5. QuickAddService.resetAll()
  ///   6. EatingPatternService.resetAll()
  ///   7. WorkoutService.clearAll()
  ///   8. SharedPreferences cleanup
  ///   9. supabase.auth.signOut()  ← happens in AuthService.signOut() after this
  ///  10. Login screen shown
  static Future<void> reset() async {
    // Step 1: close the nutrition memory gate BEFORE clearing any local data.
    // This prevents any read that might slip in between clear calls.
    NutritionHydrationGuard.instance.reset();

    _onboardingDone = false;
    ProfileService.instance.currentUserProfile = null;
    _cachedOwnerId = null;
    dayLogStore.clear();

    // Steps 2–4: wipe user-specific nutrition memory
    await PersonalNutritionMemory.instance.clearAll();
    await MealMemory.instance.clearAll();
    await UserNutritionMemory.instance.clearAll();

    // Steps 5–7: wipe other local services
    EatingPatternService.instance.resetAll();
    await QuickAddService.instance.resetAll();
    await WorkoutService.instance.clearAll();
    await InsightsReportService.instance.reset();
    await WidgetService.updateWidgetData();

    // Step 8: explicit SharedPreferences cleanup (belt-and-suspenders over
    // the individual clearAll() calls above, plus keys those don't own)
    try {
      final prefs = await SharedPreferences.getInstance();
      // Core profile + session
      await prefs.remove(_kProfile);
      await prefs.remove(_kOnboarding);
      await prefs.remove(_kDayLogs);
      await prefs.remove('cached_owner_user_id_v1');
      await prefs.remove('insights_weekly_v1');
      await prefs.remove('insights_monthly_v1');
      await prefs.remove('insights_yearly_v1');
      await prefs.remove('insights_personal_bests_v1');
      await prefs.remove('insights_achievements_v1');
      await prefs.remove('insights_ai_summaries_v1');
      await prefs.remove('insights_last_computed_v1');
      // Nutrition memory (belt-and-suspenders over clearAll() calls above)
      await prefs.remove('personal_nutrition_memory_v1');
      await prefs.remove('meal_memory_v1');
      await prefs.remove('meal_memory_candidates_v1');
      await prefs.remove('known_food_memory_v1');
      await prefs.remove('user_meal_overrides_v1');
      // Eating patterns
      await prefs.remove('eating_patterns_v1');
      await prefs.remove('meal_context_v1');
      // Carry-forward cache (dashboard_screen)
      await prefs.remove('carry_forward_resolved_dates_v1');
      await prefs.remove('carry_forward_history_v1');
      // NOTE: 'memory_schema_v2_migrated' is intentionally NOT removed.
      // It is a one-time migration sentinel; clearing it would re-trigger
      // the legacy quarantine on every logout.
    } catch (_) {}
    debugPrint('[PersistenceService] ✅ reset() complete — all user data wiped');
  }
}
