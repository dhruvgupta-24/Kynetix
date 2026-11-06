import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Where a teen account's parent check stands.
enum GuardianStatus { none, pending, approved, declined, revoked, expired }

GuardianStatus guardianStatusFrom(Object? v) => switch (v) {
      'pending' => GuardianStatus.pending,
      'approved' => GuardianStatus.approved,
      'declined' => GuardianStatus.declined,
      'revoked' => GuardianStatus.revoked,
      'expired' => GuardianStatus.expired,
      _ => GuardianStatus.none,
    };

/// The answer to a link request: the status, and the link to share (null
/// when the account is already approved).
@immutable
class GuardianLink {
  const GuardianLink({required this.status, this.link, this.expiresAt});
  final GuardianStatus status;
  final String? link;
  final DateTime? expiresAt;
}

class GuardianException implements Exception {
  const GuardianException(this.message, {this.code});
  final String message;
  final String? code;
  @override
  String toString() => 'GuardianException($code)';
}

/// Calls the guardian-consent function. Tests swap it for a fake.
typedef GuardianTransport = Future<Map<String, dynamic>> Function(Map<String, dynamic> body);

/// A parent's OK for a teen account (13 to 17), per user.
///
/// The server (guardian-consent + guardian_consents) is the record. This keeps
/// the last known status in prefs (`guardian_v1_<userId>`) so an approved
/// teen gets straight in offline, and refreshes it on launch so a parent
/// switching it off takes effect.
class GuardianService {
  GuardianService._();
  static final GuardianService instance = GuardianService._();

  static String prefsKey(String userId) => 'guardian_v1_$userId';

  SharedPreferences? _prefs;
  GuardianTransport? _transport;

  @visibleForTesting
  set prefsOverride(SharedPreferences? p) => _prefs = p;

  @visibleForTesting
  set transportOverride(GuardianTransport? t) => _transport = t;

  Future<SharedPreferences> _p() async => _prefs ??= await SharedPreferences.getInstance();

  Future<void> warmUp() async {
    try {
      await _p();
    } catch (_) {}
  }

  /// The last known status, synchronously, once prefs are loaded.
  GuardianStatus? peek(String userId) {
    final p = _prefs;
    if (p == null || userId.isEmpty) return null;
    return guardianStatusFrom(p.getString(prefsKey(userId)));
  }

  Future<void> _store(String userId, GuardianStatus s) async {
    try {
      await (await _p()).setString(prefsKey(userId), s.name);
    } catch (_) {}
  }

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
    final t = _transport;
    if (t != null) return t(body);
    final client = Supabase.instance.client;
    final session = client.auth.currentSession;
    if (session == null) throw const GuardianException('Sign in again to carry on.', code: 'unauthorized');
    try {
      final res = await client.functions
          .invoke(
            'guardian-consent',
            body: body,
            headers: {'Authorization': 'Bearer ${session.accessToken}'},
          )
          .timeout(const Duration(seconds: 15));
      final data = res.data;
      if (data is Map) return data.cast<String, dynamic>();
      throw const GuardianException("Couldn't reach Kynetix. Try again in a moment.");
    } on FunctionException catch (e) {
      final d = e.details;
      if (d is Map && d['message'] is String) {
        throw GuardianException(d['message'] as String, code: d['error'] as String?);
      }
      throw const GuardianException("Couldn't reach Kynetix. Try again in a moment.");
    } on TimeoutException {
      throw const GuardianException("That took too long. Check your connection and try again.");
    }
  }

  /// Makes a fresh link for a parent (any earlier one stops working).
  Future<GuardianLink> requestLink({
    required String userId,
    required DateTime dateOfBirth,
    required String firstName,
  }) async {
    final d = dateOfBirth;
    final dob = '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final data = await _call({'action': 'request', 'dob': dob, 'first_name': firstName.trim()});
    final status = guardianStatusFrom(data['status']);
    await _store(userId, status);
    return GuardianLink(
      status: status,
      link: data['link'] as String?,
      expiresAt: DateTime.tryParse('${data['expires_at']}'),
    );
  }

  /// Asks the server. Offline or failing, returns the last known status
  /// (null if there is none) and never throws.
  Future<GuardianStatus?> refresh(String userId) async {
    try {
      final data = await _call({'action': 'status'});
      final s = guardianStatusFrom(data['status']);
      await _store(userId, s);
      return s;
    } catch (e) {
      if (kDebugMode) debugPrint('[GuardianService] refresh skipped: $e');
      await warmUp();
      return peek(userId);
    }
  }

  /// Forgets the local copy (sign out / account switch).
  Future<void> clear(String userId) async {
    try {
      await (await _p()).remove(prefsKey(userId));
    } catch (_) {}
  }
}
