import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/models/user_profile.dart';
import 'package:kynetix/models/workout_session.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/services/cloud_sync_service.dart';
import 'package:kynetix/services/global_food_service.dart';
import 'package:kynetix/services/internal/net_timeouts.dart';
import 'package:kynetix/services/internal/scoped_prefs.dart';
import 'package:kynetix/services/nutrition_target_engine.dart';
import 'package:kynetix/services/profile_service.dart';
import 'package:kynetix/services/user_nutrition_memory.dart';
import 'package:kynetix/services/user_session_coordinator.dart';
import 'package:kynetix/services/workout_service.dart';

class _FakeSource extends CloudHydrationSource {
  _FakeSource(this.core);
  final CloudHydrationCore core;
  final deleted = <String>{};

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
  Future<bool> deleteWorkouts(Set<String> ids, String userId) async {
    deleted.addAll(ids);
    return true;
  }
}

WorkoutSession _session(String id, DateTime date) =>
    WorkoutSession(id: id, date: date, splitDayName: 'Push', entries: const []);

Map<String, dynamic> _row(String id, DateTime date) => {
      'id': id,
      'date': date.toIso8601String(),
      'split_day_name': 'Push',
      'entries_json': <dynamic>[],
    };

String _workoutBlob(List<WorkoutSession> sessions) => jsonEncode({
      'setupDone': true,
      'sessions': sessions.map((s) => s.toJson()).toList(),
    });

