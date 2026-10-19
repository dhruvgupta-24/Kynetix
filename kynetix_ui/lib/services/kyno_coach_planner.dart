import 'dart:math' as math;

import '../data/exercise_classification.dart';
import '../models/exercise_definition.dart';
import '../models/workout_session.dart';
import '../models/workout_split.dart';

// ─── KynoCoachPlanner ─────────────────────────────────────────────────────────
//
// Kyno as a strength coach, for one exercise:
//
//   1. Reads how the person actually loads it (straight sets, pyramid,
//      reverse pyramid, top set + back-off, ramping, drop sets) from their
//      last sessions.
//   2. Writes today's plan set by set in that same pattern: double
//      progression on the right set (all sets for straight work, the top set
//      for pyramids), plate-sized jumps per equipment, belt load for
//      bodyweight moves, a 10% deload after a real decline.
//   3. Spots a stall (no strength gain across 4+ exposures over 3+ weeks)
//      and names a specific swap for the same muscle.
//   4. Judges the latest session against the ones before it; when it fell
//      short, looks at that day's and the day before's food, sleep and
//      spacing for the likely cause, and says what to change.
//
// Pure: history, diet and sleep come in as values, so it is testable without
// the app's singletons. [KynoProgressionEngine] adapts it for the UI.

/// How a person loads an exercise across its working sets.
enum LoadingPattern {
  straight('Straight sets'),
  straightFading('Straight sets, reps fading'),
  pyramid('Pyramid'),
  reversePyramid('Reverse pyramid'),
  topSetBackOff('Top set + back-off'),
  fullPyramid('Up and down pyramid'),
  single('Single working set'),
  mixed('Mixed loading'),
  bodyweight('Bodyweight reps');

  const LoadingPattern(this.label);
  final String label;
}

/// What Kyno wants done with the load today.
enum CoachAction { increase, addReps, hold, deload, rebuild, calibrate }

/// One set of today's plan.
class PlannedSet {
  const PlannedSet({required this.load, required this.reps, this.bodyweight = false});

  /// kg on the bar or machine; for a bodyweight move, the added belt load.
  final double load;
  final int reps;
  final bool bodyweight;

  /// "62.5 × 8", "BW+10 × 8", "BW × 12".
  String get label {
    final l = _kg(load);
    if (bodyweight) return load > 0 ? 'BW+$l × $reps' : 'BW × $reps';
    return '$l × $reps';
  }
}

/// A named alternative for a stalled lift.
class SwapSuggestion {
  const SwapSuggestion({required this.exerciseId, required this.name, required this.reason});
  final String exerciseId;
  final String name;
  final String reason;
}

/// How the latest session went against the person's own recent level.
enum SessionVerdict { strong, onTrack, belowPar, unknown }

/// A likely reason a session fell short, with what to do about it.
class PerformanceCause {
  const PerformanceCause(this.finding, this.fix);
  final String finding;
  final String fix;
}

/// Food on one day, against its target.
class DietDay {
  const DietDay({
    required this.calories,
    required this.protein,
    required this.calorieTarget,
    required this.proteinTarget,
    required this.logged,
  });
  final double calories, protein, calorieTarget, proteinTarget;

  /// False when nothing was logged: the numbers are unknown, not zero.
  final bool logged;
}

/// Kyno's full coaching read on one exercise.
class CoachPlan {
  const CoachPlan({
    required this.pattern,
    required this.patternConfidence,
    required this.action,
    required this.sets,
    required this.headline,
    required this.summary,
    required this.reasons,
    required this.nextMilestone,
    required this.stalled,
    required this.verdict,
    required this.verdictLine,
    required this.causes,
    required this.e1rmTrend,
    this.swap,
    this.dropSetFinisher = false,
  });

  final LoadingPattern pattern;
  final double patternConfidence;
  final CoachAction action;

  /// Today's working sets, in order.
  final List<PlannedSet> sets;

  /// "Increase to 62.5 kg", "Hold 60 kg, add a rep", "Deload to 54 kg".
  final String headline;
  final String summary;
  final List<String> reasons;
  final String nextMilestone;

  /// No strength gain across recent exposures.
  final bool stalled;
  final SwapSuggestion? swap;

