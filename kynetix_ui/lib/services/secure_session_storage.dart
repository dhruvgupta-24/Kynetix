import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A minimal string key-value store, so the session logic can be tested
/// without platform channels.
abstract class SessionKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Keystore/Keychain-backed store (flutter_secure_storage).
class SecureKeyValueStore implements SessionKeyValueStore {
  SecureKeyValueStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              // v10 default ciphers (RSA OAEP + AES-GCM). resetOnError: false
              // so a keystore failure surfaces as an exception (and we fall
              // back to SharedPreferences) instead of silently wiping the
              // store and signing the user out.
              aOptions: AndroidOptions(resetOnError: false),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Plain SharedPreferences store: where supabase_flutter kept the session
/// before, and the fallback when secure storage is unusable on a device.
class PrefsKeyValueStore implements SessionKeyValueStore {
  Future<SharedPreferences>? _prefs;

  Future<SharedPreferences> get _instance {
    WidgetsFlutterBinding.ensureInitialized();
    return _prefs ??= SharedPreferences.getInstance();
  }

  @override
  Future<String?> read(String key) async => (await _instance).getString(key);

  @override
  Future<void> write(String key, String value) async {
    await (await _instance).setString(key, value);
  }

  @override
  Future<void> delete(String key) async {
    await (await _instance).remove(key);
  }
}

/// Persists the Supabase auth session in secure storage instead of plain
/// SharedPreferences.
///
/// Migration: supabase_flutter's default [SharedPreferencesLocalStorage]
/// stored the session under `sb-<project-ref>-auth-token` in
/// SharedPreferences. On [initialize], a session found there is copied into
/// secure storage (verified by reading it back) and only then removed from
/// SharedPreferences, so signed-in users stay signed in.
///
/// Invariant: a session is in SharedPreferences only if it is the newest one
/// (pre-migration, or written while secure storage was failing), because
/// every successful secure write deletes the SharedPreferences copy. So on
/// start-up the SharedPreferences copy, when present, always wins.
///
/// If secure storage throws at any point, this falls back to
/// SharedPreferences for the rest of the app session rather than losing the
/// session.
///
/// Only the session moves. The PKCE code verifier (`pkceAsyncStorage`) keeps
/// supabase_flutter's default SharedPreferences store: it is short-lived and
/// unrelated to this key.
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage({
    required this.persistSessionKey,
    SessionKeyValueStore? secure,
    SessionKeyValueStore? legacy,
  })  : _secure = secure ?? SecureKeyValueStore(),
        _legacy = legacy ?? PrefsKeyValueStore();

  /// The key supabase_flutter 2.x uses by default for [supabaseUrl]
  /// (see `Supabase.initialize`): `sb-<first host label>-auth-token`.
  static String defaultPersistSessionKey(String supabaseUrl) =>
      'sb-${Uri.parse(supabaseUrl).host.split('.').first}-auth-token';

  final String persistSessionKey;
  final SessionKeyValueStore _secure;
  final SessionKeyValueStore _legacy;

  bool _useLegacy = false;
  String? _session;

  /// Serialises writes: supabase_flutter persists without awaiting, so two
  /// token refreshes could otherwise interleave.
  Future<void> _queue = Future<void>.value();

  @visibleForTesting
  bool get usingFallback => _useLegacy;

  @override
  Future<void> initialize() async {
    String? legacy;
    try {
      legacy = await _legacy.read(persistSessionKey);
    } catch (_) {
      legacy = null;
    }

    if (legacy != null) {
      _session = legacy;
      try {
        await _secure.write(persistSessionKey, legacy);
        final check = await _secure.read(persistSessionKey);
        if (check != legacy) throw StateError('secure storage read-back mismatch');
      } catch (e) {
        debugPrint('[SecureSessionStorage] Secure storage unavailable, keeping prefs: $e');
        _useLegacy = true;
        return;
      }
      try {
        await _legacy.delete(persistSessionKey);
      } catch (_) {
        // Harmless: next start migrates the same (identical) value again.
      }
      return;
    }

    try {
      _session = await _secure.read(persistSessionKey);
    } catch (e) {
      debugPrint('[SecureSessionStorage] Secure storage unreadable, using prefs: $e');
      _useLegacy = true;
      _session = null;
    }
  }

  @override
  Future<bool> hasAccessToken() async => _session != null;

  @override
  Future<String?> accessToken() async => _session;

  @override
  Future<void> persistSession(String persistSessionString) {
    _session = persistSessionString;
    return _enqueue(() async {
      if (!_useLegacy) {
        try {
          await _secure.write(persistSessionKey, persistSessionString);
          try {
            await _legacy.delete(persistSessionKey);
          } catch (_) {}
          return;
        } catch (e) {
          debugPrint('[SecureSessionStorage] Secure write failed, using prefs: $e');
          _useLegacy = true;
        }
      }
      await _legacy.write(persistSessionKey, persistSessionString);
    });
  }

  @override
  Future<void> removePersistedSession() {
    _session = null;
    return _enqueue(() async {
      try {
        await _secure.delete(persistSessionKey);
      } catch (_) {}
      try {
        await _legacy.delete(persistSessionKey);
      } catch (_) {}
    });
  }

  Future<void> _enqueue(Future<void> Function() op) {
    final next = _queue.then((_) => op());
    _queue = next.catchError((Object _) {});
    return next;
  }
}
