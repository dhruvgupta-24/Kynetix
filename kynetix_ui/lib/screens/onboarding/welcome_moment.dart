import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import 'scene_backdrop.dart';

/// The payoff at the end of onboarding: "You're all set, [name]."
///
/// Moment: celebration (bounded). Trigger: onboarding fully finished (profile
/// saved, optional ChatGPT step done or skipped). Change: the scene fades up,
/// the line rises in, a hairline fills to show it moves on by itself, then
/// the photo and copy fade away to the plain page so the app can fade in
/// behind it (a fade-through). Plays once, never loops, and a tap anywhere
/// skips straight to the app. Haptic: one success on the first frame.
/// Reduced motion: everything is static and in place; it still moves on by
/// itself after the same dwell, or on tap.
class WelcomeMoment extends StatefulWidget {
  const WelcomeMoment({super.key, required this.name, required this.onDone});

  /// The user's name as entered; only the first word is shown.
  final String name;

  /// Called exactly once, when the moment ends or is skipped.
  final VoidCallback onDone;

  static const total = Duration(milliseconds: 2900);

  @override
  State<WelcomeMoment> createState() => _WelcomeMomentState();
}

class _WelcomeMomentState extends State<WelcomeMoment>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: WelcomeMoment.total)
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) _finish();
        });
  bool _done = false;

  @override
  void initState() {
    super.initState();
    KHaptics.success();
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _finish() {
    if (_done) return;
    _done = true;
    _c.stop();
    widget.onDone();
  }

  String get _line {
    final first = widget.name.trim().split(RegExp(r'\s+')).first;
    return first.isEmpty ? "You're all set." : "You're all set, $first.";
  }

  @override
  Widget build(BuildContext context) {
    final still = KMotion.reduced(context);
    double seg(double a, double b, [Curve curve = KMotion.decelerate]) {
      if (still) return 1;
      final t = ((_c.value - a) / (b - a)).clamp(0.0, 1.0);
      return curve.transform(t);
    }

    return Semantics(
      container: true,
      liveRegion: true,
      button: true,
      label: '$_line Tap to continue.',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _finish,
        child: ColoredBox(
          color: KColor.bg,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              // Scene and copy fade up, hold, then fade away to plain bg.
              final inScene = seg(0.0, 0.22);
              final out = still ? 0.0 : seg(0.84, 1.0, KMotion.accelerate);
              final line = seg(0.08, 0.38);
              final sub = seg(0.20, 0.50);
              final fill = still ? 0.0 : seg(0.10, 0.84, Curves.linear);
              return Opacity(
                opacity: (inScene * (1 - out)).clamp(0.0, 1.0),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const KSceneBackdrop(
                      asset: KScene.lifter,
                      alignment: Alignment(0.2, -0.2),
                      veil: 1.15,
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                            KSpacing.xxl, 0, KSpacing.xxl, KSpacing.xxl),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Spacer(flex: 3),
                            Opacity(
                              opacity: line,
                              child: Transform.translate(
                                offset: Offset(0, 18 * (1 - line)),
                                child: Text(
                                  _line,
                                  style: KText.display.copyWith(
                                    fontSize: 40,
                                    height: 1.05,
                                    letterSpacing: -1.6,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: KSpacing.md),
                            Opacity(
                              opacity: sub,
                              child: Transform.translate(
                                offset: Offset(0, 12 * (1 - sub)),
                                child: Text(
                                  'Your targets are saved. Chalo, let\'s go.',
                                  style: KText.body.copyWith(
                                    color: KColor.textSecondary,
                                    fontSize: 17,
                                  ),
                                ),
                              ),
                            ),
                            const Spacer(),
                            // Hairline that fills while the moment plays, so
                            // it's clear it moves on by itself.
                            ClipRRect(
                              borderRadius: KRadius.pill,
                              child: SizedBox(
                                height: 2,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ColoredBox(color: KColor.fg.withValues(alpha: 0.10)),
                                    FractionallySizedBox(
                                      alignment: AlignmentDirectional.centerStart,
                                      widthFactor: fill,
                                      child: ColoredBox(color: KColor.ink),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: KSpacing.md),
                            Text(
                              'Tap anywhere to skip',
                              style: KText.caption.copyWith(color: KColor.textMuted),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
