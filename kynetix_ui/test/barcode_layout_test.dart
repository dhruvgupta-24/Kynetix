import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kynetix/config/app_theme.dart';
import 'package:kynetix/models/barcode_product.dart';
import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/screens/barcode_scanner_screen.dart';
import 'package:kynetix/widgets/barcode_product_form.dart';
import 'package:kynetix/widgets/barcode_product_sheet.dart';
import 'package:kynetix/widgets/barcode_scan_sheet.dart';

/// No overflow on a small phone with large text, in Carbon and in Paper,
/// for every barcode surface; and every tap target is at least 48dp.
BarcodeProduct longProduct() => const BarcodeProduct(
      barcode: '8904004400731',
      name: "Haldiram's Aloo Bhujia Sev Classic Family Pack Namkeen",
      brand: "Haldiram's",
      per100g: BarcodeNutriments(
        calories: 569,
        proteinG: 9,
        carbsG: 47.7,
        fatG: 37.5,
        fiberG: 0,
        sugarG: 0,
      ),
      servings: [BarcodeProduct.hundredGrams],
      netQuantity: 1000,
      packCount: 5,
      innerQuantity: 200,
      servingQuantity: 20,
    );

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'https://mock.supabase.co', anonKey: 'mock-anon-key');
  });

  setUp(() => BarcodeScannerScreen.debugCameraEnabled = false);
  tearDown(() {
    BarcodeScannerScreen.debugCameraEnabled = true;
    KThemeController.instance.value = ThemeMode.system;
  });

  final surfaces = <String, Widget Function()>{
    'scanner': () => BarcodeScannerScreen(
          date: DateTime(2026, 9, 7),
          section: MealSection.eveningSnack,
        ),
    'product sheet': () => Scaffold(
          body: SingleChildScrollView(
            child: BarcodeProductSheet(
              product: longProduct(),
              date: DateTime(2026, 9, 7),
              initialSection: MealSection.eveningSnack,
            ),
          ),
        ),
    'manual form': () => const Scaffold(
          body: SingleChildScrollView(
            child: BarcodeProductForm(
              barcode: '8901234500001',
              mode: BarcodeFormMode.labelPhoto,
            ),
          ),
        ),
    'code sheet': () => const Scaffold(
          body: SingleChildScrollView(child: BarcodeCodeSheet()),
        ),
  };

  for (final dark in [true, false]) {
    for (final width in [320.0, 411.0]) {
      for (final scale in [1.0, 1.5]) {
        for (final entry in surfaces.entries) {
          testWidgets(
              '${entry.key}: ${dark ? 'Carbon' : 'Paper'} ${width}dp ${scale}x',
              (tester) async {
            KThemeController.instance.value = dark ? ThemeMode.dark : ThemeMode.light;
            tester.view.physicalSize = Size(width * 3, 760 * 3);
            tester.view.devicePixelRatio = 3;
            addTearDown(tester.view.reset);

            await tester.pumpWidget(KThemeScope(
              builder: (context, palette) => MaterialApp(
                home: MediaQuery(
                  data: MediaQueryData(
                    size: Size(width, 760),
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: entry.value(),
                ),
              ),
            ));
            for (var i = 0; i < 5; i++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
            expect(tester.takeException(), isNull);
            expect(KColor.isDark, dark);

            // 48dp targets for every tappable thing that is on screen.
            for (final e in find.byType(IconButton).evaluate()) {
              final size = tester.getSize(find.byWidget(e.widget));
              expect(size.width >= 48 && size.height >= 48, isTrue,
                  reason: 'IconButton is $size');
            }
          });
        }
      }
    }
  }
}
