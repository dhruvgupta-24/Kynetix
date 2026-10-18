import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'k_motion.dart';

// ─── KShake ───────────────────────────────────────────────────────────────────
// The out-of-range nudge: a value was rejected, so the field gives a short
// sideways "no" next to its error text. A decaying sine (stiff, barely
// damped spring), about 6 px and 400 ms, then still. Translation only, so
// nothing relayouts. Reduced motion skips the movement; the haptic and the
// error text still say it.
//
// Drive it with a GlobalKey<KShakeState> (`key.currentState?.shake()`), or
// let a Form find its own rejects: [KShake.shakeInvalid] shakes every KShake
// that wraps a field currently showing an error.

class KShake extends StatefulWidget {
  const KShake({super.key, required this.child, this.offset = 6});

  final Widget child;

  /// Peak horizontal travel in logical pixels.
  final double offset;

  /// Shake each KShake under [formContext] that wraps a FormField with an
  /// error, once each. Call it right after `FormState.validate()` failed.
  /// No haptic by default: the caller usually fires its own reject.
  static void shakeInvalid(BuildContext? formContext, {bool haptic = false}) {
    if (formContext == null) return;
    final shakes = <KShakeState>{};
    void visit(Element e) {
      if (e is StatefulElement && e.state is FormFieldState && (e.state as FormFieldState).hasError) {
        final s = e.findAncestorStateOfType<KShakeState>();
        if (s != null) shakes.add(s);
      }
      e.visitChildElements(visit);
    }
    if (formContext is Element) {
      formContext.visitChildElements(visit);
    }
    for (final s in shakes) {
      s.shake(haptic: false);
    }
    if (haptic && shakes.isNotEmpty) KHaptics.reject();
  }

  @override
  State<KShake> createState() => KShakeState();
}

class KShakeState extends State<KShake> with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 400);

  late final AnimationController _c = AnimationController(vsync: this, duration: _duration);

  /// Kick the shake. Restarts from rest if one is already running.
  void shake({bool haptic = true}) {
    if (haptic) KHaptics.reject();
    if (!mounted || KMotion.reduced(context)) return;
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) {
          final t = _c.value;
          // Three and a half swings, decaying to zero by t = 1. The envelope
          // reaches exactly 0 at the end, so there is no last-frame snap.
          final dx = t == 0 || t == 1
              ? 0.0
              : widget.offset * math.sin(t * math.pi * 7) * math.pow(1 - t, 2);
          return Transform.translate(offset: Offset(dx, 0), child: child);
        },
      );
}
