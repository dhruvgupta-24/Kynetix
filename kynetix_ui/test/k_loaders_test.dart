import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/config/app_theme.dart';

const _lines = ['Crunching your macros…', 'Warming up…', 'Pulling your history…'];

Map<String, Widget Function()> _loaders() => {
      'KOrbitLoader': () => const KOrbitLoader(),
      'KOrbitLoader tinted': () => KOrbitLoader(size: 24, color: KColor.violet),
      'KMacroLoader': () => const KMacroLoader(),
      'KRepLoader': () => const KRepLoader(),
      'KSpinner': () => const KSpinner(semanticsLabel: 'Loading'),
      'KLoadingLabel': () => const KLoadingLabel(messages: _lines),
      'KLoaderPanel': () => const KLoaderPanel(messages: _lines),
      'KLoaderPanel macro': () => const KLoaderPanel(
            loader: KMacroLoader(semanticsLabel: null),
            messages: _lines,
            semanticsLabel: 'Estimating your meal',
          ),
      'KPulseLoader': () => const KPulseLoader(),
      'KLoadingDots': () => const KLoadingDots(),
      'KShimmerBox': () => const KShimmerBox(width: 120, height: 40),
      'KCardShimmer': () => const KCardShimmer(),
      'KChartShimmer': () => const KChartShimmer(),
      'KMessageShimmer': () => const KMessageShimmer(),
    };

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    KThemeScope(
      builder: (context, palette) => MaterialApp(
        home: Scaffold(
          backgroundColor: KColor.bg,
          body: Center(child: SizedBox(width: 360, child: child)),
        ),
      ),
    ),
  );
}

void main() {
  tearDown(() {
    KLoaders.debugForceAmbient = false;
    KThemeController.instance.value = ThemeMode.system;
  });

  for (final mode in [ThemeMode.dark, ThemeMode.light]) {
    for (final ambient in [false, true]) {
      final tag = '${mode.name} / ambient ${ambient ? 'on' : 'off'}';
      _loaders().forEach((name, build) {
        testWidgets('$name renders ($tag)', (tester) async {
          final semantics = tester.ensureSemantics();
          KThemeController.instance.value = mode;
          KLoaders.debugForceAmbient = ambient;

          await _pump(tester, build());
          expect(KColor.isDark, mode == ThemeMode.dark);

          // Loop through several cycles with fixed pumps (never settle).
          for (var i = 0; i < 12; i++) {
            await tester.pump(const Duration(milliseconds: 350));
          }
          expect(tester.takeException(), isNull);

          if (name.startsWith('KLoaderPanel')) {
            final label = name == 'KLoaderPanel' ? 'Loading' : 'Estimating your meal';
            expect(find.bySemanticsLabel(label), findsOneWidget);
            final node = tester.getSemantics(find.bySemanticsLabel(label));
            expect(node.flagsCollection.isLiveRegion, isTrue);
          } else if (name == 'KLoadingLabel') {
            expect(find.bySemanticsLabel(_lines.first), findsOneWidget);
          } else if (name.startsWith('KOrbit') ||
              name == 'KMacroLoader' ||
              name == 'KRepLoader' ||
              name == 'KSpinner' ||
              name == 'KPulseLoader') {
            expect(find.bySemanticsLabel('Loading'), findsOneWidget);
          }

          // Unmount cleanly mid-loop (no leaked tickers).
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          expect(tester.takeException(), isNull);
          semantics.dispose();
        });
      });
    }
  }

  testWidgets('loading label is static and shows the first line when motion is off',
      (tester) async {
    await _pump(tester, const KLoadingLabel(messages: _lines));
    await tester.pump(const Duration(seconds: 10));
    expect(find.text(_lines.first), findsOneWidget);
    expect(find.text(_lines[1]), findsNothing);
  });

  testWidgets('loading label rotates no faster than every 2.6s when allowed',
      (tester) async {
    KLoaders.debugForceAmbient = true;
    await _pump(tester, const KLoadingLabel(messages: _lines));
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.text(_lines.first), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1600)); // 2.6s in
    expect(find.text(_lines.first), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600)); // 3.2s in
    expect(find.text(_lines[1]), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reduced motion keeps loops parked even when forced', (tester) async {
    KLoaders.debugForceAmbient = true;
    await tester.pumpWidget(
      KThemeScope(
        builder: (context, palette) => MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: const Center(child: KOrbitLoader()),
        ),
      ),
    );
    // Settles because nothing is looping.
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
