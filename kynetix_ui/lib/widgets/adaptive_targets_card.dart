import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../services/adaptive_expenditure_service.dart';

/// "Adapt to my weight trend": the switch for adaptive targets, what the
/// user's own data says they burn, and why, in plain words.
class AdaptiveTargetsCard extends StatelessWidget {
  const AdaptiveTargetsCard({super.key, required this.formulaKcal, required this.onChanged});

  /// Maintenance from the formula alone (BMR × activity + steps).
  final double formulaKcal;

  /// Called after the switch flips, so the screen can refresh its targets.
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final svc = AdaptiveExpenditureService.instance;
    return ValueListenableBuilder<int>(
      valueListenable: svc.changes,
      builder: (context, _, _) {
        final e = svc.current(formulaKcal);
        final on = svc.enabled;
        final applied = svc.appliedKcal;
        return Container(
          margin: const EdgeInsets.fromLTRB(KSpacing.lg, 0, KSpacing.lg, KSpacing.md),
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 14),
          decoration: BoxDecoration(
            gradient: KShade.sunken(KColor.card),
            borderRadius: KRadius.md,
            border: Border.all(color: KColor.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Adapt to my weight trend', style: KText.h3),
                        const SizedBox(height: 2),
                        Text(
                          'Learns what you really burn from your meals and weigh-ins. Moves at most once a week.',
                          style: KText.caption,
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: on,
                    onChanged: (v) async {
                      KHaptics.select();
                      await svc.setEnabled(v, formulaKcal);
                      onChanged();
                    },
                  ),
                ],
              ),
              const SizedBox(height: KSpacing.md),
              if (e.ready) ...[
                Row(
                  children: [
                    _Figure(label: 'Formula', kcal: formulaKcal),
                    _Figure(label: 'Your data', kcal: e.observedKcal!),
                    _Figure(label: on ? 'Using' : 'Would use', kcal: on ? (applied ?? e.blendedKcal) : e.blendedKcal, strong: true),
                  ],
                ),
                const SizedBox(height: KSpacing.sm),
                Text(e.explanation, style: KText.caption.copyWith(color: KColor.textSecondary)),
                const SizedBox(height: 4),
                Text(
                  'Trusted ${(e.confidence * 100).round()}%: the more days you log and the more often you weigh in, the more it counts.',
                  style: KText.caption.copyWith(color: KColor.textMuted, fontSize: 11.5),
                ),
              ] else
                Text(
                  on
                      ? 'On. Using the formula until there is enough data: ${e.missing}.'
                      : 'Needs ${e.missing} in the last ${e.windowDays} days.',
                  style: KText.caption.copyWith(color: KColor.textSecondary),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.kcal, this.strong = false});
  final String label;
  final double kcal;
  final bool strong;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: KText.caption.copyWith(color: KColor.textMuted, fontSize: 11.5)),
            const SizedBox(height: 2),
            Text(
              '${kcal.round()} kcal',
              style: KText.numSmall.copyWith(fontSize: 14, color: strong ? KColor.ember : null),
            ),
          ],
        ),
      );
}
