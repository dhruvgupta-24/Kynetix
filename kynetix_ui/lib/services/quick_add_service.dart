import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/quick_add_item.dart';
import '../models/day_log.dart';
import '../models/nutrition_result.dart';
import '../config/supabase_client.dart';
import 'nutrition_hydration_guard.dart';
import 'nutrition_pipeline.dart';
import 'meal_memory.dart';
import 'persistence_service.dart';
import 'nutrition_target_engine.dart';
import 'user_session_coordinator.dart';
import 'user_nutrition_memory.dart';
import 'food_link_service.dart';
import 'analytics_service.dart';

// Logging in this file is debug-only: release builds skip the console I/O.
void _debugLog(String? message, {int? wrapWidth}) {
  if (kDebugMode) debugPrint(message, wrapWidth: wrapWidth);
}


class QuickAddService {
  QuickAddService._();
  static final QuickAddService instance = QuickAddService._();

  static const _prefsKey = 'quick_add_custom_items_v2';
  static const _legacyPrefsKey = 'quick_add_custom_items';

  String? _currentUserId;
  String get _currentPrefsKey => _currentUserId != null ? '${_prefsKey}_$_currentUserId' : _prefsKey;

  List<QuickAddItem> _customItems = [];
  List<QuickAddItem> get customItems => List.unmodifiable(_customItems);

  SupabaseClient get _supabase => supabase;

  /// The two items that used to be hard-coded into every Quick Add list.
  /// They are no longer shown to new accounts. Existing users get them once,
  /// as ordinary items they can delete (see [_materializeFormerDefaults]).
  static const _formerDefaults = [
    (name: '1 scoop whey', calories: 115.0, protein: 22.0, emoji: '🥛'),
    (name: '4 egg whites + 400ml milk', calories: 328.0, protein: 27.0, emoji: '🥚'),
  ];
  static String _defaultsMarkerKey(String userId) =>
      'quick_add_defaults_materialized_v1_$userId';

  // ── Deletion tombstones ────────────────────────────────────────────────
  //
  // Ids the user deleted on this device whose cloud row may still exist (the
  // delete failed offline, or has not landed yet). Cloud sync never restores
  // them and retries their cloud delete; an id is dropped only once its
  // cloud delete succeeded. Stored per user, so account deletion's per-user
  // key sweep removes it.
  static String tombstoneKeyFor(String userId) => 'quick_add_tombstones_v1_$userId';

  final Set<String> _tombstones = {};
  Future<void>? _cloudDeleteRun;
  bool _cloudDeleteAgain = false;

  /// Ids currently suppressed from cloud sync.
  Set<String> get deletedTombstones => Set.unmodifiable(_tombstones);

  /// Replaces the cloud delete in tests (the real one needs Supabase).
  /// Returns true when the delete of [ids] went through for [userId].
  @visibleForTesting
  Future<bool> Function(Set<String> ids, String userId)? cloudDeleterOverride;

  /// Completes when any in-flight cloud delete (and its tombstone write) has
  /// finished.
  @visibleForTesting
  Future<void> waitForCloudDeletes() async {
    while (_cloudDeleteRun != null) {
      await _cloudDeleteRun;
    }
  }

  /// Load for specific authenticated user
  Future<void> initForUser(String userId, {SharedPreferences? prefsOverride}) async {
    _currentUserId = userId;
    _customItems.clear();
    _tombstones.clear();
    await init(prefsOverride: prefsOverride);
    await _materializeFormerDefaults(userId, prefsOverride);
    try {
      final prefs = prefsOverride ?? await SharedPreferences.getInstance();
      if (_currentUserId != userId) return;
      _tombstones
        ..clear()
        ..addAll(prefs.getStringList(tombstoneKeyFor(userId)) ?? const []);
      // Retry cloud deletes an earlier session could not land.
      if (_tombstones.isNotEmpty) _pushCloudDeletes();
    } catch (e) {
      _debugLog('[QuickAddService] Tombstone load failed: $e');
    }
  }

