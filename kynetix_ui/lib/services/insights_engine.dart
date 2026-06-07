import 'dart:math' show max, min;
import '../models/day_log.dart';
import '../models/day_status.dart';
import '../models/insights_models.dart';
import '../models/workout_session.dart';
import '../models/user_profile.dart';
import '../services/nutrition_target_engine.dart';

// ─── AchievementRegistry ──────────────────────────────────────────────────────
class AchievementRegistry {
  static final Map<String, ({String title, String description, String emoji, AchievementCategory category})> _metadata = {
    'logged_first_day': (
      title: 'First Step',
      description: 'Logged your first meal! The journey begins.',
      emoji: '🌱',
      category: AchievementCategory.consistency,
    ),
    'logged_7_days': (
      title: 'Consistency Champion',
      description: 'Tracked your meals for 7 days. Keeping the habit alive!',
      emoji: '📅',
      category: AchievementCategory.consistency,
    ),
    'logged_30_days': (
      title: 'Habit Master',
      description: 'Tracked your meals for 30 days. You\'re building a real habit.',
      emoji: '📊',
      category: AchievementCategory.consistency,
    ),
    'logged_100_days': (
      title: 'Lifestyle Legend',
      description: '100 days of tracking! A lifestyle legend in the making.',
      emoji: '💯',
      category: AchievementCategory.consistency,
    ),
    'protein_target_3_row': (
      title: 'Fuel Streak',
      description: 'Hit your daily protein goal 3 days in a row!',
      emoji: '⚡',
      category: AchievementCategory.nutrition,
    ),
    'protein_target_7_row': (
      title: 'Protein Powerhouse',
      description: 'Met your daily protein target 7 days in a row!',
      emoji: '🔋',
      category: AchievementCategory.nutrition,
    ),
    'cal_adherence_week': (
      title: 'Perfect Calorie Week',
      description: 'Kept calories within targets at least 90% of the week.',
      emoji: '🎯',
      category: AchievementCategory.nutrition,
    ),
    'perfect_week': (
      title: 'Perfect Week',
      description: 'Hit both calorie and protein targets every single day Mon–Sun!',
      emoji: '✨',
      category: AchievementCategory.nutrition,
    ),
    'gym_3_row': (
      title: 'Workout Streak',
      description: 'Logged workouts 3 days in a row. Dedication in action!',
      emoji: '💪',
      category: AchievementCategory.training,
    ),
    'gym_30_total': (
      title: 'Gym Habit',
      description: 'Logged 30 workouts. Building strength, day by day.',
      emoji: '🏋️',
      category: AchievementCategory.training,
    ),
    'gym_100_total': (
      title: 'Iron Dedicated',
      description: 'Logged 100 workouts. Elite dedication to your training.',
      emoji: '🏆',
      category: AchievementCategory.training,
    ),
    'quality_score_80_week': (
      title: 'Mindful Eater',
      description: 'Averaged a high meal quality score of 80+ for a week.',
      emoji: '🥗',
      category: AchievementCategory.nutrition,
    ),
    'first_monthly_report': (
      title: 'Milestone Review',
      description: 'Generated your first monthly review. Let\'s see your progress!',
      emoji: '📈',
      category: AchievementCategory.milestone,
    ),
    'improvement_month': (
      title: 'Steady Progress',
      description: 'Showed a positive monthly calorie trend. Keep stepping up!',
      emoji: '🚀',
      category: AchievementCategory.milestone,
    ),
    'pb_protein_day': (
      title: 'Protein Peak',
      description: 'Recorded your highest protein intake in a single day!',
      emoji: '🥩',
      category: AchievementCategory.milestone,
    ),
  };

  static Achievement? fromId(String id, {DateTime? earnedAt, bool isNew = true}) {
    final meta = _metadata[id];
    if (meta == null) return null;
    return Achievement(
      id: id,
      title: meta.title,
      description: meta.description,
      emoji: meta.emoji,
      category: meta.category,
      earnedAt: earnedAt ?? DateTime.now(),
      isNew: isNew,
    );
  }

  static List<String> get allIds => _metadata.keys.toList();
}

// ─── InsightsEngine ───────────────────────────────────────────────────────────
class InsightsEngine {
  InsightsEngine._();

  // Helper: format a date key "yyyy-MM-dd"
  static String dateKeyOf(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // Helper: compute ISO week number
  static int isoWeekNumber(DateTime date) {
    final thurs = date.add(Duration(days: 4 - date.weekday));
    final firstDayOfYear = DateTime(thurs.year, 1, 1);
    final firstThurs = firstDayOfYear.add(Duration(days: 4 - firstDayOfYear.weekday));
    final diff = thurs.difference(firstThurs).inDays;
    return 1 + (diff / 7).round();
  }

  // Helper: compute ISO week year
  static int isoWeekYear(DateTime date) {
    final thurs = date.add(Duration(days: 4 - date.weekday));
    return thurs.year;
  }

  // Helper: weekKey format "yyyy-Www"
  static String weekKeyOf(DateTime date) {
    final y = isoWeekYear(date);
    final w = isoWeekNumber(date);
    final wStr = w.toString().padLeft(2, '0');
    return '$y-W$wStr';
  }

  // Helper: Monday of ISO week
  static DateTime mondayOfIsoWeek(int year, int week) {
    final jan4 = DateTime(year, 1, 4);
    final jan4Monday = jan4.subtract(Duration(days: jan4.weekday - 1));
    return jan4Monday.add(Duration(days: (week - 1) * 7));
  }

  // Helper: get monthKey "yyyy-MM"
  static String monthKeyOf(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}';
  }

