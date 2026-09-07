import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kynetix/models/barcode_product.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/services/barcode_food_service.dart';

/// A minimal Open Food Facts product document, overridable per test.
Map<String, dynamic> offProduct({
  String code = '8901491101837',
  String? productName = 'Classic Salted',
  String? brands = "Lay's",
  String? quantity,
  dynamic servingQuantity,
  String? servingSize,
  Map<String, dynamic>? nutriments,
}) =>
    {
      'code': code,
      if (productName != null) 'product_name': productName,
      if (brands != null) 'brands': brands,
      if (quantity != null) 'quantity': quantity,
      if (servingQuantity != null) 'serving_quantity': servingQuantity,
      if (servingSize != null) 'serving_size': servingSize,
      'nutriments': nutriments ??
          {
            'energy-kcal_100g': 536.0,
            'proteins_100g': 6.6,
            'carbohydrates_100g': 53.0,
            'fat_100g': 32.0,
            'fiber_100g': 4.0,
            'sugars_100g': 1.2,
          },
    };

String offResponse(Map<String, dynamic> product) =>
    jsonEncode({'status': 1, 'product': product});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BarcodeFoodService.instance.client = null;
  });

  // ── Code validation ───────────────────────────────────────────────────────

  group('isBarcode', () {
    test('accepts EAN-8 through GTIN-14', () {
      expect(BarcodeFoodService.isBarcode('12345678'), isTrue);
      expect(BarcodeFoodService.isBarcode('8901491101837'), isTrue);
      expect(BarcodeFoodService.isBarcode('12345678901234'), isTrue);
    });

    test('rejects anything that is not 8-14 digits', () {
      expect(BarcodeFoodService.isBarcode('1234567'), isFalse);
      expect(BarcodeFoodService.isBarcode('123456789012345'), isFalse);
      expect(BarcodeFoodService.isBarcode('890149110183X'), isFalse);
      expect(BarcodeFoodService.isBarcode(''), isFalse);
      expect(BarcodeFoodService.isBarcode(null), isFalse);
    });
  });

  // ── Normalisation ─────────────────────────────────────────────────────────

  group('parseProduct', () {
    test('prefixes the brand so packaged food is recognisable', () {
      final p = BarcodeFoodService.parseProduct(offProduct())!;
      expect(p.name, "Lay's Classic Salted");
      expect(p.brand, "Lay's");
    });

    test('does not repeat a brand already inside the product name', () {
      final p = BarcodeFoodService.parseProduct(
        offProduct(productName: "Lay's Classic Salted"),
      )!;
      expect(p.name, "Lay's Classic Salted");
    });

    test('falls back to converting kJ when kcal is absent', () {
      final p = BarcodeFoodService.parseProduct(offProduct(nutriments: {
        'energy-kj_100g': 1000.0,
        'proteins_100g': 5.0,
        'carbohydrates_100g': 30.0,
        'fat_100g': 9.0,
      }))!;
      // 1000 / 4.184 = 239 kcal
      expect(p.per100g.calories, 239.0);
    });

    test('returns null when the product carries no energy at all', () {
      expect(
        BarcodeFoodService.parseProduct(offProduct(nutriments: const {})),
        isNull,
      );
    });

    test('returns null when the product has no usable name', () {
      expect(
        BarcodeFoodService.parseProduct(
          offProduct(productName: null, brands: null),
        ),
        isNull,
      );
    });

    test('uses the brand alone when only a brand is known', () {
      final p = BarcodeFoodService.parseProduct(offProduct(productName: null))!;
      expect(p.name, "Lay's");
    });
  });

  // ── Servings ──────────────────────────────────────────────────────────────

  group('servings', () {
    test('always ends with a plain 100 g portion', () {
      final p = BarcodeFoodService.parseProduct(offProduct())!;
      expect(p.servings.last.grams, 100);
      expect(p.servings.last.unit, 'g');
    });

    test('offers the stated serving first, then the pack', () {
      final p = BarcodeFoodService.parseProduct(offProduct(
        servingQuantity: 30,
        servingSize: '30 g',
        quantity: '52 g',
      ))!;
      expect(p.servings.map((s) => s.grams).toList(), [30.0, 52.0, 100.0]);
      expect(p.servings[1].unit, 'pack');
      expect(p.defaultServing.grams, 30.0);
    });

    test('parses a pack weight out of free text', () {
      final p = BarcodeFoodService.parseProduct(offProduct(quantity: '140g'))!;
      expect(p.servings.first.grams, 140.0);
    });

    test('ignores a pack too big to be one sitting', () {
      final p = BarcodeFoodService.parseProduct(offProduct(quantity: '1000 g'))!;
      expect(p.servings.length, 1);
      expect(p.servings.single.grams, 100);
    });

    test('a litre is not one gram', () {
      // Reading the unit off "1 L" as a bare 1 produced a one-gram "pack",
      // and logging it recorded a fraction of a calorie for a litre of juice.
      expect(BarcodeFoodService.parsePackWeight('1 L'), 1000.0);
      expect(BarcodeFoodService.parsePackWeight('500 ml'), 500.0);
      expect(BarcodeFoodService.parsePackWeight('1.5 kg'), 1500.0);
      expect(BarcodeFoodService.parsePackWeight('33 cl'), 330.0);
      expect(BarcodeFoodService.parsePackWeight('140g'), 140.0);
    });

    test('accepts the European decimal comma', () {
      expect(BarcodeFoodService.parsePackWeight('1,5 l'), 1500.0);
    });

    test('offers no pack chip for a multipack', () {
      // "2 x 50 g" could be the 100 g box or the 50 g sachet actually opened,
      // and a chip reading "1 pack" cannot say which.
      expect(BarcodeFoodService.parsePackWeight('2 x 50 g'), isNull);
      expect(BarcodeFoodService.parsePackWeight('6 × 330 ml'), isNull);

      final p = BarcodeFoodService.parseProduct(
        offProduct(quantity: '2 x 50 g'),
      )!;
      expect(p.servings.single.grams, 100);
    });

    test('ignores pack text with no unit at all', () {
      expect(BarcodeFoodService.parsePackWeight('1 sachet'), isNull);
      expect(BarcodeFoodService.parsePackWeight(''), isNull);
      expect(BarcodeFoodService.parsePackWeight(null), isNull);
    });

    test('a litre pack does not become a serving', () {
      final p = BarcodeFoodService.parseProduct(offProduct(
        quantity: '1 L',
        nutriments: const {
          'energy-kcal_100g': 50.0,
          'proteins_100g': 0.0,
          'carbohydrates_100g': 12.0,
          'fat_100g': 0.0,
        },
      ))!;
      // 1000 g exceeds the one-sitting ceiling, so only 100 g is offered —
      // never a "1 pack (1 g)" chip worth half a calorie.
      expect(p.servings.single.grams, 100);
    });

    test('does not duplicate the pack when it equals the serving', () {
      final p = BarcodeFoodService.parseProduct(offProduct(
        servingQuantity: 52,
        quantity: '52 g',
      ))!;
      expect(p.servings.map((s) => s.grams).toList(), [52.0, 100.0]);
    });
  });

  // ── Physical plausibility ─────────────────────────────────────────────────

  group('checkPer100g', () {
    BarcodeNutriments n({
      double calories = 100,
      double protein = 0,
      double carbs = 0,
      double fat = 0,
    }) =>
        BarcodeNutriments(
          calories: calories,
          proteinG: protein,
          carbsG: carbs,
          fatG: fat,
          fiberG: 0,
          sugarG: 0,
        );

    test('accepts figures that agree with their own macros', () {
      expect(
        BarcodeFoodService.checkPer100g(
          'Biscuit',
          n(calories: 480, protein: 6, carbs: 65, fat: 21),
        ),
        isNull,
      );
    });

    test('rejects calories that contradict the macros', () {
      // A mis-keyed decimal: macros say ~480, label says 48.
      final reason = BarcodeFoodService.checkPer100g(
        'Biscuit',
        n(calories: 48, protein: 6, carbs: 65, fat: 21),
      );
      expect(reason, contains('contradict'));
    });

    test('rejects more energy than pure fat can carry', () {
      final reason = BarcodeFoodService.checkPer100g(
        'Ghee',
        n(calories: 1200, protein: 0, carbs: 0, fat: 133),
      );
      expect(reason, contains('exceeds pure fat'));
    });

    test('allows a genuine fat to be mostly fat', () {
      expect(
        BarcodeFoodService.checkPer100g(
          'Amul Butter',
          n(calories: 720, protein: 0.5, carbs: 0.5, fat: 80),
        ),
        isNull,
      );
    });

    test('rejects an ordinary food claiming to be mostly fat', () {
      final reason = BarcodeFoodService.checkPer100g(
        'Masala Noodles',
        n(calories: 590, protein: 0, carbs: 5, fat: 64),
      );
      expect(reason, contains('fat/100g implausible'));
    });

    test('rejects zero calories alongside real macros', () {
      final reason = BarcodeFoodService.checkPer100g(
        'Protein Powder',
        n(calories: 0, protein: 24, carbs: 3, fat: 1),
      );
      expect(reason, contains('macros carry energy'));
    });

    test('a genuinely zero-calorie product is scannable', () {
      // Diet drinks, black coffee and water are really 0 kcal. Treating that
      // as a missing field made every one of them read as "not in the database".
      final p = BarcodeFoodService.parseProduct(offProduct(
        productName: 'Diet Coke',
        brands: 'Coca-Cola',
        nutriments: const {
          'energy-kcal_100g': 0.0,
          'proteins_100g': 0.0,
          'carbohydrates_100g': 0.0,
          'fat_100g': 0.0,
        },
      ));
      expect(p, isNotNull);
      expect(p!.per100g.calories, 0.0);
    });

    test('keeps a product whose macros were never filled in', () {
      // Open Food Facts' Indian coverage is patchy on macros. Absent is not the
      // same as zero, and must not read as a contradiction.
      final p = BarcodeFoodService.parseProduct(
        offProduct(nutriments: const {'energy-kcal_100g': 400.0}),
      );
      expect(p, isNotNull);
      expect(p!.per100g.calories, 400.0);
      expect(p.per100g.proteinG, 0.0);
    });

    test('counts alcohol at 7 kcal/g rather than rejecting beer', () {
      final p = BarcodeFoodService.parseProduct(offProduct(
        productName: 'Lager',
        brands: 'Kingfisher',
        nutriments: const {
          'energy-kcal_100g': 43.0,
          'proteins_100g': 0.4,
          'carbohydrates_100g': 3.6,
          'fat_100g': 0.0,
          'alcohol_100g': 4.5,
        },
      ));
      // 4(0.4) + 4(3.6) + 7(4.5) = 47.5 against a stated 43 — inside tolerance.
      expect(p, isNotNull);
    });

    test('counts sugar alcohols, so sugar-free sweets survive', () {
      final reason = BarcodeFoodService.checkPer100g(
        'Sugar Free Mints',
        const BarcodeNutriments(
          calories: 240,
          proteinG: 0,
          carbsG: 2,
          fatG: 0,
          fiberG: 0,
          sugarG: 0,
        ),
        polyolsG: 95,
      );
      // 4(2) + 2.4(95) = 236 against a stated 240.
      expect(reason, isNull);
    });

    test('an implausible product never becomes a BarcodeProduct', () {
      expect(
        BarcodeFoodService.parseProduct(offProduct(nutriments: {
          'energy-kcal_100g': 3000.0,
          'proteins_100g': 6.0,
          'carbohydrates_100g': 60.0,
          'fat_100g': 30.0,
        })),
        isNull,
      );
    });
  });

  // ── Portion → NutritionResult ─────────────────────────────────────────────

  group('toNutritionResult', () {
    late BarcodeProduct product;

    setUp(() {
      product = BarcodeFoodService.parseProduct(offProduct(
        servingQuantity: 30,
        servingSize: '30 g',
      ))!;
    });

    test('scales the label figures to the chosen portion', () {
      final r = product.toNutritionResult(servingIdx: 0, quantity: 1);
      // 536 kcal/100 g × 30 g = 160.8
      expect(r.calories.mid, closeTo(160.8, 0.05));
      expect(r.protein.mid, closeTo(2.0, 0.05));
      expect(r.carbohydrates!.mid, closeTo(15.9, 0.05));
      expect(r.fat!.mid, closeTo(9.6, 0.05));
    });

    test('multiplies by quantity', () {
      final one = product.toNutritionResult(servingIdx: 0, quantity: 1);
      final two = product.toNutritionResult(servingIdx: 0, quantity: 2);
      expect(two.calories.mid, closeTo(one.calories.mid * 2, 0.2));
    });

    test('states no range, because a label is not an estimate', () {
      final r = product.toNutritionResult(servingIdx: 0, quantity: 1);
      expect(r.calories.min, r.calories.max);
      expect(r.protein.min, r.protein.max);
      expect(r.confidence, 1.0);
      expect(r.warnings, isEmpty);
    });

    test('is attributed to the barcode path, not an estimator', () {
      final r = product.toNutritionResult(servingIdx: 0, quantity: 1);
      expect(r.source, 'barcode');
      expect(r.estimationAudit?.memoryPriorityLevel, 'Branded Food');
      expect(r.estimationAudit?.uncertaintyFactors, isEmpty);
      expect(r.items.single.estimated, isFalse);
      expect(r.items.single.mode, EstimationMode.packagedKnown);
    });

    test('carries the gram weight in the name, so the edit screen cannot '
        're-estimate it away', () {
      final r = product.toNutritionResult(servingIdx: 0, quantity: 2);
      // AddMealScreen rebuilds a row's text from quantity + unit + name and
      // only re-estimates when that text changes. quantity 1 / unit "serving"
      // makes the reconstructed text exactly the name.
      expect(r.items.single.quantity, 1);
      expect(r.items.single.unit, 'serving');
      expect(r.items.single.name, "Lay's Classic Salted (60 g)");
      expect(r.canonicalMeal, r.items.single.name);
    });

    test('a 100 g portion scales to the label figures unchanged', () {
      final idx = product.servings.length - 1;
      final r = product.toNutritionResult(servingIdx: idx, quantity: 1);
      expect(r.calories.mid, closeTo(536.0, 0.05));
    });
  });

  // ── Lookup ────────────────────────────────────────────────────────────────

  group('lookup', () {
    test('rejects a malformed code without touching the network', () async {
      var called = false;
      BarcodeFoodService.instance.client = MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      });

      final res = await BarcodeFoodService.instance.lookup('abc');
      expect(res.status, BarcodeLookupStatus.invalidCode);
      expect(called, isFalse);
    });

    test('resolves a product from Open Food Facts', () async {
      BarcodeFoodService.instance.client = MockClient((req) async {
        expect(req.url.path, contains('/api/v2/product/8901491101837.json'));
        expect(req.headers['User-Agent'], contains('Kynetix'));
        return http.Response(offResponse(offProduct()), 200);
      });

      final res = await BarcodeFoodService.instance.lookup('8901491101837');
      expect(res.isFound, isTrue);
      expect(res.product!.name, "Lay's Classic Salted");
    });

    test('reports an unknown product as not found', () async {
      BarcodeFoodService.instance.client = MockClient(
        (_) async => http.Response(jsonEncode({'status': 0}), 200),
      );

      final res = await BarcodeFoodService.instance.lookup('8901491101837');
      expect(res.status, BarcodeLookupStatus.notFound);
      expect(res.product, isNull);
    });

    test('treats HTTP 404 as not found', () async {
      BarcodeFoodService.instance.client =
          MockClient((_) async => http.Response('', 404));

      final res = await BarcodeFoodService.instance.lookup('8901491101837');
      expect(res.status, BarcodeLookupStatus.notFound);
    });

    test('a scan with no network is a retry, not a crash', () async {
      BarcodeFoodService.instance.client =
          MockClient((_) async => throw http.ClientException('offline'));

      final res = await BarcodeFoodService.instance.lookup('8901491101837');
      expect(res.status, BarcodeLookupStatus.networkError);
    });

    test('a product present but unusable reads as not found', () async {
      BarcodeFoodService.instance.client = MockClient(
        (_) async => http.Response(
          offResponse(offProduct(nutriments: const {})),
          200,
        ),
      );

      final res = await BarcodeFoodService.instance.lookup('8901491101837');
      expect(res.status, BarcodeLookupStatus.notFound);
    });

    test('the second scan of a pack is served from cache', () async {
      var requests = 0;
      BarcodeFoodService.instance.client = MockClient((_) async {
        requests++;
        return http.Response(offResponse(offProduct()), 200);
      });

      final first = await BarcodeFoodService.instance.lookup('8901491101837');
      final second = await BarcodeFoodService.instance.lookup('8901491101837');

      expect(requests, 1);
      expect(first.product!.name, second.product!.name);
      expect(second.product!.per100g.calories, 536.0);
    });

    test('a cached product survives a round trip through storage', () async {
      BarcodeFoodService.instance.client = MockClient(
        (_) async => http.Response(
          offResponse(offProduct(servingQuantity: 30, servingSize: '30 g')),
          200,
        ),
      );
      await BarcodeFoodService.instance.lookup('8901491101837');

      // Second call reads the JSON back out of SharedPreferences.
      final cached =
          (await BarcodeFoodService.instance.lookup('8901491101837')).product!;
      expect(cached.servings.first.grams, 30.0);
      expect(cached.servings.first.label, '30 g');
      expect(cached.brand, "Lay's");
    });

    test('a malformed document reads as not found, not a hang', () async {
      // Crowd-sourced fields arrive as the wrong type. A TypeError escaping the
      // lookup would leave the sheet's spinner turning with nothing shown.
      BarcodeFoodService.instance.client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'status': 1,
            'product': {'code': '8901491101837', 'nutriments': <dynamic>[]},
          }),
          200,
        ),
      );

      final res = await BarcodeFoodService.instance.lookup('8901491101837');
      expect(res.status, BarcodeLookupStatus.notFound);
    });

    test('junk in the response body is a network error, not a crash', () async {
      BarcodeFoodService.instance.client =
          MockClient((_) async => http.Response('<html>502</html>', 200));

      final res = await BarcodeFoodService.instance.lookup('8901491101837');
      expect(res.status, BarcodeLookupStatus.networkError);
    });

    test('a stale cache entry is refetched', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.barcode_product_cache_v1': jsonEncode({
          '8901491101837': {
            'cachedAt': DateTime.now()
                .subtract(const Duration(days: 45))
                .toIso8601String(),
            'product': {
              'barcode': '8901491101837',
              'name': 'Stale Name',
              'per100g': {'calories': 1.0},
              'servings': <dynamic>[],
            },
          },
        }),
      });

      var requests = 0;
      BarcodeFoodService.instance.client = MockClient((_) async {
        requests++;
        return http.Response(offResponse(offProduct()), 200);
      });

      final res = await BarcodeFoodService.instance.lookup('8901491101837');
      expect(requests, 1);
      expect(res.product!.name, "Lay's Classic Salted");
    });

    test('clearCache forces the next scan back to the network', () async {
      var requests = 0;
      BarcodeFoodService.instance.client = MockClient((_) async {
        requests++;
        return http.Response(offResponse(offProduct()), 200);
      });

      await BarcodeFoodService.instance.lookup('8901491101837');
      await BarcodeFoodService.instance.clearCache();
      await BarcodeFoodService.instance.lookup('8901491101837');

      expect(requests, 2);
    });
  });
}
