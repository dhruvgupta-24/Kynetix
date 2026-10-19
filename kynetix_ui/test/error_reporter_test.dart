import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/services/error_reporter.dart';

void main() {
  group('ErrorReporter.scrub', () {
    test('removes emails, phone numbers and tokens', () {
      final out = ErrorReporter.scrub(
        'Login failed for dhruv.gupta+test@example.co.in, phone +91 98765 43210 '
        '(alt 9876543210), Bearer abcdefghijklmnop1234, '
        'jwt eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMifQ.c2lnbmF0dXJl',
      );
      expect(out, isNot(contains('example.co.in')));
      expect(out, isNot(contains('98765')));
      expect(out, isNot(contains('9876543210')));
      expect(out, isNot(contains('abcdefghijklmnop1234')));
      expect(out, isNot(contains('eyJ')));
      expect(out, contains('[email]'));
      expect(out, contains('[phone]'));
      expect(out, contains('[token]'));
    });

    test('keeps ordinary numbers and stack positions', () {
      const s = 'RangeError (index): 3 of 12 at file.dart:120:15';
      expect(ErrorReporter.scrub(s), s);
    });

    test('truncates stacks', () {
      final stack = StackTrace.fromString(
          List.generate(200, (i) => '#$i      frame$i (package:kynetix/x.dart:$i:1)').join('\n'));
      final out = ErrorReporter.scrubStack(stack)!;
      expect(out.split('\n').length, lessThanOrEqualTo(ErrorReporter.maxStackLines));
      expect(out.length, lessThanOrEqualTo(ErrorReporter.maxStackLength + 1));
    });
  });

  group('ErrorReporter.report', () {
    test('sends a scrubbed row with the expected columns', () async {
      final sent = <Map<String, Object?>>[];
      final r = ErrorReporter.forTesting(transport: (row) async => sent.add(row));
      r.report(StateError('bad user a@b.com'), StackTrace.current, type: 'flutter');
      await Future<void>.delayed(Duration.zero);
      expect(sent, hasLength(1));
      final row = sent.single;
      expect(row.keys, containsAll(['user_id', 'app_version', 'platform', 'error_type', 'message', 'stack']));
      expect(row['message'], isNot(contains('a@b.com')));
      expect(row['error_type'], 'flutter:StateError');
    });

    test('de-duplicates and caps at 20 per session', () async {
      final sent = <Map<String, Object?>>[];
      final r = ErrorReporter.forTesting(transport: (row) async => sent.add(row));
      final st = StackTrace.current;
      for (var i = 0; i < 5; i++) {
        r.report(Exception('same'), st);
      }
      expect(sent, hasLength(1));
      for (var i = 0; i < 50; i++) {
        r.report(Exception('distinct $i'), st);
      }
      expect(sent, hasLength(ErrorReporter.maxPerSession));
    });

    test('never throws, even when the transport fails', () async {
      final r = ErrorReporter.forTesting(transport: (_) async => throw Exception('offline'));
      expect(() => r.report(Exception('x'), null), returnsNormally);
      final sync = ErrorReporter.forTesting(transport: (_) => throw Exception('sync'));
      expect(() => sync.report(Exception('y'), null), returnsNormally);
      await Future<void>.delayed(Duration.zero);
    });

    test('is a no-op in debug unless enabled, and when signed out', () async {
      final sent = <Map<String, Object?>>[];
      final debug = ErrorReporter.forTesting(
          transport: (row) async => sent.add(row), debugMode: true);
      debug.report(Exception('debug'), null);
      expect(sent, isEmpty);

      final signedOut = ErrorReporter.forTesting(
          transport: (row) async => sent.add(row), currentUserId: () => null);
      signedOut.report(Exception('anon'), null);
      expect(sent, isEmpty);
    });
  });

  group('ErrorReporter signed-out queue', () {
    test('queues while signed out and flushes on sign-in', () async {
      final sent = <Map<String, Object?>>[];
      final signIns = StreamController<void>.broadcast();
      String? user;
      final r = ErrorReporter.forTesting(
        transport: (row) async => sent.add(row),
        currentUserId: () => user,
        appVersion: () => '2.3.4+56',
        signedInEvents: () => signIns.stream,
      );

      r.report(StateError('onboarding broke for a@b.com'), StackTrace.current, type: 'flutter');
      r.report(Exception('auth broke'), null);
      expect(sent, isEmpty);
      expect(r.pendingCount, 2);

      user = 'user-1';
      signIns.add(null);
      await Future<void>.delayed(Duration.zero);

      expect(sent, hasLength(2));
      expect(r.pendingCount, 0);
      for (final row in sent) {
        expect(row['user_id'], 'user-1');
        expect(row['app_version'], '2.3.4+56');
      }
      expect(sent.first['message'], isNot(contains('a@b.com')));
      expect(sent.first['error_type'], 'flutter:StateError');

      // Nothing is sent twice.
      signIns.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(sent, hasLength(2));
      await signIns.close();
    });

    test('caps the queue at maxPending', () async {
      final r = ErrorReporter.forTesting(
        transport: (_) async {},
        currentUserId: () => null,
      );
      for (var i = 0; i < 50; i++) {
        r.report(Exception('distinct $i'), null);
      }
      expect(r.pendingCount, ErrorReporter.maxPending);
    });

    test('a report after sign-in also sends what was queued', () async {
      final sent = <Map<String, Object?>>[];
      String? user;
      final r = ErrorReporter.forTesting(
        transport: (row) async => sent.add(row),
        currentUserId: () => user,
      );
      r.report(Exception('before'), null);
      user = 'u';
      r.report(Exception('after'), null);
      await Future<void>.delayed(Duration.zero);
      expect(sent.map((r) => r['message']), ['Exception: before', 'Exception: after']);
    });

    test('async version source is awaited; failure reports unknown', () async {
      final sent = <Map<String, Object?>>[];
      final r = ErrorReporter.forTesting(
        transport: (row) async => sent.add(row),
        appVersion: () async => throw Exception('no platform'),
      );
      r.report(Exception('x'), null);
      await Future<void>.delayed(const Duration(milliseconds: 1));
      expect(sent.single['app_version'], 'unknown');
    });
  });
}
