import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/screens/connect_chatgpt_screen.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('embedded idle shows both ways in plus Skip, and Skip finishes',
      (tester) async {
    var finished = 0;
    await pump(
      tester,
      ConnectChatGptScreen(embedded: true, onFinished: () => finished++),
    );

    expect(find.text('Continue with ChatGPT'), findsOneWidget);
    expect(find.text('Use a code instead'), findsOneWidget);
    expect(find.text('Skip for now'), findsOneWidget);
    expect(find.text('You can do this later in Settings.'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);

    await tester.ensureVisible(find.text('Skip for now'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Skip for now'));
    await tester.pump();
    expect(finished, 1);
  });

  testWidgets('pushed page has no Skip and keeps an app bar', (tester) async {
    await pump(tester, const ConnectChatGptScreen());
    expect(find.text('Continue with ChatGPT'), findsOneWidget);
    expect(find.text('Use a code instead'), findsOneWidget);
    expect(find.text('Skip for now'), findsNothing);
    expect(find.byType(AppBar), findsOneWidget);
  });
}
