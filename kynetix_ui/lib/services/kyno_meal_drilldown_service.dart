import '../models/day_log.dart';
import '../models/kyno_fitness_snapshot.dart';
import 'kyno_context_service.dart';
import 'kyno_historical_analysis_service.dart';

/// Single historical meal record extracted directly from DayLog.
class HistoricalMealRecord {
  final String mealName;
  final DateTime timestamp;
  final String formattedTime;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final MealSection section;
  final List<String> parsedFoods;
  final String source;
  final bool isLateNight;

  const HistoricalMealRecord({
    required this.mealName,
    required this.timestamp,
    required this.formattedTime,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.section,
    required this.parsedFoods,
    required this.source,
    required this.isLateNight,
  });

  static String formatTime(DateTime dt) {
    final hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$h12:$minute $period';
  }

  factory HistoricalMealRecord.fromEntry(MealEntry entry) {
    final name = entry.finalSavedInput.trim().isNotEmpty
        ? entry.finalSavedInput.trim()
        : (entry.result.canonicalMeal.trim().isNotEmpty
            ? entry.result.canonicalMeal.trim()
            : entry.rawInput.trim());

    final carbs = ((entry.result.carbohydrates?.min ?? 0.0) + (entry.result.carbohydrates?.max ?? 0.0)) / 2.0;
    final fat = ((entry.result.fat?.min ?? 0.0) + (entry.result.fat?.max ?? 0.0)) / 2.0;
    final hour = entry.addedAt.hour;
    // Considered late-night if 8:00 PM (20:00) or later, or before 5:00 AM
    final lateNight = hour >= 20 || hour < 5;

    return HistoricalMealRecord(
      mealName: name.isNotEmpty ? name : 'Logged Meal',
      timestamp: entry.addedAt,
      formattedTime: formatTime(entry.addedAt),
      calories: entry.calMid,
      protein: entry.protMid,
      carbs: carbs,
      fat: fat,
      section: entry.section,
      parsedFoods: entry.parsedFoods,
      source: entry.result.source,
      isLateNight: lateNight,
    );
  }

  String get summaryString =>
      '$mealName (${section.name.toUpperCase()} at $formattedTime) – ${calories.toStringAsFixed(0)} kcal, ${protein.toStringAsFixed(0)}g P, ${carbs.toStringAsFixed(0)}g C, ${fat.toStringAsFixed(0)}g F';
}

/// Service dedicated to retrieving exact historical DayLog meal entries and
/// synthesizing non-moralizing, evidence-based meal drill-downs.
class KynoMealDrilldownService {
  KynoMealDrilldownService._();
  static final KynoMealDrilldownService instance = KynoMealDrilldownService._();

  /// Formats date to 'yyyy-MM-dd' for DayLog key lookup.
  String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  /// Retrieves chronological historical meals for a given calendar date.
  List<HistoricalMealRecord> getMealsForDate(DateTime date) {
    final key = _dateKey(date);
    final log = dayLogStore[key];
    if (log == null || log.allEntries.isEmpty) return const [];

    final records = log.allEntries.map((e) => HistoricalMealRecord.fromEntry(e)).toList();
    records.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return records;
  }

  /// Retrieves chronological historical meals across an inclusive date range.
  List<HistoricalMealRecord> getMealsForDateRange(DateTime start, DateTime end) {
    final all = <HistoricalMealRecord>[];
    DateTime cursor = DateTime(start.year, start.month, start.day);
    final last = DateTime(end.year, end.month, end.day);

    while (!cursor.isAfter(last)) {
      all.addAll(getMealsForDate(cursor));
      cursor = cursor.add(const Duration(days: 1));
    }
    all.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return all;
  }

