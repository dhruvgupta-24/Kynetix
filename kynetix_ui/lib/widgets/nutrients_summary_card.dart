// Compact micronutrient summary for the dashboard: the three nutrients
// furthest from target (sodium when it's over the limit), each with a thin
// bar, plus how many of today's meals are tracked. When salt has clearly run
// high over the week, one line says so and names the foods behind it. Taps
// through to [NutrientsScreen].

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
        final watch = MicronutrientService.instance.sodiumWatch(
          summary,
          store: dayLogStore,
          today: DateTime(t.year, t.month, t.day),
        );
        final watchLine = watch == null ? null : sodiumWatchLine(watch);
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
          semanticLabel: 'Nutrients. $coverage.${watchLine == null ? '' : ' $watchLine'} Open details',
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
                if (watchLine != null) ...[
                  const SizedBox(height: KSpacing.md),
                  _WatchLine(watchLine),
                ],
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

/// "Salt ran high this week, about 2,650 mg a day against a 2,000 mg limit.
/// Maggi and mango pickle carried the most."
String sodiumWatchLine(SodiumWatch w) {
  final avg = (w.avg / 50).round() * 50.0;
  final head = 'Salt ran high this week, about ${formatMicro(avg, Micro.sodium)} a day '
      'against a ${formatMicro(w.limit, Micro.sodium)} limit.';
  if (w.sources.isEmpty) {
    return '$head Packaged snacks, pickles and outside food usually carry most of it.';
  }
  final names = w.sources.join(' and ');
  return '$head ${names[0].toUpperCase()}${names.substring(1)} carried the most.';
}

/// One calm line: an ember mark for attention, body text in the normal ink.
class _WatchLine extends StatelessWidget {
  const _WatchLine(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    // The card's own label already speaks this line.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: KIcon(KIcons.info, size: KIcons.sm, color: KColor.ember),
        ),
        const SizedBox(width: KSpacing.sm),
        Expanded(child: Text(text, style: KText.caption.copyWith(color: KColor.textPrimary))),
      ],
    );
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
                style: KText.caption.copyWith(color: over ? KColor.ember : KColor.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: KSpacing.xs),
          KBar(progress: ratio, colors: [over ? KColor.ember : KColor.ink], height: 4),
        ],
      ),
    );
  }
}
