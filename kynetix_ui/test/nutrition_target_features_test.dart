import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/screens/onboarding_screen.dart';
import 'package:kynetix/services/nutrition_target_engine.dart';
import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/models/carry_forward_record.dart';
import 'package:kynetix/services/health_service.dart';

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

  group('NutritionTargetEngine - Calorie Carry-Forward Preservation & Single Source of Truth', () {
    test('DayLog.carryForwardAdjustment acts as a dynamic getter prioritizing accepted carryForwardRecord', () {
      final log = DayLog();
      
      // Initially null
      expect(log.carryForwardAdjustment, isNull);

      // Setting manually falls back
      log.carryForwardAdjustment = 150.0;
      expect(log.carryForwardAdjustment, 150.0);

      // Adding an accepted record overrides the fallback value
      final recordAccepted = CarryForwardRecord(
        date: '2026-06-11',
        yesterdayDate: '2026-06-10',
        yesterdayTarget: 2000.0,
        yesterdayConsumed: 2200.0,
        difference: 200.0,
        adjustmentAmount: -200.0,
        accepted: true,
      );
      log.gymDay = GymDay(didGym: true, carryForwardRecord: recordAccepted);
      expect(log.carryForwardAdjustment, -200.0);

      // Adding a non-accepted record does not apply adjustment and returns null
      final recordIgnored = CarryForwardRecord(
        date: '2026-06-11',
        yesterdayDate: '2026-06-10',
        yesterdayTarget: 2000.0,
        yesterdayConsumed: 2200.0,
        difference: 200.0,
        adjustmentAmount: -200.0,
        accepted: false,
      );
      log.gymDay = GymDay(didGym: true, carryForwardRecord: recordIgnored);
      expect(log.carryForwardAdjustment, isNull);
    });

    test('Accepted carry-forward record survives GymDay status changes and split overrides', () {
      final record = CarryForwardRecord(
        date: '2026-06-11',
        yesterdayDate: '2026-06-10',
        yesterdayTarget: 2000.0,
        yesterdayConsumed: 2200.0,
        difference: 200.0,
        adjustmentAmount: -200.0,
        accepted: true,
      );
      
      var gymDay = GymDay(
        didGym: true,
        workoutType: WorkoutType.legs,
        splitDayName: 'Legs',
        carryForwardRecord: record,
      );

      // Toggle Gym to false (Rest Day) using withGym(false)
      gymDay = gymDay.withGym(false);
      expect(gymDay.didGym, isFalse);
      expect(gymDay.workoutType, isNull);
      expect(gymDay.carryForwardRecord, isNotNull);
      expect(gymDay.carryForwardRecord!.accepted, isTrue);
      expect(gymDay.carryForwardRecord!.adjustmentAmount, -200.0);

      // Toggle Gym back to true using withGym(true)
      gymDay = gymDay.withGym(true);
      expect(gymDay.didGym, isTrue);
      expect(gymDay.carryForwardRecord, isNotNull);
      expect(gymDay.carryForwardRecord!.adjustmentAmount, -200.0);

      // User split override preserves carryForwardRecord
      gymDay = gymDay.withUserOverride(splitName: 'Push', type: WorkoutType.push);
      expect(gymDay.didGym, isTrue);
      expect(gymDay.workoutType, WorkoutType.push);
      expect(gymDay.splitDayName, 'Push');
      expect(gymDay.carryForwardRecord, isNotNull);
      expect(gymDay.carryForwardRecord!.adjustmentAmount, -200.0);
    });

    test('Cloud sync JSON serialization/deserialization retains carry-forward record', () {
      final record = CarryForwardRecord(
        date: '2026-06-11',
        yesterdayDate: '2026-06-10',
        yesterdayTarget: 2000.0,
        yesterdayConsumed: 2200.0,
        difference: 200.0,
        adjustmentAmount: -200.0,
        accepted: true,
      );
      final originalLog = DayLog();
      originalLog.gymDay = GymDay(didGym: true, carryForwardRecord: record);

      // Serialize originalLog.gymDay (simulates Supabase gym_day_json storage)
      final gymDayJson = originalLog.gymDay!.toJson();

      // Deserialize on hydration
      final hydratedLog = DayLog();
      hydratedLog.gymDay = GymDay.fromJson(gymDayJson);

      // Verify the carry-forward adjustment resolves correctly
      expect(hydratedLog.carryForwardAdjustment, -200.0);
    });
  });

  group('NutritionTargetEngine - effectiveTargetForDate & Health caching', () {
    test('effectiveTargetForDate uses HealthService.instance.lastSyncResult when health parameter is null', () {
      final engine = NutritionTargetEngine();
      final healthService = HealthService();
      
      // Set the cached sync result
      final cachedHealth = HealthSyncResult(
        effectiveAverageSteps: 12000.0, // active tier -> higher target
        syncedAt: DateTime(2026, 6, 11),
      );
      healthService.lastSyncResult = cachedHealth;

      final target = engine.effectiveTargetForDate(
        DateTime(2026, 6, 11),
        profile: baseProfile,
      );

      // Compute expected target manually with the cached steps
      final expected = engine.dayTarget(
        baseProfile,
        isGymDay: true, // baseProfile workoutDaysMin=5, workoutDaysMax=6 -> training day by split default
        health: cachedHealth,
      );

      expect(target.calories, expected.calories);
      
      // Reset cached result to not affect other tests
      healthService.lastSyncResult = null;
    });

    test('effectiveTargetForDate frozen vs recalculated target behavior', () {
      final engine = NutritionTargetEngine();
      final date = DateTime(2026, 6, 11);
      final log = logFor(date);

      // Setup initial target values
      log.targetCalories = 2200.0;
      log.targetProtein = 150.0;

      // 1. Without forceRecalculate, it must return the frozen targets
      final targetFrozen = engine.effectiveTargetForDate(
        date,
        profile: baseProfile,
      );
      expect(targetFrozen.calories, 2200.0);
      expect(targetFrozen.protein, 150.0);

      // 2. With forceRecalculate: true, it must recalculate dynamically
      final targetRecalc = engine.effectiveTargetForDate(
        date,
        profile: baseProfile,
        forceRecalculate: true,
      );
      expect(targetRecalc.calories, isNot(2200.0));

      // Clean up log targets to prevent leaking state
      log.targetCalories = null;
      log.targetProtein = null;
    });
  });
}
