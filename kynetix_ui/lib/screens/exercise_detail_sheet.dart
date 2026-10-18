import 'package:flutter/material.dart';
import '../models/exercise_definition.dart';
import '../models/workout_split.dart';
import '../services/workout_service.dart';
import '../config/app_theme.dart';
import '../widgets/exercise_media_widget.dart';

/// Shows the detailed anatomical information, step-by-step cues, equipment info,
/// and personal historical PR stats for an exercise.
Future<Exercise?> showExerciseDetailSheet(
  BuildContext context, {
  required ExerciseDefinition definition,
  bool showAddButton = true,
}) {
  return showKSheet<Exercise>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => ExerciseDetailSheet(
      definition: definition,
      showAddButton: showAddButton,
    ),
  );
}

class ExerciseDetailSheet extends StatelessWidget {
  final ExerciseDefinition definition;
  final bool showAddButton;

  const ExerciseDetailSheet({
    super.key,
    required this.definition,
    this.showAddButton = true,
  });

  @override
  Widget build(BuildContext context) {
    // Rebuilds when workout history hydrates or changes, so the bests panel
    // moves from its loader to real numbers without reopening the sheet.
    return ListenableBuilder(
      listenable: WorkoutService.instance,
      builder: (context, _) => _buildSheet(context),
    );
  }

