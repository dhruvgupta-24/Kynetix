import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/ui/k_text_morph.dart';
import 'package:kynetix/widgets/k_avatar.dart';

Widget _app(Widget child, {bool reduced = false}) => MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: MaterialApp(home: Scaffold(body: Center(child: child))),
    );

void main() {
  group('KTextMorph', () {
    Widget m(String t, int order, {bool reduced = false}) =>
        _app(KTextMorph(t, order: order, style: const TextStyle(fontSize: 14)), reduced: reduced);

    testWidgets('idle is a plain Text with no ticker; a change morphs, then settles back', (tester) async {
      await tester.pumpWidget(m('October 2026', 10));
      expect(tester.hasRunningAnimations, isFalse);
      expect(find.text('October 2026'), findsOneWidget);

      // Same text: nothing moves.
      await tester.pumpWidget(m('October 2026', 10));
      expect(tester.hasRunningAnimations, isFalse);

      await tester.pumpWidget(m('November 2026', 11));
      expect(tester.hasRunningAnimations, isTrue);
      expect(find.byType(CustomPaint), findsWidgets);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
      expect(find.text('November 2026'), findsOneWidget);
      expect(find.bySemanticsLabel('November 2026'), findsOneWidget);

      // Back a month rolls the other way and still lands on plain text.
      await tester.pumpWidget(m('October 2026', 10));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpAndSettle();
      expect(find.text('October 2026'), findsOneWidget);
    });

    testWidgets('reduced motion shows the new text at once', (tester) async {
      await tester.pumpWidget(m('October 2026', 10, reduced: true));
      await tester.pumpWidget(m('November 2026', 11, reduced: true));
      expect(tester.hasRunningAnimations, isFalse);
      expect(find.text('November 2026'), findsOneWidget);
    });

    testWidgets('a change mid-morph retargets cleanly', (tester) async {
      await tester.pumpWidget(m('October 2026', 10));
      await tester.pumpWidget(m('November 2026', 11));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pumpWidget(m('December 2026', 12));
      await tester.pumpAndSettle();
      expect(find.text('December 2026'), findsOneWidget);
    });
  });

  group('KFuelAvatar', () {
    testWidgets('draws rings around the picture without animating at rest', (tester) async {
      await tester.pumpWidget(_app(const KFuelAvatar(size: 32)));
      expect(tester.hasRunningAnimations, isFalse);
      expect(tester.getSize(find.byType(KFuelAvatar)), const Size(32, 32));
      // The picture sits inside the rings.
      final face = tester.getSize(find.byType(KAvatar));
      expect(face.width, lessThan(32));
      expect(face.width, closeTo(32 - 2 * KFuelAvatar.ringBand(1.6), 0.01));
    });
  });
}
