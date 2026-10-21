import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/screens/connect_chatgpt_screen.dart';
import 'package:kynetix/services/chatgpt_link_service.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('embedded idle shows Sign in with ChatGPT plus Skip, and Skip finishes',
      (tester) async {
    var finished = 0;
    await pump(
      tester,
      ConnectChatGptScreen(embedded: true, onFinished: () => finished++),
    );

    expect(find.text('Continue with ChatGPT'), findsOneWidget);
    // The device-code path is hidden (see _allowDeviceCode).
    expect(find.text('Use a code instead'), findsNothing);
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
    await pump(
      tester,
      ConnectChatGptScreen(loadStatus: () async => ChatGptLinkStatus.disconnected),
    );
    expect(find.text('Continue with ChatGPT'), findsOneWidget);
    // The device-code path is hidden (see _allowDeviceCode).
    expect(find.text('Use a code instead'), findsNothing);
    expect(find.text('Skip for now'), findsNothing);
    expect(find.byType(AppBar), findsOneWidget);
  });

  testWidgets('already linked opens on the connection, not the pitch', (tester) async {
    await pump(
      tester,
      ConnectChatGptScreen(
        loadStatus: () async => const ChatGptLinkStatus(
          isConnected: true,
          activeProvider: 'user_chatgpt',
          activeModel: 'gpt-5-mini',
          authMethod: 'siwc',
        ),
      ),
    );
    expect(find.text('Kyno runs on your ChatGPT plan'), findsOneWidget);
    expect(find.text('gpt-5-mini'), findsOneWidget);
    expect(find.text('Continue with ChatGPT'), findsNothing);
    expect(find.text('Disconnect'), findsOneWidget);
    expect(find.text('Reconnect'), findsOneWidget);
  });
}
