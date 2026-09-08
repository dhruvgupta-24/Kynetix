import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/services/saved_meal_service.dart';

void main() {
  setUp(() {
    dayLogStore.clear();
  });

  group('SavedMealService Tests', () {
    test('Token normalization and tokenization work properly', () {
      expect(SavedMealService.normalize('  Yogabar: Cold-Coffee (Protein Shake)! '),
          equals('yogabar cold coffee protein shake'));

      final tokens = SavedMealService.tokenize('Yogabar Cold Coffee Protein Shake');
      expect(tokens, containsAll(['yogabar', 'cold', 'coffee', 'protein', 'shake']));
    });

    test('Searches and matches meals across partial tokens and word orders', () {
      final dummyResult = NutritionResult.createCustom(
        canonicalMeal: 'Yogabar Cold Coffee Protein Shake',
        calories: 207,
        protein: 26,
        source: 'user_override',
      );

      final entry = MealEntry(
        rawInput: 'Yogabar Cold Coffee Protein Shake',
        result: dummyResult,
        addedAt: DateTime.now(),
        section: MealSection.breakfast,
        dayOfWeek: 1,
        parsedFoods: const ['Yogabar Cold Coffee'],
        finalSavedInput: 'Yogabar Cold Coffee Protein Shake',
      );

      final log = logFor(DateTime.now());
      log.add(MealSection.breakfast, entry);

      // Search "cold coffee"
      final results1 = SavedMealService.instance.search('cold coffee');
      expect(results1.isNotEmpty, isTrue);
      expect(results1.first.title, contains('Cold Coffee'));
      expect(results1.first.calories, closeTo(207, 1));
      expect(results1.first.protein, closeTo(26, 1));
      expect(results1.first.emoji, equals('🥤'));

      // Search "protein shake"
      final results2 = SavedMealService.instance.search('protein shake');
      expect(results2.isNotEmpty, isTrue);
      expect(results2.first.title, contains('Cold Coffee'));

      // Search "yogabar"
      final results3 = SavedMealService.instance.search('yogabar');
      expect(results3.isNotEmpty, isTrue);
      expect(results3.first.title, contains('Yogabar'));
    });

    test('SavedMealType classification and exact macro preservation', () {
      final custom = NutritionResult.createCustom(
        canonicalMeal: 'Whey Isolate Shake',
        calories: 140,
        protein: 30,
        source: 'user_override',
      );

      final entry = MealEntry(
        rawInput: 'Whey Isolate Shake',
        result: custom,
        addedAt: DateTime.now(),
        section: MealSection.eveningSnack,
        dayOfWeek: 1,
        parsedFoods: const ['Whey Protein'],
        finalSavedInput: 'Whey Isolate Shake',
      );

      final log = logFor(DateTime.now());
      log.add(MealSection.eveningSnack, entry);

      final matches = SavedMealService.instance.search('whey');
      expect(matches, isNotEmpty);

      final item = matches.first;
      expect(item.title, equals('Whey Isolate Shake'));
      expect(item.protein, equals(30.0));
      expect(item.calories, equals(140.0));

      // Test conversion back to NutritionResult without AI regeneration
      final restored = item.toNutritionResult();
      expect(restored.canonicalMeal, equals('Whey Isolate Shake'));
      expect(restored.calories.mid, equals(140.0));
      expect(restored.protein.mid, equals(30.0));
      expect(restored.source, equals('user_override'));
    });
  });
}