  /// The person usually ends with a drop set.
  final bool dropSetFinisher;

  final SessionVerdict verdict;
  final String verdictLine;
  final List<PerformanceCause> causes;

  /// Best estimated 1RM per session, oldest first.
  final List<double> e1rmTrend;

  /// "62.5×8, 62.5×8, 62.5×7" for compact lists and the AI brief.
  String get setsLine => sets.map((s) => s.label.replaceAll(' × ', '×')).join(', ');

  PlannedSet? setAt(int i) => i >= 0 && i < sets.length ? sets[i] : null;
}

class KynoCoachPlanner {
  const KynoCoachPlanner._();

  /// Builds the plan for [exercise] from [history] (newest first, one entry
  /// per session). [dietFor] returns the food for a date, [sleepHours] is last
  /// night's sleep (only used when the latest session is [now]'s),
  /// [library] offers swap candidates.
  static CoachPlan plan({
    required Exercise exercise,
    required List<({DateTime date, ExerciseEntry entry})> history,
    required DateTime now,
    DietDay? Function(DateTime day)? dietFor,
    double? sleepHours,
    List<ExerciseDefinition> library = const [],
    Set<String> doneBefore = const {},
  }) {
    final cls = ExerciseClassifier.forExercise(exercise);
    final mode = exercise.effectiveExecutionMode;
    final isBw = mode == ExerciseExecutionMode.bodyweightReps || mode == ExerciseExecutionMode.weightedBodyweight;
    final repMin = exercise.targetRepMin;
    final repMax = math.max(exercise.targetRepMax, repMin);
    final step = _step(cls, isBw);

    final sessions = [
      for (final h in history)
        if (_working(h.entry, isBw).isNotEmpty) (date: h.date, entry: h.entry, sets: _working(h.entry, isBw)),
    ];
    final trend = [for (final s in sessions.reversed) _bestE1rm(s.sets)];

    if (sessions.isEmpty) {
      return CoachPlan(
        pattern: isBw ? LoadingPattern.bodyweight : LoadingPattern.straight,
        patternConfidence: 0,
        action: CoachAction.calibrate,
        sets: const [],
        headline: 'Calibrate baseline',
        summary: 'First time on this one. Find a weight you can move for '
            '${exercise.targetSets} clean sets of $repMin to $repMax with 1 or 2 reps in reserve.',
        reasons: ['New exercise in active rotation.', 'Target range is $repMin to $repMax reps.'],
        nextMilestone: 'Log ${exercise.targetSets} working sets so Kyno can set your first jump.',
        stalled: false,
        verdict: SessionVerdict.unknown,
        verdictLine: '',
        causes: const [],
        e1rmTrend: const [],
      );
    }

    // ── 1. Pattern: the most common shape across the last three sessions.
    final shapes = [for (final s in sessions.take(3)) _shape(s.sets, isBw)];
    final pattern = _mode(shapes);
    final confidence = shapes.where((p) => p == pattern).length / shapes.length;
    final dropFinisher = sessions.take(3).any((s) => s.entry.logicalSets.any((g) => g.isWorkingSet && g.subSets.isNotEmpty));

    final last = sessions.first;
    final lastSets = last.sets;
    final lastLine = lastSets.map((s) => s.shortLabel).join(', ');

    // ── 2. Trend, deload, stall.
    final declining = trend.length >= 3 &&
        trend[trend.length - 1] < trend[trend.length - 2] &&
        trend[trend.length - 2] < trend[trend.length - 3] &&
        trend[trend.length - 1] < trend[trend.length - 3] * 0.97;
    final stalled = _stalled(sessions.map((s) => (date: s.date, e1rm: _bestE1rm(s.sets))).toList());
    final safety = lastSets.any((s) => s.rpe != null && s.rpe! >= 10 && s.reps <= 4);

    final reasons = <String>['Last time: $lastLine.'];
    if (confidence >= 0.66 && sessions.length >= 2) {
      reasons.add('You train this as ${pattern.label.toLowerCase()} (${shapes.where((p) => p == pattern).length} of last ${shapes.length} sessions).');
    }
    if (dropFinisher) reasons.add('You usually finish with a drop set.');

    late CoachAction action;
    late List<PlannedSet> sets;
    late String headline, summary, milestone;

    if (declining) {
      action = CoachAction.deload;
      sets = [
        for (final s in lastSets)
          PlannedSet(load: _round(_load(s) * 0.9, step), reps: s.reps, bodyweight: isBw),
      ];
      final top = sets.map((s) => s.load).reduce(math.max);
      headline = isBw && top <= 0 ? 'Deload: fewer reps' : 'Deload to ${_kg(top)} kg';
      summary = 'Estimated strength dropped three sessions in a row. Take about 10% off, '
          'keep the same reps and make every one crisp. Next session goes back up.';
      reasons.add('Estimated 1RM fell across the last 3 sessions.');
      milestone = 'One easy session, then return to ${_kg(lastSets.map(_load).reduce(math.max))} kg.';
    } else if (safety) {
      action = CoachAction.hold;
      sets = [for (final s in lastSets) PlannedSet(load: _load(s), reps: s.reps, bodyweight: isBw)];
      headline = 'Hold ${_loadText(sets.first.load, isBw)}';
      summary = 'Last session hit failure on a low-rep set. Same load, stop each set with a rep in reserve.';
      reasons.add('An RPE 10 set at 4 reps or fewer.');
      milestone = 'All sets at RPE 8 to 9 before adding load.';
    } else {
      final r = _progress(pattern, lastSets, repMin, repMax, step, isBw);
      action = r.action;
      sets = r.sets;
      headline = r.headline;
      summary = r.summary;
      milestone = r.milestone;
      reasons.addAll(r.reasons);
    }

    // ── 3. Swap when stalled.
    SwapSuggestion? swap;
    if (stalled && !declining) {
      reasons.add('No strength gain across your last ${math.min(sessions.length, 6)} sessions.');
      swap = _swapFor(exercise, library, doneBefore);
      summary = '$summary${swap != null ? ' This lift has stalled: try ${swap.name} for the next 4 to 6 weeks.' : ' This lift has stalled: change the rep range for a few weeks (for example $repMax to ${repMax + 4}).'}';
    }

    // ── 4. How the latest session went, and why.
    final v = _verdict(sessions, now, dietFor, sleepHours, isBw);

    return CoachPlan(
      pattern: pattern,
      patternConfidence: confidence,
      action: action,
      sets: sets,
      headline: headline,
      summary: summary,
      reasons: reasons,
      nextMilestone: milestone,
      stalled: stalled,
      swap: swap,
      dropSetFinisher: dropFinisher,
      verdict: v.verdict,
      verdictLine: v.line,
      causes: v.causes,
      e1rmTrend: trend,
    );
  }

