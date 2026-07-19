import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kynetix/models/user_profile.dart';
import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/services/profile_service.dart';
import 'package:kynetix/services/persistence_service.dart';
import 'package:kynetix/services/nutrition_target_engine.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://mock.supabase.co',
      anonKey: 'mock-anon-key',
    );
  });

  setUp(() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    ProfileService.instance.currentUserProfile = null;
    dayLogStore.clear();
  });

  test('Profile timeline records snapshots and reconstructs active profiles correctly', () async {
    // 1. Initial Profile (Maintenance)
    final profile1 = const UserProfile(
      name: 'Dhruv',
      age: 25,
      gender: 'Male',
      height: 180.0,
      weight: 80.0,
      workoutDaysMin: 3,
      workoutDaysMax: 4,
      goal: kMaintenance,
    );

    // Save profile for the first time (represents Onboarding done)
    await PersistenceService.saveProfile(profile1);
    final savedProfile1 = ProfileService.instance.currentUserProfile!;
    expect(savedProfile1.targetChangeHistory.length, 1);
    expect(savedProfile1.targetChangeHistory[0].sourceType, 'System Calculated');
    expect(savedProfile1.targetChangeHistory[0].profileSnapshot?['goal'], kMaintenance);

    // Let's create a couple of records in the past.
    // To simulate past dates, we can manually manipulate timestamps of the history list.
    final t1 = DateTime.now().subtract(const Duration(days: 10));
    final t2 = DateTime.now().subtract(const Duration(days: 5));

    final historyWithT1 = [
      TargetChangeRecord(
        timestamp: t1,
        sourceType: 'System Calculated',
        profileSnapshot: profile1.toSnapshotJson(),
      ),
    ];

    // 2. Goal changes to Fat Loss
    final profile2 = savedProfile1.copyWith(
      goal: kFatLoss,
      targetChangeHistory: historyWithT1,
    );
    await PersistenceService.saveProfile(profile2);
    final savedProfile2 = ProfileService.instance.currentUserProfile!;
    expect(savedProfile2.targetChangeHistory.length, 2);

    // Update the second record's timestamp to t2 for simulation
    final historyWithT2 = [
      savedProfile2.targetChangeHistory[0],
      TargetChangeRecord(
        timestamp: t2,
        sourceType: 'System Calculated',
        profileSnapshot: savedProfile2.copyWith(goal: kFatLoss).toSnapshotJson(),
      ),
    ];

    // 3. Goal changes to Lean Bulk (Today's profile)
    final profile3 = savedProfile2.copyWith(
      goal: kLeanBulk,
      targetChangeHistory: historyWithT2,
    );
    await PersistenceService.saveProfile(profile3);
    final finalProfile = ProfileService.instance.currentUserProfile!;
    expect(finalProfile.targetChangeHistory.length, 3);
    expect(finalProfile.goal, kLeanBulk);

    // Verify profileActiveOn for different historical dates
    // Date before t1 -> should return the snapshot of the first record (Maintenance)
    final activeBeforeT1 = finalProfile.profileActiveOn(t1.subtract(const Duration(days: 1)));
    expect(activeBeforeT1, isNotNull);
    expect(activeBeforeT1!.goal, kMaintenance);

    // Date between t1 and t2 -> should return the snapshot of t1 (Maintenance)
    final activeBetweenT1AndT2 = finalProfile.profileActiveOn(t1.add(const Duration(days: 2)));
    expect(activeBetweenT1AndT2, isNotNull);
    expect(activeBetweenT1AndT2!.goal, kMaintenance);

    // Date between t2 and now -> should return the snapshot of t2 (Fat Loss)
    final activeAfterT2 = finalProfile.profileActiveOn(t2.add(const Duration(days: 2)));
    expect(activeAfterT2, isNotNull);
    expect(activeAfterT2!.goal, kFatLoss);

    // Date today -> should return today's snapshot (Lean Bulk)
    final activeToday = finalProfile.profileActiveOn(DateTime.now());
    expect(activeToday, isNotNull);
    expect(activeToday!.goal, kLeanBulk);
  });

  test('runHistoricalRepairMigration uses reconstructed profile or skips if history is empty', () async {
    // Scenario A: targetChangeHistory is empty (e.g. fresh install/restore with old null targets)
    final profile = const UserProfile(
      name: 'Dhruv',
      age: 25,
      gender: 'Male',
      height: 180.0,
      weight: 80.0,
      workoutDaysMin: 3,
      workoutDaysMax: 4,
      goal: kLeanBulk,
      targetChangeHistory: [],
    );
    ProfileService.instance.currentUserProfile = profile;

    final dateStr = '2026-07-10';
    final date = DateTime.parse(dateStr);
    final log = DayLog();
    dayLogStore[dateStr] = log;

    // Run repair migration -> should skip since history is empty (insufficient info)
    await PersistenceService.runHistoricalRepairMigration();
    expect(dayLogStore[dateStr]?.targetCalories, isNull);

    // Scenario B: targetChangeHistory has history
    final t1 = DateTime.now().subtract(const Duration(days: 10));
    final profileWithHistory = profile.copyWith(
      targetChangeHistory: [
        TargetChangeRecord(
          timestamp: t1,
          sourceType: 'System Calculated',
          profileSnapshot: profile.copyWith(goal: kMaintenance).toSnapshotJson(),
        ),
      ],
    );
    ProfileService.instance.currentUserProfile = profileWithHistory;

    // Run repair migration again -> should resolve historical profile and freeze it
    await PersistenceService.runHistoricalRepairMigration();
    final repairedLog = dayLogStore[dateStr];
    expect(repairedLog, isNotNull);
    expect(repairedLog!.targetCalories, isNotNull);
    // Since history resolved to kMaintenance, check target match
    final maintenanceTarget = NutritionTargetEngine.instance.effectiveTargetForDate(
      date,
      profile: profile.copyWith(goal: kMaintenance),
      forceRecalculate: true,
    );
    expect(repairedLog.targetCalories, maintenanceTarget.calories);
  });
}
