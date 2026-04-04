import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_client.dart';

import '../services/persistence_service.dart';

class AuthService {
  User? get currentUser => supabase.auth.currentUser;

  Stream<AuthState> get authStateChanges => supabase.auth.onAuthStateChange;

  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) async {
    debugPrint('[AuthService] Attempting signUp for: $email');
    try {
      final response = await supabase.auth.signUp(
        email: email,
        password: password,
      );
      debugPrint('[AuthService] signUp success. User ID: ${response.user?.id}');
      return response;
    } catch (e) {
      debugPrint('[AuthService] signUp failed: $e');
      rethrow;
    }
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    debugPrint('[AuthService] Attempting signIn for: $email');
    try {
      final response = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      debugPrint('[AuthService] signIn success. User ID: ${response.user?.id}');
      return response;
    } catch (e) {
      debugPrint('[AuthService] signIn failed: $e');
      rethrow;
    }
  }

  Future<void> signOut() async {
    debugPrint('[AuthService] Initiating signOut sequence.');
    try {
      await PersistenceService.reset();
      await supabase.auth.signOut();
      debugPrint('[AuthService] signOut completed successfully.');
    } catch (e) {
      debugPrint('[AuthService] signOut failed: $e');
      rethrow;
    }
  }
}