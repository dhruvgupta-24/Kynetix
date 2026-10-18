import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/screens/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('onboarding chapters lay out on a small phone and advance',
      (tester) async {
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: OnboardingScreen(onFinished: () {})));
    await tester.pumpAndSettle();

    expect(find.text('A bit about you'), findsOneWidget);
    expect(find.text('Step 1 of 6'), findsOneWidget);

    // Validation blocks an empty chapter.
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Add your name so we know what to call you.'), findsOneWidget);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Dhruv Gupta');
    await tester.enterText(fields.at(1), '24');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Height and weight'), findsOneWidget);
    expect(find.text('Step 2 of 6'), findsOneWidget);

    final body = find.byType(TextFormField);
    await tester.enterText(body.at(0), '175');
    await tester.enterText(body.at(1), '72');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('How do you train?'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('How do you eat?'), findsOneWidget);

    await tester.ensureVisible(find.text('Skip for now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();
    expect(find.text('Your targets'), findsOneWidget);
    expect(find.text('Save my targets'), findsOneWidget);

    // Back still works before saving.
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('How do you eat?'), findsOneWidget);
  });
}
