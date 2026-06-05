import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/screens/onboarding_screen.dart';
import 'package:kynetix/services/nutrition_target_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final baseProfile = UserProfile(
    name: 'Test Athlete',
    age: 25,
    gender: 'Male',
    height: 180.0,
    weight: 85.0,
    workoutDaysMin: 5,
    workoutDaysMax: 6,
    goal: kLeanBulk,
  );

  group('NutritionTargetEngine - Custom Targets', () {
    test('Should return calculated targets when useCustomTargets is false', () {
      final engine = NutritionTargetEngine();
      final plan = engine.weeklyPlan(baseProfile);

      expect(plan.maintenanceCalories, greaterThan(2000.0));
      expect(plan.avgDailyCalories, greaterThan(plan.maintenanceCalories)); // lean bulk goal
      expect(plan.avgDailyProtein, closeTo(85.0 * 1.70, 1.0));
    });

    test('Should return custom targets when useCustomTargets is true', () {
      final engine = NutritionTargetEngine();
      final customProfile = baseProfile.copyWith(
        useCustomTargets: true,
        customMaintenanceCalories: 2800.0,
        customTrainingDayCalories: 2600.0,
        customRestDayCalories: 2100.0,
        customProteinTarget: 160.0,
      );
      final plan = engine.weeklyPlan(customProfile);

      expect(plan.maintenanceCalories, 2800.0);
      expect(plan.trainingDayCalories, 2600.0);
      expect(plan.restDayCalories, 2100.0);
      expect(plan.avgDailyProtein, 160.0);
      expect(plan.trainingDayProtein, 160.0);
      expect(plan.restDayProtein, 160.0);
    });
  });

  group('NutritionTargetEngine - Carry-Forward Adjustments', () {
    test('Should apply carryForwardAdjustment to training and rest day targets', () {
      final engine = NutritionTargetEngine();
      
      // Base training day target without adjustment
      final targetNoAdj = engine.dayTarget(
        baseProfile,
        isGymDay: true,
      );

      // Apply +200 kcal carry-forward adjustment
      final targetPositiveAdj = engine.dayTarget(
        baseProfile,
        isGymDay: true,
        carryForwardAdjustment: 200.0,
      );

      expect(targetPositiveAdj.calories, targetNoAdj.calories + 200.0);
      expect(targetPositiveAdj.note, contains('carry-forward: +200 kcal'));

      // Apply -300 kcal carry-forward adjustment
      final targetNegativeAdj = engine.dayTarget(
        baseProfile,
        isGymDay: true,
        carryForwardAdjustment: -300.0,
      );

      expect(targetNegativeAdj.calories, targetNoAdj.calories - 300.0);
      expect(targetNegativeAdj.note, contains('carry-forward: -300 kcal'));
    });

    test('Should respect the daily override over carryForwardAdjustment', () {
      final engine = NutritionTargetEngine();
      final target = engine.dayTarget(
        baseProfile,
        isGymDay: true,
        carryForwardAdjustment: 200.0,
        targetCaloriesOverride: 2500.0,
      );

      expect(target.calories, 2500.0);
      expect(target.note, contains('Manual Override'));
    });
  });

  group('NutritionTargetEngine - Fiber Targets', () {
    test('Should calculate fiber target as 14g per 1,000 kcal of average daily calories', () {
      final engine = NutritionTargetEngine();
      final plan = engine.weeklyPlan(baseProfile.copyWith(
        useCustomTargets: true,
        customMaintenanceCalories: 2000.0,
        customTrainingDayCalories: 2000.0,
        customRestDayCalories: 2000.0,
      ));

      // 2000 kcal * 14 / 1000 = 28.0 g
      expect(plan.fiberTargetG, 28.0);
    });

    test('Should clamp fiber target to a floor of 20g for very low calorie levels', () {
      final engine = NutritionTargetEngine();
      final plan = engine.weeklyPlan(baseProfile.copyWith(
        useCustomTargets: true,
        customMaintenanceCalories: 1200.0,
        customTrainingDayCalories: 1200.0,
        customRestDayCalories: 1200.0,
      ));

      // 1200 kcal * 14 / 1000 = 16.8 g -> clamp floor to 20.0 g
      expect(plan.fiberTargetG, 20.0);
    });

    test('Should clamp fiber target to a ceiling of 60g for very high calorie levels', () {
      final engine = NutritionTargetEngine();
      final plan = engine.weeklyPlan(baseProfile.copyWith(
        useCustomTargets: true,
        customMaintenanceCalories: 5000.0,
        customTrainingDayCalories: 5000.0,
        customRestDayCalories: 5000.0,
      ));

      // 5000 kcal * 14 / 1000 = 70.0 g -> clamp ceiling to 60.0 g
      expect(plan.fiberTargetG, 60.0);
    });
  });
}