  // ─── 1. "Why were my calories high yesterday?" ──────────────────────────────
  KynoAnalysisResult analyzeYesterdayCalories(KynoUserFitnessSnapshot snapshot, {DateTime? date}) {
    final targetDate = date ?? DateTime.now().subtract(const Duration(days: 1));
    final meals = getMealsForDate(targetDate);
    final insights = <KynoInsightItem>[];

    if (meals.isEmpty) {
      insights.add(KynoInsightItem(
        type: KynoInformationType.fact,
        title: 'Yesterday Meal Log',
        detail: 'No meals were logged in your DayLog records for yesterday (${targetDate.month}/${targetDate.day}).',
      ));
      insights.add(KynoInsightItem(
        type: KynoInformationType.unknown,
        title: 'Calorie Breakdown',
        detail: 'Cannot identify calorie contributors because no meals were logged for this date.',
      ));
      return KynoAnalysisResult(
        intent: KynoAnalysisIntent.yesterdayNutrition,
        headline: 'Calorie breakdown for yesterday (${targetDate.month}/${targetDate.day}):',
        insights: insights,
      );
    }

    final totalCal = meals.fold(0.0, (sum, m) => sum + m.calories);
    final totalPro = meals.fold(0.0, (sum, m) => sum + m.protein);
    final targetCal = snapshot.targetDailyCalories;

    // Sort descending by calorie contribution
    final sortedByCal = List<HistoricalMealRecord>.from(meals)
      ..sort((a, b) => b.calories.compareTo(a.calories));
    final highestCal = sortedByCal.first;

    // FACT: Cites exact meals with name, timestamp, and macros
    final mealLines = meals.map((m) =>
        '• ${m.formattedTime} [${m.section.name.toUpperCase()}]: "${m.mealName}" – ${m.calories.toStringAsFixed(0)} kcal (${m.protein.toStringAsFixed(0)}g P, ${m.carbs.toStringAsFixed(0)}g C, ${m.fat.toStringAsFixed(0)}g F)'
    ).join('\n');

    insights.add(KynoInsightItem(
      type: KynoInformationType.fact,
      title: 'Yesterday Meal Log (${meals.length} meals logged)',
      detail: '$mealLines\nTotal Logged: ${totalCal.toStringAsFixed(0)} kcal, ${totalPro.toStringAsFixed(0)}g protein.',
    ));

    // CALCULATION: Contribution math and delta vs target
    final delta = totalCal - targetCal;
    final topPct = totalCal > 0 ? ((highestCal.calories / totalCal) * 100).round() : 0;
    final calcLines = <String>[
      '• Highest contributor: "${highestCal.mealName}" at ${highestCal.formattedTime} accounted for ${highestCal.calories.toStringAsFixed(0)} kcal ($topPct% of yesterday\'s total intake).',
      if (delta > 0)
        '• Total logged intake exceeded your configured target of ${targetCal.toStringAsFixed(0)} kcal by ${delta.toStringAsFixed(0)} kcal (+${((delta / targetCal) * 100).round()}%).'
      else
        '• Total logged intake was within your configured target (${totalCal.toStringAsFixed(0)} kcal logged vs ${targetCal.toStringAsFixed(0)} kcal target).',
    ];
    if (sortedByCal.length > 1) {
      final second = sortedByCal[1];
      final secondPct = totalCal > 0 ? ((second.calories / totalCal) * 100).round() : 0;
      calcLines.add('• Second highest contributor: "${second.mealName}" at ${second.formattedTime} accounted for ${second.calories.toStringAsFixed(0)} kcal ($secondPct%).');
    }

    insights.add(KynoInsightItem(
      type: KynoInformationType.calculation,
      title: 'Calorie Distribution Math',
      detail: calcLines.join('\n'),
    ));

    // INFERENCE: Objective, non-moralizing explanation relative to goal
    insights.add(KynoInsightItem(
      type: KynoInformationType.inference,
      title: 'Energy Context',
      detail: delta > 0
          ? 'The higher calorie total was primarily driven by the energy density of "${highestCal.mealName}" at ${highestCal.formattedTime}. In the context of your configured daily calorie target, single-day calorie fluctuations are normal and do not compromise long-term adaptation.'
          : 'Yesterday\'s calorie distribution was anchored across your logged meals without an overall surplus.',
    ));

    // RECOMMENDATION: Constructive guidance aligned with user targets
    insights.add(KynoInsightItem(
      type: KynoInformationType.recommendation,
      title: 'Target Alignment',
      detail: delta > 250
          ? 'If you want to stay closer to your ${targetCal.toStringAsFixed(0)} kcal target, consider moderating portion sizes or carbohydrate and fat density for higher-energy meals like "${highestCal.mealName}".'
          : 'Maintain your current meal balance and continue logging consistently.',
    ));

    // UNKNOWN: Unmeasured variables
    insights.add(KynoInsightItem(
      type: KynoInformationType.unknown,
      title: 'Untracked Variables',
      detail: 'Cooking oils, exact sauce quantities, non-exercise physical activity, and precise metabolic expenditure are not tracked.',
    ));

    return KynoAnalysisResult(
      intent: KynoAnalysisIntent.yesterdayNutrition,
      headline: 'Yesterday\'s calorie analysis based on your exact DayLog entries:',
      insights: insights,
      mostLikelyContributors: [
        '"${highestCal.mealName}" at ${highestCal.formattedTime} (${highestCal.calories.toStringAsFixed(0)} kcal)',
      ],
    );
  }

