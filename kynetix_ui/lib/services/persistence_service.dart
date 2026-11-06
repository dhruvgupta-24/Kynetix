import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding, WidgetsBindingObserver, AppLifecycleState;
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
import 'user_session_coordinator.dart';
import 'kyno_context_service.dart';
import 'error_reporter.dart';
import 'meal_tombstones.dart';
import 'internal/test_environment.dart';

// Logging in this file is debug-only: release builds skip the console I/O.
void _debugLog(String? message, {int? wrapWidth}) {
  if (kDebugMode) debugPrint(message, wrapWidth: wrapWidth);
}

/// A day-log write waiting for its turn in the write chain. Calls that arrive
/// while it is still queued refresh [snapshot] and share [done], so a burst of
/// saves becomes one disk write that contains every change.
class _PendingDayLogsWrite {
  _PendingDayLogsWrite(this.key, this.snapshot);
  final String key;
  Map<String, DayLog> snapshot;
  late final Future<void> done;
}

/// Result of encoding the day-log store: the exact blob that is persisted plus
/// each day's JSON (the change fingerprint behind the dirty-day set).
typedef _EncodedDayLogs = ({String blob, Map<String, String> days});

/// What one write encodes: the store's days ([logs]) plus days kept verbatim
/// because they could not be read at load ([raw], `{dateKey: json}`), so an
/// unreadable day is never dropped from disk by a later save.
typedef _DayLogsWriteInput = ({Map<String, DayLog> logs, Map<String, String> raw});

/// Encodes the store exactly like `jsonEncode({key: log.toJson(), ...})`:
/// `{"k1":<day1>,"k2":<day2>}` with entries in map order, then any raw day
/// the store does not hold. Top-level so it can run in a background isolate.
_EncodedDayLogs _encodeDayLogs(_DayLogsWriteInput input) {
  final days = <String, String>{};
  final buf = StringBuffer('{');
  var first = true;
  void put(String key, String json) {
    if (!first) buf.write(',');
    first = false;
    buf
      ..write(jsonEncode(key))
      ..write(':')
      ..write(json);
  }
  for (final e in input.logs.entries) {
    final dayJson = jsonEncode(e.value.toJson());
    days[e.key] = dayJson;
    put(e.key, dayJson);
  }
  for (final e in input.raw.entries) {
    if (!input.logs.containsKey(e.key)) put(e.key, e.value);
  }
  buf.write('}');
  return (blob: buf.toString(), days: days);
}

/// A decoded day-log blob: the days that could be read ([logs]), each one's
/// JSON as it will be written again ([days], the baseline later writes are
/// compared with), and the raw JSON of each day that could not be read
/// ([bad]).
typedef _DecodedDayLogs = ({
  Map<String, DayLog> logs,
  Map<String, String> days,
  Map<String, String> bad,
});

/// Decodes a persisted day-log blob, each day on its own: one unreadable day
/// is set aside, never the rest. Throws only when the blob itself is not a
/// JSON object. Top-level so it can run in a background isolate.
_DecodedDayLogs _decodeDayLogs(String raw) {
  final map = jsonDecode(raw) as Map<String, dynamic>;
  final logs = <String, DayLog>{};
  final days = <String, String>{};
  final bad = <String, String>{};
  for (final e in map.entries) {
    try {
      final log = DayLog.fromJson(e.value as Map<String, dynamic>);
      days[e.key] = jsonEncode(log.toJson());
      logs[e.key] = log;
    } catch (_) {
      bad[e.key] = jsonEncode(e.value);
    }
  }
  return (logs: logs, days: days, bad: bad);
}

/// Exposed for tests: the encoder used for every day-log write.
@visibleForTesting
String encodeDayLogsForTest(Map<String, DayLog> snapshot) =>
    _encodeDayLogs((logs: snapshot, raw: const <String, String>{})).blob;

