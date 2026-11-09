import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/screens/onboarding/plan_builder_moment.dart';
import 'package:kynetix/screens/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'consent_test.dart' show pickBirthday;

Future<void> _answerUpToEating(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField).at(0), 'Dhruv Gupta');
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await pickBirthday(tester, DateTime(2002, 3, 14));
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
  final body = find.byType(TextFormField);
  await tester.enterText(body.at(0), '175');
  await tester.enterText(body.at(1), '72');
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
  expect(find.text('How do you eat?'), findsOneWidget);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Your targets plays the plan being built, then settles; no replay for the same answers',
      (tester) async {
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: OnboardingScreen(onFinished: () {})));
    await tester.pumpAndSettle();
    await _answerUpToEating(tester);

    await tester.tap(find.text('Roti or rice first'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    // Into the step, mid-build.
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byType(PlanBuilderMoment), findsOneWidget);
    expect(find.text('Working it out from your answers'), findsOneWidget);
    expect(find.textContaining('Running your numbers'), findsWidgets);

    // Save waits for the sheet: a tap now saves nothing.
    await tester.tap(find.text('Save my targets'));
    await tester.pump();
    expect(find.text('Your targets'), findsOneWidget);
    expect(find.text('Bring your own AI'), findsNothing);

    await tester.pumpAndSettle();
    expect(find.text('Your daily target'), findsOneWidget);
    expect(find.text('Roti or rice first'), findsOneWidget);
    expect(find.textContaining("Here's where you start"), findsWidgets);

    // Back and forward with the same answers: shown settled, no replay.
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Your daily target'), findsOneWidget);
    expect(find.text('Skip'), findsNothing);
    await tester.pumpAndSettle();
  });
}
