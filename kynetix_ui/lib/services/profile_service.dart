import 'package:flutter/foundation.dart';
import '../models/user_profile.dart';
import '../config/supabase_client.dart';

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
          .maybeSingle();
      return data != null;
    } catch (_) {
      return false;
    }
  }

  /// Fetches the profile from Supabase and converts it into local UserProfile.
  /// Throws exceptions on network or database errors.
  Future<UserProfile?> fetchProfile() async {
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
          .maybeSingle();

      if (data == null) {
        debugPrint('[ProfileService] No profile row found in database for user: ${user.id}');
        return null;
      }
      
      debugPrint('[ProfileService] Profile successfully fetched and mapped.');
      // Defensive parsing: Supabase can return null or wrong types for newly
      // created accounts where not all columns are populated yet.
      double _d(dynamic v, double fb) {
        if (v == null) return fb;
        if (v is num) return v.toDouble();
        return double.tryParse(v.toString()) ?? fb;
      }
      int _i(dynamic v, int fb) {
        if (v == null) return fb;
        if (v is int) return v;
        if (v is num) return v.toInt();
        return int.tryParse(v.toString()) ?? fb;
      }
      final anchorRaw = data['portion_anchor'] as String?;
      return UserProfile(
        name: (data['name'] as String?) ?? '',
        age: _i(data['age'], 25),
        gender: (data['gender'] as String?) ?? 'Male',
        height: _d(data['height_cm'], 170.0),
        weight: _d(data['weight_kg'], 70.0),
        workoutDaysMin: _i(data['workout_days_min'], 2),
        workoutDaysMax: _i(data['workout_days_max'], 3),
        goal: (data['goal'] as String?) ?? 'Maintenance',
        portionAnchor: anchorRaw != null
            ? PortionAnchor.values.firstWhere(
                (e) => e.name == anchorRaw,
                orElse: () => PortionAnchor.balanced,
              )
            : null,
        averageDailySteps: null, // Keep HealthSync strictly local for now
        healthSyncEnabled: false,
        carryForwardEnabled: data['carry_forward_enabled'] as bool? ?? false,
        carryForwardThreshold: _i(data['carry_forward_threshold'], 100),
      );
    } catch (e) {
      debugPrint('[ProfileService] Exception during profile fetch: $e');
      rethrow;
    }
  }

  /// Uploads local UserProfile state to Supabase mapping Native -> Cloud
  Future<void> upsertProfile(UserProfile profile) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      await supabase.from('profiles').upsert({
        'id': user.id,
        'email': user.email,
        'phone': user.phone,
        'name': profile.name,
        'age': profile.age,
        'gender': profile.gender,
        'height_cm': profile.height.toInt(),
        'weight_kg': profile.weight,
        'workout_days_min': profile.workoutDaysMin,
        'workout_days_max': profile.workoutDaysMax,
        'goal': profile.goal,
        'carry_forward_enabled': profile.carryForwardEnabled,
        'carry_forward_threshold': profile.carryForwardThreshold,
        if (profile.portionAnchor != null)
          'portion_anchor': profile.portionAnchor!.toJson()
        else
          'portion_anchor': null,
      });
    } catch (e) {
      // Background failure safe due to local-first architecture.
    }
  }
}
