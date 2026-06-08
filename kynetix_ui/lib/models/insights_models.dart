import 'day_status.dart';

// ─── Schema version sentinel ──────────────────────────────────────────────────
// Increment when any field is added/removed. Cached blobs with lower versions
// are discarded on load and immediately recomputed.
const int kInsightsSchemaVersion = 2;

// ─── ConsistencyScore ─────────────────────────────────────────────────────────
class ConsistencyScore {
  final int schemaVersion = kInsightsSchemaVersion;
  final double loggingConsistency;  // 0.0–1.0 (logged days / period days)
  final double proteinAdherence;    // 0.0–1.0 (days ≥90% protein target / logged days)
  final double calorieAdherence;    // 0.0–1.0 (days within ±12% of cal target / logged days)
  final double gymAttendance;       // 0.0–1.0 (gym days / expected gym days from profile)
  final double mealQuality;         // 0.0–1.0 (avg dailyNutritionScore / 100; 0.0 if no data)
  final int score;                  // composite 0–100

  const ConsistencyScore({
    required this.loggingConsistency,
    required this.proteinAdherence,
    required this.calorieAdherence,
    required this.gymAttendance,
    required this.mealQuality,
    required this.score,
  });

  static int computeScoreValue({
    required double loggingConsistency,
    required double proteinAdherence,
    required double calorieAdherence,
    required double gymAttendance,
    required double mealQuality,
  }) {
    return (loggingConsistency * 35 +
            proteinAdherence * 25 +
            calorieAdherence * 20 +
            gymAttendance * 10 +
            mealQuality * 10)
        .round()
        .clamp(0, 100);
  }

  Map<String, dynamic> toJson() => {
        'loggingConsistency': loggingConsistency,
        'proteinAdherence': proteinAdherence,
        'calorieAdherence': calorieAdherence,
        'gymAttendance': gymAttendance,
        'mealQuality': mealQuality,
        'score': score,
      };

  factory ConsistencyScore.fromJson(Map<String, dynamic> j) => ConsistencyScore(
        loggingConsistency: (j['loggingConsistency'] as num).toDouble(),
        proteinAdherence: (j['proteinAdherence'] as num).toDouble(),
        calorieAdherence: (j['calorieAdherence'] as num).toDouble(),
        gymAttendance: (j['gymAttendance'] as num).toDouble(),
        mealQuality: (j['mealQuality'] as num).toDouble(),
        score: (j['score'] as num).toInt(),
      );
}

// ─── PeriodDelta ──────────────────────────────────────────────────────────────
class PeriodDelta {
  final double? proteinAdherenceDelta;    // e.g. +0.12 = +12 percentage points
  final double? calorieAdherenceDelta;
  final double? loggingConsistencyDelta;
  final double? mealQualityDelta;         // in score points (0–100 scale)
  final int? consistencyScoreDelta;       // integer points

  const PeriodDelta({
    this.proteinAdherenceDelta,
    this.calorieAdherenceDelta,
    this.loggingConsistencyDelta,
    this.mealQualityDelta,
    this.consistencyScoreDelta,
  });

  Map<String, dynamic> toJson() => {
        'proteinAdherenceDelta': proteinAdherenceDelta,
        'calorieAdherenceDelta': calorieAdherenceDelta,
        'loggingConsistencyDelta': loggingConsistencyDelta,
        'mealQualityDelta': mealQualityDelta,
        'consistencyScoreDelta': consistencyScoreDelta,
      };

  factory PeriodDelta.fromJson(Map<String, dynamic> j) => PeriodDelta(
        proteinAdherenceDelta: (j['proteinAdherenceDelta'] as num?)?.toDouble(),
        calorieAdherenceDelta: (j['calorieAdherenceDelta'] as num?)?.toDouble(),
        loggingConsistencyDelta: (j['loggingConsistencyDelta'] as num?)?.toDouble(),
        mealQualityDelta: (j['mealQualityDelta'] as num?)?.toDouble(),
        consistencyScoreDelta: (j['consistencyScoreDelta'] as num?)?.toInt(),
      );
}

// ─── TopImprovement ───────────────────────────────────────────────────────────
enum ImprovementMetric {
  proteinAdherence,
  calorieAdherence,
  loggingConsistency,
  mealQuality,
  consistencyScore
}

