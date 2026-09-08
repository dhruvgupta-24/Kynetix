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
      chips.add('How did my workout go today?');
    } else {
      chips.add('What is scheduled for today?');
    }

    if (snapshot.nutrition.remainingProtein > 5.0) {
      chips.add('What should I eat to hit protein?');
    } else {
      chips.add('Did I eat enough today?');
    }

    if (snapshot.training.exercisesTrainedToday.isNotEmpty) {
      final firstEx = snapshot.training.exercisesTrainedToday.first;
      chips.add('Should I increase $firstEx?');
    } else {
      chips.add('Am I progressing overall?');
    }

    chips.add('How much protein do I need?');

    return chips;
  }

  /// Processes user query through the single Kyno Context layer.
  Future<KynoChatMessage> processQuery(String query) async {
    final snapshot = KynoContextService.instance.getSnapshot(forceRefresh: true);
    final q = query.toLowerCase().trim();

    final insights = <KynoInsightItem>[];
    final buffer = StringBuffer();

    if (q.contains('workout') || q.contains('gym') || q.contains('train') || q.contains('exercise')) {
      // Training query
      if (snapshot.training.hasWorkoutToday) {
        insights.add(KynoInsightItem(
          type: KynoInformationType.fact,
          title: 'Today\'s Session: ${snapshot.training.todaySplitDayName ?? "Workout"}',
          detail: '${snapshot.training.exercisesTrainedToday.length} exercises completed • '
              '${snapshot.training.setsLoggedToday} sets • '
              '${snapshot.training.volumeTrainedTodayKg.toStringAsFixed(0)} kg total volume.',
        ));
        insights.add(KynoInsightItem(
          type: KynoInformationType.calculation,
          title: 'Exercises Trained',
          detail: snapshot.training.exercisesTrainedToday.join(', '),
        ));
        insights.add(KynoInsightItem(
          type: KynoInformationType.inference,
          title: 'Stimulus & Recovery',
          detail: snapshot.crossDomain.recoveryStatus,
        ));
        insights.add(KynoInsightItem(
          type: KynoInformationType.recommendation,
          title: 'Next Action',
          detail: snapshot.crossDomain.nutritionAdvice,
        ));

        buffer.writeln('Here is how your workout went today:');
      } else {
        insights.add(KynoInsightItem(
          type: KynoInformationType.fact,
          title: 'No Session Logged Today',
          detail: 'You have not logged a workout for today yet.',
        ));
        insights.add(KynoInsightItem(
          type: KynoInformationType.calculation,
          title: 'Weekly Frequency',
          detail: 'Averaging ${snapshot.training.averageSessionsPerWeek} sessions per week across ${snapshot.training.totalCompletedSessions} lifetime workouts.',
        ));
        insights.add(KynoInsightItem(
          type: KynoInformationType.recommendation,
          title: 'Schedule',
          detail: 'Today is designated for rest and recovery or light mobility. Target ${snapshot.nutrition.targetProtein.toStringAsFixed(0)}g protein.',
        ));

        buffer.writeln('No active workout session logged for today yet.');
      }
    } else if (q.contains('protein') || q.contains('eat') || q.contains('food') || q.contains('meal') || q.contains('dinner') || q.contains('tonight')) {
      // Nutrition query
      final remainingPro = snapshot.nutrition.remainingProtein;
      final remainingCal = snapshot.nutrition.remainingCalories;

      insights.add(KynoInsightItem(
        type: KynoInformationType.fact,
        title: 'Logged Nutrition Today',
        detail: '${snapshot.nutrition.consumedCalories.toStringAsFixed(0)} kcal • ${snapshot.nutrition.consumedProtein.toStringAsFixed(1)}g protein.',
      ));
      insights.add(KynoInsightItem(
        type: KynoInformationType.calculation,
        title: 'Remaining Targets',
        detail: '${remainingCal.toStringAsFixed(0)} kcal and ${remainingPro.toStringAsFixed(0)}g protein remaining to reach your daily goal.',
      ));

      final savedMeals = SavedMealService.instance.search('protein', limit: 2);
      if (remainingPro > 5.0) {
        insights.add(KynoInsightItem(
          type: KynoInformationType.inference,
          title: 'Protein Gap',
          detail: 'You are ${remainingPro.toStringAsFixed(0)}g short of your muscle preservation target for today.',
        ));

        final suggestion = savedMeals.isNotEmpty
            ? 'Consider having ${savedMeals.first.title} (${savedMeals.first.protein.toStringAsFixed(0)}g protein) or Greek yogurt/whey.'
            : 'Aim for a 25–40g protein meal (chicken breast, eggs, whey isolate, or paneer/tofu).';

        insights.add(KynoInsightItem(
          type: KynoInformationType.recommendation,
          title: 'Meal Suggestion',
          detail: suggestion,
        ));
      } else {
        insights.add(KynoInsightItem(
          type: KynoInformationType.inference,
          title: 'Target Achieved',
          detail: 'Protein target has been successfully achieved for optimal recovery!',
        ));
        insights.add(KynoInsightItem(
          type: KynoInformationType.recommendation,
          title: 'Maintenance',
          detail: 'Hydrate well and keep calories balanced within ${snapshot.nutrition.targetCalories.toStringAsFixed(0)} kcal.',
        ));
      }

      buffer.writeln('Here is your nutrition breakdown for today:');
    } else if (q.contains('bench') || q.contains('progress') || q.contains('increase') || q.contains('weight') || q.contains('squat') || q.contains('deadlift')) {
      // Progression query
      String searchEx = 'Bench Press';
      if (q.contains('squat')) searchEx = 'Squat';
      if (q.contains('deadlift')) searchEx = 'Deadlift';
      if (q.contains('overhead') || q.contains('press')) searchEx = 'Overhead Press';

      final exHistory = KynoContextService.instance.getCanonicalExerciseHistory(searchEx);
      final ws = WorkoutService.instance;
      final matching = ws.allExercises.where((e) => e.name.toLowerCase().contains(searchEx.toLowerCase())).toList();

      if (matching.isNotEmpty) {
        final advice = KynoProgressionEngine.instance.computeAdvice(
          exercise: matching.first,
          splitDayName: snapshot.training.todaySplitDayName ?? 'Chest',
        );

        insights.add(KynoInsightItem(
          type: KynoInformationType.fact,
          title: '${exHistory.canonicalName} History',
          detail: 'Recent working sets: ${exHistory.recentWorkingSets.isNotEmpty ? exHistory.recentWorkingSets.join(", ") : "None recorded"}. Lifetime best: ${exHistory.lifetimeBest ?? "None"}.',
        ));
        insights.add(KynoInsightItem(
          type: KynoInformationType.calculation,
          title: 'Target Protocol',
          detail: advice.todayTarget,
        ));
        insights.add(KynoInsightItem(
          type: KynoInformationType.inference,
          title: 'Progression Rationale',
          detail: advice.summary,
        ));
        insights.add(KynoInsightItem(
          type: KynoInformationType.recommendation,
          title: advice.action,
          detail: '${advice.styleLabel} • Target: ${advice.todayTarget}. Next milestone: ${advice.nextMilestone}',
        ));

        buffer.writeln('Here is your progression evaluation for ${exHistory.canonicalName}:');
      } else {
        insights.add(KynoInsightItem(
          type: KynoInformationType.fact,
          title: 'Exercise Query',
          detail: 'No direct historical sessions logged under this exercise name.',
        ));
        insights.add(KynoInsightItem(
          type: KynoInformationType.recommendation,
          title: 'Guidance',
          detail: 'Apply Double Progression: keep the load until you hit the top of the rep range on all sets.',
        ));
        buffer.writeln('Progression guidance:');
      }
    } else {
      // General assistant overview
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
