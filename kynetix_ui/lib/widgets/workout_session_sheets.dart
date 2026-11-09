import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_theme.dart';
import '../models/workout_split.dart';
import '../services/rest_timer_prefs.dart';
import '../services/session_score.dart';
import '../services/warmup_calculator.dart';

// ─── Rest picker ─────────────────────────────────────────────────────────────

/// Pick a rest length (30 s to 5 min) for [exerciseName]. Returns the seconds,
/// or null when dismissed. The choice is remembered per exercise by the
/// caller.
Future<int?> showRestPickerSheet(
  BuildContext context, {
  required String exerciseName,
  required int currentSeconds,
}) {
  return showKSheet<int>(
    context: context,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KSheetHeader('Rest timer', subtitle: 'Kynetix remembers this for $exerciseName.'),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final s in RestTimerPrefs.presets)
                  _RestChip(
                    seconds: s,
                    selected: s == RestTimerPrefs.normalize(currentSeconds),
                    onTap: () {
                      KHaptics.select();
                      Navigator.of(ctx).pop(s);
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _RestChip extends StatelessWidget {
  final int seconds;
  final bool selected;
  final VoidCallback onTap;
  const _RestChip({required this.seconds, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Rest ${restLabel(seconds)}',
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: KRadius.pill,
          child: Container(
            constraints: const BoxConstraints(minWidth: 72, minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: selected ? null : Colors.transparent,
              gradient: selected ? KShade.convex(KColor.ink) : null,
              boxShadow: selected ? KShadow.lifted : null,
              borderRadius: KRadius.pill,
              border: Border.all(color: selected ? KColor.ink : KColor.fg.withValues(alpha: 0.16)),
            ),
            child: Center(
              widthFactor: 1.0,
              child: Text(
                restLabel(seconds),
                style: KText.numSmall.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: selected ? KColor.onInk : KColor.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Warm-up builder ─────────────────────────────────────────────────────────

/// Today's working weight and the ramp built for it.
typedef WarmUpPlan = ({double workingWeight, List<WarmUpStep> steps});

/// Asks for today's working weight and previews the ramp. Returns the plan,
/// or null when dismissed.
Future<WarmUpPlan?> showWarmUpSheet(
  BuildContext context, {
  required Exercise exercise,
  double? suggestedWorkingWeight,
}) {
  return showKSheet<WarmUpPlan>(
    context: context,
    builder: (_) => _WarmUpSheet(exercise: exercise, suggested: suggestedWorkingWeight),
  );
}

class _WarmUpSheet extends StatefulWidget {
  final Exercise exercise;
  final double? suggested;
  const _WarmUpSheet({required this.exercise, this.suggested});

  @override
  State<_WarmUpSheet> createState() => _WarmUpSheetState();
}

class _WarmUpSheetState extends State<_WarmUpSheet> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.suggested != null ? amount(widget.suggested!) : '',
  );

  double? get _working => double.tryParse(_ctrl.text.replaceAll(',', '.').trim());

  List<WarmUpStep> get _steps {
    final w = _working;
    if (w == null || w <= 0) return const [];
    return WarmUpCalculator.generate(workingWeight: w, type: widget.exercise.type);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
    final w = _working;
    final isBar = widget.exercise.type == ExerciseType.barbellCompound;
    final String? hint = w == null || w <= 0
        ? null
        : steps.isEmpty
            ? (isBar
                ? 'That\'s the empty bar or lighter, so there\'s nothing to ramp.'
                : 'Too light to ramp. Go straight to your working sets.')
            : null;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KSheetHeader('Add warm-up sets', subtitle: widget.exercise.name),
            const SizedBox(height: 14),
            Text('Working weight today', style: KText.caption.copyWith(color: KColor.textSecondary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: _ctrl,
              autofocus: widget.suggested == null,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              style: KText.numMedium.copyWith(fontSize: 28, fontWeight: FontWeight.w800),
              cursorColor: KColor.textPrimary,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                suffixText: 'kg',
                suffixStyle: KText.bodyMedium.copyWith(color: KColor.textSecondary),
                hintText: '0',
                hintStyle: KText.numMedium.copyWith(fontSize: 28, color: KColor.textDisabled),
                isDense: true,
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: KColor.fg.withValues(alpha: 0.18))),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: KColor.ink, width: 2)),
              ),
            ),
            const SizedBox(height: 14),
            if (hint != null)
              Text(hint, style: KText.body.copyWith(color: KColor.textSecondary))
            else if (steps.isNotEmpty) ...[
              for (var i = 0; i < steps.length; i++)
                Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: KColor.fg.withValues(alpha: 0.08))),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 34,
                        child: Text('W${i + 1}', style: KText.numSmall.copyWith(color: KColor.textMuted, fontWeight: FontWeight.w700)),
                      ),
                      Expanded(
                        child: Text(
                          '${amount(steps[i].weight)} kg × ${steps[i].reps}',
                          style: KText.numSmall.copyWith(fontSize: 16, fontWeight: FontWeight.w700, color: KColor.textPrimary),
                        ),
                      ),
                      Text(
                        isBar && steps[i].weight == WarmUpCalculator.defaultBarKg
                            ? 'Empty bar'
                            : '${((steps[i].weight / w!) * 100).round()}%',
                        style: KText.caption.copyWith(color: KColor.textSecondary),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                isBar
                    ? 'Rounded to plates you can load. Warm-ups don\'t count toward volume or progress.'
                    : 'Rounded to the nearest dumbbell or stack step. Warm-ups don\'t count toward volume or progress.',
                style: KText.caption.copyWith(color: KColor.textMuted),
              ),
            ],
            const SizedBox(height: 16),
            KButton(
              label: steps.isEmpty ? 'Add warm-up sets' : 'Add ${steps.length} warm-up ${steps.length == 1 ? 'set' : 'sets'}',
              onTap: steps.isEmpty
                  ? null
                  : () {
                      KHaptics.commit();
                      Navigator.of(context).pop((workingWeight: w!, steps: steps));
                    },
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Score breakdown ─────────────────────────────────────────────────────────

/// What the workout score is made of: four parts, each with its points, its
/// maximum and one plain line on what it measures.
Future<void> showSessionScoreSheet(BuildContext context, SessionScoreBreakdown score) {
  return showKSheet<void>(
    context: context,
    builder: (_) => _ScoreSheet(score: score),
  );
}

class _ScoreSheet extends StatelessWidget {
  final SessionScoreBreakdown score;
  const _ScoreSheet({required this.score});

  String get _effortLine => switch (score.effortBasis) {
        EffortBasis.volume => 'Kilos moved against last time. Match it for full points.',
        EffortBasis.reps => 'Reps against last time. Match them for full points.',
        EffortBasis.plan => 'Nothing to compare with yet, so this follows the plan.',
      };

  String get _recordsLine => score.recordExercises == 0
      ? '5 for each exercise with a new best, up to 3.'
      : '${score.recordExercises} ${score.recordExercises == 1 ? 'exercise' : 'exercises'} with a new best, 5 each, up to 3.';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          key: const Key('session_score_sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KSheetHeader('Score ${score.total}', subtitle: 'Out of 100. Here is what went into it.'),
            const SizedBox(height: 8),
            _ScorePart(
              label: 'Plan done',
              line: 'Sets done and reps reached on every exercise you did.',
              points: score.plan,
              max: SessionScoreBreakdown.planMax,
            ),
            _ScorePart(label: 'Effort', line: _effortLine, points: score.effort, max: SessionScoreBreakdown.effortMax),
            _ScorePart(
              label: 'Sets',
              line: 'Working sets logged against the target. Warm-ups don\'t count.',
              points: score.sets,
              max: SessionScoreBreakdown.setsMax,
            ),
            _ScorePart(
              label: 'New bests',
              line: _recordsLine,
              points: score.records,
              max: SessionScoreBreakdown.recordsMax,
              last: true,
            ),
            const SizedBox(height: 12),
            Text(
              'Finish the plan and match last time for 85. New bests take it to 100. Skipped exercises earn nothing.',
              style: KText.caption.copyWith(color: KColor.textMuted, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScorePart extends StatelessWidget {
  final String label;
  final String line;
  final int points;
  final int max;
  final bool last;
  const _ScorePart({required this.label, required this.line, required this.points, required this.max, this.last = false});

  @override
  Widget build(BuildContext context) {
    final f = max == 0 ? 0.0 : (points / max).clamp(0.0, 1.0);
    return Semantics(
      label: '$label, $points of $max. $line',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: last ? null : Border(bottom: BorderSide(color: KColor.fg.withValues(alpha: 0.08))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(label, style: KText.bodyMedium.copyWith(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
                Text(
                  '$points',
                  style: KText.numSmall.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: KColor.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  ' / $max',
                  style: KText.numSmall.copyWith(
                    fontSize: 13,
                    color: KColor.textMuted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(line, style: KText.caption.copyWith(color: KColor.textSecondary, height: 1.35)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: KRadius.pill,
              child: SizedBox(
                height: 4,
                child: LinearProgressIndicator(
                  value: f,
                  minHeight: 4,
                  backgroundColor: KColor.fg.withValues(alpha: KColor.isDark ? 0.08 : 0.07),
                  valueColor: AlwaysStoppedAnimation<Color>(KColor.ink),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}