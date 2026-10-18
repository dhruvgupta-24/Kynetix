// Compact micronutrient summary for the dashboard: the three nutrients
// furthest from target (sodium when it's over the limit), each with a thin
// bar, plus how many of today's meals are tracked. Taps through to
// [NutrientsScreen].

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/day_log.dart';
import '../models/micronutrients.dart';
import '../screens/nutrients_screen.dart';
import '../services/micronutrient_service.dart';
import '../services/persistence_service.dart';
import '../services/profile_service.dart';

class NutrientsSummaryCard extends StatelessWidget {
  const NutrientsSummaryCard({super.key, this.onOpen, this.onLogFood, this.now});

  /// Replaces the default push of [NutrientsScreen].
  final VoidCallback? onOpen;

  /// Passed to [NutrientsScreen] so its suggestions can open the meal box.
  final void Function(String logText)? onLogFood;

  /// Fixed clock for tests.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: PersistenceService.dayLogNotifier,
      builder: (context, _, _) {
        final t = now ?? DateTime.now();
        final summary = MicronutrientService.instance.summarize(
          store: dayLogStore,
          today: DateTime(t.year, t.month, t.day),
          profile: ProfileService.instance.currentUserProfile,
        );
        final rows = _pick(summary);
        final open = onOpen ??
            () => Navigator.of(context).push(NutrientsScreen.route(onLogFood: onLogFood));
        final coverage = summary.mealsToday == 0
            ? 'Nothing logged today'
            : 'Tracked for ${summary.trackedMealsToday} of ${plural(summary.mealsToday, 'meal')} today';

        return Pressable(
          onTap: () {
            KHaptics.select();
            open();
          },
          semanticLabel: 'Nutrients. $coverage. Open details',
          borderRadius: KRadius.lg,
          scale: 0.985,
          child: KCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Nutrients', style: KText.h3)),
                    KIcon(KIcons.next, size: KIcons.md, color: KColor.textMuted),
                  ],
                ),
                const SizedBox(height: 2),
                Text(coverage, style: KText.caption),
                const SizedBox(height: KSpacing.md),
                if (rows.isEmpty)
                  Text(
                    'Iron, calcium, B12 and more show up for meals you log from now on.',
                    style: KText.body.copyWith(color: KColor.textSecondary),
                  )
                else
                  for (final r in rows) _MiniRow(status: r.$1, weekly: r.$2),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Up to three rows: sodium first when over the limit, then the lowest
  /// nutrients by 7-day average (or today's when there's no week yet).
  static List<(MicroStatus, bool)> _pick(MicroSummary s) {
    final out = <(MicroStatus, bool)>[];
    final na = s.of(Micro.sodium);
    final naRatio = na.avgRatio ?? (na.today.isTracked ? na.todayRatio : null);
    if (naRatio != null && naRatio > 1) out.add((na, na.avgRatio != null));
    final ranked = <(MicroStatus, double, bool)>[];
    for (final x in s.statuses) {
      if (x.micro.isLimit) continue;
      if (x.avgRatio != null) {
        ranked.add((x, x.avgRatio!, true));
      } else if (x.today.hasAny) {
        ranked.add((x, x.todayRatio, false));
      }
    }
    ranked.sort((a, b) => a.$2.compareTo(b.$2));
    for (final r in ranked) {
      if (out.length >= 3) break;
      out.add((r.$1, r.$3));
    }
    return out;
  }
}

class _MiniRow extends StatelessWidget {
  const _MiniRow({required this.status, required this.weekly});
  final MicroStatus status;

  /// Showing the 7-day average (true) or today so far (false).
  final bool weekly;

  @override
  Widget build(BuildContext context) {
    final m = status.micro;
    final v = weekly ? status.avg7! : status.today.amount;
    final ratio = status.target.amount <= 0 ? 0.0 : v / status.target.amount;
    final over = m.isLimit && ratio > 1;
    final pct = '${(ratio * 100).round()}%';
    final when = weekly ? '7-day avg' : 'today';
    return Padding(
      padding: const EdgeInsets.only(bottom: KSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(m.label, style: KText.bodyMedium)),
              Text(
                over ? '$pct of limit, $when' : '$pct, $when',
                style: KText.caption.copyWith(color: over ? KColor.danger : KColor.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: KSpacing.xs),
          KBar(progress: ratio, colors: [over ? KColor.danger : KColor.fuel], height: 4),
        ],
      ),
    );
  }
}
