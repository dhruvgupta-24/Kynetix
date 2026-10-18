import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kynetix/models/barcode_product.dart';
import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/screens/barcode_scanner_screen.dart';
import 'package:kynetix/services/barcode_food_service.dart';
import 'package:kynetix/services/barcode_label_reader.dart';
import 'package:kynetix/services/barcode_user_products.dart';
import 'package:kynetix/widgets/barcode_product_sheet.dart';

/// The product sheet logs exactly the chosen amount into the chosen day and
/// section, and the not-found fallback saves a product the next scan recalls.
const parleDoc = <String, dynamic>{
  'code': '8901719134845',
  'product_name': 'Parle-G Biscuit',
  'brands': 'Parle',
  'quantity': '40 g',
  'serving_quantity': 15,
  'nutriments': {
    'energy-kcal_100g': 448.0,
    'proteins_100g': 7.0,
    'carbohydrates_100g': 78.4,
    'fat_100g': 11.8,
  },
};

BarcodeProduct pack40() => BarcodeFoodService.parseProduct(parleDoc)!;

void main() {
  final date = DateTime(2026, 9, 7);

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'https://mock.supabase.co', anonKey: 'mock-anon-key');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dayLogStore.clear();
    BarcodeScannerScreen.debugCameraEnabled = false;
    BarcodeUserProducts.instance.userIdOverride = () => 'user-a';
  });

  tearDown(() {
    BarcodeScannerScreen.debugCameraEnabled = true;
    BarcodeUserProducts.instance.userIdOverride = null;
    BarcodeFoodService.instance.client = null;
    BarcodeScannerScreen.debugPickLabelPhoto = null;
    BarcodeLabelReader.instance.invokeOverride = null;
    dayLogStore.clear();
  });

  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// A host page with a button that opens [open].
  Future<void> host(WidgetTester tester, Future<void> Function(BuildContext) open) async {
    await phone(tester);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(onPressed: () => open(context), child: const Text('open')),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  group('product sheet', () {
    testWidgets('logs the whole 40 g pack, not 100 g, to the picked section', (tester) async {
      BarcodeSheetResult? result;
      await host(tester, (context) async {
        result = await showBarcodeProductSheet(
          context,
          product: pack40(),
          date: date,
          section: MealSection.breakfast,
        );
      });

      expect(find.text('Parle-G Biscuit'), findsOneWidget);
      expect(find.text('From the label · per 100 g'), findsOneWidget);
      expect(find.text('Whole pack · 40 g'), findsOneWidget);
      expect(find.text('1 serving · 15 g'), findsOneWidget);
      expect(find.text('Log 40 g to Breakfast'), findsOneWidget);
      // 448 × 0.4 = 179.2 → 179 kcal shown.
      expect(find.text('179'), findsOneWidget);

      await tester.ensureVisible(find.text('Lunch'));
      await tester.tap(find.text('Lunch'));
      await tester.pump();
      expect(find.text('Log 40 g to Lunch'), findsOneWidget);

      await tester.ensureVisible(find.text('Log 40 g to Lunch'));
      await tester.tap(find.text('Log 40 g to Lunch'));
      await settle(tester);

      expect(result?.action, BarcodeSheetAction.logged);
      final log = logFor(date);
      expect(log.entriesFor(MealSection.breakfast), isEmpty);
      final entry = log.entriesFor(MealSection.lunch).single;
      expect(entry.finalSavedInput, '40 g Parle-G Biscuit');
      expect(entry.section, MealSection.lunch);
      final item = entry.result.items.single;
      expect(item.quantity, 40);
      expect(item.unit, 'g');
      expect(entry.result.calories.mid, closeTo(179.2, 0.05));
      expect(entry.result.protein.mid, closeTo(2.8, 0.05));
    });

    testWidgets('100 g and a stepped serving log what they say', (tester) async {
      await host(tester, (context) => showBarcodeProductSheet(
            context,
            product: pack40(),
            date: date,
            section: MealSection.eveningSnack,
          ));

      await tester.tap(find.text('1 serving · 15 g'));
      await tester.pump();
      await tester.tap(find.byTooltip('More'));
      await tester.pump();
      expect(find.text('1.5 × 15 g'), findsOneWidget);
      expect(find.text('Log 22.5 g to Evening Snack'), findsOneWidget);

      await tester.tap(find.text('100 g'));
      await tester.pump();
      await tester.ensureVisible(find.text('Log 100 g to Evening Snack'));
      await tester.tap(find.text('Log 100 g to Evening Snack'));
      await settle(tester);

      final entry = logFor(date).entriesFor(MealSection.eveningSnack).single;
      expect(entry.result.items.single.quantity, 100);
      expect(entry.result.calories.mid, 448);
    });

    testWidgets('a custom amount scales exactly', (tester) async {
      await host(tester, (context) => showBarcodeProductSheet(
            context,
            product: pack40(),
            date: date,
            section: MealSection.dinner,
          ));

      await tester.tap(find.text('Custom'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '25');
      await tester.pump();
      await tester.ensureVisible(find.text('Log 25 g to Dinner'));
      await tester.tap(find.text('Log 25 g to Dinner'));
      await settle(tester);

      final entry = logFor(date).entriesFor(MealSection.dinner).single;
      expect(entry.result.items.single.quantity, 25);
      expect(entry.result.calories.mid, closeTo(112.0, 0.05));
    });

    testWidgets('a multipack starts at one inner pack', (tester) async {
      final multi = BarcodeFoodService.parseProduct({
        'code': '8901063000000',
        'product_name': 'Marie Gold',
        'quantity': '6 x 35 g',
        'nutriments': {
          'energy-kcal_100g': 445.0,
          'proteins_100g': 7.9,
          'carbohydrates_100g': 79.5,
          'fat_100g': 10.6,
        },
      })!;
      await host(tester, (context) => showBarcodeProductSheet(
            context,
            product: multi,
            date: date,
            section: MealSection.breakfast,
          ));
      expect(find.text('Log 35 g to Breakfast'), findsOneWidget);
      expect(find.text('Whole pack · 210 g'), findsOneWidget);
    });

    testWidgets('fill mode returns the portion without logging', (tester) async {
      BarcodeSheetResult? result;
      await host(tester, (context) async {
        result = await showBarcodeProductSheet(
          context,
          product: pack40(),
          date: date,
          section: MealSection.breakfast,
          mode: BarcodeSheetMode.fill,
        );
      });
      expect(find.text('Edit before logging'), findsNothing);
      await tester.ensureVisible(find.text('Add 40 g to this meal'));
      await tester.tap(find.text('Add 40 g to this meal'));
      await settle(tester);
      expect(result?.action, BarcodeSheetAction.fill);
      expect(result?.result.items.single.quantity, 40);
      expect(logFor(date).entriesFor(MealSection.breakfast), isEmpty);
    });
  });

  group('edit before logging', () {
    testWidgets('opens the editor with the exact amount and logs it', (tester) async {
      BarcodeFoodService.instance.client = MockClient((_) async => http.Response(
            jsonEncode({'status': 1, 'product': parleDoc}),
            200,
          ));
      BarcodeFlowOutcome? outcome;
      await host(tester, (context) async {
        outcome = await openBarcodeFlow(context, date: date, section: MealSection.lunch);
      });
      await tester.tap(find.text('Type the code'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), '8901719134845');
      await tester.pump();
      await tester.tap(find.text('Find'));
      await settle(tester);

      await tester.ensureVisible(find.text('Edit before logging'));
      await tester.tap(find.text('Edit before logging'));
      await settle(tester);

      // The editor, pre-filled with the real amount and the label figures.
      expect(find.text('Add to Lunch'), findsOneWidget);
      expect(find.text('40 g Parle-G Biscuit'), findsWidgets);
      expect(find.widgetWithText(TextField, '179'), findsWidgets);
      expect(logFor(date).entriesFor(MealSection.lunch), isEmpty,
          reason: 'nothing is logged before the editor saves');

      await tester.ensureVisible(find.text('Log meal'));
      await tester.tap(find.text('Log meal'));
      await settle(tester);

      final entry = logFor(date).entriesFor(MealSection.lunch).single;
      expect(outcome?.entry, isNotNull);
      expect(entry.result.items.single.quantity, 40);
      expect(entry.result.items.single.unit, 'g');
      expect(entry.result.calories.mid, closeTo(179, 0.6));
      expect(find.text('Meal logged to Lunch.'), findsOneWidget);
    });
  });

  group('scanner fallback', () {
    testWidgets('read the label: Kyno pre-fills, the person confirms, then logs', (tester) async {
      BarcodeFoodService.instance.client = MockClient((_) async => http.Response(
            jsonEncode({
              'status': 1,
              'product': {
                'code': '8901725133979',
                'product_name': 'Sunfeast Dark Fantasy Bourbon',
                'quantity': '50g',
                'nutriments': <String, dynamic>{},
              },
            }),
            200,
          ));
      BarcodeScannerScreen.debugPickLabelPhoto = () async => Uint8List.fromList([1, 2, 3]);
      Map<String, dynamic>? sent;
      BarcodeLabelReader.instance.invokeOverride = (body) async {
        sent = body;
        return {
          'success': true,
          'response': jsonEncode({
            'readable': true,
            'product_name': null,
            'brand': null,
            'basis': 'per_100g',
            'net_quantity': 50,
            'net_unit': 'g',
            'serving_size': null,
            'per_100': {
              'energy_kcal': 490,
              'protein_g': 5.5,
              'carbohydrates_g': 68,
              'fat_g': 21.5,
              'fibre_g': 2,
              'sugar_g': 32,
            },
          }),
        };
      };

      await host(tester, (context) => openBarcodeFlow(context, date: date, section: MealSection.eveningSnack));
      await tester.tap(find.text('Type the code'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), '8901725133979');
      await tester.pump();
      await tester.tap(find.text('Find'));
      await settle(tester);

      await tester.tap(find.text('Read the label'));
      await settle(tester);

      expect(sent?['purpose'], 'label_read');
      expect(find.text('Check the numbers'), findsOneWidget);
      // OFF's name and Kyno's numbers are pre-filled, and editable.
      expect(find.widgetWithText(TextField, 'Sunfeast Dark Fantasy Bourbon'), findsOneWidget);
      expect(find.widgetWithText(TextField, '490'), findsOneWidget);
      expect(logFor(date).entriesFor(MealSection.eveningSnack), isEmpty);

      // The person corrects one number before saving.
      await tester.enterText(find.widgetWithText(TextField, '490'), '488');
      await tester.ensureVisible(find.text('Save product'));
      await tester.tap(find.text('Save product'));
      await settle(tester);

      expect(find.text('From your label photo · per 100 g'), findsOneWidget);
      await tester.ensureVisible(find.text('Log 50 g to Evening Snack'));
      await tester.tap(find.text('Log 50 g to Evening Snack'));
      await settle(tester);

      final entry = logFor(date).entriesFor(MealSection.eveningSnack).single;
      expect(entry.result.calories.mid, 244);
      final saved = await BarcodeUserProducts.instance.get('8901725133979');
      expect(saved?.source, BarcodeSource.labelPhoto);
      expect(saved?.per100g.calories, 488);
    });

    testWidgets('enter it yourself, log it, and the next scan is instant', (tester) async {
      var offCalls = 0;
      BarcodeFoodService.instance.client = MockClient((_) async {
        offCalls++;
        return http.Response(jsonEncode({'status': 0}), 200);
      });

      BarcodeFlowOutcome? outcome;
      await host(tester, (context) async {
        outcome = await openBarcodeFlow(context, date: date, section: MealSection.breakfast);
      });

      Future<void> typeCode() async {
        await tester.tap(find.text('Type the code'));
        await settle(tester);
        await tester.enterText(find.byType(TextField), '8901234500001');
        await tester.pump();
        await tester.tap(find.text('Find'));
        await settle(tester);
      }

      await typeCode();
      expect(find.text("We don't have that product yet"), findsOneWidget);
      await tester.tap(find.text('Enter it yourself'));
      await settle(tester);

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Local Protein Bar');
      await tester.enterText(fields.at(1), '40');
      await tester.enterText(fields.at(2), '400');
      await tester.enterText(fields.at(3), '30');
      await tester.enterText(fields.at(4), '40');
      await tester.enterText(fields.at(5), '13');
      await tester.pump();
      await tester.ensureVisible(find.text('Save product'));
      await tester.tap(find.text('Save product'));
      await settle(tester);

      expect(find.text('You entered this · per 100 g'), findsOneWidget);
      await tester.ensureVisible(find.text('Log 40 g to Breakfast'));
      await tester.tap(find.text('Log 40 g to Breakfast'));
      await settle(tester);

      expect(outcome?.entry, isNotNull);
      expect(find.text('Logged 40 g of Local Protein Bar to Breakfast.'), findsOneWidget);
      final entry = logFor(date).entriesFor(MealSection.breakfast).single;
      expect(entry.result.items.single.quantity, 40);
      expect(entry.result.calories.mid, 160);
      expect(entry.result.protein.mid, 12);

      // Saved for this user, and the next scan goes straight to the sheet.
      expect((await BarcodeUserProducts.instance.get('8901234500001'))?.name, 'Local Protein Bar');
      expect(offCalls, 1);
      await tester.pump(const Duration(seconds: 4));
      await tester.tap(find.text('open'));
      await settle(tester);
      await typeCode();
      expect(find.text('Log 40 g to Breakfast'), findsOneWidget);
      expect(offCalls, 1, reason: 'recalled locally, no lookup');
    });
  });
}
