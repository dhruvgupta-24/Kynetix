import 'package:flutter_test/flutter_test.dart';

import 'package:kynetix/models/user_profile.dart';
import 'package:kynetix/services/nutrition_target_engine.dart';

/// The calorie and protein rules, checked against their intent.
void main() {
  final engine = NutritionTargetEngine.instance;

  UserProfile p({
    String goal = kFatLoss,
    double weight = 75,
    double height = 178,
    int minDays = 5,
    int maxDays = 5,
    String gender = 'Male',
  }) => UserProfile(
        name: 'T',
        age: 27,
        gender: gender,
        height: height,
        weight: weight,
        workoutDaysMin: minDays,
        workoutDaysMax: maxDays,
        goal: goal,
      );

  test('the weekly average of training and rest days equals the goal intake', () {
    for (final days in [2, 3, 4, 5, 6]) {
      for (final goal in [kLeanBulk, kBulk, kRecomposition, kMaintenance]) {
        final plan = engine.weeklyPlan(p(goal: goal, minDays: days, maxDays: days));
        final weekly = (plan.trainingDayCalories * days + plan.restDayCalories * (7 - days)) / 7;
        expect(weekly, closeTo(plan.avgDailyCalories, 0.6), reason: '$goal @ $days days');
      }
    }
  });

  test('goal ordering: cut < recomp < maintenance < lean bulk < bulk', () {
    double avg(String g) => engine.weeklyPlan(p(goal: g)).avgDailyCalories;
    expect(avg(kFatLoss), lessThan(avg(kRecomposition)));
    expect(avg(kRecomposition), lessThan(avg(kMaintenance)));
    expect(avg(kMaintenance), lessThan(avg(kLeanBulk)));
    expect(avg(kLeanBulk), lessThan(avg(kBulk)));
  });

  test('bulk surplus stays within about 10% of maintenance', () {
    final plan = engine.weeklyPlan(p(goal: kBulk));
    final surplus = plan.avgDailyCalories - plan.maintenanceCalories;
    expect(surplus, inInclusiveRange(200, 350));
  });

  test('a cut gets the most protein per kg', () {
    double pro(String g) => engine.weeklyPlan(p(goal: g)).avgDailyProtein;
    for (final g in [kRecomposition, kMaintenance, kLeanBulk, kBulk]) {
      expect(pro(kFatLoss), greaterThan(pro(g)), reason: g);
    }
    expect(pro(kFatLoss) / 75, closeTo(2.1, 0.01));
  });

  test('protein uses a reference weight capped at BMI 27', () {
    final heavy = engine.weeklyPlan(p(weight: 130, height: 175, goal: kMaintenance));
    final cap = 27 * 1.75 * 1.75; // 82.7 kg
    expect(heavy.avgDailyProtein, closeTo(cap * 1.8, 0.2));
  });

  test('older goal wording gets its goal numbers', () {
    final legacy = engine.weeklyPlan(p(goal: 'Fat Loss'));
    final current = engine.weeklyPlan(p(goal: kFatLoss));
    expect(legacy.avgDailyCalories, current.avgDailyCalories);
    expect(legacy.avgDailyProtein, current.avgDailyProtein);
  });

  test('gender matching is case-insensitive', () {
    expect(
      engine.weeklyPlan(p(gender: 'male')).maintenanceCalories,
      engine.weeklyPlan(p(gender: 'Male')).maintenanceCalories,
    );
  });

  test('macro split: fat never below 0.6 g/kg, macros add back to the calories', () {
    final split = engine.macroSplit(1600, 170, profile: p(weight: 80));
    expect(split.fat, greaterThanOrEqualTo(0.6 * 80 - 0.5));
    final kcal = 170 * 4 + split.carbs * 4 + split.fat * 9;
    expect(kcal, closeTo(1600, 10));
  });

  test('steps above 7,000 raise the target, below lower it, capped at 400', () {
    final low = p().copyWith(averageDailySteps: 3000);
    final high = p().copyWith(averageDailySteps: 14000);
    final crazy = p().copyWith(averageDailySteps: 90000);
    expect(engine.stepCorrectionKcal(low, null), lessThan(0));
    expect(engine.stepCorrectionKcal(high, null), greaterThan(0));
    expect(engine.stepCorrectionKcal(crazy, null), 400);
  });
}
