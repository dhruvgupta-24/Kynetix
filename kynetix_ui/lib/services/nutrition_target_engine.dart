import 'package:flutter/foundation.dart';
import '../models/workout_session.dart';
import '../models/user_profile.dart';
import '../services/health_service.dart';
import '../models/day_log.dart';
import 'profile_service.dart';
import 'workout_service.dart';
import 'persistence_service.dart';

// Logging in this file is debug-only: release builds skip the console I/O.
void _debugLog(String? message, {int? wrapWidth}) {
  if (kDebugMode) debugPrint(message, wrapWidth: wrapWidth);
}

/// Flip to true locally to trace every target calculation.
const bool _kVerboseTargetLogs = false;


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

/// Carbohydrate and fat grams for a day's calorie and protein target.
class MacroSplit {
  const MacroSplit({required this.carbs, required this.fat});
  final double carbs;
  final double fat;
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

  /// Daily fiber target in grams.
  ///
  /// Derived from the IOM / Academy of Nutrition and Dietetics guideline:
  ///   14 g of fiber per 1,000 kcal consumed
  ///   (Institute of Medicine, Dietary Reference Intakes, 2005).
  /// Clamped to [20, 60] g to protect edge cases (very-low or very-high TDEE).
  final double fiberTargetG;

  const WeeklyTargetPlan({
    required this.maintenanceCalories,
    required this.avgDailyCalories,
    required this.avgDailyProtein,
    required this.trainingDayCalories,
    required this.restDayCalories,
    required this.trainingDayProtein,
    required this.restDayProtein,
    required this.healthConnectActive,
    required this.fiberTargetG,
    this.effectiveStepsPerDay,
  });
}

// ─── NutritionTargetEngine ────────────────────────────────────────────────────
//
// Single source of truth for all nutrition targets.
// All formulas are profile-driven — no hardcoded personal values.
//
// Calibration (resistance-trained users):
//   • BMR: Mifflin-St Jeor.
//   • Activity multipliers 1.20-1.50 by training days, LOWER than classic
//     tables (a lifting session is ~300-450 kcal, the rest of the day light).
//   • Steps: (steps - 7,000) x weight x 0.00041 kcal, clamped to ±400, from
//     the 14/30-day weighted step average (7,000 is already in the multiplier).
//   • Goal: cut -22% [350, 550], lean bulk +8% [150, 250], bulk +10%
//     [200, 350], recomp -9% [120, 250], maintenance 0.
//   • Training vs rest days differ by 140-220 kcal, weighted by the number of
//     each so the weekly average equals the goal.
//   • Floor: BMR + 200.
//   • Protein: 1.7-2.2 g/kg by goal and day on a reference weight capped at
//     BMI 27; fat at least 0.6 g/kg; carbs fill the rest (see macroSplit).

class NutritionTargetEngine {
  const NutritionTargetEngine._();
  static const NutritionTargetEngine instance = NutritionTargetEngine._();
  factory NutritionTargetEngine() => instance;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Pure read function. Resolves current DayTarget for a given date without mutating DayLog or triggering notifications.
  DayTarget effectiveTargetForDate(
    DateTime date, {
    UserProfile? profile,
    HealthSyncResult? health,
    bool forceRecalculate = false,
    DayLog? log,
  }) {
    final prof = profile ?? ProfileService.instance.currentUserProfile;
    if (prof == null) {
      return const DayTarget(
        calories: 2000.0,
        protein: 140.0,
        isTrainingDay: false,
        label: 'Default',
        note: 'No Profile Loaded',
      );
    }

    final resolvedLog = log ?? logFor(date);
    final effectiveHealth = health ?? HealthService().lastSyncResult;

    final ws = WorkoutService.instance;
    final plan = ws.planFor(date, log: resolvedLog);

    // Return stored/frozen targets if present and not forcing recalculation
    if (!forceRecalculate && resolvedLog.targetCalories != null && resolvedLog.targetProtein != null) {
      final override = resolvedLog.gymDay?.targetCaloriesOverride;
      if (override != null) {
        return DayTarget(
          calories: override,
          protein: resolvedLog.targetProtein!,
          isTrainingDay: plan.isTraining,
          label: 'Manual Override',
          note: 'Saved Target (Drift Protected)',
        );
      }
      return DayTarget(
        calories: resolvedLog.targetCalories!,
        protein: resolvedLog.targetProtein!,
        isTrainingDay: plan.isTraining,
        label: _planLabel(plan),
        note: 'Saved Target (Drift Protected)',
      );
    }

    // Pure dynamic calculation for display if target is not stored yet
    final session = ws.sessionFor(date);
    final gymDay = resolvedLog.gymDay;

    return dayTarget(
      prof,
      isGymDay: plan.isTraining,
      health: effectiveHealth,
      session: session,
      workoutTypeName: plan.isTraining ? plan.name : null,
      targetCaloriesOverride: gymDay?.targetCaloriesOverride,
      carryForwardAdjustment: resolvedLog.carryForwardAdjustment,
      date: null,
    );
  }

