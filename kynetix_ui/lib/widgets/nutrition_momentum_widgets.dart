import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/insights_models.dart';
import '../services/insights_engine.dart';
import '../services/nutrition_momentum.dart';
import '../ui/k_rolling.dart';
import 'k_badge_medal.dart';

// ─── Nutrition momentum on the home screen ────────────────────────────────────
//
// Three pieces, one language:
// - the streak chip beside the greeting: seven dots for the last seven days
//   and the count, today shown as an open ring until something is logged;
// - the streak sheet behind it: the number, the best run, the protein run,
//   and one honest line about today;
// - the "This week" card: three challenges as small rings (the fuel rings'
//   flat lap), and the next badge with its progress.
// Nothing here scolds. A missed day is a quiet dot, never red.

const _weekLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

/// Seven dots, oldest first: logged (ember), missed (track), still open
/// (a ring). Purely visual; the parent carries the words.
class _DayDots extends StatelessWidget {
  const _DayDots({required this.days, this.size = 6, this.gap = 3, this.letters = false, this.startWeekday});
  final List<bool?> days;
  final double size;
  final double gap;
  final bool letters;

  /// Weekday (1 = Monday) of the first dot, for the letters.
  final int? startWeekday;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < days.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: days[i] == true ? KColor.ember : (days[i] == false ? KColor.track : null),
                    border: days[i] == null
                        ? Border.all(color: KColor.ember.withValues(alpha: 0.8), width: size > 8 ? 1.5 : 1)
                        : null,
                  ),
                ),
                if (letters) ...[
                  const SizedBox(height: 6),
                  Text(
                    _weekLetters[((startWeekday ?? 1) - 1 + i) % 7],
                    style: KText.label.copyWith(fontSize: 11),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The streak beside the greeting: "● ● ● ● ● ● ○  12".
class StreakChip extends StatelessWidget {
  const StreakChip({super.key, required this.streak, required this.onTap});
  final StreakSnapshot streak;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = streak.days;
    final label = n == 0
        ? 'No logging streak yet. Opens streak details'
        : '$n day logging streak${streak.atRisk ? ', today not logged yet' : ''}. Opens streak details';
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        borderRadius: KRadius.pill,
        scale: 0.96,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
          decoration: BoxDecoration(
            gradient: KShade.raised(KColor.card),
            borderRadius: KRadius.pill,
            border: Border.all(color: KColor.isDark ? KColor.fg.withValues(alpha: 0.08) : KColor.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DayDots(days: streak.last7, size: 5, gap: 2.5),
              const SizedBox(width: 10),
              KRollingNumber.int(
                n,
                style: KText.numSmall.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 3),
              Text(
                n == 1 ? 'day' : 'days',
                style: KText.caption.copyWith(fontSize: 12.5, color: KColor.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The streak, opened up.
Future<void> showStreakSheet(
  BuildContext context, {
  required StreakSnapshot streak,
  VoidCallback? onLogMeal,
}) {
  final today = DateTime.now();
  return showKSheet<void>(
    context: context,
    builder: (ctx) {
      final n = streak.days;
      final line = n == 0
          ? 'Log a meal today and a streak starts. Anything counts, even chai.'
          : streak.todayLogged
              ? "Today's in. Keep it rolling tomorrow."
              : 'Log anything today to keep it going. Even chai counts.';
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(KSpacing.p, 0, KSpacing.p, KSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const KSheetHeader('Logging streak'),
              const SizedBox(height: KSpacing.md),
              Semantics(
                label: '$n day streak',
                excludeSemantics: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    KRollingNumber.int(n, fromZero: true, style: KText.numDisplay.copyWith(fontSize: 56)),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: Text(n == 1 ? 'day in a row' : 'days in a row', style: KText.h3.copyWith(color: KColor.textSecondary)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: KSpacing.sm),
              Text(line, style: KText.body.copyWith(color: KColor.textSecondary)),
              const SizedBox(height: KSpacing.xl),
              Text('Last 7 days', style: KText.caption.copyWith(color: KColor.textMuted, fontWeight: FontWeight.w600)),
              const SizedBox(height: KSpacing.sm),
              Semantics(
                label: 'Logged on ${streak.last7.where((d) => d == true).length} of the last 7 days',
                excludeSemantics: true,
                child: _DayDots(
                  days: streak.last7,
                  size: 14,
                  gap: 14,
                  letters: true,
                  startWeekday: today.subtract(const Duration(days: 6)).weekday,
                ),
              ),
              const SizedBox(height: KSpacing.xl),
              Row(
                children: [
                  Expanded(child: _Stat(value: streak.best, label: 'Best run')),
                  Expanded(child: _Stat(value: streak.proteinDays, label: 'Protein days in a row', color: KColor.protein)),
                ],
              ),
              if (onLogMeal != null && !streak.todayLogged) ...[
                const SizedBox(height: KSpacing.xl),
                KButton(
                  label: 'Log a meal',
                  onTap: () {
                    Navigator.of(ctx).pop();
                    onLogMeal();
                  },
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.color});
  final int value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value', style: KText.numMedium.copyWith(color: color ?? KColor.textPrimary)),
          const SizedBox(height: 2),
          Text(label, style: KText.caption.copyWith(color: KColor.textMuted)),
        ],
      ),
    );
  }
}

// ─── This week ────────────────────────────────────────────────────────────────

/// Three challenges and the next badge.
class ThisWeekCard extends StatelessWidget {
  const ThisWeekCard({
    super.key,
    required this.momentum,
    required this.nextBadge,
    required this.onOpenBadges,
  });

  final NutritionMomentum momentum;
  final AchievementProgress? nextBadge;
  final VoidCallback onOpenBadges;

  @override
  Widget build(BuildContext context) {
    final done = momentum.doneCount;
    final total = momentum.challenges.length;
    final daysLeft = momentum.challenges.isEmpty ? 0 : momentum.challenges.first.daysLeft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: KSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text('This week', style: KText.h3.copyWith(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
              Text(
                done == total
                    ? 'All $total done'
                    : (daysLeft <= 1 ? 'Last day' : '$done of $total done · $daysLeft days left'),
                style: KText.caption.copyWith(color: KColor.textMuted),
              ),
            ],
          ),
        ),
        KCard(
          padding: const EdgeInsets.fromLTRB(KSpacing.lg, KSpacing.xs, KSpacing.lg, KSpacing.xs),
          child: Column(
            children: [
              for (var i = 0; i < momentum.challenges.length; i++) ...[
                if (i > 0) const KHairline(indent: 52),
                _ChallengeRow(challenge: momentum.challenges[i]),
              ],
              if (nextBadge != null) ...[
                const KHairline(),
                _NextBadgeRow(progress: nextBadge!, onTap: onOpenBadges),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ChallengeRow extends StatelessWidget {
  const _ChallengeRow({required this.challenge});
  final WeeklyChallenge challenge;

  @override
  Widget build(BuildContext context) {
    final c = challenge;
    final ring = SizedBox(
      width: 40,
      height: 40,
      child: KDabbaRings(
        size: 40,
        stroke: 3.5,
        rings: [KRingSpec(c.fraction, KRingColors.calories)],
        child: Center(
          child: AnimatedSwitcher(
            duration: KMotion.of(context, KMotion.standard),
            switchInCurve: KMotion.overshoot,
            transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
            child: c.done
                ? Icon(Icons.check_rounded, key: const ValueKey('done'), size: 20, color: KColor.ember)
                : Text(
                    '${c.progress}',
                    key: ValueKey(c.progress),
                    style: KText.numSmall.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      label: '${c.title}. ${c.status}. Opens how it counts',
      excludeSemantics: true,
      child: Pressable(
        onTap: () => _showChallengeSheet(context, c),
        borderRadius: KRadius.md,
        scale: 0.99,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              ring,
              const SizedBox(width: KSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.title,
                      style: KText.bodyMedium.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.done ? KColor.textSecondary : KColor.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      c.status,
                      style: KText.caption.copyWith(color: c.done ? KColor.ember : KColor.textMuted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: KColor.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showChallengeSheet(BuildContext context, WeeklyChallenge c) {
  return showKSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(KSpacing.p, 0, KSpacing.p, KSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KSheetHeader(c.title, subtitle: c.rule),
            const SizedBox(height: KSpacing.lg),
            Semantics(
              label: '${c.progress} of ${c.goal} days so far this week',
              excludeSemantics: true,
              child: _DayDots(days: c.week, size: 14, gap: 14, letters: true, startWeekday: 1),
            ),
            const SizedBox(height: KSpacing.lg),
            Text(c.status, style: KText.body.copyWith(color: KColor.textSecondary)),
            const SizedBox(height: KSpacing.sm),
            Text(
              'Kyno sets each week\'s challenges from your last week: one step past it, never a leap.',
              style: KText.caption.copyWith(color: KColor.textMuted),
            ),
          ],
        ),
      ),
    ),
  );
}

class _NextBadgeRow extends StatelessWidget {
  const _NextBadgeRow({required this.progress, required this.onTap});
  final AchievementProgress progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meta = AchievementRegistry.fromId(progress.id);
    if (meta == null) return const SizedBox.shrink();
    return Semantics(
      button: true,
      label: 'Next badge: ${meta.title}, ${progress.current} of ${progress.target}. Opens badges',
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        borderRadius: KRadius.md,
        scale: 0.99,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              KBadgeMedal(id: progress.id, size: 40, state: KMedalState.progress, progress: progress.fraction),
              const SizedBox(width: KSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Next badge', style: KText.caption.copyWith(color: KColor.textMuted)),
                    const SizedBox(height: 1),
                    Text(meta.title, style: KText.bodyMedium.copyWith(fontSize: 15, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Text(
                '${progress.current} of ${progress.target}',
                style: KText.numSmall.copyWith(color: KColor.textSecondary),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 20, color: KColor.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