  // ─── ConsistencyScore computation ───────────────────────────────────────────
  static ConsistencyScore computeScore({
    required double loggingConsistency,
    required double proteinAdherence,
    required double calorieAdherence,
    required double gymAttendance,
    required double mealQuality,
    required bool hasMealQuality,
  }) {
    double totalWeight = 100.0;
    double weightedSum = 0.0;

    weightedSum += loggingConsistency * 35.0;
    weightedSum += proteinAdherence * 25.0;
    weightedSum += calorieAdherence * 20.0;
    weightedSum += gymAttendance * 10.0;

    if (hasMealQuality) {
      weightedSum += mealQuality * 10.0;
    } else {
      totalWeight = 90.0;
    }

    final scoreValue = (weightedSum / totalWeight * 100).round().clamp(0, 100);

    return ConsistencyScore(
      loggingConsistency: loggingConsistency,
      proteinAdherence: proteinAdherence,
      calorieAdherence: calorieAdherence,
      gymAttendance: gymAttendance,
      mealQuality: mealQuality,
      score: scoreValue,
    );
  }

  // ─── Weekly Report computation ──────────────────────────────────────────────
  static WeeklyReport? computeWeek({
    required String weekKey,
    required UserProfile profile,
    required Map<String, DayLog> logs,
    required List<WorkoutSession> sessions,
    required WeeklyReport? priorWeek,
  }) {
    final parts = weekKey.split('-W');
    if (parts.length < 2) return null;
    final year = int.parse(parts[0]);
    final week = int.parse(parts[1]);
    final DateTime weekStart = mondayOfIsoWeek(year, week);

    final sessionsByDate = {for (final s in sessions) dateKeyOf(s.date): s};

    int loggedDaysCount = 0;
    int gymDaysCount = 0;
    double totalCals = 0.0;
    double totalPro = 0.0;
    double totalFib = 0.0;

    int proteinHitDays = 0;
    int calorieHitDays = 0;
    double mealQualitySum = 0.0;
    int scoredMealsCount = 0;

    double maxProteinValue = -1.0;
    String? bestDayKey;

    final outcomeCounts = <DayOutcome, int>{};

    for (int i = 0; i < 7; i++) {
      final date = weekStart.add(Duration(days: i));
      final dKey = dateKeyOf(date);
      final log = logs[dKey];

      if (log == null || log.isEmpty) {
        outcomeCounts[DayOutcome.unlogged] = (outcomeCounts[DayOutcome.unlogged] ?? 0) + 1;
        continue;
      }

      loggedDaysCount++;

      final session = sessionsByDate[dKey];
      final isGymDay = log.gymDay?.didGym == true;
      if (isGymDay) {
        gymDaysCount++;
      }

      final target = NutritionTargetEngine.instance.dayTarget(
        profile,
        isGymDay: isGymDay,
        session: session,
        workoutTypeName: log.gymDay?.workoutType?.displayName ?? log.gymDay?.splitDayName,
      );

      final cals = log.totalCaloriesMid;
      final pro = log.totalProteinMid;
      final fib = log.totalFiberMid;

      totalCals += cals;
      totalPro += pro;
      totalFib += fib;

      if (pro > maxProteinValue) {
        maxProteinValue = pro;
        bestDayKey = dKey;
      }

      final calRat = cals / target.calories.clamp(1.0, double.infinity);
      final proRat = pro / target.protein.clamp(1.0, double.infinity);

      if (proRat >= 0.90) {
        proteinHitDays++;
      }
      if (calRat >= 0.88 && calRat <= 1.08) {
        calorieHitDays++;
      }

      final dailyScore = log.dailyNutritionScore;
      if (dailyScore != null) {
        mealQualitySum += dailyScore;
        scoredMealsCount++;
      }

      final outcomeResult = DayStatusEngine.classify(log, target, now: date);
      outcomeCounts[outcomeResult.outcome] = (outcomeCounts[outcomeResult.outcome] ?? 0) + 1;
    }

    if (loggedDaysCount < 3) return null;

    final double avgCalories = totalCals / loggedDaysCount;
    final double avgProtein = totalPro / loggedDaysCount;
    final double avgFiber = totalFib / loggedDaysCount;

    final double loggingConsistency = loggedDaysCount / 7.0;
    final double proteinAdherence = proteinHitDays / loggedDaysCount;
    final double calorieAdherence = calorieHitDays / loggedDaysCount;

    final double expectedGymDays = (profile.workoutDaysMin + profile.workoutDaysMax) / 2.0;
    final double gymAttendance = (expectedGymDays > 0)
        ? (gymDaysCount / expectedGymDays).clamp(0.0, 1.0)
        : 1.0;

    final double mealQuality = (scoredMealsCount > 0) ? (mealQualitySum / scoredMealsCount) / 100.0 : 0.0;
    final bool hasMealQuality = scoredMealsCount > 0;

    final consistencyScore = computeScore(
      loggingConsistency: loggingConsistency,
      proteinAdherence: proteinAdherence,
      calorieAdherence: calorieAdherence,
      gymAttendance: gymAttendance,
      mealQuality: mealQuality,
      hasMealQuality: hasMealQuality,
    );

    // mostCommonOutcome calculation
    DayOutcome mostCommonOutcome = DayOutcome.incomplete;
    int maxCount = -1;
    for (final entry in outcomeCounts.entries) {
      if (entry.key != DayOutcome.unlogged && entry.value > maxCount) {
        maxCount = entry.value;
        mostCommonOutcome = entry.key;
      }
    }

    // Deltas
    PeriodDelta? deltaVsPrior;
    TopImprovement? topImprovement;
    final regressions = <RegressionAlert>[];

    if (priorWeek != null) {
      final pScore = priorWeek.consistencyScore;
      final proteinDelta = proteinAdherence - pScore.proteinAdherence;
      final calorieDelta = calorieAdherence - pScore.calorieAdherence;
      final loggingDelta = loggingConsistency - pScore.loggingConsistency;
      final qualityDelta = (scoredMealsCount > 0 && priorWeek.consistencyScore.mealQuality > 0)
          ? (mealQuality * 100.0 - pScore.mealQuality * 100.0)
          : null;
      final scoreDelta = consistencyScore.score - pScore.score;

      deltaVsPrior = PeriodDelta(
        proteinAdherenceDelta: proteinDelta,
        calorieAdherenceDelta: calorieDelta,
        loggingConsistencyDelta: loggingDelta,
        mealQualityDelta: qualityDelta,
        consistencyScoreDelta: scoreDelta,
      );

      // Top Improvement calculation (on 0-100 scale)
      double maxPositive = 0.0;
      ImprovementMetric? bestMetric;
      String label = '';

      if (scoreDelta > 0 && scoreDelta > maxPositive) {
        maxPositive = scoreDelta.toDouble();
        bestMetric = ImprovementMetric.consistencyScore;
        label = 'Consistency score improved most (+$scoreDelta pts)';
      }
      if (proteinDelta > 0 && (proteinDelta * 100.0) > maxPositive) {
        maxPositive = proteinDelta * 100.0;
        bestMetric = ImprovementMetric.proteinAdherence;
        label = 'Protein target hit rate improved most (+${(proteinDelta * 100.0).round()}%)';
      }
      if (calorieDelta > 0 && (calorieDelta * 100.0) > maxPositive) {
        maxPositive = calorieDelta * 100.0;
        bestMetric = ImprovementMetric.calorieAdherence;
        label = 'Calorie target hit rate improved most (+${(calorieDelta * 100.0).round()}%)';
      }
      if (loggingDelta > 0 && (loggingDelta * 100.0) > maxPositive) {
        maxPositive = loggingDelta * 100.0;
        bestMetric = ImprovementMetric.loggingConsistency;
        label = 'Tracking consistency improved most (+${(loggingDelta * 100.0).round()}%)';
      }
      if (qualityDelta != null && qualityDelta > 0 && qualityDelta > maxPositive) {
        maxPositive = qualityDelta;
        bestMetric = ImprovementMetric.mealQuality;
        label = 'Meal quality score improved most (+${qualityDelta.round()} pts)';
      }

      if (bestMetric != null) {
        double rawDelta = 0.0;
        switch (bestMetric) {
          case ImprovementMetric.consistencyScore:
            rawDelta = scoreDelta.toDouble();
            break;
          case ImprovementMetric.proteinAdherence:
            rawDelta = proteinDelta;
            break;
          case ImprovementMetric.calorieAdherence:
            rawDelta = calorieDelta;
            break;
          case ImprovementMetric.loggingConsistency:
            rawDelta = loggingDelta;
            break;
          case ImprovementMetric.mealQuality:
            rawDelta = qualityDelta!;
            break;
        }
        topImprovement = TopImprovement(
          metric: bestMetric,
          label: label,
          delta: rawDelta,
        );
      }

      // Regressions
      if (proteinDelta <= -0.10) {
        final mag = -proteinDelta;
        regressions.add(RegressionAlert(
          type: RegressionType.proteinConsistency,
          message: 'Protein consistency dropped ${(mag * 100).round()}% this week — consider adding a protein-rich meal earlier in the day.',
          magnitude: mag,
        ));
      }
      if (qualityDelta != null && qualityDelta <= -8.0) {
        final mag = -qualityDelta;
        regressions.add(RegressionAlert(
          type: RegressionType.mealQuality,
          message: 'Meal quality dipped ${mag.round()} points vs last week — more whole foods may help.',
          magnitude: mag,
        ));
      }
      if (loggingDelta <= -0.15) {
        final mag = -loggingDelta;
        regressions.add(RegressionAlert(
          type: RegressionType.loggingConsistency,
          message: 'Logging was less consistent this week — even rough estimates keep the trend data accurate.',
          magnitude: mag,
        ));
      }
      final gymAttendanceDelta = gymAttendance - pScore.gymAttendance;
      if (gymAttendanceDelta <= -0.20) {
        final mag = -gymAttendanceDelta;
        regressions.add(RegressionAlert(
          type: RegressionType.gymAttendance,
          message: 'Fewer sessions this week than last — recovery weeks are fine if intentional.',
          magnitude: mag,
        ));
      }
    }

    return WeeklyReport(
      weekKey: weekKey,
      weekStart: weekStart,
      consistencyScore: consistencyScore,
      avgCalories: avgCalories,
      avgProtein: avgProtein,
      avgFiber: avgFiber,
      gymDaysCount: gymDaysCount,
      loggedDaysCount: loggedDaysCount,
      bestDayKey: bestDayKey,
      mostCommonOutcome: mostCommonOutcome,
      deltaVsPrior: deltaVsPrior,
      topImprovement: topImprovement,
      regressions: regressions,
      computedAt: DateTime.now(),
    );
  }

