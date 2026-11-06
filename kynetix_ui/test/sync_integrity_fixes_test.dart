import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/models/workout_session.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/services/cloud_sync_service.dart';
import 'package:kynetix/services/eating_pattern_service.dart';
import 'package:kynetix/services/food_role_classifier.dart';
import 'package:kynetix/services/global_food_service.dart';
import 'package:kynetix/services/persistence_service.dart';
import 'package:kynetix/services/user_session_coordinator.dart';
import 'package:kynetix/services/workout_service.dart';

// Sync and local-storage integrity: workouts and days that failed to upload
// are retried, hydration reads every page and survives bad rows, trimming
// keeps the newest workouts, unreadable local data is never written over,
// and pattern resets stick.

/// The cloud, as the background sync sees it. Failures are switched on per
/// call type; every call is recorded.
class _FakeRemote extends CloudSyncRemote {
  _FakeRemote(this.userId);
  String? userId;
  bool failUpserts = false;
  bool failDeletes = false;
  bool failDayMerges = false;
  bool failPatternDeletes = false;
  final upserted = <Map<String, dynamic>>[];
  final deletedIds = <String>[];
  final mergedDays = <String>[];
  final patternDeletes = <String>[];
  int inFlightMerges = 0;
  int maxInFlightMerges = 0;
  Duration mergeDelay = Duration.zero;

  @override
  String? get currentUserId => userId;

  @override
  Future<void> upsertWorkouts(List<Map<String, dynamic>> rows) async {
    if (failUpserts) throw StateError('offline');
    upserted.addAll(rows);
  }

  @override
  Future<void> deleteWorkouts(String userId, List<String> ids) async {
    if (failDeletes) throw StateError('offline');
    deletedIds.addAll(ids);
  }

  @override
  Future<void> mergeDayLog(Map<String, dynamic> params) async {
    inFlightMerges++;
    if (inFlightMerges > maxInFlightMerges) maxInFlightMerges = inFlightMerges;
    try {
      await Future<void>.delayed(mergeDelay);
      if (failDayMerges) throw StateError('offline');
      mergedDays.add(params['p_date_key'] as String);
    } finally {
      inFlightMerges--;
    }
  }

  @override
  Future<void> deleteEatingPatterns(String userId,
      {required DateTime before, String? targetRole, String? contextRole}) async {
    if (failPatternDeletes) throw StateError('offline');
    patternDeletes.add('${targetRole ?? '*'}|${contextRole ?? ''}');
  }

  @override
  Future<void> deleteMealContexts(String userId, {required DateTime before}) async {
    if (failPatternDeletes) throw StateError('offline');
    patternDeletes.add('contexts');
  }
}

class _FakeSource extends CloudHydrationSource {
  _FakeSource(this.core);
  final CloudHydrationCore core;

  @override
  Future<CloudHydrationCore> fetchCore() async => core;

  @override
  Future<List<dynamic>> fetchAchievements() async => const [];

  @override
  Future<Map<String, dynamic>?> fetchInsightsCache() async => null;

  @override
  Future<void> syncQuickAdds(String userId, bool Function() stillCurrent) async {}

  @override
  Future<void> uploadSplit(WorkoutSplit split, List<Exercise> customExercises) async {}

  @override
  Future<bool> deleteWorkouts(Set<String> ids, String userId) async => false;
}

const _user = 'sync-integrity-user';

MealEntry _meal(String name, DateTime at) => MealEntry(
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
    );

DayLog _day(String name, DateTime at) => DayLog()
  ..add(MealSection.lunch, _meal(name, at))
  ..targetCalories = 2000
  ..targetProtein = 140;

WorkoutSession _session(String id, DateTime date) =>
    WorkoutSession(id: id, date: date, splitDayName: 'Push', entries: const []);

