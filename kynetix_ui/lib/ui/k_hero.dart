import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
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
// The lead card per world. Content on it uses [KHeroInk], which maps to the
// regular text tokens now that the hero is a plain card.

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
// protein (elaichi). Each sweeps from 12 o'clock in one flat colour and
// eases to its value.

class KRingSpec {
  const KRingSpec(this.progress, this.colors);
  final double progress;
  final List<Color> colors;
}

abstract final class KRingColors {
  // Calories wear the accent, protein its own green. Going over is drawn as a
  // second lap by the painter, never as a new colour.
  static List<Color> get calories => [KColor.ember, KColor.ember];
  static List<Color> get over => [KColor.ember, KColor.ember];
  static List<Color> get protein => [KColor.protein, KColor.protein];
}

class KDabbaRings extends StatefulWidget {
  const KDabbaRings({
    super.key,
    required this.rings,
    this.size = 128,
    this.stroke = 11,
    Color? track,
    this.child,
    this.sweepIn = true,
    this.duration,
    this.curve,
  }) : _track = track;

  final List<KRingSpec> rings;
  final double size;
  final double stroke;
  final Color? _track;
  final Widget? child;

  /// Sweep up from empty the first time it shows. Off for a copy that is
  /// arriving already drawn (the far end of a Hero flight).
  final bool sweepIn;

  /// How long a change takes to ease in. Defaults to [KMotion.slow].
  final Duration? duration;

  /// The easing for a change. Defaults to [KMotion.emphasizedCurve]. Read
  /// once, when the rings first show.
  final Curve? curve;

  /// The same rings, already drawn: what a Hero flight carries, so the
  /// shuttle never replays the sweep mid-air.
  KDabbaRings settled() => KDabbaRings(
        rings: rings,
        size: size,
        stroke: stroke,
        track: _track,
        sweepIn: false,
        duration: duration,
        curve: curve,
        child: child,
      );

  /// Flight shuttle for a Hero whose child is a [KDabbaRings]: flies the
  /// rings of the screen being opened (or left), settled, on a transparent
  /// Material so the centre text keeps its style in the overlay. Rings and
  /// centre move as one piece, so nothing inside jumps.
  static Widget heroShuttle(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    final hero = (direction == HeroFlightDirection.push ? toHeroContext : fromHeroContext).widget as Hero;
    final child = hero.child;
    return Material(
      type: MaterialType.transparency,
      child: child is KDabbaRings ? child.settled() : child,
    );
  }

  @override
  State<KDabbaRings> createState() => _KDabbaRingsState();
}

class _KDabbaRingsState extends State<KDabbaRings> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(vsync: this);
  late final CurvedAnimation _curve = CurvedAnimation(parent: _ctrl, curve: widget.curve ?? KMotion.emphasizedCurve);

  // Each ring eases from where it was drawn to where it should be.
  List<double> _from = const [];
  List<double> _to = const [];
  bool _started = false;

  static List<double> _progressOf(List<KRingSpec> rings) => [
        for (final r in rings) r.progress.isFinite ? r.progress : 0.0,
      ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _to = _progressOf(widget.rings);
    final d = KMotion.of(context, widget.duration ?? KMotion.slow);
    if (!widget.sweepIn || d == Duration.zero) {
      _from = _to;
      _ctrl.value = 1;
      return;
    }
    _from = List.filled(_to.length, 0.0);
    _ctrl
      ..duration = d
      ..forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant KDabbaRings old) {
    super.didUpdateWidget(old);
    final next = _progressOf(widget.rings);
    if (listEquals(next, _to)) return;
    // Start from what is on screen right now, so a change mid-sweep
    // carries on smoothly instead of restarting from empty.
    final now = _current();
    _from = [for (var i = 0; i < next.length; i++) i < now.length ? now[i] : 0.0];
    _to = next;
    final d = KMotion.of(context, widget.duration ?? KMotion.slow);
    if (d == Duration.zero) {
      _from = _to;
      _ctrl.value = 1;
    } else {
      _ctrl
        ..duration = d
        ..forward(from: 0);
    }
  }

  List<double> _current() {
    final t = _curve.value;
    return [
      for (var i = 0; i < _to.length; i++)
        (i < _from.length ? _from[i] : 0.0) + (_to[i] - (i < _from.length ? _from[i] : 0.0)) * t,
    ];
  }

  @override
  void dispose() {
    _curve.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    // Own layer, and the painter listens to the animation itself: the sweep
    // repaints the rings only, with no widget rebuilds per frame.
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: CustomPaint(
          painter: _RingsPainter(
            colors: [for (final r in widget.rings) r.colors.first],
            from: _from,
            to: _to,
            t: _curve,
            stroke: widget.stroke,
            track: widget._track ?? KColor.track,
            lapColor: KColor.ink,
            lapOnInk: KColor.bg,
          ),
          child: child == null ? null : Center(child: child),
        ),
      ),
    );
  }
}

/// Flat rings, outside in. Each inner ring is a touch thinner, so the two
/// read apart by shape as well as colour. Going past 100% draws a second
/// lap in ink over the full ring instead of changing colour. On a ring that
/// is already ink (protein), the lap is cut in base colour so it still shows.
class _RingsPainter extends CustomPainter {
  _RingsPainter({
    required this.colors,
    required this.from,
    required this.to,
    required this.t,
    required this.stroke,
    required this.track,
    required this.lapColor,
    required this.lapOnInk,
  }) : super(repaint: t);
  final List<Color> colors;
  final List<double> from;
  final List<double> to;
  final Animation<double> t;
  final double stroke;
  final Color track;
  final Color lapColor;
  final Color lapOnInk;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final gap = stroke * 0.42;
    final k = t.value;
    var outer = size.shortestSide / 2;
    final base = Paint()..style = PaintingStyle.stroke;
    for (var i = 0; i < colors.length; i++) {
      final w = stroke * (i == 0 ? 1.0 : 0.78);
      final radius = outer - w / 2;
      outer = radius - w / 2 - gap;
      if (radius <= w) break;
      base
        ..strokeWidth = w
        ..strokeCap = StrokeCap.butt
        ..color = track;
      canvas.drawCircle(c, radius, base);
      final a = i < from.length ? from[i] : 0.0;
      final b = i < to.length ? to[i] : 0.0;
      final raw = a + (b - a) * k;
      final p = raw.clamp(0.0, 1.0);
      if (p <= 0) continue;
      final rect = Rect.fromCircle(center: c, radius: radius);
      final full = p >= 1;
      final sweep = full ? 2 * math.pi : math.max(p * 2 * math.pi, 0.08);
      base
        ..strokeCap = full ? StrokeCap.butt : StrokeCap.round
        ..color = colors[i];
      canvas.drawArc(rect, -math.pi / 2, sweep, false, base);
      // Over target: the extra share as a lap on top, in ink, so "over"
      // reads without a new colour. An ink ring gets a base-coloured lap.
      final lap = colors[i] == lapColor ? lapOnInk : lapColor;
      final extra = (raw - 1).clamp(0.0, 1.0);
      if (extra > 0) {
        base
          ..strokeWidth = w * 0.42
          ..strokeCap = StrokeCap.round
          ..color = lap.withValues(alpha: 0.85);
        canvas.drawArc(rect, -math.pi / 2, math.max(extra * 2 * math.pi, 0.08), false, base);
      }
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) =>
      old.t != t ||
      old.stroke != stroke ||
      old.track != track ||
      old.lapColor != lapColor ||
      old.lapOnInk != lapOnInk ||
      !listEquals(old.colors, colors) ||
      !listEquals(old.from, from) ||
      !listEquals(old.to, to);
}