  // ─── Monthly Report computation ─────────────────────────────────────────────
  static MonthlyReport? computeMonth({
    required String monthKey,
    required UserProfile profile,
    required Map<String, DayLog> logs,
    required List<WorkoutSession> sessions,
    required MonthlyReport? priorMonth,
  }) {
    final parts = monthKey.split('-');
    if (parts.length < 2) return null;
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);

    // Find first and last day of month
    final monthStart = DateTime(year, month, 1);
    final monthEnd = DateTime(year, month + 1, 1).subtract(const Duration(days: 1));
    final totalDaysInMonth = monthEnd.day;

    final sessionsByDate = {for (final s in sessions) dateKeyOf(s.date): s};

    int totalLoggedDays = 0;
    int totalGymDays = 0;
    double totalCals = 0.0;
    double totalPro = 0.0;

    int proteinHitDays = 0;
    int calorieHitDays = 0;
    double mealQualitySum = 0.0;
    int scoredMealsCount = 0;

    // Track weekly aggregates inside the month to find best / worst weeks
    final weeklyCals = <String, double>{};
    final weeklyLogged = <String, int>{};

    // For trendDirection: first 14 days vs last 14 days calorie adherence
    int first14Logged = 0;
    int first14Hits = 0;
    int last14Logged = 0;
    int last14Hits = 0;

