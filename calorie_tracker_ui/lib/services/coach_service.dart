import '../models/coach_insight.dart';
import '../models/day_log.dart';
import '../models/workout_session.dart';
import '../screens/onboarding_screen.dart';
import '../services/day_pattern_service.dart';
import '../services/nutrition_target_engine.dart';

// ─── CoachService ─────────────────────────────────────────────────────────────
//
// Produces short, direct, context-aware coaching insights.
//
// Intelligence model:
//   • Uses actual numbers (not just ratios) so messages feel human.
//   • Estimates meals remaining based on time + meal count already logged.
//   • Determines whether the protein gap is still recoverable today.
//   • Weight-aware: protein needs per meal are derived from the user's real
//     target, not a generic percentage.
//   • Time is a soft signal only — never the primary decision axis.

class CoachService {
  const CoachService._();
  static const CoachService instance = CoachService._();
  factory CoachService() => instance;

  List<CoachInsight> insightsForDay(
    DayLog    log,
    DayTarget target, {
    UserProfile?    profile,
    WorkoutSession? todayWorkout,
    DateTime?       now,
  }) {
    if (log.isEmpty) return const [];

    final cal         = log.totalCaloriesMid;
    final pro         = log.totalProteinMid;
    final calRat      = cal / target.calories.clamp(1, double.infinity);
    final proRat      = pro / target.protein .clamp(1, double.infinity);
    final hour        = (now ?? DateTime.now()).hour;
    final mealCount   = _mealCount(log);
    final patterns    = DayPatternService.instance.snapshot(upTo: now);

    // Meals still reasonably available today (soft estimate).
    final mealsLeft   = _estimateMealsLeft(hour, mealCount);
    final remainCal   = (target.calories - cal).clamp(0, 4000).toDouble();
    final remainProt  = (target.protein  - pro).clamp(0, 300).toDouble();
    final protPerMeal = mealsLeft > 0 ? remainProt / mealsLeft : remainProt;
    final proteinPlan = _proteinPlan(target: target, profile: profile, currentProtein: pro, now: now ?? DateTime.now(), mealsLeft: mealsLeft);

    final out = <CoachInsight>[];

    // ─ Protein analysis ──────────────────────────────────────────────────────

    if (pro < proteinPlan.minimumTarget * 0.72) {
      // Severely behind on protein
      final insight = _severeProteinGap(
        pro:         pro,
        target:      proteinPlan.idealTarget,
        minimum:     proteinPlan.minimumTarget,
        stretch:     proteinPlan.stretchTarget,
        remainProt:  remainProt,
        mealsLeft:   mealsLeft,
        protPerMeal: protPerMeal,
        calRat:      calRat,
        recoverable: proteinPlan.isRecoverable,
      );
      out.add(insight);
    } else if (pro < proteinPlan.minimumTarget) {
      // Meaningfully behind — actionable but recoverable
      final insight = _moderateProteinGap(
        pro:         pro,
        target:      proteinPlan.minimumTarget,
        ideal:       proteinPlan.idealTarget,
        remainProt:  remainProt,
        mealsLeft:   mealsLeft,
        protPerMeal: protPerMeal,
      );
      out.add(insight);
    } else if (pro >= proteinPlan.minimumTarget) {
      // Protein mostly covered — user can eat more flexibly
      if (remainCal > 200) {
        out.add(CoachInsight(
          type:       CoachInsightType.info,
          message:    'Protein is in a workable range.',
          actionHint: 'You have ~${remainCal.toInt()} kcal left — use it without pressure.',
        ));
      }
    }

    // ─ Calorie analysis ──────────────────────────────────────────────────────

    if (calRat > 1.12) {
      out.add(CoachInsight(
        type:       CoachInsightType.overGoal,
        message:    '${cal.toInt()} kcal — over your daily target.',
        actionHint: proRat >= 0.85
            ? 'Both macros are done. Skip unnecessary snacking.'
            : 'Keep the rest of the day light and protein-only.',
      ));
    } else if (calRat > 0.97 && proRat >= 0.85) {
      out.add(const CoachInsight(
        type:       CoachInsightType.info,
        message:    'Calories are almost at target.',
        actionHint: 'Avoid heavy carb meals now — lean protein is fine.',
      ));
    } else if (calRat > 0.97 && proRat < 0.80) {
      // Calories at limit but protein still low — classic mess-food trap
      out.add(CoachInsight(
        type:       CoachInsightType.balance,
        message:    'Calories are mostly covered but protein is still light at ${pro.toInt()}g.',
        actionHint: 'Use any remaining food budget on whey, curd, or egg whites only.',
      ));
    }

    if (remainCal < 250 && remainProt > 20) {
      out.add(const CoachInsight(
        type: CoachInsightType.balance,
        message: 'Protein is the bottleneck now.',
        actionHint: 'Skip another heavy carb meal. Finish with lean protein.',
      ));
    }

    if (patterns.tendsToMissProteinEarly && hour < 16 && pro < proteinPlan.minimumTarget * 0.45) {
      out.add(const CoachInsight(
        type: CoachInsightType.info,
        message: 'You usually leave too much protein for late evening.',
        actionHint: 'Fix it earlier today so dinner doesn’t have to do all the work.',
      ));
    }

    // ─ Under-eaten (early evening as soft signal, not hard cutoff) ───────────
    if (calRat < 0.48 && mealCount >= 2 && hour >= 18) {
      // They've eaten multiple times but still very low — probably not just
      // late-logging, likely genuinely under-eaten.
      out.add(CoachInsight(
        type:       CoachInsightType.underEaten,
        message:    '${cal.toInt()} kcal so far — there\'s still room.',
        actionHint: 'Add a proper meal. Don\'t chase a too-low calorie day.',
      ));
    }

    // ─ Workout-aware insights (injected at front — highest priority on gym days) ─
    if (todayWorkout != null && !todayWorkout.isEmpty) {
      final wi = _workoutInsight(
        pro: pro, cal: cal, proRat: proRat, calRat: calRat,
        target: target, hour: hour, workout: todayWorkout,
      );
      if (wi != null) out.insert(0, wi);
    }

    // ─ Limit to 2 insights — highest-signal wins ────────────────────────────
    return out.take(2).toList();
  }

