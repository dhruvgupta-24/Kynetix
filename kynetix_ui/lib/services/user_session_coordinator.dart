import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/day_log.dart';
import '../models/workout_session.dart';
import 'eating_pattern_service.dart';
import 'insights_report_service.dart';
import 'kyno_context_service.dart';
import 'kyno_historical_analysis_service.dart';
import 'kyno_coaching_insight_service.dart';
import 'meal_memory.dart';
import 'nutrition_hydration_guard.dart';
import 'persistence_service.dart';
import 'personal_nutrition_memory.dart';
import 'profile_service.dart';
import 'quick_add_service.dart';
import 'user_nutrition_memory.dart';
import 'workout_service.dart';
import 'wakelock_service.dart';

class DataPreservationException implements Exception {
  final String message;
  final Map<String, dynamic>? details;
  DataPreservationException(this.message, [this.details]);

  @override
  String toString() => 'DataPreservationException: $message ${details ?? ""}';
}

class MigrationAuditReport {
  final String userId;
  final int historicalNutritionRecordsScanned;
  final int historicalNutritionRecordsChanged;
  final int historicalNutritionRecordsDeleted;
  final int historicalNutritionRecordsLost;
  final int workoutSessionsScanned;
  final int workoutSessionsChanged;
  final int workoutSessionsDeleted;
  final int workoutSessionsLost;
  final int overridesScanned;
  final int overridesLost;
  final int mealMemoryScanned;
  final int mealMemoryLost;
  final bool isVerified;
  final DateTime timestamp;

  const MigrationAuditReport({
    required this.userId,
    required this.historicalNutritionRecordsScanned,
    required this.historicalNutritionRecordsChanged,
    required this.historicalNutritionRecordsDeleted,
    required this.historicalNutritionRecordsLost,
    required this.workoutSessionsScanned,
    required this.workoutSessionsChanged,
    required this.workoutSessionsDeleted,
    required this.workoutSessionsLost,
    required this.overridesScanned,
    required this.overridesLost,
    required this.mealMemoryScanned,
    required this.mealMemoryLost,
    required this.isVerified,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'historicalNutritionRecordsScanned': historicalNutritionRecordsScanned,
    'historicalNutritionRecordsChanged': historicalNutritionRecordsChanged,
    'historicalNutritionRecordsDeleted': historicalNutritionRecordsDeleted,
    'historicalNutritionRecordsLost': historicalNutritionRecordsLost,
    'workoutSessionsScanned': workoutSessionsScanned,
    'workoutSessionsChanged': workoutSessionsChanged,
    'workoutSessionsDeleted': workoutSessionsDeleted,
    'workoutSessionsLost': workoutSessionsLost,
    'overridesScanned': overridesScanned,
    'overridesLost': overridesLost,
    'mealMemoryScanned': mealMemoryScanned,
    'mealMemoryLost': mealMemoryLost,
    'isVerified': isVerified,
    'timestamp': timestamp.toIso8601String(),
  };
}

/// Single authoritative coordinator for user identity, user-scoped service lifecycle,
/// and safe, non-destructive data migration with zero data loss.
class UserSessionCoordinator {
  UserSessionCoordinator._();
  static final UserSessionCoordinator instance = UserSessionCoordinator._();

  String? _currentUserId;
  String? get currentUserId => _currentUserId;
  bool get isAuthenticated => _currentUserId != null && _currentUserId!.isNotEmpty;

  MigrationAuditReport? _lastAuditReport;
  MigrationAuditReport? get lastAuditReport => _lastAuditReport;

  /// Prefix keys for user scoping
  static String scopedKey(String baseKey, String userId) => '${baseKey}_$userId';
  static String backupKey(String baseKey, String userId) => 'backup_pre_migration_${baseKey}_$userId';

  /// Primary unscoped storage keys that belong to a single user
  static const unscopedKeys = [
    'day_logs_v1',
    'workout_data_v2',
    'user_profile_v2',
    'user_profile_v1',
    'user_meal_overrides_v1',
    'meal_memory_v1',
    'meal_memory_candidates_v1',
    'known_food_memory_v1',
    'personal_nutrition_memory_v1',
    'eating_patterns_v1',
    'meal_context_v1',
    'kynetix_sleep_hours_v1',
    'kynetix_hrv_rmssd_v1',
    'kynetix_hrv_baseline_v1',
    'kynetix_workout_recovery',
    'insights_weekly_v1',
    'insights_monthly_v1',
    'insights_yearly_v1',
    'insights_personal_bests_v1',
    'insights_achievements_v1',
    'insights_ai_summaries_v1',
    'insights_last_computed_v1',
  ];

