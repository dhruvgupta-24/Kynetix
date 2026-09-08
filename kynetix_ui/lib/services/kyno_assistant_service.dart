import 'dart:async';
import 'kyno_context_service.dart';
import 'kyno_progression_engine.dart';
import 'saved_meal_service.dart';
import 'workout_service.dart';

class KynoChatMessage {
  final String id;
  final bool isUser;
  final String text;
  final DateTime timestamp;
  final List<KynoInsightItem>? structuredInsights;

  const KynoChatMessage({
    required this.id,
    required this.isUser,
    required this.text,
    required this.timestamp,
    this.structuredInsights,
  });
}

/// Specialized assistant service powered by the unified KynoContextService.
/// Resolves queries with structured separation of Facts, Calculations, Inferences, and Recommendations.
class KynoAssistantService {
  KynoAssistantService._();
  static final KynoAssistantService instance = KynoAssistantService._();

  /// Generates dynamic contextual suggestion chips based on real user state.
  List<String> getContextualPromptSuggestions() {
    final snapshot = KynoContextService.instance.getSnapshot();
    final chips = <String>[];

    if (snapshot.training.hasWorkoutToday) {
      chips.add('What did I train today?');
      chips.add('I trained today. Am I eating enough protein to recover?');
    } else {
      chips.add('What did I train today?');
    }

    if (snapshot.nutrition.remainingProtein > 5.0) {
      chips.add('How much protein have I had today?');
      chips.add('What should I eat tonight?');
    } else {
      chips.add('How many calories do I have left?');
    }

    if (snapshot.training.exercisesTrainedToday.isNotEmpty) {
      final firstEx = snapshot.training.exercisesTrainedToday.first;
      chips.add('Should I increase $firstEx?');
    } else {
      chips.add('How am I progressing on bench press?');
    }

    return chips;
  }

