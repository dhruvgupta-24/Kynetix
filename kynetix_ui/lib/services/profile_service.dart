import 'package:flutter/foundation.dart';
import '../models/user_profile.dart';
import '../config/supabase_client.dart';
import '../services/internal/net_timeouts.dart';
import '../services/persistence_service.dart';
import '../services/user_session_coordinator.dart';

/// A profile read from the cloud. [isFullBackup] is true when it came from
/// `profiles.profile_json` (every field), false for rows written by older
/// app versions (basic columns only).
class RemoteProfile {
  const RemoteProfile(this.profile, {required this.isFullBackup});
  final UserProfile profile;
  final bool isFullBackup;
}

class ProfileService {
  ProfileService._();
  static final instance = ProfileService._();

  /// Global in-memory user profile store
  UserProfile? currentUserProfile;

  /// Helper to get the active PortionAnchor
  PortionAnchor get activePortionAnchor => currentUserProfile?.portionAnchor ?? PortionAnchor.balanced;


  /// Check if the currently logged in user already has a profile row.
  Future<bool> hasProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return false;

    try {
      final data = await supabase
          .from('profiles')
          .select('id')
          .eq('id', user.id)
          .maybeSingle()
          .within(NetTimeouts.sync, 'profile check');
      return data != null;
    } catch (_) {
      return false;
    }
  }

  /// Fetches the profile from Supabase and converts it into local UserProfile.
  /// Throws exceptions on network or database errors.
  Future<UserProfile?> fetchProfile() async =>
      (await fetchRemoteProfile())?.profile;

  /// Like [fetchProfile], and says whether the row held a full backup.
  /// Throws exceptions on network or database errors.
  Future<RemoteProfile?> fetchRemoteProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      debugPrint('[ProfileService] fetchProfile called but currentUser is null.');
      return null;
    }

    debugPrint('[ProfileService] Fetching profile for user: ${user.id}');
    try {
      final data = await supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle()
          .within(NetTimeouts.sync, 'profile fetch');

      if (data == null) {
        debugPrint('[ProfileService] No profile row found in database for user: ${user.id}');
        return null;
      }
      final remote = profileFromRow(data, local: currentUserProfile);
      debugPrint(remote == null
          ? '[ProfileService] Profile row is incomplete (not onboarded yet).'
          : '[ProfileService] Profile successfully fetched and mapped '
              '(full backup: ${remote.isFullBackup}).');
      return remote;
    } catch (e) {
      debugPrint('[ProfileService] Exception during profile fetch: $e');
      rethrow;
    }
  }

  /// Maps a `profiles` row. Prefers `profile_json` (the full profile); the
  /// basic columns are laid over it (an older app version on another device
  /// may have updated only those). Rows without `profile_json` map from the
  /// columns; a missing name/gender/goal/workout days then keeps [local]'s
  /// value rather than a default. Returns null for a row that has not been
  /// onboarded yet.
  @visibleForTesting
  static RemoteProfile? profileFromRow(Map<String, dynamic> data, {UserProfile? local}) {
    double? toD(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }
    int? toI(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }
    String? toS(dynamic v) => v is String && v.isNotEmpty ? v : null;
    PortionAnchor? anchor(dynamic v) => v is String
        ? PortionAnchor.values.firstWhere((e) => e.name == v, orElse: () => PortionAnchor.balanced)
        : null;

    final rawJson = data['profile_json'];
    UserProfile? backup;
    if (rawJson is Map) {
      try {
        backup = UserProfile.fromJson(Map<String, dynamic>.from(rawJson));
      } catch (e) {
        debugPrint('[ProfileService] Unreadable profile_json ignored: $e');
      }
    }

    if (backup != null) {
      // Columns are written alongside (identical) or later by an older
      // client. height_cm used to be an integer column: only a whole-cm
      // difference counts, so a truncated copy never overrides the precise
      // height.
      final colHeight = toD(data['height_cm']);
      final height = colHeight != null && (colHeight - backup.height).abs() >= 1
          ? colHeight
          : backup.height;
      return RemoteProfile(
        UserProfile(
          name: toS(data['name']) ?? backup.name,
          age: toI(data['age']) ?? backup.age,
          gender: toS(data['gender']) ?? backup.gender,
          height: height,
          weight: toD(data['weight_kg']) ?? backup.weight,
          workoutDaysMin: toI(data['workout_days_min']) ?? backup.workoutDaysMin,
          workoutDaysMax: toI(data['workout_days_max']) ?? backup.workoutDaysMax,
          goal: toS(data['goal']) ?? backup.goal,
          portionAnchor: data.containsKey('portion_anchor')
              ? anchor(data['portion_anchor'])
              : backup.portionAnchor,
          averageDailySteps: backup.averageDailySteps,
          healthSyncEnabled: backup.healthSyncEnabled,
          lastHealthSyncAt: backup.lastHealthSyncAt,
          useCustomTargets: backup.useCustomTargets,
          customMaintenanceCalories: backup.customMaintenanceCalories,
          customTrainingDayCalories: backup.customTrainingDayCalories,
          customRestDayCalories: backup.customRestDayCalories,
          customProteinTarget: backup.customProteinTarget,
          targetChangeHistory: backup.targetChangeHistory,
          carryForwardEnabled: data['carry_forward_enabled'] as bool? ?? backup.carryForwardEnabled,
          carryForwardThreshold: toI(data['carry_forward_threshold']) ?? backup.carryForwardThreshold,
        ),
        isFullBackup: true,
      );
    }

    // A row can exist before onboarding (created at sign-up with only id /
    // email). Onboarding always writes age, height and weight, so a row
    // without them is a brand-new account that still has to onboard — never
    // fill it with defaults and skip straight to the home screen.
    if (data['age'] == null || data['height_cm'] == null || data['weight_kg'] == null) {
      return null;
    }
    return RemoteProfile(
      UserProfile(
        name: toS(data['name']) ?? local?.name ?? '',
        age: toI(data['age']) ?? 25,
        gender: toS(data['gender']) ?? local?.gender ?? 'Male',
        height: toD(data['height_cm']) ?? 170.0,
        weight: toD(data['weight_kg']) ?? 70.0,
        workoutDaysMin: toI(data['workout_days_min']) ?? local?.workoutDaysMin ?? 2,
        workoutDaysMax: toI(data['workout_days_max']) ?? local?.workoutDaysMax ?? 3,
        goal: toS(data['goal']) ?? local?.goal ?? kMaintenance,
        portionAnchor: anchor(data['portion_anchor']),
        averageDailySteps: null, // Not in the legacy columns.
        healthSyncEnabled: false,
        carryForwardEnabled: data['carry_forward_enabled'] as bool? ?? false,
        carryForwardThreshold: toI(data['carry_forward_threshold']) ?? 100,
      ),
      isFullBackup: false,
    );
  }

  /// Combines the cloud profile with this device's ([local]).
  ///
  /// Full backup: the cloud copy wins, unless the local profile's target
  /// history shows a newer change (saved here while the upload failed). The
  /// Health Connect switch is per device and stays local; step data comes
  /// from whichever copy synced last.
  ///
  /// Legacy row (basic columns only): fields the columns never held come
  /// from [local], as before.
  static UserProfile mergeRemoteWithLocal(RemoteProfile remote, UserProfile? local) {
    final r = remote.profile;
    if (!remote.isFullBackup) {
      return r.copyWith(
        healthSyncEnabled: local?.healthSyncEnabled ?? false,
        averageDailySteps: local?.averageDailySteps,
        lastHealthSyncAt: local?.lastHealthSyncAt,
        portionAnchor: r.portionAnchor ?? local?.portionAnchor,
        useCustomTargets: local?.useCustomTargets,
        customMaintenanceCalories: local?.customMaintenanceCalories,
        customTrainingDayCalories: local?.customTrainingDayCalories,
        customRestDayCalories: local?.customRestDayCalories,
        customProteinTarget: local?.customProteinTarget,
        targetChangeHistory: local?.targetChangeHistory,
        carryForwardEnabled: local?.carryForwardEnabled,
        carryForwardThreshold: local?.carryForwardThreshold,
      );
    }
    if (local == null) return r.copyWith(healthSyncEnabled: false);

    DateTime? latest(UserProfile p) => p.targetChangeHistory.isEmpty
        ? null
        : p.targetChangeHistory
            .map((e) => e.timestamp)
            .reduce((a, b) => a.isAfter(b) ? a : b);
    final lr = latest(r), ll = latest(local);
    final base = ll != null && (lr == null || ll.isAfter(lr)) ? local : r;

    final rSync = r.lastHealthSyncAt, lSync = local.lastHealthSyncAt;
    final steps = rSync != null && (lSync == null || rSync.isAfter(lSync)) ? r : local;
    return UserProfile(
      name: base.name,
      age: base.age,
      gender: base.gender,
      height: base.height,
      weight: base.weight,
      workoutDaysMin: base.workoutDaysMin,
      workoutDaysMax: base.workoutDaysMax,
      goal: base.goal,
      portionAnchor: base.portionAnchor,
      averageDailySteps: steps.averageDailySteps,
      healthSyncEnabled: local.healthSyncEnabled,
      lastHealthSyncAt: steps.lastHealthSyncAt,
      useCustomTargets: base.useCustomTargets,
      customMaintenanceCalories: base.customMaintenanceCalories,
      customTrainingDayCalories: base.customTrainingDayCalories,
      customRestDayCalories: base.customRestDayCalories,
      customProteinTarget: base.customProteinTarget,
      targetChangeHistory: base.targetChangeHistory,
      carryForwardEnabled: base.carryForwardEnabled,
      carryForwardThreshold: base.carryForwardThreshold,
    );
  }

  Future<void> _lastUpload = Future.value();

  /// Completes when the upload started by the latest [save] has finished
  /// (it never throws).
  Future<void> get lastUpload => _lastUpload;

  /// The one way to save the profile: writes it locally (appending a target
  /// history record when target inputs changed), keeps [currentUserProfile]
  /// in step when [p] is the current one, and backs the whole profile up to
  /// the cloud (fire-and-forget; see [lastUpload]). Returns it as stored.
  Future<UserProfile> save(UserProfile p, {bool upload = true}) async {
    final saved = await PersistenceService.saveProfile(p);
    if (identical(currentUserProfile, p)) currentUserProfile = saved;
    if (upload) _lastUpload = upsertProfile(saved);
    return saved;
  }

  /// Row written by [upsertProfile] (without the auth identity columns).
  @visibleForTesting
  static Map<String, dynamic> profileRow(UserProfile profile) => {
        'name': profile.name,
        'age': profile.age,
        'gender': profile.gender,
        'height_cm': profile.height,
        'weight_kg': profile.weight,
        'workout_days_min': profile.workoutDaysMin,
        'workout_days_max': profile.workoutDaysMax,
        'goal': profile.goal,
        'carry_forward_enabled': profile.carryForwardEnabled,
        'carry_forward_threshold': profile.carryForwardThreshold,
        'portion_anchor': profile.portionAnchor?.toJson(),
        'profile_json': profile.toJson(),
        'profile_updated_at': DateTime.now().toUtc().toIso8601String(),
      };

  /// Uploads the whole local UserProfile to Supabase (columns + profile_json).
  /// Never throws.
  Future<void> upsertProfile(UserProfile profile) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;
      // The in-memory profile belongs to the session user; never upload it
      // under a different auth identity.
      final sessionUser = UserSessionCoordinator.instance.currentUserId;
      if (sessionUser != null && sessionUser != user.id) return;

      await supabase.from('profiles').upsert({
        'id': user.id,
        'email': user.email,
        'phone': user.phone,
        ...profileRow(profile),
      }).within(NetTimeouts.sync, 'profile upsert');
    } catch (e) {
      // Background failure safe due to local-first architecture.
    }
  }
}
