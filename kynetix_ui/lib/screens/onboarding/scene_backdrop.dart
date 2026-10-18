import 'package:flutter/material.dart';

import '../../config/app_theme.dart';

// ─── Scene photos ─────────────────────────────────────────────────────────────
// Graded 3:4 photos (Unsplash License, see assets/images/scenes/CREDITS.md).
// Gym scenes for training moments, food scenes for eating moments. Only ever
// used behind calm, low-density screens (sign-in, onboarding chapters).

abstract final class KScene {
  static const rack = 'assets/images/scenes/rack.jpg';
  static const lifter = 'assets/images/scenes/lifter.jpg';
  static const thali = 'assets/images/scenes/thali.jpg';
  static const roti = 'assets/images/scenes/roti.jpg';
}

/// Full-bleed hero photo under a scrim that settles into [KColor.bg].
///
/// Moment: scene change. Trigger: [asset] changes (a new chapter or mode).
/// Change: the old photo cross-fades out while the new one fades in and
/// settles from a 4% push-in to rest — a single, one-shot camera move, never
/// a loop. Duration: slow. Haptic: none. Reduced motion: instant swap, no
/// push-in. The scrim is a gradient into the page background, so text set on
/// the lower part of the hero reads in Carbon and in Paper (where the veil is
/// lighter and the bottom fade carries the contrast).
class KSceneBackdrop extends StatelessWidget {
  const KSceneBackdrop({
    super.key,
    required this.asset,
    this.alignment = Alignment.center,
    this.veil = 1.0,
  });

  final String asset;
  final Alignment alignment;

  /// Scales the top-of-hero veil. 1.0 is the default reading-safe scrim;
  /// higher dims the photo further (used behind long copy).
  final double veil;

  @override
  Widget build(BuildContext context) {
    final dark = KColor.isDark;
    final bg = KColor.bg;
    // Carbon: the photo shows through near the top and sinks into black.
    // Paper: a warm-white veil keeps the photo soft, then a full fade to bg.
    final top = ((dark ? 0.28 : 0.40) * veil).clamp(0.0, 0.95);
    final mid = ((dark ? 0.62 : 0.70) * veil).clamp(0.0, 0.97);
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, box) {
          final dpr = MediaQuery.devicePixelRatioOf(context);
          final w = box.maxWidth.isFinite
              ? box.maxWidth
              : MediaQuery.sizeOf(context).width;
          // Decode at display size: the photo is 3:4, cover-fitted to width.
          final cacheWidth = (w * dpr).clamp(1, 1080).round();
          // The whole hero fades out at its foot, so it melts into the page's
          // aurora instead of ending on a hard edge where the box stops.
          return ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.0, 0.8, 1.0],
              colors: [Colors.white, Colors.white, Colors.transparent], // alpha mask only
            ).createShader(rect),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: bg),
                // Clipped so the one-shot push-in (scale 1.04) never spills past
                // the scrim and leaves a hard photo edge across the page.
                ClipRect(
                  child: RepaintBoundary(
                    child: AnimatedSwitcher(
                      duration: KMotion.of(context, KMotion.slow),
                      switchInCurve: KMotion.decelerate,
                      switchOutCurve: KMotion.accelerate,
                      layoutBuilder: (current, previous) => Stack(
                        fit: StackFit.expand,
                        children: [...previous, ?current],
                      ),
                      child: _ScenePhoto(
                        key: ValueKey(asset),
                        asset: asset,
                        alignment: alignment,
                        cacheWidth: cacheWidth,
                      ),
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.0, 0.45, 0.82, 1.0],
                      colors: [
                        bg.withValues(alpha: top),
                        bg.withValues(alpha: mid),
                        bg.withValues(alpha: dark ? 0.90 : 0.94),
                        bg,
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ScenePhoto extends StatelessWidget {
  const _ScenePhoto({
    super.key,
    required this.asset,
    required this.alignment,
    required this.cacheWidth,
  });

  final String asset;
  final Alignment alignment;
  final int cacheWidth;

  @override
  Widget build(BuildContext context) {
    final settle = KMotion.of(context, KMotion.celebrate);
    final image = Image.asset(
      asset,
      fit: BoxFit.cover,
      alignment: alignment,
      cacheWidth: cacheWidth,
      gaplessPlayback: true,
      excludeFromSemantics: true,
      // Fade in once decoded so the hero never pops in.
      frameBuilder: (context, child, frame, sync) {
        if (sync) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: KMotion.of(context, KMotion.emphasized),
          curve: KMotion.decelerate,
          child: child,
        );
      },
      errorBuilder: (_, _, _) => const SizedBox.expand(),
    );
    if (settle == Duration.zero) return image;
    // One-shot settle: a gentle push-in that comes to rest. Keyed by asset,
    // so it plays once per scene.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1.04, end: 1.0),
      duration: settle,
      curve: KMotion.emphasizedCurve,
      builder: (context, s, child) => Transform.scale(scale: s, child: child),
      child: image,
    );
  }
}