  /// Initialize all user-scoped services for the authenticated [userId].
  /// Enforces:
  /// 1. Auth comes FIRST.
  /// 2. Non-destructive migration of existing unscoped local stores with backup and field-by-field verification.
  /// 3. Zero historical record modifications, recalculations, or deletions.
  /// 4. User-scoped service initialization.
  Future<void> initializeForUser(String userId, {SharedPreferences? prefsOverride}) async {
    if (userId.isEmpty) {
      throw ArgumentError('[UserSessionCoordinator] Cannot initialize for empty userId');
    }

    // If switching from a different user, cleanly flush all in-memory states first.
    if (_currentUserId != null && _currentUserId != userId) {
      debugPrint('[UserSessionCoordinator] 🔄 Switching user from $_currentUserId to $userId');
      await clearAllUserServices();
    }

    _currentUserId = userId;
    final prefs = prefsOverride ?? await SharedPreferences.getInstance();

    // 1. Perform safe, non-destructive migration if not yet done for this user
    await migrateUnscopedDataForUser(userId, prefs);

    // 2. Set authoritative owner ID across persistence guards
    await PersistenceService.setCachedOwnerId(userId);

    // 3. Initialize user-scoped services with this user's data
    await PersistenceService.loadForUser(userId, prefsOverride: prefs);
    await WorkoutService.instance.initForUser(userId, prefsOverride: prefs);
    await UserNutritionMemory.instance.initForUser(userId, prefsOverride: prefs);
    await MealMemory.instance.initForUser(userId, prefsOverride: prefs);
    await PersonalNutritionMemory.instance.initForUser(userId, prefsOverride: prefs);
    await EatingPatternService.instance.loadForUser(userId, prefsOverride: prefs);
    await QuickAddService.instance.initForUser(userId, prefsOverride: prefs);
    await InsightsReportService.instance.initForUser(userId, prefsOverride: prefs);

    // 4. Reset KynoContext cache so no stale data from any prior session leaks
    KynoContextService.instance.reset();

    // 5. Open hydration guard for this user
    NutritionHydrationGuard.instance.markComplete(userId);

    debugPrint('[UserSessionCoordinator] ✅ All services successfully initialized for user: $userId');
  }

  /// Hard boundary flush for logout or account switching.
  /// Wipes all in-memory state without deleting persisted scoped data on disk.
  Future<void> clearAllUserServices() async {
    debugPrint('[UserSessionCoordinator] 🔒 Flushing all in-memory user states (Hard Boundary)');
    
    // Close the hydration gate first
    NutritionHydrationGuard.instance.reset();

    // Flush in-memory stores
    ProfileService.instance.currentUserProfile = null;
    dayLogStore.clear();
    WorkoutService.instance.clearMemory();
    UserNutritionMemory.instance.clearMemory();
    MealMemory.instance.clearMemory();
    PersonalNutritionMemory.instance.clearMemory();
    EatingPatternService.instance.clearMemory();
    QuickAddService.instance.clearMemory();
    InsightsReportService.instance.clearMemory();
    KynoContextService.instance.reset();
    KynoHistoricalAnalysisService.instance.clearMemory();
    KynoCoachingInsightService.instance.clearMemory();
    WakelockService.instance.disable().ignore();

    _currentUserId = null;
    debugPrint('[UserSessionCoordinator] ✅ In-memory flush complete — zero cross-user leakage');
  }

