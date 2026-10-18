import 'package:flutter_test/flutter_test.dart';

import 'package:kynetix/models/barcode_product.dart';
import 'package:kynetix/services/barcode_food_service.dart';

/// The default-amount rule and the scaling maths. These are the two things a
/// scan has to get exactly right: which amount it proposes, and what that
/// amount contains.
Map<String, dynamic> doc({
  String? quantity,
  dynamic productQuantity,
  String? productQuantityUnit,
  dynamic servingQuantity,
  String? nutritionPer,
  Map<String, dynamic>? nutriments,
  String name = 'Test Snack',
}) =>
    {
      'code': '8901234567890',
      'product_name': name,
      'brands': 'Brand',
      'quantity': ?quantity,
      'product_quantity': ?productQuantity,
      'product_quantity_unit': ?productQuantityUnit,
      'serving_quantity': ?servingQuantity,
      'nutrition_data_per': ?nutritionPer,
      'nutriments': nutriments ??
          {
            'energy-kcal_100g': 448.0,
            'proteins_100g': 7.0,
            'carbohydrates_100g': 78.4,
            'fat_100g': 11.8,
            'fiber_100g': 0.7,
            'sugars_100g': 25.5,
          },
    };

BarcodeProduct parse(Map<String, dynamic> d) => BarcodeFoodService.parseProduct(d)!;

