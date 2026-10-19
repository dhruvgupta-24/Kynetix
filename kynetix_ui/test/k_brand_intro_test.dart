import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/ui/k_brand_intro.dart';

Widget _host(VoidCallback onDone, {bool reduceMotion = false}) => MediaQuery(
      data: MediaQueryData(size: const Size(412, 915), disableAnimations: reduceMotion),
      child: Directionality(textDirection: TextDirection.ltr, child: KBrandIntro(onDone: onDone)),
    );

void main() {
  // The native side reports the Android splash gone straight away.
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.kynetix.app/splash'),
      (call) async => true,
    );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('com.kynetix.app/splash'), null);
  });

  testWidgets('plays through and reports done once', (tester) async {
    var done = 0;
    await tester.pumpWidget(_host(() => done++));
    // Starts once frames arrive on time: six smooth 60 fps frames.
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 1200));
    expect(done, 0);
    await tester.pump(KBrandIntro.total);
    await tester.pump();
    expect(done, 1);
    expect(find.bySemanticsLabel('Kynetix'), findsOneWidget);
  });

  testWidgets('holds the K while frames are janky, then starts', (tester) async {
    var done = 0;
    await tester.pumpWidget(_host(() => done++));
    await tester.pump();
    // Long frames (a busy cold start): the intro waits rather than skipping.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(done, 0);
    // The 1.8 s cap starts it regardless, and it plays to the end.
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(); // the animation's first tick
    await tester.pump(KBrandIntro.total);
    await tester.pump(const Duration(milliseconds: 100));
    expect(done, 1);
  });

  testWidgets('a tap skips to the finished mark and fades out', (tester) async {
    var done = 0;
    await tester.pumpWidget(_host(() => done++));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byType(KBrandIntro));
    // From the hold to the end is well under the full run.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    expect(done, 1);
  });

  testWidgets('reduced motion shows the mark, then fades', (tester) async {
    var done = 0;
    await tester.pumpWidget(_host(() => done++, reduceMotion: true));
    await tester.pump(const Duration(milliseconds: 300));
    expect(done, 0);
    await tester.pump(const Duration(milliseconds: 600)); // the hold ends, the fade starts
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    expect(done, 1);
  });
}
