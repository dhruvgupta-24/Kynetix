import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/screens/onboarding/consent_panel.dart';
import 'package:kynetix/screens/onboarding_screen.dart';
import 'package:kynetix/services/consent_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _uid = '11111111-aaaa-4aaa-8aaa-111111111111';

void main() {
  group('ConsentService', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      ConsentService.instance.prefsOverride = await SharedPreferences.getInstance();
    });

    test('records version + timestamp per user under privacy_consent_v1_<id>',
        () async {
      final svc = ConsentService.instance;
      expect(await svc.hasConsented(_uid), isFalse);
      expect(svc.peek(_uid), isFalse);

      await svc.recordConsent(_uid,
          ageConfirmedAdult: true, now: DateTime.utc(2026, 10, 16, 9), syncRemote: false);

      final prefs = await SharedPreferences.getInstance();
      final raw = jsonDecode(prefs.getString('privacy_consent_v1_$_uid')!) as Map;
      expect(raw['version'], '2026-10-20');
      expect(raw['at'], '2026-10-16T09:00:00.000Z');
      expect(raw['adult'], isTrue);
      expect(await svc.hasConsented(_uid), isTrue);
      expect(svc.peek(_uid), isTrue);
      // Another account on the phone is unaffected.
      expect(await svc.hasConsented('someone-else'), isFalse);
    });

    test('an old policy version or no 18+ confirmation is not consent',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'privacy_consent_v1_$_uid',
          jsonEncode({'version': '2025-01-01', 'at': '2025-01-01T00:00:00Z', 'adult': true}));
      expect(await ConsentService.instance.hasConsented(_uid), isFalse);
      await prefs.setString(
          'privacy_consent_v1_$_uid',
          jsonEncode({'version': '2026-10-20', 'at': '2026-10-20T00:00:00Z', 'adult': false}));
      expect(await ConsentService.instance.hasConsented(_uid), isFalse);
    });

    test('cloud calls never throw without a backend', () async {
      await ConsentService.instance
          .recordConsent(_uid, ageConfirmedAdult: true, syncRemote: false);
      expect(await ConsentService.instance.syncToCloud(_uid), isFalse);
      expect(await ConsentService.instance.restoreFromCloud(_uid), isFalse);
    });
  });

  group('ConsentPanel', () {
    testWidgets('both controls are required; decline offers sign out',
        (tester) async {
      var agreed = 0;
      var signedOut = 0;
      bool? adult;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ConsentPanel(
            onAgree: ({required bool ageConfirmedAdult}) async {
              agreed++;
              adult = ageConfirmedAdult;
            },
            onSignOut: () async => signedOut++,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      Future<void> tapAgree() async {
        await tester.ensureVisible(find.text('Agree and continue'));
        await tester.tap(find.text('Agree and continue'));
        await tester.pumpAndSettle();
      }

      await tapAgree();
      expect(agreed, 0);

      await tester.tap(find.text('I agree to the Privacy Policy'));
      await tester.pumpAndSettle();
      await tapAgree();
      expect(agreed, 0, reason: '18+ still unchecked');

      await tester.tap(find.text("I'm 18 or older"));
      await tester.pumpAndSettle();
      await tapAgree();
      expect(agreed, 1);
      expect(adult, isTrue);

      await tester.ensureVisible(find.text("I don't agree"));
      await tester.tap(find.text("I don't agree"));
      await tester.pumpAndSettle();
      expect(find.text("You can't use Kynetix without this"), findsOneWidget);
      expect(find.text('Read the privacy policy'), findsOneWidget);
      await tester.ensureVisible(find.text('Sign out'));
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(signedOut, 1);
    });
  });

  group('Onboarding', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('privacy step comes first when consent is needed',
        (tester) async {
      tester.view.physicalSize = const Size(720, 1280);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      var recorded = false;

      await tester.pumpWidget(MaterialApp(
        home: OnboardingScreen(
          onFinished: () {},
          onConsent: ({required bool ageConfirmedAdult}) async =>
              recorded = ageConfirmedAdult,
          onSignOut: () async {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Your data, your call'), findsOneWidget);
      expect(find.text('Step 1 of 6'), findsNothing);

      for (final label in ['I agree to the Privacy Policy', "I'm 18 or older"]) {
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.text('Agree and continue'));
      await tester.tap(find.text('Agree and continue'));
      await tester.pumpAndSettle();

      expect(recorded, isTrue);
      expect(find.text('A bit about you'), findsOneWidget);
      expect(find.text('Step 1 of 6'), findsOneWidget);
    });

    testWidgets('under-18 ages are refused with calm copy', (tester) async {
      tester.view.physicalSize = const Size(720, 1280);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(home: OnboardingScreen(onFinished: () {})));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Dhruv');
      await tester.enterText(fields.at(1), '17');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Kynetix is for adults 18 and over.'), findsOneWidget);
      expect(find.text('Height and weight'), findsNothing);

      await tester.enterText(fields.at(1), '18');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Height and weight'), findsOneWidget);
    });
  });
}
