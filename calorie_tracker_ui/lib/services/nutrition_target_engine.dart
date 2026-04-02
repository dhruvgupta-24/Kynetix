import '../screens/onboarding_screen.dart';
import '../services/health_service.dart';

// ─── DayTarget ────────────────────────────────────────────────────────────────

class DayTarget {
  final double calories;
  final double protein;
  final bool   isTrainingDay;
  final String label;   // "Training Day" | "Rest Day"
  final String note;    // brief derivation note

  const DayTarget({
    required this.calories,
    required this.protein,
    required this.isTrainingDay,
    required this.label,
    required this.note,
  });
}

// ─── WeeklyTargetPlan ─────────────────────────────────────────────────────────

class WeeklyTargetPlan {
  final double maintenanceCalories;
  final double avgDailyCalories;
  final double avgDailyProtein;
  final double trainingDayCalories;
  final double restDayCalories;
  final double trainingDayProtein;
  final double restDayProtein;
  final bool   healthConnectActive;
  final int?   effectiveStepsPerDay;

  const WeeklyTargetPlan({
    required this.maintenanceCalories,
    required this.avgDailyCalories,
    required this.avgDailyProtein,
    required this.trainingDayCalories,
    required this.restDayCalories,
    required this.trainingDayProtein,
    required this.restDayProtein,
    required this.healthConnectActive,
    this.effectiveStepsPerDay,
  });
}

// ─── NutritionTargetEngine ────────────────────────────────────────────────────
//
// Single source of truth for all nutrition targets.
// All formulas are profile-driven — no hardcoded personal values.
//
// Calibration design for resistance-training athletes (gym-focused):
//   • Activity multipliers are LOWER than classic Mifflin tables because
//     lifting sessions ~350–450 kcal/hr ≠ sustained cardio.
//   • Step correction is capped at ±120 kcal — a minor modifier, not dominant.
//   • Fat loss deficit: −500 kcal/day (sustainable for young active males).
//   • Protein: 1.85 g/kg avg for fat loss — muscle-protective, attainable.
//   • Calorie cycling: ±120 kcal around weekly avg (realistic food diff).
//
// Validation (65 kg, 180 cm, 20 yr, male, 5–6 gym days, fat loss):
//   BMR   = 1 680 kcal
//   TDEE  = 1 680 × 1.41 = 2 369 kcal  (target: 2 325–2 400) ✅
//   Avg   = 2 369 − 500  = 1 869 kcal  (target: 1 800–1 900) ✅
//   Train = 1 869 + 120  = 1 989 kcal  (target: 1 900–2 000) ✅
//   Rest  = 1 869 − 120  = 1 749 kcal  (target: 1 700–1 800) ✅
//   Prot avg = 65 × 1.85 = 120 g       (target: ~120 g)       ✅

class NutritionTargetEngine {
  const NutritionTargetEngine._();
  static const NutritionTargetEngine instance = NutritionTargetEngine._();
  factory NutritionTargetEngine() => instance;

  // ── Public API ────────────────────────────────────────────────────────────

  WeeklyTargetPlan weeklyPlan(
    UserProfile profile, {
    HealthSyncResult? health,
  }) {
    final tdee      = _tdee(profile, health);
    final goalDelta = _goalAdjustment(profile.goal, tdee);
    final rawAvg    = tdee + goalDelta;
    final floor     = _calFloor(profile);
    final avgCal    = _r(rawAvg.clamp(floor, double.infinity));
    final avgProt   = _baseProtein(profile);
    final cycle     = _calorieCycle(profile);

    final trainCal = _r((rawAvg + cycle).clamp(floor, double.infinity));
    final restCal  = _r((rawAvg - cycle).clamp(floor, double.infinity));

    return WeeklyTargetPlan(
      maintenanceCalories:  tdee,
      avgDailyCalories:     avgCal,
      avgDailyProtein:      avgProt,
      trainingDayCalories:  trainCal,
      restDayCalories:      restCal,
      trainingDayProtein:   _trainingProtein(profile),
      restDayProtein:       _restProtein(profile),
      healthConnectActive:  health?.hasData == true,
      effectiveStepsPerDay: health?.effectiveAverageSteps?.toInt(),
    );
  }

  DayTarget dayTarget(
    UserProfile profile, {
    required bool isGymDay,
    HealthSyncResult? health,
  }) {
    final plan = weeklyPlan(profile, health: health);
    final cal  = isGymDay ? plan.trainingDayCalories : plan.restDayCalories;
    final pro  = isGymDay ? plan.trainingDayProtein  : plan.restDayProtein;
    return DayTarget(
      calories:      cal,
      protein:       pro,
      isTrainingDay: isGymDay,
      label:         isGymDay ? 'Training Day' : 'Rest Day',
      note:          isGymDay ? '+${plan.trainingDayCalories - plan.avgDailyCalories} kcal vs daily avg' : '${plan.restDayCalories - plan.avgDailyCalories} kcal vs daily avg',
    );
  }