  /// One-time move off the hard-coded defaults. A user who was already using
  /// the app keeps the two items (now deletable, synced like any other item);
  /// a brand-new account starts with an empty Quick Add list.
  Future<void> _materializeFormerDefaults(
      String userId, SharedPreferences? prefsOverride) async {
    try {
      final prefs = prefsOverride ?? await SharedPreferences.getInstance();
      final marker = _defaultsMarkerKey(userId);
      if (prefs.getBool(marker) == true) return;
      final existingUser =
          dayLogStore.isNotEmpty || PersistenceService.isOnboardingDone;
      if (existingUser) {
        for (final d in _formerDefaults) {
          final taken = _customItems
              .any((i) => i.name.toLowerCase() == d.name.toLowerCase());
          if (taken) continue;
          final item = QuickAddItem(
            id: generateUuid(),
            name: d.name,
            calories: d.calories,
            protein: d.protein,
            emoji: d.emoji,
          );
          _customItems.add(item);
          _syncQuickAddBackground(item).ignore();
        }
        await _saveLocally(prefs);
      }
      await prefs.setBool(marker, true);
    } catch (e) {
      _debugLog('[QuickAddService] Default materialization failed: $e');
    }
  }

  /// Flush in-memory state without deleting persisted disk stores
  void clearMemory() {
    _customItems.clear();
    _tombstones.clear();
    _currentUserId = null;
  }

  /// Public service method to execute a Quick Add operation cleanly:
  ///   1. Ensures hydration guard is ready for current user.
  ///   2. Loads today's DayLog.
  ///   3. Resolves estimation via NutritionPipeline.
  ///   4. Inserts MealEntry into DayLog.
  ///   5. Remembers meal in MealMemory.
  ///   6. Awaits PersistenceService.saveDay(date).
  ///   7. Refreshes nutrition targets via NutritionTargetEngine.
  /// Returns the inserted MealEntry upon successful persistence.
  /// [onInserted] fires as soon as the entry is in the in-memory DayLog
  /// (before persistence), for optimistic UI.
  Future<MealEntry> addMealToDay({
    required DateTime date,
    required String name,
    required double calories,
    required double protein,
    required MealSection section,
    void Function(MealEntry entry)? onInserted,
  }) async {
    final sw = Stopwatch()..start();
    final tapTimeMs = sw.elapsedMicroseconds / 1000.0;
    _debugLog('[QuickAddTap] ⏱️ QuickAddService entered: T+${tapTimeMs.toStringAsFixed(2)} ms');

    // 1. Hydration check
    if (!NutritionHydrationGuard.instance.isReadyForCurrentUser) {
      final currentUserId = _supabase.auth.currentUser?.id ?? 'guest';
      NutritionHydrationGuard.instance.markComplete(currentUserId);
    }

    // 2. DayLog retrieval
    final dayLog = logFor(date);

    // 3. Strict Single Source of Truth Lookup Chain. A name linked to a
    //    scanned pack logs that pack's label numbers first.
    final linked = FoodLinkService.instance.resolveMeal(name);
    final userMem = UserNutritionMemory.instance.lookup(name);
    final mealMem = MealMemory.instance.lookupExactKnownFood(name) ??
                    MealMemory.instance.lookupRecurring(name);

    final NutritionResult selectedResult;
    if (linked != null) {
      selectedResult = linked;
    } else if (userMem != null) {
      selectedResult = userMem;
    } else if (mealMem != null) {
      selectedResult = mealMem;
    } else if (calories > 0) {
      // The Quick Add item carries the numbers the user saw and saved: log
      // exactly those rather than re-estimating the name.
      selectedResult = NutritionResult.createCustom(
        canonicalMeal: name,
        calories: calories,
        protein: protein,
        source: 'quick_add',
        userCorrected: true,
      );
    } else {
      selectedResult = await NutritionPipeline.instance.estimateMeal(name);
    }

    // 4. Construct immutable MealEntry using selectedResult directly
    final entry = MealEntry(
      rawInput:        name,
      finalSavedInput: name,
      section:         section,
      addedAt:         DateTime.now(),
      dayOfWeek:       date.weekday,
      parsedFoods:     [name],
      userCorrected:   true,
      result:          selectedResult,
    );

    // 5. Store in DayLog and MealMemory
    dayLog.add(section, entry);
    AnalyticsService.instance.track('meal_logged', {'method': 'quick', 'kcal_bucket': AnalyticsService.kcalBucket(entry.calMid)});
    // The in-memory log now holds the entry (source of truth): let the UI
    // confirm immediately while persistence below completes.
    onInserted?.call(entry);
    await MealMemory.instance.store(
      name,
      entry.result,
      finalSavedInput: name,
      canonicalMeal: name,
    );

    // 6. Persistence
    final pStartMs = sw.elapsedMicroseconds / 1000.0;
    _debugLog('[QuickAddTap] ⏱️ Persistence started: T+${pStartMs.toStringAsFixed(2)} ms');

    await PersistenceService.saveDay(date);

    final pEndMs = sw.elapsedMicroseconds / 1000.0;
    _debugLog('[QuickAddTap] ⏱️ Persistence finished: T+${pEndMs.toStringAsFixed(2)} ms');

    // 7. Verification trace of zero mutations across pipeline (debug only:
    //    building this multi-line string costs real time on every tap).
    if (kDebugMode) {
      final dayLogReloaded = logFor(date);
      final reloadedEntry = dayLogReloaded.entriesFor(section).firstWhere((e) => e == entry);

      _debugLog('''
=================== REAL APP RUNTIME AUDIT TRACE (QUICK ADD) ===================
  1. Quick Add item selected     : "$name" (preset: ${calories}kcal, ${protein}g pro)
  2. UserNutritionMemory lookup  : ${userMem != null ? 'Calories=${userMem.calories.mid}, Pro=${userMem.protein.mid}, Carbs=${userMem.carbohydrates?.mid}, Fat=${userMem.fat?.mid}, Score=${userMem.mealQualityScore}' : 'NULL'}
  3. MealMemory lookup           : ${mealMem != null ? 'Calories=${mealMem.calories.mid}, Pro=${mealMem.protein.mid}, Carbs=${mealMem.carbohydrates?.mid}, Fat=${mealMem.fat?.mid}, Score=${mealMem.mealQualityScore}' : 'NULL'}
  4. NutritionPipeline output    : Calories=${selectedResult.calories.mid}, Pro=${selectedResult.protein.mid}, Carbs=${selectedResult.carbohydrates?.mid}, Fat=${selectedResult.fat?.mid}, Fiber=${selectedResult.fiber?.mid}, Score=${selectedResult.mealQualityScore} (Source: ${selectedResult.source})
  5. MealEntry.result before save: Calories=${entry.result.calories.mid}, Pro=${entry.result.protein.mid}, Carbs=${entry.result.carbohydrates?.mid}, Fat=${entry.result.fat?.mid}, Score=${entry.result.mealQualityScore}
  6. MealEntry.result after save : Calories=${reloadedEntry.result.calories.mid}, Pro=${reloadedEntry.result.protein.mid}, Carbs=${reloadedEntry.result.carbohydrates?.mid}, Fat=${reloadedEntry.result.fat?.mid}, Score=${reloadedEntry.result.mealQualityScore}
================================================================================
''');
    }

    await NutritionTargetEngine.instance.refreshTargetForDate(date);

    return entry;
  }

