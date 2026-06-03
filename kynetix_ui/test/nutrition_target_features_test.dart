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
}
