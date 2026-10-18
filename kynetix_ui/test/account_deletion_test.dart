import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/screens/account_deletion_screen.dart';
import 'package:kynetix/services/account_deletion_service.dart';
import 'package:kynetix/services/persistence_service.dart';
import 'package:kynetix/services/user_session_coordinator.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _a = '11111111-aaaa-4aaa-8aaa-111111111111';
const _b = '22222222-bbbb-4bbb-8bbb-222222222222';

Map<String, Object> _twoUsers() => {
      // User A
      'day_logs_v1_$_a': '{"2026-10-15":{}}',
      'user_profile_v2_$_a': '{"name":"A"}',
      'onboarding_done_v1_$_a': true,
      'workout_data_v2_$_a': '[]',
      'privacy_consent_v1_$_a': '{"version":"2026-10-16"}',
      'chatgpt_siwc_client_id_$_a': 'client-a',
      'rule_plateau_bench_press_$_a': true,
      'backup_pre_migration_day_logs_v1_$_a': '{}',
      'migration_verified_v1_$_a': true,
      // User B
      'day_logs_v1_$_b': '{"2026-10-15":{"meals":[1]}}',
      'user_profile_v2_$_b': '{"name":"B"}',
      'onboarding_done_v1_$_b': true,
      'workout_data_v2_$_b': '[{"id":1}]',
      'privacy_consent_v1_$_b': '{"version":"2026-10-16"}',
      'migration_verified_v1_$_b': true,
      // Device-wide
      'ui_theme_mode_v1': 'dark',
      'memory_schema_v2_migrated': true,
      'widget_data_v1': '{}',
    };