  Future<void> init({SharedPreferences? prefsOverride}) async {
    try {
      final prefs = prefsOverride ?? await SharedPreferences.getInstance();
      
      // Load current schema items. The device-wide (unscoped) list only ever
      // belongs to the account that owns the device's legacy data; any other
      // account must not inherit it.
      final ownsLegacy = _currentUserId == null ||
          UserSessionCoordinator.legacyOwner(prefs) == _currentUserId;
      final raw = prefs.getStringList(_currentPrefsKey) ??
          (ownsLegacy ? prefs.getStringList(_prefsKey) : null);
      if (raw != null) {
        _customItems = raw.map((s) {
          try {
            return QuickAddItem.fromJson(jsonDecode(s) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        }).whereType<QuickAddItem>().toList();
      }

      // Check legacy migration (owner only, same rule as above)
      final legacyRaw = ownsLegacy ? prefs.getStringList(_legacyPrefsKey) : null;
      if (legacyRaw != null && legacyRaw.isNotEmpty) {
        _debugLog('[QuickAddService] Migrating legacy custom quick adds...');
        final migrated = <QuickAddItem>[];
        for (final s in legacyRaw) {
          try {
            final json = jsonDecode(s) as Map<String, dynamic>;
            final item = QuickAddItem(
              id: generateUuid(),
              name: (json['name'] as String?) ?? '',
              calories: (json['calories'] as num?)?.toDouble() ?? 0.0,
              protein: (json['protein'] as num?)?.toDouble() ?? 0.0,
              emoji: (json['emoji'] as String?) ?? '⚡',
              builtIn: false,
            );
            migrated.add(item);
          } catch (_) {}
        }
        if (migrated.isNotEmpty) {
          _customItems.addAll(migrated);
          await _saveLocally(prefs);
        }
        await prefs.remove(_legacyPrefsKey);
        _debugLog('[QuickAddService] Legacy migration complete. Migrated ${migrated.length} items.');
      }
    } catch (e) {
      _debugLog('[QuickAddService] Init failed: $e');
    }
  }

  /// Updates memory synchronously (so callers can rebuild this frame), then
  /// persists.
  Future<void> saveItem(QuickAddItem item) async {
    final idx = _customItems.indexWhere((i) => i.id == item.id);
    _tombstones.remove(item.id); // Saved again: no longer deleted.
    if (idx >= 0) {
      _customItems[idx] = item;
    } else {
      _customItems.add(item);
    }
    final prefs = await SharedPreferences.getInstance();
    await _saveLocally(prefs);
    
    // Background sync to cloud
    _syncQuickAddBackground(item).ignore();
  }

  /// Updates memory synchronously (so callers can rebuild this frame), then
  /// persists.
  /// The id is tombstoned first, so a failed (offline) cloud delete can never
  /// be undone by the next cloud sync.
  Future<void> deleteItem(QuickAddItem item) async {
    _customItems.removeWhere((i) => i.id == item.id);
    final owner = _currentUserId;
    if (owner != null) _tombstones.add(item.id);
    final prefs = await SharedPreferences.getInstance();
    await _saveLocally(prefs);
    if (owner != null && _currentUserId == owner) {
      await _persistTombstones(prefs, owner);
    }

    // Background sync deletion to cloud (retried until it lands)
    _pushCloudDeletes();
  }

  Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    _customItems.clear();
    await prefs.remove(_currentPrefsKey);
    await prefs.remove(_prefsKey);
    await prefs.remove(_legacyPrefsKey);
    _currentUserId = null;
  }

  /// Two-way sync with the cloud list. With [expectedUserId] / [stillCurrent]
  /// (cloud hydration) it stops the moment that user's session is no longer
  /// the loaded one, so nothing lands under another account (or the
  /// device-wide key).
  Future<void> syncWithCloud({
    String? expectedUserId,
    bool Function()? stillCurrent,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    if (expectedUserId != null && userId != expectedUserId) return;
    if (!_isCurrent(userId, stillCurrent)) return;

    try {
      _debugLog('[QuickAddService] Starting custom quick adds cloud sync...');

      // 1. Upload local custom items that don't exist on the cloud yet or need update
      if (_customItems.isNotEmpty) {
        final List<Map<String, dynamic>> rows = _customItems.map((item) => {
          'id': item.id,
          'user_id': userId,
          'name': item.name,
          'calories': item.calories,
          'protein': item.protein,
          'emoji': item.emoji,
          'updated_at': DateTime.now().toIso8601String(),
        }).toList();

        await _supabase.from('user_quick_adds').upsert(rows);
        if (!_isCurrent(userId, stillCurrent)) return;
      }

      // 2. Fetch all custom quick adds from cloud and update local cache
      final response = await _supabase
          .from('user_quick_adds')
          .select()
          .eq('user_id', userId);

      await applyCloudItems(userId, response, stillCurrent: stillCurrent);
    } catch (e) {
      _debugLog('[QuickAddService] Cloud sync failed: $e');
    }
  }

  bool _isCurrent(String userId, bool Function()? stillCurrent) =>
      _currentUserId == userId && (stillCurrent?.call() ?? true);

  /// Replaces the local list with the cloud [rows] for [userId], except ids
  /// the user deleted on this device (their cloud delete is retried).
  /// Dropped if [userId]'s session is no longer the loaded one.
  @visibleForTesting
  Future<void> applyCloudItems(
    String userId,
    List<dynamic> rows, {
    bool Function()? stillCurrent,
  }) async {
    if (!_isCurrent(userId, stillCurrent)) return;
    final List<QuickAddItem> cloudItems = [];
    var skippedDeleted = false;
    for (final row in rows) {
      final id = row['id'] as String;
      if (_tombstones.contains(id)) {
        skippedDeleted = true;
        continue;
      }
      cloudItems.add(QuickAddItem(
        id: id,
        name: row['name'] as String,
        calories: (row['calories'] as num).toDouble(),
        protein: (row['protein'] as num).toDouble(),
        emoji: (row['emoji'] as String?) ?? '⚡',
        builtIn: false,
      ));
    }

    _customItems = cloudItems;
    final prefs = await SharedPreferences.getInstance();
    if (!_isCurrent(userId, stillCurrent)) return;
    await _saveLocally(prefs);
    _debugLog('[QuickAddService] Cloud sync complete. Loaded ${cloudItems.length} items from Supabase.');
    if (skippedDeleted) _pushCloudDeletes();
  }

  Future<void> _saveLocally(SharedPreferences prefs) async {
    final list = _customItems.map((i) => jsonEncode(i.toJson())).toList();
    await prefs.setStringList(_currentPrefsKey, list);
    if (_currentUserId == null) {
      await prefs.setStringList(_prefsKey, list);
    }
  }

  Future<void> _syncQuickAddBackground(QuickAddItem item) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await _supabase.from('user_quick_adds').upsert({
        'id': item.id,
        'user_id': userId,
        'name': item.name,
        'calories': item.calories,
        'protein': item.protein,
        'emoji': item.emoji,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      _debugLog('[QuickAddService] Background quick add sync failed: $e');
    }
  }

  Future<void> _persistTombstones(SharedPreferences prefs, String owner) async {
    final key = tombstoneKeyFor(owner);
    if (_tombstones.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setStringList(key, _tombstones.toList());
    }
  }

  /// Background cloud delete of every tombstoned id. Serialized; a request
  /// during a run triggers one more run. Ids are un-tombstoned only after a
  /// successful delete, and only for the user who deleted them.
  void _pushCloudDeletes() {
    if (_cloudDeleteRun != null) {
      _cloudDeleteAgain = true;
      return;
    }
    _cloudDeleteRun = () async {
      try {
        do {
          _cloudDeleteAgain = false;
          final owner = _currentUserId;
          if (owner == null || _tombstones.isEmpty) return;
          final ids = Set<String>.of(_tombstones);
          bool ok;
          try {
            final deleter = cloudDeleterOverride;
            ok = deleter != null
                ? await deleter(ids, owner)
                : await _deleteCloudRows(ids, owner);
          } catch (e) {
            _debugLog('[QuickAddService] Background quick add deletion sync failed: $e');
            ok = false;
          }
          if (!ok || _currentUserId != owner) return;
          final before = _tombstones.length;
          _tombstones.removeAll(ids);
          if (_tombstones.length == before) continue;
          final prefs = await SharedPreferences.getInstance();
          if (_currentUserId != owner) return;
          await _persistTombstones(prefs, owner);
        } while (_cloudDeleteAgain);
      } finally {
        _cloudDeleteRun = null;
      }
    }();
  }

  /// Deletes [ids] from [expectedUserId]'s cloud list. True only when the
  /// delete went through for that user.
  Future<bool> _deleteCloudRows(Set<String> ids, String expectedUserId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null || userId != expectedUserId) return false;
    await _supabase
        .from('user_quick_adds')
        .delete()
        .eq('user_id', userId)
        .inFilter('id', ids.toList());
    return true;
  }

  String generateUuid() {
    final random = Random.secure();
    final hex = List.generate(256, (i) => i.toRadixString(16).padLeft(2, '0'));
    final r = List.generate(16, (_) => random.nextInt(256));
    r[6] = (r[6] & 0x0f) | 0x40; // version 4
    r[8] = (r[8] & 0x3f) | 0x80; // variant RFC4122
    
    final buf = StringBuffer();
    for (int i = 0; i < 16; i++) {
      buf.write(hex[r[i]]);
      if (i == 3 || i == 5 || i == 7 || i == 9) {
        buf.write('-');
      }
    }
    return buf.toString();
  }
}
