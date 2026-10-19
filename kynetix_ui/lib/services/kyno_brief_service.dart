// Everything Kyno knows, in one compact JSON brief.
//
// The phone holds the whole picture: every logged day, every set, steps,
// weight and the target engine. This builds a bounded summary of it for the
// coach model: today's numbers, two weeks of eating, lift trends with the
// eating and activity around them, and food options that fit what's left.
// Numbers here are computed, not guessed, so Kyno explains instead of
// inventing. User-typed text (meal and exercise names) is sent as data and
// the server fences it.

import 'dart:convert';
import 'dart:math' as math;

import '../models/day_log.dart';
import '../models/user_profile.dart';
import 'body_metrics_service.dart';
import 'fasting_service.dart';
import 'health_service.dart';
import 'kyno_fuel_planner.dart';
import 'kyno_notes_service.dart';
import 'micronutrient_service.dart';
import 'nutrition_target_engine.dart';
import 'profile_service.dart';
import 'kyno_coach_planner.dart';
import 'kyno_progression_engine.dart';
import 'workout_service.dart';
import '../models/workout_split.dart' show Exercise;

class KynoBrief {
  const KynoBrief({required this.json, required this.fuelPlan});

  /// The bounded context sent with every Kyno question.
  final Map<String, dynamic> json;

  /// Today's "what to eat" plan (also inside [json]).
  final FuelPlan? fuelPlan;

  String encode() => jsonEncode(json);
}

class KynoBriefService {
  KynoBriefService._();
  static final KynoBriefService instance = KynoBriefService._();

  /// Hard cap on the encoded brief (the server rejects larger ones).
  static const int maxChars = 16000;

