import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One user's agreement to the privacy policy (and the 18+ confirmation).
@immutable
class ConsentRecord {
  const ConsentRecord({
    required this.version,
    required this.consentedAt,
    required this.ageConfirmedAdult,
    this.synced = false,
  });

  final String version;
  final DateTime consentedAt;
  final bool ageConfirmedAdult;

  /// Written to the `profiles` row as well (best effort).
  final bool synced;

  /// Valid for the current policy: right version and 18+ confirmed.
  bool get isCurrent =>
      version == ConsentService.policyVersion && ageConfirmedAdult;

  ConsentRecord copyWith({bool? synced}) => ConsentRecord(
        version: version,
        consentedAt: consentedAt,
        ageConfirmedAdult: ageConfirmedAdult,
        synced: synced ?? this.synced,
      );

  Map<String, Object?> toJson() => {
        'version': version,
        'at': consentedAt.toUtc().toIso8601String(),
        'adult': ageConfirmedAdult,
        'synced': synced,
      };

  static ConsentRecord? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return null;
      final v = m['version'];
      final at = DateTime.tryParse('${m['at']}');
      if (v is! String || at == null) return null;
      return ConsentRecord(
        version: v,
        consentedAt: at,
        ageConfirmedAdult: m['adult'] == true,
        synced: m['synced'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Stores privacy consent per user: locally in prefs
/// (`privacy_consent_v1_<userId>`) and, best effort, in the user's `profiles`
/// row (`privacy_consent_at`, `privacy_policy_version`,
/// `age_confirmed_adult`). Never blocks on the network.
class ConsentService {
  ConsentService._();
  static final ConsentService instance = ConsentService._();

  /// Bump when the policy changes in a way that needs fresh consent.
  static const policyVersion = '2026-10-20b';

  static String prefsKey(String userId) => 'privacy_consent_v1_$userId';

  SharedPreferences? _prefs;

  /// Test hook: use this prefs instance instead of the shared one.
  @visibleForTesting
  set prefsOverride(SharedPreferences? p) => _prefs = p;

  Future<SharedPreferences> _p() async =>
      _prefs ??= await SharedPreferences.getInstance();

  /// Starts loading prefs so [peek] can answer synchronously later.
  Future<void> warmUp() async {
    try {
      await _p();
    } catch (_) {}
  }

  /// Synchronous answer when prefs are already loaded: true/false, or null
  /// when it isn't known yet.
  bool? peek(String userId) {
    final p = _prefs;
    if (p == null || userId.isEmpty) return null;
    return ConsentRecord.tryParse(p.getString(prefsKey(userId)))?.isCurrent ??
        false;
  }

  Future<ConsentRecord?> readLocal(String userId) async {
    try {
      return ConsentRecord.tryParse((await _p()).getString(prefsKey(userId)));
    } catch (_) {
      return null;
    }
  }

  Future<bool> hasConsented(String userId) async =>
      (await readLocal(userId))?.isCurrent ?? false;

  /// Records consent locally (awaited) and pushes it to the profile row in
  /// the background.
  Future<void> recordConsent(
    String userId, {
    required bool ageConfirmedAdult,
    DateTime? now,
    bool syncRemote = true,
  }) async {
    if (userId.isEmpty) return;
    final record = ConsentRecord(
      version: policyVersion,
      consentedAt: now ?? DateTime.now(),
      ageConfirmedAdult: ageConfirmedAdult,
    );
    await _write(userId, record);
    if (syncRemote) unawaited(syncToCloud(userId));
  }

  Future<void> _write(String userId, ConsentRecord r) async {
    try {
      await (await _p()).setString(prefsKey(userId), jsonEncode(r.toJson()));
    } catch (_) {}
  }

  /// Writes the local record to `profiles` if it isn't there yet. Updates
  /// the existing row only (never creates a half-empty profile). Returns
  /// true once the server has it. Never throws.
  Future<bool> syncToCloud(String userId) async {
    try {
      final local = await readLocal(userId);
      if (local == null) return false;
      if (local.synced) return true;
      final client = Supabase.instance.client;
      if (client.auth.currentSession?.user.id != userId) return false;
      final rows = await client
          .from('profiles')
          .update({
            'privacy_consent_at': local.consentedAt.toUtc().toIso8601String(),
            'privacy_policy_version': local.version,
            'age_confirmed_adult': local.ageConfirmedAdult,
          })
          .eq('id', userId)
          .select('id')
          .timeout(const Duration(seconds: 10));
      // No row yet (brand-new account mid-onboarding): try again later.
      if (rows.isEmpty) return false;
      await _write(userId, local.copyWith(synced: true));
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[ConsentService] sync skipped: $e');
      return false;
    }
  }

  /// For a reinstall or a new phone: if the profile row already holds
  /// consent to the current policy, copy it to this device. Returns whether
  /// the user now has current consent locally. Never throws.
  Future<bool> restoreFromCloud(
    String userId, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      final client = Supabase.instance.client;
      if (client.auth.currentSession?.user.id != userId) return false;
      final row = await client
          .from('profiles')
          .select('privacy_consent_at, privacy_policy_version, age_confirmed_adult')
          .eq('id', userId)
          .maybeSingle()
          .timeout(timeout);
      if (row == null) return false;
      final at = DateTime.tryParse('${row['privacy_consent_at']}');
      final version = row['privacy_policy_version'];
      if (at == null || version is! String) return false;
      final record = ConsentRecord(
        version: version,
        consentedAt: at,
        ageConfirmedAdult: row['age_confirmed_adult'] == true,
        synced: true,
      );
      if (!record.isCurrent) return false;
      await _write(userId, record);
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[ConsentService] restore skipped: $e');
      return false;
    }
  }
}