  // ── Progression per pattern ──────────────────────────────────────────────────

  static ({
    CoachAction action,
    List<PlannedSet> sets,
    String headline,
    String summary,
    String milestone,
    List<String> reasons,
  }) _progress(LoadingPattern pattern, List<SetEntry> last, int repMin, int repMax, double step, bool isBw) {
    final loads = last.map(_load).toList();
    final reps = last.map((s) => s.reps).toList();

    // Bodyweight with no belt: progress reps, then add a belt.
    if (isBw && loads.every((l) => l <= 0)) {
      final bwMax = math.max(repMax, 12);
      if (reps.every((r) => r >= bwMax)) {
        return (
          action: CoachAction.increase,
          sets: [for (final _ in reps) PlannedSet(load: step, reps: repMin, bodyweight: true)],
          headline: 'Add ${_kg(step)} kg on a belt',
          summary: 'Every set reached $bwMax reps. Time to load it: belt ${_kg(step)} kg and start back at $repMin reps.',
          milestone: '${reps.length} sets of $bwMax with the belt, then add another ${_kg(step)} kg.',
          reasons: ['All sets at $bwMax+ reps.'],
        );
      }
      return (
        action: CoachAction.addReps,
        sets: [for (final r in reps) PlannedSet(load: 0, reps: math.min(r + 1, bwMax), bodyweight: true)],
        headline: 'Bodyweight, add a rep a set',
        summary: 'Beat last time by one rep on each set. At $bwMax reps across the board, add a belt.',
        milestone: '${reps.length} sets of $bwMax, then belt ${_kg(step)} kg.',
        reasons: const [],
      );
    }

    switch (pattern) {
      case LoadingPattern.pyramid:
      case LoadingPattern.fullPyramid:
        // The heaviest set drives it; the ramp keeps its gaps.
        final top = loads.indexOf(loads.reduce(math.max));
        final topReps = reps[top];
        final topCeiling = math.max(repMin, math.min(repMax, repMin + 2));
        if (topReps >= topCeiling) {
          return (
            action: CoachAction.increase,
            sets: [
              for (var i = 0; i < loads.length; i++)
                PlannedSet(load: _round(loads[i] + step, step), reps: reps[i], bodyweight: isBw),
            ],
            headline: 'Shift the pyramid up ${_kg(step)} kg',
            summary: 'Your top set made $topReps reps at ${_loadText(loads[top], isBw)}. '
                'Move every step of the pyramid up ${_kg(step)} kg and keep the same reps.',
            milestone: '$topCeiling reps on the top set at ${_loadText(loads[top] + step, isBw)}.',
            reasons: ['Top set: ${_loadText(loads[top], isBw)} × $topReps.'],
          );
        }
        return (
          action: CoachAction.addReps,
          sets: [
            for (var i = 0; i < loads.length; i++)
              PlannedSet(load: loads[i], reps: i == top ? topReps + 1 : reps[i], bodyweight: isBw),
          ],
          headline: 'Same pyramid, one more rep on top',
          summary: 'Keep the ramp. Push the top set to ${topReps + 1} reps; at $topCeiling the whole pyramid moves up.',
          milestone: '$topCeiling reps on the top set at ${_loadText(loads[top], isBw)}.',
          reasons: ['Top set: ${_loadText(loads[top], isBw)} × $topReps.'],
        );

      case LoadingPattern.reversePyramid:
      case LoadingPattern.topSetBackOff:
        // Top set progresses by double progression; back-offs keep their
        // share of the top set and chase one more rep.
        final top = loads.first;
        final topReps = reps.first;
        final topCeiling = math.max(repMin, math.min(repMax, repMin + 2));
        final ratios = [for (final l in loads) top > 0 ? l / top : 1.0];
        final up = topReps >= topCeiling;
        final newTop = up ? _round(top + step, step) : top;
        final sets = <PlannedSet>[
          for (var i = 0; i < loads.length; i++)
            PlannedSet(
              load: i == 0 ? newTop : _round(newTop * ratios[i], step),
              reps: i == 0 ? (up ? repMin : topReps + 1) : (up ? reps[i] : reps[i] + 1),
              bodyweight: isBw,
            ),
        ];
        final style = pattern == LoadingPattern.topSetBackOff ? 'back-off sets' : 'lighter sets';
        return (
          action: up ? CoachAction.increase : CoachAction.addReps,
          sets: sets,
          headline: up ? 'Top set up to ${_loadText(newTop, isBw)}' : 'Top set: ${_loadText(top, isBw)} for ${topReps + 1}',
          summary: up
              ? 'Top set hit $topReps reps. Add ${_kg(step)} kg to it and aim for $repMin; the $style follow at the same percentages.'
              : 'Keep the top set at ${_loadText(top, isBw)} and fight for ${topReps + 1}. One more rep on each of the $style too.',
          milestone: '$topCeiling reps on the top set, then add ${_kg(step)} kg.',
          reasons: ['Top set: ${_loadText(top, isBw)} × $topReps.'],
        );

      case LoadingPattern.straight:
      case LoadingPattern.straightFading:
      case LoadingPattern.single:
      case LoadingPattern.mixed:
      case LoadingPattern.bodyweight:
        final load = loads.reduce(math.max);
        final atLoad = [for (var i = 0; i < loads.length; i++) if (loads[i] >= load * 0.98) reps[i]];
        final allTop = atLoad.length >= math.min(loads.length, 3) && atLoad.every((r) => r >= repMax);
        if (allTop) {
          final next = _round(load + step, step);
          return (
            action: CoachAction.increase,
            sets: [for (final _ in loads) PlannedSet(load: next, reps: repMin, bodyweight: isBw)],
            headline: 'Increase to ${_loadText(next, isBw)}',
            summary: 'Every set reached $repMax at ${_loadText(load, isBw)}. Go up ${_kg(step)} kg and aim for $repMin reps on each set.',
            milestone: '${loads.length} × $repMax at ${_loadText(next, isBw)}, then add ${_kg(step)} kg again.',
            reasons: ['All sets at the top of $repMin to $repMax.'],
          );
        }
        final low = atLoad.where((r) => r < repMin).length;
        if (low >= 2 && atLoad.every((r) => r < repMin + 1)) {
          final back = _round(load * 0.95, step);
          return (
            action: CoachAction.rebuild,
            sets: [for (final _ in loads) PlannedSet(load: back, reps: repMin + 1, bodyweight: isBw)],
            headline: 'Step back to ${_loadText(back, isBw)}',
            summary: 'Most sets fell below $repMin at ${_loadText(load, isBw)}: the jump came too early. '
                'Drop about 5%, own $repMin to $repMax again, then return.',
            milestone: '${loads.length} × $repMax at ${_loadText(back, isBw)}, then ${_loadText(load, isBw)} again.',
            reasons: ['$low sets under $repMin reps.'],
          );
        }
        // Add a rep to every set below the ceiling, the weakest first.
        return (
          action: CoachAction.addReps,
          sets: [for (final r in reps) PlannedSet(load: load, reps: math.min(r + 1, repMax), bodyweight: isBw)],
          headline: 'Hold ${_loadText(load, isBw)}, add a rep',
          summary: 'Same load as last time. Beat each set by one rep; when all ${loads.length} reach $repMax, the weight goes up.',
          milestone: 'All ${loads.length} sets at $repMax reps at ${_loadText(load, isBw)}, then add ${_kg(step)} kg.',
          reasons: [
            if (pattern == LoadingPattern.straightFading) 'Reps fade across sets: rest a little longer (2 to 3 min) before the later ones.',
          ],
        );
    }
  }