  KynoBrief build({DateTime? now, Map<String, DayLog>? store, UserProfile? profile}) {
    final t = now ?? DateTime.now();
    final today = DateTime(t.year, t.month, t.day);
    final logs = store ?? dayLogStore;
    final prof = profile ?? ProfileService.instance.currentUserProfile;
    final engine = NutritionTargetEngine.instance;
    final health = HealthService().lastSyncResult;
    final ws = WorkoutService.instance;

    final out = <String, dynamic>{'generated_for': _key(today), 'local_time': _hhmm(t)};

    // ── Profile & plan ───────────────────────────────────────────────────────
    if (prof != null) {
      final plan = engine.weeklyPlan(prof, health: health);
      out['profile'] = {
        'goal': prof.goal,
        'sex': prof.gender,
        'age': prof.age,
        'height_cm': prof.height.round(),
        'weight_kg': _r1(prof.weight),
        'training_days_per_week': '${prof.workoutDaysMin}-${prof.workoutDaysMax}',
        'maintenance_kcal': plan.maintenanceCalories.round(),
        'avg_daily_target_kcal': plan.avgDailyCalories.round(),
        'training_day_kcal': plan.trainingDayCalories.round(),
        'rest_day_kcal': plan.restDayCalories.round(),
        'avg_daily_protein_g': plan.avgDailyProtein.round(),
      };
    }

    // ── Today ────────────────────────────────────────────────────────────────
    final todayLog = logs[_key(today)] ?? DayLog();
    final dayPlan = ws.planFor(today, log: todayLog);
    FuelPlan? fuel;
    if (prof != null) {
      final target = engine.effectiveTargetForDate(today, profile: prof, health: health, log: todayLog);
      final split = engine.macroSplit(target.calories, target.protein, profile: prof);
      final eaten = _eaten(todayLog);
      final remaining = {
        'kcal': (target.calories - eaten.kcal).round(),
        'protein_g': math.max(0, target.protein - eaten.protein).round(),
        'carbs_g': (split.carbs - eaten.carbs).round(),
        'fat_g': (split.fat - eaten.fat).round(),
      };
      out['today'] = {
        'day_type': dayPlan.label,
        'day_type_source': dayPlan.source.name,
        'target': {
          'kcal': target.calories.round(),
          'protein_g': target.protein.round(),
          'carbs_g': split.carbs.round(),
          'fat_g': split.fat.round(),
          if (todayLog.gymDay?.targetCaloriesOverride != null) 'kcal_set_by_user': true,
        },
        'eaten': {
          'kcal': eaten.kcal.round(),
          'protein_g': eaten.protein.round(),
          'carbs_g': eaten.carbs.round(),
          'fat_g': eaten.fat.round(),
          'fiber_g': eaten.fiber.round(),
        },
        'remaining': remaining,
        'meals': [
          for (final e in todayLog.allEntries.take(16))
            {
              'meal': e.section.displayName,
              'food': _name(e),
              'kcal': e.calMid.round(),
              'protein_g': e.protMid.round(),
            },
        ],
        'workout_logged': ws.sessionFor(today) != null,
      };

      // What to eat for the rest of the day.
      final history = KynoFuelPlanner.historyFrom(logs, today: today);
      final diets = KynoFuelPlanner.inferDiets(history.map((f) => f.name));
      fuel = KynoFuelPlanner.plan(
        gap: FuelGap(
          kcal: target.calories - eaten.kcal,
          protein: math.max(0, target.protein - eaten.protein),
          carbs: split.carbs - eaten.carbs,
          fat: split.fat - eaten.fat,
        ),
        history: history,
        diets: diets,
        slot: KynoFuelPlanner.slotAt(t),
        // Navratri / Ekadashi: only vrat foods.
        fastingOnly: FastingService.instance.vratFoodsOnly(now: t),
        today: today,
      );
      out['food_options'] = {
        'diet_seen_in_log': [for (final d in diets) d.name],
        ...fuel.toJson(),
      };
    }

    // ── Eating, last 14 days ─────────────────────────────────────────────────
    final days = <Map<String, dynamic>>[];
    for (var i = 1; i <= 14; i++) {
      final d = today.subtract(Duration(days: i));
      final log = logs[_key(d)];
      if (log == null || log.isEmpty) continue;
      final eaten = _eaten(log);
      final late = log.allEntries
          .where((e) => e.section == MealSection.lateNight)
          .fold(0.0, (s, e) => s + e.calMid);
      final tgt = prof == null
          ? null
          : engine.effectiveTargetForDate(d, profile: prof.profileActiveOn(d) ?? prof, health: health, log: log);
      days.add({
        'date': _key(d),
        'kcal': eaten.kcal.round(),
        'protein_g': eaten.protein.round(),
        if (tgt != null) 'target_kcal': tgt.calories.round(),
        if (tgt != null) 'target_protein_g': tgt.protein.round(),
        'trained': ws.planFor(d, log: log).source == DayPlanSource.session,
        if (late > 0) 'late_night_kcal': late.round(),
      });
    }
    out['eating_last_14_days'] = days;
    out['eating_trend'] = _eatingTrend(days);
    out['frequent_foods_30d'] = [
      for (final f in KynoFuelPlanner.historyFrom(logs, today: today, days: 30).take(10))
        {'food': f.name, 'times': f.timesLogged, 'kcal': f.kcal.round(), 'protein_g': f.protein.round()},
    ];

    // ── Training ─────────────────────────────────────────────────────────────
    out['training'] = _training(ws, today);

    // ── Activity & body ──────────────────────────────────────────────────────
    if (health != null && health.hasData) {
      out['activity'] = {
        if (health.averageDailySteps7d != null) 'steps_avg_7d': health.averageDailySteps7d!.round(),
        if (health.averageDailySteps14d != null) 'steps_avg_14d': health.averageDailySteps14d!.round(),
        if (health.averageDailySteps30d != null) 'steps_avg_30d': health.averageDailySteps30d!.round(),
        if (prof != null) 'step_adjustment_kcal': engine.stepCorrectionKcal(prof, health),
      };
    } else if (prof?.averageDailySteps != null) {
      out['activity'] = {'steps_avg_entered': prof!.averageDailySteps};
    }
    // Micronutrients: 7-day averages vs ICMR-NIN targets, with coverage, so
    // Kyno can answer "am I low on iron" honestly (or say it can't tell).
    final micros = MicronutrientService.instance.briefJson(store: logs, today: today, profile: prof);
    if (micros != null) out['micronutrients'] = micros;

    // Fasting: a running or planned fast changes what to suggest and when.
    final fast = FastingService.instance.briefJson(now: t);
    if (fast != null) out['fasting'] = fast;

    // Standing notes: things the user asked Kyno to always keep in mind.
    final notes = KynoNotesService.instance.notes.value;
    if (notes.isNotEmpty) out['standing_notes'] = notes;

    // Health Connect plus weigh-ins logged in the app.
    final weights = BodyMetricsService.instance.mergedReadings(health?.weightHistory);
    if (weights.isNotEmpty) {
      out['body_weight'] = _weightTrend(weights, today);
      final trend = BodyMetricsService.instance.trend(external: health?.weightHistory ?? const [], now: today);
      if (trend.latest != null) out['body_weight']['trend_kg'] = _r1(trend.latest!.trendKg);
      final rate = trend.weeklyRateKg;
      if (rate != null) out['body_weight']['trend_kg_per_week'] = (rate * 100).round() / 100;
    }

    var brief = KynoBrief(json: out, fuelPlan: fuel);
    // Stay under the cap: drop the least useful detail first.
    for (final drop in const ['frequent_foods_30d', 'eating_last_14_days', 'micronutrients']) {
      if (brief.encode().length <= maxChars) break;
      out.remove(drop);
      brief = KynoBrief(json: out, fuelPlan: fuel);
    }
    return brief;
  }

