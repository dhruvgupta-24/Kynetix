import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/day_log.dart';
import '../models/workout_session.dart';
import '../models/workout_split.dart';
import '../services/workout_service.dart';
import '../services/user_nutrition_memory.dart';
import '../services/eating_pattern_service.dart';
import '../services/persistence_service.dart';
import '../services/meal_tombstones.dart';
import '../services/quick_add_service.dart';

import '../services/nutrition_hydration_guard.dart';
import '../models/insights_models.dart';
import '../services/insights_report_service.dart';
import '../services/user_session_coordinator.dart';
import '../services/internal/net_timeouts.dart';

// Logging in this file is debug-only: release builds skip the console I/O.
void _debugLog(String? message, {int? wrapWidth}) {
  if (kDebugMode) debugPrint(message, wrapWidth: wrapWidth);
}

/// The remote rows hydration merges, fetched in one round trip.
class CloudHydrationCore {
  const CloudHydrationCore({
    this.dayLogs = const [],
    this.workouts = const [],
    this.memory = const [],
    this.patterns = const [],
    this.contexts = const [],
    this.split,
  });
  final List<dynamic> dayLogs;
  final List<dynamic> workouts;
  final List<dynamic> memory;
  final List<dynamic> patterns;
  final List<dynamic> contexts;
  final Map<String, dynamic>? split;
}

/// Remote reads (and the split back-up) that hydration performs. The default
/// talks to Supabase; tests substitute a fake so the merge path runs offline.
class CloudHydrationSource {
  const CloudHydrationSource();

  SupabaseClient get _db => Supabase.instance.client;

  Future<CloudHydrationCore> fetchCore() async {
    final results = await Future.wait([
      _db.from('day_logs').select(),
      _db.from('workout_sessions').select(),
      _db.from('user_nutrition_memory').select(),
      _db.from('user_eating_patterns').select().order('recorded_at', ascending: true),
      _db.from('user_meal_contexts').select().order('recorded_at', ascending: true),
      _db.from('workout_splits').select().maybeSingle(),
    ]).within(NetTimeouts.sync, 'cloud hydration');
    return CloudHydrationCore(
      dayLogs: results[0] as List<dynamic>,
      workouts: results[1] as List<dynamic>,
      memory: results[2] as List<dynamic>,
      patterns: results[3] as List<dynamic>,
      contexts: results[4] as List<dynamic>,
      split: results[5] as Map<String, dynamic>?,
    );
  }

  Future<List<dynamic>> fetchAchievements() async =>
      await _db.from('user_achievements').select()
          .within(NetTimeouts.sync, 'achievements fetch');

  Future<Map<String, dynamic>?> fetchInsightsCache() =>
      _db.from('user_insights_cache').select().maybeSingle()
          .within(NetTimeouts.sync, 'insights cache fetch');

  /// Quick Add two-way sync; it re-checks [stillCurrent] after every await.
  Future<void> syncQuickAdds(String userId, bool Function() stillCurrent) =>
      QuickAddService.instance
          .syncWithCloud(expectedUserId: userId, stillCurrent: stillCurrent);

  Future<void> uploadSplit(WorkoutSplit split, List<Exercise> customExercises) =>
      CloudSyncService.instance.syncWorkoutSplitBackground(split, customExercises);

  /// Re-sends the cloud delete for sessions the user deleted on this device.
  Future<bool> deleteWorkouts(Set<String> ids, String userId) =>
      CloudSyncService.instance
          .deleteWorkoutSessions(ids, expectedUserId: userId);
}

class CloudSyncService {
  CloudSyncService._();
  static final CloudSyncService instance = CloudSyncService._();

  SupabaseClient get _supabase => Supabase.instance.client;

  /// True while [userId]'s session, as it was at [epoch], is still the loaded
  /// one. Every cloud merge re-checks this after each await: a sign-out or
  /// account switch in between must drop the remote data, never write it
  /// into the next account's store (or the device-wide legacy keys).
  static bool isSessionCurrent(String userId, int epoch) =>
      PersistenceService.sessionEpoch == epoch &&
      UserSessionCoordinator.instance.isReadyFor(userId);

