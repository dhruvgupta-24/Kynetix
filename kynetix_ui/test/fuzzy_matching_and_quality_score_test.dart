import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/services/item_parser.dart';
import 'package:kynetix/services/nutrition_pipeline.dart';
import 'package:kynetix/services/meal_memory.dart';
import 'package:kynetix/services/user_nutrition_memory.dart';
import 'package:kynetix/services/personal_nutrition_memory.dart';
import 'package:kynetix/services/nutrition_hydration_guard.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://mock.supabase.co',
      anonKey: 'mock-anon-key',
    );
    // Enable hydration guards so memory looks up correctly
    NutritionHydrationGuard.instance.currentUserIdOverride = 'user-1234';
    NutritionHydrationGuard.instance.markComplete('user-1234');
    await UserNutritionMemory.instance.init();
    await PersonalNutritionMemory.instance.init();
    await MealMemory.instance.init();
  });

  group('Fuzzy spelling corrections', () {
    setUp(() async {
      // Register custom food to test custom food protection
      await UserNutritionMemory.instance.saveOverride(
        'customfoodxyz',
        100.0,
        20.0,
      );
      // Register a very long food name to test >95% high confidence auto-correct
      await UserNutritionMemory.instance.saveOverride(
        'supercalifragilisticexpialidocious',
        200.0,
        15.0,
      );
    });

    test('Medium confidence suggestions (80% - 95%)', () {
      final srouts = ItemParser.getSpellingSuggestion('srouts');
      expect(srouts, isNotNull);
      expect(srouts!.suggested, equals('sprouts'));
      expect(srouts.confidence, inInclusiveRange(0.80, 0.95));

      final bannana = ItemParser.getSpellingSuggestion('bannana');
      expect(bannana, isNotNull);
      expect(bannana!.suggested, equals('banana'));
      expect(bannana.confidence, inInclusiveRange(0.80, 0.95));

      final panner = ItemParser.getSpellingSuggestion('panner');
      expect(panner, isNotNull);
      expect(panner!.suggested, equals('paneer'));
      expect(panner.confidence, inInclusiveRange(0.80, 0.95));

      final oatz = ItemParser.getSpellingSuggestion('oatz');
      expect(oatz, isNotNull);
      expect(oatz!.suggested, equals('oats'));
      // short-word rule match (maxLen <= 4, dist <= 1)
      expect(oatz.confidence, inInclusiveRange(0.80, 0.95));
    });

    test('Medium confidence are NOT silently auto-corrected', () {
      expect(ItemParser.correctSpelling('srouts'), equals('srouts'));
      expect(ItemParser.correctSpelling('bannana'), equals('bannana'));
      expect(ItemParser.correctSpelling('panner'), equals('panner'));
      expect(ItemParser.correctSpelling('oatz'), equals('oatz'));
    });

    test('Protected brands and custom foods suggestions are blocked', () {
      // goatlife (protected brand)
      final goatlifeTypo = ItemParser.getSpellingSuggestion('goatlif');
      expect(goatlifeTypo, isNull);

      // troovy (protected brand)
      final troovyTypo = ItemParser.getSpellingSuggestion('troov');
      expect(troovyTypo, isNull);

      // myprotein (protected brand)
      final myproteinTypo = ItemParser.getSpellingSuggestion('myprotei');
      expect(myproteinTypo, isNull);

      // customfoodxyz (user custom food)
      final customfoodTypo = ItemParser.getSpellingSuggestion('customfoodxy');
      expect(customfoodTypo, isNull);
    });

    test('High confidence (>95%) are silently auto-corrected', () {
      final input = 'supercalifragilisticexpialidociou'; // length 33, dist 1
      expect(ItemParser.correctSpelling(input), equals('supercalifragilisticexpialidocious'));
    });

    test('Multi-word spelling suggestions', () {
      final peenut = ItemParser.getSpellingSuggestion('peenut butter');
      expect(peenut, isNotNull);
      expect(peenut!.suggested, equals('peanut butter'));

      final protien = ItemParser.getSpellingSuggestion('protien shake');
      expect(protien, isNotNull);
      expect(protien!.suggested, equals('protein shake'));

      final chickn = ItemParser.getSpellingSuggestion('chickn breast');
      expect(chickn, isNotNull);
      expect(chickn!.suggested, equals('chicken breast'));
    });

    test('Custom food protection: user-created foods never replaced', () async {
      await UserNutritionMemory.instance.saveOverride('massgainerx', 800, 50);
      
      // Since it is in UserNutritionMemory, it is protected and must not suggest replacing it
      final massgainer = ItemParser.getSpellingSuggestion('massgainerx');
      expect(massgainer, isNull);
    });

    test('Ranking priority tie-breaker (User > Saved > Template > Database)', () async {
      // Create saved food "browniex" (Priority 2)
      final dummyResult = NutritionResult(
        canonicalMeal: 'browniex',
        items: const [],
        calories: const NutrientRange(min: 180, max: 180),
        protein: const NutrientRange(min: 2, max: 2),
        confidence: 0.98,
        warnings: const [],
        source: 'test_stub',
        createdAt: DateTime.now(),
      );
      await MealMemory.instance.store('1 serving browniex', dummyResult);

      // Now query "browniez" which is distance 1 from both "browniex" (Saved food, Priority 2) 
      // and "brownie" (built-in template, Priority 3)
      final sug = ItemParser.getSpellingSuggestion('browniez');
      expect(sug, isNotNull);
      // Priority 2 (browniex) wins over Priority 3 (brownie)
      expect(sug!.suggested, equals('browniex'));
    });

    test('Negative corrections (standard/correct foods stay unchanged)', () {
      expect(ItemParser.correctSpelling('rice'), equals('rice'));
      expect(ItemParser.correctSpelling('milk'), equals('milk'));
      expect(ItemParser.correctSpelling('bread'), equals('bread'));
      expect(ItemParser.correctSpelling('chips'), equals('chips'));
      expect(ItemParser.correctSpelling('goatlife'), equals('goatlife'));
      expect(ItemParser.correctSpelling('troovy'), equals('troovy'));
      expect(ItemParser.correctSpelling('myprotein'), equals('myprotein'));
      expect(ItemParser.correctSpelling('customfoodxyz'), equals('customfoodxyz'));
    });
  });

  group('Food Quality Score calculations', () {
    test('Dynamic calculation of quality scores for chips/snack items', () async {
      final pipeline = NutritionPipeline.instance;
      final result = await pipeline.estimateMeal('chips');
      
      expect(result.mealQualityScore, isNotNull);
      expect(result.mealQualityScore, greaterThan(0));
      expect(result.mealQualityExplanation, isNotNull);
      expect(result.mealQualityPositive, isNotNull);
      expect(result.mealQualityImprovement, isNotNull);
    });

    test('Quality score is set for items returned from memory defaults', () {
      // MealMemory default known foods (like whey/tofu)
      final wheyResult = MealMemory.instance.lookupExactKnownFood('1 scoop whey');
      expect(wheyResult, isNotNull);
      expect(wheyResult!.mealQualityScore, isNotNull);
      expect(wheyResult.mealQualityScore, greaterThan(0));

      final tofuResult = MealMemory.instance.lookupExactKnownFood('150 g tofu');
      expect(tofuResult, isNotNull);
      expect(tofuResult!.mealQualityScore, isNotNull);
      expect(tofuResult.mealQualityScore, greaterThan(0));
    });

    test('Quality score is set for items returned from PersonalNutritionMemory templates', () {
      final result = PersonalNutritionMemory.instance.lookupExact('1 scoop whey');
      expect(result, isNotNull);
      expect(result!.mealQualityScore, isNotNull);
      expect(result.mealQualityScore, greaterThan(0));
    });
  });
}