  // ─── 2. "Why am I not hitting protein?" ────────────────────────────────────
  KynoAnalysisResult analyzeProteinDeficitAndMeals(KynoUserFitnessSnapshot snapshot, {DateTime? date}) {
    final targetDate = date ?? DateTime.now().subtract(const Duration(days: 1));
    final meals = getMealsForDate(targetDate);
    final insights = <KynoInsightItem>[];

    final targetPro = snapshot.targetDailyProtein;

    // FACT: Longitudinal average & yesterday's exact protein records
    insights.add(KynoInsightItem(
      type: KynoInformationType.fact,
      title: 'Protein Intake History',
      detail: '• 14-Day Average: ${snapshot.avgProteinLast14Days.toStringAsFixed(0)}g / day across ${snapshot.nutritionDaysIn14DayWindow} logged days.\n'
          '• Configured Target: ${targetPro.toStringAsFixed(0)}g / day.\n'
          '• Days below 75% target: ${snapshot.lowProteinDaysLast14Days} of last ${snapshot.nutritionDaysIn14DayWindow} logged days.',
    ));

    if (meals.isNotEmpty) {
      final mealFacts = meals.map((m) =>
          '• ${m.formattedTime} [${m.section.name.toUpperCase()}]: "${m.mealName}" – ${m.protein.toStringAsFixed(0)}g protein (${m.calories.toStringAsFixed(0)} kcal)'
      ).join('\n');

      insights.add(KynoInsightItem(
        type: KynoInformationType.fact,
        title: 'Recent Meal Protein Drill-Down (${targetDate.month}/${targetDate.day})',
        detail: mealFacts,
      ));

      // Identify low-protein meals (<15g) and anchors (>=30g)
      final lowProMeals = meals.where((m) => m.protein < 15.0).toList();
      final anchorMeals = meals.where((m) => m.protein >= 30.0).toList();

      final yesterdayPro = meals.fold(0.0, (s, m) => s + m.protein);
      final yesterdayDeficit = (targetPro - yesterdayPro).clamp(0.0, 999.0);

      insights.add(KynoInsightItem(
        type: KynoInformationType.calculation,
        title: 'Protein Opportunity Math',
        detail: '• Yesterday\'s protein total: ${yesterdayPro.toStringAsFixed(0)}g vs ${targetPro.toStringAsFixed(0)}g target (${yesterdayDeficit.toStringAsFixed(0)}g deficit).\n'
            '• High-protein anchor meals (≥30g): ${anchorMeals.length} logged.\n'
            '• Low-protein meals (<15g): ${lowProMeals.length} of ${meals.length} meals.',
      ));

      insights.add(KynoInsightItem(
        type: KynoInformationType.inference,
        title: 'Deficit Analysis',
        detail: lowProMeals.isNotEmpty
            ? 'The primary reason for not hitting your protein target is that several logged meals (such as ${lowProMeals.map((m) => '"${m.mealName}" (${m.protein.toStringAsFixed(0)}g)').join(', ')}) contained minimal protein relative to their energy content. Without dedicated protein anchors at each meal, reaching ${targetPro.toStringAsFixed(0)}g requires high volume later in the day.'
            : 'Your logged meals had moderate protein density, but total meal frequency was insufficient to accumulate ${targetPro.toStringAsFixed(0)}g.',
      ));
    } else {
      insights.add(KynoInsightItem(
        type: KynoInformationType.calculation,
        title: 'Longitudinal Adherence Math',
        detail: '• Average daily protein deficit: ${(targetPro - snapshot.avgProteinLast14Days).clamp(0.0, 999.0).toStringAsFixed(0)}g / day (${(snapshot.proteinAdherencePct14Days * 100).toInt()}% adherence).',
      ));

      insights.add(KynoInsightItem(
        type: KynoInformationType.inference,
        title: 'Protein Adherence Pattern',
        detail: 'Consistent shortfalls across recorded days indicate that current meal routines lack regular 30–40g protein servings.',
      ));
    }

    insights.add(KynoInsightItem(
      type: KynoInformationType.recommendation,
      title: 'Actionable Adjustment',
      detail: 'Aim for 30–40g of protein per main meal (e.g. adding Greek yogurt, whey, eggs, poultry, tofu, or fish) rather than relying on snacks to catch up.',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.unknown,
      title: 'Untracked Variables',
      detail: 'Protein bioavailability, digestive absorption, and unlogged amino acid supplements are not recorded.',
    ));

    return KynoAnalysisResult(
      intent: KynoAnalysisIntent.proteinAdherence,
      headline: 'Drill-down on protein deficit and meal opportunities:',
      insights: insights,
      recommendedChanges: [
        'Anchor each primary meal with at least 30–40g of high-quality protein.',
        'Review low-protein snacks to see where 15–20g protein can be added.',
      ],
    );
  }

