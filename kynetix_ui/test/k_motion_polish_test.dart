import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/config/app_theme.dart';

Widget _app(Widget child, {bool reduced = false}) => KThemeScope(
      builder: (context, palette) => MaterialApp(
        theme: ThemeData(pageTransitionsTheme: kPageTransitions),
        builder: (context, c) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
          child: c!,
        ),
        home: Scaffold(body: Center(child: child)),
      ),
    );

double _scaleOf(WidgetTester tester) {
  final t = tester.widget<ScaleTransition>(
    find.descendant(of: find.byType(Pressable), matching: find.byType(ScaleTransition)),
  );
  return t.scale.value;
}

void main() {
  final haptics = <String>[];

  setUp(() {
    haptics.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments as String);
      return null;
    });
  });

  testWidgets('Pressable squashes to 0.97 on press and springs back to 1', (tester) async {
    await tester.pumpWidget(_app(Pressable(
      onTap: () {},
      child: const SizedBox(width: 100, height: 50),
    )));
    final g = await tester.startGesture(tester.getCenter(find.byType(Pressable)));
    await tester.pump(const Duration(milliseconds: 150)); // past the tap-down delay
    await tester.pump(const Duration(milliseconds: 200));
    expect(_scaleOf(tester), closeTo(0.97, 0.002));

    await g.up();
    var max = 0.0;
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      max = _scaleOf(tester) > max ? _scaleOf(tester) : max;
    }
    await tester.pumpAndSettle();
    expect(_scaleOf(tester), closeTo(1.0, 0.0005));
    // A slight lift past rest, never a big overshoot.
    expect(max, lessThan(1.003));
  });

  testWidgets('Pressable does not scale under reduced motion', (tester) async {
    await tester.pumpWidget(_app(
      Pressable(onTap: () {}, child: const SizedBox(width: 100, height: 50)),
      reduced: true,
    ));
    final g = await tester.startGesture(tester.getCenter(find.byType(Pressable)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_scaleOf(tester), 1.0);
    await g.up();
    await tester.pumpAndSettle();
  });

  testWidgets('KButton success state draws a check, shows the label and buzzes once',
      (tester) async {
    var taps = 0;
    Widget build(KButtonState s) => _app(KButton(
          label: 'Log meal',
          successLabel: 'Logged',
          state: s,
          onTap: () => taps++,
        ));

    await tester.pumpWidget(build(KButtonState.idle));
    expect(find.text('Log meal'), findsOneWidget);
    expect(find.text('Logged'), findsNothing);

    await tester.tap(find.byType(KButton));
    await tester.pump();
    expect(taps, 1);
    haptics.clear();

    await tester.pumpWidget(build(KButtonState.loading));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(KSpinner), findsOneWidget);

    await tester.pumpWidget(build(KButtonState.success));
    await tester.pumpAndSettle();
    expect(find.text('Logged'), findsOneWidget);
    expect(haptics, ['HapticFeedbackType.mediumImpact']);
    // Ignores taps while showing success.
    await tester.tap(find.byType(KButton));
    await tester.pump();
    expect(taps, 1);

    // Rebuilding in the same state does not buzz again.
    await tester.pumpWidget(build(KButtonState.success));
    await tester.pumpAndSettle();
    expect(haptics.length, 1);

    await tester.pumpWidget(build(KButtonState.idle));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(KButton));
    await tester.pump();
    expect(taps, 2);
  });

  testWidgets('KButton legacy constructor still works (loading flag, success bool)',
      (tester) async {
    await tester.pumpWidget(_app(const KButton(label: 'Save', loading: true)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(KSpinner), findsOneWidget);
    await tester.pumpWidget(_app(KButton(label: 'Save', success: true, onTap: () {})));
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsWidgets);
  });

  testWidgets('shared-axis push and pop settle, reduced motion is instant', (tester) async {
    for (final reduced in [false, true]) {
      await tester.pumpWidget(_app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Second'))),
            ),
            child: const Text('Go'),
          ),
        ),
        reduced: reduced,
      ));
      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();
      expect(find.text('Second'), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(find.text('Second'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('skeleton switcher cross-fades to content', (tester) async {
    Widget build(bool loading) => _app(KSkeletonSwitcher(
          loading: loading,
          skeleton: const KShimmerBox(width: 100, height: 20),
          child: const Text('Ready'),
        ));
    await tester.pumpWidget(build(true));
    expect(find.byType(KShimmerBox), findsOneWidget);
    await tester.pumpWidget(build(false));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(KShimmerBox), findsOneWidget); // still fading out
    await tester.pumpAndSettle();
    expect(find.byType(KShimmerBox), findsNothing);
    expect(find.text('Ready'), findsOneWidget);
  });

  test('sheet spring curve starts at 0, ends at 1, never overshoots', () {
    final c = KMotion.sheetCurve;
    expect(c.transform(0), 0);
    expect(c.transform(1), 1);
    for (var i = 0; i <= 100; i++) {
      final v = c.transform(i / 100);
      expect(v, inInclusiveRange(0.0, 1.0));
    }
  });
}
