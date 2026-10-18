import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/config/app_theme.dart';
import 'package:kynetix/screens/add_meal_screen.dart';
import 'package:kynetix/screens/barcode_scanner_screen.dart';
import 'package:kynetix/services/barcode_food_service.dart';

/// End-to-end for the one thing a barcode has to get right: the figures that
/// come off the pack are the figures that reach the edit screen, unchanged and
/// un-re-estimated, with the person still able to change them.
///
/// Drives the manual-entry path rather than the camera. That is deliberate and
/// not a shortcut — typing the digits under the barcode lands on exactly the
/// same lookup, and it is the path that works when the camera is refused,
/// unavailable, or pointed at a crumpled wrapper.
///
/// Updated for the full-screen scanner: the editor's inline "Scan a barcode"
/// pill (tooltip "Scan barcode") opens the scanner, "Type the code" opens the
/// code sheet, and the product sheet's primary button ("Add 30 g to this
/// meal") replaces the old "Review & add". The logged row now carries the real
/// amount in its quantity and unit ("30 g Lay's Classic Salted") instead of
/// "Lay's Classic Salted (30 g)" as one serving, so the day screen and detail
/// sheet show "30 g". The stepper moves in half portions, as before.
void main() {
  const barcode = '8901491101837';

  final offBody = jsonEncode({
    'status': 1,
    'product': {
      'code': barcode,
      'product_name': 'Classic Salted',
      'brands': "Lay's",
      'serving_quantity': 30,
      'serving_size': '30 g',
      'nutriments': {
        'energy-kcal_100g': 536.0,
        'proteins_100g': 6.6,
        'carbohydrates_100g': 53.0,
        'fat_100g': 32.0,
        'fiber_100g': 4.0,
        'sugars_100g': 1.2,
      },
    },
  });

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://mock.supabase.co',
      anonKey: 'mock-anon-key',
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BarcodeScannerScreen.debugCameraEnabled = false;
    BarcodeFoodService.instance.client =
        MockClient((_) async => http.Response(offBody, 200));
  });

  tearDown(() {
    BarcodeFoodService.instance.client = null;
    BarcodeScannerScreen.debugCameraEnabled = true;
  });

  /// Routes and sheets animate; the composer's pulse only runs while
  /// estimating, so a bounded run of frames lands every transition.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> openCodeSheet(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Scan barcode'));
    await settle(tester);
    await tester.tap(find.text('Type the code'));
    await settle(tester);
  }

  Future<void> pumpAddMeal(WidgetTester tester) async {
    // A phone-height surface. At the 800×600 default the ingredient rows sit
    // below the fold and the sliver never builds them, so the editable macro
    // fields would not exist to assert on.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: AddMealScreen(
          section: MealSection.breakfast,
          date: DateTime(2026, 9, 7),
        ),
      ),
    );
    // pump() rather than pumpAndSettle() — the screen runs a repeating pulse
    // animation that never settles.
    await tester.pump();
  }

  /// Open the scanner, type the digits, look the product up.
  Future<void> lookUpBarcode(WidgetTester tester) async {
    await openCodeSheet(tester);

    await tester.enterText(find.widgetWithText(TextField, '8901491101837'),
        barcode);
    await tester.pump();

    await tester.tap(find.text('Find'));
    await settle(tester);
  }

  testWidgets('a scanned product reaches the edit screen with label figures',
      (tester) async {
    await pumpAddMeal(tester);
    await lookUpBarcode(tester);

    // The sheet shows what the pack says before anything is logged.
    expect(find.text("Lay's Classic Salted"), findsOneWidget);
    expect(find.textContaining('From the label'), findsOneWidget);

    // No pack size on this entry, so the label serving is the default.
    await tester.tap(find.text('Add 30 g to this meal'));
    await settle(tester);

    // Back on the edit screen, carrying the real amount.
    expect(find.text("30 g Lay's Classic Salted"), findsWidgets);

    // 536 kcal/100 g × 30 g = 160.8 → the calorie field reads 161, and the
    // protein field 2.0 (6.6 × 0.3). These are editable fields, not labels.
    expect(find.widgetWithText(TextField, '161'), findsWidgets);
    expect(find.widgetWithText(TextField, '2.0'), findsWidgets);
  });

  testWidgets('the quantity stepper scales what lands in the editor',
      (tester) async {
    await pumpAddMeal(tester);
    await lookUpBarcode(tester);

    // The stepper moves in half servings, so two taps is 2 × 30 g = 60 g.
    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    expect(find.text('2 × 30 g'), findsOneWidget);

    await tester.tap(find.text('Add 60 g to this meal'));
    await settle(tester);

    expect(find.text("60 g Lay's Classic Salted"), findsWidgets);
    expect(find.widgetWithText(TextField, '322'), findsWidgets);
  });

  testWidgets('an unknown product is reported, not silently logged',
      (tester) async {
    BarcodeFoodService.instance.client = MockClient(
      (_) async => http.Response(jsonEncode({'status': 0}), 200),
    );

    await pumpAddMeal(tester);
    await lookUpBarcode(tester);

    expect(find.textContaining("don't have that product"), findsOneWidget);
    expect(find.textContaining('to this meal'), findsNothing);
    // The fallbacks are offered instead of a number.
    expect(find.text('Read the label'), findsOneWidget);
    expect(find.text('Enter it yourself'), findsOneWidget);
  });

  testWidgets('a network failure offers a retry rather than a wrong number',
      (tester) async {
    BarcodeFoodService.instance.client =
        MockClient((_) async => throw http.ClientException('offline'));

    await pumpAddMeal(tester);
    await lookUpBarcode(tester);

    expect(find.textContaining("Couldn't reach"), findsOneWidget);
  });

  testWidgets('Find stays disabled until the code is a plausible barcode',
      (tester) async {
    await pumpAddMeal(tester);

    await openCodeSheet(tester);

    KButton findButton() =>
        tester.widget<KButton>(find.widgetWithText(KButton, 'Find'));

    expect(findButton().onTap, isNull);

    await tester.enterText(
        find.widgetWithText(TextField, '8901491101837'), '12345');
    await tester.pump();
    expect(findButton().onTap, isNull, reason: 'too short to be a barcode');

    await tester.enterText(
        find.widgetWithText(TextField, '8901491101837'), barcode);
    await tester.pump();
    expect(findButton().onTap, isNotNull);
  });
}