  // ─── 3. "Did I eat anything late last night?" ──────────────────────────────
  KynoAnalysisResult analyzeLateNightEating({DateTime? date}) {
    final targetDate = date ?? DateTime.now().subtract(const Duration(days: 1));
    final meals = getMealsForDate(targetDate);
    final insights = <KynoInsightItem>[];

    if (meals.isEmpty) {
      insights.add(KynoInsightItem(
        type: KynoInformationType.fact,
        title: 'Meal Log Record',
        detail: 'No meals were logged in your DayLog for yesterday (${targetDate.month}/${targetDate.day}).',
      ));
      insights.add(KynoInsightItem(
        type: KynoInformationType.unknown,
        title: 'Late Night Intake',
        detail: 'Cannot determine if anything was eaten late because no meal entries were logged for this date.',
      ));
      return KynoAnalysisResult(
        intent: KynoAnalysisIntent.lateNightEating,
        headline: 'Late night eating check for ${targetDate.month}/${targetDate.day}:',
        insights: insights,
      );
    }

    final lateMeals = meals.where((m) => m.isLateNight).toList();

    if (lateMeals.isNotEmpty) {
      final lateLines = lateMeals.map((m) =>
          '• "${m.mealName}" at ${m.formattedTime} [${m.section.name.toUpperCase()}]: ${m.calories.toStringAsFixed(0)} kcal, ${m.protein.toStringAsFixed(0)}g P, ${m.carbs.toStringAsFixed(0)}g C, ${m.fat.toStringAsFixed(0)}g F'
      ).join('\n');

      final lateCal = lateMeals.fold(0.0, (s, m) => s + m.calories);
      final latePro = lateMeals.fold(0.0, (s, m) => s + m.protein);

      insights.add(KynoInsightItem(
        type: KynoInformationType.fact,
        title: 'Logged Late-Night Meals (${lateMeals.length} logged after 8:00 PM)',
        detail: lateLines,
      ));

      insights.add(KynoInsightItem(
        type: KynoInformationType.calculation,
        title: 'Late Evening Nutrition Sum',
        detail: 'Total late-night intake: ${lateCal.toStringAsFixed(0)} kcal, ${latePro.toStringAsFixed(0)}g protein across ${lateMeals.length} logged items.',
      ));

      // Non-moralizing explanation
      insights.add(KynoInsightItem(
        type: KynoInformationType.inference,
        title: 'Contextual Alignment',
        detail: 'Eating late is neither inherently beneficial nor harmful for body composition. Energy balance across the full 24-hour cycle determines weight changes. This late meal contributed ${lateCal.toStringAsFixed(0)} kcal toward your daily total.',
      ));

      insights.add(KynoInsightItem(
        type: KynoInformationType.recommendation,
        title: 'Guidance',
        detail: 'If late-night hunger regularly leads to exceeding your daily calorie target, consider increasing fiber and protein at dinner to enhance evening satiety.',
      ));
    } else {
      final lastMeal = meals.last;
      insights.add(KynoInsightItem(
        type: KynoInformationType.fact,
        title: 'Logged Meal Timing',
        detail: 'No meals were logged after 8:00 PM yesterday (${targetDate.month}/${targetDate.day}).\n'
            'Your last recorded meal was "${lastMeal.mealName}" at ${lastMeal.formattedTime} [${lastMeal.section.name.toUpperCase()}], containing ${lastMeal.calories.toStringAsFixed(0)} kcal and ${lastMeal.protein.toStringAsFixed(0)}g protein.',
      ));

      insights.add(KynoInsightItem(
        type: KynoInformationType.calculation,
        title: 'Late Night Intake Math',
        detail: '0 kcal and 0g protein logged after 8:00 PM.',
      ));

      insights.add(KynoInsightItem(
        type: KynoInformationType.inference,
        title: 'Logged Pattern',
        detail: 'Your logged intake for yesterday concluded at ${lastMeal.formattedTime}.',
      ));
    }

    insights.add(KynoInsightItem(
      type: KynoInformationType.unknown,
      title: 'Untracked Factors',
      detail: 'Any unlogged snacks, beverages, or eating that occurred without recording in Kynetix remain untracked.',
    ));

    return KynoAnalysisResult(
      intent: KynoAnalysisIntent.lateNightEating,
      headline: lateMeals.isNotEmpty
          ? 'Yes, you logged ${lateMeals.length} item(s) late last night:'
          : 'No meals were logged late last night (after 8:00 PM):',
      insights: insights,
    );
  }

