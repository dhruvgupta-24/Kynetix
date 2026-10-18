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
}
