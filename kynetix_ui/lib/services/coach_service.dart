import 'dart:math' as math;
import '../models/coach_insight.dart';
import '../models/day_log.dart';
import '../models/workout_session.dart';
import '../models/user_profile.dart';
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
          message:    'Protein is in a good place.',
          actionHint: 'About ${remainCal.round()} kcal left. Eat them however you like.',
        ));
      }
    }

    // ─ Calorie analysis ──────────────────────────────────────────────────────

    if (calRat > 1.12) {
      out.add(CoachInsight(
        type:       CoachInsightType.overGoal,
        message:    '${cal.round()} kcal, over today\'s target.',
        actionHint: proRat >= 0.85
            ? 'Protein is done too. No stress, tomorrow\'s a fresh page.'
            : 'If you eat again, keep it light and high in protein.',
      ));
    } else if (calRat > 0.97 && proRat >= 0.85) {
      out.add(const CoachInsight(
        type:       CoachInsightType.info,
        message:    'Calories are almost at target.',
        actionHint: 'If you\'re still hungry, go for lean protein over a heavy carb meal.',
      ));
    } else if (calRat > 0.97 && proRat < 0.80) {
      // Calories at limit but protein still low — classic mess-food trap
      out.add(CoachInsight(
        type:       CoachInsightType.balance,
        message:    'Calories are mostly covered, but protein is light at ${pro.round()} g.',
        actionHint: 'Spend what\'s left on whey, curd or egg whites.',
      ));
    }

    if (remainCal < 250 && remainProt > 20) {
      out.add(const CoachInsight(
        type: CoachInsightType.balance,
        message: 'Protein is the bottleneck now.',
        actionHint: 'Skip another heavy carb meal and finish with lean protein.',
      ));
    }

    if (patterns.tendsToMissProteinEarly && hour < 16 && pro < proteinPlan.minimumTarget * 0.45) {
      out.add(const CoachInsight(
        type: CoachInsightType.info,
        message: 'You usually leave too much protein for late evening.',
        actionHint: 'Get some in earlier today so dinner doesn\'t have to do all the work.',
      ));
    }

    // ─ Under-eaten (early evening as soft signal, not hard cutoff) ───────────
    if (calRat < 0.48 && mealCount >= 2 && hour >= 18) {
      // They've eaten multiple times but still very low — probably not just
      // late-logging, likely genuinely under-eaten.
      out.add(CoachInsight(
        type:       CoachInsightType.underEaten,
        message:    '${cal.round()} kcal so far. There\'s still room.',
        actionHint: 'Have a proper meal. A very low day isn\'t the goal.',
      ));
    }

    // ─ Workout-aware insights (injected at front — highest priority on gym days) ─
    if (todayWorkout != null && !todayWorkout.isEmpty) {
      final wi = _workoutInsight(
        pro: pro, cal: cal, proRat: proRat, calRat: calRat,
        target: target, hour: hour, workout: todayWorkout,
        plan: proteinPlan,
      );
      if (wi != null) {
        // One protein recommendation per day: the training-day note already
        // carries the numbers, so drop any other protein note.
        if (wi.type == CoachInsightType.protein) {
          out.removeWhere((i) => i.type == CoachInsightType.protein);
        }
        out.insert(0, wi);
      }
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
    required _ProteinPlan plan,
  }) {
    // Priority 1: protein is critically low on a training day → recovery note.
    // Uses the same floor and ideal as every other protein note.
    if (proRat < 0.65) {
      return CoachInsight(
        type:       CoachInsightType.protein,
        message:    'You trained today and protein is at ${pro.round()} g.',
        actionHint: 'Aim for at least ${plan.minimumTarget.round()} g by tonight; '
            '${plan.idealTarget.round()} g is ideal. One protein-heavy meal does most of it.',
      );
    }
    if (workout.totalSets >= 12 && calRat < 0.7) {
      return const CoachInsight(
        type: CoachInsightType.underEaten,
        message: 'Solid session, but calories are still low.',
        actionHint: 'Let dinner cover recovery so this isn\'t a low-fuel training day.',
      );
    }
    // Priority 2: calorie deficit is severe late in the day → under-fueling
    if (calRat < 0.55 && hour >= 15) {
      return CoachInsight(
        type:       CoachInsightType.underEaten,
        message:    'You trained, and you\'re at ${cal.round()} kcal so far.',
        actionHint: 'Under-fuelling slows recovery. Have a proper meal with protein in it.',
      );
    }
    // Priority 3: positive signal when diet aligns with training
    if (proRat >= 0.88 && calRat >= 0.80 && calRat <= 1.05) {
      return const CoachInsight(
        type:       CoachInsightType.info,
        message:    'Training-day fuel looks solid.',
        actionHint: 'Calories and protein are both on track. Sleep well tonight.',
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
        message: 'Finished at ${pro.round()} g protein, under the ${minimum.round()} g floor.',
        actionHint: 'Make tomorrow\'s breakfast protein-heavy.',
      );
    }

    if (!recoverable || protPerMeal > 40) {
      // Mathematically very hard to close gap this day
      return CoachInsight(
        type:       CoachInsightType.protein,
        message:    'You\'re at ${pro.round()} g protein. Aim for at least ${minimum.round()} g today.',
        actionHint: 'One protein-heavy meal now does the most. ${target.round()} g is ideal.',
      );
    }

    return CoachInsight(
      type:       CoachInsightType.protein,
      message:    'You\'re at ${pro.round()} g protein. Aim for at least ${minimum.round()} g today.',
      actionHint: calRat > 0.80
          ? 'Spend what\'s left of your calories on protein: dal, paneer, curd or whey.'
          : '${target.round()} g is ideal. That\'s about ${protPerMeal.round()} g '
            '${mealsLeft > 1 ? 'in each of your next $mealsLeft meals' : 'in your next meal'}.',
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
        message:    'You\'re at ${pro.round()} g protein. Aim for at least ${target.round()} g today.',
        actionHint: 'One protein-focused meal, like paneer or whey with curd, closes it.',
      );
    }
    return CoachInsight(
      type:       CoachInsightType.protein,
      message:    'You\'re at ${pro.round()} g protein. Aim for at least ${target.round()} g today.',
      actionHint: '${ideal.round()} g is ideal. About ${protPerMeal.round()} g per meal from here keeps you on track.',
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
      kBulk          => 1.65,
      kLeanBulk      => 1.60,
      kRecomposition => 1.55,
      kFatLoss       => 1.45,
      _              => 1.30,
    };
    final idealPerKg = switch (goal) {
      kBulk          => 2.0,
      kLeanBulk      => 1.9,
      kRecomposition => 1.85,
      kFatLoss       => 1.75,
      _              => 1.55,
    };
    final minimum = (weight * baseMinPerKg).clamp(target.protein * 0.72, target.protein * 0.92).toDouble();
    // clamp() throws when lower > upper, which happens for small targets
    // (e.g. a 70 g custom target): keep the upper bound >= the lower bound.
    final idealLo = minimum + 8;
    final idealHi = math.max(idealLo, target.protein * 1.02);
    final ideal = (weight * idealPerKg).clamp(idealLo, idealHi).toDouble();
    final stretchHi = math.max(ideal, target.protein * 1.1);
    final stretch = (ideal + 10).clamp(ideal, stretchHi).toDouble();
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
      < 10  => 4, // morning, breakfast + lunch + snack + dinner ahead
      < 13  => 3, // late morning, lunch + snack + dinner
      < 16  => 2, // afternoon, snack + dinner
      < 20  => 1, // evening, dinner
      < 23  => 1, // night, late meal possible
      _     => 0, // very late, nothing realistic left
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
