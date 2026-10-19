import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_secrets.dart';
import 'auth_service.dart';
import 'persistence_service.dart';
import 'user_session_coordinator.dart';
import 'widget_service.dart';
import 'internal/net_timeouts.dart';
import 'analytics_service.dart';

/// Why an account deletion did not go through. Nothing local was removed.
class AccountDeletionException implements Exception {
  const AccountDeletionException(this.message);

  /// Calm, user-facing copy (never raw exception text).
  final String message;

  @override
  String toString() => 'AccountDeletionException: $message';
}

/// Deletes the signed-in user's account: server first (the `delete-account`
/// edge function), then only this user's data on this phone, then sign-out.
///
/// The order is the safety property: if the server call fails, nothing on
/// the device is touched. Local data is wiped only after the server confirms
/// `{deleted: true}`.
class AccountDeletionService {
  AccountDeletionService({
    String? Function()? currentUserId,
    Future<Object?> Function()? invokeDelete,
    Future<void> Function()? flushPending,
    Future<void> Function(String userId)? wipeLocal,
    Future<void> Function()? signOut,
  })  : _currentUserId = currentUserId ?? _defaultUserId,
        _invokeDelete = invokeDelete ?? _defaultInvoke,
        _flushPending = flushPending ?? PersistenceService.flushForSessionEnd,
        _wipeLocal = wipeLocal ?? wipeLocalData,
        _signOut = signOut ?? _defaultSignOut;

  static final AccountDeletionService instance = AccountDeletionService();

  /// What the user must type to confirm. Case-sensitive.
  static const confirmPhrase = 'DELETE';

  static bool isConfirmed(String typed) => typed.trim() == confirmPhrase;

  static const failureMessage =
      "Couldn't delete your account. Nothing was removed. "
      'Check your connection and try again.';

  final String? Function() _currentUserId;
  final Future<Object?> Function() _invokeDelete;
  final Future<void> Function() _flushPending;
  final Future<void> Function(String userId) _wipeLocal;
  final Future<void> Function() _signOut;

  bool _running = false;

  /// Runs the whole deletion. Throws [AccountDeletionException] when the
  /// server did not confirm; in that case no local data was removed.
  Future<void> deleteAccount() async {
    if (_running) throw const AccountDeletionException(failureMessage);
    _running = true;
    try {
      final userId = _currentUserId();
      if (userId == null || userId.isEmpty) {
        throw const AccountDeletionException(
          "You're signed out, so there's no account to delete here. "
          'Sign in and try again.',
        );
      }

      // Land queued local writes and uploads first, so nothing from this
      // account is still on its way to the server after it is deleted.
      try {
        await _flushPending();
      } catch (_) {}
      // Goes up now; the row is then deleted with the account like the rest.
      AnalyticsService.instance.track('account_deleted');
      await AnalyticsService.instance.flushBeforeSignOut();

      final Object? response;
      try {
        response = await _invokeDelete();
      } catch (e) {
        if (kDebugMode) debugPrint('[AccountDeletion] delete-account failed: $e');
        throw const AccountDeletionException(failureMessage);
      }
      if (!_confirmsDeleted(response)) {
        throw const AccountDeletionException(failureMessage);
      }

      // Server confirmed. Now remove this account, and only this account,
      // from the phone.
      try {
        await _wipeLocal(userId);
      } catch (e) {
        if (kDebugMode) debugPrint('[AccountDeletion] local wipe error: $e');
      }
      try {
        await _signOut();
      } catch (e) {
        if (kDebugMode) debugPrint('[AccountDeletion] sign-out error: $e');
      }
    } finally {
      _running = false;
    }
  }

  static bool _confirmsDeleted(Object? data) {
    Object? d = data;
    if (d is String) {
      try {
        d = jsonDecode(d);
      } catch (_) {
        return false;
      }
    }
    return d is Map && d['deleted'] == true;
  }

  /// The device-wide (pre-multi-user) stores that hold the legacy owner's
  /// data, plus the migration's device-wide backups of them. Removed only
  /// when the legacy owner deletes their account. Device settings (theme,
  /// consent records, migration sentinels) are not in this list.
  static List<String> get legacyStoreKeys => [
        for (final k in UserSessionCoordinator.unscopedKeys) ...[
          k,
          'backup_pre_migration_$k',
        ],
        'onboarding_done_v1',
        'quick_add_custom_items_v2',
        'quick_add_custom_items',
        'eating_pattern_seeded_anchor_v1',
        'carry_forward_resolved_dates_v1',
        'carry_forward_history_v1',
      ];

  /// Removes [userId]'s local data: the in-memory state (via
  /// [UserSessionCoordinator.clearAllUserServices]) and every stored
  /// `*_<userId>` key. If this account also owns the device's legacy
  /// pre-multi-user stores, those go too. Other accounts' keys and
  /// device-wide settings (theme, migration sentinels) are kept.
  static Future<void> wipeLocalData(
    String userId, {
    SharedPreferences? prefsOverride,
    bool clearMemory = true,
  }) async {
    if (userId.trim().isEmpty) return;
    if (clearMemory) {
      await UserSessionCoordinator.instance.clearAllUserServices();
    }
    final prefs = prefsOverride ?? await SharedPreferences.getInstance();

    // Legacy unscoped stores belong to exactly one account; read the owner
    // before the per-user keys (its back-fill markers) are removed.
    final ownsLegacy = UserSessionCoordinator.legacyOwner(prefs) == userId;

    await PersistenceService.removeKeysForUser(userId, prefsOverride: prefs);

    if (ownsLegacy) {
      for (final k in legacyStoreKeys) {
        await prefs.remove(k);
      }
      // Keep the claim, pointing at nobody: removing it would let
      // legacyOwner() re-derive an owner from another account's migration
      // marker and hand that account whatever legacy data is left.
      await prefs.setString(UserSessionCoordinator.legacyOwnerKey,
          UserSessionCoordinator.legacyOwnerDeleted);
    }
    if (prefs.getString('dev_auto_login_user_id') == userId) {
      await prefs.remove('dev_auto_login_user_id');
    }

    if (clearMemory) {
      // The home-screen widget shows today's numbers; with no profile in
      // memory this clears it.
      try {
        await WidgetService.updateWidgetData();
      } catch (_) {}
    }
  }

  // ── Defaults ──────────────────────────────────────────────────────────────

  static String? _defaultUserId() =>
      Supabase.instance.client.auth.currentSession?.user.id;

  static Future<Object?> _defaultInvoke() async {
    final res = await Supabase.instance.client.functions.invoke(
      'delete-account',
      body: const {'confirm': confirmPhrase},
    ).within(NetTimeouts.accountDeletion, 'account deletion');
    return res.data;
  }

  static Future<void> _defaultSignOut() async {
    // Revoke the Google grant too, so the deleted account no longer shows
    // Kynetix as a connected app. Best effort.
    try {
      await GoogleSignIn(
        serverClientId: SupabaseSecrets.googleWebClientId.isNotEmpty
            ? SupabaseSecrets.googleWebClientId
            : null,
      ).disconnect();
    } catch (_) {}
    try {
      await const AuthService().signOut();
    } catch (_) {
      // The server user is gone, so a global sign-out can be refused; drop
      // the local session regardless.
      try {
        await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
      } catch (_) {}
    }
  }
}