class TopImprovement {
  final ImprovementMetric metric;
  final String label;   // e.g. "Protein adherence improved most (+18%)"
  final double delta;   // raw delta value (always positive)

  const TopImprovement({
    required this.metric,
    required this.label,
    required this.delta,
  });

  Map<String, dynamic> toJson() => {
        'metric': metric.name,
        'label': label,
        'delta': delta,
      };

  factory TopImprovement.fromJson(Map<String, dynamic> j) => TopImprovement(
        metric: ImprovementMetric.values.byName(j['metric'] as String),
        label: j['label'] as String,
        delta: (j['delta'] as num).toDouble(),
      );
}

// ─── RegressionAlert ──────────────────────────────────────────────────────────
enum RegressionType {
  proteinConsistency,
  mealQuality,
  loggingConsistency,
  gymAttendance
}

class RegressionAlert {
  final RegressionType type;
  final String message;   // advisory, non-judgmental
  final double magnitude; // absolute delta that triggered this

  const RegressionAlert({
    required this.type,
    required this.message,
    required this.magnitude,
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'message': message,
        'magnitude': magnitude,
      };

  factory RegressionAlert.fromJson(Map<String, dynamic> j) => RegressionAlert(
        type: RegressionType.values.byName(j['type'] as String),
        message: j['message'] as String,
        magnitude: (j['magnitude'] as num).toDouble(),
      );
}

// ─── PersonalBests ────────────────────────────────────────────────────────────
class PersonalBests {
  final int schemaVersion = kInsightsSchemaVersion;
  final double? highestProteinDay;          // grams
  final String? highestProteinDayKey;       // "yyyy-MM-dd"
  final int? bestMealQualityWeekScore;   // ConsistencyScore.score for best week
  final String? bestMealQualityWeekKey;     // "yyyy-Www"
  final int longestLoggingStreak;       // consecutive logged days (all-time)
  final int? highestAvgStepsWeek;        // steps/day avg for best week
  final String? highestAvgStepsWeekKey;
  final int? mostConsistentMonthScore;   // ConsistencyScore.score for best month
  final String? mostConsistentMonthKey;     // "yyyy-MM"
  final DateTime computedAt;

  const PersonalBests({
    this.highestProteinDay,
    this.highestProteinDayKey,
    this.bestMealQualityWeekScore,
    this.bestMealQualityWeekKey,
    required this.longestLoggingStreak,
    this.highestAvgStepsWeek,
    this.highestAvgStepsWeekKey,
    this.mostConsistentMonthScore,
    this.mostConsistentMonthKey,
    required this.computedAt,
  });

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'highestProteinDay': highestProteinDay,
        'highestProteinDayKey': highestProteinDayKey,
        'bestMealQualityWeekScore': bestMealQualityWeekScore,
        'bestMealQualityWeekKey': bestMealQualityWeekKey,
        'longestLoggingStreak': longestLoggingStreak,
        'highestAvgStepsWeek': highestAvgStepsWeek,
        'highestAvgStepsWeekKey': highestAvgStepsWeekKey,
        'mostConsistentMonthScore': mostConsistentMonthScore,
        'mostConsistentMonthKey': mostConsistentMonthKey,
        'computedAt': computedAt.toIso8601String(),
      };

  factory PersonalBests.fromJson(Map<String, dynamic> j) => PersonalBests(
        highestProteinDay: (j['highestProteinDay'] as num?)?.toDouble(),
        highestProteinDayKey: j['highestProteinDayKey'] as String?,
        bestMealQualityWeekScore: (j['bestMealQualityWeekScore'] as num?)?.toInt(),
        bestMealQualityWeekKey: j['bestMealQualityWeekKey'] as String?,
        longestLoggingStreak: (j['longestLoggingStreak'] as num).toInt(),
        highestAvgStepsWeek: (j['highestAvgStepsWeek'] as num?)?.toInt(),
        highestAvgStepsWeekKey: j['highestAvgStepsWeekKey'] as String?,
        mostConsistentMonthScore: (j['mostConsistentMonthScore'] as num?)?.toInt(),
        mostConsistentMonthKey: j['mostConsistentMonthKey'] as String?,
        computedAt: DateTime.parse(j['computedAt'] as String),
      );
}