    for (int day = 1; day <= totalDaysInMonth; day++) {
      final date = DateTime(year, month, day);
      final dKey = dateKeyOf(date);
      final log = logs[dKey];

      if (log == null || log.isEmpty) continue;

      totalLoggedDays++;

      final isGymDay = log.gymDay?.didGym == true;
      if (isGymDay) {
        totalGymDays++;
      }

      final session = sessionsByDate[dKey];
      final target = NutritionTargetEngine.instance.dayTarget(
        profile,
        isGymDay: isGymDay,
        session: session,
        workoutTypeName: log.gymDay?.workoutType?.displayName ?? log.gymDay?.splitDayName,
      );

      final cals = log.totalCaloriesMid;
      final pro = log.totalProteinMid;

      totalCals += cals;
      totalPro += pro;

      final calRat = cals / target.calories.clamp(1.0, double.infinity);
      final proRat = pro / target.protein.clamp(1.0, double.infinity);

      final calHit = calRat >= 0.88 && calRat <= 1.08;
      final proHit = proRat >= 0.90;

      if (proHit) {
        proteinHitDays++;
      }
      if (calHit) {
        calorieHitDays++;
      }

      final dailyScore = log.dailyNutritionScore;
      if (dailyScore != null) {
        mealQualitySum += dailyScore;
        scoredMealsCount++;
      }

      // Group by week key to find best/worst weeks
      final wKey = weekKeyOf(date);
      weeklyCals[wKey] = (weeklyCals[wKey] ?? 0.0) + cals;
      weeklyLogged[wKey] = (weeklyLogged[wKey] ?? 0) + 1;

      // Trend direction checks
      if (day <= 14) {
        first14Logged++;
        if (calHit) first14Hits++;
      }
      if (day > totalDaysInMonth - 14) {
        last14Logged++;
        if (calHit) last14Hits++;
      }
    }

    if (totalLoggedDays < 10) return null;

    final double avgCalories = totalCals / totalLoggedDays;
    final double avgProtein = totalPro / totalLoggedDays;

    final double loggingConsistency = totalLoggedDays / totalDaysInMonth.toDouble();
    final double proteinAdherence = proteinHitDays / totalLoggedDays;
    final double calorieAdherence = calorieHitDays / totalLoggedDays;

    final double expectedGymDays = (profile.workoutDaysMin + profile.workoutDaysMax) / 2.0 / 7.0 * totalDaysInMonth;
    final double gymAttendance = (expectedGymDays > 0)
        ? (totalGymDays / expectedGymDays).clamp(0.0, 1.0)
        : 1.0;

    final double mealQuality = (scoredMealsCount > 0) ? (mealQualitySum / scoredMealsCount) / 100.0 : 0.0;
    final bool hasMealQuality = scoredMealsCount > 0;

    final consistencyScore = computeScore(
      loggingConsistency: loggingConsistency,
      proteinAdherence: proteinAdherence,
      calorieAdherence: calorieAdherence,
      gymAttendance: gymAttendance,
      mealQuality: mealQuality,
      hasMealQuality: hasMealQuality,
    );

    // trendDirection
    String trendDirection = 'stable';
    if (first14Logged >= 1 && last14Logged >= 1) {
      final firstAdherence = first14Hits / first14Logged;
      final lastAdherence = last14Hits / last14Logged;
      final trendDelta = lastAdherence - firstAdherence;
      if (trendDelta >= 0.05) {
        trendDirection = 'improving';
      } else if (trendDelta <= -0.05) {
        trendDirection = 'declining';
      }
    }

    // Best / worst week by average calories (closest to average targets, or simply highest logged days / calorie adherence)
    // Spec asks: bestWeekKey and worstWeekKey. Let's find week key with highest and lowest average calorie adherence or consistency
    String? bestWeekKey;
    String? worstWeekKey;
    double maxWeekCalAdh = -1.0;
    double minWeekCalAdh = 999.0;

    for (final wKey in weeklyLogged.keys) {
      // Find logged days in this week within this month
      int loggedDaysInWeek = weeklyLogged[wKey] ?? 0;
      if (loggedDaysInWeek == 0) continue;
      
      // Calculate calorie adherence for this week within this month
      int hits = 0;
      for (int day = 1; day <= totalDaysInMonth; day++) {
        final date = DateTime(year, month, day);
        if (weekKeyOf(date) != wKey) continue;
        final dKey = dateKeyOf(date);
        final log = logs[dKey];
        if (log == null || log.isEmpty) continue;
        final session = sessionsByDate[dKey];
        final isGymDay = log.gymDay?.didGym == true;
        final target = NutritionTargetEngine.instance.dayTarget(
          profile,
          isGymDay: isGymDay,
          session: session,
          workoutTypeName: log.gymDay?.workoutType?.displayName ?? log.gymDay?.splitDayName,
        );
        final calRat = log.totalCaloriesMid / target.calories.clamp(1.0, double.infinity);
        if (calRat >= 0.88 && calRat <= 1.08) {
          hits++;
        }
      }
      final weekAdh = hits / loggedDaysInWeek;
      if (weekAdh > maxWeekCalAdh) {
        maxWeekCalAdh = weekAdh;
        bestWeekKey = wKey;
      }
      if (weekAdh < minWeekCalAdh) {
        minWeekCalAdh = weekAdh;
        worstWeekKey = wKey;
      }
    }

