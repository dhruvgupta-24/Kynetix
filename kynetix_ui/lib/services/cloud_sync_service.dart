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
import '../services/error_reporter.dart';
import '../services/food_role_classifier.dart' show FoodRole;

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

  /// Every row of [table] (RLS limits it to the caller's own), read page by
  /// page in a stable order: [orderBy] ascending, then `id` as tie-break.
  Future<List<dynamic>> _all(String table, String orderBy) =>
      CloudSyncService.fetchAllPages(
        (from, to) => _db
            .from(table)
            .select()
            .order(orderBy, ascending: true)
            .order('id', ascending: true)
            .range(from, to),
        what: table,
      );

  Future<CloudHydrationCore> fetchCore() async {
    // Paged (PostgREST returns at most 1000 rows per request), each page
    // with its own timeout, so a long-lived account is neither truncated
    // nor cut off by one limit over the whole batch.
    final results = await Future.wait([
      _all('day_logs', 'date_key'),
      _all('workout_sessions', 'date'),
      _all('user_nutrition_memory', 'canonical_meal'),
      _all('user_eating_patterns', 'recorded_at'),
      _all('user_meal_contexts', 'recorded_at'),
      _db.from('workout_splits').select().maybeSingle()
          .within(NetTimeouts.sync, 'split fetch'),
    ]);
    return CloudHydrationCore(
      dayLogs: results[0] as List<dynamic>,
      workouts: results[1] as List<dynamic>,
      memory: results[2] as List<dynamic>,
      patterns: results[3] as List<dynamic>,
      contexts: results[4] as List<dynamic>,
      split: results[5] as Map<String, dynamic>?,
    );
  }

  Future<List<dynamic>> fetchAchievements() => _all('user_achievements', 'id');

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

/// Remote writes the background sync performs (uploads, deletes, the signed
/// in user). The default talks to Supabase; tests substitute a fake so the
/// retry paths run offline. Every call throws on failure.
class CloudSyncRemote {
  const CloudSyncRemote();

  SupabaseClient get _db => Supabase.instance.client;

  String? get currentUserId => _db.auth.currentUser?.id;

  Future<void> upsertWorkouts(List<Map<String, dynamic>> rows) => _db
      .from('workout_sessions')
      .upsert(rows, onConflict: 'user_id,id')
      .within(NetTimeouts.sync, 'workout upload');

  Future<void> deleteWorkouts(String userId, List<String> ids) => _db
      .from('workout_sessions')
      .delete()
      .eq('user_id', userId)
      .inFilter('id', ids)
      .within(NetTimeouts.sync, 'workout delete');

  Future<void> mergeDayLog(Map<String, dynamic> params) => _db
      .rpc('merge_day_log', params: params)
      .within(NetTimeouts.sync, 'day log upload');

  /// Deletes [userId]'s correction rows recorded at or before [before]: all
  /// of them when [targetRole] is null, else one pattern (a null
  /// [contextRole] meaning "eaten alone").
  Future<void> deleteEatingPatterns(
    String userId, {
    required DateTime before,
    String? targetRole,
    String? contextRole,
  }) {
    var q = _db
        .from('user_eating_patterns')
        .delete()
        .eq('user_id', userId)
        .lte('recorded_at', before.toUtc().toIso8601String());
    if (targetRole != null) {
      q = q.eq('target_role', targetRole);
      q = contextRole == null
          ? q.isFilter('context_role', null)
          : q.eq('context_role', contextRole);
    }
    return q.within(NetTimeouts.sync, 'eating pattern delete');
  }

  /// Deletes [userId]'s meal-context rows recorded at or before [before].
  Future<void> deleteMealContexts(String userId, {required DateTime before}) =>
      _db
          .from('user_meal_contexts')
          .delete()
          .eq('user_id', userId)
          .lte('recorded_at', before.toUtc().toIso8601String())
          .within(NetTimeouts.sync, 'meal context delete');
}

class CloudSyncService {
  CloudSyncService._();
  static final CloudSyncService instance = CloudSyncService._();

  SupabaseClient get _supabase => Supabase.instance.client;

  /// Where uploads and deletes go. Tests replace it with a fake.
  @visibleForTesting
  CloudSyncRemote remote = const CloudSyncRemote();

  /// Rows PostgREST returns per request at most (its default `max-rows`).
  static const pageSize = 1000;

