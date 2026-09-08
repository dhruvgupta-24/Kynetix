import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../models/workout_split.dart';
import '../services/kyno_progression_engine.dart';
import 'exercise_media_widget.dart';

/// Single bounded Kyno Stage (~195px slot).
///
/// Houses the GymVisual demonstration GIF and the precomputed
/// Kyno Progression Recommendation in the exact same slot.
/// Switches smoothly via [AnimatedSwitcher] (600ms) after exactly
/// 2 animation loops, with zero loading delay. A `[Demo]` button
/// allows replaying the demonstration anytime.
class KynoStageSlot extends StatefulWidget {
  final Exercise exercise;
  final KynoProgressionAdvice advice;
  final double height;
  final VoidCallback? onDemoTapped;
  final ExerciseDemoPlaybackController? playbackController;

  const KynoStageSlot({
    super.key,
    required this.exercise,
    required this.advice,
    this.height = 195.0,
    this.onDemoTapped,
    this.playbackController,
  });

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
        borderRadius: BorderRadius.circular(16),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 600),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (currentChild, previousChildren) {
            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                ...previousChildren,
                ?currentChild,
              ],
            );
          },
          transitionBuilder: (child, animation) {
            final isProgression = child.key == const ValueKey('progression_view');
            final inOffset = isProgression
                ? const Offset(0.12, 0.0)
                : const Offset(-0.12, 0.0);
            final slideAnim = Tween<Offset>(
              begin: inOffset,
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));

            return SlideTransition(
              position: slideAnim,
              child: FadeTransition(
                opacity: animation,
                child: child,
              ),
            );
          },
          child: _progressionRevealed
              ? KeyedSubtree(
                  key: const ValueKey('progression_view'),
                  child: _buildKynoProgressionCard(widget.advice, widget.height),
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

  Widget _buildKynoProgressionCard(KynoProgressionAdvice advice, double height) {
    final isDeloadOrSafety = advice.isDeload ||
        advice.confidence.contains('Safety') ||
        advice.confidence.contains('Deload');
    final cardColor = isDeloadOrSafety
        ? KColor.danger.withValues(alpha: 0.08)
        : const Color(0xFF13131F);
    final borderColor = isDeloadOrSafety
        ? KColor.danger.withValues(alpha: 0.35)
        : const Color(0xFFFFB347).withValues(alpha: 0.3);
    final actionColor = isDeloadOrSafety ? KColor.danger : const Color(0xFFFFB347);

    return Container(
      width: double.infinity,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.0),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Eyebrow Row: PROGRESSION RECOMMENDATION + Replay Demo Button
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  isDeloadOrSafety
                      ? Icons.warning_amber_rounded
                      : Icons.offline_bolt_rounded,
                  color: actionColor,
                  size: 13,
                ),
                const SizedBox(width: 4),
                Text(
                  'PROGRESSION RECOMMENDATION',
                  style: TextStyle(
                    color: actionColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
            GestureDetector(
              onTap: _replayDemo,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white12, width: 0.5),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.play_arrow_rounded, size: 12, color: Colors.white70),
                    SizedBox(width: 2),
                    Text(
                      'Demo',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 8.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),

        // Action + Style Badge Row (No ellipsis on action)
        Row(
          children: [
            Expanded(
              child: Text(
                advice.action,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: actionColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                advice.styleLabel.toUpperCase(),
                style: TextStyle(
                  color: actionColor,
                  fontSize: 8.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),

        // Today's Target
        Text(
          advice.todayTarget.startsWith("Today's target:")
              ? advice.todayTarget
              : "Today's target: ${advice.todayTarget}",
          style: const TextStyle(
            color: Color(0xFF60A5FA),
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),

        // Recommendation Summary (Strictly non-truncated, complete instruction)
        Text(
          advice.summary,
          style: const TextStyle(
            color: Color(0xFFE5E7EB),
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            height: 1.25,
          ),
        ),

        // Footer Row: Why Button + Evidence preview + 1RM indicator
        Row(
          children: [
            GestureDetector(
              onTap: () => setState(() => _showWhyDetails = true),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2C),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: KColor.border, width: 0.5),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Why?',
                      style: TextStyle(
                        color: KColor.green,
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(width: 2),
                    Icon(Icons.arrow_drop_down_rounded, color: KColor.green, size: 16),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                advice.evidence.isNotEmpty ? advice.evidence.first : '',
                style: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (advice.spark1RmTrend.length >= 2) ...[
              const SizedBox(width: 6),
              const Icon(Icons.trending_up_rounded, size: 12, color: KColor.green),
              const SizedBox(width: 3),
              Text(
                '1RM: ${advice.spark1RmTrend.last.toStringAsFixed(1)} kg',
                style: const TextStyle(
                  color: KColor.green,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildExpandedWhyView(KynoProgressionAdvice advice) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.psychology_rounded, size: 14, color: KColor.green),
            const SizedBox(width: 6),
            const Text(
              'EVIDENCE & NEXT MILESTONE',
              style: TextStyle(
                color: KColor.textMuted,
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => setState(() => _showWhyDetails = false),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2C),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Close',
                      style: TextStyle(
                        color: KColor.green,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(width: 2),
                    Icon(Icons.arrow_drop_up_rounded, color: KColor.green, size: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...advice.evidence.map((ev) => Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '• ',
                            style: TextStyle(
                              color: Color(0xFFFFB347),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              ev,
                              style: const TextStyle(
                                color: Color(0xFFE5E7EB),
                                fontSize: 10.5,
                                height: 1.22,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E2C).withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFFFFB347).withValues(alpha: 0.25),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    'NEXT: ${advice.nextMilestone}',
                    style: const TextStyle(
                      color: Color(0xFFFFB347),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