void main() {
  group('PersistenceService.removeKeysForUser', () {
    test('removes only keys ending in _<userId>', () async {
      SharedPreferences.setMockInitialValues(_twoUsers());
      final prefs = await SharedPreferences.getInstance();

      final removed =
          await PersistenceService.removeKeysForUser(_a, prefsOverride: prefs);

      expect(removed, isNotEmpty);
      for (final k in prefs.getKeys()) {
        expect(k.endsWith('_$_a'), isFalse, reason: '$k should be gone');
      }
      // Other account untouched, values intact.
      expect(prefs.getString('day_logs_v1_$_b'), '{"2026-10-15":{"meals":[1]}}');
      expect(prefs.getString('user_profile_v2_$_b'), '{"name":"B"}');
      expect(prefs.getBool('onboarding_done_v1_$_b'), isTrue);
      expect(prefs.getString('workout_data_v2_$_b'), '[{"id":1}]');
      expect(prefs.getString('privacy_consent_v1_$_b'), isNotNull);
      expect(prefs.getBool('migration_verified_v1_$_b'), isTrue);
      // Device-wide settings kept.
      expect(prefs.getString('ui_theme_mode_v1'), 'dark');
      expect(prefs.getBool('memory_schema_v2_migrated'), isTrue);
    });

    test('a blank user id removes nothing', () async {
      SharedPreferences.setMockInitialValues({
        'odd_key_': 1,
        'ui_theme_mode_v1': 'light',
      });
      final prefs = await SharedPreferences.getInstance();
      final removed =
          await PersistenceService.removeKeysForUser('', prefsOverride: prefs);
      expect(removed, isEmpty);
      expect(prefs.getKeys(), containsAll(['odd_key_', 'ui_theme_mode_v1']));
    });

    test('clears the cached owner pointer only when it names this user',
        () async {
      SharedPreferences.setMockInitialValues({
        ..._twoUsers(),
        'cached_owner_user_id_v1': _b,
      });
      final prefs = await SharedPreferences.getInstance();
      await PersistenceService.removeKeysForUser(_a, prefsOverride: prefs);
      expect(prefs.getString('cached_owner_user_id_v1'), _b);

      await PersistenceService.removeKeysForUser(_b, prefsOverride: prefs);
      expect(prefs.getString('cached_owner_user_id_v1'), isNull);
    });
  });

  group('AccountDeletionService.wipeLocalData', () {
    test('keeps other users and device settings', () async {
      SharedPreferences.setMockInitialValues(_twoUsers());
      final prefs = await SharedPreferences.getInstance();
      final before = Map.fromEntries(prefs
          .getKeys()
          .where((k) => !k.endsWith('_$_a'))
          .map((k) => MapEntry(k, prefs.get(k))));

      await AccountDeletionService.wipeLocalData(_a,
          prefsOverride: prefs, clearMemory: false);

      final after = {for (final k in prefs.getKeys()) k: prefs.get(k)};
      // A was the (back-filled) legacy owner: the claim now names nobody, so
      // B can never be derived as owner from its migration marker.
      expect(after.remove(UserSessionCoordinator.legacyOwnerKey),
          UserSessionCoordinator.legacyOwnerDeleted);
      expect(after, before);
    });

    test('full wipe (in-memory services too) keeps the other account',
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(_twoUsers());
      await AccountDeletionService.wipeLocalData(_a);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((k) => k.endsWith('_$_a')), isEmpty);
      expect(prefs.getString('day_logs_v1_$_b'), '{"2026-10-15":{"meals":[1]}}');
      expect(prefs.getString('ui_theme_mode_v1'), 'dark');
    });

    test('removes legacy unscoped stores only when this user owns them',
        () async {
      SharedPreferences.setMockInitialValues({
        ..._twoUsers(),
        UserSessionCoordinator.legacyOwnerKey: _a,
        'day_logs_v1': '{"legacy":true}',
        'workout_data_v2': '[]',
        'onboarding_done_v1': true,
      });
      final prefs = await SharedPreferences.getInstance();

      // B does not own them: untouched.
      await AccountDeletionService.wipeLocalData(_b,
          prefsOverride: prefs, clearMemory: false);
      expect(prefs.getString('day_logs_v1'), '{"legacy":true}');
      expect(prefs.getString(UserSessionCoordinator.legacyOwnerKey), _a);
      expect(prefs.getString('day_logs_v1_$_a'), isNotNull);

      // A owns them: gone.
      await AccountDeletionService.wipeLocalData(_a,
          prefsOverride: prefs, clearMemory: false);
      expect(prefs.getString('day_logs_v1'), isNull);
      expect(prefs.getString('workout_data_v2'), isNull);
      expect(prefs.getBool('onboarding_done_v1'), isNull);
      // The claim stays, pointing at nobody, so it is never re-derived.
      expect(prefs.getString(UserSessionCoordinator.legacyOwnerKey),
          UserSessionCoordinator.legacyOwnerDeleted);
      expect(prefs.getString('ui_theme_mode_v1'), 'dark');
    });
  });

  group('AccountDeletionService.deleteAccount', () {
    late List<String> calls;

    AccountDeletionService service({
      Future<Object?> Function()? invoke,
      String? userId = _a,
    }) =>
        AccountDeletionService(
          currentUserId: () => userId,
          flushPending: () async => calls.add('flush'),
          invokeDelete: invoke ??
              () async {
                calls.add('invoke');
                return {'deleted': true};
              },
          wipeLocal: (uid) async => calls.add('wipe:$uid'),
          signOut: () async => calls.add('signOut'),
        );

    setUp(() => calls = []);

    test('success: server, then local wipe, then sign-out', () async {
      await service().deleteAccount();
      expect(calls, ['flush', 'invoke', 'wipe:$_a', 'signOut']);
    });

    test('accepts a JSON string body', () async {
      await service(invoke: () async => '{"deleted":true}').deleteAccount();
      expect(calls, contains('wipe:$_a'));
    });

    test('server error: nothing local is deleted', () async {
      await expectLater(
        service(invoke: () async => throw Exception('500')).deleteAccount(),
        throwsA(isA<AccountDeletionException>()),
      );
      expect(calls, ['flush']);
    });

    test('unconfirmed response: nothing local is deleted', () async {
      await expectLater(
        service(invoke: () async => {'deleted': false}).deleteAccount(),
        throwsA(isA<AccountDeletionException>()),
      );
      expect(calls.where((c) => c.startsWith('wipe')), isEmpty);
      expect(calls, isNot(contains('signOut')));
    });

    test('signed out: refuses without calling the server', () async {
      await expectLater(
        service(userId: null).deleteAccount(),
        throwsA(isA<AccountDeletionException>()),
      );
      expect(calls, isEmpty);
    });

    test('confirm phrase is exact', () {
      expect(AccountDeletionService.isConfirmed('DELETE'), isTrue);
      expect(AccountDeletionService.isConfirmed(' DELETE '), isTrue);
      expect(AccountDeletionService.isConfirmed('delete'), isFalse);
      expect(AccountDeletionService.isConfirmed('DELET'), isFalse);
    });
  });

  group('AccountDeletionScreen', () {
    testWidgets('needs DELETE, and a failure shows an error and wipes nothing',
        (tester) async {
      final calls = <String>[];
      final svc = AccountDeletionService(
        currentUserId: () => _a,
        flushPending: () async {},
        invokeDelete: () async => throw Exception('offline'),
        wipeLocal: (uid) async => calls.add('wipe'),
        signOut: () async => calls.add('signOut'),
      );
      await tester.pumpWidget(MaterialApp(
        home: AccountDeletionScreen(service: svc, onDeleted: () => calls.add('done')),
      ));
      await tester.pumpAndSettle();

      expect(find.text("This can't be undone. Once it's deleted, we can't bring any of it back."),
          findsOneWidget);

      // Disabled until the phrase matches.
      await tester.ensureVisible(find.text('Delete my account'));
      await tester.tap(find.text('Delete my account'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(find.text(AccountDeletionService.failureMessage), findsNothing);

      await tester.enterText(find.byKey(const ValueKey('delete-confirm-field')), 'DELETE');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Delete my account'));
      await tester.tap(find.text('Delete my account'));
      await tester.pumpAndSettle();

      expect(find.text(AccountDeletionService.failureMessage), findsOneWidget);
      expect(calls, isEmpty);
    });

    testWidgets('success calls onDeleted', (tester) async {
      final calls = <String>[];
      final svc = AccountDeletionService(
        currentUserId: () => _a,
        flushPending: () async {},
        invokeDelete: () async => {'deleted': true},
        wipeLocal: (uid) async => calls.add('wipe'),
        signOut: () async => calls.add('signOut'),
      );
      await tester.pumpWidget(MaterialApp(
        home: AccountDeletionScreen(service: svc, onDeleted: () => calls.add('done')),
      ));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('delete-confirm-field')), 'DELETE');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Delete my account'));
      await tester.tap(find.text('Delete my account'));
      await tester.pumpAndSettle();
      expect(calls, ['wipe', 'signOut', 'done']);
    });
  });
}
