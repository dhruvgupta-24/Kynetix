import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/models/user_profile.dart';
import 'package:kynetix/services/global_food_service.dart';
import 'package:kynetix/services/persistence_service.dart';
import 'package:kynetix/services/profile_service.dart';
import 'package:kynetix/services/user_session_coordinator.dart';

/// Regression: signing up with a new email on a device where someone already
/// onboarded skipped onboarding and loaded the previous person's profile.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userA = 'user-a-onboarded';
  const userB = 'user-b-brand-new';

  const aliceProfile = UserProfile(
    name: 'Alice',
    age: 28,
    gender: 'female',
    height: 165,
    weight: 60,
    goal: 'Fat Loss',
    workoutDaysMin: 3,
    workoutDaysMax: 4,
  );

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'https://mock.supabase.co', anonKey: 'mock-anon-key');
    await GlobalFoodService.instance.init(fetchRemote: false);
  });

  setUp(() async {
    await UserSessionCoordinator.instance.clearAllUserServices();
  });

  test('a new account after an onboarded one must onboard and start clean', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    // User A onboards and logs a meal day.
    await UserSessionCoordinator.instance.initializeForUser(userA, prefsOverride: prefs);
    ProfileService.instance.currentUserProfile = aliceProfile;
    await PersistenceService.saveProfile(aliceProfile);
    await PersistenceService.setOnboardingDone();
    dayLogStore['2026-03-05'] = DayLog()..targetCalories = 1800;
    await PersistenceService.saveDayLogs();
    expect(PersistenceService.isOnboardingDone, isTrue);

    // A signs out; B signs up with a new email on the same phone.
    await UserSessionCoordinator.instance.clearAllUserServices();
    await UserSessionCoordinator.instance.initializeForUser(userB, prefsOverride: prefs);

    expect(PersistenceService.isOnboardingDone, isFalse,
        reason: 'A brand-new account must go through onboarding');
    expect(ProfileService.instance.currentUserProfile, isNull,
        reason: "A new account must never see the previous user's profile");
    expect(dayLogStore.isEmpty, isTrue,
        reason: "A new account must never see the previous user's meals");

    // A's data is untouched and comes back when A signs in again.
    await UserSessionCoordinator.instance.clearAllUserServices();
    await UserSessionCoordinator.instance.initializeForUser(userA, prefsOverride: prefs);
    expect(PersistenceService.isOnboardingDone, isTrue);
    expect(ProfileService.instance.currentUserProfile?.name, 'Alice');
    expect(dayLogStore.containsKey('2026-03-05'), isTrue);
  });

  test('legacy device-wide data is only migrated into its owner', () async {
    final legacyLogs = jsonEncode({
      '2026-01-01': (DayLog()..targetCalories = 2000).toJson(),
    });
    SharedPreferences.setMockInitialValues({
      'onboarding_done_v1': true,
      'user_profile_v2': jsonEncode(aliceProfile.toJson()),
      'day_logs_v1': legacyLogs,
    });
    final prefs = await SharedPreferences.getInstance();

    // First account on the device claims the legacy data (zero loss).
    await UserSessionCoordinator.instance.initializeForUser(userA, prefsOverride: prefs);
    expect(PersistenceService.isOnboardingDone, isTrue);
    expect(ProfileService.instance.currentUserProfile?.name, 'Alice');
    expect(dayLogStore.containsKey('2026-01-01'), isTrue);

    // A second account must not receive a copy of it.
    await UserSessionCoordinator.instance.clearAllUserServices();
    await UserSessionCoordinator.instance.initializeForUser(userB, prefsOverride: prefs);
    expect(PersistenceService.isOnboardingDone, isFalse);
    expect(ProfileService.instance.currentUserProfile, isNull);
    expect(dayLogStore.isEmpty, isTrue);
    expect(prefs.getString('user_profile_v2_$userB'), isNull);

    // Nothing was deleted: the legacy keys are still there for their owner.
    expect(prefs.getString('day_logs_v1'), legacyLogs);
    expect(prefs.getString('user_profile_v2'), isNotNull);
  });

  test('installs migrated before the claim key back-fill the owner', () async {
    SharedPreferences.setMockInitialValues({
      'user_profile_v2': jsonEncode(aliceProfile.toJson()),
      'migration_verified_v1_$userA': true,
      'user_profile_v2_$userA': jsonEncode(aliceProfile.toJson()),
    });
    final prefs = await SharedPreferences.getInstance();

    await UserSessionCoordinator.instance.initializeForUser(userB, prefsOverride: prefs);
    expect(ProfileService.instance.currentUserProfile, isNull);
    expect(prefs.getString(UserSessionCoordinator.legacyOwnerKey), userA);
  });
}
