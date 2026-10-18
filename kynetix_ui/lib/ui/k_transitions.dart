import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import '../config/app_theme.dart';

// ─── Page transitions ─────────────────────────────────────────────────────────
// Signature navigation: Material shared-axis Z ("scaled") — the new screen
// grows in from slightly behind while the old one recedes. Applied globally
// through PageTransitionsTheme so every MaterialPageRoute gets it for free.

const kPageTransitions = PageTransitionsTheme(
  builders: {
    TargetPlatform.android: _KScaledAxisBuilder(),
    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.windows: _KScaledAxisBuilder(),
    TargetPlatform.linux: _KScaledAxisBuilder(),
    TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
  },
);

class _KScaledAxisBuilder extends PageTransitionsBuilder {
  const _KScaledAxisBuilder();

  @override
  Duration get transitionDuration => KMotion.emphasized;

  @override
  Duration get reverseTransitionDuration => KMotion.standard + const Duration(milliseconds: 60);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (KMotion.reduced(context)) {
      return FadeTransition(opacity: animation, child: child);
    }
    return SharedAxisTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      transitionType: SharedAxisTransitionType.scaled,
      fillColor: KColor.bg,
      child: child,
    );
  }
}

/// Route for screens that behave like a raised layer (composer, editors,
/// full-screen pickers): rises from the bottom with a soft fade.
PageRoute<T> kRiseRoute<T>({required WidgetBuilder builder, bool fullscreenDialog = false}) {
  return PageRouteBuilder<T>(
    fullscreenDialog: fullscreenDialog,
    opaque: true,
    pageBuilder: (ctx, anim, sec) => builder(ctx),
    transitionDuration: KMotion.emphasized,
    reverseTransitionDuration: KMotion.standard,
    transitionsBuilder: (ctx, anim, sec, child) {
      if (KMotion.reduced(ctx)) return FadeTransition(opacity: anim, child: child);
      final curved = CurvedAnimation(
        parent: anim,
        curve: KMotion.emphasizedCurve,
        reverseCurve: KMotion.accelerate,
      );
      return FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: const Interval(0, 0.6)),
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.12), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Route that fades through (no spatial relationship) — auth → app, etc.
PageRoute<T> kFadeThroughRoute<T>({required WidgetBuilder builder}) {
  return PageRouteBuilder<T>(
    pageBuilder: (ctx, anim, sec) => builder(ctx),
    transitionDuration: KMotion.slow,
    reverseTransitionDuration: KMotion.standard,
    transitionsBuilder: (ctx, anim, sec, child) => FadeThroughTransition(
      animation: anim,
      secondaryAnimation: sec,
      fillColor: KColor.bg,
      child: child,
    ),
  );
}
