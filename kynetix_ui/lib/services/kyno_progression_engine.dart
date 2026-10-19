import '../models/day_log.dart';
import '../models/workout_session.dart';
import '../models/workout_split.dart';
import 'exercise_library_service.dart';
import 'exercise_media_service.dart';
import 'kyno_coach_planner.dart';
import 'nutrition_target_engine.dart';
import 'workout_service.dart';

/// Structured, rich progression recommendation produced by Kyno.
class KynoProgressionAdvice {
  final String action; // e.g. "KEEP 70.0 KG" or "INCREASE TO 72.5 KG"
  final String styleLabel; // e.g. "Double Progression"
  final String todayTarget; // e.g. "70.0 kg • 4 sets • 8-10 reps"
  final String summary; // Clear, non-truncated primary coaching recommendation
  final List<String> evidence; // Explicit factual bullet points (reps, volume, history)
  final String nextMilestone; // Explicit criteria to trigger the next progression
  final String confidence; // "High", "Moderate", "Safety Priority", "Deload"
  final bool isDeload;
  final List<double> spark1RmTrend;

  /// Kyno's full read: pattern, set-by-set plan, swap, session verdict.
  /// Null for hand-built advice (fallbacks, previews).
  final CoachPlan? plan;

  const KynoProgressionAdvice({
    required this.action,
    required this.styleLabel,
    required this.todayTarget,
    required this.summary,
    required this.evidence,
    required this.nextMilestone,
    required this.confidence,
    this.isDeload = false,
    required this.spark1RmTrend,
    this.plan,
  });

  /// Formatted weight helper
  static String fmtWeight(double w) =>
      w == w.truncateToDouble() ? '${w.toInt()} kg' : '${w.toStringAsFixed(1)} kg';
}

/// Kyno's progression advice for one exercise, read from the person's whole
/// history of it: [KynoCoachPlanner] does the coaching, this adapts it for
/// the stage card, the ghost row and the offline assistant.
class KynoProgressionEngine {
  KynoProgressionEngine._();
  static final KynoProgressionEngine instance = KynoProgressionEngine._();

  /// The coach plan for [exercise], with today's diet and sleep context.
  CoachPlan planFor(Exercise exercise, {DateTime? now}) {
    final ws = WorkoutService.instance;
    final at = now ?? DateTime.now();
    return KynoCoachPlanner.plan(
      exercise: exercise,
      history: historyOf(exercise),
      now: at,
      dietFor: dietOn,
      sleepHours: ws.sleepHours,
      library: ExerciseLibraryService.instance.allDefinitions,
      doneBefore: {
        for (final s in ws.sessions)
          for (final e in s.entries)
            if (!e.isEmpty) e.exercise.id,
      },
    );
  }

  /// Sessions with [exercise], newest first. Looks under the saved id and
  /// the canonical media id, which can differ for older saves.
  List<({DateTime date, ExerciseEntry entry})> historyOf(Exercise exercise, {int limit = 12}) {
    final ws = WorkoutService.instance;
    final ids = {exercise.id, ExerciseMediaService.instance.getCanonicalId(exercise.id)};
    final out = <({DateTime date, ExerciseEntry entry})>[];
    for (final s in ws.sessions.reversed) {
      for (final e in s.entries) {
        if (ids.contains(e.exercise.id) && !e.isEmpty && !e.isSkipped) {
          out.add((date: s.date, entry: e));
          break;
        }
      }
      if (out.length >= limit) break;
    }
    return out;
  }

  /// Food logged on [day] against that day's target. Reads the store without
  /// creating an empty day.
  static DietDay? dietOn(DateTime day) {
    final log = dayLogStore[dateKey(day)];
    if (log == null || log.isEmpty) {
      return const DietDay(calories: 0, protein: 0, calorieTarget: 0, proteinTarget: 0, logged: false);
    }
    final target = NutritionTargetEngine.instance.effectiveTargetForDate(day, log: log);
    return DietDay(
      calories: log.totalCaloriesMid,
      protein: log.totalProteinMid,
      calorieTarget: log.targetCalories ?? target.calories,
      proteinTarget: log.targetProtein ?? target.protein,
      logged: true,
    );
  }

  /// Personalized progression advice for [exercise].
  KynoProgressionAdvice computeAdvice({
    required Exercise exercise,
    required String splitDayName,
  }) {
    final plan = planFor(exercise);
    final top = plan.sets.isEmpty ? null : plan.sets.reduce((a, b) => a.load >= b.load ? a : b);
    final load = top == null ? '' : (top.bodyweight ? (top.load > 0 ? 'BW + ${_kg(top.load)} KG' : 'BODYWEIGHT') : '${_kg(top.load)} KG');

    final action = switch (plan.action) {
      CoachAction.increase => 'INCREASE TO $load',
      CoachAction.addReps || CoachAction.hold => 'KEEP $load',
      CoachAction.deload => 'DELOAD TO $load',
      CoachAction.rebuild => 'STEP BACK TO $load',
      CoachAction.calibrate => 'CALIBRATE BASELINE',
    };
    final straight = plan.pattern == LoadingPattern.straight || plan.pattern == LoadingPattern.straightFading;
    final style = plan.action == CoachAction.deload
        ? 'Active Recovery'
        : straight && exercise.targetRepMin < exercise.targetRepMax
            ? 'Double Progression'
            : plan.pattern.label;

    return KynoProgressionAdvice(
      action: action.trim(),
      styleLabel: style,
      todayTarget: plan.sets.isEmpty
          ? '${exercise.targetSets} sets • ${exercise.targetRepMin}-${exercise.targetRepMax} reps (Moderate RPE 7-8)'
          : plan.setsLine,
      summary: plan.summary,
      evidence: [
        ...plan.reasons,
        if (plan.verdictLine.isNotEmpty) plan.verdictLine,
      ],
      nextMilestone: plan.nextMilestone,
      confidence: switch (plan.action) {
        CoachAction.deload => 'Deload',
        CoachAction.hold => 'Safety Priority',
        CoachAction.calibrate => 'Baseline',
        _ => plan.patternConfidence >= 0.66 ? 'High' : 'Moderate',
      },
      isDeload: plan.action == CoachAction.deload,
      spark1RmTrend: plan.e1rmTrend,
      plan: plan,
    );
  }
}

String _kg(double v) => v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
