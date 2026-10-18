import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/models/quick_add_item.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/services/account_deletion_service.dart';
import 'package:kynetix/services/cloud_sync_service.dart';
import 'package:kynetix/services/global_food_service.dart';
import 'package:kynetix/services/persistence_service.dart';
import 'package:kynetix/services/quick_add_service.dart';
import 'package:kynetix/services/user_session_coordinator.dart';
import 'package:kynetix/services/workout_service.dart';

/// Remote side of hydration, driven by the test. [fetchCore] completes only
/// when the test says so, which lets a session boundary land in between.
class _FakeSource extends CloudHydrationSource {
  _FakeSource(this.core);
  final CloudHydrationCore core;
  final gate = Completer<void>();
  int quickAddSyncs = 0;

  @override
  Future<CloudHydrationCore> fetchCore() async {
    await gate.future;
    return core;
  }

  @override
  Future<List<dynamic>> fetchAchievements() async => const [];

  @override
  Future<Map<String, dynamic>?> fetchInsightsCache() async => null;

  @override
  Future<void> syncQuickAdds(String userId, bool Function() stillCurrent) async {
    quickAddSyncs++;
  }

  @override
  Future<void> uploadSplit(WorkoutSplit split, List<Exercise> customExercises) async {}
}

Map<String, dynamic> _entryJson(String name, DateTime at) => MealEntry(
      rawInput: name,
      finalSavedInput: name,
      addedAt: at,
      section: MealSection.lunch,
      dayOfWeek: at.weekday,
      parsedFoods: [name],
      result: NutritionResult.createCustom(
        canonicalMeal: name,
        calories: 500,
        protein: 30,
        source: 'test',
        userCorrected: true,
      ),
    ).toJson();