    // Deltas vs Prior Month
    PeriodDelta? deltaVsPrior;
    TopImprovement? topImprovement;
    final regressions = <RegressionAlert>[];

    if (priorMonth != null) {
      final pScore = priorMonth.consistencyScore;
      final proteinDelta = proteinAdherence - pScore.proteinAdherence;
      final calorieDelta = calorieAdherence - pScore.calorieAdherence;
      final loggingDelta = loggingConsistency - pScore.loggingConsistency;
      final qualityDelta = (scoredMealsCount > 0 && priorMonth.consistencyScore.mealQuality > 0)
          ? (mealQuality * 100.0 - pScore.mealQuality * 100.0)
          : null;
      final scoreDelta = consistencyScore.score - pScore.score;

      deltaVsPrior = PeriodDelta(
        proteinAdherenceDelta: proteinDelta,
        calorieAdherenceDelta: calorieDelta,
        loggingConsistencyDelta: loggingDelta,
        mealQualityDelta: qualityDelta,
        consistencyScoreDelta: scoreDelta,
      );

      // Top Improvement calculation
      double maxPositive = 0.0;
      ImprovementMetric? bestMetric;
      String label = '';

      if (scoreDelta > 0 && scoreDelta > maxPositive) {
        maxPositive = scoreDelta.toDouble();
        bestMetric = ImprovementMetric.consistencyScore;
        label = 'Consistency score improved most (+$scoreDelta pts)';
      }
      if (proteinDelta > 0 && (proteinDelta * 100.0) > maxPositive) {
        maxPositive = proteinDelta * 100.0;
        bestMetric = ImprovementMetric.proteinAdherence;
        label = 'Protein target hit rate improved most (+${(proteinDelta * 100.0).round()}%)';
      }
      if (calorieDelta > 0 && (calorieDelta * 100.0) > maxPositive) {
        maxPositive = calorieDelta * 100.0;
        bestMetric = ImprovementMetric.calorieAdherence;
        label = 'Calorie target hit rate improved most (+${(calorieDelta * 100.0).round()}%)';
      }
      if (loggingDelta > 0 && (loggingDelta * 100.0) > maxPositive) {
        maxPositive = loggingDelta * 100.0;
        bestMetric = ImprovementMetric.loggingConsistency;
        label = 'Tracking consistency improved most (+${(loggingDelta * 100.0).round()}%)';
      }
      if (qualityDelta != null && qualityDelta > 0 && qualityDelta > maxPositive) {
        maxPositive = qualityDelta;
        bestMetric = ImprovementMetric.mealQuality;
        label = 'Meal quality score improved most (+${qualityDelta.round()} pts)';
      }

      if (bestMetric != null) {
        double rawDelta = 0.0;
        switch (bestMetric) {
          case ImprovementMetric.consistencyScore:
            rawDelta = scoreDelta.toDouble();
            break;
          case ImprovementMetric.proteinAdherence:
            rawDelta = proteinDelta;
            break;
          case ImprovementMetric.calorieAdherence:
            rawDelta = calorieDelta;
            break;
          case ImprovementMetric.loggingConsistency:
            rawDelta = loggingDelta;
            break;
          case ImprovementMetric.mealQuality:
            rawDelta = qualityDelta!;
            break;
        }
        topImprovement = TopImprovement(
          metric: bestMetric,
          label: label,
          delta: rawDelta,
        );
      }

      // Regressions
      if (proteinDelta <= -0.10) {
        final mag = -proteinDelta;
        regressions.add(RegressionAlert(
          type: RegressionType.proteinConsistency,
          message: 'Protein consistency dropped ${(mag * 100).round()}% this month — consider adding a protein-rich meal earlier in the day.',
          magnitude: mag,
        ));
      }
      if (qualityDelta != null && qualityDelta <= -8.0) {
        final mag = -qualityDelta;
        regressions.add(RegressionAlert(
          type: RegressionType.mealQuality,
          message: 'Meal quality dipped ${mag.round()} points vs last month — more whole foods may help.',
          magnitude: mag,
        ));
      }
      if (loggingDelta <= -0.15) {
        final mag = -loggingDelta;
        regressions.add(RegressionAlert(
          type: RegressionType.loggingConsistency,
          message: 'Logging was less consistent this month — even rough estimates keep the trend data accurate.',
          magnitude: mag,
        ));
      }
      final gymAttendanceDelta = gymAttendance - pScore.gymAttendance;
      if (gymAttendanceDelta <= -0.20) {
        final mag = -gymAttendanceDelta;
        regressions.add(RegressionAlert(
          type: RegressionType.gymAttendance,
          message: 'Fewer sessions this month than last — recovery weeks are fine if intentional.',
          magnitude: mag,
        ));
      }
    }