  // ── Pattern ──────────────────────────────────────────────────────────────────

  static LoadingPattern _shape(List<SetEntry> sets, bool isBw) {
    final loads = sets.map(_load).toList();
    final reps = sets.map((s) => s.reps).toList();
    if (isBw && loads.every((l) => l <= 0)) return LoadingPattern.bodyweight;
    if (sets.length == 1) return LoadingPattern.single;
    final top = loads.reduce(math.max);
    final tol = math.max(0.5, top * 0.025);
    bool same(double a, double b) => (a - b).abs() <= tol;

    if (loads.every((l) => same(l, loads.first))) {
      return reps.first - reps.last >= 2 ? LoadingPattern.straightFading : LoadingPattern.straight;
    }
    final up = [for (var i = 1; i < loads.length; i++) loads[i] - loads[i - 1]];
    final rising = up.every((d) => d >= -tol) && up.any((d) => d > tol);
    final falling = up.every((d) => d <= tol) && up.any((d) => d < -tol);
    if (rising) return LoadingPattern.pyramid;
    if (falling) {
      final rest = loads.sublist(1);
      final flatRest = rest.every((l) => same(l, rest.first));
      return flatRest && loads.first > rest.first + tol ? LoadingPattern.topSetBackOff : LoadingPattern.reversePyramid;
    }
    final peak = loads.indexOf(top);
    if (peak > 0 && peak < loads.length - 1) {
      final before = loads.sublist(0, peak + 1);
      final after = loads.sublist(peak);
      final upThen = [for (var i = 1; i < before.length; i++) before[i] >= before[i - 1] - tol].every((b) => b);
      final downAfter = [for (var i = 1; i < after.length; i++) after[i] <= after[i - 1] + tol].every((b) => b);
      if (upThen && downAfter) return LoadingPattern.fullPyramid;
    }
    return LoadingPattern.mixed;
  }

