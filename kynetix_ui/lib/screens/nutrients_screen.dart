// Nutrients: today and the 7-day average for iron, calcium, B12, vitamin D,
// sodium, potassium, magnesium and zinc against ICMR-NIN targets, with
// honest coverage ("tracked for 6 of 9 meals") and, for the lowest one, the
// foods that would close the gap: ones the user already eats first.

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../data/kyno_food_catalog.dart';
import '../models/day_log.dart';
import '../models/micronutrients.dart';
import '../services/micronutrient_service.dart';
import '../services/persistence_service.dart';
import '../services/profile_service.dart';

/// Formats an amount in its unit: "11 mg", "1.4 µg", "2,100 mg".
String formatMicro(double v, Micro m) {
  final String n;
  if (v >= 1000) {
    n = thousands(v);
  } else if (v >= 20) {
    n = v.round().toString();
  } else if (v >= 1) {
    final r = (v * 10).round() / 10;
    n = r == r.roundToDouble() ? r.round().toString() : r.toStringAsFixed(1);
  } else {
    n = v <= 0 ? '0' : v.toStringAsFixed(v < 0.1 ? 2 : 1);
  }
  return '$n ${m.unit}';
}

class NutrientsScreen extends StatelessWidget {
  const NutrientsScreen({super.key, this.onLogFood, this.now});

  /// Called with a food's log text when the user taps a suggestion. Leave
  /// null to show suggestions without a log action.
  final void Function(String logText)? onLogFood;

  /// Fixed clock for tests.
  final DateTime? now;

  static Route<void> route({void Function(String logText)? onLogFood}) =>
      MaterialPageRoute<void>(builder: (_) => NutrientsScreen(onLogFood: onLogFood));

  @override
  Widget build(BuildContext context) {
    return KPage(
      tone: KTone.fuel,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        leading: BackButton(color: KColor.textSecondary),
        title: Text('Nutrients', style: KText.h3.copyWith(fontSize: 16)),
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: PersistenceService.dayLogNotifier,
        builder: (context, _, _) => _Body(onLogFood: onLogFood, now: now ?? DateTime.now()),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.onLogFood, required this.now});
  final void Function(String logText)? onLogFood;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final today = DateTime(now.year, now.month, now.day);
    final svc = MicronutrientService.instance;
    final summary = svc.summarize(
      store: dayLogStore,
      today: today,
      profile: ProfileService.instance.currentUserProfile,
    );
    final low = summary.lowest;
    final picks = low == null
        ? const <MicroFoodPick>[]
        : svc.richFoods(low.micro,
            store: dayLogStore, today: today, diets: summary.diets, target: low.target.amount);

    final nothingYet = !summary.hasHistory && summary.statuses.every((s) => !s.today.hasAny);

    return ListView(
      padding: const EdgeInsets.fromLTRB(KSpacing.p, KSpacing.sm, KSpacing.p, KSpacing.xxxl),
      children: [
        Text('Today and your week', style: KText.h1),
        const SizedBox(height: KSpacing.sm),
        Text(_coverageLine(summary), style: KText.body.copyWith(color: KColor.textSecondary)),
        if (nothingYet) ...[
          const SizedBox(height: KSpacing.xl),
          Text(
            'Iron, calcium, B12 and the rest show up for meals you log from now on. '
            'Older meals stay exactly as they were and count as not tracked.',
            style: KText.body,
          ),
        ],
        if (low != null) ...[
          const SizedBox(height: KSpacing.xl),
          _OracleCard(status: low, picks: picks, diets: summary.diets, onLogFood: onLogFood),
        ],
        const SizedBox(height: KSpacing.xl),
        for (final s in summary.statuses) ...[
          _NutrientRow(status: s),
          const KHairline(),
        ],
        const SizedBox(height: KSpacing.lg),
        Text(
          'Targets: ICMR-NIN 2020 recommended dietary allowances for Indian adults. '
          'Food values: IFCT 2017 and USDA, the pack label, or Kyno\'s estimate. '
          'A guide to patterns, not a diagnosis.',
          style: KText.caption.copyWith(color: KColor.textMuted),
        ),
      ],
    );
  }

  static String _coverageLine(MicroSummary s) {
    if (s.mealsToday == 0) return 'Nothing logged today yet. The 7-day average uses days with tracked meals.';
    return 'Tracked for ${s.trackedMealsToday} of ${plural(s.mealsToday, 'meal')} today. '
        'Untracked meals are missing data, not zero.';
  }
}

class _NutrientRow extends StatelessWidget {
  const _NutrientRow({required this.status});
  final MicroStatus status;

