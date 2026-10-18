import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../models/workout_split.dart';
import '../services/kyno_progression_engine.dart';
import 'exercise_media_widget.dart';

/// Single bounded Kyno Stage (~195px slot).
///
/// Houses the GymVisual demonstration GIF and the precomputed
/// Kyno Progression Recommendation in the exact same slot.
/// Switches smoothly via [AnimatedSwitcher] (KMotion.emphasized, collapses to
/// zero under reduced motion) after exactly 2 animation loops, with zero
/// loading delay. A `[Demo]` button allows replaying the demonstration anytime.
class KynoStageSlot extends StatefulWidget {
  final Exercise exercise;
  final KynoProgressionAdvice? advice;
  final double height;
  final VoidCallback? onDemoTapped;
  final ExerciseDemoPlaybackController? playbackController;

  const KynoStageSlot({
    super.key,
    required this.exercise,
    this.advice,
    this.height = 195.0,
    this.onDemoTapped,
    this.playbackController,
  });

  /// Deterministic neutral fallback progression recommendation when engine returns null
  /// or when there is no historical progression data yet.
  static KynoProgressionAdvice getNeutralAdvice(Exercise exercise) {
    return KynoProgressionAdvice(
      action: 'Establish baseline',
      styleLabel: 'Standard Progression',
      todayTarget:
          "Target: ${exercise.defaultTargetSets} sets • ${exercise.targetRepMin}-${exercise.targetRepMax} reps",
      summary:
          'Clean reps and a steady tempo today. Log your sets and Kyno builds your progression from there.',
      evidence: [
        'No earlier sessions logged for this one yet.',
        'Target range is ${exercise.targetRepMin}-${exercise.targetRepMax} reps.',
      ],
      nextMilestone:
          'Finish ${exercise.defaultTargetSets} working sets with 1-2 reps left in the tank to unlock your first bump.',
      confidence: 'Baseline',
      isDeload: false,
      spark1RmTrend: const [],
    );
  }

  @override
  State<KynoStageSlot> createState() => _KynoStageSlotState();
}

class _KynoStageSlotState extends State<KynoStageSlot> {
  bool _progressionRevealed = false;
  bool _showWhyDetails = false;

  @override
  void initState() {
    super.initState();
    _attachController(widget.playbackController);
  }

