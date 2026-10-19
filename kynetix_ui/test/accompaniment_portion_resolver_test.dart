import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/data/indian_curry_table.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/models/user_profile.dart' show PortionAnchor;
import 'package:kynetix/services/accompaniment_portion_resolver.dart';
import 'package:kynetix/services/mock_estimation_service.dart' show NutrientRange;

NutritionItem _item(String name, double qty, String unit, {double kcal = 0}) => NutritionItem(
      name: name,
      quantity: qty,
      unit: unit,
      estimated: true,
      mode: EstimationMode.contextualIntake,
      calories: NutrientRange(min: kcal, max: kcal),
      protein: const NutrientRange(min: 0, max: 0),
    );

NutritionItem _curry(List<NutritionItem> items, PortionAnchor anchor, {String name = 'white chane'}) =>
    AccompanimentPortionResolver.resolve(items, anchor: anchor).firstWhere((i) => i.name == name);

void main() {
  group('IndianCurryTable.match', () {
    test('spellings of white chana resolve to chole', () {
      for (final n in ['white chane', 'safed chana', 'chhole', 'kabuli chana', 'chana masala', 'chane']) {
        expect(IndianCurryTable.match(n)?.name, 'chole', reason: n);
      }
    });

    test('the most specific dish wins', () {
      expect(IndianCurryTable.match('kala chana')?.name, 'kala chana');
      expect(IndianCurryTable.match('chana dal')?.name, 'chana dal');
      expect(IndianCurryTable.match('dal makhani')?.name, 'dal makhani');
      expect(IndianCurryTable.match('bhindi sabzi')?.name, 'bhindi');
      expect(IndianCurryTable.match('palak paneer')?.name, 'palak paneer');
      expect(IndianCurryTable.match('aloo matar paneer')?.name, 'matar paneer');
      expect(IndianCurryTable.match('paneer butter masala')?.name, 'paneer butter masala');
    });

    test('generic sabzi stands alone; a named vegetable is not mix veg', () {
      expect(IndianCurryTable.match('sabzi')?.name, 'mix veg');
      expect(IndianCurryTable.match('mess sabzi')?.name, 'mix veg');
      expect(IndianCurryTable.match('arbi sabzi'), isNull);
      expect(IndianCurryTable.match('bhindi sabzi')?.name, 'bhindi');
      expect(IndianCurryTable.match('aloo gobi sabzi')?.name, 'aloo gobi');
    });

    test('non curries and combo plates do not match', () {
      for (final n in ['roasted chana', 'chana chaat', 'rajma chawal', 'chole bhature', 'banana', 'rice', 'roti']) {
        expect(IndianCurryTable.match(n), isNull, reason: n);
      }
    });

    test('table values add up (4P + 4C + 9F within 12%)', () {
      for (final d in IndianCurryTable.dishes) {
        final implied = 4 * d.protein + 4 * d.carbs + 9 * d.fat;
        expect((implied - d.kcal).abs() / d.kcal, lessThan(0.12), reason: d.name);
      }
    });
  });

  group('AccompanimentPortionResolver', () {
    const carbFirst = PortionAnchor.carbAnchored;

    test('chole grows with every roti and with rice', () {
      final two = _curry([_item('roti', 2, 'serving'), _item('white chane', 1, 'serving')], carbFirst);
      final three = _curry([_item('roti', 3, 'serving'), _item('white chane', 1, 'serving')], carbFirst);
      final threeRice = _curry([
        _item('roti', 3, 'serving'),
        _item('rice', 1, 'ladle'),
        _item('white chane', 1, 'serving'),
      ], carbFirst);

      expect(two.unit, 'g');
      expect(two.quantity, 70); // 2 x 35 g
      expect(three.quantity, 105); // one roti more
      expect(threeRice.quantity, 155); // plus a ladle of rice (50 g)
      expect(three.calories.mid, greaterThan(two.calories.mid));
      expect(threeRice.calories.mid, greaterThan(three.calories.mid));
      // 70 g chole at 150 kcal / 6 g protein per 100 g.
      expect(two.calories.mid, closeTo(105, 0.5));
      expect(two.protein.mid, closeTo(4.2, 0.05));
    });

    test('eater type sets how much curry each roti takes', () {
      double grams(PortionAnchor a) =>
          _curry([_item('roti', 2, 'serving'), _item('white chane', 1, 'serving')], a).quantity;
      expect(grams(PortionAnchor.carbAnchored), 70);
      expect(grams(PortionAnchor.balanced), 100);
      expect(grams(PortionAnchor.curryAnchored), 140);
    });

    test('rice takes more dal than a roti, and less dry sabzi', () {
      final dalRice = _curry([_item('rice', 1, 'ladle'), _item('dal', 1, 'serving')], carbFirst, name: 'dal');
      final dalRoti = _curry([_item('roti', 1, 'serving'), _item('dal', 1, 'serving')], carbFirst, name: 'dal');
      expect(dalRice.quantity, greaterThan(dalRoti.quantity));
      final bhindiRice = _curry([_item('rice', 1, 'ladle'), _item('bhindi', 1, 'serving')], carbFirst, name: 'bhindi');
      final bhindiRoti = _curry([_item('roti', 1, 'serving'), _item('bhindi', 1, 'serving')], carbFirst, name: 'bhindi');
      expect(bhindiRice.quantity, lessThan(bhindiRoti.quantity));
    });

    test('a typed amount always wins', () {
      final out = AccompanimentPortionResolver.resolve([
        _item('roti', 4, 'serving'),
        _item('rajma', 150, 'g'),
        _item('katori dal', 2, 'serving'),
      ], anchor: carbFirst);
      expect(out[1].quantity, 150);
      expect(out[1].calories.mid, closeTo(180, 0.5));
      expect(out[2].unit, 'serving'); // keeps "2 katori"
      expect(out[2].calories.mid, closeTo(2 * 150 * 0.75, 0.5));
    });

    test('two curries share the carbs', () {
      final out = AccompanimentPortionResolver.resolve([
        _item('roti', 3, 'serving'),
        _item('dal', 1, 'serving'),
        _item('aloo gobi', 1, 'serving'),
      ], anchor: PortionAnchor.balanced);
      // Alone: dal 150 g, aloo gobi 135 g. Together each is 0.65 of that.
      expect(out[1].quantity, 100);
      expect(out[2].quantity, 90);
    });

    test('a curry with no carbs is a katori', () {
      final out = AccompanimentPortionResolver.resolve([_item('rajma', 1, 'serving')], anchor: carbFirst);
      expect(out.single.quantity, 150);
    });

    test('pinned items and roti counts are never changed', () {
      final out = AccompanimentPortionResolver.resolve(
        [_item('roti', 2, 'serving', kcal: 200), _item('white chane', 1, 'serving', kcal: 321)],
        anchor: carbFirst,
        pinned: {'white chane'},
      );
      expect(out[0].quantity, 2);
      expect(out[0].calories.mid, 200);
      expect(out[0].eatingPatternScalarApplied, isTrue);
      expect(out[1].calories.mid, 321);
    });

    test('naan and paratha count as bigger breads, plate rice as more rice', () {
      final naan = _curry([_item('butter naan', 2, 'serving'), _item('dal makhani', 1, 'serving')], carbFirst,
          name: 'dal makhani');
      final roti = _curry([_item('roti', 2, 'serving'), _item('dal makhani', 1, 'serving')], carbFirst,
          name: 'dal makhani');
      expect(naan.quantity, greaterThan(roti.quantity));
      final plate = _curry([_item('rice', 1, 'plate'), _item('rajma', 1, 'serving')], carbFirst, name: 'rajma');
      expect(plate.quantity, 125); // 2.5 ladles x 50 g
    });

    test('plain rice is counted by its stated amount', () {
      final out = AccompanimentPortionResolver.resolve([
        _item('rice', 1, 'plate', kcal: 150),
        _item('rice', 2, 'ladle', kcal: 300),
        _item('jeera rice', 1, 'plate', kcal: 400),
      ], anchor: carbFirst);
      expect(out[0].calories.mid, closeTo(325, 0.5));
      expect(out[1].calories.mid, closeTo(260, 0.5));
      expect(out[2].calories.mid, 400); // not plain rice
    });
  });
}
