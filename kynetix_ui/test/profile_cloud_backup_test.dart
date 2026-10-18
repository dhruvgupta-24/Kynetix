import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/user_profile.dart';
import 'package:kynetix/services/profile_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The whole profile reaches the cloud (profiles.profile_json) and comes
/// back on restore; rows written by older versions still map from columns.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  UserProfile full() => UserProfile(
        name: 'Dhruv',
        age: 24,
        gender: 'Female',
        height: 175.5,
        weight: 72.4,
        workoutDaysMin: 4,
        workoutDaysMax: 5,
        goal: kLeanBulk,
        portionAnchor: PortionAnchor.curryAnchored,
        averageDailySteps: 9100,
        healthSyncEnabled: true,
        lastHealthSyncAt: DateTime.utc(2026, 10, 15, 8),
        useCustomTargets: true,
        customMaintenanceCalories: 2550,
        customTrainingDayCalories: 2800,
        customRestDayCalories: 2400,
        customProteinTarget: 150,
        targetChangeHistory: [
          TargetChangeRecord(
            timestamp: DateTime.utc(2026, 10, 1),
            sourceType: 'Custom Targets',
            profileSnapshot: const {'goal': kLeanBulk},
          ),
        ],
        carryForwardEnabled: true,
        carryForwardThreshold: 150,
      );

  /// What the server row looks like after [ProfileService.upsertProfile]
  /// (JSON round trip, height_cm numeric).
  Map<String, dynamic> uploadedRow(UserProfile p) =>
      jsonDecode(jsonEncode({'id': 'u1', ...ProfileService.profileRow(p)})) as Map<String, dynamic>;

  void expectSameProfile(UserProfile a, UserProfile b) =>
      expect(jsonEncode(a.toJson()), jsonEncode(b.toJson()));

  group('upload payload', () {
    test('carries the full profile and the precise height', () {
      final row = ProfileService.profileRow(full());
      expect(row['height_cm'], 175.5);
      final json = row['profile_json'] as Map<String, dynamic>;
      expect(json['useCustomTargets'], true);
      expect(json['customMaintenanceCalories'], 2550);
      expect(json['customTrainingDayCalories'], 2800);
      expect(json['customRestDayCalories'], 2400);
      expect(json['customProteinTarget'], 150);
      expect((json['targetChangeHistory'] as List), hasLength(1));
      expect(json['averageDailySteps'], 9100);
      expect(json['portionAnchor'], 'curryAnchored');
      expect(json['carryForwardThreshold'], 150);
      expect(row['portion_anchor'], 'curryAnchored');
      expect(row['profile_updated_at'], isA<String>());
    });

    test('clearing the eating style uploads null', () {
      final row = ProfileService.profileRow(full().copyWith(clearPortionAnchor: true));
      expect(row.containsKey('portion_anchor'), isTrue);
      expect(row['portion_anchor'], isNull);
    });
  });

  group('restore from a row', () {
    test('profile_json round-trips every field', () {
      final remote = ProfileService.profileFromRow(uploadedRow(full()))!;
      expect(remote.isFullBackup, isTrue);
      expectSameProfile(remote.profile, full());
    });

    test('a truncated integer height column never overrides the precise one', () {
      final row = uploadedRow(full())..['height_cm'] = 175;
      expect(ProfileService.profileFromRow(row)!.profile.height, 175.5);
    });

    test('columns changed later by an older app version are honoured', () {
      final row = uploadedRow(full())
        ..['weight_kg'] = 70.0
        ..['height_cm'] = 180
        ..['goal'] = kFatLoss;
      final p = ProfileService.profileFromRow(row)!.profile;
      expect(p.weight, 70.0);
      expect(p.height, 180);
      expect(p.goal, kFatLoss);
      expect(p.customProteinTarget, 150); // json-only fields kept
    });

    test('legacy row (no profile_json): columns, local fallback for gaps', () {
      final local = full();
      final row = <String, dynamic>{
        'id': 'u1',
        'name': 'Dhruv',
        'age': 24,
        'gender': null,
        'height_cm': 175.5,
        'weight_kg': 72.4,
        'goal': null,
        'workout_days_min': 4,
        'workout_days_max': 5,
        'carry_forward_enabled': true,
        'carry_forward_threshold': 150,
        'portion_anchor': null,
      };
      final remote = ProfileService.profileFromRow(row, local: local)!;
      expect(remote.isFullBackup, isFalse);
      expect(remote.profile.gender, 'Female');
      expect(remote.profile.goal, kLeanBulk);
      expect(remote.profile.height, 175.5);
    });

    test('a row that never onboarded maps to null', () {
      expect(ProfileService.profileFromRow({'id': 'u1', 'email': 'x@y.z'}), isNull);
    });

    test('unreadable profile_json falls back to the columns', () {
      final row = uploadedRow(full())..['profile_json'] = {'targetChangeHistory': 'garbage'};
      final remote = ProfileService.profileFromRow(row)!;
      expect(remote.isFullBackup, isFalse);
      expect(remote.profile.height, 175.5);
    });
  });

  group('merge with this device', () {
    test('new device restores custom targets, history, steps', () {
      final merged = ProfileService.mergeRemoteWithLocal(
          ProfileService.profileFromRow(uploadedRow(full()))!, null);
      expect(merged.useCustomTargets, isTrue);
      expect(merged.customTrainingDayCalories, 2800);
      expect(merged.targetChangeHistory, hasLength(1));
      expect(merged.averageDailySteps, 9100);
      expect(merged.carryForwardEnabled, isTrue);
      // Health Connect permission is per device.
      expect(merged.healthSyncEnabled, isFalse);
    });

    test('cloud wins over an older local copy', () {
      final local = full().copyWith(customProteinTarget: 120, targetChangeHistory: [
        TargetChangeRecord(timestamp: DateTime.utc(2026, 9, 1), sourceType: 'Custom Targets'),
      ]);
      final merged = ProfileService.mergeRemoteWithLocal(
          ProfileService.profileFromRow(uploadedRow(full()))!, local);
      expect(merged.customProteinTarget, 150);
      expect(merged.healthSyncEnabled, isTrue); // local switch kept
    });

    test('a newer local target change (upload failed) is kept', () {
      final local = full().copyWith(customProteinTarget: 165, targetChangeHistory: [
        ...full().targetChangeHistory,
        TargetChangeRecord(timestamp: DateTime.utc(2026, 10, 16), sourceType: 'Custom Targets'),
      ]);
      final merged = ProfileService.mergeRemoteWithLocal(
          ProfileService.profileFromRow(uploadedRow(full()))!, local);
      expect(merged.customProteinTarget, 165);
      expect(merged.targetChangeHistory, hasLength(2));
    });

    test('legacy row keeps the local-only fields as before', () {
      final local = full();
      final row = Map<String, dynamic>.from(uploadedRow(full()))..remove('profile_json');
      final merged = ProfileService.mergeRemoteWithLocal(
          ProfileService.profileFromRow(row, local: local)!, local);
      expect(merged.customMaintenanceCalories, 2550);
      expect(merged.targetChangeHistory, hasLength(1));
      expect(merged.averageDailySteps, 9100);
      expect(merged.portionAnchor, PortionAnchor.curryAnchored);
    });
  });

  test('save() writes locally, keeps the current profile in step, never throws offline', () async {
    SharedPreferences.setMockInitialValues({});
    final p = full();
    ProfileService.instance.currentUserProfile = p;
    final saved = await ProfileService.instance.save(p);
    await ProfileService.instance.lastUpload; // no Supabase here: must not throw
    expect(identical(ProfileService.instance.currentUserProfile, saved), isTrue);
    expect(saved.customProteinTarget, 150);
    ProfileService.instance.currentUserProfile = null;
  });
}
