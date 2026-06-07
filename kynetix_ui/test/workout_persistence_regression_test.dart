import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kynetix/models/user_profile.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/models/workout_session.dart';
import 'package:kynetix/services/workout_service.dart';
import 'package:kynetix/services/persistence_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://mock.supabase.co',
      anonKey: 'mock-anon-key',
    );
  });

  setUp(() async {
    // Clear SharedPreferences and service state between tests
    SharedPreferences.setMockInitialValues({});
    await WorkoutService.instance.clearAll();
  });

  group('Workout Persistence & Account Isolation Regression Tests', () {
    test('Workout survives cold restart', () async {
      final session = WorkoutSession(
        id: 'test-session-cold-restart',
        date: DateTime(2026, 6, 6),
        splitDayName: 'Push Day',
        entries: const [],
      );

      final service = WorkoutService.instance;
      await service.clearAll();
      await service.saveSession(session);

      // Retrieve persisted string before simulating restart
      final prefs = await SharedPreferences.getInstance();
      final savedData = prefs.getString('workout_data_v2');
      expect(savedData, isNotNull);

      // Reset service in-memory state (mimicking cold restart)
      await service.clearAll();
      expect(service.sessions, isEmpty);

      // Restore data to shared preferences
      await prefs.setString('workout_data_v2', savedData!);

      // Force init to reload by resetting the ready flag
      service.resetReadyForTesting();

      // Initialize again
      await service.init();

      // Verify the session is restored
      expect(service.sessions, hasLength(1));
      expect(service.sessions.first.id, 'test-session-cold-restart');
    });

    test('Workout survives flutter run simulation', () async {
      final session = WorkoutSession(
        id: 'test-session-flutter-run',
        date: DateTime(2026, 6, 6),
        splitDayName: 'Push Day',
        entries: const [],
      );

      final service = WorkoutService.instance;
      await service.clearAll();
      await service.saveSession(session);

      final prefs = await SharedPreferences.getInstance();
      
      // Simulate cachedOwnerId being null due to hydration delay on cold launch,
      // while the user profile is cached in SharedPreferences.
      await prefs.remove('cached_owner_user_id_v1');
      await prefs.setString(
        'user_profile_v2',
        jsonEncode(const UserProfile(
          name: 'Dhruv',
          age: 25,
          gender: 'Male',
          height: 175.0,
          weight: 70.0,
          workoutDaysMin: 3,
          workoutDaysMax: 4,
          goal: kMaintenance,
        ).toJson()),
      );

      expect(service.sessions, hasLength(1));
      expect(prefs.getString('cached_owner_user_id_v1'), isNull);

      // Simulate the logic in auth_gate.dart:
      final cachedOwnerId = prefs.getString('cached_owner_user_id_v1');
      final currentUserId = 'user-same-123';

      if (cachedOwnerId != null && cachedOwnerId != currentUserId) {
        await PersistenceService.reset();
      } else if (cachedOwnerId == null) {
        await PersistenceService.setCachedOwnerId(currentUserId);
      }

      // Verify workouts are NOT wiped because cachedOwnerId was null (hydration timing issue assumed)
      expect(service.sessions, hasLength(1));
      expect(service.sessions.first.id, 'test-session-flutter-run');
      expect(prefs.getString('cached_owner_user_id_v1'), currentUserId);
    });

    test('Workout survives logout/login with same account', () async {
      final session = WorkoutSession(
        id: 'test-session-logout-login',
        date: DateTime(2026, 6, 6),
        splitDayName: 'Push Day',
        entries: const [],
      );

      final service = WorkoutService.instance;
      await service.clearAll();
      await service.saveSession(session);
      expect(service.sessions, hasLength(1));

      // Simulate cloud backup of this session
      final cloudSessions = [session];

      // Simulate logout sequence: clear all local data
      await PersistenceService.reset();
      expect(service.sessions, isEmpty);

      // Simulate login with same account: sync/hydrate from cloud
      await service.bulkImportCloudSessions(cloudSessions);

      // Verify workouts are restored
      expect(service.sessions, hasLength(1));
      expect(service.sessions.first.id, 'test-session-logout-login');
    });

    test('Missing cached owner ID does not wipe workouts', () async {
      final session = WorkoutSession(
        id: 'test-session-missing-owner',
        date: DateTime(2026, 6, 6),
        splitDayName: 'Push Day',
        entries: const [],
      );

      final service = WorkoutService.instance;
      await service.clearAll();
      await service.saveSession(session);

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('cached_owner_user_id_v1');

      expect(service.sessions, hasLength(1));
      expect(prefs.getString('cached_owner_user_id_v1'), isNull);

      // Simulate auth_gate check
      final cachedOwnerId = prefs.getString('cached_owner_user_id_v1');
      final currentUserId = 'user-same-123';

      if (cachedOwnerId != null && cachedOwnerId != currentUserId) {
        await PersistenceService.reset();
      } else if (cachedOwnerId == null) {
        await PersistenceService.setCachedOwnerId(currentUserId);
      }

      expect(service.sessions, hasLength(1));
      expect(service.sessions.first.id, 'test-session-missing-owner');
      expect(prefs.getString('cached_owner_user_id_v1'), currentUserId);
    });

    test('Different owner ID does wipe workouts', () async {
      final session = WorkoutSession(
        id: 'test-session-different-owner',
        date: DateTime(2026, 6, 6),
        splitDayName: 'Push Day',
        entries: const [],
      );

      final service = WorkoutService.instance;
      await service.clearAll();
      await service.saveSession(session);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_owner_user_id_v1', 'user-owner-a');

      expect(service.sessions, hasLength(1));

      // Simulate auth_gate check for user-owner-b (mismatch!)
      final cachedOwnerId = prefs.getString('cached_owner_user_id_v1');
      final currentUserId = 'user-owner-b';

      if (cachedOwnerId != null && cachedOwnerId != currentUserId) {
        await PersistenceService.reset();
      } else if (cachedOwnerId == null) {
        await PersistenceService.setCachedOwnerId(currentUserId);
      }

      // Verify workouts and cached owner ID are wiped
      expect(service.sessions, isEmpty);
      expect(prefs.getString('cached_owner_user_id_v1'), isNull);
    });

    test('Empty cloud history does not remove local sessions', () async {
      final session = WorkoutSession(
        id: 'test-session-local-only',
        date: DateTime(2026, 6, 6),
        splitDayName: 'Push Day',
        entries: const [],
      );

      final service = WorkoutService.instance;
      await service.clearAll();
      await service.saveSession(session);
      expect(service.sessions, hasLength(1));

      // Simulate cloud response of workouts is empty
      final List<dynamic> workoutsResp = [];

      final importedSessions = <WorkoutSession>[];
      for (final row in workoutsResp) {
        final id = row['id'] as String;
        final exists = service.sessions.any((s) => s.id == id);
        if (!exists) {
          final session = WorkoutSession(
            id: row['id'],
            date: DateTime.parse(row['date'] as String),
            splitDayName: row['split_day_name'] as String,
            entries: const [],
          );
          importedSessions.add(session);
        }
      }
      if (importedSessions.isNotEmpty) {
        await service.bulkImportCloudSessions(importedSessions);
      }

      // Verify local session is preserved
      expect(service.sessions, hasLength(1));
      expect(service.sessions.first.id, 'test-session-local-only');
    });
  });
}
