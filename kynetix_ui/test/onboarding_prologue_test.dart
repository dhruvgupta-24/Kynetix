import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/screens/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('story plays three beats by tap, then the first chapter', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: OnboardingScreen(onFinished: () {}, showPrologue: true)));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Every plate is a story.'), findsOneWidget);

    await tester.tap(find.text('Tap to continue'));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Every rep adds a line.'), findsOneWidget);

    await tester.tap(find.text('Tap to continue'));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text("I read both. That's my job."), findsOneWidget);

    await tester.tap(find.text("Let's begin"));
    await tester.pumpAndSettle();
    expect(find.text('A bit about you'), findsOneWidget);
    expect(find.textContaining("I'm Kyno"), findsWidgets);
  });

  testWidgets('Skip goes straight to the questions', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: OnboardingScreen(onFinished: () {}, showPrologue: true)));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('A bit about you'), findsOneWidget);
  });
}