  // ─── 4. "What did I eat yesterday?" ────────────────────────────────────────
  KynoAnalysisResult analyzeChronologicalMeals({DateTime? date}) {
    final targetDate = date ?? DateTime.now().subtract(const Duration(days: 1));
    final meals = getMealsForDate(targetDate);
    final insights = <KynoInsightItem>[];

    if (meals.isEmpty) {
      insights.add(KynoInsightItem(
        type: KynoInformationType.fact,
        title: 'Meal Log Record',
        detail: 'No meals were logged in your DayLog for yesterday (${targetDate.month}/${targetDate.day}).',
      ));
      insights.add(KynoInsightItem(
        type: KynoInformationType.unknown,
        title: 'Nutrition History',
        detail: 'Intake for this date was not recorded in the application.',
      ));
      return KynoAnalysisResult(
        intent: KynoAnalysisIntent.historicalMealQuery,
        headline: 'No meals were logged yesterday (${targetDate.month}/${targetDate.day}).',
        insights: insights,
      );
    }

    final chronologicalLines = meals.map((m) =>
        '• ${m.formattedTime} [${m.section.name.toUpperCase()}]: "${m.mealName}" – ${m.calories.toStringAsFixed(0)} kcal | ${m.protein.toStringAsFixed(0)}g P | ${m.carbs.toStringAsFixed(0)}g C | ${m.fat.toStringAsFixed(0)}g F'
    ).join('\n');

    final totalCal = meals.fold(0.0, (s, m) => s + m.calories);
    final totalPro = meals.fold(0.0, (s, m) => s + m.protein);
    final totalCarb = meals.fold(0.0, (s, m) => s + m.carbs);
    final totalFat = meals.fold(0.0, (s, m) => s + m.fat);

    insights.add(KynoInsightItem(
      type: KynoInformationType.fact,
      title: 'Chronological Meal Record (${meals.length} meals)',
      detail: chronologicalLines,
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.calculation,
      title: 'Daily Macronutrient Totals',
      detail: '• Total Calories: ${totalCal.toStringAsFixed(0)} kcal\n'
          '• Protein: ${totalPro.toStringAsFixed(0)}g\n'
          '• Carbohydrates: ${totalCarb.toStringAsFixed(0)}g\n'
          '• Fat: ${totalFat.toStringAsFixed(0)}g',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.inference,
      title: 'Meal Structure',
      detail: 'Intake was distributed across ${meals.length} logged sessions from ${meals.first.formattedTime} to ${meals.last.formattedTime}.',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.unknown,
      title: 'Untracked Nutrients',
      detail: 'Micronutrients, water intake, and condiment additions not entered in the DayLog are untracked.',
    ));

    return KynoAnalysisResult(
      intent: KynoAnalysisIntent.historicalMealQuery,
      headline: 'Here is what you logged yesterday (${targetDate.month}/${targetDate.day}):',
      insights: insights,
    );
  }