  @override
  Widget build(BuildContext context) {
    final s = status;
    final m = s.micro;
    final target = s.target.amount;
    final over = m.isLimit && s.today.amount > target;
    final barColor = over ? KColor.ember : KColor.ink;
    final todayTracked = s.today.hasAny;
    final avg = s.avg7;

    final targetText = m.isLimit ? 'under ${formatMicro(target, m)}' : 'of ${formatMicro(target, m)}';
    final semantics = StringBuffer('${m.label}. ');
    semantics.write(todayTracked
        ? 'Today ${formatMicro(s.today.amount, m)} $targetText.'
        : 'Not tracked today.');
    if (avg != null) semantics.write(' 7-day average ${formatMicro(avg, m)}.');

    return Semantics(
      label: semantics.toString(),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: KSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(child: Text(m.label, style: KText.h3.copyWith(fontSize: 16))),
                if (todayTracked)
                  Text.rich(TextSpan(children: [
                    TextSpan(
                      text: formatMicro(s.today.amount, m),
                      style: KText.numSmall.copyWith(fontWeight: FontWeight.w600, color: KColor.textPrimary),
                    ),
                    TextSpan(text: ' $targetText', style: KText.caption),
                  ]))
                else
                  Text('Not tracked today', style: KText.caption.copyWith(color: KColor.textMuted)),
              ],
            ),
            const SizedBox(height: KSpacing.sm),
            if (todayTracked)
              KBar(progress: target <= 0 ? 0 : s.today.amount / target, colors: [barColor], height: 6)
            else
              const _UntrackedBar(),
            if (over) ...[
              const SizedBox(height: KSpacing.xs),
              Text('Over the daily limit', style: KText.caption.copyWith(color: KColor.ember)),
            ],
            const SizedBox(height: KSpacing.sm),
            if (avg != null) ...[
              KBar(
                progress: target <= 0 ? 0 : avg / target,
                colors: [KColor.textMuted],
                height: 3,
              ),
              const SizedBox(height: KSpacing.xs),
              Text(
                '7-day average ${formatMicro(avg, m)}, '
                '${(avg / target * 100).round()}% of ${m.isLimit ? 'the limit' : 'target'} '
                '(${plural(s.avgDays, 'tracked day')})',
                style: KText.caption,
              ),
            ] else
              Text('7-day average builds up as you log', style: KText.caption.copyWith(color: KColor.textMuted)),
          ],
        ),
      ),
    );
  }
}

/// A dotted track: there's no number here, and it shouldn't look like zero.
class _UntrackedBar extends StatelessWidget {
  const _UntrackedBar();

  @override
  Widget build(BuildContext context) {
    final c = KColor.fg.withValues(alpha: KColor.isDark ? 0.14 : 0.12);
    return SizedBox(
      height: 6,
      child: LayoutBuilder(
        builder: (context, box) {
          final n = (box.maxWidth / 10).floor().clamp(1, 200);
          return Row(
            children: [
              for (var i = 0; i < n; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: c, borderRadius: KRadius.pill),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _OracleCard extends StatelessWidget {
  const _OracleCard({required this.status, required this.picks, required this.diets, required this.onLogFood});
  final MicroStatus status;
  final List<MicroFoodPick> picks;
  final Set<FoodDiet> diets;
  final void Function(String logText)? onLogFood;

  @override
  Widget build(BuildContext context) {
    final m = status.micro;
    final avg = status.avg7;
    final basis = avg != null
        ? 'About ${formatMicro(avg, m)} a day this week, ${(avg / status.target.amount * 100).round()}% of ${formatMicro(status.target.amount, m)}.'
        : 'About ${formatMicro(status.today.amount, m)} so far today, against ${formatMicro(status.target.amount, m)}.';
    final yours = picks.where((p) => p.fromHistory).toList();
    final fresh = picks.where((p) => !p.fromHistory).toList();

    return KCard(
      color: KColor.tint(KColor.fuel),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Lowest right now', style: KText.caption.copyWith(color: KColor.fuel)),
          const SizedBox(height: KSpacing.xs),
          Text(m.label, style: KText.h2),
          const SizedBox(height: KSpacing.xs),
          Text(basis, style: KText.body.copyWith(color: KColor.textSecondary)),
          if (yours.isNotEmpty) ...[
            const SizedBox(height: KSpacing.lg),
            Text('From what you already eat', style: KText.label),
            for (final p in yours) _PickRow(pick: p, micro: m, onLogFood: onLogFood),
          ],
          if (fresh.isNotEmpty) ...[
            const SizedBox(height: KSpacing.lg),
            Text(yours.isEmpty ? 'Good sources' : 'Worth adding', style: KText.label),
            for (final p in fresh) _PickRow(pick: p, micro: m, onLogFood: onLogFood),
          ],
          const SizedBox(height: KSpacing.md),
          Text(MicronutrientService.tipFor(m, diets), style: KText.caption),
        ],
      ),
    );
  }
}

class _PickRow extends StatelessWidget {
  const _PickRow({required this.pick, required this.micro, required this.onLogFood});
  final MicroFoodPick pick;
  final Micro micro;
  final void Function(String logText)? onLogFood;

  @override
  Widget build(BuildContext context) {
    final amount = formatMicro(pick.amount, micro);
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: KSpacing.sm),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pick.name, style: KText.bodyMedium),
                  Text(pick.serving, style: KText.caption),
                ],
              ),
            ),
            const SizedBox(width: KSpacing.md),
            Text(amount, style: KText.numSmall.copyWith(fontWeight: FontWeight.w600, color: KColor.textPrimary)),
            if (onLogFood != null) ...[
              const SizedBox(width: KSpacing.sm),
              KIcon(KIcons.add, size: KIcons.md, color: KColor.textSecondary),
            ],
          ],
        ),
      ),
    );
    if (onLogFood == null) {
      return Semantics(label: '${pick.name}, ${pick.serving}, $amount', excludeSemantics: true, child: row);
    }
    return Pressable(
      onTap: () {
        KHaptics.select();
        onLogFood!(pick.logText);
      },
      semanticLabel: 'Log ${pick.name}, ${pick.serving}, $amount',
      borderRadius: KRadius.sm,
      scale: 0.985,
      child: row,
    );
  }
}