// ─── MuscleGroupAnalysis ──────────────────────────────────────────────────────
class MuscleGroupAnalysis {
  final String muscleGroup;
  final int sessionsTrained;
  final int hardSets;
  final double weeklyVolume;
  final int recoveryFrequency;
  final double? daysBetweenExposures;

  const MuscleGroupAnalysis({
    required this.muscleGroup,
    required this.sessionsTrained,
    required this.hardSets,
    required this.weeklyVolume,
    required this.recoveryFrequency,
    this.daysBetweenExposures,
  });

  Map<String, dynamic> toJson() => {
        'muscleGroup': muscleGroup,
        'sessionsTrained': sessionsTrained,
        'hardSets': hardSets,
        'weeklyVolume': weeklyVolume,
        'recoveryFrequency': recoveryFrequency,
        if (daysBetweenExposures != null) 'daysBetweenExposures': daysBetweenExposures,
      };

  factory MuscleGroupAnalysis.fromJson(Map<String, dynamic> j) => MuscleGroupAnalysis(
        muscleGroup: j['muscleGroup'] as String? ?? '',
        sessionsTrained: (j['sessionsTrained'] as num?)?.toInt() ?? 0,
        hardSets: (j['hardSets'] as num?)?.toInt() ?? 0,
        weeklyVolume: (j['weeklyVolume'] as num?)?.toDouble() ?? 0.0,
        recoveryFrequency: (j['recoveryFrequency'] as num?)?.toInt() ?? 0,
        daysBetweenExposures: (j['daysBetweenExposures'] as num?)?.toDouble(),
      );
}

// ─── WeeklyReport ─────────────────────────────────────────────────────────────
class WeeklyReport {
  final int schemaVersion = kInsightsSchemaVersion;
  final String weekKey;              // "yyyy-Www" (ISO week)
  final DateTime weekStart;            // Monday of this week
  final ConsistencyScore consistencyScore;
  final double avgCalories;
  final double avgProtein;
  final double avgFiber;
  final int gymDaysCount;
  final int loggedDaysCount;      // of 7
  final String? bestDayKey;           // highest protein, null if no data
  final DayOutcome mostCommonOutcome;
  final PeriodDelta? deltaVsPrior;         // null if no prior week
  final TopImprovement? topImprovement;       // null if no prior week or no positive change
  final List<RegressionAlert> regressions;
  final DateTime computedAt;

  // Training & Spacing Analysis (Explainable Scores)
  final int trainingQualityScore;
  final int trainingRecoveryScore;
  final int trainingVolumeScore;
  final int trainingBalanceScore;
  final int trainingConsistencyScore;

  final String trainingQualityExplanation;
  final String trainingRecoveryExplanation;
  final String trainingVolumeExplanation;
  final String trainingBalanceExplanation;
  final String trainingConsistencyExplanation;

  final List<MuscleGroupAnalysis> muscleAnalyses;

  final List<String> coachingWhatWentWell;
  final List<String> coachingNeedsImprovement;
  final List<String> coachingRecommendations;

  const WeeklyReport({
    required this.weekKey,
    required this.weekStart,
    required this.consistencyScore,
    required this.avgCalories,
    required this.avgProtein,
    required this.avgFiber,
    required this.gymDaysCount,
    required this.loggedDaysCount,
    this.bestDayKey,
    required this.mostCommonOutcome,
    this.deltaVsPrior,
    this.topImprovement,
    required this.regressions,
    required this.computedAt,

    // Training Metrics
    this.trainingQualityScore = 0,
    this.trainingRecoveryScore = 0,
    this.trainingVolumeScore = 0,
    this.trainingBalanceScore = 0,
    this.trainingConsistencyScore = 0,
    this.trainingQualityExplanation = '',
    this.trainingRecoveryExplanation = '',
    this.trainingVolumeExplanation = '',
    this.trainingBalanceExplanation = '',
    this.trainingConsistencyExplanation = '',
    this.muscleAnalyses = const [],
    this.coachingWhatWentWell = const [],
    this.coachingNeedsImprovement = const [],
    this.coachingRecommendations = const [],
  });

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'weekKey': weekKey,
        'weekStart': weekStart.toIso8601String(),
        'consistencyScore': consistencyScore.toJson(),
        'avgCalories': avgCalories,
        'avgProtein': avgProtein,
        'avgFiber': avgFiber,
        'gymDaysCount': gymDaysCount,
        'loggedDaysCount': loggedDaysCount,
        if (bestDayKey != null) 'bestDayKey': bestDayKey,
        'mostCommonOutcome': mostCommonOutcome.name,
        if (deltaVsPrior != null) 'deltaVsPrior': deltaVsPrior!.toJson(),
        if (topImprovement != null) 'topImprovement': topImprovement!.toJson(),
        'regressions': regressions.map((r) => r.toJson()).toList(),
        'computedAt': computedAt.toIso8601String(),

