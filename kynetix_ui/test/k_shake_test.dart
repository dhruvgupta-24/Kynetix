import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/ui/k_motion.dart';
import 'package:kynetix/ui/k_shake.dart';

void main() {
  setUp(() => KHaptics.enabled = false);
  tearDown(() => KHaptics.enabled = true);

  double dx(WidgetTester tester) => tester
      .widget<Transform>(find.descendant(of: find.byType(KShake), matching: find.byType(Transform)))
      .transform
      .getTranslation()
      .x;

  testWidgets('shake swings sideways and comes to rest within ~400 ms', (tester) async {
    final key = GlobalKey<KShakeState>();
    await tester.pumpWidget(MaterialApp(home: Center(child: KShake(key: key, child: const SizedBox(width: 40, height: 20)))));
    expect(dx(tester), 0);

    key.currentState!.shake();
    var peak = 0.0;
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      peak = dx(tester).abs() > peak ? dx(tester).abs() : peak;
    }
    expect(peak, greaterThan(2));
    expect(peak, lessThanOrEqualTo(6));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.hasRunningAnimations, isFalse);
    expect(dx(tester), 0);
  });

  testWidgets('reduced motion: no movement', (tester) async {
    final key = GlobalKey<KShakeState>();
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Center(child: KShake(key: key, child: const SizedBox(width: 40, height: 20))),
      ),
    ));
    key.currentState!.shake();
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
    expect(dx(tester), 0);
  });

  testWidgets('shakeInvalid shakes only the fields that failed validation', (tester) async {
    final formKey = GlobalKey<FormState>();
    final good = GlobalKey<KShakeState>();
    final bad = GlobalKey<KShakeState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Form(
          key: formKey,
          child: Column(children: [
            KShake(key: good, child: TextFormField(initialValue: '30', validator: (_) => null)),
            KShake(key: bad, child: TextFormField(initialValue: '900', validator: (_) => 'Enter an age from 18 to 100.')),
          ]),
        ),
      ),
    ));
    expect(formKey.currentState!.validate(), isFalse);
    KShake.shakeInvalid(formKey.currentContext);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    double dxOf(GlobalKey k) => tester
        .widget<Transform>(find.descendant(of: find.byKey(k), matching: find.byType(Transform)).first)
        .transform
        .getTranslation()
        .x;
    expect(dxOf(good), 0);
    expect(dxOf(bad), isNot(0));
    await tester.pumpAndSettle();
    expect(find.text('Enter an age from 18 to 100.'), findsOneWidget);
  });
}
