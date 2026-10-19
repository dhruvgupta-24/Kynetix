import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/ui/k_brand_intro.dart';

Widget _host(VoidCallback onDone, {bool reduceMotion = false}) => MediaQuery(
      data: MediaQueryData(size: const Size(412, 915), disableAnimations: reduceMotion),
      child: Directionality(textDirection: TextDirection.ltr, child: KBrandIntro(onDone: onDone)),
    );

void main() {
  testWidgets('plays through and reports done once', (tester) async {
    var done = 0;
    await tester.pumpWidget(_host(() => done++));
    // Starts a beat after the first frame, once cold start settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 1200));
    expect(done, 0);
    await tester.pump(KBrandIntro.total);
    await tester.pump();
    expect(done, 1);
    expect(find.bySemanticsLabel('Kynetix'), findsOneWidget);
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