  // ─── 5. "Why am I gaining weight?" ─────────────────────────────────────────
  KynoAnalysisResult analyzeWeightGain(KynoUserFitnessSnapshot snapshot, {DateTime? date}) {
    final targetDate = date ?? DateTime.now().subtract(const Duration(days: 1));
    final yesterdayMeals = getMealsForDate(targetDate);
    final insights = <KynoInsightItem>[];

    final avgCal = snapshot.avgCaloriesLast14Days;
    final targetCal = snapshot.targetDailyCalories;
    final delta = snapshot.calorieDelta14Days;

    // FACT: Multi-day calorie pattern and target
    insights.add(KynoInsightItem(
      type: KynoInformationType.fact,
      title: '14-Day Calorie Pattern',
      detail: '• 14-Day Average: ${avgCal.toStringAsFixed(0)} kcal / day across ${snapshot.nutritionDaysIn14DayWindow} logged days.\n'
          '• Configured Daily Target: ${targetCal.toStringAsFixed(0)} kcal / day.\n'
          '• Current Logged Weight: ${snapshot.userWeightKg != null ? "${snapshot.userWeightKg!.toStringAsFixed(1)} kg" : "unrecorded"}.',
    ));

    // Cite specific highest-energy historical meals if available
    if (yesterdayMeals.isNotEmpty) {
      final sortedByCal = List<HistoricalMealRecord>.from(yesterdayMeals)
        ..sort((a, b) => b.calories.compareTo(a.calories));
      final topMeal = sortedByCal.first;

      insights.add(KynoInsightItem(
        type: KynoInformationType.fact,
        title: 'Recent High-Energy Meal Drill-Down',
        detail: '• "${topMeal.mealName}" at ${topMeal.formattedTime} [${topMeal.section.name.toUpperCase()}]: ${topMeal.calories.toStringAsFixed(0)} kcal, ${topMeal.protein.toStringAsFixed(0)}g P, ${topMeal.carbs.toStringAsFixed(0)}g C, ${topMeal.fat.toStringAsFixed(0)}g F.',
      ));
    }

    // CALCULATION: Energy balance math
    final calcLines = <String>[];
    if (delta > 0) {
      calcLines.add('• Daily surplus: +${delta.toStringAsFixed(0)} kcal / day above target.');
      final biweeklySurplus = delta * 14;
      calcLines.add('• Cumulative 14-day energy surplus: approximately +${biweeklySurplus.toStringAsFixed(0)} kcal.');
      final estGainKg = biweeklySurplus / 7700.0;
      calcLines.add('• Expected tissue mass change: approximately +${estGainKg.toStringAsFixed(2)} kg over 14 days (based on 7,700 kcal/kg).');
    } else {
      calcLines.add('• Logged calories averaged ${delta.abs().toStringAsFixed(0)} kcal below target.');
      calcLines.add('• A logged calorie deficit is mathematically inconsistent with true adipose tissue gain unless unlogged calories occurred or water retention is elevated.');
    }

    insights.add(KynoInsightItem(
      type: KynoInformationType.calculation,
      title: 'Energy Balance Math',
      detail: calcLines.join('\n'),
    ));

    // INFERENCE: Non-moralizing explanation
    insights.add(KynoInsightItem(
      type: KynoInformationType.inference,
      title: 'Weight Assessment',
      detail: delta > 150
          ? 'Your logged records show an average daily surplus of +${delta.toStringAsFixed(0)} kcal over the past fortnight. Weight gain is consistent with sustained positive energy balance. In the context of your configured daily calorie target, a moderate surplus supports muscle hypertrophy when paired with progressive resistance training.'
          : 'If your logged intake shows a deficit but scale weight is increasing, short-term scale fluctuations are frequently driven by water retention, sodium intake, glycogen storage, or unlogged energy intake rather than structural fat gain.',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.recommendation,
      title: 'Target Alignment',
      detail: delta > 0
          ? 'If weight gain exceeds your target rate, reduce daily intake by 200–300 kcal toward your configured daily calorie target, keeping protein high at ${snapshot.targetDailyProtein.toStringAsFixed(0)}g.'
          : 'Track body weight consistently under identical morning conditions and monitor weekly rolling averages.',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.unknown,
      title: 'Untracked Variables',
      detail: 'Non-exercise physical activity (NEAT), daily sodium fluctuations, fluid balance, and unlogged foods are not tracked.',
    ));

    return KynoAnalysisResult(
      intent: KynoAnalysisIntent.weightGain,
      headline: 'Analysis of weight trends and energy balance across your history:',
      insights: insights,
    );
  }

