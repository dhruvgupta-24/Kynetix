import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/services/feedback_service.dart';
import 'package:kynetix/widgets/feedback_sheet.dart';

void main() {
  group('FeedbackService.buildRow', () {
    test('maps kinds to what the table accepts', () {
      expect(FeedbackKind.values.map((k) => k.code), ['idea', 'bug', 'love', 'other']);
      expect(FeedbackKind.values.map((k) => k.label), ['Idea', 'Bug', 'Love it', 'Other']);
      for (final k in FeedbackKind.values) {
        expect(FeedbackService.buildRow(kind: k, message: 'x')['kind'], k.code);
        expect(FeedbackKind.fromCode(k.code), k);
      }
      expect(FeedbackKind.fromCode('nope'), isNull);
      expect(FeedbackKind.bug.hint, 'What broke, and what were you doing?');
    });

    test('never sends user_id or status; the server fills them', () {
      final row = FeedbackService.buildRow(kind: FeedbackKind.idea, message: 'Dark mode for the dock');
      expect(row.containsKey('user_id'), isFalse);
      expect(row.containsKey('status'), isFalse);
      expect(row.keys.toSet(), {'kind', 'message', 'reply_to', 'app_version', 'platform'});
    });

    test('trims text and sends blanks as null', () {
      final row = FeedbackService.buildRow(
        kind: FeedbackKind.love,
        message: '  Paid in sweat.  \n',
        replyTo: '  me@example.com ',
        appVersion: '   ',
        platform: '',
      );
      expect(row['message'], 'Paid in sweat.');
      expect(row['reply_to'], 'me@example.com');
      expect(row['app_version'], isNull);
      expect(row['platform'], isNull);
      expect(FeedbackService.buildRow(kind: FeedbackKind.other, message: 'x')['reply_to'], isNull);
    });

    test('truncates every field to its column limit', () {
      final row = FeedbackService.buildRow(
        kind: FeedbackKind.bug,
        message: 'm' * 2500,
        replyTo: 'r' * 400,
        appVersion: 'v' * 50,
        platform: 'p' * 80,
      );
      expect((row['message'] as String).length, 2000);
      expect((row['reply_to'] as String).length, 320);
      expect((row['app_version'] as String).length, 40);
      expect((row['platform'] as String).length, 60);
      expect(FeedbackService.maxMessageLength, 2000);
    });

    test('truncation never leaves half an emoji', () {
      final row = FeedbackService.buildRow(kind: FeedbackKind.love, message: '${'a' * 1999}\u{1F600}');
      expect(row['message'], 'a' * 1999);
    });

    test('photos go in only when there are some, at most three', () {
      expect(FeedbackService.buildRow(kind: FeedbackKind.bug, message: 'x').containsKey('photos'), isFalse);
      final row = FeedbackService.buildRow(kind: FeedbackKind.bug, message: 'x', photos: ['u/1.jpg', 'u/2.jpg', 'u/3.jpg', 'u/4.jpg']);
      expect(row['photos'], ['u/1.jpg', 'u/2.jpg', 'u/3.jpg']);
      expect(FeedbackService.maxPhotos, 3);
    });

    test('imageType reads JPEG, PNG and WebP from the first bytes only', () {
      expect(FeedbackService.imageType(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]))?.mime, 'image/jpeg');
      expect(FeedbackService.imageType(_png)?.ext, 'png');
      final webp = Uint8List.fromList([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50]);
      expect(FeedbackService.imageType(webp)?.mime, 'image/webp');
      expect(FeedbackService.imageType(Uint8List.fromList(utf8.encode('ftypheic....'))), isNull);
      expect(FeedbackService.imageType(Uint8List(0)), isNull);
    });

    test('photoPath sits in the user folder with a unique name', () {
      final at = DateTime.utc(2026, 11, 8, 10);
      final path = FeedbackService.photoPath('uid-1', at, 2, 'png');
      expect(path, 'uid-1/${at.microsecondsSinceEpoch}-2.png');
      expect(path.split('/').first, 'uid-1');
    });

    test('rejects an empty message', () {
      expect(() => FeedbackService.buildRow(kind: FeedbackKind.idea, message: ' \n '), throwsArgumentError);
    });
  });

  group('helpers', () {
    test('platformLabel collapses whitespace', () {
      expect(FeedbackService.platformLabel('android', ' 16 '), 'android 16');
      expect(FeedbackService.platformLabel('ios', 'Version 18.1\n(Build 22B83)'), 'ios Version 18.1 (Build 22B83)');
      expect(FeedbackService.platformLabel('linux', ''), 'linux');
    });

    test('mailtoFor fills the subject with %20 spaces', () {
      final uri = FeedbackService.mailtoFor(' me+gym@example.com ');
      expect(uri.scheme, 'mailto');
      expect(uri.path, 'me+gym@example.com');
      expect(uri.toString(), contains('subject=About%20your%20Kynetix%20feedback'));
    });

    test('relativeTime', () {
      final now = DateTime(2026, 10, 20, 12);
      expect(FeedbackService.relativeTime(now.subtract(const Duration(seconds: 20)), now: now), 'just now');
      expect(FeedbackService.relativeTime(now.subtract(const Duration(minutes: 5)), now: now), '5m ago');
      expect(FeedbackService.relativeTime(now.subtract(const Duration(hours: 3)), now: now), '3h ago');
      expect(FeedbackService.relativeTime(now.subtract(const Duration(days: 2)), now: now), '2d ago');
      expect(FeedbackService.relativeTime(DateTime(2026, 9, 3), now: now), '3 Sep');
      expect(FeedbackService.relativeTime(DateTime(2025, 9, 3), now: now), '3 Sep 2025');
    });

    test('inbox rows parse from both tables', () {
      final f = InboxItem.fromFeedbackRow({
        'id': 'a1',
        'created_at': '2026-10-20T09:00:00Z',
        'kind': 'bug',
        'message': 'Timer froze',
        'reply_to': 'me@example.com',
        'app_version': '1.2.0+14',
        'platform': 'android 16',
        'status': 'read',
      });
      expect(f.source, InboxSource.feedback);
      expect(f.label, 'Bug');
      expect(f.status, InboxStatus.read);
      expect(f.replyTo, 'me@example.com');
      expect(f.createdAt.toUtc(), DateTime.utc(2026, 10, 20, 9));
      expect(f.photos, isEmpty);
      final withPhotos = InboxItem.fromFeedbackRow({'id': 'a2', 'kind': 'bug', 'message': 'x', 'photos': ['u/1.jpg', ' ', 7]});
      expect(withPhotos.photos, ['u/1.jpg']);
      expect(withPhotos.withStatus(InboxStatus.done).photos, ['u/1.jpg']);

      final r = InboxItem.fromReportRow({
        'id': 'b2',
        'created_at': '2026-10-20T09:00:00Z',
        'reason': 'unsafe',
        'message': 'Eat 5000 kcal',
        'prompt': 'How much should I eat?',
        'note': ' ',
        'status': null,
      });
      expect(r.source, InboxSource.report);
      expect(r.label, 'Wrong or unsafe advice');
      expect(r.status, InboxStatus.fresh);
      expect(r.note, isNull);
      expect(r.replyTo, isNull);
      expect(r.withStatus(InboxStatus.done).status, InboxStatus.done);
    });

    test('status codes match the check constraint', () {
      expect(InboxStatus.values.map((s) => s.code), ['new', 'read', 'done']);
      expect(InboxStatus.fromCode('done'), InboxStatus.done);
      expect(InboxStatus.fromCode('weird'), InboxStatus.fresh);
    });
  });

  group('FeedbackSheet', () {
    Widget host(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

    testWidgets('renders, swaps the hint per kind, and refuses an empty message', (tester) async {
      var sent = 0;
      await tester.pumpWidget(host(FeedbackSheet(
        email: 'me@example.com',
        send: ({required kind, required message, replyTo, photos = const []}) async => sent++,
      )));

      expect(find.text('Say it straight'), findsOneWidget);
      for (final k in FeedbackKind.values) {
        expect(find.text(k.label), findsOneWidget);
      }
      expect(find.text(FeedbackKind.idea.hint), findsOneWidget);
      expect(find.textContaining('You can reply to me at'), findsOneWidget);

      await tester.tap(find.text('Bug'));
      await tester.pumpAndSettle();
      expect(find.text(FeedbackKind.bug.hint), findsOneWidget);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(sent, 0);
      expect(find.text('Say something first. Even one line.'), findsOneWidget);
    });

    testWidgets('sends kind, text and reply address; the toggle drops the address', (tester) async {
      final calls = <(FeedbackKind, String, String?)>[];
      await tester.pumpWidget(host(FeedbackSheet(
        email: 'me@example.com',
        send: ({required kind, required message, replyTo, photos = const []}) async => calls.add((kind, message, replyTo)),
      )));

      await tester.tap(find.text('Love it'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Paid in sweat.');
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(calls, [(FeedbackKind.love, 'Paid in sweat.', null)]);
    });

    testWidgets('a failed send keeps the text and says so calmly', (tester) async {
      await tester.pumpWidget(host(FeedbackSheet(
        send: ({required kind, required message, replyTo, photos = const []}) async => throw Exception('offline'),
      )));
      expect(find.textContaining('You can reply to me at'), findsNothing);

      await tester.enterText(find.byType(TextField), 'The rest timer froze');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(find.text("Didn't go through. Check your connection and try again."), findsOneWidget);
      expect(find.text('The rest timer froze'), findsOneWidget);
    });

    testWidgets('attaches up to three photos, drops bad ones, and sends them', (tester) async {
      final sent = <List<Uint8List>>[];
      final junk = Uint8List.fromList(utf8.encode('not an image'));
      var picks = 0;
      await tester.pumpWidget(host(FeedbackSheet(
        pickPhotos: (context, limit) async {
          picks++;
          return picks == 1 ? [_png, junk, _png] : List.filled(limit + 2, _png);
        },
        send: ({required kind, required message, replyTo, photos = const []}) async => sent.add(photos),
      )));

      expect(find.text('Add a screenshot or photo'), findsOneWidget);
      await tester.tap(find.text('Add a screenshot or photo'));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNWidgets(2));

      await tester.tap(find.text('Add another'));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNWidgets(3));
      expect(find.text('Add another'), findsNothing);

      await tester.tap(find.byIcon(Icons.close_rounded).first);
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNWidgets(2));

      await tester.enterText(find.byType(TextField), 'Look at this');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(sent.single, hasLength(2));
    });
  });
}

/// A real 1x1 PNG.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);
