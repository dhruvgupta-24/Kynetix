import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PredictiveBackEvent;

import '../config/app_theme.dart';

// ─── Page transitions ─────────────────────────────────────────────────────────
// Signature navigation: a shared-axis X move. The new screen slides in 24 px
// from the trailing side while it fades up; the screen underneath drifts a
// little the other way and fades into the page colour. No zoom. 300 ms on
// KMotion.easeOut, so it answers the tap at once and lands softly. Applied
// globally through PageTransitionsTheme so every MaterialPageRoute gets it.
//
// Android predictive back: the back swipe scrubs the same transition (the
// top screen slides back toward the trailing edge and fades, the screen
// underneath returns) and commits or cancels with the gesture. The system
// only sends those events when the manifest's <application> sets
// android:enableOnBackInvokedCallback="true"; without it back still pops,
// just without the preview.
//
// iOS and macOS keep the native Cupertino slide and its edge swipe-back.

const kPageTransitions = PageTransitionsTheme(
  builders: {
    TargetPlatform.android: KSharedAxisPageTransitionsBuilder(),
    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.windows: KSharedAxisPageTransitionsBuilder(),
    TargetPlatform.linux: KSharedAxisPageTransitionsBuilder(),
    TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
  },
);

/// Reduced motion as the platform reports it, for the places that need a
/// duration before any BuildContext exists (route durations).
bool get _platformReducedMotion {
  final f = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
  return f.disableAnimations || f.reduceMotion;
}

/// Shared-axis X page transition with predictive back support.
class KSharedAxisPageTransitionsBuilder extends PageTransitionsBuilder {
  const KSharedAxisPageTransitionsBuilder();

  /// Travel of the incoming screen, in logical pixels.
  static const double shift = 24;

  @override
  Duration get transitionDuration =>
      _platformReducedMotion ? Duration.zero : KMotion.page;

  @override
  Duration get reverseTransitionDuration => _platformReducedMotion
      ? Duration.zero
      : KMotion.page - const Duration(milliseconds: 40);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (KMotion.reduced(context)) return child;
    return _KBackGestureDetector(
      route: route,
      child: KSharedAxisTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        // While a finger drives the route, follow it linearly; curves would
        // make the screen lag, then jump, under the thumb.
        linear: route.popGestureInProgress,
        child: child,
      ),
    );
  }
}

/// The shared-axis X move on its own, for custom routes.
///
/// [animation] brings this screen in (slide from +[shift] px, fade up);
/// [secondaryAnimation] moves it out of the way when another screen covers
/// it (drift to -[shift]/2 px and fade into the page colour, which stays
/// opaque behind it, so the backdrop never shows through mid-transition).
class KSharedAxisTransition extends StatelessWidget {
  const KSharedAxisTransition({
    super.key,
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
    this.linear = false,
    this.shift = KSharedAxisPageTransitionsBuilder.shift,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;
  final bool linear;
  final double shift;

  // Incoming: most of the fade in the first 60%, so the new screen reads
  // almost at once; the slide uses the whole duration.
  static const _inFade = Interval(0, 0.6, curve: KMotion.easeOut);
  // Outgoing: gone by halfway, so two screens never read as a double
  // exposure.
  static const _outFade = Interval(0, 0.5, curve: KMotion.easeOut);

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final dir = rtl ? -1.0 : 1.0;
    final Curve slide = linear ? Curves.linear : KMotion.easeOut;
    final Curve inFade = linear ? Curves.linear : _inFade;
    final Curve outFade = linear ? Curves.linear : _outFade;

    final inOpacity = animation.drive(CurveTween(curve: inFade));
    final inShift = animation.drive(
      Tween(begin: shift * dir, end: 0.0).chain(CurveTween(curve: slide)),
    );
    final outOpacity = secondaryAnimation.drive(
      Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: outFade)),
    );
    final outShift = secondaryAnimation.drive(
      Tween(begin: 0.0, end: -shift / 2 * dir).chain(CurveTween(curve: slide)),
    );

    // Outer: this screen as the one being covered. Inner: as the one coming
    // in. Only opacity and translation change per frame; the page itself is
    // a cached layer (routes wrap pages in a RepaintBoundary).
    return ColoredBox(
      color: KColor.bg,
      child: _ShiftX(
        dx: outShift,
        child: FadeTransition(
          opacity: outOpacity,
          child: _ShiftX(
            dx: inShift,
            child: FadeTransition(opacity: inOpacity, child: child),
          ),
        ),
      ),
    );
  }
}

