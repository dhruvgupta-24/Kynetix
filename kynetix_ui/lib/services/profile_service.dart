import 'package:flutter/foundation.dart';
import '../screens/onboarding_screen.dart'; // Where UserProfile lives currently
import '../config/supabase_client.dart';

class ProfileService {
  ProfileService._();
  static final instance = ProfileService._();

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
      return UserProfile(
      name: data['name'] as String,
      age: data['age'] as int,
      gender: data['gender'] as String,
      height: (data['height_cm'] as num).toDouble(),
      weight: (data['weight_kg'] as num).toDouble(),
      workoutDaysMin: data['workout_days_min'] as int? ?? 2,
      workoutDaysMax: data['workout_days_max'] as int? ?? 3,
      goal: data['goal'] as String,
      averageDailySteps: null, // Keep HealthSync strictly local for now
      healthSyncEnabled: false,
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
        'name': profile.name,
        'age': profile.age,
        'gender': profile.gender,
        'height_cm': profile.height.toInt(),
        'weight_kg': profile.weight,
        'workout_days_min': profile.workoutDaysMin,
        'workout_days_max': profile.workoutDaysMax,
        'goal': profile.goal,
      });
    } catch (e) {
      // Background failure safe due to local-first architecture.
    }
  }
}
