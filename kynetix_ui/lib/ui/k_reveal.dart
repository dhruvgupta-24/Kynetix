import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'k_motion.dart';

// ─── KReveal ──────────────────────────────────────────────────────────────────
// Entrance animation that plays ONCE when the widget first mounts:
// fade + rise (+ optional scale/blur-free soften). Staggering is expressed as an
// [index]; the delay lives inside a single AnimationController (via Interval),
// so there are no Timers — safe for widget tests and hot reload.
//
// Motion decorates state, never is it: the child is always in the tree, always
// hit-testable, and under reduced motion it simply appears at its end state.

class KReveal extends StatefulWidget {
  const KReveal({
    super.key,
    required this.child,
    this.index = 0,
    this.delay = Duration.zero,
    this.duration = KMotion.emphasized,
    this.stagger = KMotion.stagger,
    this.rise = 18,
    this.slideX = 0,
    this.fromScale = 1.0,
    this.maxIndex = 10,
    this.curve = KMotion.decelerate,
  });

  final Widget child;

  /// Position in a staggered group. Capped by [maxIndex] so long lists don't
  /// make the last item wait forever.
  final int index;
  final Duration delay;
  final Duration duration;
  final Duration stagger;

  /// Vertical travel in logical pixels (positive = comes up from below).
  final double rise;

  /// Horizontal travel in logical pixels.
  final double slideX;

  /// Starting scale (1.0 = no scale).
  final double fromScale;
  final int maxIndex;
  final Curve curve;

  @override
  State<KReveal> createState() => _KRevealState();
}

class _KRevealState extends State<KReveal> with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;
  Animation<double>? _anim;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    final lead = widget.delay +
        widget.stagger * math.min(widget.index, widget.maxIndex);
    final total = lead + widget.duration;

    if (KMotion.reduced(context) || total == Duration.zero) return;

    final ctrl = AnimationController(vsync: this, duration: total);
    final start = lead.inMicroseconds / total.inMicroseconds;
    _anim = CurvedAnimation(
      parent: ctrl,
      curve: Interval(start, 1.0, curve: widget.curve),
    );
    _ctrl = ctrl..forward();
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final anim = _anim;
    if (anim == null) return widget.child;

    return FadeTransition(
      opacity: anim,
      child: AnimatedBuilder(
        animation: anim,
        child: widget.child,
        builder: (context, child) {
          // Tree shape must stay identical every frame — swapping wrapper
          // types would remount (and reset) the child's state.
          final v = anim.value;
          final inv = 1.0 - v;
          Widget out = child!;
          if (widget.fromScale != 1.0) {
            out = Transform.scale(
              scale: widget.fromScale + (1.0 - widget.fromScale) * v,
              child: out,
            );
          }
          return Transform.translate(
            offset: Offset(widget.slideX * inv, widget.rise * inv),
            child: out,
          );
        },
      ),
    );
  }
}

/// Convenience: wraps each child in a [KReveal] with an increasing index.
List<Widget> kStagger(
  List<Widget> children, {
  Duration delay = Duration.zero,
  Duration stagger = KMotion.stagger,
  double rise = 18,
  double fromScale = 1.0,
}) {
  return [
    for (var i = 0; i < children.length; i++)
      KReveal(
        index: i,
        delay: delay,
        stagger: stagger,
        rise: rise,
        fromScale: fromScale,
        child: children[i],
      ),
  ];
}
