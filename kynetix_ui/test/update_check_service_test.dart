import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/services/update_check_service.dart';
import 'package:kynetix/widgets/update_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object?> _json({int code = 7, int min = 1, String? play}) => {
      'versionCode': code,
      'versionName': '1.0.0-beta.2',
      'apk': 'https://github.com/dhruvgupta-24/Kynetix/releases/download/v1.0.0-beta.2/kynetix-1.0.0-beta.2-arm64-v8a.apk',
      'page': 'https://dhruvgupta-24.github.io/Kynetix/download/',
      'notes': ['Faster logging', '  ', 'New share cards'],
      'minVersionCode': min,
      'playUrl': play,
    };

AppRelease _release({int code = 7, int min = 1, String? play}) => AppRelease.fromJson(_json(code: code, min: min, play: play))!;

void main() {
  group('version codes', () {
    test('split-per-abi offsets are ignored', () {
      expect(UpdateCheckService.installedCode('7'), 7);
      expect(UpdateCheckService.installedCode('1007'), 7); // armeabi-v7a
      expect(UpdateCheckService.installedCode('2007'), 7); // arm64-v8a
      expect(UpdateCheckService.installedCode('4007'), 7); // x86_64
      expect(UpdateCheckService.installedCode(''), 0);
      expect(UpdateCheckService.installedCode('x'), 0);
    });

    test('newer, same and older builds across ABIs', () {
      expect(UpdateCheckService.decide(_release(code: 7), 2006), UpdateKind.optional);
      expect(UpdateCheckService.decide(_release(code: 7), 1006), UpdateKind.optional);
      expect(UpdateCheckService.decide(_release(code: 7), 2007), UpdateKind.none);
      expect(UpdateCheckService.decide(_release(code: 7), 1007), UpdateKind.none);
      expect(UpdateCheckService.decide(_release(code: 7), 2008), UpdateKind.none);
      // A version.json that carries an ABI offset compares the same way.
      expect(UpdateCheckService.decide(_release(code: 2008), 1007), UpdateKind.optional);
    });

    test('below minVersionCode is required', () {
      expect(UpdateCheckService.decide(_release(code: 9, min: 5), 2004), UpdateKind.required);
      expect(UpdateCheckService.decide(_release(code: 9, min: 5), 2005), UpdateKind.optional);
      expect(UpdateCheckService.decide(_release(code: 5, min: 5), 1005), UpdateKind.none);
    });

    test('a Play move wins over everything', () {
      final play = _release(code: 7, min: 9, play: 'https://play.google.com/store/apps/details?id=com.kynetix.app');
      expect(UpdateCheckService.decide(play, 2007), UpdateKind.play);
      expect(UpdateCheckService.decide(play, 2001), UpdateKind.play);
    });

    test('parses version.json and rejects junk', () {
      final r = _release();
      expect(r.versionName, '1.0.0-beta.2');
      expect(r.notes, ['Faster logging', 'New share cards']);
      expect(r.playUrl, isNull);
      expect(AppRelease.fromJson({'versionCode': '7', 'versionName': 'x', 'page': 'p'}), isNull);
      expect(AppRelease.fromJson({'versionCode': 7, 'versionName': 'x'}), isNull);
      expect(AppRelease.fromJson([1, 2]), isNull);
      expect(AppRelease.fromJson({..._json(), 'playUrl': ''})!.playUrl, isNull);
    });

    test('isDue: first time, every 12 h, and a clock that went back', () {
      final t = DateTime(2026, 10, 20, 9);
      expect(UpdateCheckService.isDue(null, t), isTrue);
      expect(UpdateCheckService.isDue(t, t.add(const Duration(hours: 11, minutes: 59))), isFalse);
      expect(UpdateCheckService.isDue(t, t.add(const Duration(hours: 12))), isTrue);
      expect(UpdateCheckService.isDue(t, t.subtract(const Duration(minutes: 1))), isTrue);
    });
  });

  group('check', () {
    late int fetches;
    late String? body;
    late DateTime now;

    UpdateCheckService make({bool sideload = true, String? installer, String build = '2006'}) => UpdateCheckService(
          sideload: sideload,
          installer: () async => installer,
          buildNumber: () async => build,
          now: () => now,
          fetch: () async {
            fetches++;
            return body;
          },
        );

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      fetches = 0;
      body = jsonEncode(_json(code: 7));
      now = DateTime(2026, 10, 20, 9);
    });

    test('off for Play builds, and for Play installs of a sideload build', () async {
      expect((await make(sideload: false).check()).kind, UpdateKind.none);
      expect((await make(installer: 'com.android.vending').check(force: true)).kind, UpdateKind.none);
      expect(fetches, 0);
      expect((await make(installer: 'com.google.android.packageinstaller').check()).kind, UpdateKind.optional);
    });

    test('throttles to one fetch per 12 h; optional shows only on a fetch', () async {
      final s = make();
      expect((await s.check()).kind, UpdateKind.optional);
      expect(fetches, 1);

      now = now.add(const Duration(hours: 3));
      final again = await s.check();
      expect(again.kind, UpdateKind.none);
      expect(again.reached, isFalse);
      expect(fetches, 1);

      now = now.add(const Duration(hours: 9));
      expect((await s.check()).kind, UpdateKind.optional);
      expect(fetches, 2);
    });

    test('a required update shows every launch, from the cache', () async {
      body = jsonEncode(_json(code: 9, min: 8));
      final s = make();
      expect((await s.check()).kind, UpdateKind.required);
      now = now.add(const Duration(hours: 1));
      expect((await s.check()).kind, UpdateKind.required);
      expect(fetches, 1);
    });

    test('force always fetches and says whether it got through', () async {
      final s = make(build: '2007');
      final first = await s.check(force: true);
      expect(first.kind, UpdateKind.none);
      expect(first.reached, isTrue);
      body = null;
      final offline = await s.check(force: true);
      expect(offline.reached, isFalse);
      expect(fetches, 2);
    });

    test('a failed or broken fetch stays quiet and does not burn the 12 h', () async {
      body = '{not json';
      final s = make();
      expect((await s.check()).kind, UpdateKind.none);
      body = jsonEncode(_json(code: 7));
      expect((await s.check()).kind, UpdateKind.optional);
      expect(fetches, 2);
    });
  });

  group('UpdateSheet', () {
    Widget host(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

    testWidgets('optional: notes, Get it opens the page, Later is there', (tester) async {
      final opened = <Uri>[];
      await tester.pumpWidget(host(UpdateSheet(
        release: _release(),
        kind: UpdateKind.optional,
        open: (u) async {
          opened.add(u);
          return true;
        },
      )));
      expect(find.text('Fresh build ready'), findsOneWidget);
      expect(find.text('Faster logging'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
      await tester.tap(find.text('Get it'));
      await tester.pumpAndSettle();
      expect(opened.single.toString(), 'https://dhruvgupta-24.github.io/Kynetix/download/');
    });

    testWidgets('required: no Later', (tester) async {
      await tester.pumpWidget(host(UpdateSheet(release: _release(min: 9), kind: UpdateKind.required)));
      expect(find.text('Get it'), findsOneWidget);
      expect(find.text('Later'), findsNothing);
    });

    testWidgets('play: points to Google Play and says the data comes along', (tester) async {
      final opened = <Uri>[];
      await tester.pumpWidget(host(UpdateSheet(
        release: _release(play: 'https://play.google.com/store/apps/details?id=com.kynetix.app'),
        kind: UpdateKind.play,
        open: (u) async {
          opened.add(u);
          return true;
        },
      )));
      expect(find.text('Kynetix is on Google Play now'), findsOneWidget);
      expect(find.textContaining('Your account and data come with you'), findsOneWidget);
      expect(find.text('Faster logging'), findsNothing);
      await tester.tap(find.text('Open Google Play'));
      await tester.pumpAndSettle();
      expect(opened.single.host, 'play.google.com');
    });
  });
}
