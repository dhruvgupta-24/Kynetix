import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'k_motion.dart';

// ─── KReveal ──────────────────────────────────────────────────────────────────
// Entrance animation that plays ONCE when the widget first mounts:
// fade + rise (+ optional scale). Staggering is expressed as an [index]; the
// delay lives inside a single AnimationController (via Interval), so there
// are no Timers, which keeps it safe for widget tests and hot reload.
//
// Transform and opacity only: no layout work per frame. Once settled the
// opacity is 1 and no layer is pushed.
//
// [replayKey] lets one element play again for a new subject (the dashboard
// replays its tiles the first time a new day is shown) without remounting
// the child: when the key changes the entrance restarts if [enabled], or
// snaps to its end state if not.
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
    this.enabled = true,
    this.replayKey,
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

  /// Whether to play at mount, and on a [replayKey] change.
  final bool enabled;

  /// Changing it replays the entrance (when [enabled]).
  final Object? replayKey;

  @override
  State<KReveal> createState() => _KRevealState();
}

class _KRevealState extends State<KReveal> with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;
  Animation<double> _anim = kAlwaysCompleteAnimation;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.enabled) _play();
  }

  @override
  void didUpdateWidget(covariant KReveal old) {
    super.didUpdateWidget(old);
    if (old.replayKey == widget.replayKey) return;
    if (widget.enabled) {
      _play();
    } else {
      _ctrl?.value = 1.0;
    }
  }

  void _play() {
    final lead = widget.delay +
        widget.stagger * math.min(widget.index, widget.maxIndex);
    final total = lead + widget.duration;
    if (KMotion.reduced(context) || total == Duration.zero) {
      _ctrl?.value = 1.0;
      return;
    }
    final ctrl = _ctrl ??= AnimationController(vsync: this);
    ctrl.duration = total;
    final start = lead.inMicroseconds / total.inMicroseconds;
    _anim = CurvedAnimation(
      parent: ctrl,
      curve: Interval(start, 1.0, curve: widget.curve),
    );
    ctrl.forward(from: 0);
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final anim = _anim;
    // Tree shape stays identical whether or not anything is animating, so a
    // replay never remounts (and resets) the child's state.
    return FadeTransition(
      opacity: anim,
      child: AnimatedBuilder(
        animation: anim,
        child: widget.child,
        builder: (context, child) {
          // Wrapper types depend only on the widget's config, never on the
          // frame, so the tree shape is the same every frame.
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
