import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/services/mock_estimation_service.dart' show NutrientRange;

/// The meal quality score is a pure function of the logged numbers and the
/// meal's words, so the same meal always gets the same score. These pin the
/// keyword bugs (substring matches) and the copy rules.
int score(double cal, double pro, String text, {double? fiber}) =>
    NutritionResult.calculateLocalQualityScore(cal, pro, text, fiber: fiber);

void main() {
  group('keywords match whole words, not pieces of words', () {
    test('chocolate is a sweet, not a cola as well', () {
      // Sugar penalty only (55 - 15), not sugar + soda (55 - 30).
      expect(score(200, 3, 'dark chocolate'), 40);
    });

    test('sweet potato and sweet corn are not sweets', () {
      expect(score(130, 2.5, 'sweet potato', fiber: 4),
          greaterThanOrEqualTo(score(130, 2.5, 'boiled potato', fiber: 4)));
      expect(score(130, 4, 'sweet corn'), greaterThanOrEqualTo(55));
    });

    test('sugar free, no sugar and unsweetened are not penalised', () {
      expect(score(80, 6, 'black coffee no sugar'), score(80, 6, 'black coffee'));
      expect(score(150, 8, 'sugar free lassi'), score(150, 8, 'lassi'));
      expect(score(60, 2, 'unsweetened almond milk'), score(60, 2, 'almond milk'));
    });

    test('diet and zero sodas carry no sugar penalty', () {
      expect(score(1, 0, 'diet coke'), score(1, 0, 'water'));
      expect(score(1, 0, 'coke zero'), score(1, 0, 'water'));
    });

    test('air fried and stir fried are not deep fried', () {
      expect(score(300, 25, 'air fried chicken'), score(300, 25, 'grilled chicken'));
      expect(score(300, 20, 'stir fried tofu with veggies', fiber: 4),
          score(300, 20, 'tofu with veggies', fiber: 4));
      // Deep fried still counts.
      expect(score(300, 25, 'fried chicken'), lessThan(score(300, 25, 'grilled chicken')));
    });

    test('pancake and rice cake are not cake; cupcake still is a sweet', () {
      expect(score(200, 6, 'oats pancake'), greaterThanOrEqualTo(55));
      expect(score(35, 0.7, 'rice cake'), 55);
      expect(score(250, 3, 'cupcake'), lessThan(55));
    });

    test('a "veg" pizza or burger gets no vegetable bonus', () {
      expect(score(800, 20, 'veg pizza'), score(800, 20, 'pizza'));
      expect(score(450, 12, 'veg burger'), score(450, 12, 'burger'));
      // Real vegetables still do.
      expect(score(150, 4, 'mix veg sabzi'), greaterThan(55));
    });

    test('eggplant is not egg', () {
      expect(score(120, 2, 'eggplant curry'), score(120, 2, 'brinjal curry'));
    });
  });

  group('Indian foods', () {
    test('samosa, pakora, kachori, puri and bhature count as fried', () {
      for (final food in ['2 samosa', 'onion pakora', 'kachori', '4 puri', 'chole bhature', 'vada pav']) {
        expect(score(400, 8, food), lessThanOrEqualTo(40), reason: food);
      }
    });

    test('mithai counts as a sweet', () {
      for (final food in ['2 gulab jamun', 'jalebi', 'besan ladoo', 'kaju katli', 'gajar halwa', 'rasgulla', 'kheer']) {
        expect(score(300, 5, food), lessThanOrEqualTo(40), reason: food);
      }
    });

    test('soya, curd and mutton count as protein foods', () {
      expect(score(200, 10, 'soya chunks curry'), greaterThan(score(200, 10, 'aloo curry')));
      expect(score(150, 8, 'curd'), greaterThan(score(150, 8, 'rice')));
      expect(score(400, 30, 'mutton curry'), greaterThan(score(400, 30, 'aloo curry')));
    });

    test('a balanced home thali scores well, a fried snack plate does not', () {
      final thali = score(650, 22, '3 roti, dal, bhindi sabzi, rice, salad', fiber: 9);
      final snack = score(650, 10, '2 samosa with chutney and a coke');
      expect(thali, greaterThanOrEqualTo(75));
      expect(snack, lessThanOrEqualTo(30));
    });
  });

  group('score shape', () {
    test('stays within 20 to 100', () {
      expect(score(2000, 5, 'pizza burger fries coke cake'), 20);
      expect(score(300, 60, 'grilled chicken salad with spinach and whey', fiber: 12), 100);
    });

    test('same meal, same numbers, same score every time', () {
      final a = score(520, 32, 'Paneer bhurji with 2 roti', fiber: 5);
      final b = score(520, 32, 'Paneer bhurji with 2 roti', fiber: 5);
      expect(a, b);
    });
  });

  group('copy', () {
    final texts = <String>[];
    for (final s in [20, 35, 49, 50, 59, 60, 70, 79, 80, 89, 90, 100]) {
      for (final meal in ['pizza', 'samosa', 'dal rice', 'chicken salad', 'gulab jamun', 'water', 'maggi', 'mango pickle', '']) {
        texts
          ..add(NutritionResult.getLocalQualityExplanation(s, meal))
          ..add(NutritionResult.getLocalQualityPositive(s, meal))
          ..add(NutritionResult.getLocalQualityImprovement(s, meal));
      }
    }

    test('no exclamation marks, emoji, em or en dashes', () {
      for (final t in texts) {
        expect(t.contains('!'), isFalse, reason: t);
        expect(t.contains('—') || t.contains('–'), isFalse, reason: t);
        expect(RegExp(r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]', unicode: true).hasMatch(t), isFalse, reason: t);
      }
    });

    test('no guilt or diet-shaming words (teens read these too)', () {
      final banned = RegExp(r'\b(bad|junk|unhealthy|guilt|cheat|failed|processed ingredients|poor)\b', caseSensitive: false);
      for (final t in texts) {
        expect(banned.hasMatch(t), isFalse, reason: t);
      }
    });

    test('the explanation follows the same three bands as the score colour', () {
      // Day detail colours: 80+ good, 60 to 79 neutral, under 60 needs a nudge.
      expect(NutritionResult.getLocalQualityExplanation(80, 'x'),
          NutritionResult.getLocalQualityExplanation(89, 'x'));
      expect(NutritionResult.getLocalQualityExplanation(60, 'x'),
          NutritionResult.getLocalQualityExplanation(79, 'x'));
      expect(NutritionResult.getLocalQualityExplanation(79, 'x'),
          isNot(NutritionResult.getLocalQualityExplanation(80, 'x')));
      expect(NutritionResult.getLocalQualityExplanation(59, 'dal'),
          isNot(NutritionResult.getLocalQualityExplanation(60, 'dal')));
    });

    test('a protein-rich meal is never told to add protein', () {
      expect(NutritionResult.getLocalQualityImprovement(85, 'soya chunks curry').toLowerCase(),
          isNot(contains('protein')));
      expect(NutritionResult.getLocalQualityImprovement(85, 'curd and fruit').toLowerCase(),
          isNot(contains('protein')));
    });
  });

  group('stored results', () {
    test('a score saved as a double still loads', () {
      final r = NutritionResult.createCustom(canonicalMeal: 'dal rice', calories: 400, protein: 12, source: 'quick_add');
      final j = r.toJson()..['mealQualityScore'] = 72.0;
      expect(NutritionResult.fromJson(j).mealQualityScore, 72);
    });

    test('old built-in copy is replaced by the current copy on load', () {
      final r = NutritionResult.createCustom(canonicalMeal: 'grilled chicken', calories: 300, protein: 40, source: 'quick_add');
      final j = r.toJson()
        ..['mealQualityExplanation'] = 'Exceptional choice! Highly nutritious, protein-dense, and rich in whole foods.';
      final loaded = NutritionResult.fromJson(j);
      expect(loaded.mealQualityExplanation, isNot(contains('!')));
      expect(loaded.mealQualityExplanation,
          NutritionResult.getLocalQualityExplanation(loaded.mealQualityScore!, 'grilled chicken'));
    });

    test('a person-written or AI explanation that is not old copy is kept', () {
      final r = NutritionResult.createCustom(canonicalMeal: 'dal rice', calories: 400, protein: 12, source: 'quick_add');
      final j = r.toJson()..['mealQualityExplanation'] = 'Solid fuel.';
      expect(NutritionResult.fromJson(j).mealQualityExplanation, 'Solid fuel.');
    });
  });

  test('a home thali with one sweet on the side is decent, not a junk score', () {
    // Read from a real photo: rice, roti, sambar, rasam, dal fry, pickle and
    // one gulab jamun. The sweet counts once; dal and sambar count for it.
    const text = '250 g white rice, 1 chapati, 120 g sambar, 100 g rasam, 100 g dal fry, 20 g mango pickle, 1 gulab jamun';
    final s = NutritionResult.calculateLocalQualityScore(854, 20, text, fat: 23, fiber: 12);
    expect(s, inInclusiveRange(60, 79));
  });

  group('salt, fat and sugar', () {
    MealQuality q(double cal, double pro, String text,
            {double? fat, double? fiber, double? sugar, double? sat, double? sodium}) =>
        NutritionResult.assessQuality(cal, pro, text,
            fat: fat, fiber: fiber, sugar: sugar, saturatedFat: sat, sodium: sodium);

    test('salty foods named in the meal get a gentle nudge', () {
      expect(score(310, 7, 'maggi'), score(310, 7, 'poha') - 5);
      expect(score(60, 1, 'mango pickle'), score(60, 1, 'mango') - 5);
      expect(score(40, 2, '2 papad'), score(40, 2, '2 khakhra') - 5);
      // Chips are fried and salty: both, but each once.
      expect(score(160, 2, 'chips'), 55 - 20 - 5);
      // Unsalted is not salted.
      expect(score(170, 7, 'unsalted peanuts'), score(170, 7, 'peanuts'));
    });

    test('sodium in the numbers: half the day is a nudge, most of it a firmer one', () {
      expect(q(500, 20, 'veg biryani', sodium: 900).score, q(500, 20, 'veg biryani').score);
      expect(q(500, 20, 'veg biryani', sodium: 1000).score, q(500, 20, 'veg biryani').score - 5);
      expect(q(500, 20, 'veg biryani', sodium: 1800).score, q(500, 20, 'veg biryani').score - 10);
    });

    test('salt counts once when the words and the numbers both say so', () {
      expect(q(310, 7, 'maggi', sodium: 1100).score, score(310, 7, 'maggi'));
      expect(q(620, 14, '2 maggi', sodium: 2200).score, q(620, 14, '2 poha').score - 10);
    });

    test('fat from the numbers nudges a plate that is mostly fat with little protein', () {
      // Cream pasta: 63% of calories from fat, 10% from protein.
      expect(q(600, 15, 'white sauce pasta', fat: 42).score, q(600, 15, 'white sauce pasta').score - 10);
      // Plenty of protein: no nudge on fat alone.
      expect(q(300, 20, 'paneer bhurji', fat: 21).score, q(300, 20, 'paneer bhurji').score);
      // Nuts and seeds are never nudged on fat.
      expect(q(170, 6, 'almonds', fat: 15).score, q(170, 6, 'almonds').score);
      // A pakora's fat is already counted as fried; the numbers add nothing.
      expect(q(400, 8, 'onion pakora', fat: 30).score, score(400, 8, 'onion pakora'));
    });

    test('saturated fat, when known, takes the place of total fat', () {
      final base = q(400, 12, 'malai kofta').score;
      expect(q(400, 12, 'malai kofta', sat: 4).score, base);
      expect(q(400, 12, 'malai kofta', sat: 5).score, base - 5);
      expect(q(400, 12, 'malai kofta', sat: 8).score, base - 10);
    });

    test('added sugar: a cup of chai stays clear, a cola does not', () {
      expect(q(80, 3, 'masala chai', sugar: 9).score, q(80, 3, 'masala chai').score);
      expect(q(140, 0, 'cold coffee', sugar: 35).score, q(140, 0, 'cold coffee').score - 15);
      expect(q(200, 5, 'flavoured yogurt drink', sugar: 16).score, q(200, 5, 'flavoured yogurt drink').score - 8);
      // Jalebi is already a sweet; its sugar number adds nothing.
      expect(q(300, 3, 'jalebi', sugar: 40).score, score(300, 3, 'jalebi'));
    });

    test('three concerns together still land on the floor, not below it', () {
      expect(q(900, 10, 'cheese burger with fries, coke and mango pickle', sugar: 40, sodium: 2400).score, 20);
    });

    test('the lines name the biggest concern', () {
      final salty = q(500, 20, 'veg biryani', sodium: 1300);
      expect(salty.improvement, contains('1,300 mg sodium'));
      expect(q(310, 7, 'maggi').improvement, contains('salt'));
      expect(q(600, 15, 'white sauce pasta', fat: 42).improvement, contains('cream, butter and oil'));
      expect(q(140, 0, 'cold coffee', sugar: 35).improvement, contains('unsweetened'));
      // Fried still wins over salty for chips.
      expect(q(160, 2, 'chips').improvement, contains('air fried'));
      final low = q(310, 4, 'maggi', sodium: 1900);
      expect(low.score, lessThan(60));
      expect(low.explanation, contains('salty'));
    });

    test('the score from assessQuality is the score everywhere', () {
      final a = q(450, 18, 'rajma chawal with pickle', fat: 12, fiber: 9, sodium: 1200);
      expect(
        a.score,
        NutritionResult.calculateLocalQualityScore(450, 18, 'rajma chawal with pickle',
            fat: 12, fiber: 9, sodium: 1200),
      );
    });

    test('item nutrients: a floor, sodium from the library first, fruit sugar left out', () {
      NutritionItem item(String name, {double? sugar, double? sodium, double? microNa, double? sat}) =>
          NutritionItem(
            name: name,
            quantity: 1,
            unit: 'serving',
            estimated: true,
            mode: EstimationMode.contextualIntake,
            calories: const NutrientRange(min: 100, max: 100),
            protein: const NutrientRange(min: 3, max: 3),
            sugar: sugar == null ? null : NutrientRange(min: sugar, max: sugar),
            sodium: sodium == null ? null : NutrientRange(min: sodium, max: sodium),
            saturatedFat: sat == null ? null : NutrientRange(min: sat, max: sat),
            micros: microNa == null ? null : Micronutrients({Micro.sodium: microNa}),
          );
      final n = NutritionResult.qualityNutrients([
        item('banana', sugar: 14),
        item('gulab jamun', sugar: 25),
        item('dal', sodium: 900, microNa: 350),
        item('rice'),
        item('pickle', sodium: 600, sat: 1),
      ]);
      expect(n.sugar, 25);
      expect(n.sodium, 350 + 600);
      expect(n.saturatedFat, 1);
      final none = NutritionResult.qualityNutrients([item('rice')]);
      expect(none.sugar, isNull);
      expect(none.sodium, isNull);
      expect(none.saturatedFat, isNull);
    });
  });

  group('protein tip follows the numbers', () {
    test('a protein-rich plate with no protein word is not told to add protein', () {
      // Real log: 2 aloo parathas, 460 kcal, 33 g protein (29% of calories).
      final q = NutritionResult.assessQuality(460, 33, '2 milld aloo parantha', fat: 11, fiber: 4);
      expect(q.improvement.toLowerCase(), isNot(contains('protein')));
      expect(q.improvement, contains('sabzi'));
    });

    test('a plate short on protein still gets the protein tip', () {
      final q = NutritionResult.assessQuality(400, 8, 'aloo paratha', fat: 14);
      expect(q.improvement, startsWith('Add some protein'));
    });

    test('a saved meal rebuilds a built-in tip from its numbers, keeps a written one', () {
      final r = NutritionResult.createCustom(
          canonicalMeal: '2 milld aloo parantha', calories: 460, protein: 33, fat: 11, source: 'quick_add');
      final j = r.toJson()
        ..['mealQualityScore'] = 75
        ..['mealQualityImprovement'] = 'Add some protein: dal, curd, paneer, eggs or chicken.';
      expect(NutritionResult.fromJson(j).mealQualityImprovement!.toLowerCase(), isNot(contains('protein')));
      final written = r.toJson()
        ..['mealQualityScore'] = 75
        ..['mealQualityImprovement'] = 'Try it with curd next time.';
      expect(NutritionResult.fromJson(written).mealQualityImprovement, 'Try it with curd next time.');
    });
  });
}
