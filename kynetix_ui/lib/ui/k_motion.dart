import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

// ─── KMotion ──────────────────────────────────────────────────────────────────
// Motion tokens. Every duration / curve in the UI should come from here so the
// whole app moves with one rhythm, and so reduced-motion collapses everything
// in one place.

//
// Token set (pick by role, never by feel):
//
//   instant     90 ms  press acknowledgement, colour flips under a finger
//   quick      160 ms  small state flips (chips, toggles, icon swaps)
//   standard   280 ms  most transitions (cross-fades, expanders)
//   emphasized 460 ms  reveals and the dock's island morph
//   slow       720 ms  rings, charts, numbers settling
//
// Purpose-built roles: [press] (finger down), [tab] (tab fade-through),
// [page] (route push / pop). Curves: [easeOut] is the default for anything
// entering or responding; [accelerate] for things leaving. Springs
// ([pressSpring], [sheetSpring]) drive release and sheet motion.
// [overshoot] and [spring] are for celebrations only (PRs, a finished
// workout), never for routine UI.
//
// Reduced motion: wrap every duration in [KMotion.of]; it collapses to zero
// so the end state shows immediately.

abstract class KMotion {
  // ── Duration roles
  static const instant    = Duration(milliseconds: 90);   // press acknowledgment
  static const quick      = Duration(milliseconds: 160);  // small state flips
  static const standard   = Duration(milliseconds: 280);  // most transitions
  static const emphasized = Duration(milliseconds: 460);  // route / reveal
  static const slow       = Duration(milliseconds: 720);  // rings, charts
  static const celebrate  = Duration(milliseconds: 1400); // PR / finish moments
  static const ambient    = Duration(seconds: 22);        // background drift loop

  /// Finger-down squash on a pressable.
  static const press = Duration(milliseconds: 120);

  /// Tab fade-through in the app shell.
  static const tab = Duration(milliseconds: 220);

  /// Route push / pop (shared-axis slide + fade).
  static const page = Duration(milliseconds: 300);

  /// Delay between siblings in a staggered reveal.
  static const stagger = Duration(milliseconds: 55);

  // ── Curve roles
  /// Strong ease-out: instant response, long soft landing. The default for
  /// anything that enters, responds to a finger, or settles.
  static const Curve easeOut = Cubic(0.23, 1, 0.32, 1);
  /// Material 3 "emphasized" — confident start, long soft landing.
  static const Curve emphasizedCurve = Cubic(0.2, 0.0, 0.0, 1.0);
  /// Things arriving on screen.
  static const Curve decelerate = Cubic(0.05, 0.7, 0.1, 1.0);
  /// Things leaving the screen.
  static const Curve accelerate = Cubic(0.3, 0.0, 0.8, 0.15);
  /// Playful overshoot. Celebrations only (PR, workout finished); routine
  /// selections use [easeOut].
  static const Curve overshoot = Cubic(0.34, 1.56, 0.64, 1.0);
  /// Bouncy damped spring as a curve. Celebrations only, like [overshoot].
  static const Curve spring = KSpringCurve();

  // ── Springs
  /// Press release: ~350 ms response, bounce 0.15 (damping ratio 0.85), so
  /// a released card settles with a barely visible lift and no wobble.
  static const SpringDescription pressSpring =
      SpringDescription(mass: 1, stiffness: 320, damping: 30.41);

  /// Sheets and raised layers: ~450 ms response, bounce under 0.1 (damping
  /// ratio 0.92), so a sheet lands firmly without bouncing.
  static const SpringDescription sheetSpring =
      SpringDescription(mass: 1, stiffness: 195, damping: 25.69);

  /// [sheetSpring] as a curve for APIs that take a duration and a curve
  /// (AnimationStyle, implicit animations). Pair it with [sheetDuration].
  static final Curve sheetCurve = KSpringSimulationCurve(sheetSpring, sheetDuration);

  /// Time [sheetSpring] needs to settle within 0.1%.
  static const sheetDuration = Duration(milliseconds: 500);

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

/// A [SpringSimulation] from 0 to 1 sampled over [duration], as a [Curve].
/// The value is clamped to [0, 1] so layout that reads it (a sheet's
/// height fraction) never sees an overshoot.
class KSpringSimulationCurve extends Curve {
  KSpringSimulationCurve(this.spring, Duration duration)
      : _seconds = duration.inMicroseconds / Duration.microsecondsPerSecond,
        _sim = SpringSimulation(spring, 0, 1, 0) {
    // Normalise so the curve lands exactly on 1 at t = 1 (no last-frame jump
    // if the spring has not fully settled by then).
    _end = _sim.x(_seconds);
  }

  final SpringDescription spring;
  final double _seconds;
  final SpringSimulation _sim;
  late final double _end;

  @override
  double transformInternal(double t) =>
      (_sim.x(t * _seconds) / _end).clamp(0.0, 1.0);
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