/// Translates [child] horizontally by [dx] logical pixels without rebuilding
/// it: only this tiny widget rebuilds per frame.
class _ShiftX extends AnimatedWidget {
  const _ShiftX({required Animation<double> dx, required this.child})
    : super(listenable: dx);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final v = (listenable as Animation<double>).value;
    return Transform.translate(offset: Offset(v, 0), child: child);
  }
}

/// Feeds Android predictive back events into [route], so the back swipe
/// scrubs the page transition. Mirrors the framework's own detector in
/// PredictiveBackPageTransitionsBuilder, without imposing its visuals.
class _KBackGestureDetector extends StatefulWidget {
  const _KBackGestureDetector({required this.route, required this.child});

  final PageRoute<dynamic> route;
  final Widget child;

  @override
  State<_KBackGestureDetector> createState() => _KBackGestureDetectorState();
}

class _KBackGestureDetectorState extends State<_KBackGestureDetector>
    with WidgetsBindingObserver {
  bool _active = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    final route = widget.route;
    if (backEvent.isButtonEvent ||
        !route.isCurrent ||
        !route.popGestureEnabled) {
      return false;
    }
    _active = true;
    route.handleStartBackGesture(progress: 1 - backEvent.progress);
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    if (!_active) return;
    widget.route.handleUpdateBackGestureProgress(
      progress: 1 - backEvent.progress,
    );
  }

  @override
  void handleCancelBackGesture() {
    if (!_active) return;
    _active = false;
    widget.route.handleCancelBackGesture();
  }

  @override
  void handleCommitBackGesture() {
    if (!_active) return;
    _active = false;
    widget.route.handleCommitBackGesture();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Route for screens that behave like a raised layer (composer, editors,
/// full-screen pickers): rises from the bottom with a soft fade.
PageRoute<T> kRiseRoute<T>({
  required WidgetBuilder builder,
  bool fullscreenDialog = false,
}) {
  final reduced = _platformReducedMotion;
  return PageRouteBuilder<T>(
    fullscreenDialog: fullscreenDialog,
    opaque: true,
    pageBuilder: (ctx, anim, sec) => builder(ctx),
    transitionDuration: reduced ? Duration.zero : KMotion.sheetDuration,
    reverseTransitionDuration: reduced
        ? Duration.zero
        : KMotion.page - const Duration(milliseconds: 40),
    transitionsBuilder: (ctx, anim, sec, child) {
      if (KMotion.reduced(ctx)) return child;
      final rise = anim.drive(
        Tween(begin: const Offset(0, 0.08), end: Offset.zero).chain(
          CurveTween(
            curve: _Directional(KMotion.sheetCurve, KMotion.accelerate, anim),
          ),
        ),
      );
      return FadeTransition(
        opacity: anim.drive(
          CurveTween(curve: const Interval(0, 0.5, curve: KMotion.easeOut)),
        ),
        child: SlideTransition(position: rise, child: child),
      );
    },
  );
}

/// Uses [forward] while [animation] runs forward and [reverse] on the way
/// back, without registering a status listener per build (unlike
/// CurvedAnimation).
class _Directional extends Curve {
  const _Directional(this.forward, this.reverse, this.animation);
  final Curve forward;
  final Curve reverse;
  final Animation<double> animation;

  @override
  double transform(double t) => animation.status == AnimationStatus.reverse
      ? reverse.transform(t)
      : forward.transform(t);
}

/// Route that fades through (no spatial relationship): auth to app, etc.
PageRoute<T> kFadeThroughRoute<T>({required WidgetBuilder builder}) {
  final reduced = _platformReducedMotion;
  return PageRouteBuilder<T>(
    pageBuilder: (ctx, anim, sec) => builder(ctx),
    transitionDuration: reduced
        ? Duration.zero
        : KMotion.page + const Duration(milliseconds: 60),
    reverseTransitionDuration: reduced
        ? Duration.zero
        : KMotion.page - const Duration(milliseconds: 40),
    transitionsBuilder: (ctx, anim, sec, child) {
      if (KMotion.reduced(ctx)) return child;
      return FadeThroughTransition(
        animation: anim,
        secondaryAnimation: sec,
        fillColor: KColor.bg,
        child: child,
      );
    },
  );
}