        // Training Metrics
        'trainingQualityScore': trainingQualityScore,
        'trainingRecoveryScore': trainingRecoveryScore,
        'trainingVolumeScore': trainingVolumeScore,
        'trainingBalanceScore': trainingBalanceScore,
        'trainingConsistencyScore': trainingConsistencyScore,
        'trainingQualityExplanation': trainingQualityExplanation,
        'trainingRecoveryExplanation': trainingRecoveryExplanation,
        'trainingVolumeExplanation': trainingVolumeExplanation,
        'trainingBalanceExplanation': trainingBalanceExplanation,
        'trainingConsistencyExplanation': trainingConsistencyExplanation,
        'muscleAnalyses': muscleAnalyses.map((m) => m.toJson()).toList(),
        'coachingWhatWentWell': coachingWhatWentWell,
        'coachingNeedsImprovement': coachingNeedsImprovement,
        'coachingRecommendations': coachingRecommendations,
      };

  factory WeeklyReport.fromJson(Map<String, dynamic> j) => WeeklyReport(
        weekKey: j['weekKey'] as String,
        weekStart: DateTime.parse(j['weekStart'] as String),
        consistencyScore: ConsistencyScore.fromJson(j['consistencyScore'] as Map<String, dynamic>),
        avgCalories: (j['avgCalories'] as num).toDouble(),
        avgProtein: (j['avgProtein'] as num).toDouble(),
        avgFiber: (j['avgFiber'] as num).toDouble(),
        gymDaysCount: (j['gymDaysCount'] as num).toInt(),
        loggedDaysCount: (j['loggedDaysCount'] as num).toInt(),
        bestDayKey: j['bestDayKey'] as String?,
        mostCommonOutcome: DayOutcome.values.byName(j['mostCommonOutcome'] as String),
        deltaVsPrior: j['deltaVsPrior'] != null
            ? PeriodDelta.fromJson(j['deltaVsPrior'] as Map<String, dynamic>)
            : null,
        topImprovement: j['topImprovement'] != null
            ? TopImprovement.fromJson(j['topImprovement'] as Map<String, dynamic>)
            : null,
        regressions: (j['regressions'] as List<dynamic>?)
                ?.map((r) => RegressionAlert.fromJson(r as Map<String, dynamic>))
                .toList() ??
            const [],
        computedAt: DateTime.parse(j['computedAt'] as String),

        // Training Metrics
        trainingQualityScore: (j['trainingQualityScore'] as num?)?.toInt() ?? 0,
        trainingRecoveryScore: (j['trainingRecoveryScore'] as num?)?.toInt() ?? 0,
        trainingVolumeScore: (j['trainingVolumeScore'] as num?)?.toInt() ?? 0,
        trainingBalanceScore: (j['trainingBalanceScore'] as num?)?.toInt() ?? 0,
        trainingConsistencyScore: (j['trainingConsistencyScore'] as num?)?.toInt() ?? 0,
        trainingQualityExplanation: j['trainingQualityExplanation'] as String? ?? '',
        trainingRecoveryExplanation: j['trainingRecoveryExplanation'] as String? ?? '',
        trainingVolumeExplanation: j['trainingVolumeExplanation'] as String? ?? '',
        trainingBalanceExplanation: j['trainingBalanceExplanation'] as String? ?? '',
        trainingConsistencyExplanation: j['trainingConsistencyExplanation'] as String? ?? '',
        muscleAnalyses: (j['muscleAnalyses'] as List<dynamic>?)
                ?.map((m) => MuscleGroupAnalysis.fromJson(m as Map<String, dynamic>))
                .toList() ??
            const [],
        coachingWhatWentWell: (j['coachingWhatWentWell'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            const [],
        coachingNeedsImprovement: (j['coachingNeedsImprovement'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            const [],
        coachingRecommendations: (j['coachingRecommendations'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            const [],
      );
}

// ─── MonthlyReport ────────────────────────────────────────────────────────────
class MonthlyReport {
  final int schemaVersion = kInsightsSchemaVersion;
  final String monthKey;             // "yyyy-MM"
  final ConsistencyScore consistencyScore;
  final double avgCalories;
  final double avgProtein;
  final int totalGymDays;
  final int totalLoggedDays;
  final String? bestWeekKey;
  final String? worstWeekKey;
  final String trendDirection;       // "improving" | "stable" | "declining"
  final PeriodDelta? deltaVsPrior;
  final TopImprovement? topImprovement;
  final List<RegressionAlert> regressions;
  final DateTime computedAt;

  const MonthlyReport({
    required this.monthKey,
    required this.consistencyScore,
    required this.avgCalories,
    required this.avgProtein,
    required this.totalGymDays,
    required this.totalLoggedDays,
    this.bestWeekKey,
    this.worstWeekKey,
    required this.trendDirection,
    this.deltaVsPrior,
    this.topImprovement,
    required this.regressions,
    required this.computedAt,
  });

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'monthKey': monthKey,
        'consistencyScore': consistencyScore.toJson(),
        'avgCalories': avgCalories,
        'avgProtein': avgProtein,
        'totalGymDays': totalGymDays,
        'totalLoggedDays': totalLoggedDays,
        if (bestWeekKey != null) 'bestWeekKey': bestWeekKey,
        if (worstWeekKey != null) 'worstWeekKey': worstWeekKey,
        'trendDirection': trendDirection,
        if (deltaVsPrior != null) 'deltaVsPrior': deltaVsPrior!.toJson(),
        if (topImprovement != null) 'topImprovement': topImprovement!.toJson(),
        'regressions': regressions.map((r) => r.toJson()).toList(),
        'computedAt': computedAt.toIso8601String(),
      };

  factory MonthlyReport.fromJson(Map<String, dynamic> j) => MonthlyReport(
        monthKey: j['monthKey'] as String,
        consistencyScore: ConsistencyScore.fromJson(j['consistencyScore'] as Map<String, dynamic>),
        avgCalories: (j['avgCalories'] as num).toDouble(),
        avgProtein: (j['avgProtein'] as num).toDouble(),
        totalGymDays: (j['totalGymDays'] as num).toInt(),
        totalLoggedDays: (j['totalLoggedDays'] as num).toInt(),
        bestWeekKey: j['bestWeekKey'] as String?,
        worstWeekKey: j['worstWeekKey'] as String?,
        trendDirection: j['trendDirection'] as String,
        deltaVsPrior: j['deltaVsPrior'] != null
            ? PeriodDelta.fromJson(j['deltaVsPrior'] as Map<String, dynamic>)
            : null,
        topImprovement: j['topImprovement'] != null
            ? TopImprovement.fromJson(j['topImprovement'] as Map<String, dynamic>)
            : null,
        regressions: (j['regressions'] as List<dynamic>?)
                ?.map((r) => RegressionAlert.fromJson(r as Map<String, dynamic>))
                .toList() ??
            const [],
        computedAt: DateTime.parse(j['computedAt'] as String),
      );
}

// ─── YearlyReport ─────────────────────────────────────────────────────────────
class YearlyReport {
  final int schemaVersion = kInsightsSchemaVersion;
  final String yearKey;              // "yyyy"
  final ConsistencyScore consistencyScore;
  final double avgCalories;
  final double avgProtein;
  final int totalGymDays;
  final int totalLoggedDays;
  final Map<String, int> monthlyScores;        // "yyyy-MM" → ConsistencyScore.score
  final String? bestMonthKey;
  final String? worstMonthKey;
  final DateTime computedAt;

  const YearlyReport({
    required this.yearKey,
    required this.consistencyScore,
    required this.avgCalories,
    required this.avgProtein,
    required this.totalGymDays,
    required this.totalLoggedDays,
    required this.monthlyScores,
    this.bestMonthKey,
    this.worstMonthKey,
    required this.computedAt,
  });

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'yearKey': yearKey,
        'consistencyScore': consistencyScore.toJson(),
        'avgCalories': avgCalories,
        'avgProtein': avgProtein,
        'totalGymDays': totalGymDays,
        'totalLoggedDays': totalLoggedDays,
        'monthlyScores': monthlyScores,
        if (bestMonthKey != null) 'bestMonthKey': bestMonthKey,
        if (worstMonthKey != null) 'worstMonthKey': worstMonthKey,
        'computedAt': computedAt.toIso8601String(),
      };

  factory YearlyReport.fromJson(Map<String, dynamic> j) => YearlyReport(
        yearKey: j['yearKey'] as String,
        consistencyScore: ConsistencyScore.fromJson(j['consistencyScore'] as Map<String, dynamic>),
        avgCalories: (j['avgCalories'] as num).toDouble(),
        avgProtein: (j['avgProtein'] as num).toDouble(),
        totalGymDays: (j['totalGymDays'] as num).toInt(),
        totalLoggedDays: (j['totalLoggedDays'] as num).toInt(),
        monthlyScores: Map<String, int>.from(j['monthlyScores'] as Map),
        bestMonthKey: j['bestMonthKey'] as String?,
        worstMonthKey: j['worstMonthKey'] as String?,
        computedAt: DateTime.parse(j['computedAt'] as String),
      );
}

// ─── Achievement ──────────────────────────────────────────────────────────────
enum AchievementCategory { nutrition, training, consistency, milestone }

class Achievement {
  final String id;
  final String title;
  final String description;
  final String emoji;
  final AchievementCategory category;
  final DateTime earnedAt;
  final bool isNew;    // true until user views InsightsScreen

  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.emoji,
    required this.category,
    required this.earnedAt,
    this.isNew = true,
  });

  Achievement copyWith({
    String? title,
    String? description,
    String? emoji,
    AchievementCategory? category,
    DateTime? earnedAt,
    bool? isNew,
  }) =>
      Achievement(
        id: id,
        title: title ?? this.title,
        description: description ?? this.description,
        emoji: emoji ?? this.emoji,
        category: category ?? this.category,
        earnedAt: earnedAt ?? this.earnedAt,
        isNew: isNew ?? this.isNew,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'emoji': emoji,
        'category': category.name,
        'earnedAt': earnedAt.toIso8601String(),
        'isNew': isNew,
      };

  factory Achievement.fromJson(Map<String, dynamic> j) => Achievement(
        id: j['id'] as String,
        title: j['title'] as String,
        description: j['description'] as String,
        emoji: j['emoji'] as String,
        category: AchievementCategory.values.byName(j['category'] as String),
        earnedAt: DateTime.parse(j['earnedAt'] as String),
        isNew: j['isNew'] as bool? ?? true,
      );
}

// ─── AchievementProgress ──────────────────────────────────────────────────────
// Computed on demand — never stored.
class AchievementProgress {
  final String id;
  final int current;
  final int target;
  final String label;    // e.g. "67 / 100 sessions"

  const AchievementProgress({
    required this.id,
    required this.current,
    required this.target,
    required this.label,
  });

  double get fraction => (current / target).clamp(0.0, 1.0);
}

// ─── InsightsSummary (AI narrative — stored separately) ───────────────────────
class InsightsSummary {
  final String weekKey;
  final String narrative;      // AI-generated 2–3 sentences; never required for UI
  final DateTime generatedAt;
  final bool isStale;        // true if WeeklyReport was recomputed after this

  const InsightsSummary({
    required this.weekKey,
    required this.narrative,
    required this.generatedAt,
    this.isStale = false,
  });

  Map<String, dynamic> toJson() => {
        'weekKey': weekKey,
        'narrative': narrative,
        'generatedAt': generatedAt.toIso8601String(),
        'isStale': isStale,
      };

  factory InsightsSummary.fromJson(Map<String, dynamic> j) => InsightsSummary(
        weekKey: j['weekKey'] as String,
        narrative: j['narrative'] as String,
        generatedAt: DateTime.parse(j['generatedAt'] as String),
        isStale: j['isStale'] as bool? ?? false,
      );
}