  /// Centralized write pipeline for target calculation and persistence.
  /// Refreshes automatically-managed nutrition targets when workout/day state changes.
  /// Preserves manual target overrides (targetCaloriesOverride / custom targets).
  Future<void> refreshTargetForDate(
    DateTime date, {
    UserProfile? profile,
    bool force = false,
    bool notify = true,
  }) async {
    final current = profile ?? ProfileService.instance.currentUserProfile;
    if (current == null) return;
    // A past day is judged by the profile (weight, goal) in force that day,
    // not today's.
    final prof = current.profileActiveOn(date) ?? current;

    final log = logFor(date);

    // Preserve manual target override if present. The training pick may still
    // have changed, so the day is saved either way.
    if (log.gymDay?.targetCaloriesOverride != null) {
      _debugLog('[NutritionTargetEngine] Preserving manual calorie override for ${dateKey(date)}: ${log.gymDay!.targetCaloriesOverride} kcal');
      if (force) {
        await PersistenceService.saveDayLogsAndSync(date);
        if (notify) PersistenceService.notifyLogsChanged();
      }
      return;
    }

    final ws = WorkoutService.instance;
    final session = ws.sessionFor(date);
    final plan = ws.planFor(date, log: log);

    final freshTarget = dayTarget(
      prof,
      isGymDay: plan.isTraining,
      health: HealthService().lastSyncResult,
      session: session,
      workoutTypeName: plan.isTraining ? plan.name : null,
      targetCaloriesOverride: null, // Only refresh automatic target
      carryForwardAdjustment: log.carryForwardAdjustment,
      date: date,
    );

    final changed = force ||
        log.targetCalories != freshTarget.calories ||
        log.targetProtein != freshTarget.protein;

    if (changed) {
      log.targetCalories = freshTarget.calories;
      log.targetProtein = freshTarget.protein;
      await PersistenceService.saveDay(date);
      if (notify) {
        PersistenceService.notifyLogsChanged();
      }
    }
  }

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
    final spread    = _calorieCycle(profile);

    // Training days sit [spread] kcal above rest days, weighted by how many of
    // each the week has, so the weekly average lands exactly on the goal
    // (5 training days pull rest days down more than they lift training days).
    final trainDays = _trainingDaysPerWeek(profile);
    final trainCal = _r((rawAvg + spread * (7 - trainDays) / 7).clamp(floor, double.infinity));
    final restCal  = _r((rawAvg - spread * trainDays / 7).clamp(floor, double.infinity));

    if (profile.useCustomTargets) {
      final maintenance = profile.customMaintenanceCalories ?? tdee;
      final customTrainCal = profile.customTrainingDayCalories ?? trainCal;
      final customRestCal = profile.customRestDayCalories ?? restCal;
      final protein = profile.customProteinTarget ?? avgProt;
      final avgCal  = _r((customTrainCal + customRestCal) / 2);

      return WeeklyTargetPlan(
        maintenanceCalories:  maintenance,
        avgDailyCalories:     avgCal,
        avgDailyProtein:      protein,
        trainingDayCalories:  customTrainCal,
        restDayCalories:      customRestCal,
        trainingDayProtein:   protein,
        restDayProtein:       protein,
        healthConnectActive:  health?.hasData == true,
        fiberTargetG:         _fiberTarget(avgCal),
        effectiveStepsPerDay: health?.effectiveAverageSteps?.toInt() ?? profile.averageDailySteps,
      );
    }