class _PersistenceLifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      PersistenceService.flushAll().ignore();
    } else {
      // Back in front (maybe on a new day): keep the home-screen widget's
      // numbers current.
      WidgetService.updateWidgetData().catchError((_) {}).ignore();
      // Retry whatever the cloud is still missing (failed or offline
      // uploads and deletes).
      try {
        CloudSyncService.instance.drainPendingUploads();
      } catch (_) {}
    }
  }
}

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

  /// Bumped at every session boundary (sign-out / account switch). A load
  /// that started before the boundary must not publish its data after it.
  static int _sessionEpoch = 0;

  /// Current session epoch. Async work that writes user data captures it at
  /// its start and must drop its result if it changed (sign-out / switch).
  static int get sessionEpoch => _sessionEpoch;

  static Future<void> clearCachedOwnerId() async {
    _sessionEpoch++;
    _cachedOwnerId = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('cached_owner_user_id_v1');
    } catch (_) {}
  }

  /// Account deletion only: removes every stored key that belongs to
  /// [userId] (all `*_<userId>` keys) and nothing else. Other accounts' data
  /// and device-wide settings (theme, migration sentinels) are untouched.
  /// Returns the removed keys. Never call this as a side effect of anything
  /// but an explicit, confirmed account deletion.
  static Future<List<String>> removeKeysForUser(
    String userId, {
    SharedPreferences? prefsOverride,
  }) async {
    // A blank id would match every key ending in '_'.
    if (userId.trim().isEmpty) return const [];
    await flushPendingWrites();
    final prefs = prefsOverride ?? await SharedPreferences.getInstance();
    final suffix = '_$userId';
    final doomed = prefs.getKeys().where((k) => k.endsWith(suffix)).toList();
    for (final k in doomed) {
      await prefs.remove(k);
    }
    // Device-wide pointers that name this account.
    if (prefs.getString('cached_owner_user_id_v1') == userId) {
      await prefs.remove('cached_owner_user_id_v1');
      doomed.add('cached_owner_user_id_v1');
    }
    if (_cachedOwnerId == userId) _cachedOwnerId = null;
    return doomed;
  }

  static bool get isOnboardingDone => _onboardingDone;

  // ── Startup load ─────────────────────────────────────────────────────────

  /// Restore persisted state for a specific authenticated user.
  static Future<void> loadForUser(String userId, {SharedPreferences? prefsOverride}) async {
    final epoch = _sessionEpoch;
    // Never read the store while a write for it is still queued.
    await flushPendingWrites();
    if (epoch != _sessionEpoch) return; // signed out before the load began
    _ensureLifecycleObserver();
    try {
      final prefs = prefsOverride ?? await SharedPreferences.getInstance();
      _cachedOwnerId = userId;
      // Device-wide legacy keys only ever belong to their one owner; any other
      // account must not inherit onboarding, profile or meal logs from them.
      final ownsLegacy =
          UserSessionCoordinator.legacyOwner(prefs) == userId;
      _onboardingDone = prefs.getBool('${_kOnboarding}_$userId') ??
          (ownsLegacy ? prefs.getBool(_kOnboarding) : null) ??
          false;

      // Hook hydration complete callback to save user ID
      NutritionHydrationGuard.instance.onHydrationComplete = (id) {
        setCachedOwnerId(id).ignore();
      };

      // Profile and day logs load independently: an unreadable profile must
      // not cost the meal logs, nor the reverse.
      final profileKey = '${_kProfile}_$userId';
      final profileRaw = prefs.getString(profileKey) ??
          (ownsLegacy ? prefs.getString(_kProfile) : null);
      // A brand-new account has no profile yet: never keep a previous one.
      try {
        ProfileService.instance.currentUserProfile = profileRaw == null
            ? null
            : UserProfile.fromJson(jsonDecode(profileRaw) as Map<String, dynamic>);
      } catch (e, st) {
        ProfileService.instance.currentUserProfile = null;
        _reportError('profile could not be read', e, st);
        await _backUpUnreadable(prefs, _kProfile, userId, profileRaw!);
      }

      final dayLogsKey = '${_kDayLogs}_$userId';
      final ownRaw = prefs.getString(dayLogsKey);
      final logsRaw = ownRaw ?? (ownsLegacy ? prefs.getString(_kDayLogs) : null);
      var decoded = _noDayLogs;
      var failedOutright = false;
      if (logsRaw != null) {
        try {
          decoded = await _decodeDayLogsForLoad(logsRaw);
        } catch (e, st) {
          failedOutright = true;
          _reportError('day logs could not be read', e, st);
        }
      }
      // A sign-out / account switch during the background decode must never
      // let this user's logs land in the next session.
      if (epoch != _sessionEpoch || _cachedOwnerId != userId) {
        _debugLog('[PersistenceService] Owner changed during load, dropping $userId logs');
        return;
      }
      await _setAsideUnreadable(prefs, dayLogsKey, userId, logsRaw, decoded,
          failedOutright: failedOutright, ownsKey: ownRaw != null);
      if (epoch != _sessionEpoch || _cachedOwnerId != userId) return;
      // Days changed here and not yet confirmed in the cloud. None stored
      // (first run with this list): every day counts as changed until
      // hydration finds it matching the cloud.
      final dirty = prefs.getStringList(_dirtyKeyFor(dayLogsKey));
      _dirtyDays
        ..clear()
        ..[dayLogsKey] = dirty?.toSet() ?? decoded.logs.keys.toSet();
      _dirtyUnsaved.clear();
      _writtenDayJson
        ..clear()
        ..[dayLogsKey] = decoded.days;
      dayLogStore.clear();
      dayLogStore.addAll(decoded.logs);
      _debugLog('[PersistenceService] Loaded ${dayLogStore.length} day logs for user: $userId');
    } catch (e) {
      _debugLog('[PersistenceService] Error loading user-scoped data: $e');
    }
  }

  static const _DecodedDayLogs _noDayLogs = (
    logs: <String, DayLog>{},
    days: <String, String>{},
    bad: <String, String>{},
  );

  /// After loading [key]: keeps a copy of whatever could not be read before
  /// anything can overwrite it, and decides whether [key] may be written.
  ///  * Some days unreadable: they are copied aside, and every later write of
  ///    [key] carries them verbatim (see [_DayLogsWriteInput]).
  ///  * Nothing readable: the whole blob is copied aside. Until a verified
  ///    copy exists, [key] is never written (a save would replace it with
  ///    what is in memory); that lifts once the copy lands or [key] loads.
  static Future<void> _setAsideUnreadable(
    SharedPreferences prefs,
    String key,
    String? userId,
    String? raw,
    _DecodedDayLogs decoded, {
    required bool failedOutright,
    required bool ownsKey,
  }) async {
    _unreadableDays.remove(key);
    _writeBlocked.remove(key);
    if (raw == null) return;
    if (failedOutright) {
      final saved = await _backUpUnreadable(prefs, _kDayLogs, userId, raw);
      // A legacy blob is only read; writes go to the user's own key.
      if (!saved && ownsKey) _writeBlocked.add(key);
      return;
    }
    if (decoded.bad.isEmpty) return;
    _reportError('${decoded.bad.length} stored day(s) could not be read',
        StateError('unreadable day logs'), null);
    _unreadableDays[key] = decoded.bad;
    // Only the unreadable days: the rest stay readable in [key] itself.
    await _backUpUnreadable(prefs, _kDayLogs, userId,
        _encodeDayLogs((logs: const <String, DayLog>{}, raw: decoded.bad)).blob);
  }

  /// Copies an unreadable stored value aside as
  /// `<base>_corrupt_<millis>_<userId>` (the user suffix keeps it within
  /// account deletion's reach). Skipped when an identical copy exists, so a
  /// value that stays unreadable is not copied again on every launch. True
  /// once a verified copy exists. Never throws.
  static Future<bool> _backUpUnreadable(
      SharedPreferences prefs, String base, String? userId, String payload) async {
    final prefix = '${base}_corrupt_';
    final suffix = userId == null || userId.isEmpty ? '' : '_$userId';
    try {
      for (final k in prefs.getKeys()) {
        if (!k.startsWith(prefix) || !k.endsWith(suffix)) continue;
        final existing = prefs.get(k);
        if (existing is String && existing == payload) return true;
      }
      final key = '$prefix${DateTime.now().millisecondsSinceEpoch}$suffix';
      final ok = await _setString(prefs, key, payload);
      final verified = ok && prefs.getString(key) == payload;
      if (!verified) {
        _reportError('backup of unreadable $base failed',
            StateError('backup not stored'), null);
      }
      return verified;
    } catch (e, st) {
      _reportError('backup of unreadable $base failed', e, st);
      return false;
    }
  }

  /// Test seam: replaces SharedPreferences.setString for persistence writes
  /// (day logs and backups), to simulate a full or failing disk.
  @visibleForTesting
  static Future<bool> Function(String key, String value)? debugSetStringOverride;

  /// Test seam: receives every error report instead of [ErrorReporter].
  @visibleForTesting
  static void Function(String what, Object error)? debugErrorSink;

  static Future<bool> _setString(
      SharedPreferences prefs, String key, String value) {
    final override = debugSetStringOverride;
    return override != null ? override(key, value) : prefs.setString(key, value);
  }

  /// Reports a local storage problem (no user data in the message).
  static void _reportError(String what, Object error, StackTrace? stack) {
    _debugLog('[PersistenceService] $what: $error');
    final sink = debugErrorSink;
    if (sink != null) {
      sink(what, error);
      return;
    }
    ErrorReporter.instance.report(
        StateError('Persistence: $what (${error.runtimeType})'), stack,
        type: 'persistence');
  }

  /// Restore all persisted state. Must be awaited before runApp().
  static Future<void> load() async {
    await flushPendingWrites();
    _ensureLifecycleObserver();
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
        // Each day on its own; nothing unreadable is ever written over.
        var decoded = _noDayLogs;
        var failedOutright = false;
        try {
          decoded = _decodeDayLogs(logsRaw);
        } catch (e, st) {
          failedOutright = true;
          _reportError('day logs could not be read', e, st);
        }
        await _setAsideUnreadable(prefs, _kDayLogs, null, logsRaw, decoded,
            failedOutright: failedOutright, ownsKey: true);
        dayLogStore.addAll(decoded.logs);
        _writtenDayJson[_kDayLogs] = {
          ...?_writtenDayJson[_kDayLogs],
          ...decoded.days,
        };
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

    _debugLog('[PersistenceService] ⚠️  Legacy memory quarantine complete '
        '(one-time migration to per-unit schema)');
  }

  // ── Write helpers ─────────────────────────────────────────────────────────

  /// Local write only. Use ProfileService.save, which also backs the
  /// profile up to the cloud. Returns the profile as stored (with a target
  /// history record appended when target inputs changed).
  static Future<UserProfile> saveProfile(UserProfile p) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = UserSessionCoordinator.instance.currentUserId ?? _cachedOwnerId;
      final key = userId != null ? '${_kProfile}_$userId' : _kProfile;

      final oldRaw = prefs.getString(key) ?? prefs.getString(_kProfile);
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

      await prefs.setString(key, jsonEncode(finalProfile.toJson()));
      if (userId == null) {
        await prefs.setString(_kProfile, jsonEncode(finalProfile.toJson()));
      }
      WidgetService.updateWidgetData().ignore();
      return finalProfile;
    } catch (_) {
      return p;
    }
  }

  static Future<void> setOnboardingDone() async {
    _onboardingDone = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = UserSessionCoordinator.instance.currentUserId ?? _cachedOwnerId;
      if (userId != null) {
        await prefs.setBool('${_kOnboarding}_$userId', true);
      } else {
        // Only an unscoped (pre-auth) session may write the device-wide flag;
        // writing it for a signed-in user made every later account skip
        // onboarding.
        await prefs.setBool(_kOnboarding, true);
      }
    } catch (_) {}
  }

  // ── Day-log write pipeline ────────────────────────────────────────────────
  //
  // The in-memory [dayLogStore] is the source of truth. Writes are serialized
  // through [_writeTail]; overlapping saves for the same storage key coalesce
  // into one write that encodes the newest state. What is written (key and
  // JSON) is identical to the previous direct `jsonEncode` implementation.

  static Future<void> _writeTail = Future<void>.value();
  static bool _writeBusy = false;
  static _PendingDayLogsWrite? _queuedWrite;

  /// Per storage key, each day's JSON as of the last write (or the load):
  /// what the next write is compared with to find changed days.
  static final Map<String, Map<String, String>> _writtenDayJson = {};

  /// Per storage key, the raw JSON of days that could not be read at load.
  static final Map<String, Map<String, String>> _unreadableDays = {};

  /// Storage keys that must not be written (see [_setAsideUnreadable]).
  static final Set<String> _writeBlocked = {};

  /// Storage keys whose last write failed: the next flush writes again.
  static final Set<String> _rewriteNeeded = {};

  /// True when [userId]'s stored day logs could not be read and are being
  /// left untouched (no verified copy could be made).
  static bool dayLogsWriteBlockedFor(String userId) =>
      _writeBlocked.contains('${_kDayLogs}_$userId');

  // ── Dirty days (cloud upload queue) ───────────────────────────────────────
  //
  // Per storage key, the days that changed here and are not yet confirmed
  // uploaded. A write adds every day whose JSON differs from the previous
  // write; CloudSyncService removes a day only after its upload succeeded
  // (and only if it did not change meanwhile); hydration removes days that
  // already match the cloud. Persisted next to the store
  // (`day_logs_dirty_v1_<userId>`), so a restart neither forgets a pending
  // upload nor re-uploads the whole history.

  static const _kDirtyDays = 'day_logs_dirty_v1';
  static final Map<String, Set<String>> _dirtyDays = {};
  static final Set<String> _dirtyUnsaved = {};

  static String _dirtyKeyFor(String dayLogsKey) =>
      dayLogsKey.replaceFirst(_kDayLogs, _kDirtyDays);

  static String _keyForUser(String userId) => '${_kDayLogs}_$userId';

  /// Days of [userId] to upload: changed and unconfirmed, or carrying a meal
  /// deletion not yet uploaded. Empty unless [userId]'s store is loaded.
  static Set<String> daysNeedingUpload(String userId) {
    final key = _keyForUser(userId);
    if (_currentDayLogsKey() != key) return const {};
    final tombstones = MealTombstones.instance;
    return {
      for (final d in _dirtyDays[key] ?? const <String>{})
        if (dayLogStore.containsKey(d)) d,
      if (tombstones.ownerUserId == userId)
        for (final d in tombstones.days)
          if (dayLogStore.containsKey(d) && tombstones.deletionsFor(d).isNotEmpty) d,
    };
  }

  /// [dateKey] of [userId] reached the cloud as [sentJson]. It stays queued
  /// if it changed while the upload ran. Call [persistDirtyDays] after.
  static void markDayUploaded(String userId, String dateKey, String sentJson) {
    final key = _keyForUser(userId);
    if (_currentDayLogsKey() != key) return;
    final log = dayLogStore[dateKey];
    if (log == null || jsonEncode(log.toJson()) != sentJson) return;
    if (_dirtyDays[key]?.remove(dateKey) ?? false) _dirtyUnsaved.add(key);
  }

  /// Hydration found these days of [userId] identical to the cloud (`{day:
  /// JSON}` after the merge): nothing to upload, unless they changed since.
  static Future<void> markDaysInSyncWithCloud(
      String userId, Map<String, String> matching) async {
    final key = _keyForUser(userId);
    if (_currentDayLogsKey() != key || matching.isEmpty) return;
    final dirty = _dirtyDays[key];
    final written = _writtenDayJson[key];
    if (dirty == null || written == null) return;
    matching.forEach((day, json) {
      if (written[day] == json && dirty.remove(day)) _dirtyUnsaved.add(key);
    });
    await persistDirtyDays(userId);
  }

  /// Saves [userId]'s dirty-day set if it changed. Never throws.
  static Future<void> persistDirtyDays(String userId) async {
    try {
      await _persistDirty(await SharedPreferences.getInstance(),
          _keyForUser(userId));
    } catch (e) {
      _debugLog('[PersistenceService] dirty-day persist error: $e');
    }
  }

  static Future<void> _persistDirty(SharedPreferences prefs, String key) async {
    final dirty = _dirtyDays[key];
    // The unscoped (pre-auth) store is never uploaded.
    if (dirty == null || key == _kDayLogs || !_dirtyUnsaved.remove(key)) return;
    await prefs.setStringList(_dirtyKeyFor(key), dirty.toList()..sort());
  }

  /// Marks every day of [days] whose JSON changed since the last write of
  /// [key] as dirty, and makes [days] the new baseline.
  static void _markChangedDays(String key, Map<String, String> days) {
    final before = _writtenDayJson[key];
    final dirty = _dirtyDays.putIfAbsent(key, () => <String>{});
    for (final e in days.entries) {
      if (before == null || before[e.key] != e.value) {
        if (dirty.add(e.key)) _dirtyUnsaved.add(key);
      }
    }
    _writtenDayJson[key] = days;
  }

  /// Stores at least this many days are encoded in a background isolate so
  /// the UI isolate never stalls on a multi-megabyte jsonEncode.
  @visibleForTesting
  static int isolateEncodeThreshold = 60;

  /// Persisted day-log blobs at least this long (UTF-16 code units) are
  /// decoded in a background isolate at sign-in so the boot loader keeps
  /// animating instead of freezing on a multi-megabyte jsonDecode.
  @visibleForTesting
  static int isolateDecodeThresholdChars = 64 * 1024;

  /// Decodes [raw] off the UI isolate when it is large and the result is
  /// guaranteed identical. `DayLog.fromJson` consults the user's correction
  /// memory only once the hydration guard is open; during sign-in the guard is
  /// closed, so a background isolate (which has its own, closed guard) yields
  /// exactly the same logs. If the guard is open, decode here instead.
  static Future<_DecodedDayLogs> _decodeDayLogsForLoad(String raw) async {
    final guard = NutritionHydrationGuard.instance;
    final guardOpen = guard.isReadyForUser(guard.hydratedUserId);
    if (raw.length >= isolateDecodeThresholdChars && !guardOpen) {
      try {
        return await compute(_decodeDayLogs, raw, debugLabel: 'decodeDayLogs');
      } catch (e) {
        _debugLog('[PersistenceService] Background decode failed, decoding inline: $e');
      }
    }
    return _decodeDayLogs(raw);
  }

  static String _currentDayLogsKey() {
    final userId = UserSessionCoordinator.instance.currentUserId ?? _cachedOwnerId;
    return userId != null ? '${_kDayLogs}_$userId' : _kDayLogs;
  }

  static Future<void> saveDayLogs() {
    lastLogsChangedAt = DateTime.now();
    _ensureLifecycleObserver();
    // Owner key and the set of days are captured now, so a later account
    // switch can never redirect this user's data to another user's key.
    final key = _currentDayLogsKey();
    final snapshot = Map<String, DayLog>.of(dayLogStore);

    final queued = _queuedWrite;
    if (queued != null && queued.key == key) {
      queued.snapshot = snapshot;
      return queued.done;
    }

    if (!_writeBusy) {
      // Nothing in flight: start immediately (no chaining on stale futures).
      final done = _performDayLogsWrite(key, snapshot);
      _trackWrite(done);
      return done;
    }

    // A write is in flight: queue one follow-up that later callers join.
    final write = _PendingDayLogsWrite(key, snapshot);
    _queuedWrite = write;
    write.done = _writeTail.then((_) {
      if (identical(_queuedWrite, write)) _queuedWrite = null;
      return _performDayLogsWrite(write.key, write.snapshot);
    });
    _trackWrite(write.done);
    return write.done;
  }

  static void _trackWrite(Future<void> done) {
    _writeBusy = true;
    _writeTail = done;
    done.whenComplete(() {
      if (identical(_writeTail, done)) _writeBusy = false;
    }).ignore();
  }

  static Future<void> _performDayLogsWrite(
      String key, Map<String, DayLog> snapshot) async {
    try {
      final _DayLogsWriteInput input = (
        logs: snapshot,
        raw: _unreadableDays[key] ?? const <String, String>{},
      );
      _EncodedDayLogs encoded;
      if (snapshot.length >= isolateEncodeThreshold) {
        try {
          encoded = await compute(_encodeDayLogs, input,
              debugLabel: 'encodeDayLogs');
        } catch (_) {
          encoded = _encodeDayLogs(input);
        }
      } else {
        encoded = _encodeDayLogs(input);
      }
      // Changed days need uploading whether or not the disk write lands
      // (the upload reads memory).
      _markChangedDays(key, encoded.days);
      final prefs = await SharedPreferences.getInstance();
      if (_writeBlocked.contains(key)) {
        _reportError('day logs not saved: the stored copy is unreadable '
            'and could not be backed up', StateError('write refused'), null);
      } else {
        var ok = false;
        try {
          ok = await _setString(prefs, key, encoded.blob);
          if (!ok) {
            _reportError('day logs write was rejected',
                StateError('setString returned false'), null);
          }
        } catch (e, st) {
          _reportError('day logs write failed', e, st);
        }
        // Not on disk: the next flush (app pause, sign-out) or save writes
        // again; memory still holds every change.
        ok ? _rewriteNeeded.remove(key) : _rewriteNeeded.add(key);
      }
      await _persistDirty(prefs, key);
    } catch (e, st) {
      _rewriteNeeded.add(key);
      _reportError('day logs write failed', e, st);
    }
  }

  /// Writes the store again if its last write failed.
  static void _retryFailedWrite() {
    if (_rewriteNeeded.contains(_currentDayLogsKey())) saveDayLogs().ignore();
  }

  /// Completes once every day-log write requested so far has hit disk.
  static Future<void> flushPendingWrites() async {
    while (_writeBusy) {
      await _writeTail;
    }
  }

  // ── Post-save side effects (widget, cloud sync, insights) ─────────────────
  //
  // These are derived from the saved store, so they are deferred off the
  // interaction frame and coalesced. Insights readers flush pending work on
  // read, and app pause/detach and logout flush everything.

  /// Delay before post-save side effects run. Zero runs them inline (the
  /// default under `flutter test`, which keeps tests deterministic).
  static Duration postSaveEffectsDelay = isRunningInFlutterTest
      ? Duration.zero
      : const Duration(milliseconds: 450);
  static Timer? _postSaveTimer;
  static bool _postSaveEffectsPending = false;

  static void _schedulePostSaveEffects(DateTime date) {
    final profile = ProfileService.instance.currentUserProfile;
    if (profile != null) {
      InsightsReportService.instance.queueRecomputeForDate(date, profile);
    }
    _postSaveEffectsPending = true;
    if (postSaveEffectsDelay == Duration.zero) {
      _runPostSaveEffects();
      return;
    }
    _postSaveTimer?.cancel();
    _postSaveTimer = Timer(postSaveEffectsDelay, _runPostSaveEffects);
  }

  /// Number of cloud day-log uploads requested by post-save effects.
  @visibleForTesting
  static int cloudSyncRequestCount = 0;

  static void _runPostSaveEffects({bool includeInsights = true}) {
    _postSaveTimer?.cancel();
    _postSaveTimer = null;
    if (!_postSaveEffectsPending) return;
    _postSaveEffectsPending = false;

    WidgetService.updateWidgetData().catchError((_) {}).ignore();

    // Fire-and-forget sync to Supabase
    cloudSyncRequestCount++;
    try {
      CloudSyncService.instance.syncDayLogsBackground().catchError((_) {}).ignore();
    } catch (_) {}

    if (includeInsights) {
      InsightsReportService.instance.flushPendingRecompute().ignore();
    }
  }

  /// Runs any deferred side effects now and waits for pending disk writes.
  /// Called on app pause / hide / detach.
  static Future<void> flushAll() async {
    _runPostSaveEffects();
    await InsightsReportService.instance.flushPendingRecompute();
    _retryFailedWrite();
    await flushPendingWrites();
  }

  /// Session boundary (logout / account switch): push this user's pending
  /// widget + cloud work while their data is still in memory, make sure every
  /// write is on disk, and drop derived insight work (maybeRecompute rebuilds
  /// it next session).
  static Future<void> flushForSessionEnd() async {
    InsightsReportService.instance.cancelPendingRecompute();
    _runPostSaveEffects(includeInsights: false);
    _retryFailedWrite();
    await flushPendingWrites();
  }

  static _PersistenceLifecycleObserver? _lifecycleObserver;
  static void _ensureLifecycleObserver() {
    if (_lifecycleObserver != null) return;
    try {
      final observer = _PersistenceLifecycleObserver();
      WidgetsBinding.instance.addObserver(observer);
      _lifecycleObserver = observer;
    } catch (_) {
      // No binding (pure Dart tests): writes are still awaited normally.
    }
  }

  static Future<void> runHistoricalRepairMigration() async {
    bool migrated = false;

    for (final entry in dayLogStore.entries) {
      final log = entry.value;
      final date = DateTime.tryParse(entry.key);
      if (date == null) continue;

      // No gym-day back-fill: an unset day follows WorkoutService.planFor
      // (session > the user's pick > split), so it can't go stale.

      // Freeze missing targets for any historical days that have null values
      if (log.targetCalories == null || log.targetProtein == null) {
        final profile = ProfileService.instance.currentUserProfile;
        if (profile != null) {
          final historicalProfile = profile.profileActiveOn(date);
          if (historicalProfile == null) {
            _debugLog('[PersistenceService] Skipping target freeze for $entry: insufficient timeline history');
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
          _debugLog('[PersistenceService] Freezing targets on startup for $entry using historical profile: '
              '${resolvedTarget.calories} kcal / ${resolvedTarget.protein}g');
        }
      }
    }

    if (migrated) {
      await saveDayLogs();
      CloudSyncService.instance.syncDayLogsBackground().ignore();
    }
    lastHistoricalRepairCompletedAt = DateTime.now();
    _debugLog('[PersistenceService] Historical repair migration complete at: $lastHistoricalRepairCompletedAt');
  }

  static Future<void> saveDay(DateTime date) async {
    final dKey = dateKey(date);
    final log = dayLogStore[dKey];
    if (log != null) {
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

    // Widget refresh, cloud upload and insights recompute are derived from the
    // saved store; they run coalesced, off the interaction frame.
    _schedulePostSaveEffects(date);
  }

  /// Saves the store exactly as it is (no gym-day or target back-fill, unlike
  /// [saveDay]) and schedules the same post-save effects as [saveDay],
  /// including the cloud upload. Used for meal removals / Undo so a delete
  /// always reaches the cloud, whatever the day's target mode.
  static Future<void> saveDayLogsAndSync(DateTime date) async {
    await saveDayLogs();
    _schedulePostSaveEffects(date);
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
    // Step 0: land any queued write before wiping, so a late write can never
    // resurrect data after the keys below are removed.
    await flushForSessionEnd();

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
    KynoContextService.instance.reset();
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
    _debugLog('[PersistenceService] ✅ reset() complete, all user data wiped');
  }
}