  // ── Pieces ─────────────────────────────────────────────────────────────────

  Map<String, dynamic> _eatingTrend(List<Map<String, dynamic>> days) {
    Map<String, dynamic> window(Iterable<Map<String, dynamic>> w) {
      final list = w.toList();
      if (list.isEmpty) return {'logged_days': 0};
      double avg(String k) => list.fold(0.0, (s, d) => s + ((d[k] as num?) ?? 0)) / list.length;
      final withTarget = list.where((d) => d['target_kcal'] != null).toList();
      final onTarget = withTarget
          .where((d) => ((d['kcal'] as int) - (d['target_kcal'] as int)).abs() <= (d['target_kcal'] as int) * 0.1)
          .length;
      final proteinHit = withTarget
          .where((d) => (d['protein_g'] as int) >= (d['target_protein_g'] as int) * 0.9)
          .length;
      final late = list.fold(0.0, (s, d) => s + ((d['late_night_kcal'] as num?) ?? 0));
      final total = list.fold(0.0, (s, d) => s + (d['kcal'] as int));
      return {
        'logged_days': list.length,
        'avg_kcal': avg('kcal').round(),
        'avg_protein_g': avg('protein_g').round(),
        if (withTarget.isNotEmpty) 'days_within_10pct_of_kcal_target': onTarget,
        if (withTarget.isNotEmpty) 'days_protein_at_least_90pct': proteinHit,
        if (total > 0) 'late_night_share_pct': (late / total * 100).round(),
      };
    }

    final cutoff = DateTime.now().subtract(const Duration(days: 8));
    final recent = days.where((d) => DateTime.parse(d['date'] as String).isAfter(cutoff));
    final earlier = days.where((d) => !DateTime.parse(d['date'] as String).isAfter(cutoff));
    return {'last_7_days': window(recent), 'previous_7_days': window(earlier)};
  }

  Map<String, dynamic> _training(WorkoutService ws, DateTime today) {
    final sessions = ws.sessions.where((s) => !s.isEmpty).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    if (sessions.isEmpty) {
      return {'sessions_logged': 0, 'today': ws.planFor(today).label};
    }
    int countSince(int daysBack) =>
        sessions.where((s) => today.difference(_day(s.date)).inDays < daysBack).length;

    // Per exercise: best estimated 1RM recently vs 3-8 weeks ago.
    final perExercise = <String, List<_LiftPoint>>{};
    final names = <String, String>{};
    final muscles = <String, String>{};
    final exercises = <String, Exercise>{};
    for (final s in sessions) {
      final age = today.difference(_day(s.date)).inDays;
      if (age > 70) continue;
      for (final e in s.entries) {
        if (e.isSkipped) continue;
        final top = e.topWorkingSet;
        if (top == null || top.reps <= 0) continue;
        final e1rm = top.estimatedOneRepMax;
        if (e1rm <= 0) continue;
        perExercise.putIfAbsent(e.exercise.id, () => []).add(
              _LiftPoint(age, e1rm, '${_r1(top.externalLoadKg ?? top.weight)} kg x ${top.reps}'),
            );
        names[e.exercise.id] = e.exercise.name;
        muscles[e.exercise.id] = e.exercise.muscleGroup;
        exercises.putIfAbsent(e.exercise.id, () => e.exercise);
      }
    }
    final lifts = <Map<String, dynamic>>[];
    final ids = perExercise.keys.toList()
      ..sort((a, b) => perExercise[b]!.length.compareTo(perExercise[a]!.length));
    for (final id in ids.take(8)) {
      final pts = perExercise[id]!;
      final recent = pts.where((p) => p.age <= 21).map((p) => p.e1rm);
      final earlier = pts.where((p) => p.age > 21 && p.age <= 56).map((p) => p.e1rm);
      final r = recent.isEmpty ? null : recent.reduce(math.max);
      final b = earlier.isEmpty ? null : earlier.reduce(math.max);
      String trend = 'not enough data';
      double? pct;
      if (r != null && b != null && b > 0) {
        pct = (r - b) / b * 100;
        trend = pct > 2.5 ? 'up' : (pct < -2.5 ? 'down' : 'flat');
      }
      lifts.add({
        'exercise': names[id],
        'muscle': muscles[id],
        'sessions_10w': pts.length,
        'last_top_set': pts.first.label,
        'last_trained_days_ago': pts.first.age,
        if (r != null) 'best_e1rm_last_3w_kg': r.round(),
        if (b != null) 'best_e1rm_3_to_8w_ago_kg': b.round(),
        if (pct != null) 'change_pct': _r1(pct),
        'trend': trend,
        ..._coachFields(exercises[id]!),
      });
    }

    // Working sets per muscle: last 14 days vs the 14 before.
    Map<String, int> setsPerMuscle(int from, int to) {
      final m = <String, int>{};
      for (final s in sessions) {
        final age = today.difference(_day(s.date)).inDays;
        if (age < from || age >= to) continue;
        for (final e in s.entries) {
          if (e.isSkipped) continue;
          final n = e.sets.where((x) => x.isMainWorkingSet).length;
          if (n == 0) continue;
          m.update(e.exercise.muscleGroup, (v) => v + n, ifAbsent: () => n);
        }
      }
      return m;
    }

    return {
      'today': ws.planFor(today).label,
      'sessions_last_7d': countSince(7),
      'sessions_last_28d': countSince(28),
      'days_since_last_session': today.difference(_day(sessions.first.date)).inDays,
      'recent_sessions': [
        for (final s in sessions.take(6))
          {
            'date': _key(s.date),
            'workout': s.splitDayName,
            'working_sets': s.totalWorkingSets,
            'volume_kg': s.totalWorkingVolume.round(),
          },
      ],
      'lifts': lifts,
      'working_sets_per_muscle_last_14d': setsPerMuscle(0, 14),
      'working_sets_per_muscle_prev_14d': setsPerMuscle(14, 28),
    };
  }

