import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/services/mock_estimation_service.dart' show NutrientRange;
import 'package:kynetix/services/saved_meal_service.dart';
import 'package:kynetix/services/saved_meal_canonicalizer.dart';

NutritionResult _makeDummyResult(String name, double cal, double pro, double carb, double fat) {
  return NutritionResult(
    canonicalMeal: name,
    items: [
      NutritionItem(
        name: name,
        quantity: 1.0,
        unit: 'serving',
        estimated: false,
        mode: EstimationMode.directQuantity,
        calories: NutrientRange(min: cal, max: cal),
        protein: NutrientRange(min: pro, max: pro),
        carbohydrates: NutrientRange(min: carb, max: carb),
        fat: NutrientRange(min: fat, max: fat),
        fiber: const NutrientRange(min: 0, max: 0),
      ),
    ],
    calories: NutrientRange(min: cal, max: cal),
    protein: NutrientRange(min: pro, max: pro),
    carbohydrates: NutrientRange(min: carb, max: carb),
    fat: NutrientRange(min: fat, max: fat),
    fiber: const NutrientRange(min: 0, max: 0),
    confidence: 1.0,
    warnings: const [],
    source: 'test',
    createdAt: DateTime.now(),
  );
}

SavedMealMatch _makeMatch(String title, String rawInput, double cal, double pro, double carb, double fat, {int timesUsed = 1}) {
  return SavedMealMatch(
    title: title,
    rawInput: rawInput,
    calories: cal,
    protein: pro,
    carbohydrates: carb,
    fat: fat,
    fiber: 0.0,
    ingredientNames: [title],
    timesUsed: timesUsed,
    result: _makeDummyResult(title, cal, pro, carb, fat),
    emoji: '🍽️',
    matchScore: 100.0,
    mealType: SavedMealType.savedMeal,
  );
}

void main() {
  group('SavedMealCanonicalizer Tests', () {
    test('1. Quantity-prefixed duplicate resolves to canonical base meal', () {
      final m1 = _makeMatch(
        'beyond snack desi masala chips',
        'beyond snack desi masala chips',
        380.0, 4.3, 48.8, 18.0,
        timesUsed: 5,
      );
      final m2 = _makeMatch(
        '0.8 beyond snack desi masala chips',
        '0.8 beyond snack desi masala chips',
        304.0, 3.4, 39.0, 14.4,
        timesUsed: 1,
      );

      final collapsed = SavedMealCanonicalizer.collapseConservativeDuplicates([m2, m1]);

      expect(collapsed.length, 1, reason: '0.8 variant must collapse into canonical base');
      expect(collapsed.first.title, 'beyond snack desi masala chips');
      expect(collapsed.first.calories, 380.0);
      expect(collapsed.first.protein, 4.3);
    });

    test('2. Multiple quantity variants collapse into single base entry', () {
      final base = _makeMatch('beyond snack desi masala chips', 'beyond snack desi masala chips', 380, 4.3, 48.8, 18, timesUsed: 2);
      final var08 = _makeMatch('0.8 beyond snack desi masala chips', '0.8 beyond snack desi masala chips', 304, 3.4, 39.0, 14.4, timesUsed: 1);
      final var12 = _makeMatch('1.2 beyond snack desi masala chips', '1.2 beyond snack desi masala chips', 456, 5.2, 58.5, 21.6, timesUsed: 1);

      final collapsed = SavedMealCanonicalizer.collapseConservativeDuplicates([var08, base, var12]);

      expect(collapsed.length, 1);
      expect(collapsed.first.title, 'beyond snack desi masala chips');
    });

    test('3. Genuinely different meals with similar names remain separate', () {
      final chickenBreast = _makeMatch('chicken breast', 'chicken breast', 165, 31, 0, 3.6);
      final chickenBiryani = _makeMatch('chicken biryani', 'chicken biryani', 450, 22, 55, 14);

      final collapsed = SavedMealCanonicalizer.collapseConservativeDuplicates([chickenBreast, chickenBiryani]);

      expect(collapsed.length, 2, reason: 'Genuinely different meals must remain separate');
      expect(collapsed.map((m) => m.title), containsAll(['chicken breast', 'chicken biryani']));
    });

    test('4. Exact saved macros are preserved when restored via toNutritionResult()', () {
      final m = _makeMatch(
        'beyond snack desi masala chips',
        'beyond snack desi masala chips',
        380.0, 4.3, 48.8, 18.0,
      );

      final restored = m.toNutritionResult();
      expect(restored.calories.mid, 380.0);
      expect(restored.protein.mid, 4.3);
      expect(restored.carbohydrates?.mid, 48.8);
      expect(restored.fat?.mid, 18.0);
    });

    test('5. Ambiguous meals with incompatible macros are not merged', () {
      // Same name prefix but wildly divergent macros (e.g. user saved completely different food under loose name)
      final egg1 = _makeMatch('eggs', 'eggs', 140, 12, 1, 10);
      final egg2 = _makeMatch('3 eggs', '3 eggs', 900, 70, 50, 40); // macros do not scale with multiplier 3

      final collapsed = SavedMealCanonicalizer.collapseConservativeDuplicates([egg1, egg2]);
      expect(collapsed.length, 2, reason: 'Incompatible macros should cause conservative fallback (no merge)');
    });
  });
}