CloudHydrationCore _remoteFor(String owner) => CloudHydrationCore(
      dayLogs: [
        {
          'date_key': '2026-10-01',
          'sections_json': {
            'lunch': [_entryJson('$owner cloud meal', DateTime(2026, 10, 1, 13))],
          },
          'target_calories': 2100,
          'target_protein': 140,
        },
      ],
      workouts: [
        {
          'id': '$owner-session-1',
          'date': DateTime(2026, 10, 1, 18).toIso8601String(),
          'split_day_name': 'Push',
          'entries_json': <dynamic>[],
        },
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userA = 'safety-user-a';
  const userB = 'safety-user-b';

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'https://mock.supabase.co', anonKey: 'mock-anon-key');
    await GlobalFoodService.instance.init(fetchRemote: false);
  });

  setUp(() async {
    await UserSessionCoordinator.instance.clearAllUserServices();
    QuickAddService.instance.cloudDeleterOverride = null;
  });

  Map<String, Object?> snapshot(SharedPreferences prefs) =>
      {for (final k in prefs.getKeys()) k: prefs.get(k)};

  // ── Bug 1: hydration after a session boundary ────────────────────────────
  group('cloud hydration never writes after the session ends', () {
    test("A's late hydration does not touch B's store, B's keys or legacy keys",
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final coordinator = UserSessionCoordinator.instance;

      await coordinator.initializeForUser(userA, prefsOverride: prefs);
      final source = _FakeSource(_remoteFor('A'));
      final hydration =
          CloudSyncService.instance.hydrateForUser(userA, source: source);

      // A signs out, B signs in, B logs a meal.
      await coordinator.clearAllUserServices();
      await coordinator.initializeForUser(userB, prefsOverride: prefs);
      logFor(DateTime(2026, 10, 2)).add(
        MealSection.lunch,
        MealEntry.fromJson(_entryJson('B own meal', DateTime(2026, 10, 2, 13))),
      );
      await PersistenceService.saveDayLogs();
      await PersistenceService.flushPendingWrites();
      final bStoreBefore = jsonEncode(
          {for (final e in dayLogStore.entries) e.key: e.value.toJson()});
      final keysBefore = snapshot(prefs);

      // A's remote fetch only completes now.
      source.gate.complete();
      await hydration;
      await PersistenceService.flushPendingWrites();

      final bStoreAfter = jsonEncode(
          {for (final e in dayLogStore.entries) e.key: e.value.toJson()});
      expect(bStoreAfter, bStoreBefore, reason: "B's in-memory store unchanged");
      expect(dayLogStore.containsKey('2026-10-01'), isFalse);
      expect(WorkoutService.instance.sessions.any((s) => s.id == 'A-session-1'),
          isFalse);
      expect(snapshot(prefs), keysBefore,
          reason: 'No key (B, A or legacy) was written by the late hydration');
      expect(prefs.getString('day_logs_v1'), isNull);
      expect(prefs.getString('workout_data_v2'), isNull);
      expect(source.quickAddSyncs, 0);
      expect(coordinator.isReadyFor(userB), isTrue);
    });

    test('a late hydration after plain sign-out writes no legacy keys', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final coordinator = UserSessionCoordinator.instance;

      await coordinator.initializeForUser(userA, prefsOverride: prefs);
      final source = _FakeSource(_remoteFor('A'));
      final hydration =
          CloudSyncService.instance.hydrateForUser(userA, source: source);
      await coordinator.clearAllUserServices();
      final keysBefore = snapshot(prefs);

      source.gate.complete();
      await hydration;
      await PersistenceService.flushPendingWrites();

      expect(dayLogStore, isEmpty);
      expect(snapshot(prefs), keysBefore);
      for (final k in UserSessionCoordinator.unscopedKeys) {
        expect(prefs.containsKey(k), isFalse, reason: '$k must not be written');
      }
    });

    test('a hydration that stays in its session still merges as before',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await UserSessionCoordinator.instance
          .initializeForUser(userA, prefsOverride: prefs);
      final source = _FakeSource(_remoteFor('A'))..gate.complete();

      await CloudSyncService.instance.hydrateForUser(userA, source: source);
      await PersistenceService.flushPendingWrites();

      final day = dayLogStore['2026-10-01'];
      expect(day, isNotNull);
      expect(day!.entriesFor(MealSection.lunch).single.rawInput, 'A cloud meal');
      expect(day.targetCalories, 2100);
      expect(WorkoutService.instance.sessions.any((s) => s.id == 'A-session-1'),
          isTrue);
      expect(prefs.getString('day_logs_v1_$userA'), contains('A cloud meal'));
      expect(prefs.getString('day_logs_v1'), isNull);
      expect(source.quickAddSyncs, 1);
    });
  });

  // ── Bug 2: removals reach the cloud ───────────────────────────────────────
  test('saveDayLogsAndSync saves as-is and schedules the cloud upload',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await UserSessionCoordinator.instance
        .initializeForUser(userA, prefsOverride: prefs);
    final date = DateTime(2026, 10, 3);
    final log = logFor(date);
    log.add(
      MealSection.lunch,
      MealEntry.fromJson(_entryJson('kept meal', DateTime(2026, 10, 3, 13))),
    );
    final before = PersistenceService.cloudSyncRequestCount;

    await PersistenceService.saveDayLogsAndSync(date);
    await PersistenceService.flushPendingWrites();

    expect(PersistenceService.cloudSyncRequestCount, before + 1,
        reason: 'The change must be scheduled for upload');
    // Nothing is back-filled: the day is stored exactly as it was.
    expect(log.gymDay, isNull);
    expect(log.targetCalories, isNull);
    final stored = jsonDecode(prefs.getString('day_logs_v1_$userA')!)
        as Map<String, dynamic>;
    expect(stored[dateKey(date)], log.toJson());
  });

  // ── Bug 3: account deletion and legacy data ──────────────────────────────
  group('account deletion and legacy (device-wide) data', () {
    Map<String, Object> legacyDevice() => {
          UserSessionCoordinator.legacyOwnerKey: userA,
          'day_logs_v1': '{"legacy":true}',
          'workout_data_v2': '{"sessions":[]}',
          'user_profile_v2': '{"name":"legacy"}',
          'backup_pre_migration_day_logs_v1': '{"legacy":true}',
          'backup_pre_migration_workout_data_v2': '{"sessions":[]}',
          'onboarding_done_v1': true,
          'quick_add_custom_items_v2': ['{"id":"q","name":"legacy shake"}'],
          'quick_add_custom_items': ['{"name":"older shake"}'],
          'carry_forward_resolved_dates_v1': ['2026-09-01'],
          'migration_verified_v1_$userA': true,
          'migration_verified_v1_$userB': true,
          'day_logs_v1_$userA': '{"a":true}',
          'day_logs_v1_$userB': '{"b":true}',
          'privacy_consent_v1_$userB': '{"version":"x"}',
          'ui_theme_mode_v1': 'dark',
          'memory_schema_v2_migrated': true,
        };

    test('owner deletion removes every legacy store and backup, keeps a '
        'sentinel claim, and leaves B and device settings alone', () async {
      SharedPreferences.setMockInitialValues(legacyDevice());
      final prefs = await SharedPreferences.getInstance();

      await AccountDeletionService.wipeLocalData(userA,
          prefsOverride: prefs, clearMemory: false);

      for (final k in [
        'day_logs_v1',
        'workout_data_v2',
        'user_profile_v2',
        'backup_pre_migration_day_logs_v1',
        'backup_pre_migration_workout_data_v2',
        'onboarding_done_v1',
        'quick_add_custom_items_v2',
        'quick_add_custom_items',
        'carry_forward_resolved_dates_v1',
      ]) {
        expect(prefs.containsKey(k), isFalse, reason: '$k must be removed');
      }
      expect(prefs.getKeys().where((k) => k.endsWith('_$userA')), isEmpty);
      expect(prefs.getString(UserSessionCoordinator.legacyOwnerKey),
          UserSessionCoordinator.legacyOwnerDeleted);
      expect(UserSessionCoordinator.legacyOwner(prefs),
          UserSessionCoordinator.legacyOwnerDeleted,
          reason: 'Never re-derived from B\'s migration marker');
      expect(prefs.getString('day_logs_v1_$userB'), '{"b":true}');
      expect(prefs.getString('privacy_consent_v1_$userB'), isNotNull);
      expect(prefs.getBool('migration_verified_v1_$userB'), isTrue);
      expect(prefs.getString('ui_theme_mode_v1'), 'dark');
      expect(prefs.getBool('memory_schema_v2_migrated'), isTrue);
    });

    test('after the owner is deleted, a new account never migrates leftovers',
        () async {
      SharedPreferences.setMockInitialValues({
        UserSessionCoordinator.legacyOwnerKey:
            UserSessionCoordinator.legacyOwnerDeleted,
        // Something unscoped re-appeared later; it belongs to nobody.
        'day_logs_v1': '{"2026-01-01":{}}',
        'quick_add_custom_items_v2': [
          '{"id":"q","name":"stray shake","calories":1,"protein":1,"emoji":"x","builtIn":false}'
        ],
      });
      final prefs = await SharedPreferences.getInstance();
      await UserSessionCoordinator.instance
          .initializeForUser('safety-user-c', prefsOverride: prefs);

      expect(prefs.getString('day_logs_v1_safety-user-c'), isNull);
      expect(dayLogStore.containsKey('2026-01-01'), isFalse);
      expect(QuickAddService.instance.customItems, isEmpty);
      expect(prefs.getString(UserSessionCoordinator.legacyOwnerKey),
          UserSessionCoordinator.legacyOwnerDeleted);
    });

    test('non-owner deletion keeps every legacy key for the owner', () async {
      SharedPreferences.setMockInitialValues(legacyDevice());
      final prefs = await SharedPreferences.getInstance();
      final legacyBefore = {
        for (final k in prefs.getKeys().where((k) => !k.endsWith('_$userB')))
          k: prefs.get(k),
      };

      await AccountDeletionService.wipeLocalData(userB,
          prefsOverride: prefs, clearMemory: false);

      expect({for (final k in prefs.getKeys()) k: prefs.get(k)}, legacyBefore);
      expect(UserSessionCoordinator.legacyOwner(prefs), userA);
    });
  });

  // ── Bug 4: Quick Add tombstones ──────────────────────────────────────────
  group('Quick Add deletions survive cloud sync', () {
    QuickAddItem item(String id, String name) => QuickAddItem(
          id: id,
          name: name,
          calories: 200,
          protein: 20,
          emoji: 'x',
          builtIn: false,
        );
    Map<String, dynamic> row(QuickAddItem i) => {
          'id': i.id,
          'name': i.name,
          'calories': i.calories,
          'protein': i.protein,
          'emoji': i.emoji,
        };

    test('an offline delete is not undone by a sync that still has the item',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final qa = QuickAddService.instance;
      await UserSessionCoordinator.instance
          .initializeForUser(userA, prefsOverride: prefs);
      final shake = item('qa-shake', 'Shake');
      final oats = item('qa-oats', 'Oats');
      await qa.saveItem(shake);
      await qa.saveItem(oats);

      var online = false;
      final deleteCalls = <Set<String>>[];
      qa.cloudDeleterOverride = (ids, uid) async {
        deleteCalls.add(ids);
        return online;
      };

      await qa.deleteItem(shake); // offline: cloud delete fails
      await qa.waitForCloudDeletes();
      expect(prefs.getStringList(QuickAddService.tombstoneKeyFor(userA)),
          ['qa-shake']);

      // Cloud still returns the deleted item.
      await qa.applyCloudItems(userA, [row(shake), row(oats)]);
      await qa.waitForCloudDeletes();
      expect(qa.customItems.map((i) => i.id), ['qa-oats']);
      expect(prefs.getStringList('quick_add_custom_items_v2_$userA')!.join(),
          isNot(contains('qa-shake')));
      expect(deleteCalls.length, greaterThanOrEqualTo(2),
          reason: 'The sync retries the cloud delete');

      // Survives a restart, then clears once the cloud delete lands.
      await UserSessionCoordinator.instance.clearAllUserServices();
      online = true;
      await UserSessionCoordinator.instance
          .initializeForUser(userA, prefsOverride: prefs);
      await qa.waitForCloudDeletes();
      expect(qa.deletedTombstones, isEmpty);
      expect(prefs.getStringList(QuickAddService.tombstoneKeyFor(userA)), isNull);
      expect(qa.customItems.map((i) => i.id), ['qa-oats']);
    });

    test("a sync for another user's session is dropped", () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await UserSessionCoordinator.instance
          .initializeForUser(userB, prefsOverride: prefs);
      final keysBefore = snapshot(prefs);
      await QuickAddService.instance
          .applyCloudItems(userA, [row(item('qa-a', 'A only'))]);
      expect(QuickAddService.instance.customItems, isEmpty);
      expect(snapshot(prefs), keysBefore);
    });
  });

  // ── Bug 5: carry-forward keys ─────────────────────────────────────────────
  test('carry-forward lists are per user; only the legacy owner reads the '
      'device-wide list', () async {
    SharedPreferences.setMockInitialValues({
      UserSessionCoordinator.legacyOwnerKey: userA,
      'carry_forward_resolved_dates_v1': ['2026-09-01'],
    });
    final prefs = await SharedPreferences.getInstance();
    const key = UserSessionCoordinator.kCarryForwardResolved;

    expect(UserSessionCoordinator.readCarryForwardList(prefs, key, userA),
        ['2026-09-01']);
    expect(UserSessionCoordinator.readCarryForwardList(prefs, key, userB),
        isNull);
    expect(UserSessionCoordinator.carryForwardWriteKey(key, userB),
        'carry_forward_resolved_dates_v1_$userB');
    expect(UserSessionCoordinator.carryForwardWriteKey(key, null), key);

    await prefs.setStringList(
        UserSessionCoordinator.carryForwardWriteKey(key, userA), ['2026-10-01']);
    expect(UserSessionCoordinator.readCarryForwardList(prefs, key, userA),
        ['2026-10-01']);
  });
}
