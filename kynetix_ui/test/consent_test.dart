import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/screens/onboarding/consent_panel.dart';
import 'package:kynetix/screens/onboarding_screen.dart';
import 'package:kynetix/services/consent_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _uid = '11111111-aaaa-4aaa-8aaa-111111111111';

/// Opens the birthday picker, types [d] in its text mode and confirms.
Future<void> pickBirthday(WidgetTester tester, DateTime d) async {
  await tester.ensureVisible(find.byKey(const ValueKey('birthday-field')));
  await tester.tap(find.byKey(const ValueKey('birthday-field')));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.edit_outlined));
  await tester.pumpAndSettle();
  final mm = d.month.toString().padLeft(2, '0'), dd = d.day.toString().padLeft(2, '0');
  // The picker reads day first (Indian English).
  await tester.enterText(find.byType(TextField).last, '$dd/$mm/${d.year}');
  await tester.tap(find.text("That's the one"));
  await tester.pumpAndSettle();
}

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
      expect(raw['version'], ConsentService.policyVersion);
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
      DateTime? dob;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ConsentPanel(
            onAgree: ({required bool ageConfirmedAdult, required DateTime dateOfBirth}) async {
              agreed++;
              adult = ageConfirmedAdult;
              dob = dateOfBirth;
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
      expect(agreed, 0, reason: 'no birthday yet');

      // Under 13: still blocked, with a calm note.
      await pickBirthday(tester, DateTime(DateTime.now().year - 11, 1, 1));
      expect(find.textContaining('for 13 and up'), findsOneWidget);
      await tapAgree();
      expect(agreed, 0, reason: 'under 13');

      // 13 to 17: teen mode, on to the parent check.
      await pickBirthday(tester, DateTime(DateTime.now().year - 15, 1, 1));
      expect(find.textContaining('Teen mode it is'), findsOneWidget);
      expect(find.text('Continue to the parent check'), findsOneWidget);

      await pickBirthday(tester, DateTime(1999, 7, 4));
      expect(find.textContaining('That makes you'), findsOneWidget);
      await tapAgree();
      expect(agreed, 1);
      expect(adult, isTrue);
      expect(dob, DateTime(1999, 7, 4));

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

      await tester.ensureVisible(find.text('I agree to the Privacy Policy'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('I agree to the Privacy Policy'));
      await tester.pumpAndSettle();
      await pickBirthday(tester, DateTime(1999, 7, 4));
      await tester.ensureVisible(find.text('Agree and continue'));
      await tester.tap(find.text('Agree and continue'));
      await tester.pumpAndSettle();

      expect(recorded, isTrue);
      expect(find.text('A bit about you'), findsOneWidget);
      expect(find.text('Step 1 of 6'), findsOneWidget);
      // The birthday from the privacy step carries into the first chapter.
      expect(find.text('4 Jul 1999'), findsOneWidget);
    });

    testWidgets('an under-13 birthday is refused with calm copy; 13 to 17 is teen mode', (tester) async {
      tester.view.physicalSize = const Size(720, 1280);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(home: OnboardingScreen(onFinished: () {})));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'Dhruv');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final now = DateTime.now();
      await pickBirthday(tester, DateTime(now.year - 12, now.month, 1));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.textContaining('for 13 and up'), findsOneWidget);
      expect(find.text('Height and weight'), findsNothing);

      await pickBirthday(tester, DateTime(now.year - 16, 1, 1));
      expect(find.textContaining('Teen mode it is'), findsOneWidget);

      await pickBirthday(tester, DateTime(now.year - 18, 1, 1));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Height and weight'), findsOneWidget);
    });
  });
}