  static LoadingPattern _mode(List<LoadingPattern> xs) {
    final counts = <LoadingPattern, int>{};
    for (final x in xs) {
      counts[x] = (counts[x] ?? 0) + 1;
    }
    // Ties go to the most recent session's shape.
    var best = xs.first;
    for (final e in counts.entries) {
      if (e.value > counts[best]!) best = e.key;
    }
    return best;
  }

  // ── Stall ────────────────────────────────────────────────────────────────────

  /// No gain above 1% across the last 4+ exposures spanning 3+ weeks.
  static bool _stalled(List<({DateTime date, double e1rm})> s) {
    if (s.length < 5) return false;
    final recent = s.take(4).toList();
    final span = recent.first.date.difference(recent.last.date).inDays;
    if (span < 21) return false;
    final before = s.skip(4).map((x) => x.e1rm).fold<double>(0, math.max);
    final now = recent.map((x) => x.e1rm).fold<double>(0, math.max);
    return before > 0 && now <= before * 1.01;
  }

  static SwapSuggestion? _swapFor(Exercise ex, List<ExerciseDefinition> library, Set<String> doneBefore) {
    if (library.isEmpty) return null;
    final lc = ex.name.toLowerCase();
    ExerciseDefinition? base;
    for (final d in library) {
      if (d.id == ex.id || d.displayName.toLowerCase() == lc || d.canonicalName.toLowerCase() == lc) {
        base = d;
        break;
      }
    }
    final muscle = (base?.targetMuscle ?? ex.muscleGroup).toLowerCase();
    final group = base?.equipmentGroup.toLowerCase();
    final compound = ExerciseClassifier.forExercise(ex).isCompound;
    final words = lc.split(RegExp(r'[^a-z]+')).where((w) => w.length > 3).toSet();

    int score(ExerciseDefinition d) {
      var s = 0;
      if (doneBefore.contains(d.id)) s += 6;
      if (group != null && d.equipmentGroup.toLowerCase() != group) s += 3;
      final dc = d.classification.isCompound;
      if (dc == compound) s += 4;
      // Same movement in another form ("incline dumbbell press" for "bench press").
      final dw = d.displayName.toLowerCase().split(RegExp(r'[^a-z]+')).toSet();
      s += 2 * words.intersection(dw).length;
      // Plain, common names over exotic variants.
      s -= d.displayName.length ~/ 12;
      return s;
    }

    final pool = [
      for (final d in library)
        if (d.id != ex.id &&
            d.displayName.toLowerCase() != lc &&
            d.targetMuscle.toLowerCase() == muscle &&
            !RegExp(r'\b(stretch|mobility|band|assisted)\b').hasMatch(d.displayName.toLowerCase()))
          d,
    ];
    if (pool.isEmpty) return null;
    pool.sort((a, b) => score(b) - score(a));
    final pick = pool.first;
    return SwapSuggestion(
      exerciseId: pick.id,
      name: pick.displayName,
      reason: doneBefore.contains(pick.id)
          ? 'Same muscle, a lift you already know: a new angle restarts progress.'
          : 'Same muscle (${pick.targetMuscle}), a different angle and equipment to restart progress.',
    );
  }

