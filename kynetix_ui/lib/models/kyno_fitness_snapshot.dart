/// Single exercise longitudinal progress summary.
class ExerciseProgressSummary {
  final String exerciseId;
  final String canonicalName;
  final String muscleGroup;
  final int totalSessions;
  final List<String> recentWorkingSets; // e.g. ["25kg × 8", "25kg × 8", "25kg × 8"]
  final List<double> recentWeights;
  final List<int> recentReps;
  final List<double> e1rmHistory;
  final double? highestE1rm;
  final bool isStalled;
  final String? stallReason;
  final String trend; // "improving", "flat", "declining", "insufficient_data"
  final DateTime? lastTrainedDate;

  const ExerciseProgressSummary({
    required this.exerciseId,
    required this.canonicalName,
    required this.muscleGroup,
    required this.totalSessions,
    required this.recentWorkingSets,
    required this.recentWeights,
    required this.recentReps,
    required this.e1rmHistory,
    this.highestE1rm,
    required this.isStalled,
    this.stallReason,
    required this.trend,
    this.lastTrainedDate,
  });
}

/// Derived transient multi-window snapshot of the authenticated user's fitness history.
class KynoUserFitnessSnapshot {
  final String? userId;
  final DateTime computedAt;

  // Profile & Goals
  final String userName;
  final String userGoal;
  final double? userWeightKg;
  final double targetDailyCalories;
  final double targetDailyProtein;

  // Training Longitudinal Metrics
  final int totalWorkoutsLogged;
  final double workoutsPerWeekLast14Days;
  final double workoutsPerWeekBaseline; // prior 15-60 days
  final int daysSinceLastWorkout;
  final List<String> recentWorkoutsSummary;
  final Map<String, ExerciseProgressSummary> exerciseSummaries;
  final List<String> detectedPlateaus;
  final List<String> detectedImprovements;

  // Nutrition Longitudinal Metrics
  final int totalDaysWithMealsLogged;
  final int nutritionDaysIn14DayWindow;
  final double avgCaloriesLast7Days;
  final double avgCaloriesLast14Days;
  final double avgProteinLast7Days;
  final double avgProteinLast14Days;
  final double proteinAdherencePct14Days; // avgProtein / targetProtein
  final int lowProteinDaysLast7Days; // days < 75% of target
  final int lowProteinDaysLast14Days;
  final double calorieDelta14Days; // avgCalories - targetDailyCalories (+ surplus, - deficit)
  final List<String> recurringMeals;

  // Untracked Variables (prevent hallucination)
  final List<String> unmeasuredMetrics;

  const KynoUserFitnessSnapshot({
    this.userId,
    required this.computedAt,
    required this.userName,
    required this.userGoal,
    this.userWeightKg,
    required this.targetDailyCalories,
    required this.targetDailyProtein,
    required this.totalWorkoutsLogged,
    required this.workoutsPerWeekLast14Days,
    required this.workoutsPerWeekBaseline,
    required this.daysSinceLastWorkout,
    required this.recentWorkoutsSummary,
    required this.exerciseSummaries,
    required this.detectedPlateaus,
    required this.detectedImprovements,
    required this.totalDaysWithMealsLogged,
    this.nutritionDaysIn14DayWindow = 14,
    required this.avgCaloriesLast7Days,
    required this.avgCaloriesLast14Days,
    required this.avgProteinLast7Days,
    required this.avgProteinLast14Days,
    required this.proteinAdherencePct14Days,
    required this.lowProteinDaysLast7Days,
    required this.lowProteinDaysLast14Days,
    required this.calorieDelta14Days,
    required this.recurringMeals,
    required this.unmeasuredMetrics,
  });

  bool get hasSufficientTrainingHistory => totalWorkoutsLogged >= 3;
  bool get hasSufficientNutritionHistory => totalDaysWithMealsLogged >= 3;
}