  /// Hard stop for [fetchAllPages] (a million rows), so a misbehaving
  /// server can never keep it looping.
  static const _maxPages = 1000;

  /// Reads every row of a query, [size] rows per request, until a short
  /// page. [page] fetches rows [from]..[to] (inclusive) of a stable order, so
  /// pages neither skip nor repeat rows. Each page gets its own [perPage]
  /// timeout: a large account is slow, not cut off.
  @visibleForTesting
  static Future<List<dynamic>> fetchAllPages(
    Future<List<dynamic>> Function(int from, int to) page, {
    required String what,
    int size = pageSize,
    Duration perPage = NetTimeouts.sync,
  }) async {
    final rows = <dynamic>[];
    for (var i = 0; i < _maxPages; i++) {
      final from = i * size;
      final batch =
          await page(from, from + size - 1).within(perPage, '$what page $i');
      rows.addAll(batch);
      if (batch.length < size) return rows;
    }
    _debugLog('[CloudSyncService] $what: stopped after $_maxPages pages');
    return rows;
  }

  /// Reports a cloud row hydration had to skip (it could not be read), with
  /// no row content, so one bad row is visible without blocking the rest.
  static void _reportBadRow(String table, Object error, StackTrace stack) {
    _debugLog('[CloudSyncService] Skipped unreadable $table row: $error');
    ErrorReporter.instance.report(
        StateError('Skipped unreadable $table row (${error.runtimeType})'),
        stack,
        type: 'cloud_hydration');
  }

  /// A `timestamptz` that older builds uploaded as a local wall-clock time
  /// without offset (so the server stored it as UTC) comes back with its
  /// wall-clock fields intact: read it as that local time again.
  static DateTime _wallClock(DateTime parsed) => parsed.isUtc
      ? DateTime(parsed.year, parsed.month, parsed.day, parsed.hour,
          parsed.minute, parsed.second, parsed.millisecond, parsed.microsecond)
      : parsed;

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

