import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_theme.dart';
import '../models/workout_split.dart';
import '../services/rest_timer_prefs.dart';
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
    isScrollControlled: false,
    builder: (ctx) => SafeArea(
      child: Padding(
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
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: selected ? KColor.ink : Colors.transparent,
              borderRadius: KRadius.pill,
              border: Border.all(color: selected ? KColor.ink : KColor.fg.withValues(alpha: 0.16)),
            ),
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
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: KColor.train, width: 2)),
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