  // ── Workout-nutrition bridge ──────────────────────────────────────────────
  //
  // Called only when the user has logged a workout session today.
  // Protein coaching becomes more urgent on training days.
  // Returns null when no specific workout insight is warranted.

  CoachInsight? _workoutInsight({
    required double pro,
    required double cal,
    required double proRat,
    required double calRat,
    required DayTarget target,
    required int    hour,
    required WorkoutSession workout,
  }) {
    // Priority 1: protein is critically low on a training day → recovery warning
    if (proRat < 0.65) {
      return CoachInsight(
        type:       CoachInsightType.protein,
        message:    'Training day — protein is at ${pro.toInt()}g, which is too low.',
        actionHint: 'Recovery and muscle retention both suffer. Hit at least ${(target.protein * 0.85).toInt()}g today.',
      );
    }
    if (workout.totalSets >= 12 && calRat < 0.7) {
      return CoachInsight(
        type: CoachInsightType.underEaten,
        message: 'You trained properly today but calories are still too low.',
        actionHint: 'Dinner should cover recovery — don’t leave this as a low-fuel training day.',
      );
    }
    // Priority 2: calorie deficit is severe late in the day → under-fueling
    if (calRat < 0.55 && hour >= 15) {
      return CoachInsight(
        type:       CoachInsightType.underEaten,
        message:    'You trained but have only consumed ${cal.toInt()} kcal today.',
        actionHint: 'Under-fueling on training days slows recovery. Eat a proper meal — prioritize protein.',
      );
    }
    // Priority 3: positive signal when diet aligns with training
    if (proRat >= 0.88 && calRat >= 0.80 && calRat <= 1.05) {
      return const CoachInsight(
        type:       CoachInsightType.info,
        message:    'Training day fueling looks solid.',
        actionHint: 'Calories and protein are both on track. Prioritise sleep and recovery tonight.',
      );
    }
    return null;
  }

  // ── Protein gap insight builders ──────────────────────────────────────────

  CoachInsight _severeProteinGap({
    required double pro,
    required double target,
    required double minimum,
    required double stretch,
    required double remainProt,
    required int    mealsLeft,
    required double protPerMeal,
    required double calRat,
    required bool recoverable,
  }) {
    if (mealsLeft == 0) {
      // Too late to do much — be honest about it
      return CoachInsight(
        type:    CoachInsightType.protein,
        message: 'Ended at ${pro.toInt()}g protein. Minimum today was ~${minimum.toInt()}g.',
        actionHint: 'Make tomorrow\'s breakfast protein-heavy to compensate.',
      );
    }

    if (!recoverable || protPerMeal > 40) {
      // Mathematically very hard to close gap this day
      return CoachInsight(
        type:       CoachInsightType.protein,
        message:    'You’re at ${pro.toInt()}g. Try to salvage at least ~${minimum.toInt()}g today.',
        actionHint: 'Ideal finish is ~${target.toInt()}–${stretch.toInt()}g, but focus on one protein-heavy meal now.',
      );
    }

    return CoachInsight(
      type:       CoachInsightType.protein,
      message:    'You’re at ${pro.toInt()}g. Try to reach at least ${minimum.toInt()}g today.',
      actionHint: calRat > 0.80
          ? 'Remaining budget: use it entirely on high-protein foods.'
          : 'Ideal finish today: ~${target.toInt()}–${stretch.toInt()}g. '
            'Next ${mealsLeft > 1 ? "$mealsLeft meals" : "meal"}: ~${protPerMeal.toInt()}g each.',
    );
  }

