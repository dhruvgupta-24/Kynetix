import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

// ─── KMotion ──────────────────────────────────────────────────────────────────
// Motion tokens. Every duration / curve in the UI should come from here so the
// whole app moves with one rhythm, and so reduced-motion collapses everything
// in one place.

abstract class KMotion {
  // ── Duration roles
  static const instant    = Duration(milliseconds: 90);   // press acknowledgment
  static const quick      = Duration(milliseconds: 160);  // small state flips
  static const standard   = Duration(milliseconds: 280);  // most transitions
  static const emphasized = Duration(milliseconds: 460);  // route / reveal
  static const slow       = Duration(milliseconds: 720);  // rings, charts
  static const celebrate  = Duration(milliseconds: 1400); // PR / finish moments
  static const ambient    = Duration(seconds: 22);        // background drift loop

  /// Delay between siblings in a staggered reveal.
  static const stagger = Duration(milliseconds: 55);

  // ── Curve roles
  /// Material 3 "emphasized" — confident start, long soft landing.
  static const Curve emphasizedCurve = Cubic(0.2, 0.0, 0.0, 1.0);
  /// Things arriving on screen.
  static const Curve decelerate = Cubic(0.05, 0.7, 0.1, 1.0);
  /// Things leaving the screen.
  static const Curve accelerate = Cubic(0.3, 0.0, 0.8, 0.15);
  /// Small playful overshoot for selections & pops.
  static const Curve overshoot = Cubic(0.34, 1.56, 0.64, 1.0);
  /// Damped spring for rings, indicators and anything "physical".
  static const Curve spring = KSpringCurve();

  /// True when the platform asks for reduced motion.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// Resolve a duration role against the reduced-motion setting.
  static Duration of(BuildContext context, Duration d) =>
      reduced(context) ? Duration.zero : d;

  /// Whether endless / ambient loops (aurora drift, shimmer, pulses) may run.
  /// Off under reduced motion and under `flutter test`, where a never-ending
  /// ticker would make `pumpAndSettle` time out.
  static bool ambientAllowed(BuildContext context) =>
      !reduced(context) && !_isFlutterTest;

  static final bool _isFlutterTest = () {
    if (kIsWeb) return false;
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }();
}

/// A critically-under-damped spring expressed as a [Curve] so it can be used
/// anywhere a curve is accepted (implicit animations, Tweens, transitions).
class KSpringCurve extends Curve {
  const KSpringCurve({this.damping = 6.5, this.frequency = 11.0});

  final double damping;
  final double frequency;

  @override
  double transformInternal(double t) =>
      1.0 - math.exp(-damping * t) * math.cos(frequency * t);
}

// ─── KHaptics ─────────────────────────────────────────────────────────────────
// One map from *event* to intensity. Call sites name what happened, never how
// hard to buzz. `enabled` is the single central gate.

abstract class KHaptics {
  static bool enabled = true;

  /// Selection changed (tabs, chips, toggles, wheel ticks).
  static void select() {
    if (enabled) HapticFeedback.selectionClick();
  }

  /// A committing tap (log, save, add).
  static void commit() {
    if (enabled) HapticFeedback.lightImpact();
  }

  /// Something finished successfully.
  static void success() {
    if (enabled) HapticFeedback.mediumImpact();
  }

  /// Input rejected — acknowledged, never punished.
  static void reject() {
    if (enabled) HapticFeedback.lightImpact();
  }

  /// Genuine milestone only (PR, workout complete, streak).
  static void milestone() {
    if (enabled) HapticFeedback.heavyImpact();
  }
}