  Widget _buildSheet(BuildContext context) {
    final media = MediaQuery.of(context);
    final ready = WorkoutService.instance.isReady;
    final history = WorkoutService.instance.historyFor(definition.id);

    double maxWeight = 0.0;
    int maxReps = 0;
    double bestE1rm = 0.0;
    bool hasLogs = false;

    for (final h in history) {
      for (final s in h.entry.sets) {
        if (!s.isMainWorkingSet) continue;
        hasLogs = true;
        if (s.weight > maxWeight) maxWeight = s.weight;
        if (s.reps > maxReps) maxReps = s.reps;
        final e1rm = s.estimatedOneRepMax;
        if (e1rm > bestE1rm) bestE1rm = e1rm;
      }
    }

    final lastSession = history.isNotEmpty ? history.first : null;
    final lastTopSet = lastSession?.entry.topWorkingSet;

    return Container(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.88),
      decoration: BoxDecoration(
        color: KColor.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(
            color: KColor.isDark
                ? KColor.fg.withValues(alpha: 0.08)
                : KColor.border,
          ),
        ),
      ),
      child: Column(
        children: [
          // ── Sheet chrome: handle, title, close
          Stack(
            children: [
              // The close glyph sits on the handle row (above the title's
              // first line), so the title keeps the full sheet width.
              KSheetHeader(definition.name, subtitle: _subtitle),
              Positioned(
                top: 0,
                right: KSpacing.sm,
                child: IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    backgroundColor: KColor.fg.withValues(
                      alpha: KColor.isDark ? 0.06 : 0.05,
                    ),
                  ),
                  icon: Icon(
                    Icons.close_rounded,
                    color: KColor.textSecondary,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),

          // ── Tags
          Padding(
            padding: const EdgeInsets.fromLTRB(
              KSpacing.p,
              KSpacing.md,
              KSpacing.p,
              14,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Wrap(
                spacing: KSpacing.sm,
                runSpacing: 6,
                children: [
                  // Plain labelled facts, not tinted pills. Only the target
                  // muscle carries the train accent.
                  // The demo below shows the muscle; here it is a word.
                  _Fact(text: definition.category),
                  _Fact(icon: KIcons.train, text: definition.equipment),
                  _Fact(
                    icon: KIcons.target,
                    text: definition.targetMuscle,
                    color: KColor.violet,
                  ),
                ],
              ),
            ),
          ),

          Divider(height: 1, color: KColor.divider),

          // ── Scrollable content
          Expanded(
            // Short, bounded content: a non-lazy column keeps every section
            // (and its semantics) mounted, so cues are always reachable.
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                KSpacing.p,
                KSpacing.lg,
                KSpacing.p,
                KSpacing.xxl,
              ),
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 0. Visual demonstration & media
                  ClipRRect(
                    borderRadius: KRadius.lg,
                    child: ExerciseMediaWidget(
                      definition: definition,
                      height: 190,
                    ),
                  ),
                  const SizedBox(height: KSpacing.xl),

                  // 1. Muscle anatomy
                  const _SectionHeader(
                    'Muscles worked',
                    Icons.accessibility_new_rounded,
                  ),
                  const SizedBox(height: 10),
                  _Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _LabeledRow(
                          label: 'Main muscle:',
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: KChip(
                              definition.targetMuscle,
                              color: KColor.violet,
                            ),
                          ),
                        ),
                        if (definition.secondaryMuscles.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          _LabeledRow(
                            label: 'Also works:',
                            child: Text(
                              definition.secondaryMuscles.join(', '),
                              style: KText.body.copyWith(
                                color: KColor.textPrimary,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        _LabeledRow(
                          label: 'Type:',
                          child: Text(
                            definition.classification.label,
                            style: KText.bodyMedium.copyWith(
                              color: KColor.textPrimary,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: KSpacing.xl),

                  // 2. Personal historical performance & PRs
                  const _SectionHeader(
                    'Your bests',
                    Icons.emoji_events_rounded,
                  ),
                  const SizedBox(height: 10),
                  _Panel(
                    child: AnimatedSwitcher(
                      duration: KMotion.of(context, KMotion.standard),
                      child: !ready
                          ? Padding(
                              key: const ValueKey('loading'),
                              padding: const EdgeInsets.symmetric(
                                vertical: KSpacing.xs,
                              ),
                              child: Semantics(
                                container: true,
                                liveRegion: true,
                                label: 'Loading your bests',
                                child: ExcludeSemantics(
                                  child: Row(
                                    children: [
                                      const KRepLoader(
                                        size: 32,
                                        semanticsLabel: null,
                                      ),
                                      const SizedBox(width: KSpacing.md),
                                      Expanded(
                                        child: KLoadingLabel(
                                          messages: const [
                                            'Pulling your history…',
                                          ],
                                          textAlign: TextAlign.start,
                                          style: KText.caption.copyWith(
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          : hasLogs
                          ? Column(
                              key: const ValueKey('logs'),
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: _StatColumn(
                                        label: 'Best weight',
                                        value: maxWeight,
                                        decimals: 1,
                                        unit: ' kg',
                                        color: KColor.textPrimary,
                                      ),
                                    ),
                                    Expanded(
                                      child: _StatColumn(
                                        label: 'Best reps',
                                        value: maxReps,
                                        unit: ' reps',
                                        color: KColor.textPrimary,
                                      ),
                                    ),
                                    Expanded(
                                      child: _StatColumn(
                                        label: 'Estimated 1RM',
                                        value: bestE1rm,
                                        decimals: 1,
                                        unit: ' kg',
                                        color: KColor.violet,
                                      ),
                                    ),
                                  ],
                                ),
                                if (lastTopSet != null) ...[
                                  const SizedBox(height: KSpacing.md),
                                  Divider(height: 1, color: KColor.divider),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Last top set',
                                          style: KText.caption.copyWith(
                                            color: KColor.textSecondary,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '${amount(lastTopSet.weight)} kg × ${plural(lastTopSet.reps, 'rep')}',
                                        style: KText.numSmall.copyWith(fontSize: 14),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            )
                          : Padding(
                              key: const ValueKey('empty'),
                              padding: const EdgeInsets.symmetric(
                                vertical: KSpacing.sm,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.insights_rounded,
                                    color: KColor.textMuted,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Nothing logged for this one yet. Your bests show up after your first session.',
                                      style: KText.caption.copyWith(
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: KSpacing.xl),

                  // 3. Step-by-step instructions & cues
                  if (definition.instructions.isNotEmpty) ...[
                    const _SectionHeader(
                      'How to do it',
                      Icons.format_list_numbered_rounded,
                    ),
                    const SizedBox(height: KSpacing.md),
                    for (final (i, text) in definition.instructions.indexed)
                      KReveal(
                        index: i,
                        maxIndex: 8,
                        rise: 10,
                        child: _CueRow(
                          index: i + 1,
                          text: text,
                          isLast: i == definition.instructions.length - 1,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),

          // ── Bottom CTA
          if (showAddButton)
            Container(
              padding: const EdgeInsets.fromLTRB(
                KSpacing.p,
                KSpacing.md,
                KSpacing.p,
                KSpacing.lg,
              ),
              decoration: BoxDecoration(
                color: KColor.surface,
                border: Border(top: BorderSide(color: KColor.divider)),
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  child: KButton(
                    label: 'Add to workout',
                    icon: Icons.add_rounded,
                    onTap: () {
                      Navigator.of(context).pop(definition.toExercise());
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Short descriptive line under the title (equipment · primary muscle),
  /// written in sentence case so it never duplicates the uppercase tags.
  String? get _subtitle {
    final parts = <String>[
      if (definition.equipment.trim().isNotEmpty) definition.equipment.trim(),
      if (definition.bodyPart.trim().isNotEmpty)
        '${definition.bodyPart.trim()} focus',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

// ─── Private pieces ──────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader(this.title, this.icon);

  @override
  Widget build(BuildContext context) {
    // Quiet monochrome header: icon + label, no tinted tile.
    return Row(
      children: [
        ExcludeSemantics(
          child: Icon(icon, color: KColor.textMuted, size: 16),
        ),
        const SizedBox(width: KSpacing.sm),
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: KText.label.copyWith(
                fontSize: 11.5,
                color: KColor.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One fact about the movement: a small glyph and a word, no container.
class _Fact extends StatelessWidget {
  final IconData? icon;
  final String text;
  final Color? _color;
  Color get color => _color ?? KColor.textSecondary;
  const _Fact({this.icon, required this.text, Color? color}) : _color = color;

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 28),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            KIcon(icon!, size: KIcons.sm, color: color),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              text,
              style: KText.bodyMedium.copyWith(fontSize: 14, color: color == KColor.textSecondary ? KColor.textPrimary : color),
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final Widget child;
  const _Panel({required this.child});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: KCard(
        padding: const EdgeInsets.all(KSpacing.lg),
        borderRadius: KRadius.md,
        child: child,
      ),
    );
  }
}

class _LabeledRow extends StatelessWidget {
  final String label;
  final Widget child;
  const _LabeledRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: KSpacing.sm,
      runSpacing: KSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          label,
          style: KText.caption.copyWith(
            color: KColor.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        child,
      ],
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String label;
  final num value;
  final int decimals;
  final String unit;
  final Color color;

  const _StatColumn({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    this.decimals = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        KAnimatedCount(
          value: value,
          decimalPlaces: decimals,
          suffix: unit,
          style: KText.numMedium.copyWith(
            color: color,
            fontSize: 19,
          ),
        ),
        const SizedBox(height: KSpacing.xs),
        Text(
          label,
          textAlign: TextAlign.center,
          style: KText.caption.copyWith(
            fontSize: 12,
            color: KColor.textMuted,
          ),
        ),
      ],
    );
  }
}

class _CueRow extends StatelessWidget {
  final int index;
  final String text;
  final bool isLast;
  const _CueRow({
    required this.index,
    required this.text,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : KSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: KColor.fg.withValues(alpha: KColor.isDark ? 0.06 : 0.05),
              border: Border.all(
                color: KColor.fg.withValues(alpha: KColor.isDark ? 0.14 : 0.16),
              ),
            ),
            child: Text(
              '$index',
              style: KText.numSmall.copyWith(
                color: KColor.textPrimary,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: KSpacing.md),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                text,
                style: KText.body.copyWith(fontSize: 14.5, height: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
