import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/services/secure_session_storage.dart';

class _MemStore implements SessionKeyValueStore {
  _MemStore([Map<String, String>? initial]) : data = {...?initial};

  final Map<String, String> data;
  bool failReads = false;
  bool failWrites = false;
  bool corruptWrites = false;

  @override
  Future<String?> read(String key) async {
    if (failReads) throw Exception('keystore read failed');
    return data[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw Exception('keystore write failed');
    data[key] = corruptWrites ? 'garbage' : value;
  }

  @override
  Future<void> delete(String key) async {
    if (failWrites) throw Exception('keystore delete failed');
    data.remove(key);
  }
}

void main() {
  const key = 'sb-sjrcqvqhycxtwwbivizy-auth-token';
  const session = '{"access_token":"a","refresh_token":"r"}';

  SecureSessionStorage storage(_MemStore secure, _MemStore legacy) =>
      SecureSessionStorage(persistSessionKey: key, secure: secure, legacy: legacy);

  test('key matches supabase_flutter default for the project url', () {
    expect(
      SecureSessionStorage.defaultPersistSessionKey('https://sjrcqvqhycxtwwbivizy.supabase.co'),
      key,
    );
  });

  test('migrates an existing prefs session into secure storage, then removes it', () async {
    final secure = _MemStore();
    final legacy = _MemStore({key: session, 'other': 'kept'});
    final s = storage(secure, legacy);
    await s.initialize();

    expect(await s.hasAccessToken(), isTrue);
    expect(await s.accessToken(), session);
    expect(secure.data[key], session);
    expect(legacy.data.containsKey(key), isFalse);
    expect(legacy.data['other'], 'kept');
    expect(s.usingFallback, isFalse);
  });

  test('prefs copy wins over a stale secure copy (written during a fallback)', () async {
    final secure = _MemStore({key: 'stale'});
    final legacy = _MemStore({key: session});
    final s = storage(secure, legacy);
    await s.initialize();
    expect(await s.accessToken(), session);
    expect(secure.data[key], session);
    expect(legacy.data.containsKey(key), isFalse);
  });

  test('reads an already-migrated session from secure storage', () async {
    final s = storage(_MemStore({key: session}), _MemStore());
    await s.initialize();
    expect(await s.accessToken(), session);
  });

  test('no session anywhere means signed out', () async {
    final s = storage(_MemStore(), _MemStore());
    await s.initialize();
    expect(await s.hasAccessToken(), isFalse);
    expect(await s.accessToken(), isNull);
  });

  test('secure write failure during migration keeps the prefs session', () async {
    final secure = _MemStore()..failWrites = true;
    final legacy = _MemStore({key: session});
    final s = storage(secure, legacy);
    await s.initialize();

    expect(await s.accessToken(), session);
    expect(legacy.data[key], session);
    expect(s.usingFallback, isTrue);

    await s.persistSession('refreshed');
    expect(legacy.data[key], 'refreshed');
  });

  test('read-back mismatch keeps the prefs session', () async {
    final secure = _MemStore()..corruptWrites = true;
    final legacy = _MemStore({key: session});
    final s = storage(secure, legacy);
    await s.initialize();
    expect(await s.accessToken(), session);
    expect(legacy.data[key], session);
    expect(s.usingFallback, isTrue);
  });

  test('unreadable secure storage falls back to prefs for writes', () async {
    final secure = _MemStore()..failReads = true..failWrites = true;
    final legacy = _MemStore();
    final s = storage(secure, legacy);
    await s.initialize();
    expect(s.usingFallback, isTrue);
    await s.persistSession(session);
    expect(legacy.data[key], session);

    // Next launch with a healthy keystore migrates it.
    final next = storage(_MemStore(), legacy);
    await next.initialize();
    expect(await next.accessToken(), session);
    expect(legacy.data.containsKey(key), isFalse);
  });

  test('persist writes to secure storage; a failing write falls back', () async {
    final secure = _MemStore();
    final legacy = _MemStore();
    final s = storage(secure, legacy);
    await s.initialize();
    await s.persistSession('one');
    expect(secure.data[key], 'one');
    expect(legacy.data.containsKey(key), isFalse);

    secure.failWrites = true;
    await s.persistSession('two');
    expect(legacy.data[key], 'two');
    expect(await s.accessToken(), 'two');
  });

  test('concurrent persists land in order', () async {
    final secure = _MemStore();
    final s = storage(secure, _MemStore());
    await s.initialize();
    final a = s.persistSession('a');
    final b = s.persistSession('b');
    await Future.wait([a, b]);
    expect(secure.data[key], 'b');
  });

  test('remove clears both stores', () async {
    final secure = _MemStore({key: session});
    final legacy = _MemStore({key: session});
    final s = storage(secure, legacy);
    await s.initialize();
    await s.removePersistedSession();
    expect(await s.hasAccessToken(), isFalse);
    expect(secure.data.containsKey(key), isFalse);
    expect(legacy.data.containsKey(key), isFalse);
  });
}