    return WeeklyTargetPlan(
      maintenanceCalories:  tdee,
      avgDailyCalories:     avgCal,
      avgDailyProtein:      avgProt,
      trainingDayCalories:  trainCal,
      restDayCalories:      restCal,
      trainingDayProtein:   _trainingProtein(profile),
      restDayProtein:       _restProtein(profile),
      healthConnectActive:  health?.hasData == true,
      fiberTargetG:         _fiberTarget(avgCal),
      effectiveStepsPerDay: health?.effectiveAverageSteps?.toInt() ?? profile.averageDailySteps,
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
    double? carryForwardAdjustment,
    DateTime? date,
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
    int originalCalBonus = 0;
    if (session != null && !session.isEmpty) {
      loadScore = _workoutLoadScore(session);
      originalCalBonus = _loadToCalBonus(loadScore, session);
      // calBonus is kept at 0 to prevent double-counting exercise expenditure (already budgeted in activity multiplier)
    }

    final baseCal = cal + calBonus + (carryForwardAdjustment ?? 0.0);
    final calculatedTotalCal = _r(baseCal.clamp(_calFloor(profile), double.infinity));
        
    final isOverride = targetCaloriesOverride != null;
    final finalCal = targetCaloriesOverride ?? calculatedTotalCal;

    // Verbose per-call trace. dayTarget runs for every target lookup (widget,
    // insights, day screens), so it is opt-in to keep hot paths quiet.
    if (_kVerboseTargetLogs) {
      _debugLog('[NutritionTargetEngine] --- Calorie Target Calculation ---');
      _debugLog('[NutritionTargetEngine] Date/Day Details: Label: $workoutTypeName, isGymDay: $isGymDay, actuallyTraining: $actuallyTraining');
      _debugLog('[NutritionTargetEngine] Base calculations:');
      _debugLog('[NutritionTargetEngine]   - BMR: ${_bmr(profile)} kcal (from UserProfile)');
      _debugLog('[NutritionTargetEngine]   - TDEE: ${plan.maintenanceCalories} kcal (from NutritionTargetEngine._tdee)');
      _debugLog('[NutritionTargetEngine] Modifiers applied:');
      final tdee = plan.maintenanceCalories;
      final goalDelta = _goalAdjustment(profile.goal, tdee);
      _debugLog('[NutritionTargetEngine]   - Goal Adjustment (${profile.goal}): $goalDelta kcal (from NutritionTargetEngine._goalAdjustment)');
      final cycle = _calorieCycle(profile);
      _debugLog('[NutritionTargetEngine]   - Calorie Cycling (Training/Rest split): ${actuallyTraining ? '+' : '-'}$cycle kcal (from NutritionTargetEngine._calorieCycle)');
      if (originalCalBonus != 0) {
        _debugLog('[NutritionTargetEngine]   - Workout Load Calorie Bonus (Score: $loadScore): +0 kcal (originally +$originalCalBonus kcal, removed to prevent double-counting)');
      }
      if (carryForwardAdjustment != null && carryForwardAdjustment != 0) {
        _debugLog('[NutritionTargetEngine]   - Carry-Forward Adjustment: ${carryForwardAdjustment > 0 ? '+' : ''}${carryForwardAdjustment.toInt()} kcal (from PersistenceService / DashboardScreen)');
      }
      if (isOverride) {
        _debugLog('[NutritionTargetEngine]   - Manual Calorie Target Override: $targetCaloriesOverride kcal (from GymDay / User settings)');
      }
      _debugLog('[NutritionTargetEngine] Final Calorie Target: $finalCal kcal');
      _debugLog('[NutritionTargetEngine] ----------------------------------');
    }

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
      final noteCarry = carryForwardAdjustment != null && carryForwardAdjustment != 0
          ? ' | carry-forward: ${carryForwardAdjustment > 0 ? '+' : ''}${carryForwardAdjustment.toInt()} kcal'
          : '';
      note = '$noteBase$noteExtra$noteCarry';
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

  String _planLabel(DayPlan plan) {
    if (!plan.isTraining) return 'Rest Day';
    final n = plan.name;
    if (n == null || n.isEmpty || n == 'Custom Workout' || n == 'Other') return 'Training Day';
    return n.endsWith('Day') ? n : '$n Day';
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

  double _bmr(UserProfile p) => p.gender.trim().toLowerCase() == 'male'
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
    if (avg <= 3.5) return 1.33; // 3 days/wk, light trainer
    if (avg <= 4.5) return 1.37; // 4 days/wk, moderate
    if (avg <= 5.5) return 1.41; // 5 days/wk, active trainer ← most common
    if (avg <= 6.5) return 1.45; // 6 days/wk, very frequent
    return 1.50;                 // 7 days, extreme
  }

  /// Science-based step-to-calorie correction vs a 7,000-step sedentary baseline.
  ///
  /// Physiology basis:
  ///   • Energy cost of walking ≈ 0.5–0.6 kcal per kg per km.
  ///   • Average stride ≈ 0.75 m → 1 step ≈ 0.00075 km.
  ///   • kcal/step = weight_kg × 0.00075 × 0.55 ≈ weight × 0.000413
  ///   • At 65 kg: 0.0268 kcal/step  (65 × 0.00075 × 0.55; validated against DLW studies)
  ///   • At 80 kg: 0.033 kcal/step (heavier → same stride, more energy)
  ///
  /// The "baseline" is 7,000 steps — the approximate step count already
  /// embedded in the activity multipliers (a desk person who walks to/from car,
  /// goes to gym, etc.). The correction is the DELTA above/below this.
  ///
  /// Clamped to ±400 kcal to prevent runaway values from bad sensor data.
  /// The step adjustment the targets use, in kcal (shown on the dashboard
  /// and profile so every screen quotes the same number).
  int stepCorrectionKcal(UserProfile p, HealthSyncResult? health) =>
      _stepCorrectionKcal(p, health);

  int _stepCorrectionKcal(UserProfile p, HealthSyncResult? health) {
    final double? steps;
    if (health != null && health.hasData) {
      steps = health.effectiveAverageSteps;
    } else if (p.averageDailySteps != null) {
      steps = p.averageDailySteps!.toDouble();
    } else {
      steps = null;
    }

    if (steps == null) return 0;

    const baseline = 7000.0; // steps already in the activity multiplier
    const strideKm = 0.00075; // avg stride length in km
    const metFactor = 0.55;   // kcal per kg per km (conservative walking pace)
    final kcalPerStep = p.weight * strideKm * metFactor;

    final rawOffset = (steps - baseline) * kcalPerStep;
    return rawOffset.clamp(-400.0, 400.0).round();
  }

  double _tdee(UserProfile p, HealthSyncResult? health) =>
      _r(_bmr(p) * _activityMultiplier(p) + _stepCorrectionKcal(p, health));

  /// Goal-based calorie adjustment applied to TDEE.
  ///
  /// Cut ~22% (about 0.5-1% body weight a week), lean bulk ~8%, bulk ~10%
  /// (bigger surpluses add mostly fat in trained lifters), recomp a small
  /// deficit.
  double _goalAdjustment(String goal, double tdee) => switch (_goalKey(goal)) {
    kFatLoss       => -_bounded(tdee * 0.22, 350, 550),
    kLeanBulk      =>  _bounded(tdee * 0.08, 150, 250),
    kBulk          =>  _bounded(tdee * 0.10, 200, 350),
    kRecomposition => -_bounded(tdee * 0.09, 120, 250),
    _              => 0, // Maintenance
  };

  /// Canonical goal constant for stored goal text, including older wording
  /// ("Fat Loss", "cut", "gain") so every profile gets its goal's numbers.
  static String _goalKey(String goal) {
    final g = goal.trim().toLowerCase();
    if (g.contains('fat loss') || g.contains('cut')) return kFatLoss;
    if (g.contains('lean bulk')) return kLeanBulk;
    if (g.contains('bulk') || g.contains('gain')) return kBulk;
    if (g.contains('recomp')) return kRecomposition;
    return goal;
  }

  double _trainingDaysPerWeek(UserProfile p) =>
      ((p.workoutDaysMin + p.workoutDaysMax) / 2.0).clamp(0.0, 7.0);

  /// Gap between a training day and a rest day, in kcal.
  double _calorieCycle(UserProfile p) {
    final avgWorkoutDays = _trainingDaysPerWeek(p);
    if (avgWorkoutDays <= 1) return 140;
    if (avgWorkoutDays <= 3) return 180;
    if (avgWorkoutDays <= 5) return 200;
    return 220;
  }

  // ── Protein — goal- and day-aware ─────────────────────────────────────────
  //
  // g/kg follows the ISSN position stand (1.6-2.2 g/kg for lifters, the top
  // of the range in a deficit). It is applied to a reference weight capped at
  // BMI 27 for the user's height, so a heavier user's target tracks lean mass
  // instead of growing with body fat.

  double _proteinWeight(UserProfile p) {
    final hM = p.height / 100.0;
    if (hM <= 0) return p.weight;
    final cap = 27.0 * hM * hM;
    return p.weight < cap ? p.weight : cap;
  }

  double _baseProtein(UserProfile p) => _r(_proteinWeight(p) * switch (_goalKey(p.goal)) {
    kFatLoss       => 2.10,   // highest: protect muscle in a deficit
    kRecomposition => 2.00,
    kLeanBulk      => 1.80,   // a surplus spares protein
    kBulk          => 1.80,
    _              => 1.80,   // Maintenance
  });

  double _trainingProtein(UserProfile p) => _r(_proteinWeight(p) * switch (_goalKey(p.goal)) {
    kFatLoss       => 2.20,
    kRecomposition => 2.10,
    kLeanBulk      => 1.90,
    kBulk          => 1.90,
    _              => 1.90,
  });

  double _restProtein(UserProfile p) => _r(_proteinWeight(p) * switch (_goalKey(p.goal)) {
    kFatLoss       => 2.00,
    kRecomposition => 1.90,
    kLeanBulk      => 1.70,
    kBulk          => 1.70,
    _              => 1.70,
  });

  /// Carb and fat grams for a day: fat is 30% of the non-protein calories but
  /// never under 0.6 g per kg; carbs take the rest.
  MacroSplit macroSplit(double calories, double protein, {UserProfile? profile}) {
    final nonProtein = (calories - protein * 4).clamp(0.0, double.infinity).toDouble();
    var fat = nonProtein * 0.30 / 9;
    final prof = profile ?? ProfileService.instance.currentUserProfile;
    if (prof != null) {
      final floor = 0.6 * _proteinWeight(prof);
      if (fat < floor) fat = floor;
    }
    final carbs = ((nonProtein - fat * 9) / 4).clamp(0.0, double.infinity).toDouble();
    return MacroSplit(carbs: carbs.roundToDouble(), fat: fat.roundToDouble());
  }

  double _bounded(double value, double min, double max) =>
      value.clamp(min, max).toDouble();

  /// Absolute minimum daily calorie target.
  double _calFloor(UserProfile p) => _r(_bmr(p) + 200);

  /// Daily fiber target derived from the IOM 14 g per 1,000 kcal guideline.
  ///
  /// Source: Institute of Medicine, Dietary Reference Intakes for Energy,
  /// Carbohydrate, Fiber, Fat, Fatty Acids, Cholesterol, Protein, and Amino
  /// Acids. National Academies Press, 2005, p. 339.
  ///
  /// Clamped to [20, 60] g to handle edge cases:
  ///   - Floor 20 g: ensures a minimum target for very-low-calorie entries.
  ///   - Cap   60 g: avoids unrealistically high targets on extremely high calorie intakes.
  double _fiberTarget(double avgDailyCalories) =>
      (14.0 * avgDailyCalories / 1000).clamp(20.0, 60.0);

  double _r(double v) => (v * 10).round() / 10;
}