  // ── Session verdict and causes ────────────────────────────────────────────────

  static ({SessionVerdict verdict, String line, List<PerformanceCause> causes}) _verdict(
    List<({DateTime date, ExerciseEntry entry, List<SetEntry> sets})> sessions,
    DateTime now,
    DietDay? Function(DateTime day)? dietFor,
    double? sleepHours,
    bool isBw,
  ) {
    if (sessions.length < 3) return (verdict: SessionVerdict.unknown, line: '', causes: const []);
    final latest = sessions.first;
    final latestBest = _bestE1rm(latest.sets);
    final prior = [for (final s in sessions.skip(1).take(3)) _bestE1rm(s.sets)]..sort();
    final ref = prior[prior.length ~/ 2];
    if (ref <= 0) return (verdict: SessionVerdict.unknown, line: '', causes: const []);
    final change = (latestBest - ref) / ref;
    final when = _sameDay(latest.date, now) ? 'Today' : 'Last session';

    if (change >= 0.03) {
      return (
        verdict: SessionVerdict.strong,
        line: '$when was strong: estimated 1RM up ${(change * 100).round()}% on your recent level.',
        causes: const [],
      );
    }
    if (change > -0.05) {
      return (verdict: SessionVerdict.onTrack, line: '$when was in line with your recent sessions.', causes: const []);
    }

    final causes = <PerformanceCause>[];
    final day = DateTime(latest.date.year, latest.date.month, latest.date.day);
    final before = day.subtract(const Duration(days: 1));
    final dToday = dietFor?.call(day);
    final dBefore = dietFor?.call(before);

    for (final (label, d) in [('the day before', dBefore), ('that day', dToday)]) {
      if (d == null || !d.logged) continue;
      if (d.calorieTarget > 0 && d.calories < d.calorieTarget * 0.8) {
        causes.add(PerformanceCause(
          'You ate ${d.calories.round()} of ${d.calorieTarget.round()} kcal $label.',
          'Under-fuelled lifts feel heavy. Eat close to target the day before training, with carbs (rice, roti, poha) 2 to 3 hours before.',
        ));
      }
      if (d.proteinTarget > 0 && d.protein < d.proteinTarget * 0.75) {
        causes.add(PerformanceCause(
          'Protein was ${d.protein.round()} of ${d.proteinTarget.round()} g $label.',
          'Recovery runs on protein: spread ${d.proteinTarget.round()} g over 3 to 4 meals (dal, paneer, eggs, curd, whey).',
        ));
      }
    }
    final unlogged = [dBefore, dToday].where((d) => d != null && !d.logged).length;
    if (unlogged == 2 && causes.isEmpty) {
      causes.add(const PerformanceCause(
        'No meals were logged that day or the day before.',
        'Log food around training days so Kyno can tell whether fuel is the problem.',
      ));
    }
    if (_sameDay(latest.date, now) && sleepHours != null && sleepHours < 6.5) {
      causes.add(PerformanceCause(
        'You slept ${sleepHours.toStringAsFixed(1)} h last night.',
        'Under 7 h costs strength. Aim for 7 to 9 h before heavy days; on short nights keep the load and cut a set.',
      ));
    }
    final prev = sessions[1].date;
    final gapH = latest.date.difference(prev).inHours;
    if (gapH < 48) {
      causes.add(const PerformanceCause(
        'Less than 48 hours since you last trained this lift.',
        'Give this muscle 48 to 72 hours between hard sessions.',
      ));
    } else if (gapH > 14 * 24) {
      causes.add(PerformanceCause(
        '${gapH ~/ 24} days since you last did this lift.',
        'A dip after a break is normal: one or two sessions and it comes back.',
      ));
    }
    final lastLoad = latest.sets.map(_load).fold<double>(0, math.max);
    final prevLoad = sessions[1].sets.map(_load).fold<double>(0, math.max);
    if (prevLoad > 0 && lastLoad > prevLoad * 1.075) {
      causes.add(PerformanceCause(
        'The load jumped ${((lastLoad / prevLoad - 1) * 100).round()}% from last time.',
        'Smaller steps (one plate size) keep the reps and still progress.',
      ));
    }
    if (causes.isEmpty) {
      causes.add(const PerformanceCause(
        'Food, sleep and spacing look fine.',
        'One off day is noise. If the next session is also down, take a deload week.',
      ));
    }
    return (
      verdict: SessionVerdict.belowPar,
      line: '$when was below your level: estimated 1RM down ${(-change * 100).round()}%.',
      causes: causes,
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  static List<SetEntry> _working(ExerciseEntry e, bool isBw) => [
        for (final g in e.logicalSets)
          if (g.isWorkingSet && g.mainSet.reps > 0 && g.mainSet.durationSeconds == null) g.mainSet,
      ];

  /// What progresses: the belt load for bodyweight moves, else the weight.
  static double _load(SetEntry s) => s.externalLoadKg ?? s.weight;

  static double _bestE1rm(List<SetEntry> sets) =>
      sets.map((s) => _load(s) * (1 + s.reps / 30)).fold<double>(0, math.max);

  /// One plate step for the equipment.
  static double _step(ExerciseClassification c, bool isBw) {
    if (isBw) return 2.5;
    return switch (c.equipment) {
      EquipmentKind.dumbbell => 2.5,
      EquipmentKind.kettlebell => 4.0,
      EquipmentKind.cable || EquipmentKind.machine || EquipmentKind.cableOrMachine => c.isCompound ? 5.0 : 2.5,
      _ => 2.5,
    };
  }

  static double _round(double v, double step) => v <= 0 ? 0 : (v / step).round() * step;

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  static String _loadText(double load, bool isBw) =>
      isBw ? (load > 0 ? 'BW + ${_kg(load)} kg' : 'bodyweight') : '${_kg(load)} kg';
}

String _kg(double v) => v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