  // ─── 6. "How was my nutrition yesterday?" ──────────────────────────────────
  KynoAnalysisResult analyzeYesterdaySummary(KynoUserFitnessSnapshot snapshot, {DateTime? date}) {
    final targetDate = date ?? DateTime.now().subtract(const Duration(days: 1));
    final meals = getMealsForDate(targetDate);
    final insights = <KynoInsightItem>[];

    if (meals.isEmpty) {
      insights.add(KynoInsightItem(
        type: KynoInformationType.fact,
        title: 'Yesterday Meal Log',
        detail: 'No meals were logged in your DayLog records for yesterday (${targetDate.month}/${targetDate.day}).',
      ));
      insights.add(KynoInsightItem(
        type: KynoInformationType.unknown,
        title: 'Nutrition Record',
        detail: 'Intake for yesterday was not entered in Kynetix.',
      ));
      return KynoAnalysisResult(
        intent: KynoAnalysisIntent.yesterdayNutrition,
        headline: 'No nutrition was logged yesterday (${targetDate.month}/${targetDate.day}).',
        insights: insights,
      );
    }

    final totalCal = meals.fold(0.0, (s, m) => s + m.calories);
    final totalPro = meals.fold(0.0, (s, m) => s + m.protein);
    final totalCarb = meals.fold(0.0, (s, m) => s + m.carbs);
    final totalFat = meals.fold(0.0, (s, m) => s + m.fat);

    final targetCal = snapshot.targetDailyCalories;
    final targetPro = snapshot.targetDailyProtein;

    // FACT: Day summary and specific meals
    final mealBulletList = meals.map((m) =>
        '• ${m.formattedTime} [${m.section.name.toUpperCase()}]: "${m.mealName}" – ${m.calories.toStringAsFixed(0)} kcal, ${m.protein.toStringAsFixed(0)}g P'
    ).join('\n');

    insights.add(KynoInsightItem(
      type: KynoInformationType.fact,
      title: 'Yesterday Intake Summary (${meals.length} meals logged)',
      detail: '$mealBulletList\n\nTotals: ${totalCal.toStringAsFixed(0)} kcal, ${totalPro.toStringAsFixed(0)}g P, ${totalCarb.toStringAsFixed(0)}g C, ${totalFat.toStringAsFixed(0)}g F.',
    ));

    // CALCULATION: Compare against configured targets
    final calPct = targetCal > 0 ? ((totalCal / targetCal) * 100).round() : 0;
    final proPct = targetPro > 0 ? ((totalPro / targetPro) * 100).round() : 0;
    final calDelta = totalCal - targetCal;
    final proDelta = totalPro - targetPro;

    insights.add(KynoInsightItem(
      type: KynoInformationType.calculation,
      title: 'Target Comparison Math',
      detail: '• Calories: ${totalCal.toStringAsFixed(0)} / ${targetCal.toStringAsFixed(0)} kcal ($calPct%, ${calDelta >= 0 ? "+${calDelta.toStringAsFixed(0)}" : calDelta.toStringAsFixed(0)} kcal)\n'
          '• Protein: ${totalPro.toStringAsFixed(0)} / ${targetPro.toStringAsFixed(0)}g ($proPct%, ${proDelta >= 0 ? "+${proDelta.toStringAsFixed(0)}" : proDelta.toStringAsFixed(0)}g)',
    ));

    // Find highest calorie and highest protein meal to explain result
    final sortedByCal = List<HistoricalMealRecord>.from(meals)..sort((a, b) => b.calories.compareTo(a.calories));
    final sortedByPro = List<HistoricalMealRecord>.from(meals)..sort((a, b) => b.protein.compareTo(a.protein));
    final topCal = sortedByCal.first;
    final topPro = sortedByPro.first;

    // INFERENCE: Explains the result using specific meals without moralizing
    insights.add(KynoInsightItem(
      type: KynoInformationType.inference,
      title: 'Nutritional Assessment',
      detail: 'Your day was anchored by "${topPro.mealName}" at ${topPro.formattedTime}, which contributed ${topPro.protein.toStringAsFixed(0)}g protein. The largest energy contributor was "${topCal.mealName}" at ${topCal.formattedTime} (${topCal.calories.toStringAsFixed(0)} kcal). In the context of your configured daily calorie target, yesterday was ${proPct >= 85 ? "well-aligned with" : "below"} your protein target.',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.recommendation,
      title: 'Next Step',
      detail: proPct < 85
          ? 'Carry forward the positive meal habits and add one more 20–30g protein anchor today.'
          : 'Maintain your current nutrition routine and training recovery.',
    ));

    insights.add(KynoInsightItem(
      type: KynoInformationType.unknown,
      title: 'Untracked Variables',
      detail: 'Hydration status, electrolyte intake, and micronutrient distribution are not tracked.',
    ));

    return KynoAnalysisResult(
      intent: KynoAnalysisIntent.yesterdayNutrition,
      headline: 'Yesterday\'s nutrition summary and meal drill-down:',
      insights: insights,
    );
  }
}
