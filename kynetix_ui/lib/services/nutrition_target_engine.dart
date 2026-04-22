import '../models/workout_session.dart';
import '../screens/onboarding_screen.dart';
import '../services/health_service.dart';

// ─── DayTarget ────────────────────────────────────────────────────────────────

class DayTarget {
  final double calories;
  final double protein;
  final bool   isTrainingDay;
  final String label;             // "Training Day" | "Rest Day" | "Push Day" etc.
  final String note;              // brief derivation note
  final int?   workoutLoadScore;  // 0–100, null when no session data
  final int?   workoutCalBonus;   // kcal bonus from actual session load

  const DayTarget({
    required this.calories,
    required this.protein,
    required this.isTrainingDay,
    required this.label,
    required this.note,
    this.workoutLoadScore,
    this.workoutCalBonus,
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
// Workout load scoring (added in hardening pass):
//   • Derived from actual WorkoutSession data (volume, sets, duration).
//   • Produces a bounded kcal bonus on top of the base training-day target.
//   • Capped at ±200 kcal so targets don't swing wildly.
//   • Completely optional — if no session logged, falls back to toggle-based.
//
// Validation (65 kg, 180 cm, 20 yr, male, 5–6 gym days, fat loss):
//   BMR   = 1 680 kcal
//   TDEE  = 1 680 × 1.41 = 2 369 kcal  (target: 2 325–2 400)
//   Avg   = 2 369 − 500  = 1 869 kcal  (target: 1 800–1 900)
//   Train = 1 869 + 120  = 1 989 kcal  (target: 1 900–2 000)
//   Rest  = 1 869 − 120  = 1 749 kcal  (target: 1 700–1 800)
//   Prot avg = 65 × 1.85 = 120 g       (target: ~120 g)       

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

  /// Compute the day's calorie and protein target.
  ///
  /// Priority for determining training day status and calorie load:
  ///   1. Actual [WorkoutSession] data — uses real volume/sets/duration.
  ///   2. [GymDay.workoutType] from the DayLog toggle (split type only).
  ///   3. Plain [isGymDay] bool fallback.
  ///
  /// If a [WorkoutSession] exists, its training load score adjusts the
  /// base training-day target by ±kLoadCapKcal. This keeps targets stable
  /// while reflecting actual session intensity.
  DayTarget dayTarget(
    UserProfile profile, {
    required bool isGymDay,
    HealthSyncResult? health,
    WorkoutSession? session,
    String? workoutTypeName, // e.g. "Push", "Cardio", "Rest"
    double? targetCaloriesOverride,
  }) {
    final plan = weeklyPlan(profile, health: health);

    // Determine if this is a training day — session > toggle
    final actuallyTraining = session?.isEmpty == false || isGymDay;
    final cal = actuallyTraining
        ? plan.trainingDayCalories
        : plan.restDayCalories;
    final pro = actuallyTraining
        ? plan.trainingDayProtein
        : plan.restDayProtein;

    // Compute workout load offset from real session data
    int? loadScore;
    int calBonus = 0;
    if (session != null && !session.isEmpty) {
      loadScore = _workoutLoadScore(session);
      calBonus  = _loadToCalBonus(loadScore, session);
    }

    final calculatedTotalCal = _r((cal + calBonus).clamp(
        _calFloor(profile), double.infinity));
        
    final isOverride = targetCaloriesOverride != null;
    final finalCal = targetCaloriesOverride ?? calculatedTotalCal;

    // Build a meaningful label from the actual split name / workout type
    final label = _dayLabel(
      session: session,
      workoutTypeName: workoutTypeName,
      isTraining: actuallyTraining,
    );

    final String note;
    if (isOverride) {
      note = 'Manual Override (${calculatedTotalCal.toInt()} kcal original)';
    } else {
      final noteBase = actuallyTraining
          ? '+${plan.trainingDayCalories - plan.avgDailyCalories} kcal vs daily avg'
          : '${plan.restDayCalories - plan.avgDailyCalories} kcal vs daily avg';
      final noteExtra = calBonus != 0
          ? ' | session load: ${calBonus > 0 ? '+' : ''}$calBonus kcal'
          : '';
      note = '$noteBase$noteExtra';
    }

    return DayTarget(
      calories:         finalCal,
      protein:          pro,
      isTrainingDay:    actuallyTraining,
      label:            isOverride ? 'Manual Override' : label,
      note:             note,
      workoutLoadScore: loadScore,
      workoutCalBonus:  calBonus == 0 ? null : calBonus,
    );
  }

  // ── Workout load scoring ───────────────────────────────────────────────────
  //
  // Produces a 0–100 score from real session data.
  // Components:
  //   volume score  (0–40): tonnage-based, capped at a realistic upper bound
  //   set score     (0–30): total working sets
  //   duration score(0–30): session duration (if logged)
  //
  // Score → kcal bonus (bounded ±200 kcal):
  //   < 30  → 0  (light / warm-up only)
  //   30–50 → +40 kcal
  //   50–65 → +80 kcal
  //   65–80 → +120 kcal
  //   80–90 → +160 kcal
  //   > 90  → +200 kcal
  //
  // Cardio sessions use duration as primary signal, volume as 0.

  static const _kLoadCapKcal = 200;

  int _workoutLoadScore(WorkoutSession session) {
    // Volume sub-score (0–40)
    // 5 000 kg tonnage ≈ typical moderate Push day → score 20
    // 10 000 kg → score 40 (cap)
    final volumeScore = (session.totalWorkingVolume / 10000.0 * 40).clamp(0.0, 40.0);

    // Working-set sub-score (0–30)
    // 15 working sets is a full training session → score 30
    final setScore = (session.totalWorkingSets / 15.0 * 30).clamp(0.0, 30.0);

    // Duration sub-score (0–30)
    // 60 min → score 30; proportional below that
    final dur = session.durationMinutes ?? _estimateDuration(session);
    final durScore = (dur / 60.0 * 30).clamp(0.0, 30.0);

    return (volumeScore + setScore + durScore).round().clamp(0, 100);
  }

  /// Estimates session duration from set count when not explicitly logged.
  /// Assumes ~2.5 min per working set (set + rest).
  int _estimateDuration(WorkoutSession session) =>
      (session.totalWorkingSets * 2.5).round().clamp(10, 90);

  int _loadToCalBonus(int score, WorkoutSession session) {
    // Cardio sessions: pure duration-driven, resistance tonnage is 0
    final isCardio = session.splitDayName.toLowerCase().contains('cardio') ||
        session.totalWorkingVolume < 100;

    if (isCardio) {
      // For cardio, scale by duration directly
      final dur = session.durationMinutes ?? _estimateDuration(session);
      if (dur >= 60) return (_kLoadCapKcal * 0.80).round();
      if (dur >= 45) return (_kLoadCapKcal * 0.60).round();
      if (dur >= 30) return (_kLoadCapKcal * 0.40).round();
      if (dur >= 15) return (_kLoadCapKcal * 0.20).round();
      return 0;
    }

    // Resistance training: load score drives bonus
    if (score >= 90) return _kLoadCapKcal;        // 200 kcal
    if (score >= 80) return (_kLoadCapKcal * 0.80).round(); // 160
    if (score >= 65) return (_kLoadCapKcal * 0.60).round(); // 120
    if (score >= 50) return (_kLoadCapKcal * 0.40).round(); // 80
    if (score >= 30) return (_kLoadCapKcal * 0.20).round(); // 40
    return 0;
  }

  String _dayLabel({
    WorkoutSession? session,
    String? workoutTypeName,
    required bool isTraining,
  }) {
    // 1. Actual logged session name (highest truth)
    if (session != null && !session.isEmpty) {
      final name = session.splitDayName;
      if (name.isNotEmpty && name != 'Custom Workout') return '$name Day';
    }
    // 2. workoutTypeName can be the full split day name (e.g. "Chest + Triceps")
    //    or the coarse enum name ("Push", "Cardio").  Either way, show it.
    if (workoutTypeName != null &&
        workoutTypeName.isNotEmpty &&
        workoutTypeName != 'Rest' &&
        workoutTypeName != 'Other') {
      // Avoid double "Day Day" for names already ending in "Day".
      if (workoutTypeName.endsWith('Day')) return workoutTypeName;
      return '$workoutTypeName Day';
    }
    return isTraining ? 'Training Day' : 'Rest Day';
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
  double _goalAdjustment(String goal, double tdee) => switch (goal) {
    kFatLoss       => -_bounded(tdee * 0.22, 350, 550),
    kLeanBulk      =>  _bounded(tdee * 0.08, 150, 250),
    kBulk          =>  _bounded(tdee * 0.15, 250, 450),
    kRecomposition => -_bounded(tdee * 0.09, 120, 250),
    _              => 0, // Maintenance
  };

  double _calorieCycle(UserProfile p) {
    final avgWorkoutDays = (p.workoutDaysMin + p.workoutDaysMax) / 2.0;
    if (avgWorkoutDays <= 1) return 70;
    if (avgWorkoutDays <= 3) return 90;
    if (avgWorkoutDays <= 5) return 105;
    return 120;
  }

  // ── Protein — goal- and day-aware ─────────────────────────────────────────

  double _baseProtein(UserProfile p) => switch (p.goal) {
    kFatLoss       => _r(p.weight * 1.85),   // high — protect muscle in deficit
    kLeanBulk      => _r(p.weight * 1.70),   // enough to drive growth
    kBulk          => _r(p.weight * 1.85),   // same as fat loss — mass phase protein
    kRecomposition => _r(p.weight * 2.00),   // highest — simultaneous cut+build
    _              => _r(p.weight * 1.75),   // Maintenance — still training 4-6×/wk
  };

  double _trainingProtein(UserProfile p) => switch (p.goal) {
    kFatLoss       => _r(p.weight * 1.95),   // peak day — max muscle protection
    kLeanBulk      => _r(p.weight * 1.80),   // anabolic stimulus day
    kBulk          => _r(p.weight * 2.00),   // heavy training day
    kRecomposition => _r(p.weight * 2.15),   // highest of all goals on training day
    _              => _r(p.weight * 1.85),   // Maintenance training day
  };

  double _restProtein(UserProfile p) => switch (p.goal) {
    kFatLoss       => _r(p.weight * 1.75),   // reduced but muscle-protective
    kLeanBulk      => _r(p.weight * 1.60),   // rest day — recovery focused
    kBulk          => _r(p.weight * 1.70),   // still elevated for mass phase
    kRecomposition => _r(p.weight * 1.85),   // recomp rest day — never drop low
    _              => _r(p.weight * 1.65),   // Maintenance rest day
  };

  double _bounded(double value, double min, double max) =>
      value.clamp(min, max).toDouble();

  /// Absolute minimum daily calorie target.
  double _calFloor(UserProfile p) => _r(_bmr(p) + 200);

  double _r(double v) => (v * 10).round() / 10;
}