    try {
      // Hydrate all components concurrently
      final core = await source.fetchCore();
      if (dropped('fetch')) return;

      // 1. Process Day Logs (the merge and the save's key capture both run
      //    synchronously right after the check above). One unreadable row is
      //    skipped and reported; it never costs the rest.
      final matchingCloud = <String, String>{};
      for (final raw in core.dayLogs) {
        try {
          final row = raw as Map<String, dynamic>;
          final dateKey = row['date_key'] as String;
          final merged = mergeCloudDayRow(dateKey, row, dayLogStore[dateKey]);
          dayLogStore[dateKey] = merged;
          // Nothing local to add to the cloud copy: the day needs no upload.
          final mergedJson = jsonEncode(merged.toJson());
          if (MealTombstones.instance.deletionsFor(dateKey).isEmpty &&
              jsonEncode(mergeCloudDayRow(dateKey, row, null).toJson()) ==
                  mergedJson) {
            matchingCloud[dateKey] = mergedJson;
          }
        } catch (e, st) {
          _reportBadRow('day_logs', e, st);
        }
      }
      // Re-save locally
      await PersistenceService.saveDayLogs();
      if (dropped('day logs')) return;
      await PersistenceService.markDaysInSyncWithCloud(userId, matchingCloud);
      if (dropped('day logs')) return;
      PersistenceService.lastDayLogsHydratedAt = DateTime.now();
      _debugLog('[CloudSyncService] Day logs hydration complete at: ${PersistenceService.lastDayLogsHydratedAt}');

      // 2. Process Workouts
      // Only add sessions that are not already in local storage.
      // Historical sessions are immutable — never overwrite existing local entries.
      final importedSessions = <WorkoutSession>[];
      final stillDeleted = <String>{};
      final localIds = {for (final s in WorkoutService.instance.sessions) s.id};
      for (final row in core.workouts) {
        try {
          final id = row['id'] as String;
          // Deleted on this device: never re-add it, and retry the cloud
          // delete that evidently did not land (e.g. it ran offline).
          if (WorkoutService.instance.isSessionDeleted(id)) {
            stillDeleted.add(id);
            continue;
          }
          // A session already stored here is kept as is. Taking a newer cloud
          // copy (edited on another device) would need a per-session
          // updated_at on WorkoutSession; it has none, and the row's
          // updated_at is only the upload time, so it cannot say which copy
          // is newer.
          if (localIds.contains(id)) continue;
          // WorkoutService owns ordering (it sorts by date on import).
          importedSessions.add(WorkoutSession(
            id: id,
            // Stored as a local wall-clock time (see [workoutRow]).
            date: _wallClock(DateTime.parse(row['date'] as String)),
            splitDayName: row['split_day_name'] as String,
            splitDayWeekday: row['split_day_weekday'] as int?,
            wasManuallySelected: row['was_manually_selected'] as bool? ?? false,
            notes: row['notes'] as String?,
            durationMinutes: row['duration_minutes'] as int?,
            entries: (row['entries_json'] as List<dynamic>?)?.map((e) => ExerciseEntry.fromJson(e)).toList() ?? [],
          ));
        } catch (e, st) {
          _reportBadRow('workout_sessions', e, st);
        }
      }
      if (importedSessions.isNotEmpty) {
        await WorkoutService.instance
            .bulkImportCloudSessions(importedSessions, stillCurrent: stillCurrent);
        if (dropped('workouts')) return;
      }
      if (stillDeleted.isNotEmpty) {
        // Still in the cloud, so not confirmed deleted (whatever an earlier
        // run believed): kept until a delete is confirmed.
        await WorkoutService.instance.markCloudDeletesPending(stillDeleted);
        if (dropped('workouts')) return;
        source.deleteWorkouts(stillDeleted, userId).then((ok) {
          if (ok) {
            WorkoutService.instance
                .confirmCloudDeletes(stillDeleted, userId: userId)
                .ignore();
          }
        }).ignore();
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

        // Compared as instants in UTC (the split's updated_at is uploaded in
        // UTC, see [syncWorkoutSplitBackground]).
        final isLocalNewer = WorkoutService.instance.isSetupDone &&
            cloudUpdatedAt != null &&
            localUpdatedAt.toUtc().isAfter(cloudUpdatedAt.toUtc());

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
        final restored = <Achievement>[];
        for (final row in cloudAchievements) {
          try {
            restored.add(Achievement(
              id: row['id'] as String,
              title: '',
              description: '',
              emoji: '',
              category: AchievementCategory.consistency,
              earnedAt: DateTime.parse(row['earned_at'] as String),
              isNew: false,
            ));
          } catch (e, st) {
            _reportBadRow('user_achievements', e, st);
          }
        }
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
      // Local changes the cloud still lacks (a failed upload, an offline
      // delete) go up now.
      drainPendingUploads();
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
  // [dayMergeParams]); the stored row keeps the same format. Only the days
  // PersistenceService has recorded as changed and not yet confirmed
  // uploaded (its persisted dirty set, which survives restarts) go up, plus
  // days carrying pending meal deletions. A day leaves the set only after
  // its upload succeeded and only if it did not change in the meantime.
  // At most [_dayUploadConcurrency] uploads run at once. Runs are serialized
  // and coalesced: a request during a run triggers exactly one more run.

  static const _dayUploadConcurrency = 4;

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

  /// True while [userId] is both the signed-in user and the owner of the
  /// in-memory stores (a sign-out or switch stops any upload loop).
  bool _ownsLocalData(String userId) {
    if (remote.currentUserId != userId) return false;
    final sessionUser = UserSessionCoordinator.instance.currentUserId;
    return sessionUser == null || sessionUser == userId;
  }

  Future<void> _syncChangedDayLogsOnce() async {
    final userId = remote.currentUserId;
    if (userId == null || !_ownsLocalData(userId)) return;

    // Newest days first: they are the ones the user is looking at.
    final queue = PersistenceService.daysNeedingUpload(userId).toList()
      ..sort((a, b) => b.compareTo(a));
    if (queue.isEmpty) return;
    var next = 0;
    var uploaded = 0;

    Future<void> worker() async {
      while (next < queue.length) {
        if (!_ownsLocalData(userId)) return;
        final dateKey = queue[next++];
        final log = dayLogStore[dateKey];
        if (log == null) continue;
        // What this upload carries, taken before it is sent: a change or a
        // deletion recorded while it is in flight is not in it and must
        // survive.
        final sentJson = jsonEncode(log.toJson());
        final params = dayMergeParams(
            dateKey, log, MealTombstones.instance.deletionsFor(dateKey));
        final tombstoneSnapshot = MealTombstones.instance.snapshotFor(dateKey);
        try {
          await remote.mergeDayLog(params);
        } catch (e) {
          _debugLog('[CloudSyncService] Failed to sync day log $dateKey: $e');
          continue; // stays dirty: retried on the next run
        }
        PersistenceService.markDayUploaded(userId, dateKey, sentJson);
        MealTombstones.instance
            .clearUploaded(dateKey, tombstoneSnapshot, userId: userId);
        uploaded++;
      }
    }

    try {
      await Future.wait([
        for (var i = 0; i < _dayUploadConcurrency; i++) worker(),
      ]);
    } catch (e) {
      _debugLog('[CloudSyncService] Background day log sync failed: $e');
    }
    if (uploaded > 0) await PersistenceService.persistDirtyDays(userId);
  }

  // ── Workout upload / delete ─────────────────────────────────────────────
  //
  // WorkoutService keeps, per user and on disk, the sessions saved here but
  // not yet confirmed uploaded and the deletions not yet confirmed in the
  // cloud. Each id leaves its set only after the cloud call succeeded, so a
  // workout finished offline (or whose upload failed) is retried on the
  // next drain: app start (after hydration), resume, and every save.

  /// Sessions per upsert request.
  static const _workoutUploadBatch = 25;

  /// Ids per delete request (they travel in the URL).
  static const _workoutDeleteBatch = 100;

  Future<void>? _workoutSyncRun;
  bool _workoutSyncAgain = false;

  /// One `workout_sessions` row. `date` stays the session's local
  /// wall-clock time without offset, as every build has stored it (the
  /// reader relies on its fields, see [hydrateForUser]); `updated_at` is a
  /// real instant, in UTC.
  @visibleForTesting
  static Map<String, dynamic> workoutRow(WorkoutSession session, String userId,
          {DateTime? now}) =>
      {
        'id': session.id,
        'user_id': userId,
        'date': session.date.toIso8601String(),
        'split_day_name': session.splitDayName,
        'split_day_weekday': session.splitDayWeekday,
        'was_manually_selected': session.wasManuallySelected,
        'entries_json': session.entries.map((e) => e.toJson()).toList(),
        'notes': session.notes,
        'duration_minutes': session.durationMinutes,
        'updated_at': (now ?? DateTime.now()).toUtc().toIso8601String(),
      };

  /// Uploads a just-saved workout. [WorkoutService.saveSession] has already
  /// queued it, so this drains the queue: on failure it stays queued.
  Future<void> syncWorkoutBackground(WorkoutSession session) =>
      syncPendingWorkouts();

  /// Sends every pending workout upload and delete (see above). Coalesced
  /// like the day-log sync. Never throws.
  Future<void> syncPendingWorkouts() {
    final running = _workoutSyncRun;
    if (running != null) {
      _workoutSyncAgain = true;
      return running;
    }
    final run = _runWorkoutSyncLoop();
    _workoutSyncRun = run;
    return run;
  }

  Future<void> _runWorkoutSyncLoop() async {
    try {
      do {
        _workoutSyncAgain = false;
        await _syncPendingWorkoutsOnce();
      } while (_workoutSyncAgain);
    } catch (e) {
      _debugLog('[CloudSyncService] Workout sync failed: $e');
    } finally {
      _workoutSyncRun = null;
    }
  }

  Future<void> _syncPendingWorkoutsOnce() async {
    final userId = remote.currentUserId;
    final ws = WorkoutService.instance;
    if (userId == null || ws.currentUserId != userId) return;

    // Deletes first, so a deleted session is never uploaded again.
    final deletes = ws.unconfirmedDeleteIds.toList();
    for (var i = 0; i < deletes.length; i += _workoutDeleteBatch) {
      final chunk = deletes
          .sublist(i, (i + _workoutDeleteBatch).clamp(0, deletes.length))
          .toSet();
      if (!await deleteWorkoutSessions(chunk, expectedUserId: userId)) break;
      await ws.confirmCloudDeletes(chunk, userId: userId);
    }

    final pending = ws.pendingUploadSessions();
    for (var i = 0; i < pending.length; i += _workoutUploadBatch) {
      if (ws.currentUserId != userId || remote.currentUserId != userId) return;
      final chunk = pending.sublist(
          i, (i + _workoutUploadBatch).clamp(0, pending.length));
      try {
        await remote.upsertWorkouts([for (final s in chunk) workoutRow(s, userId)]);
      } catch (e) {
        _debugLog('[CloudSyncService] Workout upload failed (kept queued): $e');
        return;
      }
      await ws.markSessionsSynced(chunk, userId: userId);
    }
  }

  /// Retries everything the cloud is still missing from this device: workout
  /// uploads and deletes, changed days, pending pattern resets. Called after
  /// hydration and when the app comes back to the foreground. Never throws.
  void drainPendingUploads() {
    syncPendingWorkouts().ignore();
    syncDayLogsBackground().catchError((_) {}).ignore();
    syncPendingPatternResets().ignore();
  }

  /// Deletes the signed-in user's own `workout_sessions` rows [ids] (RLS
  /// limits deletes to the owner; the user_id filter keeps it that way).
  /// Returns true only when the delete went through. Never throws.
  Future<bool> deleteWorkoutSessions(Set<String> ids,
      {required String expectedUserId}) async {
    if (ids.isEmpty) return true;
    try {
      final userId = remote.currentUserId;
      if (userId == null || userId != expectedUserId) return false;
      await remote.deleteWorkouts(userId, ids.toList());
      return true;
    } catch (e) {
      _debugLog('[CloudSyncService] Workout delete failed: $e');
      return false;
    }
  }

  // ── Eating-pattern resets ───────────────────────────────────────────────
  //
  // "Reset pattern" / "Clear all" on the Nutrition Intelligence screen. The
  // local clear sticks on its own (EatingPatternService keeps a reset marker
  // that filters older cloud rows, even offline); deleting the cloud rows
  // as well keeps other devices from learning them back. A reset whose
  // cloud delete failed is retried on the next drain.

  Future<void>? _patternResetRun;

  /// Sends every reset not yet confirmed in the cloud. Never throws.
  Future<void> syncPendingPatternResets() {
    final running = _patternResetRun;
    if (running != null) return running;
    final run = _sendPatternResets();
    _patternResetRun = run;
    return run;
  }

  Future<void> _sendPatternResets() async {
    try {
      // Awaited first, so the finally below never runs before the caller
      // has stored this run.
      await _sendPatternResetsOnce();
    } catch (e) {
      _debugLog('[CloudSyncService] Pattern reset sync failed: $e');
    } finally {
      _patternResetRun = null;
    }
  }

  Future<void> _sendPatternResetsOnce() async {
    final userId = remote.currentUserId;
    final eps = EatingPatternService.instance;
    if (userId == null || eps.currentUserId != userId) return;
    for (final reset in eps.pendingCloudResets) {
      if (!await deletePatternRowsFor(reset, expectedUserId: userId)) return;
      await eps.confirmCloudReset(reset, userId: userId);
    }
  }

  /// Deletes the cloud rows [reset] covers. True only when it went through.
  @visibleForTesting
  Future<bool> deletePatternRowsFor(PatternReset reset,
      {required String expectedUserId}) async {
    try {
      final userId = remote.currentUserId;
      if (userId == null || userId != expectedUserId) return false;
      final role = reset.targetRole;
      if (role == null) {
        await remote.deleteEatingPatterns(userId, before: reset.at);
        await remote.deleteMealContexts(userId, before: reset.at);
      } else {
        await remote.deleteEatingPatterns(
          userId,
          before: reset.at,
          targetRole: role.name,
          contextRole: reset.contextRole?.name,
        );
      }
      return true;
    } catch (e) {
      _debugLog('[CloudSyncService] Pattern delete failed: $e');
      return false;
    }
  }

  /// Forgets one learned pattern here and in the cloud. The local clear is
  /// saved before this returns; the cloud delete is retried until it lands.
  Future<void> resetEatingPattern(FoodRole targetRole,
      {FoodRole? contextRole}) async {
    await EatingPatternService.instance
        .forgetPattern(targetRole, contextRole: contextRole);
    syncPendingPatternResets().ignore();
  }

  /// Forgets every learned pattern and meal context, here and in the cloud.
  Future<void> resetAllEatingPatterns() async {
    await EatingPatternService.instance.forgetAll();
    syncPendingPatternResets().ignore();
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
        'updated_at': DateTime.now().toUtc().toIso8601String(),
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
        'updated_at': DateTime.now().toUtc().toIso8601String(),
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
          // Local wall-clock time without offset, as every build has sent it:
          // hydration reads its fields back as is (DateTime.parse), so sending
          // UTC here would shift every achievement already stored.
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
