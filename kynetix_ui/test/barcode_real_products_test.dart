import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kynetix/models/barcode_product.dart';
import 'package:kynetix/services/barcode_food_service.dart';

/// Real Open Food Facts entries for Indian packaged foods, captured from the
/// live API (test/fixtures/off_india_products.json), run through the same
/// lookup the app uses. Each row pins what a scan proposes by default.
class Expect {
  final String name;
  final double? defaultAmount; // null = not usable, goes to the fallback
  final String unit;
  final BarcodePortionKind? kind;
  final double? kcal100;
  final double? net;

  const Expect(
    this.name,
    this.defaultAmount, {
    this.unit = 'g',
    this.kind,
    this.kcal100,
    this.net,
  });
}

const expectations = <String, Expect>{
  // Biscuits
  '8901719134845': Expect('Parle-G 45 gm', 45, kind: BarcodePortionKind.wholePack, kcal100: 448, net: 45),
  '8901719120800': Expect('Parle-G "250", kcal typed as kJ, no unit', 100, kind: BarcodePortionKind.hundred, kcal100: 454),
  '8901719123917': Expect('Parle-G Gold 1 Kg, fat missing', 18.8, kind: BarcodePortionKind.serving, kcal100: 462, net: 1000),
  '8901063162914': Expect('Marie Gold 64 g', 64, kind: BarcodePortionKind.wholePack, kcal100: 445),
  '8901063091023': Expect('Good Day Harmony 120 g', 120, kind: BarcodePortionKind.wholePack, kcal100: 513),
  '8901719105913': Expect('Hide & Seek 120g', 120, kind: BarcodePortionKind.wholePack, kcal100: 479),
  '8901725015275': Expect('Dark Fantasy Choco Fills, 6 packs x 11.5g', 11.5, kind: BarcodePortionKind.innerPack, kcal100: 507, net: 69),
  '8901725133979': Expect('Dark Fantasy Bourbon, no nutrition', null, net: 50),
  // Namkeen and chips
  '8904004400731': Expect('Haldiram Aloo Bhujia 200 gm', 200, kind: BarcodePortionKind.wholePack, kcal100: 569),
  '8904004403732': Expect('Haldiram Moong Dal 200 g', 200, kind: BarcodePortionKind.wholePack, kcal100: 476),
  '8904004401073': Expect('Haldiram Khatta Mitha, contradictory figures', null, net: 50),
  '8901491503020': Expect("Lay's Magic Masala 26.5 g, serving > pack", 26.5, kind: BarcodePortionKind.wholePack, kcal100: 531),
  '8901491361026': Expect('Kurkure Masala Munch 41.5 g', 41.5, kind: BarcodePortionKind.wholePack, kcal100: 558),
  '8901491100533': Expect('Kurkure Chilli Chatka, "78.9" no unit', 20, kind: BarcodePortionKind.serving, kcal100: 562),
  '8901725013684': Expect('Bingo Mad Angles 58 gm', 58, kind: BarcodePortionKind.wholePack, kcal100: 526),
  // Instant noodles
  '8901058000269': Expect('Maggi 280 g, 70 g cake', 70, kind: BarcodePortionKind.serving, kcal100: 384.3),
  '8901058901542': Expect('Maggi 140 g', 140, kind: BarcodePortionKind.wholePack, kcal100: 389),
  // Chocolate
  '8901233030548': Expect('Dairy Milk 13.2 g', 13.2, kind: BarcodePortionKind.wholePack, kcal100: 527),
  '8901233022086': Expect('Dairy Milk Silk Bubbly, no nutrition', null, net: 50),
  // Dairy drinks and juice (ml)
  '8901262152341': Expect('Amul Kool Kesar 180 ml', 180, unit: 'ml', kind: BarcodePortionKind.wholePack, kcal100: 91.1),
  '8901262200189': Expect('Amul Lassi 200 ml', 200, unit: 'ml', kind: BarcodePortionKind.wholePack, kcal100: 88.5),
  '8901262153348': Expect('Amul Protein Lassi 200 ml', 200, unit: 'ml', kind: BarcodePortionKind.wholePack, kcal100: 53.5),
  '8902579103057': Expect('Frooti 300 ml', 100, unit: 'ml', kind: BarcodePortionKind.serving, kcal100: 65),
  '8901888006363': Expect('Real Mixed Fruit 180 ml', 180, unit: 'ml', kind: BarcodePortionKind.wholePack, kcal100: 52),
  '8906080600180': Expect('Paper Boat Apple 150 ml', 150, unit: 'ml', kind: BarcodePortionKind.wholePack, kcal100: 55.2),
  '8901262151863': Expect('Amul Fresh Cream 250 ml', 250, unit: 'ml', kind: BarcodePortionKind.wholePack, kcal100: 247),
  // Protein / nutrition bars
  '8906009532998': Expect('RiteBite Nutrition Bar 40 g', 40, kind: BarcodePortionKind.wholePack, kcal100: 204),
  // Its crowd figures disagree with themselves (179 kcal vs ~232 from the
  // macros), so it goes to "read the label" rather than logging a wrong number.
  '8906009532172': Expect('RiteBite Max Protein 50 g, contradictory figures', null, net: 50),
  // Big packs
  '8901725016838': Expect('Aashirvaad Atta 1 kg', 60, kind: BarcodePortionKind.serving, kcal100: 338, net: 1000),
  '8901725121723': Expect('Aashirvaad Atta 5 kg', 60, kind: BarcodePortionKind.serving, kcal100: 338, net: 5000),
  '0690225101103': Expect('India Gate Basmati 1.5 kg', 100, kcal100: 344, net: 1500),
  '8901262180146': Expect('Amul Malai Paneer 1 kg', 50, kind: BarcodePortionKind.serving, kcal100: 312),
  // Paneer, curd, butter
  '8904083300021': Expect('Milky Mist Paneer 200 g', 200, kind: BarcodePortionKind.wholePack, kcal100: 283),
  '8901262200011': Expect('Amul Masti Dahi 85 g', 85, kind: BarcodePortionKind.wholePack, kcal100: 55),
  '8901648097983': Expect('Mother Dairy Dahi 400 g', 100, kind: BarcodePortionKind.serving, kcal100: 75),
  // ≤ 250 g, so the rule says whole pack; the 10 g serving is one tap away.
  // Butter is eaten a spoonful at a time: the label's 10 g serving, not the 200 g block.
  '8901262010320': Expect('Amul Butter 200 gm', 10, kind: BarcodePortionKind.serving, kcal100: 724),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fixture = jsonDecode(
    File('test/fixtures/off_india_products.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final products = (fixture['products'] as Map).cast<String, dynamic>();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BarcodeFoodService.instance.client = MockClient((req) async {
      final code = RegExp(r'/product/(\d+)\.json').firstMatch(req.url.path)!.group(1)!;
      final body = products[code];
      return body == null
          ? http.Response(jsonEncode({'status': 0}), 404)
          : http.Response(jsonEncode(body), 200);
    });
  });

  tearDown(() => BarcodeFoodService.instance.client = null);

  test('the fixture covers every expectation and at least 15 Indian products', () {
    expect(products.keys.toSet(), expectations.keys.toSet());
    expect(products.keys.where((c) => c.startsWith('890')).length, greaterThanOrEqualTo(15));
  });

  for (final e in expectations.entries) {
    test('${e.key} ${e.value.name}', () async {
      final res = await BarcodeFoodService.instance.lookup(e.key);
      final x = e.value;

      if (x.defaultAmount == null) {
        expect(res.isFound, isFalse);
        expect(res.status, BarcodeLookupStatus.notFound);
        // What OFF does know pre-fills the fallback forms.
        expect(res.partial, isNotNull);
        expect(res.partial!.name, isNotEmpty);
        if (x.net != null) expect(res.partial!.netQuantity, x.net);
        return;
      }

      expect(res.isFound, isTrue, reason: 'should be usable');
      final p = res.product!;
      expect(p.unit, x.unit);
      expect(p.defaultAmount.grams, x.defaultAmount);
      if (x.kind != null) expect(p.defaultAmount.kind, x.kind);
      if (x.kcal100 != null) expect(p.per100g.calories, closeTo(x.kcal100!, 0.6));
      if (x.net != null) expect(p.netQuantity, x.net);

      // Whatever the default, the logged result records that exact amount
      // and scales the label figures linearly.
      final r = p.resultForAmount(p.defaultAmount.grams);
      expect(r.items.single.quantity, x.defaultAmount);
      expect(r.items.single.unit, x.unit);
      expect(r.calories.mid,
          closeTo(p.per100g.calories * x.defaultAmount! / 100, 0.1));
    });
  }
}
