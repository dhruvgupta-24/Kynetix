import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─── NutritionHydrationGuard ──────────────────────────────────────────────────
//
// SECURITY CONTRACT:
//   All user-specific nutrition memory (UserNutritionMemory, MealMemory._store /
//   _candidates, PersonalNutritionMemory._userOverrides) MUST NOT be read until
//   this guard is in the Ready state for the currently authenticated user.
//
// FAIL-CLOSED DESIGN:
//   The default state is NotReady. Any ambiguous state (NotReady, hydrating,
//   unknown auth) is treated as NotReady and callers MUST return null.
//
// STATES:
//   NotReady   – initial state, after logout, after app crash/kill
//   Hydrating  – set by AuthGate when hydration begins (blocks reads)
//   Ready      – set by CloudSyncService after successful hydration
//                carries hydratedUserId for ownership verification
//
// OWNERSHIP VERIFICATION:
//   Even after Ready, every lookup should call:
//     guard.isReadyForUser(Supabase.instance.client.auth.currentUser?.id)
//   This catches edge cases where auth state changes without a full reset.
//
// USAGE:
//   // In any user-specific cache lookup:
//   if (!NutritionHydrationGuard.instance.isReadyForCurrentUser) return null;
//
// ACCOUNT SWITCH SEQUENCE (enforced):
//   Logout:
//     1. NutritionHydrationGuard.instance.reset()   ← FIRST — closes the gate
//     2. PersonalNutritionMemory.instance.clearAll()
//     3. MealMemory.instance.clearAll()
//     4. UserNutritionMemory.instance.clearAll()
//     5. other local services clear
//     6. SharedPreferences cleanup
//     7. supabase.auth.signOut()
//     8. Login screen shown
//   Login:
//     1. NutritionHydrationGuard.instance.reset()   ← ensure clean state
//     2. supabase.auth.signIn(...)
//     3. NutritionHydrationGuard.instance.beginHydration()
//     4. CloudSyncService.hydrateFromCloud()
//     5. NutritionHydrationGuard.instance.markComplete(userId)
//     6. Nutrition memory reads now allowed

enum _HydrationState { notReady, hydrating, ready }

class NutritionHydrationGuard {
  NutritionHydrationGuard._();
  static final NutritionHydrationGuard instance = NutritionHydrationGuard._();

  _HydrationState _state = _HydrationState.notReady;

  /// The user ID that was authenticated when hydration completed.
  /// null when state is not Ready.
  String? _hydratedUserId;

  // ── State transitions ────────────────────────────────────────────────────

  /// Call BEFORE any local caches are cleared (step 1 of logout/switch).
  /// Immediately closes the gate — all cache reads will return null.
  void reset() {
    _state = _HydrationState.notReady;
    _hydratedUserId = null;
    debugPrint('[HydrationGuard] 🔒 RESET — all nutrition memory reads blocked');
  }

  /// Call when cloud hydration starts. Distinguishes "never hydrated"
  /// from "actively hydrating" in logs. If already Ready for current user and
  /// this is a background update, keeps existing Ready state active.
  void beginHydration({bool isBackgroundUpdate = false}) {
    if (_state == _HydrationState.ready && isBackgroundUpdate) {
      debugPrint('[HydrationGuard] 🔄 HYDRATING IN BACKGROUND — keeping existing ready state active for $_hydratedUserId');
      return;
    }
    _state = _HydrationState.hydrating;
    debugPrint('[HydrationGuard] 🔄 HYDRATING — nutrition memory reads blocked');
  }

  /// Callback triggered when hydration marks complete. Used to notify the
  /// persistence layer to save the owner ID without creating circular imports.
  void Function(String userId)? onHydrationComplete;

  /// Call after cloud hydration succeeds. Opens the gate for [userId] only.
  /// If [userId] is null (should never happen in practice), stays NotReady.
  void markComplete(String? userId) {
    if (userId == null) {
      _state = _HydrationState.notReady;
      _hydratedUserId = null;
      debugPrint('[HydrationGuard] ⚠️  markComplete called with null userId — staying NotReady');
      return;
    }
    _state = _HydrationState.ready;
    _hydratedUserId = userId;
    
    final callback = onHydrationComplete;
    if (callback != null) {
      callback(userId);
    }
    
    debugPrint('[HydrationGuard] ✅ READY — nutrition memory reads enabled for $userId');
  }

  // ── Read-side checks ─────────────────────────────────────────────────────

  /// Returns true ONLY when:
  ///   1. State is Ready
  ///   2. [userId] exactly matches the userId hydrated for
  ///
  /// All other states → false (fail closed).
  bool isReadyForUser(String? userId) {
    if (_state != _HydrationState.ready) return false;
    if (userId == null) return false;
    if (_hydratedUserId != userId) {
      debugPrint('[HydrationGuard] ⛔ OWNERSHIP MISMATCH: '
          'cache owned by $_hydratedUserId, current user is $userId');
      return false;
    }
    return true;
  }

  String? _currentUserIdOverride;

  @visibleForTesting
  set currentUserIdOverride(String? id) => _currentUserIdOverride = id;

  /// The active user ID, respecting test overrides.
  String? get currentUserId {
    if (_currentUserIdOverride != null) return _currentUserIdOverride;
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  /// Convenience getter — reads the current Supabase auth user and checks ownership.
  /// Use this in production lookup code for brevity.
  bool get isReadyForCurrentUser {
    return isReadyForUser(currentUserId);
  }

  // ── Diagnostics ──────────────────────────────────────────────────────────

  String get stateName => switch (_state) {
    _HydrationState.notReady  => 'NotReady',
    _HydrationState.hydrating => 'Hydrating',
    _HydrationState.ready     => 'Ready',
  };

  String? get hydratedUserId => _hydratedUserId;

  @override
  String toString() => 'NutritionHydrationGuard('
      'state=$stateName, userId=$_hydratedUserId)';
}
