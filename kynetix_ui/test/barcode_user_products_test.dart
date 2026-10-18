import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kynetix/models/barcode_product.dart';
import 'package:kynetix/services/barcode_food_service.dart';
import 'package:kynetix/services/barcode_label_reader.dart';
import 'package:kynetix/services/barcode_user_products.dart';
import 'package:kynetix/services/persistence_service.dart';

/// The fallback path: a product Open Food Facts can't help with is read off
/// the label (or typed in), confirmed, and remembered per user, so the next
/// scan is instant and uses the person's own numbers.
BarcodeProduct confirmed({
  String barcode = '8901234500001',
  BarcodeSource source = BarcodeSource.labelPhoto,
  double kcal = 520,
}) =>
    BarcodeProduct(
      barcode: barcode,
      name: 'Local Namkeen Mix',
      per100g: BarcodeNutriments(
        calories: kcal,
        proteinG: 12,
        carbsG: 50,
        fatG: 30,
        fiberG: 4,
        sugarG: 3,
      ),
      servings: const [BarcodeProduct.hundredGrams],
      netQuantity: 40,
      source: source,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var userId = 'user-a';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    userId = 'user-a';
    BarcodeUserProducts.instance.userIdOverride = () => userId;
    BarcodeFoodService.instance.client = null;
  });

  tearDown(() {
    BarcodeUserProducts.instance.userIdOverride = null;
    BarcodeFoodService.instance.client = null;
    BarcodeLabelReader.instance.invokeOverride = null;
  });

  group('storage', () {
    test('uses a per-user key, so account deletion sweeps it', () async {
      expect(BarcodeUserProducts.keyFor('user-a'), 'barcode_user_products_v1_user-a');

      await BarcodeUserProducts.instance.save(confirmed());
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('barcode_user_products_v1_user-a'), isNotNull);

      final removed = await PersistenceService.removeKeysForUser('user-a', prefsOverride: prefs);
      expect(removed, contains('barcode_user_products_v1_user-a'));
      expect(await BarcodeUserProducts.instance.get('8901234500001'), isNull);
    });

    test('saves and recalls a confirmed product with its provenance', () async {
      await BarcodeUserProducts.instance.save(confirmed(source: BarcodeSource.userEntered));
      final back = await BarcodeUserProducts.instance.get('8901234500001');
      expect(back, isNotNull);
      expect(back!.name, 'Local Namkeen Mix');
      expect(back.source, BarcodeSource.userEntered);
      expect(back.netQuantity, 40);
      expect(back.defaultAmount.grams, 40);
      expect(back.source.note(back.unit), 'You entered this · per 100 g');
    });

    test("one account never sees another's products", () async {
      await BarcodeUserProducts.instance.save(confirmed());
      userId = 'user-b';
      expect(await BarcodeUserProducts.instance.get('8901234500001'), isNull);
      userId = 'user-a';
      expect(await BarcodeUserProducts.instance.get('8901234500001'), isNotNull);
    });

    test('remove forgets one product', () async {
      await BarcodeUserProducts.instance.save(confirmed());
      await BarcodeUserProducts.instance.remove('8901234500001');
      expect(await BarcodeUserProducts.instance.get('8901234500001'), isNull);
    });
  });

  group('lookup precedence', () {
    test('a saved product is recalled without touching the network', () async {
      var calls = 0;
      BarcodeFoodService.instance.client = MockClient((_) async {
        calls++;
        return http.Response(jsonEncode({'status': 0}), 200);
      });

      // First scan: unknown to OFF.
      final miss = await BarcodeFoodService.instance.lookup('8901234500001');
      expect(miss.status, BarcodeLookupStatus.notFound);
      expect(calls, 1);

      // Confirmed from the label, then scanned again.
      await BarcodeUserProducts.instance.save(confirmed());
      final hit = await BarcodeFoodService.instance.lookup('8901234500001');
      expect(hit.isFound, isTrue);
      expect(hit.product!.source, BarcodeSource.labelPhoto);
      expect(calls, 1, reason: 'instant: no second request');
    });

    test("the user's own numbers win over Open Food Facts", () async {
      BarcodeFoodService.instance.client = MockClient((_) async => http.Response(
            jsonEncode({
              'status': 1,
              'product': {
                'code': '8901234500001',
                'product_name': 'Namkeen (crowd data)',
                'nutriments': {
                  'energy-kcal_100g': 400.0,
                  'proteins_100g': 10.0,
                  'carbohydrates_100g': 60.0,
                  'fat_100g': 13.0,
                },
              },
            }),
            200,
          ));
      await BarcodeUserProducts.instance.save(confirmed(kcal: 520));

      final res = await BarcodeFoodService.instance.lookup('8901234500001');
      expect(res.product!.name, 'Local Namkeen Mix');
      expect(res.product!.per100g.calories, 520);
    });

    test('a product with no nutrition still pre-fills the forms', () async {
      BarcodeFoodService.instance.client = MockClient((_) async => http.Response(
            jsonEncode({
              'status': 1,
              'product': {
                'code': '8904004400999',
                'product_name': 'Bhujia',
                'brands': "Haldiram's",
                'quantity': '200 gm',
                'image_front_small_url': 'https://images.openfoodfacts.org/images/x.jpg',
                'nutriments': <String, dynamic>{},
              },
            }),
            200,
          ));
      final res = await BarcodeFoodService.instance.lookup('8904004400999');
      expect(res.status, BarcodeLookupStatus.notFound);
      expect(res.partial, isNotNull);
      expect(res.partial!.name, "Haldiram's Bhujia");
      expect(res.partial!.netQuantity, 200);
      expect(res.partial!.imageUrl, isNotNull);
    });
  });

  group('label reader', () {
    final canonical = jsonEncode({
      'readable': true,
      'product_name': 'Gluco Biscuits',
      'brand': 'Parle',
      'basis': 'per_100g',
      'net_quantity': 40,
      'net_unit': 'g',
      'serving_size': 15,
      'per_100': {
        'energy_kcal': 454,
        'protein_g': 6.9,
        'carbohydrates_g': 77.3,
        'fat_g': 13,
        'fibre_g': null,
        'sugar_g': 25.5,
      },
    });

    test('sends one photo with purpose label_read', () async {
      Map<String, dynamic>? sent;
      BarcodeLabelReader.instance.invokeOverride = (body) async {
        sent = body;
        return {'success': true, 'response': canonical};
      };
      final r = await BarcodeLabelReader.instance.read(Uint8List.fromList([1, 2, 3]));
      expect(sent!['purpose'], 'label_read');
      final content = (sent!['messages'] as List).single['content'] as List;
      expect(content.where((b) => b['type'] == 'image_url'), hasLength(1));
      expect((content.last['image_url']['url'] as String).startsWith('data:image/jpeg;base64,'), isTrue);
      expect(sent!.containsKey('stream'), isFalse);

      expect(r.calories, 454);
      expect(r.netQuantity, 40);
      expect(r.unit, 'g');
      expect(r.fiberG, isNull);
      expect(r.productName, 'Gluco Biscuits');
    });

    test('an unreadable label is a calm, typed failure', () async {
      BarcodeLabelReader.instance.invokeOverride =
          (_) async => {'success': true, 'response': '{"readable": false}'};
      await expectLater(
        BarcodeLabelReader.instance.read(Uint8List(1)),
        throwsA(isA<LabelReadException>()
            .having((e) => e.kind, 'kind', LabelReadFailure.unreadable)),
      );
    });

    test('out-of-range numbers are refused on the client too', () {
      expect(
        LabelReading.tryParse(jsonEncode({
          'readable': true,
          'per_100': {'energy_kcal': 4540, 'protein_g': 1, 'carbohydrates_g': 1, 'fat_g': 1},
        })),
        isNull,
      );
    });

    test('a network failure maps to offline, never raw text', () async {
      BarcodeLabelReader.instance.invokeOverride = (_) async => throw Exception('socket');
      try {
        await BarcodeLabelReader.instance.read(Uint8List(1));
        fail('expected failure');
      } on LabelReadException catch (e) {
        expect(e.kind, LabelReadFailure.offline);
        expect(e.userMessage, isNot(contains('socket')));
      }
    });
  });
}
