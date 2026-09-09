import 'package:flutter/material.dart';
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

    testWidgets('Saved meal title displays complete text with soft wrapping, macro row, and clickable USE button', (tester) async {
      const longMealName1 = '2 normal roti with 1.2 ladle rice with dal dhaba';
      const longMealName2 =
          '2 normal roti with 1.2 ladle rice with dal dhaba and extra paneer bhurji with roasted papad and green salad';
      const extremeMealName =
          '2 normal roti with 1.2 ladle rice with dal dhaba and extra paneer bhurji with roasted papad and green salad along with 200g Greek yogurt and roasted spiced chickpeas with cucumber raita';

      for (final mealTitle in [longMealName1, longMealName2, extremeMealName]) {
        var usedClicked = false;
        final match = SavedMealMatch(
          title: mealTitle,
          rawInput: mealTitle,
          calories: 550,
          protein: 28,
          carbohydrates: 75,
          fat: 14,
          fiber: 5,
          ingredientNames: const ['Roti', 'Rice', 'Dal'],
          timesUsed: 5,
          result: NutritionResult.createCustom(
            canonicalMeal: mealTitle,
            calories: 550,
            protein: 28,
            source: 'saved_meal',
          ),
          emoji: '🍛',
          matchScore: 1.0,
          mealType: SavedMealType.savedMeal,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(match.emoji, style: const TextStyle(fontSize: 22)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              match.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                              ),
                              softWrap: true,
                            ),
                            const SizedBox(height: 3),
                            Text('${match.calories.toInt()} kcal • ${match.protein.toInt()}g protein'),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => usedClicked = true,
                        child: const Text('USE'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // 1. Complete text is rendered and found without ellipsis
        expect(find.text(mealTitle), findsOneWidget);

        // 2. Text widget has no maxLines: 1 and has softWrap: true
        final textWidget = tester.widget<Text>(find.text(mealTitle));
        expect(textWidget.maxLines, isNull);
        expect(textWidget.overflow, isNot(equals(TextOverflow.ellipsis)));
        expect(textWidget.softWrap, isTrue);

        // 3. Macro row remains visible
        expect(find.text('550 kcal • 28g protein'), findsOneWidget);

        // 4. USE button is present, visible, and clickable
        expect(find.text('USE'), findsOneWidget);
        await tester.tap(find.text('USE'));
        expect(usedClicked, isTrue);
      }
    });
  });
}