  @override
  void didUpdateWidget(KynoStageSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playbackController != widget.playbackController) {
      _detachController(oldWidget.playbackController);
      _attachController(widget.playbackController);
    }
    if (oldWidget.exercise.id != widget.exercise.id) {
      widget.playbackController?.reset();
      setState(() {
        _progressionRevealed = false;
        _showWhyDetails = false;
      });
    }
  }

  @override
  void dispose() {
    _detachController(widget.playbackController);
    super.dispose();
  }

  void _attachController(ExerciseDemoPlaybackController? controller) {
    controller?.addListener(_onPlaybackChanged);
    if (controller != null && controller.isCompleted && !_progressionRevealed) {
      _progressionRevealed = true;
    }
  }

  void _detachController(ExerciseDemoPlaybackController? controller) {
    controller?.removeListener(_onPlaybackChanged);
  }

  void _onPlaybackChanged() {
    if (!mounted) return;
    final controller = widget.playbackController;
    if (controller != null && controller.isCompleted && !_progressionRevealed) {
      setState(() {
        _progressionRevealed = true;
      });
    }
  }

  void _onMediaTwoLoopsCompleted() {
    if (mounted && !_progressionRevealed) {
      setState(() {
        _progressionRevealed = true;
      });
    }
  }

  void _replayDemo() {
    KHaptics.select();
    widget.playbackController?.reset();
    setState(() {
      _progressionRevealed = false;
      _showWhyDetails = false;
    });
    widget.onDemoTapped?.call();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: KRadius.md,
        child: AnimatedSwitcher(
          duration: KMotion.of(context, KMotion.emphasized),
          switchInCurve: KMotion.decelerate,
          switchOutCurve: KMotion.accelerate,
          layoutBuilder: (currentChild, previousChildren) {
            return Stack(
              fit: StackFit.expand,
              children: <Widget>[...previousChildren, ?currentChild],
            );
          },
          transitionBuilder: (child, animation) {
            final isProgression =
                child.key == const ValueKey('progression_view');
            final inOffset = isProgression
                ? const Offset(0.08, 0.0)
                : const Offset(-0.08, 0.0);
            final slideAnim = Tween<Offset>(
              begin: inOffset,
              end: Offset.zero,
            ).animate(animation);

            return SlideTransition(
              position: slideAnim,
              child: FadeTransition(opacity: animation, child: child),
            );
          },
          child: _progressionRevealed
              ? KeyedSubtree(
                  key: const ValueKey('progression_view'),
                  child: _buildKynoProgressionCard(
                    widget.advice ??
                        KynoStageSlot.getNeutralAdvice(widget.exercise),
                    widget.height,
                  ),
                )
              : KeyedSubtree(
                  key: const ValueKey('demo_view'),
                  child: ExerciseMediaWidget(
                    exercise: widget.exercise,
                    height: widget.height,
                    fit: BoxFit.contain,
                    preferAnimation: true,
                    showAttribution: false,
                    interactiveZoom: false,
                    targetLoops: 2,
                    playbackController: widget.playbackController,
                    onTwoLoopsCompleted: _onMediaTwoLoopsCompleted,
                  ),
                ),
        ),
      ),
    );
  }

  // ── Progression card ─────────────────────────────────────────────────────
  // Card surface + hairline, monochrome chrome. Colour only carries meaning:
  // danger for a deload / safety call (paired with a warning icon). The two
  // control rows are fixed 48dp bands so "Demo", "Why?" and "Close" are always
  // full-size targets; only the content between them scrolls at large text.

  Widget _buildKynoProgressionCard(
    KynoProgressionAdvice advice,
    double height,
  ) {
    final isDeloadOrSafety =
        advice.isDeload ||
        advice.confidence.contains('Safety') ||
        advice.confidence.contains('Deload');
    final actionColor = isDeloadOrSafety ? KColor.danger : KColor.textPrimary;
    final dark = KColor.isDark;

    return Container(
      width: double.infinity,
      height: height,
      padding: const EdgeInsets.fromLTRB(14, 0, 4, 0),
      decoration: BoxDecoration(
        color: KColor.card,
        borderRadius: KRadius.md,
        border: Border.all(
          color: isDeloadOrSafety
              ? KColor.danger.withValues(alpha: dark ? 0.45 : 0.4)
              : (dark ? KColor.fg.withValues(alpha: 0.08) : KColor.border),
          width: 1.0,
        ),
      ),
      child: _showWhyDetails
          ? _buildExpandedWhyView(advice)
          : _buildCompactCardView(advice, actionColor, isDeloadOrSafety),
    );
  }

  Widget _buildCompactCardView(
    KynoProgressionAdvice advice,
    Color actionColor,
    bool isDeloadOrSafety,
  ) {
    final target = advice.todayTarget.startsWith("Today's target:")
        ? advice.todayTarget
        : "Today's target: ${advice.todayTarget}";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Eyebrow: Kyno mark + "Progression recommendation" + Demo replay.
        SizedBox(
          height: 48,
          child: Row(
            children: [
              if (isDeloadOrSafety)
                Icon(Icons.warning_amber_rounded, color: actionColor, size: 14)
              else
                const _KynoGlyph(),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Progression recommendation',
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: KText.caption.copyWith(
                    color: isDeloadOrSafety
                        ? actionColor
                        : KColor.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _SlotPill(
                label: 'Demo',
                semanticLabel: 'Replay exercise demo',
                leading: Icons.play_arrow_rounded,
                onTap: _replayDemo,
              ),
            ],
          ),
        ),

        // Action, style, target and summary: the only part that may scroll.
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 10),
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        _sentenceCase(advice.action),
                        style: KText.h2.copyWith(
                          color: actionColor,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      // The method, as a quiet label rather than a pill.
                      Text(
                        _sentenceCase(advice.styleLabel),
                        style: KText.caption.copyWith(
                          color: KColor.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(target, style: KText.numSmall.copyWith(fontSize: 12.5)),
                  const SizedBox(height: 4),
                  // Kyno suggests; the user decides what to lift.
                  Text(
                    advice.summary,
                    style: KText.caption.copyWith(
                      color: KColor.textSecondary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w400,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Footer: Why? + first piece of evidence + latest estimated 1RM.
        SizedBox(
          height: 48,
          child: Row(
            children: [
              _SlotPill(
                label: 'Why?',
                semanticLabel: 'Why this recommendation',
                trailing: Icons.arrow_drop_down_rounded,
                onTap: () {
                  KHaptics.select();
                  setState(() => _showWhyDetails = true);
                },
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  advice.evidence.isNotEmpty ? advice.evidence.first : '',
                  style: KText.caption.copyWith(
                    color: KColor.textMuted,
                    fontSize: 10,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (advice.spark1RmTrend.length >= 2) ...[
                const SizedBox(width: 6),
                Semantics(
                  label: 'Estimated one rep max',
                  child: Icon(
                    Icons.trending_up_rounded,
                    size: 13,
                    color: KColor.textMuted,
                  ),
                ),
                const SizedBox(width: 3),
                Text(
                  '1RM ${amount(advice.spark1RmTrend.last)} kg',
                  style: KText.numSmall.copyWith(
                    color: KColor.textSecondary,
                    fontSize: 10.5,
                  ),
                ),
                const SizedBox(width: 10),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildExpandedWhyView(KynoProgressionAdvice advice) {
    final hairline = KColor.isDark
        ? KColor.fg.withValues(alpha: 0.08)
        : KColor.border;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 48,
          child: Row(
            children: [
              Icon(
                Icons.fact_check_outlined,
                size: 14,
                color: KColor.textSecondary,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Evidence and next milestone',
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: KText.caption.copyWith(
                    color: KColor.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _SlotPill(
                label: 'Close',
                semanticLabel: 'Close evidence',
                trailing: Icons.arrow_drop_up_rounded,
                onTap: () {
                  KHaptics.select();
                  setState(() => _showWhyDetails = false);
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 10, bottom: 10),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...advice.evidence.map(
                    (ev) => Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 4,
                            height: 4,
                            margin: const EdgeInsets.only(top: 6, right: 8),
                            decoration: BoxDecoration(
                              color: KColor.textMuted,
                              shape: BoxShape.circle,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              ev,
                              style: KText.caption.copyWith(
                                color: KColor.textPrimary,
                                fontSize: 11,
                                fontWeight: FontWeight.w400,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: hairline)),
                    ),
                    child: Text(
                      'Next: ${advice.nextMilestone}',
                      style: KText.caption.copyWith(
                        color: KColor.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Kyno glyph ───────────────────────────────────────────────────────────────
// Kyno's monochrome mark from the shared icon language: marks the card as
// Kyno's voice without a stock "AI orb".

class _KynoGlyph extends StatelessWidget {
  const _KynoGlyph();

  @override
  Widget build(BuildContext context) => const KynoMark(size: 16);
}

/// Engine copy arrives in caps ("INCREASE TO 42.5 KG"); the stage speaks in
/// sentence case ("Increase to 42.5 kg"). Display only: stored advice is
/// unchanged.
String _sentenceCase(String s) {
  if (s.isEmpty) return s;
  final lower = s.toLowerCase();
  return lower[0].toUpperCase() + lower.substring(1);
}

// ─── Slot pill button ─────────────────────────────────────────────────────────
// Compact visual pill inside a 48dp hit target; the whole target speaks as a
// button. Neutral outline: the stage is chrome, not data.

class _SlotPill extends StatelessWidget {
  const _SlotPill({
    required this.label,
    required this.semanticLabel,
    required this.onTap,
    this.leading,
    this.trailing,
  });

  final String label;
  final String semanticLabel;
  final VoidCallback onTap;
  final IconData? leading;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    final fg = KColor.textPrimary;
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        borderRadius: KRadius.pill,
        scale: 0.94,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Center(
              widthFactor: 1,
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  leading != null ? 8 : 11,
                  5,
                  trailing != null ? 5 : 11,
                  5,
                ),
                decoration: BoxDecoration(
                  color: KColor.fg.withValues(
                    alpha: KColor.isDark ? 0.06 : 0.04,
                  ),
                  borderRadius: KRadius.pill,
                  border: Border.all(
                    color: KColor.fg.withValues(
                      alpha: KColor.isDark ? 0.16 : 0.16,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (leading != null) ...[
                      Icon(leading, size: 14, color: fg),
                      const SizedBox(width: 3),
                    ],
                    Text(
                      label,
                      style: KText.caption.copyWith(
                        color: fg,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    if (trailing != null) Icon(trailing, size: 16, color: fg),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
