import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kynetix/services/food_role_classifier.dart';
import 'package:kynetix/services/eating_pattern_service.dart';
import 'package:kynetix/services/user_nutrition_memory.dart';
import 'package:kynetix/services/item_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://mock.supabase.co',
      anonKey: 'mock-anon-key',
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await UserNutritionMemory.instance.init();
    await EatingPatternService.instance.load();
    EatingPatternService.instance.resetAll();
  });

  group('FoodRoleClassifier tests', () {
    test('Classify basic foods correctly', () {
      expect(FoodRoleClassifier.classify('roti'), FoodRole.primary);
      expect(FoodRoleClassifier.classify('rice'), FoodRole.primary);
      expect(FoodRoleClassifier.classify('chicken'), FoodRole.protein);
      expect(FoodRoleClassifier.classify('paneer'), FoodRole.protein);
      expect(FoodRoleClassifier.classify('dal'), FoodRole.accompaniment);
      expect(FoodRoleClassifier.classify('butter'), FoodRole.addOn);
      expect(FoodRoleClassifier.classify('pizza'), FoodRole.completeMeal);
    });

    test('Classify unknown foods defaults to completeMeal', () {
      expect(FoodRoleClassifier.classify('some random unknown food'), FoodRole.completeMeal);
    });
  });

  group('EatingPatternService tests', () {
    test('Does not return scalar if sample count < 3', () {
      // Let's add 2 records
      EatingPatternService.instance.recordIngredientCorrection(
        correctedItemRole: FoodRole.accompaniment,
        mealHasPrimary: true,
        pipelineCalEstimate: 200.0,
        userCorrectedCal: 100.0, // ratio = 0.5
      );
      EatingPatternService.instance.recordIngredientCorrection(
        correctedItemRole: FoodRole.accompaniment,
        mealHasPrimary: true,
        pipelineCalEstimate: 200.0,
        userCorrectedCal: 100.0, // ratio = 0.5
      );

      final scalar = EatingPatternService.instance.getScalar(
        FoodRole.accompaniment,
        contextRole: FoodRole.primary,
      );
      expect(scalar, isNull);
      expect(EatingPatternService.instance.getSampleCount(FoodRole.accompaniment, contextRole: FoodRole.primary), 2);
    });

    test('Returns recency-weighted scalar if sample count >= 3', () {
      // Let's add 3 records
      EatingPatternService.instance.recordIngredientCorrection(
        correctedItemRole: FoodRole.accompaniment,
        mealHasPrimary: true,
        pipelineCalEstimate: 200.0,
        userCorrectedCal: 100.0, // ratio = 0.5
      );
      EatingPatternService.instance.recordIngredientCorrection(
        correctedItemRole: FoodRole.accompaniment,
        mealHasPrimary: true,
        pipelineCalEstimate: 200.0,
        userCorrectedCal: 100.0, // ratio = 0.5
      );
      EatingPatternService.instance.recordIngredientCorrection(
        correctedItemRole: FoodRole.accompaniment,
        mealHasPrimary: true,
        pipelineCalEstimate: 200.0,
        userCorrectedCal: 100.0, // ratio = 0.5
      );

      final scalar = EatingPatternService.instance.getScalar(
        FoodRole.accompaniment,
        contextRole: FoodRole.primary,
      );
      expect(scalar, isNotNull);
      expect(scalar, closeTo(0.5, 0.01));
      
      final confidence = EatingPatternService.instance.getConfidence(
        FoodRole.accompaniment,
        contextRole: FoodRole.primary,
      );
      expect(confidence, greaterThan(0));
    });

    test('No scalar applied if target role is completeMeal', () {
      EatingPatternService.instance.recordIngredientCorrection(
        correctedItemRole: FoodRole.completeMeal,
        mealHasPrimary: true,
        pipelineCalEstimate: 200.0,
        userCorrectedCal: 100.0,
      );
      EatingPatternService.instance.recordIngredientCorrection(
        correctedItemRole: FoodRole.completeMeal,
        mealHasPrimary: true,
        pipelineCalEstimate: 200.0,
        userCorrectedCal: 100.0,
      );
      EatingPatternService.instance.recordIngredientCorrection(
        correctedItemRole: FoodRole.completeMeal,
        mealHasPrimary: true,
        pipelineCalEstimate: 200.0,
        userCorrectedCal: 100.0,
      );

      final scalar = EatingPatternService.instance.getScalar(
        FoodRole.completeMeal,
        contextRole: FoodRole.primary,
      );
      expect(scalar, isNull);
    });

    test('Wipe and reset works', () {
      EatingPatternService.instance.recordIngredientCorrection(
        correctedItemRole: FoodRole.accompaniment,
        mealHasPrimary: true,
        pipelineCalEstimate: 200.0,
        userCorrectedCal: 100.0,
      );
      EatingPatternService.instance.resetAll();
      expect(EatingPatternService.instance.getSampleCount(FoodRole.accompaniment, contextRole: FoodRole.primary), 0);
    });
  });

  group('UserNutritionMemory tests', () {
    test('Save and lookup overrides with source', () async {
      await UserNutritionMemory.instance.saveOverride(
        'Special Bread',
        2.5, // 2.5 kcal per gram
        0.1, // 0.1g protein per gram
        carbohydratesPerUnit: 0.5,
        fatPerUnit: 0.02,
        fiberPerUnit: 0.03,
        referenceQuantity: 10.0,
        referenceUnit: 'g',
      );

      final (result, source) = UserNutritionMemory.instance.lookupWithSource('Special Bread');
      expect(result, isNotNull);
      expect(source, OverrideSource.userCorrected);

    });
  });

  group('ItemParser tests', () {
    test('Splits composite meals correctly into atomic ingredients', () {
      final breadPeanut = ItemParser.parse("4 bread slices with 40g peanut butter");
      expect(breadPeanut.length, 2);
      expect(breadPeanut[0].normalizedName, "bread");
      expect(breadPeanut[0].quantity, 4.0);
      expect(breadPeanut[0].unit, "slices");
      expect(breadPeanut[1].normalizedName, "peanut butter");
      expect(breadPeanut[1].quantity, 40.0);
      expect(breadPeanut[1].unit, "g");

      final rotiChanna = ItemParser.parse("2 roti + channa");
      expect(rotiChanna.length, 2);
      expect(rotiChanna[0].normalizedName, "roti");
      expect(rotiChanna[1].normalizedName, "channa");

      final riceDal = ItemParser.parse("rice + dal");
      expect(riceDal.length, 2);
      expect(riceDal[0].normalizedName, "rice");
      expect(riceDal[1].normalizedName, "dal");

      final rajmaChawal = ItemParser.parse("rajma chawal");
      expect(rajmaChawal.length, 2);
      expect(rajmaChawal[0].normalizedName, "rajma");
      expect(rajmaChawal[1].normalizedName, "chawal");

      final oatsMilk = ItemParser.parse("oats + milk");
      expect(oatsMilk.length, 2);
      expect(oatsMilk[0].normalizedName, "oats");
      expect(oatsMilk[1].normalizedName, "milk");

      final chickenRice = ItemParser.parse("chicken + rice");
      expect(chickenRice.length, 2);
      expect(chickenRice[0].normalizedName, "chicken");
      expect(chickenRice[1].normalizedName, "rice");

      final paneerRoti = ItemParser.parse("paneer + roti");
      expect(paneerRoti.length, 2);
      expect(paneerRoti[0].normalizedName, "paneer");
      expect(paneerRoti[1].normalizedName, "roti");

      final pastaSauce = ItemParser.parse("pasta + sauce");
      expect(pastaSauce.length, 2);
      expect(pastaSauce[0].normalizedName, "pasta");
      expect(pastaSauce[1].normalizedName, "sauce");

      final sandwichMayo = ItemParser.parse("sandwich + mayo");
      expect(sandwichMayo.length, 2);
      expect(sandwichMayo[0].normalizedName, "sandwich");
      expect(sandwichMayo[1].normalizedName, "mayo");
    });
  });
}