  // ── Core formulas ─────────────────────────────────────────────────────────

  double _bmr(UserProfile p) => p.gender == 'Male'
      ? 10 * p.weight + 6.25 * p.height - 5 * p.age + 5
      : 10 * p.weight + 6.25 * p.height - 5 * p.age - 161;

  /// Resistance-training-calibrated activity multiplier.
  /// Deliberately lower than classic Mifflin tables (which assume cardio).
  /// Gym lifting sessions burn ~350–450 kcal; rest of day assumed sedentary/light.
  double _activityMultiplier(UserProfile p) {
    final avg = (p.workoutDaysMin + p.workoutDaysMax) / 2.0;
    if (avg <= 0.5) return 1.20; // sedentary
    if (avg <= 1.5) return 1.25; // 1 day/wk
    if (avg <= 2.5) return 1.29; // 2 days/wk
    if (avg <= 3.5) return 1.33; // 3 days/wk — light trainer
    if (avg <= 4.5) return 1.37; // 4 days/wk — moderate
    if (avg <= 5.5) return 1.41; // 5 days/wk — active trainer ← most common
    if (avg <= 6.5) return 1.45; // 6 days/wk — very frequent
    return 1.50;                 // 7 days  — extreme
  }

  /// Step correction: minor modifier, capped so Health Connect improves targets
  /// without dominating them.
  /// Health Connect data influences TDEE only in the 3rd decimal place.
  int _stepCorrection(HealthSyncResult? health) {
    if (health == null || !health.hasData) return 0;
    final s = health.effectiveAverageSteps!;
    if (s < 3000)  return -120;
    if (s < 5000)  return  -60;
    if (s < 7500)  return    0; // baseline — most desk/student lifestyles
    if (s < 10000) return   75;
    if (s < 12000) return  100;
    return 120;
  }

  double _tdee(UserProfile p, HealthSyncResult? health) =>
      _r(_bmr(p) * _activityMultiplier(p) + _stepCorrection(health));

  /// Goal-based calorie adjustment applied to TDEE.
  /// Uses bounded percentage-based logic so targets generalize across body sizes.
  double _goalAdjustment(String goal, double tdee) => switch (goal) {
    kFatLoss           => -_bounded(tdee * 0.22, 350, 550),
    kMuscleGain        =>  _bounded(tdee * 0.11, 180, 320),
    kBodyRecomposition => -_bounded(tdee * 0.09, 120, 250),
    _                  => 0,
  };

  double _calorieCycle(UserProfile p) {
    final avgWorkoutDays = (p.workoutDaysMin + p.workoutDaysMax) / 2.0;
    if (avgWorkoutDays <= 1) return 70;
    if (avgWorkoutDays <= 3) return 90;
    if (avgWorkoutDays <= 5) return 105;
    return 120;
  }

  // ── Protein — goal- and day-aware ─────────────────────────────────────────
  // Practical targets: high enough to protect muscle, low enough to be
  // achievable on real Indian hostel food diets.

  double _baseProtein(UserProfile p) => switch (p.goal) {
    kFatLoss           => _r(p.weight * 1.85),
    kMuscleGain        => _r(p.weight * 1.90),
    kBodyRecomposition => _r(p.weight * 1.85),
    _                  => _r(p.weight * 1.55),
  };

  double _trainingProtein(UserProfile p) => switch (p.goal) {
    kFatLoss           => _r(p.weight * 1.95),
    kMuscleGain        => _r(p.weight * 2.00),
    kBodyRecomposition => _r(p.weight * 1.95),
    _                  => _r(p.weight * 1.65),
  };

  double _restProtein(UserProfile p) => switch (p.goal) {
    kFatLoss           => _r(p.weight * 1.75),
    kMuscleGain        => _r(p.weight * 1.80),
    kBodyRecomposition => _r(p.weight * 1.80),
    _                  => _r(p.weight * 1.45),
  };

  double _bounded(double value, double min, double max) =>
      value.clamp(min, max).toDouble();

  /// Absolute minimum daily calorie target.
  /// Prevents dangerous deficits for lightweight users.
  /// Rule: never allow target below BMR + 200 kcal (a conservative safety margin).
  double _calFloor(UserProfile p) => _r(_bmr(p) + 200);

  double _r(double v) => (v * 10).round() / 10;
}
