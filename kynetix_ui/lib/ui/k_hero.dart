import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/app_theme.dart';

// ─── World tone in scope ──────────────────────────────────────────────────────
// Each tab (and each KPage) says which world it belongs to, so shared pieces
// like the primary button can wear that world's colour without being told.

class KToneScope extends InheritedWidget {
  const KToneScope({super.key, required this.tone, required super.child});
  final KTone tone;

  static KTone of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<KToneScope>()?.tone ?? KTone.neutral;

  @override
  bool updateShouldNotify(KToneScope old) => old.tone != tone;
}

// ─── Hero surface ─────────────────────────────────────────────────────────────
// The one rich surface per world: a deep jewel ground (the same in both
// themes, like a premium card) lit by two coloured lamps. Gradients only, no
// blur, so it costs nothing while scrolling. Content on it uses [KHeroInk].

abstract final class KHeroInk {
  static Color get primary => KColor.textPrimary;
  static Color get secondary => KColor.textSecondary;
  static Color get muted => KColor.textMuted;
  static Color get track => KColor.track;
  static Color get rule => KColor.divider;
}

/// A world's lead card. Graphite keeps it flat: the card surface, a
/// hairline, and the bigger radius that marks it as the page's anchor. The
/// tone is accepted so call sites can say which world they belong to.
class KHeroSurface extends StatelessWidget {
  const KHeroSurface({
    super.key,
    required this.tone,
    required this.child,
    this.padding = const EdgeInsets.all(KSpacing.xl),
    this.radius = KRadius.xl,
  });

  final KTone tone;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: KColor.card,
        borderRadius: radius,
        border: Border.all(color: KColor.hairline),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

// ─── Dabba rings ──────────────────────────────────────────────────────────────
// Concentric rings like the round tins of a masala dabba: calories (mirchi),
// protein (elaichi). Each sweeps from 12
// o'clock with a two-tone gradient and eases to its value.

class KRingSpec {
  const KRingSpec(this.progress, this.colors);
  final double progress;
  final List<Color> colors;
}

abstract final class KRingColors {
  static List<Color> get calories => [KColor.ember, KColor.ember];
  static List<Color> get over => [KColor.danger, KColor.danger];
  static List<Color> get protein => [KColor.green, KColor.green];
}

class KDabbaRings extends StatelessWidget {
  const KDabbaRings({super.key, required this.rings, this.size = 128, this.stroke = 11, Color? track, this.child}) : _track = track;

  final List<KRingSpec> rings;
  final double size;
  final double stroke;
  final Color? _track;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final d = KMotion.of(context, KMotion.slow);
    return SizedBox.square(
      dimension: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: d,
        curve: KMotion.emphasizedCurve,
        builder: (context, t, c) => CustomPaint(
          painter: _RingsPainter(rings, stroke, _track ?? KColor.track, t),
          child: c,
        ),
        child: child == null ? null : Center(child: child),
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter(this.rings, this.stroke, this.track, this.t);
  final List<KRingSpec> rings;
  final double stroke;
  final Color track;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final gap = stroke * 0.38;
    for (var i = 0; i < rings.length; i++) {
      final ring = rings[i];
      final radius = size.shortestSide / 2 - stroke / 2 - i * (stroke + gap);
      if (radius <= stroke) break;
      canvas.drawCircle(
        c,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = track,
      );
      final p = (ring.progress.clamp(0.0, 1.0)) * t;
      if (p <= 0) continue;
      final sweep = math.max(p * 2 * math.pi, 0.08);
      final rect = Rect.fromCircle(center: c, radius: radius);
      final shader = SweepGradient(
        startAngle: 0,
        endAngle: math.max(sweep, 0.3),
        colors: ring.colors,
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect);
      canvas.drawArc(
        rect,
        -math.pi / 2,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = sweep >= 2 * math.pi ? StrokeCap.butt : StrokeCap.round
          ..shader = shader,
      );
      // The sweep gradient wraps at 12 o'clock, so the round start cap would
      // pick up the end colour; paint it in the start colour instead.
      if (sweep < 2 * math.pi) {
        canvas.drawCircle(c + Offset(0, -radius), stroke / 2, Paint()..color = ring.colors.first);
      }
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.t != t || old.rings != rings || old.stroke != stroke;
}