String _workoutStore(List<WorkoutSession> sessions) => jsonEncode({
      'setupDone': true,
      'sessions': sessions.map((s) => s.toJson()).toList(),
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeRemote remote;
  final errors = <String>[];

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'https://mock.supabase.co', anonKey: 'mock-anon-key');
    await GlobalFoodService.instance.init(fetchRemote: false);
  });

  setUp(() async {
    await UserSessionCoordinator.instance.clearAllUserServices();
    remote = _FakeRemote(_user);
    CloudSyncService.instance.remote = remote;
    errors.clear();
    PersistenceService.debugErrorSink = (what, _) => errors.add(what);
  });

  tearDown(() async {
    // Let fire-and-forget syncs settle before the next test swaps the fakes.
    await CloudSyncService.instance.syncPendingWorkouts();
    await CloudSyncService.instance.syncDayLogsBackground();
    CloudSyncService.instance.remote = const CloudSyncRemote();
    PersistenceService.debugSetStringOverride = null;
    PersistenceService.debugErrorSink = null;
  });

  Future<SharedPreferences> signIn([Map<String, Object> stored = const {}]) async {
    SharedPreferences.setMockInitialValues(stored);
    final prefs = await SharedPreferences.getInstance();
    await UserSessionCoordinator.instance.initializeForUser(_user, prefsOverride: prefs);
    return prefs;
  }

  Future<void> relaunch(SharedPreferences prefs) async {
    await UserSessionCoordinator.instance.clearAllUserServices();
    await UserSessionCoordinator.instance.initializeForUser(_user, prefsOverride: prefs);
  }

  // ── 1. Workout uploads and deletes are retried ────────────────────────────
  group('workout upload retry', () {
    test('a workout whose upload fails stays queued, on disk, until it lands',
        () async {
      final prefs = await signIn();
      remote.failUpserts = true;
      await WorkoutService.instance.saveSession(_session('ws_1', DateTime(2026, 11, 1, 18)));
      await CloudSyncService.instance.syncPendingWorkouts();

      expect(remote.upserted, isEmpty);
      expect(WorkoutService.instance.unsyncedSessionIds, {'ws_1'});
      expect(prefs.getStringList('workout_unsynced_session_ids_v1_$_user'), ['ws_1']);

      // Restart: the queue survives, and the next drain uploads it.
      await relaunch(prefs);
      expect(WorkoutService.instance.unsyncedSessionIds, {'ws_1'});
      remote.failUpserts = false;
      CloudSyncService.instance.drainPendingUploads();
      await CloudSyncService.instance.syncPendingWorkouts();

      expect(remote.upserted.map((r) => r['id']), ['ws_1']);
      expect(WorkoutService.instance.unsyncedSessionIds, isEmpty);
      expect(prefs.getStringList('workout_unsynced_session_ids_v1_$_user'), isEmpty);
    });

    test('a session saved again while its upload runs stays queued', () async {
      await signIn();
      remote.failUpserts = true;
      final first = _session('ws_2', DateTime(2026, 11, 2, 18));
      await WorkoutService.instance.saveSession(first);
      // Edited copy saved after the first copy was uploaded.
      final edited = WorkoutSession(
          id: 'ws_2', date: first.date, splitDayName: 'Push', entries: const [],
          notes: 'edited');
      await WorkoutService.instance.saveSession(edited);
      await WorkoutService.instance.markSessionsSynced([first], userId: _user);
      expect(WorkoutService.instance.unsyncedSessionIds, {'ws_2'});
      await WorkoutService.instance.markSessionsSynced([edited], userId: _user);
      expect(WorkoutService.instance.unsyncedSessionIds, isEmpty);
    });

    test('an unconfirmed delete is retried and never evicted by the cap',
        () async {
      final old = [for (var i = 0; i < 500; i++) 'old_$i'];
      final prefs = await signIn({
        'workout_data_v2_$_user': _workoutStore([_session('ws_x', DateTime(2026, 11, 3))]),
        'workout_unsynced_session_ids_v1_$_user': <String>[],
        'workout_deleted_session_ids_v1_$_user': old,
        // Older build: no confirmation list, so every tombstone is unconfirmed.
      });
      expect(WorkoutService.instance.unconfirmedDeleteIds, hasLength(500));

      remote.failDeletes = true;
      await WorkoutService.instance.deleteSession('ws_x');
      await CloudSyncService.instance.syncPendingWorkouts();
      final ws = WorkoutService.instance;
      expect(ws.deletedSessionIds, hasLength(501),
          reason: 'over the cap, but nothing unconfirmed may be dropped');
      expect(ws.deletedSessionIds.first, 'old_0');
      expect(ws.unconfirmedDeleteIds, contains('ws_x'));
      expect(prefs.getStringList('workout_unconfirmed_delete_ids_v1_$_user'),
          contains('ws_x'));

      remote.failDeletes = false;
      await CloudSyncService.instance.syncPendingWorkouts();
      expect(remote.deletedIds, containsAll(['ws_x', 'old_0']));
      expect(ws.unconfirmedDeleteIds, isEmpty);
      expect(ws.deletedSessionIds, hasLength(500));
      expect(ws.isSessionDeleted('ws_x'), isTrue,
          reason: 'the newest tombstone still hides the session');
    });
  });

  // ── 2. Hydration reads every page ─────────────────────────────────────────
  group('paged hydration reads', () {
    test('reads until a short page, in order', () async {
      final calls = <String>[];
      final rows = await CloudSyncService.fetchAllPages((from, to) async {
        calls.add('$from-$to');
        return [for (var i = from; i <= to && i < 2500; i++) i];
      }, what: 'test');
      expect(rows, [for (var i = 0; i < 2500; i++) i]);
      expect(calls, ['0-999', '1000-1999', '2000-2999']);
    });

    test('an exact multiple of the page size needs one empty page', () async {
      var pages = 0;
      final rows = await CloudSyncService.fetchAllPages((from, to) async {
        pages++;
        return [for (var i = from; i <= to && i < 2000; i++) i];
      }, what: 'test');
      expect(rows, hasLength(2000));
      expect(pages, 3);
    });

    test('each page has its own timeout, not one for the whole read', () async {
      final rows = await CloudSyncService.fetchAllPages((from, to) async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return [for (var i = from; i <= to && i < 50; i++) i];
      }, what: 'test', size: 10, perPage: const Duration(milliseconds: 200));
      expect(rows, hasLength(50), reason: '6 pages take longer than one timeout');

      await expectLater(
        CloudSyncService.fetchAllPages((from, to) async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          return const [];
        }, what: 'test', perPage: const Duration(milliseconds: 50)),
        throwsA(isA<TimeoutException>()),
      );
    });
  });

  // ── 3. Ordering and the 200-session cap ───────────────────────────────────
  group('session ordering and trimming', () {
    test('cloud sessions are sorted in by date, and the oldest are trimmed',
        () async {
      final base = DateTime(2026, 1, 1, 18);
      final local = [for (var i = 0; i < 200; i++) _session('l$i', base.add(Duration(days: i)))];
      await signIn({
        'workout_data_v2_$_user': _workoutStore(local),
        'workout_unsynced_session_ids_v1_$_user': <String>['l0'],
      });
      final ws = WorkoutService.instance;
      // Newest cloud sessions arrive out of order, plus one older than all.
      await ws.bulkImportCloudSessions([
        _session('c2', base.add(const Duration(days: 300))),
        _session('c1', base.add(const Duration(days: 250))),
        _session('ancient', DateTime(2020, 1, 1)),
      ]);
      final ids = ws.sessions.map((s) => s.id).toList();
      expect(ids, hasLength(200));
      expect(ids.last, 'c2');
      expect(ids[ids.length - 2], 'c1');
      expect(ids, isNot(contains('ancient')));
      expect(ids.first, 'l0', reason: 'not uploaded yet: never trimmed');
      expect(ids, isNot(contains('l1')));
      expect(ids, isNot(contains('l2')));
      final dates = ws.sessions.map((s) => s.date).toList();
      for (var i = 1; i < dates.length; i++) {
        expect(dates[i].isBefore(dates[i - 1]), isFalse);
      }
    });

    test('stored sessions from older builds are queued once and sorted', () async {
      await signIn({
        'workout_data_v2_$_user': _workoutStore([
          _session('b', DateTime(2026, 5, 2)),
          _session('a', DateTime(2026, 5, 1)),
        ]),
      });
      expect(WorkoutService.instance.sessions.map((s) => s.id), ['a', 'b']);
      expect(WorkoutService.instance.unsyncedSessionIds, {'a', 'b'});
    });
  });

  // ── 4 / 10. Timestamps go up in UTC; dedupe compares instants ─────────────
  group('timestamps', () {
    test('workout updated_at is uploaded in UTC', () {
      final row = CloudSyncService.workoutRow(
          _session('w', DateTime(2026, 11, 1, 18)), _user,
          now: DateTime(2026, 11, 1, 19, 30));
      final updatedAt = row['updated_at'] as String;
      expect(updatedAt.endsWith('Z'), isTrue);
      expect(DateTime.parse(updatedAt).isAtSameMomentAs(DateTime(2026, 11, 1, 19, 30)),
          isTrue);
    });

    test('correction and context records upload recorded_at in UTC', () async {
      await signIn();
      final eps = EatingPatternService.instance;
      final at = DateTime(2026, 11, 1, 9, 15);
      eps.recordIngredientCorrection(
          correctedItemRole: FoodRole.accompaniment, mealHasPrimary: true,
          pipelineCalEstimate: 200, userCorrectedCal: 150, timestamp: at);
      final recorded = eps.exportForCloudSync().single['recorded_at'] as String;
      expect(recorded.endsWith('Z'), isTrue);
      expect(DateTime.parse(recorded).isAtSameMomentAs(at), isTrue);
    });

    test('a correction coming back from the cloud is not counted twice',
        () async {
      await signIn();
      final eps = EatingPatternService.instance;
      final at = DateTime(2026, 11, 1, 9, 15, 7);
      eps.recordIngredientCorrection(
          correctedItemRole: FoodRole.accompaniment, mealHasPrimary: true,
          pipelineCalEstimate: 200, userCorrectedCal: 150, timestamp: at);
      String wallClockAsUtc(DateTime t) =>
          '${t.toIso8601String().substring(0, 23)}+00:00';
      eps.mergeFromCloud([
        // This build's upload, read back as an instant.
        {'target_role': 'accompaniment', 'context_role': 'primary', 'ratio': 0.75,
         'recorded_at': at.toUtc().toIso8601String()},
        // An older build's upload: local wall-clock time stored as UTC.
        {'target_role': 'accompaniment', 'context_role': 'primary', 'ratio': 0.75,
         'recorded_at': wallClockAsUtc(at)},
      ]);
      expect(eps.getSampleCount(FoodRole.accompaniment, contextRole: FoodRole.primary), 1);
    });
  });

  // ── 5. Only changed days are uploaded, and a failed upload is retried ─────
  group('dirty days', () {
    Map<String, Object> storeOf(Map<String, DayLog> days, {List<String>? dirty}) => {
          'day_logs_v1_$_user': jsonEncode({for (final e in days.entries) e.key: e.value.toJson()}),
          'day_logs_dirty_v1_$_user': ?dirty,
        };

    test('a save uploads only the day that changed', () async {
      final days = {
        for (var d = 1; d <= 30; d++)
          dateKey(DateTime(2026, 10, d)): _day('meal $d', DateTime(2026, 10, d, 13)),
      };
      final prefs = await signIn(storeOf(days, dirty: const []));
      expect(PersistenceService.daysNeedingUpload(_user), isEmpty);

      final day = DateTime(2026, 10, 7);
      logFor(day).add(MealSection.dinner, _meal('late snack', DateTime(2026, 10, 7, 21)));
      await PersistenceService.saveDay(day);
      await CloudSyncService.instance.syncDayLogsBackground();

      expect(remote.mergedDays, [dateKey(day)]);
      expect(PersistenceService.daysNeedingUpload(_user), isEmpty);
      expect(prefs.getStringList('day_logs_dirty_v1_$_user'), isEmpty);
    });

    test('a failed day upload stays dirty across a restart', () async {
      final prefs = await signIn(storeOf(const {}, dirty: const []));
      remote.failDayMerges = true;
      final day = DateTime(2026, 10, 8);
      logFor(day).add(MealSection.lunch, _meal('rice', DateTime(2026, 10, 8, 13)));
      await PersistenceService.saveDay(day);
      await CloudSyncService.instance.syncDayLogsBackground();
      expect(prefs.getStringList('day_logs_dirty_v1_$_user'), [dateKey(day)]);

      await relaunch(prefs);
      remote.failDayMerges = false;
      await CloudSyncService.instance.syncDayLogsBackground();
      expect(remote.mergedDays, [dateKey(day)]);
      expect(prefs.getStringList('day_logs_dirty_v1_$_user'), isEmpty);
    });

    test('at most four day uploads run at once', () async {
      final days = {
        for (var d = 1; d <= 12; d++)
          dateKey(DateTime(2026, 9, d)): _day('meal $d', DateTime(2026, 9, d, 13)),
      };
      await signIn(storeOf(days)); // no dirty list yet: every day is dirty
      remote.mergeDelay = const Duration(milliseconds: 5);
      await CloudSyncService.instance.syncDayLogsBackground();
      expect(remote.mergedDays, hasLength(12));
      expect(remote.maxInFlightMerges, lessThanOrEqualTo(4));
      expect(remote.maxInFlightMerges, greaterThan(1));
    });

    test('after hydration, days identical to the cloud are clean', () async {
      final same = DateTime(2026, 8, 1);
      final differs = DateTime(2026, 8, 2);
      final days = {
        dateKey(same): _day('oats', DateTime(2026, 8, 1, 8)),
        dateKey(differs): _day('dal', DateTime(2026, 8, 2, 13)),
      };
      final prefs = await signIn(storeOf(days)); // upgrade: all dirty
      expect(PersistenceService.daysNeedingUpload(_user), hasLength(2));
      remote.failDayMerges = true; // keep the drain from cleaning anything
      Map<String, dynamic> rowFor(String key, DayLog log) => {
            'date_key': key,
            'sections_json': {
              for (final s in MealSection.values)
                if (log.entriesFor(s).isNotEmpty)
                  s.name: log.entriesFor(s).map((e) => e.toJson()).toList(),
            },
            'target_calories': log.targetCalories,
            'target_protein': log.targetProtein,
          };
      await CloudSyncService.instance.hydrateForUser(_user,
          source: _FakeSource(CloudHydrationCore(dayLogs: [
            rowFor(dateKey(same), days[dateKey(same)]!),
            // The cloud lacks this day's meal: it still has to go up.
            {'date_key': dateKey(differs), 'sections_json': <String, dynamic>{},
             'target_calories': 2000, 'target_protein': 140},
          ])));
      await PersistenceService.flushPendingWrites();
      expect(PersistenceService.daysNeedingUpload(_user), {dateKey(differs)});
      expect(prefs.getStringList('day_logs_dirty_v1_$_user'), [dateKey(differs)]);
    });
  });

  // ── 6 / 7. Unreadable or unwritable local day logs ────────────────────────
  group('local day-log storage', () {
    test('one unreadable day is skipped, backed up and kept on disk', () async {
      final good = dateKey(DateTime(2026, 7, 1));
      final raw = '{"$good":${jsonEncode(_day('eggs', DateTime(2026, 7, 1, 8)).toJson())},'
          '"2026-07-02":{"sections":"not a map"}}';
      final prefs = await signIn({'day_logs_v1_$_user': raw});

      expect(dayLogStore.keys, [good]);
      expect(errors, isNotEmpty);
      final backups = prefs.getKeys()
          .where((k) => k.startsWith('day_logs_v1_corrupt_') && k.endsWith('_$_user'));
      expect(backups, hasLength(1));
      expect(prefs.getString(backups.single), contains('2026-07-02'));

      // A save keeps the unreadable day verbatim.
      await PersistenceService.saveDay(DateTime(2026, 7, 1));
      await PersistenceService.flushPendingWrites();
      final stored = jsonDecode(prefs.getString('day_logs_v1_$_user')!) as Map;
      expect(stored.keys, containsAll([good, '2026-07-02']));
      expect(stored['2026-07-02'], {'sections': 'not a map'});

      // Launching again does not pile up identical backups.
      await relaunch(prefs);
      expect(prefs.getKeys().where((k) => k.startsWith('day_logs_v1_corrupt_')),
          hasLength(1));
    });

    test('an unreadable store is never written over without a backup', () async {
      const raw = '{"2026-07-01": {broken';
      PersistenceService.debugSetStringOverride = (key, value) async =>
          key.contains('_corrupt_') ? false : throw StateError('unexpected write to $key');
      final prefs = await signIn({'day_logs_v1_$_user': raw});
      expect(PersistenceService.dayLogsWriteBlockedFor(_user), isTrue);

      logFor(DateTime(2026, 7, 3)).add(MealSection.lunch, _meal('new', DateTime(2026, 7, 3, 13)));
      await PersistenceService.saveDayLogs();
      expect(prefs.getString('day_logs_v1_$_user'), raw);
      expect(errors.any((e) => e.contains('not saved')), isTrue);
    });

    test('with a verified backup, saving resumes', () async {
      const raw = 'not json at all';
      final prefs = await signIn({'day_logs_v1_$_user': raw});
      expect(PersistenceService.dayLogsWriteBlockedFor(_user), isFalse);
      final backup = prefs.getKeys().singleWhere((k) => k.startsWith('day_logs_v1_corrupt_'));
      expect(prefs.getString(backup), raw);

      logFor(DateTime(2026, 7, 3)).add(MealSection.lunch, _meal('new', DateTime(2026, 7, 3, 13)));
      await PersistenceService.saveDayLogs();
      expect(prefs.getString('day_logs_v1_$_user'), contains('new'));
    });

    test('a rejected disk write is reported and retried on the next flush',
        () async {
      final prefs = await signIn();
      var reject = true;
      PersistenceService.debugSetStringOverride =
          (key, value) async => reject ? false : prefs.setString(key, value);
      final day = DateTime(2026, 7, 4);
      logFor(day).add(MealSection.lunch, _meal('paneer', DateTime(2026, 7, 4, 13)));
      await PersistenceService.saveDayLogs();
      expect(prefs.getString('day_logs_v1_$_user'), isNull);
      expect(errors.any((e) => e.contains('rejected')), isTrue);
      expect(PersistenceService.daysNeedingUpload(_user), {dateKey(day)},
          reason: 'still owed to the cloud');

      reject = false;
      await PersistenceService.flushAll();
      expect(prefs.getString('day_logs_v1_$_user'), contains('paneer'));
    });
  });

  // ── 8. One bad cloud row does not stop hydration ──────────────────────────
  test('hydration skips malformed rows and keeps going', () async {
    await signIn();
    await CloudSyncService.instance.hydrateForUser(_user,
        source: _FakeSource(CloudHydrationCore(
          dayLogs: [
            {'sections_json': <String, dynamic>{}}, // no date_key
            {
              'date_key': '2026-06-02',
              'sections_json': {'lunch': [_meal('cloud dal', DateTime(2026, 6, 2, 13)).toJson()]},
            },
          ],
          workouts: [
            {'id': 'bad', 'date': 'not a date', 'split_day_name': 'Push'},
            {'id': 'good', 'date': DateTime(2026, 6, 2, 18).toIso8601String(),
             'split_day_name': 'Pull', 'entries_json': <dynamic>[]},
          ],
        )));
    expect(dayLogStore['2026-06-02']?.entriesFor(MealSection.lunch).single.rawInput,
        'cloud dal');
    expect(WorkoutService.instance.sessions.map((s) => s.id), ['good']);
  });

  // ── 9. Pattern resets stick, also offline ─────────────────────────────────
  group('eating pattern resets', () {
    Map<String, dynamic> row(DateTime at, {String role = 'accompaniment'}) => {
          'target_role': role, 'context_role': 'primary', 'ratio': 0.6,
          'pipeline_estimate': 200.0, 'user_corrected_cal': 120.0,
          'recorded_at': at.toUtc().toIso8601String(),
        };

    test('reset survives an offline cloud delete, a restart and hydration',
        () async {
      final prefs = await signIn();
      final eps = EatingPatternService.instance;
      final before = DateTime.now().subtract(const Duration(days: 2));
      eps.mergeFromCloud([row(before), row(before.add(const Duration(minutes: 1)))]);
      expect(eps.getSampleCount(FoodRole.accompaniment, contextRole: FoodRole.primary), 2);

      remote.failPatternDeletes = true;
      await CloudSyncService.instance.resetEatingPattern(FoodRole.accompaniment,
          contextRole: FoodRole.primary);
      await CloudSyncService.instance.syncPendingPatternResets();
      expect(eps.getSampleCount(FoodRole.accompaniment, contextRole: FoodRole.primary), 0);
      expect(eps.pendingCloudResets, hasLength(1));

      // Restart; the cloud still has the old rows (delete never landed).
      await relaunch(prefs);
      final eps2 = EatingPatternService.instance;
      // Well past the reset (more than any time-zone offset).
      final later = DateTime.now().add(const Duration(days: 1));
      eps2.mergeFromCloud([row(before), row(later)]);
      expect(eps2.getSampleCount(FoodRole.accompaniment, contextRole: FoodRole.primary), 1,
          reason: 'only the correction made after the reset');

      remote.failPatternDeletes = false;
      CloudSyncService.instance.drainPendingUploads();
      await CloudSyncService.instance.syncPendingPatternResets();
      expect(remote.patternDeletes, ['accompaniment|primary']);
      expect(eps2.pendingCloudResets, isEmpty);
    });

    test('clear all deletes patterns and contexts from the cloud', () async {
      await signIn();
      final eps = EatingPatternService.instance;
      final before = DateTime.now().subtract(const Duration(days: 1));
      eps.mergeFromCloud([row(before), row(before, role: 'primary')]);
      await CloudSyncService.instance.resetAllEatingPatterns();
      await CloudSyncService.instance.syncPendingPatternResets();
      expect(remote.patternDeletes, ['*|', 'contexts']);
      eps.mergeFromCloud([row(before), row(before, role: 'primary')]);
      eps.mergeContextsFromCloud([
        {'primary_food_names': ['rice'], 'recorded_at': before.toUtc().toIso8601String()},
      ]);
      expect(eps.allLearned, isEmpty);
      expect(eps.totalMealsTracked, 0);
    });
  });
}