UserProfile _profile() => const UserProfile(
      name: 'T',
      age: 30,
      gender: 'Male',
      height: 178,
      weight: 78,
      workoutDaysMin: 3,
      workoutDaysMax: 4,
      goal: 'Maintenance',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const owner = 'legacy-owner';
  const other = 'second-account';

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'https://mock.supabase.co', anonKey: 'mock-anon-key');
    await GlobalFoodService.instance.init(fetchRemote: false);
  });

  setUp(() async {
    await UserSessionCoordinator.instance.clearAllUserServices();
    WorkoutService.debugWriteOverride = null;
  });

  // ── 1. Legacy unscoped keys belong to their one owner ─────────────────────
  group('legacy unscoped keys', () {
    test('ScopedPrefs: only the legacy owner (or no user) reads them', () async {
      SharedPreferences.setMockInitialValues({
        UserSessionCoordinator.legacyOwnerKey: owner,
        'k': 'legacy',
        'k_$other': 'mine',
      });
      final prefs = await SharedPreferences.getInstance();
      expect(ScopedPrefs.getString(prefs, 'k', owner), 'legacy');
      expect(ScopedPrefs.getString(prefs, 'k', 'third'), isNull);
      expect(ScopedPrefs.getString(prefs, 'k', other), 'mine');
      expect(ScopedPrefs.getString(prefs, 'k', null), 'legacy');
      expect(ScopedPrefs.key('k', other), 'k_$other');
      expect(ScopedPrefs.key('k', null), 'k');
    });

    test('nobody claimed the legacy keys: a signed-in user does not read them',
        () async {
      SharedPreferences.setMockInitialValues({'k': 'legacy'});
      final prefs = await SharedPreferences.getInstance();
      expect(ScopedPrefs.getString(prefs, 'k', other), isNull);
    });

    test('a second account inherits no workouts, health or nutrition memory; '
        'the owner still reads theirs and nothing is deleted', () async {
      final legacy = <String, Object>{
        UserSessionCoordinator.legacyOwnerKey: owner,
        'migration_verified_v1_$owner': true,
        'migration_verified_v1_$other': true,
        'workout_data_v2': _workoutBlob([_session('legacy-1', DateTime(2026, 9, 1))]),
        'kynetix_sleep_hours_v1': 7.5,
        'kynetix_readiness_history_v1': jsonEncode({'2026-09-01': 0.4}),
        'personal_nutrition_memory_v1': jsonEncode({}),
        'user_meal_overrides_v1': <String>[
          jsonEncode(UserMealOverride(
            canonicalMeal: 'legacy dal',
            caloriesPerUnit: 300,
            proteinPerUnit: 12,
            referenceQuantity: 1,
            referenceUnit: 'bowl',
            savedAt: DateTime(2026, 9, 1),
          ).toJson()),
        ],
        'eating_patterns_v1': jsonEncode([]),
      };
      SharedPreferences.setMockInitialValues(Map.of(legacy));
      final prefs = await SharedPreferences.getInstance();
      final coordinator = UserSessionCoordinator.instance;

      await coordinator.initializeForUser(other, prefsOverride: prefs);
      expect(WorkoutService.instance.sessions, isEmpty);
      expect(WorkoutService.instance.sleepHours, isNull);
      expect(UserNutritionMemory.instance.allOverrides, isEmpty);

      await coordinator.clearAllUserServices();
      await coordinator.initializeForUser(owner, prefsOverride: prefs);
      expect(WorkoutService.instance.sessions.map((s) => s.id), ['legacy-1']);
      expect(WorkoutService.instance.sleepHours, 7.5);
      expect(UserNutritionMemory.instance.allOverrides.map((o) => o.canonicalMeal),
          contains('legacy dal'));
      await coordinator.clearAllUserServices();

      for (final e in legacy.entries) {
        expect(prefs.get(e.key), e.value, reason: '${e.key} must be untouched');
      }
    });

    test('recovery and health keys are written per user', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await UserSessionCoordinator.instance.initializeForUser(other, prefsOverride: prefs);
      final ws = WorkoutService.instance;
      expect(ws.recoveryPrefKey, 'kynetix_workout_recovery_$other');
      await ws.updateSleepAndHrv(sleepHours: 6.0, hrvRmssd: 40, hrvBaseline: 45);
      expect(prefs.getDouble('kynetix_sleep_hours_v1_$other'), 6.0);
      expect(prefs.getDouble('kynetix_sleep_hours_v1'), isNull);
      expect(prefs.getString('kynetix_readiness_history_v1_$other'), isNotNull);
      expect(prefs.getString('kynetix_readiness_history_v1'), isNull);
    });
  });

  // ── 2. Deleted workouts stay deleted ──────────────────────────────────────
  group('deleted workouts', () {
    test('hydration skips a deleted id and retries its cloud delete', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final coordinator = UserSessionCoordinator.instance;
      await coordinator.initializeForUser(other, prefsOverride: prefs);
      final ws = WorkoutService.instance;
      final day = DateTime(2026, 10, 2, 18);
      await ws.saveSession(_session('gone', day));
      await ws.saveSession(_session('kept', day));
      await ws.deleteSession('gone');
      expect(ws.isSessionDeleted('gone'), isTrue);

      // Tombstone survives a restart.
      await coordinator.clearAllUserServices();
      await coordinator.initializeForUser(other, prefsOverride: prefs);
      expect(WorkoutService.instance.isSessionDeleted('gone'), isTrue);

      final source = _FakeSource(CloudHydrationCore(workouts: [
        _row('gone', day),
        _row('kept', day),
        _row('cloud-only', day),
      ]));
      await CloudSyncService.instance.hydrateForUser(other, source: source);
      final ids = WorkoutService.instance.sessions.map((s) => s.id).toSet();
      expect(ids, {'kept', 'cloud-only'});
      expect(source.deleted, {'gone'});
    });

    test('saving the same id again lifts the tombstone', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await UserSessionCoordinator.instance.initializeForUser(other, prefsOverride: prefs);
      final ws = WorkoutService.instance;
      final s = _session('undo-me', DateTime(2026, 10, 3));
      await ws.saveSession(s);
      await ws.deleteSession('undo-me');
      await ws.saveSession(s);
      expect(ws.isSessionDeleted('undo-me'), isFalse);
    });
  });

  // ── 3. Workout write chain ────────────────────────────────────────────────
  group('workout write chain', () {
    test('saveSession surfaces a failed disk write', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await UserSessionCoordinator.instance.initializeForUser(other, prefsOverride: prefs);
      WorkoutService.debugWriteOverride = (_, _) async => throw StateError('disk full');
      await expectLater(
        WorkoutService.instance.saveSession(_session('s1', DateTime(2026, 10, 4))),
        throwsA(isA<StateError>()),
      );
      WorkoutService.debugWriteOverride = null;
    });

    test('a write queued behind an in-flight one lands under the key and with '
        'the state of the session that asked for it', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final coordinator = UserSessionCoordinator.instance;
      await coordinator.initializeForUser(other, prefsOverride: prefs);
      final ws = WorkoutService.instance;

      final gate = Completer<void>();
      final writes = <String, String>{};
      WorkoutService.debugWriteOverride = (key, json) async {
        if (!gate.isCompleted) await gate.future;
        writes[key] = json;
      };
      final first = ws.saveSession(_session('a', DateTime(2026, 10, 5)));
      final second = ws.saveSession(_session('b', DateTime(2026, 10, 5)));
      // Sign-out while both writes are pending.
      ws.clearMemory();
      gate.complete();
      await first;
      await second;
      await ws.flushPendingWrites();
      WorkoutService.debugWriteOverride = null;

      expect(writes.keys, ['workout_data_v2_$other']);
      final saved = (jsonDecode(writes['workout_data_v2_$other']!)
          as Map<String, dynamic>)['sessions'] as List<dynamic>;
      expect(saved.map((s) => (s as Map)['id']), ['a', 'b']);
      expect(prefs.getString('workout_data_v2'), isNull);
    });

    test('nothing is written while no store is loaded', () async {
      SharedPreferences.setMockInitialValues({'workout_data_v2': 'legacy'});
      final prefs = await SharedPreferences.getInstance();
      final ws = WorkoutService.instance; // cleared in setUp: not ready
      ws.trackRecommendationAccepted('x', 'Push');
      await ws.flushPendingWrites();
      expect(prefs.getString('workout_data_v2'), 'legacy');
    });
  });

  // ── 4. "Not specified" eating style keeps the rest of the profile ────────
  test('copyWith(clearPortionAnchor) only clears the portion anchor', () {
    final p = _profile().copyWith(
      portionAnchor: PortionAnchor.carbAnchored,
      useCustomTargets: true,
      customMaintenanceCalories: 2400,
      customProteinTarget: 160,
      carryForwardEnabled: true,
      carryForwardThreshold: 150,
      targetChangeHistory: [
        TargetChangeRecord(timestamp: DateTime(2026, 9, 1), sourceType: 'Custom Targets'),
      ],
    );
    final cleared = p.copyWith(clearPortionAnchor: true);
    expect(cleared.portionAnchor, isNull);
    expect(cleared.useCustomTargets, isTrue);
    expect(cleared.customMaintenanceCalories, 2400);
    expect(cleared.customProteinTarget, 160);
    expect(cleared.carryForwardEnabled, isTrue);
    expect(cleared.carryForwardThreshold, 150);
    expect(cleared.targetChangeHistory, hasLength(1));
    expect(p.copyWith().portionAnchor, PortionAnchor.carbAnchored);
  });

  // ── 5. Accepted carry-forward reaches a frozen target ────────────────────
  test('refreshing after accepting carry-forward applies it to a frozen target',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await UserSessionCoordinator.instance.initializeForUser(other, prefsOverride: prefs);
    ProfileService.instance.currentUserProfile = _profile();
    final today = DateTime(2026, 10, 6);
    final engine = NutritionTargetEngine.instance;
    await engine.refreshTargetForDate(today);
    final log = logFor(today);
    final before = log.targetCalories!;

    log.carryForwardAdjustment = 150;
    // The frozen target ignores it until refreshed.
    expect(engine.effectiveTargetForDate(today).calories, before);
    await engine.refreshTargetForDate(today);
    expect(log.targetCalories, greaterThan(before));
  });

  // ── 6. Network timeouts ───────────────────────────────────────────────────
  test('within() fails a hung call with a TimeoutException', () async {
    final hung = Completer<int>().future;
    await expectLater(
      hung.within(const Duration(milliseconds: 20), 'probe'),
      throwsA(isA<TimeoutException>()),
    );
    expect(await Future.value(1).within(const Duration(seconds: 1), 'ok'), 1);
  });
}