  /// Processes user query through the single Kyno Context layer.
  Future<KynoChatMessage> processQuery(String query) async {
    print('[KYNO_QUERY] Processing query: "$query"');

    // LIVE CONTEXT: Force refresh to guarantee 100% up-to-date state
    final snapshot = KynoContextService.instance.getSnapshot(forceRefresh: true);
    print('[KYNO_CONTEXT] Snapshot loaded: Training=${snapshot.training.hasWorkoutToday ? "${snapshot.training.setsLoggedToday} sets" : "none"}, Nutrition=${snapshot.nutrition.consumedCalories.toStringAsFixed(0)} kcal / ${snapshot.nutrition.consumedProtein.toStringAsFixed(1)}g pro');

    final q = query.toLowerCase().trim();
    final insights = <KynoInsightItem>[];
    final buffer = StringBuffer();
    String responseSource = 'Unified KynoContextSnapshot';

    // ── 1. Cross-Domain Recovery Query ──────────────────────────────────────
    // e.g. "I trained chest today. Am I eating enough protein to recover?"
    final isCrossDomain = (q.contains('recover') && (q.contains('train') || q.contains('protein') || q.contains('eat') || q.contains('chest') || q.contains('leg'))) ||
        ((q.contains('train') || q.contains('workout')) && (q.contains('protein') || q.contains('eat') || q.contains('calorie')));

    if (isCrossDomain) {
      responseSource = 'Cross-Domain: Authoritative WorkoutService + DayLog + RecoveryEngine';
      print('[KYNO_RESPONSE_SOURCE] Source: $responseSource');

      final trained = snapshot.training.hasWorkoutToday;
      final proConsumed = snapshot.nutrition.consumedProtein;
      final proTarget = snapshot.nutrition.targetProtein;
      final deficit = snapshot.crossDomain.proteinDeficitG;
      final exercisesTrained = snapshot.training.exercisesTrainedToday;
      final splitName = snapshot.training.todaySplitDayName ?? 'Session';

      // Check if user specifically asked about chest or other bodypart
      final mentionsChest = q.contains('chest');
      final mentionsLegs = q.contains('leg') || q.contains('squat');
      final trainedChest = exercisesTrained.any((e) => e.toLowerCase().contains('bench') || e.toLowerCase().contains('chest') || e.toLowerCase().contains('fly') || e.toLowerCase().contains('press')) ||
          (snapshot.training.todaySplitDayName?.toLowerCase().contains('chest') ?? false);
      final trainedLegs = exercisesTrained.any((e) => e.toLowerCase().contains('squat') || e.toLowerCase().contains('leg') || e.toLowerCase().contains('lunge') || e.toLowerCase().contains('calf')) ||
          (snapshot.training.todaySplitDayName?.toLowerCase().contains('leg') ?? false);

      if (mentionsChest && !trainedChest && trained) {
        insights.add(KynoInsightItem(
          type: KynoInformationType.fact,
          title: 'Chest Training Status',
          detail: 'You did not log a chest workout today. Today\'s logged session was $splitName (${exercisesTrained.join(", ")}).',
        ));
      } else if (mentionsLegs && !trainedLegs && trained) {
        insights.add(KynoInsightItem(
          type: KynoInformationType.fact,
          title: 'Leg Training Status',
          detail: 'You did not log a leg workout today. Today\'s logged session was $splitName (${exercisesTrained.join(", ")}).',
        ));
      } else if (trained) {
        final details = snapshot.training.todayDetailedEntries.isNotEmpty
            ? snapshot.training.todayDetailedEntries.take(3).join('\n• ')
            : '${exercisesTrained.join(", ")} (${snapshot.training.setsLoggedToday} sets, ${snapshot.training.volumeTrainedTodayKg.toStringAsFixed(0)} kg volume)';

        insights.add(KynoInsightItem(
          type: KynoInformationType.fact,
          title: 'Verified Training Today ($splitName)',
          detail: '• $details\nTotal Volume: ${snapshot.training.volumeTrainedTodayKg.toStringAsFixed(0)} kg across ${snapshot.training.workingSetsLoggedToday} working sets.',
        ));
      } else {
        insights.add(KynoInsightItem(
          type: KynoInformationType.fact,
          title: 'Training Today',
          detail: 'No workout has been logged today yet.',
        ));
      }

      insights.add(KynoInsightItem(
        type: KynoInformationType.fact,
        title: 'Verified Nutrition Today',
        detail: '${proConsumed.toStringAsFixed(1)}g protein consumed of ${proTarget.toStringAsFixed(0)}g daily target (${snapshot.nutrition.consumedCalories.toStringAsFixed(0)} kcal logged).',
      ));

      insights.add(KynoInsightItem(
        type: KynoInformationType.calculation,
        title: 'Daily Protein Target Balance',
        detail: deficit <= 0
            ? 'Daily target met! (${(proConsumed - proTarget).abs().toStringAsFixed(0)}g surplus above ${proTarget.toStringAsFixed(0)}g target).'
            : '${deficit.toStringAsFixed(1)}g protein remaining to reach ${proTarget.toStringAsFixed(0)}g daily target.${snapshot.nutrition.proteinPerKg != null ? " Current intake: ${snapshot.nutrition.proteinPerKg!.toStringAsFixed(2)} g/kg." : ""}',
      ));

      insights.add(KynoInsightItem(
        type: KynoInformationType.inference,
        title: 'Training Recovery Demand',
        detail: trained
            ? 'Today\'s ${snapshot.training.todaySplitDayName ?? "training"} session (${snapshot.training.volumeTrainedTodayKg.toStringAsFixed(0)} kg volume across ${snapshot.training.workingSetsLoggedToday} working sets) increases muscle protein synthesis demand, raising the importance of meeting your daily protein target.'
            : 'Rest day: protein intake supports baseline muscle tissue maintenance and turnover.',
      ));

      insights.add(KynoInsightItem(
        type: KynoInformationType.recommendation,
        title: 'Nutrition Strategy',
        detail: deficit <= 0
            ? 'Daily protein target fulfilled. Focus on adequate hydration and recovery sleep.'
            : 'Distribute your remaining ${deficit.toStringAsFixed(0)}g protein across your upcoming meals and snacks today.',
      ));

      buffer.writeln('Here is your cross-domain recovery assessment:');
    }
    // ── 2. Exercise Progression Query ───────────────────────────────────────
    // e.g. "How am I progressing on bench press?", "Should I increase weight?"
    else if (q.contains('bench') || q.contains('progress') || q.contains('increase') || (q.contains('should') && q.contains('weight')) || q.contains('squat') || q.contains('deadlift')) {
      responseSource = 'Authoritative Workout History + KynoProgressionEngine';
      print('[KYNO_RESPONSE_SOURCE] Source: $responseSource');

      String searchEx = 'Barbell Bench Press';
      if (q.contains('bench')) {
        searchEx = 'Barbell Bench Press';
      } else if (q.contains('squat')) {
        searchEx = 'Barbell Squat';
      } else if (q.contains('deadlift')) {
        searchEx = 'Deadlift';
      } else if (q.contains('overhead') || q.contains('press')) {
        searchEx = 'Overhead Press';
      } else if (snapshot.training.exercisesTrainedToday.isNotEmpty) {
        searchEx = snapshot.training.exercisesTrainedToday.first;
      }

      final exHistory = KynoContextService.instance.getCanonicalExerciseHistory(searchEx);
      final ws = WorkoutService.instance;
      final matching = ws.allExercises.where((e) =>
          e.id == exHistory.canonicalName ||
          e.name.toLowerCase().contains(searchEx.toLowerCase()) ||
          searchEx.toLowerCase().contains(e.name.toLowerCase())).toList();

      if (matching.isNotEmpty) {
        final exercise = matching.first;
        final advice = KynoProgressionEngine.instance.computeAdvice(
          exercise: exercise,
          splitDayName: snapshot.training.todaySplitDayName ?? 'Strength Session',
        );

        insights.add(KynoInsightItem(
          type: KynoInformationType.fact,
          title: '${exercise.name} Logged History',
          detail: exHistory.totalSessions > 0
              ? 'Sessions logged: ${exHistory.totalSessions} • Total working sets: ${exHistory.totalSets}.\n'
                  'Recent working sets: ${exHistory.recentWorkingSets.isNotEmpty ? exHistory.recentWorkingSets.join(", ") : "None recorded"}.\n'
                  'Lifetime best: ${exHistory.lifetimeBest ?? "None yet"}.'
              : 'No previous historical sessions recorded for ${exercise.name}.',
        ));

        insights.add(KynoInsightItem(
          type: KynoInformationType.calculation,
          title: 'Progression Target',
          detail: advice.todayTarget,
        ));

        insights.add(KynoInsightItem(
          type: KynoInformationType.inference,
          title: 'Performance Analysis',
          detail: advice.summary,
        ));

        insights.add(KynoInsightItem(
          type: KynoInformationType.recommendation,
          title: 'Action: ${advice.action}',
          detail: '${advice.styleLabel} protocol.\nTarget: ${advice.todayTarget}.\nNext milestone: ${advice.nextMilestone}',
        ));

        buffer.writeln('Progression analysis for ${exercise.name}:');
      } else {
        insights.add(KynoInsightItem(
          type: KynoInformationType.fact,
          title: 'Exercise Not Found',
          detail: 'I do not have logged history for "$searchEx" in your exercise database.',
        ));
        insights.add(KynoInsightItem(
          type: KynoInformationType.recommendation,
          title: 'General Double Progression Rule',
          detail: 'Keep the weight constant until you achieve the top rep target on all working sets before adding weight.',
        ));
        buffer.writeln('Exercise details:');
      }
    }
    // ── 3. Nutrition & Protein Query ─────────────────────────────────────────
    // e.g. "How much protein have I had today?", "How many calories do I have left?"
    else if (q.contains('protein') || q.contains('calorie') || q.contains('macro') || q.contains('left') || q.contains('eat') || q.contains('ate') || q.contains('food')) {
      responseSource = 'Authoritative DayLog / Nutrition Store';
      print('[KYNO_RESPONSE_SOURCE] Source: $responseSource');

      final proConsumed = snapshot.nutrition.consumedProtein;
      final proTarget = snapshot.nutrition.targetProtein;
      final calConsumed = snapshot.nutrition.consumedCalories;
      final calTarget = snapshot.nutrition.targetCalories;
      final remainingCal = snapshot.nutrition.remainingCalories;
      final remainingPro = snapshot.nutrition.remainingProtein;

      insights.add(KynoInsightItem(
        type: KynoInformationType.fact,
        title: 'Logged Nutrition Today',
        detail: '${calConsumed.toStringAsFixed(0)} kcal • ${proConsumed.toStringAsFixed(1)}g protein • '
            '${snapshot.nutrition.consumedCarbs.toStringAsFixed(0)}g carbs • ${snapshot.nutrition.consumedFat.toStringAsFixed(0)}g fat.',
      ));

      if (snapshot.nutrition.mealsLoggedToday.isNotEmpty) {
        insights.add(KynoInsightItem(
          type: KynoInformationType.fact,
          title: 'Logged Meals (${snapshot.nutrition.mealsLoggedToday.length})',
          detail: '• ${snapshot.nutrition.mealsLoggedToday.join("\n• ")}',
        ));
      } else {
        insights.add(KynoInsightItem(
          type: KynoInformationType.fact,
          title: 'Logged Meals',
          detail: 'No individual meals logged yet today.',
        ));
      }

      insights.add(KynoInsightItem(
        type: KynoInformationType.calculation,
        title: 'Remaining Daily Targets',
        detail: 'Calories: ${remainingCal.toStringAsFixed(0)} kcal remaining (${calConsumed.toStringAsFixed(0)} / ${calTarget.toStringAsFixed(0)} kcal)\n'
            'Protein: ${remainingPro.toStringAsFixed(1)}g remaining (${proConsumed.toStringAsFixed(1)} / ${proTarget.toStringAsFixed(0)}g target)',
      ));

      if (q.contains('dinner') || q.contains('tonight') || q.contains('what should i eat')) {
        final savedMatches = SavedMealService.instance.search('protein', limit: 2);
        final suggestion = savedMatches.isNotEmpty
            ? 'Consider your saved meal "${savedMatches.first.title}" (${savedMatches.first.calories.toStringAsFixed(0)} kcal, ${savedMatches.first.protein.toStringAsFixed(0)}g protein).'
            : 'Aim for a 30–45g protein meal such as chicken breast (150g), eggs + egg whites, Greek yogurt, or a whey shake with oats.';

        insights.add(KynoInsightItem(
          type: KynoInformationType.recommendation,
          title: 'Suggested Meal',
          detail: suggestion,
        ));
      } else if (remainingPro > 5.0) {
        insights.add(KynoInsightItem(
          type: KynoInformationType.inference,
          title: 'Nutrition State',
          detail: 'You have a ${remainingPro.toStringAsFixed(0)}g protein deficit to close before the end of the day.',
        ));
        insights.add(KynoInsightItem(
          type: KynoInformationType.recommendation,
          title: 'Next Step',
          detail: 'Prioritize a protein-dense food for your next meal or snack to stay on track for muscle synthesis.',
        ));
      } else {
        insights.add(KynoInsightItem(
          type: KynoInformationType.inference,
          title: 'Nutrition State',
          detail: 'Daily protein target has been reached!',
        ));
        insights.add(KynoInsightItem(
          type: KynoInformationType.recommendation,
          title: 'Maintenance',
          detail: 'Stay hydrated and keep remaining calories balanced within your daily allowance.',
        ));
      }

      buffer.writeln('Here is your live nutrition breakdown:');
    }
    // ── 4. Training Status Query ────────────────────────────────────────────
    // e.g. "What did I train today?", "How was my workout?"
    else if (q.contains('train') || q.contains('workout') || q.contains('gym') || q.contains('exercise') || q.contains('session')) {
      responseSource = 'Authoritative WorkoutService State';
      print('[KYNO_RESPONSE_SOURCE] Source: $responseSource');

      if (snapshot.training.hasWorkoutToday) {
        final splitName = snapshot.training.todaySplitDayName ?? 'Workout Session';
        insights.add(KynoInsightItem(
          type: KynoInformationType.fact,
          title: 'Today\'s Workout: $splitName',
          detail: 'Completed ${snapshot.training.setsLoggedToday} sets (${snapshot.training.workingSetsLoggedToday} working sets) across '
              '${snapshot.training.exercisesTrainedToday.length} exercises.\n'
              'Total Volume: ${snapshot.training.volumeTrainedTodayKg.toStringAsFixed(0)} kg.',
        ));

        if (snapshot.training.todayDetailedEntries.isNotEmpty) {
          insights.add(KynoInsightItem(
            type: KynoInformationType.fact,
            title: 'Exercise Details',
            detail: '• ${snapshot.training.todayDetailedEntries.join("\n• ")}',
          ));
        }

        insights.add(KynoInsightItem(
          type: KynoInformationType.calculation,
          title: 'Session Workload',
          detail: 'Average volume per exercise: ${(snapshot.training.volumeTrainedTodayKg / (snapshot.training.exercisesTrainedToday.isNotEmpty ? snapshot.training.exercisesTrainedToday.length : 1)).toStringAsFixed(0)} kg.',
        ));

        if (snapshot.training.previousSessionOfSameSplit != null) {
          insights.add(KynoInsightItem(
            type: KynoInformationType.inference,
            title: 'Historical Comparison',
            detail: 'Previous session: ${snapshot.training.previousSessionOfSameSplit}',
          ));
        }

        insights.add(KynoInsightItem(
          type: KynoInformationType.recommendation,
          title: 'Post-Workout Guidance',
          detail: snapshot.crossDomain.nutritionAdvice,
        ));

        buffer.writeln('Here is what you trained today:');
      } else {
        insights.add(KynoInsightItem(
          type: KynoInformationType.fact,
          title: 'No Workout Logged Today',
          detail: 'You have not logged any workout sets for today yet.',
        ));

        insights.add(KynoInsightItem(
          type: KynoInformationType.calculation,
          title: 'Training Consistency',
          detail: 'Averaging ${snapshot.training.averageSessionsPerWeek} sessions/week across ${snapshot.training.totalCompletedSessions} lifetime sessions.',
        ));

        insights.add(KynoInsightItem(
          type: KynoInformationType.recommendation,
          title: 'Plan',
          detail: snapshot.training.isGymDayScheduled
              ? 'Today is a scheduled workout day (${snapshot.training.todaySplitDayName ?? "Gym"}). Ready to start when you are!'
              : 'Today is designated as a recovery day. Prioritize nutrition and rest.',
        ));

        buffer.writeln('Training status for today:');
      }
    }
    // ── 5. General Assistant Snapshot ───────────────────────────────────────
    else {
      responseSource = 'Unified Multi-Domain KynoContextSnapshot';
      print('[KYNO_RESPONSE_SOURCE] Source: $responseSource');

      insights.addAll(snapshot.structuredInsights);
      buffer.writeln('Here is your personal fitness status snapshot:');
    }

    return KynoChatMessage(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
      isUser: false,
      text: buffer.toString().trim(),
      timestamp: DateTime.now(),
      structuredInsights: insights,
    );
  }
}