    return MonthlyReport(
      monthKey: monthKey,
      consistencyScore: consistencyScore,
      avgCalories: avgCalories,
      avgProtein: avgProtein,
      totalGymDays: totalGymDays,
      totalLoggedDays: totalLoggedDays,
      bestWeekKey: bestWeekKey,
      worstWeekKey: worstWeekKey,
      trendDirection: trendDirection,
      deltaVsPrior: deltaVsPrior,
      topImprovement: topImprovement,
      regressions: regressions,
      computedAt: DateTime.now(),
    );
  }

  // ─── Yearly Report computation ──────────────────────────────────────────────
  static YearlyReport? computeYear({
    required String yearKey,
    required UserProfile profile,
    required Map<String, DayLog> logs,
    required Map<String, MonthlyReport> monthlyCache,
  }) {
    int totalLoggedDays = 0;
    int totalGymDays = 0;
    double totalCals = 0.0;
    double totalPro = 0.0;

    int scoredMealsCount = 0;
    double mealQualitySum = 0.0;
    int proteinHitDays = 0;
    int calorieHitDays = 0;

    final monthlyScores = <String, int>{};
    String? bestMonthKey;
    String? worstMonthKey;
    int maxMonthScore = -1;
    int minMonthScore = 999;

    // We aggregate monthly scores directly from the monthly reports in monthlyCache that match the yearKey
    for (int month = 1; month <= 12; month++) {
      final mKey = '$yearKey-${month.toString().padLeft(2, '0')}';
      final mReport = monthlyCache[mKey];
      if (mReport == null) continue;

      final score = mReport.consistencyScore.score;
      monthlyScores[mKey] = score;

      if (score > maxMonthScore) {
        maxMonthScore = score;
        bestMonthKey = mKey;
      }
      if (score < minMonthScore) {
        minMonthScore = score;
        worstMonthKey = mKey;
      }

      totalLoggedDays += mReport.totalLoggedDays;
      totalGymDays += mReport.totalGymDays;

      // Weighted averages of macros based on logged days in each month
      totalCals += mReport.avgCalories * mReport.totalLoggedDays;
      totalPro += mReport.avgProtein * mReport.totalLoggedDays;

      proteinHitDays += (mReport.consistencyScore.proteinAdherence * mReport.totalLoggedDays).round();
      calorieHitDays += (mReport.consistencyScore.calorieAdherence * mReport.totalLoggedDays).round();
      mealQualitySum += mReport.consistencyScore.mealQuality * mReport.totalLoggedDays;
      scoredMealsCount += mReport.totalLoggedDays;
    }

    if (totalLoggedDays < 60) return null;

    final avgCalories = totalLoggedDays > 0 ? totalCals / totalLoggedDays : 0.0;
    final avgProtein = totalLoggedDays > 0 ? totalPro / totalLoggedDays : 0.0;

    final totalDaysInYear = DateTime(int.parse(yearKey) + 1, 1, 1).difference(DateTime(int.parse(yearKey), 1, 1)).inDays;
    final double loggingConsistency = totalLoggedDays / totalDaysInYear.toDouble();
    final double proteinAdherence = totalLoggedDays > 0 ? proteinHitDays / totalLoggedDays : 0.0;
    final double calorieAdherence = totalLoggedDays > 0 ? calorieHitDays / totalLoggedDays : 0.0;

    final double expectedGymDays = (profile.workoutDaysMin + profile.workoutDaysMax) / 2.0 / 7.0 * totalDaysInYear;
    final double gymAttendance = (expectedGymDays > 0)
        ? (totalGymDays / expectedGymDays).clamp(0.0, 1.0)
        : 1.0;

    final double mealQuality = totalLoggedDays > 0 ? mealQualitySum / totalLoggedDays : 0.0;

    final consistencyScore = computeScore(
      loggingConsistency: loggingConsistency,
      proteinAdherence: proteinAdherence,
      calorieAdherence: calorieAdherence,
      gymAttendance: gymAttendance,
      mealQuality: mealQuality,
      hasMealQuality: scoredMealsCount > 0,
    );

    return YearlyReport(
      yearKey: yearKey,
      consistencyScore: consistencyScore,
      avgCalories: avgCalories,
      avgProtein: avgProtein,
      totalGymDays: totalGymDays,
      totalLoggedDays: totalLoggedDays,
      monthlyScores: monthlyScores,
      bestMonthKey: bestMonthKey,
      worstMonthKey: worstMonthKey,
      computedAt: DateTime.now(),
    );
  }

  // ─── Personal Bests computation ─────────────────────────────────────────────
  static PersonalBests computePersonalBests({
    required UserProfile profile,
    required Map<String, DayLog> logs,
    required Map<String, WeeklyReport> weeklyCache,
    required Map<String, MonthlyReport> monthlyCache,
  }) {
    double? highestProteinDay;
    String? highestProteinDayKey;

    int currentStreak = 0;
    int longestLoggingStreak = 0;

    // Single O(N) scan of dayLogStore keys sorted chronologically
    final sortedKeys = logs.keys.toList()..sort();
    DateTime? prevDate;

    for (final dateStr in sortedKeys) {
      final log = logs[dateStr]!;
      if (log.isEmpty) {
        currentStreak = 0;
        prevDate = null;
        continue;
      }

      final protein = log.totalProteinMid;
      if (highestProteinDay == null || protein > highestProteinDay) {
        highestProteinDay = protein;
        highestProteinDayKey = dateStr;
      }

      final parsed = DateTime.tryParse(dateStr);
      if (parsed != null) {
        if (prevDate == null) {
          currentStreak = 1;
        } else {
          final diff = parsed.difference(prevDate).inDays;
          if (diff == 1) {
            currentStreak++;
          } else if (diff > 1) {
            currentStreak = 1;
          }
        }
        prevDate = parsed;
        if (currentStreak > longestLoggingStreak) {
          longestLoggingStreak = currentStreak;
        }
      }
    }

    // Best meal quality week
    int? bestMealQualityWeekScore;
    String? bestMealQualityWeekKey;
    for (final entry in weeklyCache.entries) {
      final score = entry.value.consistencyScore.score;
      if (bestMealQualityWeekScore == null || score > bestMealQualityWeekScore) {
        bestMealQualityWeekScore = score;
        bestMealQualityWeekKey = entry.key;
      }
    }

    // Best consistent month
    int? mostConsistentMonthScore;
    String? mostConsistentMonthKey;
    for (final entry in monthlyCache.entries) {
      final score = entry.value.consistencyScore.score;
      if (mostConsistentMonthScore == null || score > mostConsistentMonthScore) {
        mostConsistentMonthScore = score;
        mostConsistentMonthKey = entry.key;
      }
    }

    // Steps PB
    int? highestAvgStepsWeek = profile.averageDailySteps;
    String? highestAvgStepsWeekKey;

    return PersonalBests(
      highestProteinDay: highestProteinDay,
      highestProteinDayKey: highestProteinDayKey,
      bestMealQualityWeekScore: bestMealQualityWeekScore,
      bestMealQualityWeekKey: bestMealQualityWeekKey,
      longestLoggingStreak: longestLoggingStreak,
      highestAvgStepsWeek: highestAvgStepsWeek,
      highestAvgStepsWeekKey: highestAvgStepsWeekKey,
      mostConsistentMonthScore: mostConsistentMonthScore,
      mostConsistentMonthKey: mostConsistentMonthKey,
      computedAt: DateTime.now(),
    );
  }

  // ─── Achievement evaluation ─────────────────────────────────────────────────
  static List<Achievement> evaluateAchievements({
    required Map<String, DayLog> logs,
    required UserProfile profile,
    required List<WorkoutSession> sessions,
    required List<Achievement> existingAchievements,
    required List<WeeklyReport> weeklyReports,
    required List<MonthlyReport> monthlyReports,
    required PersonalBests? currentPBs,
  }) {
    final earnedIds = existingAchievements.map((a) => a.id).toSet();
    final newEarned = <Achievement>[];

    int totalLoggedDays = 0;
    int totalGymDays = 0;
    int consecutiveProteinHits = 0;
    int consecutiveGymDays = 0;

    final sortedKeys = logs.keys.toList()..sort();
    final sessionsByDate = {for (final s in sessions) dateKeyOf(s.date): s};

    for (final dateStr in sortedKeys) {
      final log = logs[dateStr]!;
      if (log.isEmpty) {
        consecutiveProteinHits = 0;
        consecutiveGymDays = 0;
        continue;
      }

      totalLoggedDays++;
      final parsedDate = DateTime.tryParse(dateStr) ?? DateTime.now();

      final isGymDay = log.gymDay?.didGym == true;
      if (isGymDay) {
        totalGymDays++;
        consecutiveGymDays++;
      } else {
        consecutiveGymDays = 0;
      }

      final session = sessionsByDate[dateStr];
      final target = NutritionTargetEngine.instance.dayTarget(
        profile,
        isGymDay: isGymDay,
        session: session,
        workoutTypeName: log.gymDay?.workoutType?.displayName ?? log.gymDay?.splitDayName,
      );

      final proRat = log.totalProteinMid / target.protein.clamp(1.0, double.infinity);
      final calRat = log.totalCaloriesMid / target.calories.clamp(1.0, double.infinity);

      final proteinHit = proRat >= 0.90;
      final calHit = calRat >= 0.88 && calRat <= 1.08;

      if (proteinHit) {
        consecutiveProteinHits++;
      } else {
        consecutiveProteinHits = 0;
      }

      // Award logged-days milestones
      if (totalLoggedDays >= 1 && !earnedIds.contains('logged_first_day')) {
        earnedIds.add('logged_first_day');
        newEarned.add(AchievementRegistry.fromId('logged_first_day', earnedAt: parsedDate)!);
      }
      if (totalLoggedDays >= 7 && !earnedIds.contains('logged_7_days')) {
        earnedIds.add('logged_7_days');
        newEarned.add(AchievementRegistry.fromId('logged_7_days', earnedAt: parsedDate)!);
      }
      if (totalLoggedDays >= 30 && !earnedIds.contains('logged_30_days')) {
        earnedIds.add('logged_30_days');
        newEarned.add(AchievementRegistry.fromId('logged_30_days', earnedAt: parsedDate)!);
      }
      if (totalLoggedDays >= 100 && !earnedIds.contains('logged_100_days')) {
        earnedIds.add('logged_100_days');
        newEarned.add(AchievementRegistry.fromId('logged_100_days', earnedAt: parsedDate)!);
      }

      // Protein streaks
      if (consecutiveProteinHits >= 3 && !earnedIds.contains('protein_target_3_row')) {
        earnedIds.add('protein_target_3_row');
        newEarned.add(AchievementRegistry.fromId('protein_target_3_row', earnedAt: parsedDate)!);
      }
      if (consecutiveProteinHits >= 7 && !earnedIds.contains('protein_target_7_row')) {
        earnedIds.add('protein_target_7_row');
        newEarned.add(AchievementRegistry.fromId('protein_target_7_row', earnedAt: parsedDate)!);
      }

      // Gym streaks
      if (consecutiveGymDays >= 3 && !earnedIds.contains('gym_3_row')) {
        earnedIds.add('gym_3_row');
        newEarned.add(AchievementRegistry.fromId('gym_3_row', earnedAt: parsedDate)!);
      }
      if (totalGymDays >= 30 && !earnedIds.contains('gym_30_total')) {
        earnedIds.add('gym_30_total');
        newEarned.add(AchievementRegistry.fromId('gym_30_total', earnedAt: parsedDate)!);
      }
      if (totalGymDays >= 100 && !earnedIds.contains('gym_100_total')) {
        earnedIds.add('gym_100_total');
        newEarned.add(AchievementRegistry.fromId('gym_100_total', earnedAt: parsedDate)!);
      }

      // Protein Peak pb_protein_day (first time protein PB is recorded)
      if (!earnedIds.contains('pb_protein_day') && log.totalProteinMid > 0) {
        earnedIds.add('pb_protein_day');
        newEarned.add(AchievementRegistry.fromId('pb_protein_day', earnedAt: parsedDate)!);
      }
    }

    // Weekly reports milestones
    for (final report in weeklyReports) {
      final parsedDate = report.computedAt;

      if (report.consistencyScore.calorieAdherence >= 0.90 && !earnedIds.contains('cal_adherence_week')) {
        earnedIds.add('cal_adherence_week');
        newEarned.add(AchievementRegistry.fromId('cal_adherence_week', earnedAt: parsedDate)!);
      }

      if (report.loggedDaysCount == 7) {
        bool perfect = true;
        for (int i = 0; i < 7; i++) {
          final date = report.weekStart.add(Duration(days: i));
          final dKey = dateKeyOf(date);
          final log = logs[dKey];
          if (log == null || log.isEmpty) {
            perfect = false;
            break;
          }
          final session = sessionsByDate[dKey];
          final target = NutritionTargetEngine.instance.dayTarget(
            profile,
            isGymDay: log.gymDay?.didGym == true,
            session: session,
            workoutTypeName: log.gymDay?.workoutType?.displayName ?? log.gymDay?.splitDayName,
          );
          final cRat = log.totalCaloriesMid / target.calories.clamp(1.0, double.infinity);
          final pRat = log.totalProteinMid / target.protein.clamp(1.0, double.infinity);
          final pHit = pRat >= 0.90;
          final cHit = cRat >= 0.88 && cRat <= 1.08;
          if (!pHit || !cHit) {
            perfect = false;
            break;
          }
        }
        if (perfect && !earnedIds.contains('perfect_week')) {
          earnedIds.add('perfect_week');
          newEarned.add(AchievementRegistry.fromId('perfect_week', earnedAt: parsedDate)!);
        }
      }

      if (report.consistencyScore.mealQuality >= 0.80 && !earnedIds.contains('quality_score_80_week')) {
        earnedIds.add('quality_score_80_week');
        newEarned.add(AchievementRegistry.fromId('quality_score_80_week', earnedAt: parsedDate)!);
      }
    }

    // Monthly reports milestones
    for (final report in monthlyReports) {
      final parsedDate = report.computedAt;

      if (!earnedIds.contains('first_monthly_report')) {
        earnedIds.add('first_monthly_report');
        newEarned.add(AchievementRegistry.fromId('first_monthly_report', earnedAt: parsedDate)!);
      }

      if (report.trendDirection == 'improving' && !earnedIds.contains('improvement_month')) {
        earnedIds.add('improvement_month');
        newEarned.add(AchievementRegistry.fromId('improvement_month', earnedAt: parsedDate)!);
      }
    }

    // Combined earned achievements: existing + newly earned
    final results = List<Achievement>.from(existingAchievements)..addAll(newEarned);
    return results;
  }

  // ─── Achievement Progress computation ───────────────────────────────────────
  static List<AchievementProgress> computeProgress(
    List<Achievement> earned,
    Map<String, DayLog> logs,
    UserProfile profile,
    List<WorkoutSession> sessions,
  ) {
    final earnedIds = earned.map((a) => a.id).toSet();

    int totalLogged = 0;
    int totalGym = 0;
    int maxProStreak = 0;
    int currentProStreak = 0;

    final sortedKeys = logs.keys.toList()..sort();
    final sessionsByDate = {for (final s in sessions) dateKeyOf(s.date): s};

    for (final dateStr in sortedKeys) {
      final log = logs[dateStr]!;
      if (log.isEmpty) {
        currentProStreak = 0;
        continue;
      }
      totalLogged++;

      if (log.gymDay?.didGym == true) {
        totalGym++;
      }

      final session = sessionsByDate[dateStr];
      final target = NutritionTargetEngine.instance.dayTarget(
        profile,
        isGymDay: log.gymDay?.didGym == true,
        session: session,
        workoutTypeName: log.gymDay?.workoutType?.displayName ?? log.gymDay?.splitDayName,
      );

      final pRat = log.totalProteinMid / target.protein.clamp(1.0, double.infinity);
      if (pRat >= 0.90) {
        currentProStreak++;
        if (currentProStreak > maxProStreak) {
          maxProStreak = currentProStreak;
        }
      } else {
        currentProStreak = 0;
      }
    }

    final progressItems = <AchievementProgress>[];

    // Helper to add if not earned
    void addProgress(String id, int current, int target, String label) {
      if (!earnedIds.contains(id)) {
        progressItems.add(AchievementProgress(
          id: id,
          current: current,
          target: target,
          label: label,
        ));
      }
    }

    addProgress('logged_7_days', min(totalLogged, 7), 7, '$totalLogged / 7 days logged');
    addProgress('logged_30_days', min(totalLogged, 30), 30, '$totalLogged / 30 days logged');
    addProgress('logged_100_days', min(totalLogged, 100), 100, '$totalLogged / 100 days logged');

    addProgress('protein_target_3_row', min(maxProStreak, 3), 3, '$maxProStreak / 3 days in a row');
    addProgress('protein_target_7_row', min(maxProStreak, 7), 7, '$maxProStreak / 7 days in a row');

    addProgress('gym_30_total', min(totalGym, 30), 30, '$totalGym / 30 sessions');
    addProgress('gym_100_total', min(totalGym, 100), 100, '$totalGym / 100 sessions');

    // Sort progress items descending by fraction completed
    progressItems.sort((a, b) => b.fraction.compareTo(a.fraction));

    return progressItems;
  }
}