void main() {
  group('default amount rule', () {
    test('a 40 g pack defaults to the whole pack, not 100 g', () {
      final p = parse(doc(quantity: '40 g', servingQuantity: 15));
      expect(p.defaultAmount.kind, BarcodePortionKind.wholePack);
      expect(p.defaultAmount.grams, 40);
      expect(p.defaultAmount.chipLabel, 'Whole pack · 40 g');
    });

    test('exactly 250 g is still the whole pack; 251 g is not', () {
      expect(parse(doc(quantity: '250 g')).defaultAmount.grams, 250);
      final big = parse(doc(quantity: '251 g', servingQuantity: 30));
      expect(big.defaultAmount.kind, BarcodePortionKind.serving);
      expect(big.defaultAmount.grams, 30);
    });

    test('a multipack defaults to one inner pack', () {
      final p = parse(doc(quantity: '6 x 35 g'));
      expect(p.isMultipack, isTrue);
      expect(p.packCount, 6);
      expect(p.innerQuantity, 35);
      expect(p.netQuantity, 210);
      expect(p.defaultAmount.kind, BarcodePortionKind.innerPack);
      expect(p.defaultAmount.grams, 35);
      expect(p.defaultAmount.chipLabel, '1 pack · 35 g');
      // The whole box is still on offer.
      expect(
        p.amountOptions.map((o) => o.chipLabel),
        containsAll(['1 pack · 35 g', 'Whole pack · 210 g', '100 g']),
      );
    });

    test('"35 g x 6" reads the same as "6 x 35 g"', () {
      final p = parse(doc(quantity: '35 g x 6'));
      expect(p.defaultAmount.grams, 35);
      expect(p.netQuantity, 210);
    });

    test('a big pack defaults to the label serving', () {
      final atta = parse(doc(name: 'Atta', quantity: '5 kg', servingQuantity: 60));
      expect(atta.defaultAmount.kind, BarcodePortionKind.serving);
      expect(atta.defaultAmount.grams, 60);
      // No "whole pack · 5000 g" chip to mis-tap.
      expect(atta.amountOptions.any((o) => o.kind == BarcodePortionKind.wholePack), isFalse);
    });

    test('a big pack with no serving defaults to 100 g', () {
      final rice = parse(doc(name: 'Basmati rice', quantity: '1 kg'));
      expect(rice.defaultAmount.kind, BarcodePortionKind.hundred);
      expect(rice.defaultAmount.grams, 100);
    });

    test('an unknown pack size defaults to the serving, else 100 g', () {
      expect(parse(doc(servingQuantity: 20)).defaultAmount.grams, 20);
      expect(parse(doc()).defaultAmount.grams, 100);
      // "250" with no unit is not a pack size.
      expect(parse(doc(quantity: '250')).netQuantity, isNull);
    });

    test('a serving larger than the pack is a data error and is dropped', () {
      // Seen on a real 26.5 g Lay's entry with a 30.5 g "serving".
      final p = parse(doc(quantity: '26.5g', servingQuantity: 30.5));
      expect(p.servingQuantity, isNull);
      expect(p.defaultAmount.grams, 26.5);
      expect(p.defaultAmount.chipLabel, 'Whole pack · 26.5 g');
    });

    test('the options read as the brief describes them', () {
      final p = parse(doc(quantity: '40 g', servingQuantity: 30));
      expect(p.amountOptions.map((o) => o.chipLabel).toList(),
          ['Whole pack · 40 g', '1 serving · 30 g', '100 g']);
    });
  });

  group('ml drinks', () {
    test('a 200 ml drink defaults to the whole pack, in ml', () {
      final p = parse(doc(
        name: 'Lassi',
        quantity: '200mL',
        nutriments: const {
          'energy-kcal_100g': 88.5,
          'proteins_100g': 2.1,
          'carbohydrates_100g': 14.5,
          'fat_100g': 2.1,
        },
      ));
      expect(p.unit, 'ml');
      expect(p.isLiquid, isTrue);
      expect(p.defaultAmount.chipLabel, 'Whole pack · 200 ml');
      // 1 ml = 1 g against per-100 ml values.
      final r = p.resultForAmount(200);
      expect(r.calories.mid, closeTo(177.0, 0.05));
      expect(r.items.single.quantity, 200);
      expect(r.items.single.unit, 'ml');
      expect(r.canonicalMeal, '200 ml Brand Lassi');
    });

    test('litres become millilitres', () {
      final p = parse(doc(quantity: '1 ltr'));
      expect(p.unit, 'ml');
      expect(p.netQuantity, 1000);
    });

    test('product_quantity_unit ml is honoured when the text is missing', () {
      final p = parse(doc(productQuantity: 250, productQuantityUnit: 'ml'));
      expect(p.unit, 'ml');
      expect(p.netQuantity, 250);
    });
  });

  group('scaling', () {
    test('a 40 g pack with per-100 g values logs exactly 40 g of macros', () {
      final p = parse(doc(quantity: '40 g'));
      final n = p.nutrimentsFor(40);
      expect(n.calories, closeTo(179.2, 0.05)); // 448 × 0.4
      expect(n.proteinG, closeTo(2.8, 0.05));
      expect(n.carbsG, closeTo(31.4, 0.05)); // 31.36
      expect(n.fatG, closeTo(4.7, 0.05)); // 4.72

      final r = p.resultForAmount(40);
      expect(r.calories.min, r.calories.max, reason: 'a label is not a range');
      expect(r.calories.mid, closeTo(179.2, 0.05));
      expect(r.items.single.quantity, 40);
      expect(r.items.single.unit, 'g');
      expect(r.items.single.name, 'Brand Test Snack');
      expect(r.canonicalMeal, '40 g Brand Test Snack');
      expect(r.source, 'barcode');
      expect(r.confidence, 1.0);
    });

    test('100 g returns the label figures unchanged', () {
      final p = parse(doc());
      expect(p.nutrimentsFor(100).calories, 448);
      expect(p.nutrimentsFor(100).proteinG, 7.0);
    });

    test('scaling is linear', () {
      final p = parse(doc());
      expect(p.nutrimentsFor(70).calories,
          closeTo(p.nutrimentsFor(35).calories * 2, 0.11));
    });

    test('formats fractional amounts without trailing zeros', () {
      expect(BarcodeProduct.formatAmount(40, 'g'), '40 g');
      expect(BarcodeProduct.formatAmount(26.5, 'g'), '26.5 g');
      expect(BarcodeProduct.formatAmount(200.0, 'ml'), '200 ml');
    });
  });

  group('label shapes seen in Indian entries', () {
    test('per-serving-only nutriments convert with the serving size', () {
      final p = parse(doc(
        quantity: '30 g',
        servingQuantity: 15,
        nutriments: const {
          'energy-kcal_serving': 67.2,
          'proteins_serving': 1.05,
          'carbohydrates_serving': 11.8,
          'fat_serving': 1.77,
        },
      ));
      expect(p.per100g.calories, closeTo(448, 0.1));
      expect(p.per100g.proteinG, closeTo(7.0, 0.05));
      expect(p.per100g.carbsG, closeTo(78.7, 0.05));
      expect(p.nutrimentsFor(30).calories, closeTo(134.4, 0.1));
    });

    test('per-serving kJ only converts too', () {
      final p = parse(doc(
        servingQuantity: 20,
        nutriments: const {
          'energy-kj_serving': 440.0,
          'proteins_serving': 1.12,
          'carbohydrates_serving': 12.2,
          'fat_serving': 5.9,
        },
      ));
      expect(p.per100g.calories, closeTo(525.8, 0.2));
    });

    test('kJ only is converted', () {
      final p = parse(doc(nutriments: const {
        'energy-kj_100g': 1894.0,
        'proteins_100g': 7.0,
        'carbohydrates_100g': 78.4,
        'fat_100g': 11.8,
      }));
      expect(p.per100g.calories, 453);
    });

    test('a kcal figure typed into the kJ field is repaired, not rejected', () {
      // A real Parle-G entry stores "454" as kJ for a 454 kcal biscuit.
      final p = parse(doc(nutriments: const {
        'energy-kj_100g': 454.0,
        'proteins_100g': 6.9,
        'carbohydrates_100g': 77.3,
        'fat_100g': 13.0,
      }));
      expect(p.per100g.calories, 454);
    });

    test('pack text variants', () {
      PackQuantity? q(String s) => BarcodeFoodService.parseQuantity(s);
      expect(q('45gm')!.total, 45);
      expect(q('58 gm')!.total, 58);
      expect(q('200 gm')!.total, 200);
      expect(q('500 gms')!.total, 500);
      expect(q('1 Kg')!.total, 1000);
      expect(q('1.5 kg')!.total, 1500);
      expect(q('200mL')!.unit, 'ml');
      expect(q('Net wt. 40 g')!.total, 40);
      expect(q('4 Biscuits and 48g')!.total, 48);
      expect(q('20 g.')!.total, 20);
      expect(q('6 × 330 ml')!.count, 6);
      expect(q('1 litters')!.total, 1000);
      expect(q('1 litter')!.unit, 'ml');
      expect(q('180ml')!.total, 180);
      expect(q('1,000 g')!.total, 1000);
      expect(q('1,5 kg')!.total, 1500);
      expect(q('250'), isNull);
      expect(q('78.9'), isNull);
      expect(q('1 sachet'), isNull);
    });

    test('only Open Food Facts https images are used', () {
      expect(
        BarcodeFoodService.imageUrlOf({
          'image_front_small_url':
              'https://images.openfoodfacts.org/images/products/890/171/913/4845/front_en.3.200.jpg',
        }),
        isNotNull,
      );
      expect(BarcodeFoodService.imageUrlOf({'image_front_small_url': 'http://images.openfoodfacts.org/x.jpg'}), isNull);
      expect(BarcodeFoodService.imageUrlOf({'image_front_small_url': 'https://evil.example/x.jpg'}), isNull);
    });
  });

  group('round trip', () {
    test('new fields survive storage', () {
      final p = parse(doc(quantity: '6 x 35 g', servingQuantity: 17.5));
      final back = BarcodeProduct.fromJson(p.toJson());
      expect(back.netQuantity, 210);
      expect(back.packCount, 6);
      expect(back.innerQuantity, 35);
      expect(back.servingQuantity, 17.5);
      expect(back.unit, 'g');
      expect(back.source, BarcodeSource.openFoodFacts);
      expect(back.defaultAmount.grams, 35);
    });

    test('an old cached product (no new fields) still works', () {
      final old = BarcodeProduct.fromJson({
        'barcode': '8901491101837',
        'name': "Lay's Classic Salted",
        'per100g': {'calories': 536.0, 'proteinG': 6.6, 'carbsG': 53.0, 'fatG': 32.0},
        'servings': [
          {'label': '30 g', 'unit': 'serving', 'grams': 30.0},
          {'label': '100 g', 'unit': 'g', 'grams': 100.0},
        ],
      });
      expect(old.unit, 'g');
      // The legacy serving is recovered, so the default stays 30 g.
      expect(old.servingQuantity, 30);
      expect(old.defaultAmount.grams, 30);
      expect(old.resultForAmount(30).calories.mid, closeTo(160.8, 0.05));
    });
  });

  group('spoon-portioned foods never default to the whole pack', () {
    test('butter / ghee / ketchup default to the label serving, else 15 g', () {
      final butter = parse(doc(name: 'Amul Butter', quantity: '100 g', productQuantity: 100, servingQuantity: 10));
      expect(butter.defaultAmount.grams, 10);
      final ghee = parse(doc(name: 'Pure Cow Ghee', quantity: '200 ml', productQuantity: 200));
      expect(ghee.defaultAmount.grams, BarcodeProduct.portionedFallbackGrams);
      final ketchup = parse(doc(name: 'Tomato Ketchup', quantity: '200 g', productQuantity: 200));
      expect(ketchup.defaultAmount.grams, 15);
    });

    test('flavour words do not make a snack "portioned"', () {
      for (final name in [
        "Lay's Magic Masala", 'Kurkure Masala Munch', 'Butter Cookies',
        'Classic Salted Chips', 'Butter Chicken Ready Meal', 'Sugar Free Biscuits',
      ]) {
        final p = parse(doc(name: name, quantity: '40 g', productQuantity: 40));
        expect(p.isPortionedFood, isFalse, reason: name);
        expect(p.defaultAmount.grams, 40, reason: name);
      }
    });
  });
}