  /// Non-destructive migration:
  /// - Takes a pre-migration backup of all unscoped stores.
  /// - Copies raw data verbatim to user-scoped keys (zero recalculation, zero normalization).
  /// - Verifies counts and field-by-field macro and workout values.
  /// - Keeps the original unscoped stores intact as an emergency fallback.
  Future<MigrationAuditReport> migrateUnscopedDataForUser(String userId, SharedPreferences prefs) async {
    final migrationMarkerKey = 'migration_verified_v1_$userId';
    if (prefs.getBool(migrationMarkerKey) == true) {
      debugPrint('[UserSessionCoordinator] Migration already verified for user: $userId');
      return MigrationAuditReport(
        userId: userId,
        historicalNutritionRecordsScanned: 0,
        historicalNutritionRecordsChanged: 0,
        historicalNutritionRecordsDeleted: 0,
        historicalNutritionRecordsLost: 0,
        workoutSessionsScanned: 0,
        workoutSessionsChanged: 0,
        workoutSessionsDeleted: 0,
        workoutSessionsLost: 0,
        overridesScanned: 0,
        overridesLost: 0,
        mealMemoryScanned: 0,
        mealMemoryLost: 0,
        isVerified: true,
        timestamp: DateTime.now(),
      );
    }

    debugPrint('[UserSessionCoordinator] 🛡️ Starting Non-Destructive Pre-Migration Audit for user: $userId');

    int dayLogsScanned = 0;
    int dayLogsChanged = 0;
    int dayLogsDeleted = 0;
    int dayLogsLost = 0;

    int sessionsScanned = 0;
    int sessionsChanged = 0;
    int sessionsDeleted = 0;
    int sessionsLost = 0;

    int overridesScanned = 0;
    int overridesLost = 0;

    int mealMemoryScanned = 0;
    int mealMemoryLost = 0;

    // --- STEP 1: Capture Pre-Migration Backups & Copy Verbatim ---
    for (final baseKey in unscopedKeys) {
      final rawValue = prefs.get(baseKey);
      if (rawValue == null) continue;

      final bKey = backupKey(baseKey, userId);
      final sKey = scopedKey(baseKey, userId);
      final legacyBKey = 'backup_pre_migration_$baseKey';

      // Create pre-migration backup (both user-scoped backup and absolute pre-migration snapshot)
      if (rawValue is String) {
        await prefs.setString(bKey, rawValue);
        await prefs.setString(legacyBKey, rawValue);
        // Only populate scoped key if it doesn't already exist
        if (!prefs.containsKey(sKey)) {
          await prefs.setString(sKey, rawValue);
        }
      } else if (rawValue is List<String>) {
        await prefs.setStringList(bKey, rawValue);
        await prefs.setStringList(legacyBKey, rawValue);
        if (!prefs.containsKey(sKey)) {
          await prefs.setStringList(sKey, rawValue);
        }
      } else if (rawValue is bool) {
        await prefs.setBool(bKey, rawValue);
        await prefs.setBool(legacyBKey, rawValue);
        if (!prefs.containsKey(sKey)) {
          await prefs.setBool(sKey, rawValue);
        }
      } else if (rawValue is double) {
        await prefs.setDouble(bKey, rawValue);
        await prefs.setDouble(legacyBKey, rawValue);
        if (!prefs.containsKey(sKey)) {
          await prefs.setDouble(sKey, rawValue);
        }
      } else if (rawValue is int) {
        await prefs.setInt(bKey, rawValue);
        await prefs.setInt(legacyBKey, rawValue);
        if (!prefs.containsKey(sKey)) {
          await prefs.setInt(sKey, rawValue);
        }
      }
    }

    // --- STEP 2: Strict Day Logs Field-by-Field Integrity Audit ---
    final origLogsRaw = prefs.getString('day_logs_v1');
    final scopedLogsRaw = prefs.getString(scopedKey('day_logs_v1', userId));

    if (origLogsRaw != null) {
      if (scopedLogsRaw == null) {
        throw DataPreservationException(
          'Target scoped key day_logs_v1_$userId is missing after copy!',
        );
      }

      final origMap = jsonDecode(origLogsRaw) as Map<String, dynamic>;
      final scopedMap = jsonDecode(scopedLogsRaw) as Map<String, dynamic>;

      if (origMap.length != scopedMap.length) {
        throw DataPreservationException(
          'DayLog date count mismatch: original=${origMap.length} vs scoped=${scopedMap.length}',
        );
      }

      for (final dateKey in origMap.keys) {
        if (!scopedMap.containsKey(dateKey)) {
          dayLogsLost++;
          throw DataPreservationException(
            'DayLog missing date: $dateKey in scoped storage',
          );
        }

        final origLog = DayLog.fromJson(origMap[dateKey] as Map<String, dynamic>);
        final scopedLog = DayLog.fromJson(scopedMap[dateKey] as Map<String, dynamic>);

        for (final section in MealSection.values) {
          final origEntries = origLog.entriesFor(section);
          final scopedEntries = scopedLog.entriesFor(section);

          if (origEntries.length != scopedEntries.length) {
            dayLogsLost += (origEntries.length - scopedEntries.length).abs();
            throw DataPreservationException(
              'Entry count mismatch for date $dateKey in section ${section.name}: '
              'original=${origEntries.length} vs scoped=${scopedEntries.length}',
            );
          }

          for (int i = 0; i < origEntries.length; i++) {
            dayLogsScanned++;
            final o = origEntries[i];
            final s = scopedEntries[i];

            // Field-by-field exact numerical and semantic comparison
            final oCarb = o.result.carbohydrates?.mid;
            final sCarb = s.result.carbohydrates?.mid;
            final oFat = o.result.fat?.mid;
            final sFat = s.result.fat?.mid;
            final oFib = o.result.fiber?.mid;
            final sFib = s.result.fiber?.mid;

            if (o.rawInput != s.rawInput ||
                o.finalSavedInput != s.finalSavedInput ||
                o.calMid != s.calMid ||
                o.protMid != s.protMid ||
                oCarb != sCarb ||
                oFat != sFat ||
                oFib != sFib ||
                o.result.items.length != s.result.items.length) {
              dayLogsChanged++;
              throw DataPreservationException(
                'Historical record modified for date $dateKey, item "${o.rawInput}": '
                'orig=[${o.calMid} kcal, ${o.protMid}g P] vs scoped=[${s.calMid} kcal, ${s.protMid}g P]',
                {
                  'date': dateKey,
                  'section': section.name,
                  'original': o.toJson(),
                  'scoped': s.toJson(),
                },
              );
            }

            for (int itemIdx = 0; itemIdx < o.result.items.length; itemIdx++) {
              final oi = o.result.items[itemIdx];
              final si = s.result.items[itemIdx];
              if (oi.name != si.name ||
                  oi.quantity != si.quantity ||
                  oi.calories.mid != si.calories.mid ||
                  oi.protein.mid != si.protein.mid) {
                dayLogsChanged++;
                throw DataPreservationException(
                  'Historical item modified inside meal "${o.rawInput}": ${oi.name}',
                );
              }
            }
          }
        }
      }
    }

    // --- STEP 3: Strict Workout Data Integrity Audit ---
    final origWorkoutRaw = prefs.getString('workout_data_v2');
    final scopedWorkoutRaw = prefs.getString(scopedKey('workout_data_v2', userId));

    if (origWorkoutRaw != null) {
      if (scopedWorkoutRaw == null) {
        throw DataPreservationException(
          'Target scoped key workout_data_v2_$userId missing after copy!',
        );
      }

      final origData = jsonDecode(origWorkoutRaw) as Map<String, dynamic>;
      final scopedData = jsonDecode(scopedWorkoutRaw) as Map<String, dynamic>;

      final origSessions = (origData['sessions'] as List<dynamic>? ?? [])
          .map((s) => WorkoutSession.fromJson(s as Map<String, dynamic>))
          .toList();
      final scopedSessions = (scopedData['sessions'] as List<dynamic>? ?? [])
          .map((s) => WorkoutSession.fromJson(s as Map<String, dynamic>))
          .toList();

      if (origSessions.length != scopedSessions.length) {
        sessionsLost = (origSessions.length - scopedSessions.length).abs();
        throw DataPreservationException(
          'Workout session count mismatch: orig=${origSessions.length} vs scoped=${scopedSessions.length}',
        );
      }

      for (int i = 0; i < origSessions.length; i++) {
        sessionsScanned++;
        final o = origSessions[i];
        final s = scopedSessions[i];

        if (o.id != s.id ||
            o.splitDayName != s.splitDayName ||
            o.date.toIso8601String() != s.date.toIso8601String() ||
            o.entries.length != s.entries.length) {
          sessionsChanged++;
          throw DataPreservationException(
            'Workout session changed at index $i (id=${o.id})',
          );
        }

        // Compare each exercise entry and sets
        for (int eIdx = 0; eIdx < o.entries.length; eIdx++) {
          final oe = o.entries[eIdx];
          final se = s.entries[eIdx];

          if (oe.exercise.id != se.exercise.id ||
              oe.sets.length != se.sets.length) {
            sessionsChanged++;
            throw DataPreservationException(
              'Exercise entry changed in session ${o.id}: exercise=${oe.exercise.id}',
            );
          }

          for (int sIdx = 0; sIdx < oe.sets.length; sIdx++) {
            final os = oe.sets[sIdx];
            final ss = se.sets[sIdx];

            if (os.weight != ss.weight ||
                os.reps != ss.reps ||
                os.setType != ss.setType) {
              sessionsChanged++;
              throw DataPreservationException(
                'Set changed in session ${o.id}, exercise ${oe.exercise.id}, set $sIdx',
              );
            }
          }
        }
      }
    }

    // --- STEP 4: Strict User Meal Overrides Audit ---
    final origOverrides = prefs.getStringList('user_meal_overrides_v1');
    final scopedOverrides = prefs.getStringList(scopedKey('user_meal_overrides_v1', userId));

    if (origOverrides != null) {
      if (scopedOverrides == null || origOverrides.length != scopedOverrides.length) {
        overridesLost = origOverrides.length - (scopedOverrides?.length ?? 0);
        throw DataPreservationException(
          'User meal overrides count mismatch: orig=${origOverrides.length} vs scoped=${scopedOverrides?.length}',
        );
      }
      overridesScanned = origOverrides.length;
      for (int i = 0; i < origOverrides.length; i++) {
        if (origOverrides[i] != scopedOverrides[i]) {
          throw DataPreservationException(
            'User meal override difference at index $i: orig=${origOverrides[i]} vs scoped=${scopedOverrides[i]}',
          );
        }
      }
    }

    // --- STEP 5: Strict Meal Memory Audit ---
    final origMealMemory = prefs.getString('meal_memory_v1');
    final scopedMealMemory = prefs.getString(scopedKey('meal_memory_v1', userId));

    if (origMealMemory != null) {
      if (scopedMealMemory == null || origMealMemory != scopedMealMemory) {
        throw DataPreservationException('MealMemory v1 content mismatch after copy');
      }
      final list = jsonDecode(origMealMemory) as List<dynamic>;
      mealMemoryScanned = list.length;
    }

    // All audits passed perfectly!
    final report = MigrationAuditReport(
      userId: userId,
      historicalNutritionRecordsScanned: dayLogsScanned,
      historicalNutritionRecordsChanged: dayLogsChanged,
      historicalNutritionRecordsDeleted: dayLogsDeleted,
      historicalNutritionRecordsLost: dayLogsLost,
      workoutSessionsScanned: sessionsScanned,
      workoutSessionsChanged: sessionsChanged,
      workoutSessionsDeleted: sessionsDeleted,
      workoutSessionsLost: sessionsLost,
      overridesScanned: overridesScanned,
      overridesLost: overridesLost,
      mealMemoryScanned: mealMemoryScanned,
      mealMemoryLost: mealMemoryLost,
      isVerified: true,
      timestamp: DateTime.now(),
    );

    _lastAuditReport = report;
    await prefs.setBool(migrationMarkerKey, true);
    await prefs.setString('migration_audit_report_v1_$userId', jsonEncode(report.toJson()));

    debugPrint('[UserSessionCoordinator] 🏆 MIGRATION AUDIT PASSED 100%:');
    debugPrint('  - Historical nutrition records scanned: $dayLogsScanned, changed: 0, deleted: 0, lost: 0');
    debugPrint('  - Workout sessions scanned: $sessionsScanned, changed: 0, deleted: 0, lost: 0');
    debugPrint('  - Overrides scanned: $overridesScanned, lost: 0');
    debugPrint('  - Meal memory scanned: $mealMemoryScanned, lost: 0');
    debugPrint('  - Original unscoped storage keys KEPT INTACT as backup.');

    return report;
  }
}
