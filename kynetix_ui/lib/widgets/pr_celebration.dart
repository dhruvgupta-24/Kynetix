import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../services/pr_classifier.dart';

// Moment declaration: live PR
//   trigger: a logged working set breaks a record (PrClassifier), never on the
//            first-ever log of an exercise
//   change:  the PR strip opens under the header naming the record type; one
//            bounded burst of 20 sparks from the strip's badge, alternating
//            the ember accent and ink (the only two colours it uses), with
//            one thin ring. Flat strokes and dots: no blur, no glow.
//   duration role: ~700 ms burst, plays once per record, strip holds 4.5 s
//   haptic:  milestone, fired once by the screen on the commit frame
//   skip:    the burst ignores input and ends on its own; strip is inline
//   reduced motion: no burst, the strip simply appears

/// Banner copy for a record, e.g. title "New record: heaviest for 8 reps",
/// detail "82.5 kg × 8, up from 80 kg. Est. 1RM 104.5 kg."
({String title, String detail}) prBannerCopy(PrResult r, {required String exerciseName}) {
  String n(double v) {
    final x = (v * 10).round() / 10;
    return x == x.roundToDouble() ? x.toInt().toString() : x.toStringAsFixed(1);
  }

  final s = r.set;
  final load = s.externalLoadKg ?? s.weight;
  final what = s.externalLoadKg != null
      ? (load > 0 ? 'BW + ${n(load)} kg × ${s.reps}' : 'BW × ${s.reps}')
      : '${n(load)} kg × ${s.reps}';

  final title = switch (r.primary) {
    PrType.e1rm => 'New best estimated 1RM',
    PrType.heaviestAtReps => 'Heaviest you\'ve gone for ${s.reps} ${s.reps == 1 ? 'rep' : 'reps'}',
    PrType.mostRepsAtWeight => 'Most reps you\'ve done at ${load > 0 ? '${n(load)} kg' : 'bodyweight'}',
    null => 'New personal record',
  };

  final parts = <String>[what];
  switch (r.primary) {
    case PrType.e1rm:
      parts.add('Est. 1RM ${n(s.estimatedOneRepMax)} kg'
          '${r.previousE1rm != null ? ', up from ${n(r.previousE1rm!)}' : ''}');
    case PrType.heaviestAtReps:
      if (r.previousWeightAtReps != null) parts.add('Up from ${n(r.previousWeightAtReps!)} kg');
    case PrType.mostRepsAtWeight:
      if (r.previousRepsAtWeight != null) parts.add('Up from ${r.previousRepsAtWeight} reps');
    case null:
      break;
  }
  final others = r.types.skip(1).map((t) => t.title.toLowerCase()).toList();
  if (others.isNotEmpty) parts.add('Also ${others.join(' and ')}');
  return (title: title, detail: '$exerciseName. ${parts.join('. ')}.');
}

/// One-shot spark burst in the accent, every other spark in ink. Plays once
/// per mount; re-key it (e.g. with a PR epoch) to play again. Paints nothing
/// once finished and nothing at all under reduced motion.
class PrBurst extends StatefulWidget {
  final Color color;

  /// Second colour for alternate sparks. Defaults to the theme ink.
  final Color? ink;
  const PrBurst({super.key, required this.color, this.ink});

  @override
  State<PrBurst> createState() => _PrBurstState();
}

class _PrBurstState extends State<PrBurst> with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 700);
  late final AnimationController _c;
  late final List<_Spark> _sparks;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: _duration);
    final rnd = math.Random();
    const count = 20;
    _sparks = List.unmodifiable(List.generate(count, (i) {
      final a = (i / count) * math.pi * 2 + rnd.nextDouble() * 0.3;
      return _Spark(
        angle: a,
        distance: 34 + rnd.nextDouble() * 40,
        size: 1.6 + rnd.nextDouble() * 1.8,
        stretch: rnd.nextBool(),
        inked: i.isOdd,
      );
    }));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!KMotion.reduced(context)) _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (KMotion.reduced(context)) return const SizedBox.shrink();
    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _BurstPainter(sparks: _sparks, progress: _c, color: widget.color, ink: widget.ink ?? KColor.ink),
            size: const Size(180, 180),
          ),
        ),
      ),
    );
  }
}

class _Spark {
  final double angle, distance, size;
  final bool stretch;
  final bool inked;
  const _Spark({required this.angle, required this.distance, required this.size, required this.stretch, required this.inked});
}

class _BurstPainter extends CustomPainter {
  _BurstPainter({required this.sparks, required this.progress, required this.color, required this.ink}) : super(repaint: progress);
  final List<_Spark> sparks;
  final Animation<double> progress;
  final Color color;
  final Color ink;
  final Paint _p = Paint()..strokeCap = StrokeCap.round;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    if (t <= 0 || t >= 1) return;
    final c = size.center(Offset.zero);
    final ease = 1 - math.pow(1 - t, 3).toDouble();
    final fade = t < 0.55 ? 1.0 : (1 - (t - 0.55) / 0.45);
    // A soft ring that expands once.
    _p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color.withValues(alpha: 0.35 * fade);
    canvas.drawCircle(c, 14 + 40 * ease, _p);
    _p.style = PaintingStyle.fill;
    // Two colours per frame, resolved once (not once per spark).
    final accentNow = color.withValues(alpha: fade);
    final inkNow = ink.withValues(alpha: fade * 0.85);
    for (final s in sparks) {
      final d = s.distance * ease;
      final pos = c + Offset(math.cos(s.angle) * d, math.sin(s.angle) * d);
      _p.color = s.inked ? inkNow : accentNow;
      if (s.stretch) {
        final tail = c + Offset(math.cos(s.angle) * d * 0.78, math.sin(s.angle) * d * 0.78);
        _p
          ..style = PaintingStyle.stroke
          ..strokeWidth = s.size * 0.8;
        canvas.drawLine(tail, pos, _p);
        _p.style = PaintingStyle.fill;
      } else {
        canvas.drawCircle(pos, s.size * (1 - 0.4 * t), _p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter old) =>
      !identical(old.sparks, sparks) || old.progress != progress || old.color != color || old.ink != ink;
}