  /// Hydrate local state from Supabase
  Future<void> hydrateFromCloud() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    await hydrateForUser(userId);
  }

  /// Hydrates [userId]'s local stores from [source]. Drops everything the
  /// moment [userId]'s session stops being the loaded one.
  @visibleForTesting
  Future<void> hydrateForUser(
    String userId, {
    CloudHydrationSource source = const CloudHydrationSource(),
  }) async {
    final epoch = PersistenceService.sessionEpoch;
    bool stillCurrent() => isSessionCurrent(userId, epoch);
    bool dropped(String step) {
      if (stillCurrent()) return false;
      _debugLog('[CloudSyncService] Session for $userId ended during hydration '
          '($step), dropping remote data');
      return true;
    }

    if (dropped('start')) return;

    NutritionHydrationGuard.instance.beginHydration(isBackgroundUpdate: true);
    _debugLog('[CloudSyncService] Starting cloud hydration for user: $userId');
    // Remote rows may now differ from what this session uploaded: forget the
    // upload fingerprints so the next sync re-uploads every day.
    _uploadedDayJson.clear();

    try {
      // Hydrate all components concurrently
      final core = await source.fetchCore();
      if (dropped('fetch')) return;

      // 1. Process Day Logs (the merge and the save's key capture both run
      //    synchronously right after the check above)
      for (final row in core.dayLogs) {
        final dateKey = row['date_key'] as String;
        dayLogStore[dateKey] = mergeCloudDayRow(
          dateKey,
          row as Map<String, dynamic>,
          dayLogStore[dateKey],
        );
      }
      // Re-save locally
      await PersistenceService.saveDayLogs();
      if (dropped('day logs')) return;
      PersistenceService.lastDayLogsHydratedAt = DateTime.now();
      _debugLog('[CloudSyncService] Day logs hydration complete at: ${PersistenceService.lastDayLogsHydratedAt}');

      // 2. Process Workouts
      // Only add sessions that are not already in local storage.
      // Historical sessions are immutable — never overwrite existing local entries.
      final importedSessions = <WorkoutSession>[];
      final stillDeleted = <String>{};
      for (final row in core.workouts) {
        final id = row['id'] as String;
        // Deleted on this device: never re-add it, and retry the cloud delete
        // that evidently did not land (e.g. it ran offline).
        if (WorkoutService.instance.isSessionDeleted(id)) {
          stillDeleted.add(id);
          continue;
        }
        // Avoid overwriting local history if it exists, or just accept cloud as truth
        final exists = WorkoutService.instance.sessions.any((s) => s.id == id);
        if (!exists) {
          // Sessions are write-once and immutable. We only add sessions that
          // are not already in local storage. WorkoutService owns ordering.
          final session = WorkoutSession(
            id: row['id'],
            date: DateTime.parse(row['date'] as String),
            splitDayName: row['split_day_name'] as String,
            splitDayWeekday: row['split_day_weekday'] as int?,
            wasManuallySelected: row['was_manually_selected'] as bool? ?? false,
            notes: row['notes'] as String?,
            durationMinutes: row['duration_minutes'] as int?,
            entries: (row['entries_json'] as List<dynamic>?)?.map((e) => ExerciseEntry.fromJson(e)).toList() ?? [],
          );
          importedSessions.add(session);
        }
      }
      if (importedSessions.isNotEmpty) {
        await WorkoutService.instance
            .bulkImportCloudSessions(importedSessions, stillCurrent: stillCurrent);
        if (dropped('workouts')) return;
      }
      if (stillDeleted.isNotEmpty) {
        source.deleteWorkouts(stillDeleted, userId).ignore();
      }
      WorkoutService.lastWorkoutsHydratedAt = DateTime.now();
      _debugLog('[CloudSyncService] Workout sessions hydration complete at: ${WorkoutService.lastWorkoutsHydratedAt}');

      // 3. Process Nutrition Memory
      final cloudOverrides = <UserMealOverride>[];
      for (final row in core.memory) {
        try {
          // Support both legacy (calories) and new (caloriesPerUnit) columns.
          // Supabase rows written by older clients only have 'calories'/'protein';
          // newer rows have 'calories_per_unit'/'protein_per_unit' etc.
          final calPerUnit = (row['calories_per_unit'] as num?)?.toDouble()
              ?? (row['calories'] as num?)?.toDouble()
              ?? 0.0;
          final proPerUnit = (row['protein_per_unit'] as num?)?.toDouble()
              ?? (row['protein'] as num?)?.toDouble()
              ?? 0.0;
          final carbPerUnit = (row['carbohydrates_per_unit'] as num?)?.toDouble();
          final fatPerUnit = (row['fat_per_unit'] as num?)?.toDouble();
          final fiberPerUnit = (row['fiber_per_unit'] as num?)?.toDouble();
          final updatedAtStr = row['updated_at'] as String?;
          final savedAt = updatedAtStr != null
              ? DateTime.tryParse(updatedAtStr) ?? DateTime.now()
              : DateTime.now();
          final correctionCount = row['times_used'] as int? ?? 1;
          cloudOverrides.add(UserMealOverride(
            canonicalMeal:     row['canonical_meal'] as String,
            caloriesPerUnit:   calPerUnit,
            proteinPerUnit:    proPerUnit,
            carbohydratesPerUnit: carbPerUnit,
            fatPerUnit:        fatPerUnit,
            fiberPerUnit:      fiberPerUnit,
            referenceQuantity: (row['reference_quantity'] as num?)?.toDouble() ?? 1.0,
            referenceUnit:     row['reference_unit'] as String? ?? 'serving',
            savedAt:           savedAt,
            correctionCount:   correctionCount,
          ));
        } catch (e) {
          _debugLog('[CloudSyncService] Failed to parse memory row: $e');
        }
      }
      if (cloudOverrides.isNotEmpty) {
        await UserNutritionMemory.instance.mergeFromCloud(
          cloudOverrides,
          expectedUserId: userId,
          stillCurrent: stillCurrent,
        );
        if (dropped('nutrition memory')) return;
      }

      // 4. Process Eating Patterns (correction records)
      if (core.patterns.isNotEmpty) {
        EatingPatternService.instance.mergeFromCloud(
          core.patterns.cast<Map<String, dynamic>>(),
        );
        await EatingPatternService.instance.save();
        if (dropped('eating patterns')) return;
      }

      // 5. Process Meal Contexts
      if (core.contexts.isNotEmpty) {
        EatingPatternService.instance.mergeContextsFromCloud(
          core.contexts.cast<Map<String, dynamic>>(),
        );
        await EatingPatternService.instance.save();
        if (dropped('meal contexts')) return;
      }

      // 6. Sync Quick Adds from Cloud
      await source.syncQuickAdds(userId, stillCurrent);
      if (dropped('quick adds')) return;

      // 7. Process Workout Split & Custom Exercises
      final splitResp = core.split;
      if (splitResp != null) {
        final splitJson = splitResp['split_json'];
        final customExercisesJson = splitResp['custom_exercises_json'] as List<dynamic>?;
        final cloudUpdatedAtStr = splitResp['updated_at'] as String?;
        final cloudUpdatedAt = cloudUpdatedAtStr != null
            ? DateTime.tryParse(cloudUpdatedAtStr)
            : null;

        final localUpdatedAt = WorkoutService.instance.splitUpdatedAt;

        List<Exercise> customExercises = [];
        if (customExercisesJson != null) {
          try {
            customExercises = customExercisesJson
                .map((e) => Exercise.fromJson(e as Map<String, dynamic>))
                .toList();
          } catch (e) {
            _debugLog('[CloudSyncService] Error parsing custom exercises from cloud: $e');
          }
        }

        final isLocalNewer = WorkoutService.instance.isSetupDone &&
            cloudUpdatedAt != null &&
            localUpdatedAt.isAfter(cloudUpdatedAt);

        if (isLocalNewer) {
          _debugLog('[CloudSyncService] Local workout split is newer than cloud. Backing up split to cloud...');
          await source.uploadSplit(
            WorkoutService.instance.split,
            WorkoutService.instance.customExercises,
          );
        } else if (splitJson != null) {
          try {
            final cloudSplit = WorkoutSplit.fromJson(splitJson as Map<String, dynamic>);
            await WorkoutService.instance.loadSplitAndCustomExercisesFromCloud(
              cloudSplit,
              customExercises,
              cloudUpdatedAt: cloudUpdatedAt,
              stillCurrent: stillCurrent,
            );
            _debugLog('[CloudSyncService] 🔄 Hydrated workout split and custom exercises from cloud');
          } catch (e) {
            _debugLog('[CloudSyncService] Error parsing cloud workout split: $e');
          }
        }
      } else if (WorkoutService.instance.isSetupDone) {
        _debugLog('[CloudSyncService] Cloud split empty but local setup done. Backing up split to cloud...');
        await source.uploadSplit(
          WorkoutService.instance.split,
          WorkoutService.instance.customExercises,
        );
      }
      if (dropped('workout split')) return;

      // 8. Restore achievements from cloud
      try {
        final cloudAchievements = await source.fetchAchievements();
        if (dropped('achievements')) return;
        final restored = cloudAchievements.map((row) {
          final earnedAtStr = row['earned_at'] as String;
          final id = row['id'] as String;
          return Achievement(
            id: id,
            title: '',
            description: '',
            emoji: '',
            category: AchievementCategory.consistency,
            earnedAt: DateTime.parse(earnedAtStr),
            isNew: false,
          );
        }).toList();
        await InsightsReportService.instance
            .mergeAchievementsFromCloud(restored, stillCurrent: stillCurrent);
        _debugLog('[CloudSyncService] 🔄 Restored ${restored.length} achievements from cloud');
      } catch (e) {
        _debugLog('[CloudSyncService] Error restoring achievements: $e');
      }
      if (dropped('achievements')) return;

      // 9. Restore insights cache from cloud
      try {
        final cacheResp = await source.fetchInsightsCache();
        if (dropped('insights cache')) return;
        if (cacheResp != null) {
          await InsightsReportService.instance
              .mergeCacheFromCloud(cacheResp, stillCurrent: stillCurrent);
          _debugLog('[CloudSyncService] 🔄 Restored insights cache from cloud');
        }
      } catch (e) {
        _debugLog('[CloudSyncService] Error restoring insights cache: $e');
      }
      if (dropped('insights cache')) return;

      // 10. Reconstruct carry-forward resolved dates and history from day logs
      try {
        final prefs = await SharedPreferences.getInstance();
        if (dropped('carry-forward')) return;
        final resolvedDates = <String>{};
        final history = <String>[];

        for (final entry in dayLogStore.entries) {
          final record = entry.value.gymDay?.carryForwardRecord;
          if (record != null) {
            resolvedDates.add(record.yesterdayDate);
            history.add(jsonEncode(record.toJson()));
          }
        }

        if (resolvedDates.isNotEmpty) {
          await prefs.setStringList(
              UserSessionCoordinator.carryForwardWriteKey(
                  UserSessionCoordinator.kCarryForwardResolved, userId), resolvedDates.toList());
          if (dropped('carry-forward')) return;
          await prefs.setStringList(UserSessionCoordinator.carryForwardWriteKey(
                  UserSessionCoordinator.kCarryForwardHistory, userId), history);
          _debugLog('[CloudSyncService] 🔄 Reconstructed ${resolvedDates.length} carry-forward rollover events from logs.');
        }
      } catch (e) {
        _debugLog('[CloudSyncService] Error reconstructing carry-forward from day logs: $e');
      }

      // Never open the gate (or re-point the cached owner) for a session
      // that is no longer the loaded one.
      if (dropped('finish')) return;
      _debugLog('[CloudSyncService] Hydration completed.');
      NutritionHydrationGuard.instance.markComplete(userId);
    } catch (e) {
      _debugLog('[CloudSyncService] Error during hydration: $e');
    }
  }

  /// Merges one cloud `day_logs` row into the local day ([local], or a new
  /// day), per meal entry ([MealEntry.id]):
  ///  * a cloud entry the local day lacks is added, unless a local pending
  ///    deletion ([MealTombstones]) suppresses it;
  ///  * when both hold the entry, the cloud copy replaces the local one only
  ///    if its `updatedAt` is strictly newer (local wins ties);
  ///  * a cloud tombstone (`deleted_meal_ids`) removes the local copy unless
  ///    that copy was changed after the deletion (e.g. restored by Undo).
  @visibleForTesting
  static DayLog mergeCloudDayRow(String dateKey, Map<String, dynamic> row, DayLog? local) {
    final gymDayJson = row['gym_day_json'];
    final sectionsJson = row['sections_json'];
    final tombstones = MealTombstones.instance;

    final log = local ?? DayLog();

    if (gymDayJson != null && log.gymDay == null) {
      log.gymDay = GymDay.fromJson(gymDayJson as Map<String, dynamic>);
    }
    if (sectionsJson is Map) {
      final localById = <String, MealEntry>{
        for (final e in log.allEntries) e.id: e,
      };
      for (final sectionName in sectionsJson.keys) {
        final sectionEnum = MealSection.values.firstWhere((e) => e.name == sectionName, orElse: () => MealSection.breakfast);
        final entries = sectionsJson[sectionName];
        if (entries is! List) continue;
        for (final raw in entries) {
          if (raw is! Map<String, dynamic>) continue;
          final cloudEntry = MealEntry.fromJson(raw);
          // Pre-id deletion recorded here: now that its id is known, make it
          // uploadable as a server tombstone.
          tombstones.upgradeLegacy(dateKey, cloudEntry);
          // Deleted / edited away on this device, not yet uploaded.
          if (tombstones.suppresses(dateKey, cloudEntry)) continue;
          final mine = localById[cloudEntry.id];
          if (mine == null) {
            log.add(sectionEnum, cloudEntry);
            localById[cloudEntry.id] = cloudEntry;
          } else if (cloudEntry.isNewerThan(mine)) {
            log.replace(mine.section, mine, cloudEntry);
            localById[cloudEntry.id] = cloudEntry;
          }
        }
      }
    }
    final cloudDeleted = row['deleted_meal_ids'];
    if (cloudDeleted is Map && cloudDeleted.isNotEmpty) {
      for (final s in MealSection.values) {
        for (final e in log.entriesFor(s)) {
          final at = cloudDeleted[e.id];
          final deletedAt = at is String ? DateTime.tryParse(at) : null;
          if (deletedAt == null) continue;
          final updated = e.updatedAt;
          if (updated == null || !updated.isAfter(deletedAt)) {
            log.remove(s, e);
          }
        }
      }
    }
    // Load frozen target values from Supabase to prevent drift on hydration
    if (row['target_calories'] != null && log.targetCalories == null) {
      log.targetCalories = (row['target_calories'] as num?)?.toDouble();
    }
    if (row['target_protein'] != null && log.targetProtein == null) {
      log.targetProtein = (row['target_protein'] as num?)?.toDouble();
    }
    return log;
  }

  /// Parameters of the `merge_day_log` RPC for one day: the day's entries,
  /// its pending deletions ([deletions], `{id: deletedAt}`), and the day
  /// fields. The server merges per entry (newest `updatedAt` wins, tombstones
  /// persist and beat older copies), so a stale device can neither resurrect
  /// a meal deleted elsewhere nor drop meals it has not seen.
  @visibleForTesting
  static Map<String, dynamic> dayMergeParams(
    String dateKey,
    DayLog log,
    Map<String, String> deletions,
  ) => {
        'p_date_key': dateKey,
        'p_sections': {
          for (final s in MealSection.values)
            s.name: log.entriesFor(s).map((e) => e.toJson()).toList(),
        },
        'p_deleted': deletions,
        'p_gym_day_json': log.gymDay?.toJson(),
        'p_target_calories': log.targetCalories,
        'p_target_protein': log.targetProtein,
      };

  // ── Day-log upload ──────────────────────────────────────────────────────
  //
  // Each day is merge-uploaded through `merge_day_log` (see
  // [dayMergeParams]); the stored row keeps the same format. To avoid
  // re-uploading the whole history on every save, a day is skipped only when
  // its persisted JSON (from PersistenceService's last write) is identical to
  // the JSON it had when this session last uploaded it successfully. Anything
  // unknown, changed, or previously failed is uploaded. Runs are serialized
  // and coalesced: a request during a run triggers exactly one more run.

  final Map<String, String> _uploadedDayJson = {};
  String? _uploadedDayJsonOwner;
  Future<void>? _dayLogSyncRun;
  bool _dayLogSyncAgain = false;

  /// Fire-and-forget sync for day logs
  Future<void> syncDayLogsBackground() {
    final running = _dayLogSyncRun;
    if (running != null) {
      _dayLogSyncAgain = true;
      return running;
    }
    final run = _runDayLogSyncLoop();
    _dayLogSyncRun = run;
    return run;
  }

  Future<void> _runDayLogSyncLoop() async {
    try {
      do {
        _dayLogSyncAgain = false;
        await _syncChangedDayLogsOnce();
      } while (_dayLogSyncAgain);
    } finally {
      _dayLogSyncRun = null;
    }
  }

  Future<void> _syncChangedDayLogsOnce() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    // The in-memory store belongs to the session user; never upload it under
    // a different auth identity.
    final sessionUser = UserSessionCoordinator.instance.currentUserId;
    if (sessionUser != null && sessionUser != userId) return;

    if (_uploadedDayJsonOwner != userId) {
      _uploadedDayJson.clear();
      _uploadedDayJsonOwner = userId;
    }
    final written = PersistenceService.lastWrittenDayJsonFor(userId);
    final snapshot = Map<String, DayLog>.of(dayLogStore);

    try {
      final futures = <Future>[];
      for (final entry in snapshot.entries) {
        final dateKey = entry.key;
        final log = entry.value;
        final fingerprint = written?[dateKey];
        if (fingerprint != null && _uploadedDayJson[dateKey] == fingerprint) {
          continue; // Unchanged since this session's last successful upload.
        }
        // Deletions this upload carries to the cloud; ones recorded while it
        // is in flight are not in it and must survive.
        final tombstoneSnapshot = MealTombstones.instance.snapshotFor(dateKey);

        futures.add(
          _supabase
              .rpc('merge_day_log', params: dayMergeParams(
                dateKey,
                log,
                MealTombstones.instance.deletionsFor(dateKey),
              ))
              .within(NetTimeouts.sync, 'day log upload')
              .then((value) {
            if (fingerprint != null && _uploadedDayJsonOwner == userId) {
              _uploadedDayJson[dateKey] = fingerprint;
            }
            MealTombstones.instance.clearUploaded(dateKey, tombstoneSnapshot, userId: userId);
            return value;
          }).catchError((e) {
            _debugLog('[CloudSyncService] Failed to sync day log $dateKey: $e');
            return {};
          })
        );
      }
      await Future.wait(futures);
    } catch (e) {
      _debugLog('[CloudSyncService] Background day log sync failed: $e');
    }
  }

  /// Fire-and-forget sync for a single completed workout
  Future<void> syncWorkoutBackground(WorkoutSession session) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await _supabase.from('workout_sessions').upsert({
        'id': session.id,
        'user_id': userId,
        'date': session.date.toIso8601String(),
        'split_day_name': session.splitDayName,
        'split_day_weekday': session.splitDayWeekday,
        'was_manually_selected': session.wasManuallySelected,
        'entries_json': session.entries.map((e) => e.toJson()).toList(),
        'notes': session.notes,
        'duration_minutes': session.durationMinutes,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'id').within(NetTimeouts.sync, 'workout upload');
    } catch (e) {
      _debugLog('[CloudSyncService] Background workout sync failed: $e');
    }
  }

  /// Deletes the signed-in user's own `workout_sessions` rows [ids] (RLS
  /// limits deletes to the owner; the user_id filter keeps it that way).
  /// Returns true only when the delete went through. Never throws.
  Future<bool> deleteWorkoutSessions(Set<String> ids,
      {required String expectedUserId}) async {
    if (ids.isEmpty) return true;
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null || userId != expectedUserId) return false;
      await _supabase
          .from('workout_sessions')
          .delete()
          .eq('user_id', userId)
          .inFilter('id', ids.toList())
          .within(NetTimeouts.sync, 'workout delete');
      return true;
    } catch (e) {
      _debugLog('[CloudSyncService] Workout delete failed: $e');
      return false;
    }
  }

  /// Fire-and-forget sync for the workout split and custom exercises
  Future<void> syncWorkoutSplitBackground(WorkoutSplit split, List<Exercise> customExercises) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await _supabase.from('workout_splits').upsert({
        'user_id': userId,
        'split_json': split.toJson(),
        'custom_exercises_json': customExercises.map((e) => e.toJson()).toList(),
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id').within(NetTimeouts.sync, 'split upload');
      _debugLog('[CloudSyncService] 🔄 Workout split and custom exercises synced successfully.');
    } catch (e) {
      _debugLog('[CloudSyncService] Background workout split sync failed: $e');
    }
  }

  /// Fire-and-forget sync for a nutrition memory override.
  /// Writes both new-schema columns (calories_per_unit etc.) and legacy
  /// aliases (calories, protein) so the Supabase row is readable by any
  /// client version.
  Future<void> syncMemoryBackground(UserMealOverride memory) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await _supabase.from('user_nutrition_memory').upsert({
        'user_id':           userId,
        'canonical_meal':    memory.canonicalMeal,
        // New schema columns
        'calories_per_unit': memory.caloriesPerUnit,
        'protein_per_unit':  memory.proteinPerUnit,
        if (memory.carbohydratesPerUnit != null) 'carbohydrates_per_unit': memory.carbohydratesPerUnit,
        if (memory.fatPerUnit != null) 'fat_per_unit': memory.fatPerUnit,
        if (memory.fiberPerUnit != null) 'fiber_per_unit': memory.fiberPerUnit,
        'reference_quantity':memory.referenceQuantity,
        'reference_unit':    memory.referenceUnit,
        // Legacy aliases for backward compat with existing rows/clients
        'calories':          memory.caloriesPerUnit,
        'protein':           memory.proteinPerUnit,
        'updated_at':        memory.savedAt.toUtc().toIso8601String(),
        'times_used':        memory.correctionCount,
      }, onConflict: 'user_id, canonical_meal')
          .within(NetTimeouts.sync, 'memory upload');
    } catch (e) {
      _debugLog('[CloudSyncService] Background memory sync failed: $e');
    }
  }

  /// Deletes the signed-in user's own `user_nutrition_memory` rows for
  /// [canonicalMeals] (RLS limits the delete to the caller's rows; the
  /// explicit user_id filter keeps it that way regardless). Returns true only
  /// when the delete went through, so the caller can drop its tombstones.
  /// Only [expectedUserId]'s rows are ever touched.
  Future<bool> deleteMemoryRows(Set<String> canonicalMeals, {required String expectedUserId}) async {
    if (canonicalMeals.isEmpty) return true;
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null || userId != expectedUserId) return false;
      await _supabase
          .from('user_nutrition_memory')
          .delete()
          .eq('user_id', userId)
          .inFilter('canonical_meal', canonicalMeals.toList())
          .within(NetTimeouts.sync, 'memory delete');
      return true;
    } catch (e) {
      _debugLog('[CloudSyncService] Background memory delete failed: $e');
      return false;
    }
  }

  /// Fire-and-forget sync for new eating pattern correction records.
  /// Uploads all locally stored records to the cloud (upsert by content).
  Future<void> syncEatingPatternsBackground() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final records = EatingPatternService.instance.exportForCloudSync();
      if (records.isEmpty) return;

      // Insert in batches of 50 to avoid request size limits
      const batchSize = 50;
      for (int i = 0; i < records.length; i += batchSize) {
        final batch = records.sublist(i, (i + batchSize).clamp(0, records.length));
        final rows = batch.map((r) => {
          'user_id': userId,
          ...r,
        }).toList();
        // Use insert (not upsert) — duplicate check is done client-side during merge
        await _supabase.from('user_eating_patterns').upsert(
          rows,
          onConflict: 'user_id,recorded_at,target_role',
          ignoreDuplicates: true,
        ).within(NetTimeouts.sync, 'eating pattern upload');
      }
      _debugLog('[CloudSyncService] 🔄 Eating patterns synced (${records.length} records)');
    } catch (e) {
      _debugLog('[CloudSyncService] Eating pattern sync failed: $e');
    }
  }

  /// Fire-and-forget sync for new meal context records.
  Future<void> syncMealContextsBackground() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final contexts = EatingPatternService.instance.exportContextsForCloudSync();
      if (contexts.isEmpty) return;

      const batchSize = 50;
      for (int i = 0; i < contexts.length; i += batchSize) {
        final batch = contexts.sublist(i, (i + batchSize).clamp(0, contexts.length));
        final rows = batch.map((r) => {
          'user_id': userId,
          ...r,
        }).toList();
        await _supabase.from('user_meal_contexts').upsert(
          rows,
          onConflict: 'user_id,recorded_at',
          ignoreDuplicates: true,
        ).within(NetTimeouts.sync, 'meal context upload');
      }
      _debugLog('[CloudSyncService] 🔄 Meal contexts synced (${contexts.length} records)');
    } catch (e) {
      _debugLog('[CloudSyncService] Meal context sync failed: $e');
    }
  }

  /// Fire-and-forget sync for insights cache
  Future<void> syncInsightsCacheBackground() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final service = InsightsReportService.instance;
      await _supabase.from('user_insights_cache').upsert({
        'user_id': userId,
        'weekly_json': service.weeklyCache.map((k, v) => MapEntry(k, v.toJson())),
        'monthly_json': service.monthlyCache.map((k, v) => MapEntry(k, v.toJson())),
        'yearly_json': service.yearlyCache.map((k, v) => MapEntry(k, v.toJson())),
        'personal_bests_json': service.personalBests?.toJson(),
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id').within(NetTimeouts.sync, 'insights upload');
      _debugLog('[CloudSyncService] 🔄 Insights cache synced to cloud successfully.');
    } catch (e) {
      _debugLog('[CloudSyncService] Background insights cache sync failed: $e');
    }
  }

  /// Fire-and-forget sync for new achievements
  Future<void> syncAchievementsBackground() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final newOnes = InsightsReportService.instance.achievements
          .where((a) => a.earnedAt.isAfter(DateTime.now().subtract(const Duration(minutes: 5))))
          .toList();
      for (final a in newOnes) {
        await _supabase.from('user_achievements').upsert({
          'user_id': userId,
          'id': a.id,
          'earned_at': a.earnedAt.toIso8601String(),
        }, onConflict: 'user_id, id').within(NetTimeouts.sync, 'achievement upload');
      }
      if (newOnes.isNotEmpty) {
        _debugLog('[CloudSyncService] 🔄 Synced ${newOnes.length} new achievements to cloud.');
      }
    } catch (e) {
      _debugLog('[CloudSyncService] Background achievements sync failed: $e');
    }
  }
}
