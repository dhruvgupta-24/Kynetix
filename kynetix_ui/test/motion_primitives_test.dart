import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/config/app_theme.dart';
import 'package:kynetix/screens/dashboard_screen.dart' show FuelLabel;
import 'package:kynetix/ui/k_rolling.dart';
import 'package:kynetix/widgets/k_equal_height_row.dart';
import 'package:kynetix/widgets/k_typing_dots.dart';

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('KRollingNumber', () {
    testWidgets('rolls on change, not on a same-value rebuild, and settles to its natural width', (tester) async {
      Widget n(String t) => _app(KRollingNumber(t, style: const TextStyle(fontSize: 20)));
      await tester.pumpWidget(n('999'));
      expect(tester.hasRunningAnimations, isFalse);
      final w3 = tester.getSize(find.byType(KRollingNumber)).width;

      await tester.pumpWidget(n('999'));
      expect(tester.hasRunningAnimations, isFalse);

      await tester.pumpWidget(n('1,000'));
      expect(tester.hasRunningAnimations, isTrue);
      // Mid-roll the box is between the two widths: no jump.
      await tester.pump(const Duration(milliseconds: 120));
      final mid = tester.getSize(find.byType(KRollingNumber)).width;
      await tester.pumpAndSettle();
      final w4 = tester.getSize(find.byType(KRollingNumber)).width;
      expect(w4, greaterThan(w3));
      expect(mid, inInclusiveRange(w3, w4));
      expect(find.bySemanticsLabel('1,000'), findsOneWidget);
    });

    testWidgets('reduced motion shows the new value at once', (tester) async {
      Widget n(String t) => MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: _app(KRollingNumber(t, style: const TextStyle(fontSize: 20))),
          );
      await tester.pumpWidget(n('12'));
      await tester.pumpWidget(n('13'));
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
    });

    test('isRollable', () {
      expect(KRollingNumber.isRollable('2,350'), isTrue);
      expect(KRollingNumber.isRollable('72.5'), isTrue);
      expect(KRollingNumber.isRollable('16h 5m'), isTrue);
      expect(KRollingNumber.isRollable('Rest day'), isFalse);
      expect(KRollingNumber.isRollable('Push 2'), isFalse);
    });
  });

  testWidgets('KEqualHeightRow gives every child the tallest height', (tester) async {
    await tester.pumpWidget(_app(SizedBox(
      width: 300,
      child: KEqualHeightRow(
        gap: 10,
        minHeight: 40,
        ruleColor: const Color(0xFF888888),
        children: const [
          SizedBox(key: ValueKey('a'), height: 50),
          SizedBox(key: ValueKey('b'), height: 100),
        ],
      ),
    )));
    expect(tester.getSize(find.byKey(const ValueKey('a'))), const Size(145, 100));
    expect(tester.getSize(find.byKey(const ValueKey('b'))), const Size(145, 100));
    expect(tester.getTopLeft(find.byKey(const ValueKey('b'))).dx - tester.getTopLeft(find.byKey(const ValueKey('a'))).dx, 155);
  });

  testWidgets('KReveal replays in place for a new key only when enabled', (tester) async {
    final childKey = GlobalKey();
    Widget r(Object k, bool enabled) => _app(KReveal(
          replayKey: k,
          enabled: enabled,
          rise: 8,
          child: SizedBox(key: childKey, width: 10, height: 10),
        ));
    await tester.pumpWidget(r('a', true));
    await tester.pumpAndSettle();
    final element = childKey.currentContext;

    await tester.pumpWidget(r('a', true)); // same key: nothing
    expect(tester.hasRunningAnimations, isFalse);

    await tester.pumpWidget(r('b', true)); // new key: replays
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpAndSettle();
    expect(childKey.currentContext, same(element), reason: 'replay must not remount the child');

    await tester.pumpWidget(r('c', false)); // seen before: end state
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('fuel rings fly between two FuelLabels with the same tag', (tester) async {
    final nav = GlobalKey<NavigatorState>();
    Widget label({bool sweepIn = true}) => FuelLabel(
          title: 'Fuel',
          heroTag: 'fuel-rings-2026-10-19',
          sweepIn: sweepIn,
          consumedCal: 1200,
          targetCal: 2000,
          consumedPro: 80,
          targetPro: 120,
        );
    await tester.pumpWidget(MaterialApp(
      navigatorKey: nav,
      home: Scaffold(body: SingleChildScrollView(child: label())),
    ));
    await tester.pumpAndSettle();

    nav.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(body: SingleChildScrollView(child: label(sweepIn: false))),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // In flight: only the shuttle is on stage; both ends are hidden.
    expect(find.byType(KDabbaRings), findsOneWidget);
    expect(find.byType(KDabbaRings, skipOffstage: false), findsNWidgets(2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    nav.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('typing dots sit still in tests (no endless ticker)', (tester) async {
    await tester.pumpWidget(_app(const KTypingDots(color: Color(0xFF777777))));
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
  });
}
