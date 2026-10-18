import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../ui/k_motion.dart';

/// Three dots that breathe in turn: opacity only, no bounce, no glow.
///
/// One controller drives a painter directly (no rebuilds per frame) on its
/// own layer. The loop runs only while ambient motion is allowed (not under
/// reduced motion or in tests) and pauses with TickerMode when offstage;
/// otherwise the dots sit still at a calm middle opacity.
class KTypingDots extends StatefulWidget {
  const KTypingDots({super.key, required this.color, this.dot = 6, this.gap = 5});

  final Color color;
  final double dot;
  final double gap;

  /// One full cycle: slow enough to read as waiting, not as alarm.
  static const Duration period = Duration(milliseconds: 1200);

  @override
  State<KTypingDots> createState() => _KTypingDotsState();
}

class _KTypingDotsState extends State<KTypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(vsync: this, duration: KTypingDots.period);
  bool _running = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final allowed = KMotion.ambientAllowed(context);
    if (allowed && !_running) {
      _running = true;
      _ctrl.repeat();
    } else if (!allowed && _running) {
      _running = false;
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.dot * 3 + widget.gap * 2;
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size(w, widget.dot),
          painter: _DotsPainter(_ctrl, widget.color, widget.dot, widget.gap, _running),
        ),
      ),
    );
  }
}

class _DotsPainter extends CustomPainter {
  _DotsPainter(this.t, this.color, this.dot, this.gap, this.running) : super(repaint: t);
  final Animation<double> t;
  final Color color;
  final double dot;
  final double gap;
  final bool running;

  @override
  void paint(Canvas canvas, Size size) {
    final r = dot / 2;
    final paint = Paint();
    for (var i = 0; i < 3; i++) {
      // Each dot a third of a beat behind the last; a cosine, so the
      // brightening and dimming are equally soft.
      final double o;
      if (running) {
        final phase = (t.value - i / 3) % 1.0;
        o = 0.28 + 0.62 * (0.5 - 0.5 * math.cos(2 * math.pi * phase));
      } else {
        o = 0.55;
      }
      paint.color = color.withValues(alpha: color.a * o);
      canvas.drawCircle(Offset(r + i * (dot + gap), size.height / 2), r, paint);
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) =>
      old.t != t || old.color != color || old.dot != dot || old.gap != gap || old.running != running;
}
