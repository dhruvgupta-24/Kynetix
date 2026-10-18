import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import 'kyno_avatar.dart';

/// Kyno's mark ([KynoMark]: an ink disc with a lowercase "k") that breathes
/// while Kyno is working. The breath is a slow opacity swell that only runs
/// when ambient motion is allowed, and it settles to full opacity the moment
/// [alive] goes false, so the end state is the same with motion off.
class KynoBreathingMark extends StatefulWidget {
  const KynoBreathingMark({super.key, this.size = 28, this.alive = false});
  final double size;
  final bool alive;

  @override
  State<KynoBreathingMark> createState() => _KynoBreathingMarkState();
}

class _KynoBreathingMarkState extends State<KynoBreathingMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath =
      AnimationController(vsync: this, duration: KMotion.celebrate, value: 1);

  void _sync() {
    final run = widget.alive && KMotion.ambientAllowed(context);
    if (run && !_breath.isAnimating) {
      _breath.repeat(reverse: true, min: 0.4, max: 1);
    } else if (!run && _breath.isAnimating) {
      _breath
        ..stop()
        ..value = 1;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant KynoBreathingMark old) {
    super.didUpdateWidget(old);
    if (old.alive != widget.alive) _sync();
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: FadeTransition(
        opacity: _breath,
        child: KynoMark(size: widget.size),
      ),
    );
  }
}

/// The small "Kyno" byline that heads each of Kyno's answers. Kyno writes on
/// the page rather than in a bubble, so the byline is what marks the speaker.
class KynoByline extends StatelessWidget {
  const KynoByline({super.key, this.thinking = false});
  final bool thinking;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        KynoAvatar(
          size: 24,
          showBody: false,
          ambient: thinking,
          mood: thinking ? KynoMood.thinking : KynoMood.idle,
        ),
        const SizedBox(width: KSpacing.sm),
        Text(
          'Kyno',
          style: KText.caption.copyWith(
            color: KColor.kyno,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