  /// Kyno's coaching read on one lift, flat and short (the server caps
  /// depth and string length): loading pattern, today's plan set by set,
  /// stall and swap, and how the last session went with its likely causes.
  Map<String, dynamic> _coachFields(Exercise exercise) {
    final CoachPlan plan;
    try {
      plan = KynoProgressionEngine.instance.planFor(exercise);
    } catch (_) {
      return const {};
    }
    if (plan.sets.isEmpty) return const {};
    String cap(String s) => s.length <= 78 ? s : '${s.substring(0, 77)}.';
    return {
      'loading_pattern': plan.pattern.label,
      'kyno_plan_next_session': cap(plan.setsLine),
      'kyno_action': cap(plan.headline),
      if (plan.stalled) 'stalled': true,
      if (plan.swap != null) 'suggested_swap': cap(plan.swap!.name),
      if (plan.verdictLine.isNotEmpty) 'last_session': cap(plan.verdictLine),
      if (plan.verdict == SessionVerdict.belowPar)
        'likely_causes': [for (final c in plan.causes.take(4)) cap(c.finding)],
    };
  }

  Map<String, dynamic> _weightTrend(List<WeightReading> readings, DateTime today) {
    final sorted = [...readings]..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    double? avgAround(int daysBack) {
      final pts = sorted.where((w) {
        final age = today.difference(_day(w.recordedAt)).inDays;
        return (age - daysBack).abs() <= 3;
      }).map((w) => w.kg).toList();
      if (pts.isEmpty) return null;
      return pts.reduce((a, b) => a + b) / pts.length;
    }

    final now = avgAround(0) ?? sorted.first.kg;
    final w2 = avgAround(14);
    final w4 = avgAround(28);
    return {
      'latest_kg': _r1(sorted.first.kg),
      'latest_days_ago': today.difference(_day(sorted.first.recordedAt)).inDays,
      if (w2 != null) 'change_vs_2_weeks_kg': _r1(now - w2),
      if (w4 != null) 'change_vs_4_weeks_kg': _r1(now - w4),
      'readings_last_30d': sorted.where((w) => today.difference(_day(w.recordedAt)).inDays <= 30).length,
    };
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Totals the way the app shows them: each entry rounded, then summed.
  _Eaten _eaten(DayLog log) {
    var k = 0.0, p = 0.0, c = 0.0, f = 0.0, fi = 0.0;
    for (final e in log.allEntries) {
      final r = e.result;
      k += e.calMid.roundToDouble();
      p += e.protMid.roundToDouble();
      if (r.carbohydrates != null) c += (r.carbohydrates!.min + r.carbohydrates!.max) / 2;
      if (r.fat != null) f += (r.fat!.min + r.fat!.max) / 2;
      if (r.fiber != null) fi += (r.fiber!.min + r.fiber!.max) / 2;
    }
    return _Eaten(k, p, c, f, fi);
  }

  static String _name(MealEntry e) {
    final n = e.finalSavedInput.isNotEmpty ? e.finalSavedInput : e.rawInput;
    return n.length > 60 ? '${n.substring(0, 59)}…' : n;
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
  static String _key(DateTime d) => dateKey(d);
  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  static double _r1(double v) => (v * 10).round() / 10;
}

class _Eaten {
  const _Eaten(this.kcal, this.protein, this.carbs, this.fat, this.fiber);
  final double kcal, protein, carbs, fat, fiber;
}

class _LiftPoint {
  const _LiftPoint(this.age, this.e1rm, this.label);
  final int age;
  final double e1rm;
  final String label;
}