  CoachInsight _moderateProteinGap({
    required double pro,
    required double target,
    required double ideal,
    required double remainProt,
    required int    mealsLeft,
    required double protPerMeal,
  }) {
    if (mealsLeft <= 1) {
      // One shot left
      return CoachInsight(
        type:       CoachInsightType.protein,
        message:    'You’re at ${pro.toInt()}g. Try to finish at least ${target.toInt()}g today.',
        actionHint: 'One protein-focused meal (whey + tofu or paneer) closes it.',
      );
    }
    return CoachInsight(
      type:       CoachInsightType.protein,
      message:    'You’re at ${pro.toInt()}g. Minimum useful finish today: ~${target.toInt()}g.',
      actionHint: 'Ideal finish: ~${ideal.toInt()}g. ~${protPerMeal.toInt()}g per remaining meal keeps you on track.',
    );
  }

  _ProteinPlan _proteinPlan({
    required DayTarget target,
    required UserProfile? profile,
    required double currentProtein,
    required DateTime now,
    required int mealsLeft,
  }) {
    final weight = profile?.weight ?? (target.protein / 1.8);
    final goal = profile?.goal ?? '';
    final baseMinPerKg = switch (goal) {
      kMuscleGain => 1.65,
      kBodyRecomposition => 1.55,
      kFatLoss => 1.45,
      _ => 1.30,
    };
    final idealPerKg = switch (goal) {
      kMuscleGain => 2.0,
      kBodyRecomposition => 1.85,
      kFatLoss => 1.75,
      _ => 1.55,
    };
    final minimum = (weight * baseMinPerKg).clamp(target.protein * 0.72, target.protein * 0.92).toDouble();
    final ideal = (weight * idealPerKg).clamp(minimum + 8, target.protein * 1.02).toDouble();
    final stretch = (ideal + 10).clamp(ideal, target.protein * 1.1).toDouble();
    final remaining = (ideal - currentProtein).clamp(0, 300).toDouble();
    final recoverable = mealsLeft == 0 ? false : (remaining / mealsLeft) <= 38;
    return _ProteinPlan(
      minimumTarget: minimum,
      idealTarget: ideal,
      stretchTarget: stretch,
      isRecoverable: recoverable,
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  int _mealCount(DayLog log) {
    int count = 0;
    for (final s in MealSection.values) {
      count += log.entriesFor(s).length;
    }
    return count;
  }

  /// Estimates how many more meal opportunities exist today.
  /// Time is a SOFT signal — we also factor in how many meals have already been
  /// logged so we don't assume a user who logs late eats late.
  int _estimateMealsLeft(int hour, int mealCount) {
    // Rough typical meal slots: breakfast, lunch, evening snack, dinner, late
    // Remaining slot estimate based on time:
    final slotsLeft = switch (hour) {
      < 10  => 4, // morning — breakfast + lunch + snack + dinner ahead
      < 13  => 3, // late morning — lunch + snack + dinner
      < 16  => 2, // afternoon — snack + dinner
      < 20  => 1, // evening — dinner
      < 23  => 1, // night — late meal possible
      _     => 0, // very late — nothing realistic left
    };

    // Cap: don't claim more slots than is realistic given meals already logged.
    // If someone has already logged 4 meals, cap remaining at 1 regardless of time.
    final consumed = (mealCount / 2).ceil(); // rough consumed slot estimate
    return (slotsLeft - consumed + 2).clamp(0, 4).toInt();
  }
}

class _ProteinPlan {
  final double minimumTarget;
  final double idealTarget;
  final double stretchTarget;
  final bool isRecoverable;

  const _ProteinPlan({
    required this.minimumTarget,
    required this.idealTarget,
    required this.stretchTarget,
    required this.isRecoverable,
  });
}
