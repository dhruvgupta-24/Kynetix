import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../config/app_theme.dart';

// ─── KRing ────────────────────────────────────────────────────────────────────
// Progress ring: animates to new values in one flat colour. Over 100% it
// keeps sweeping in a thinner second lap (ink, or base on an ink ring) so
// "over target" is visible without a new colour.

class KRing extends StatelessWidget {
  const KRing({
    super.key,
    required this.progress,
    required this.colors,
    this.size = 120,
    this.stroke = 12,
    this.trackColor,
    this.child,
    this.duration = KMotion.slow,
    this.semanticsLabel,
    this.glow,
  });

  /// Retired: the palette has no glow. Kept so callers compile.
  final bool? glow;

  final double progress;
  final List<Color> colors;
  final double size;
  final double stroke;
  final Color? trackColor;
  final Widget? child;
  final Duration duration;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final target = progress.isFinite ? progress.clamp(0.0, 2.0) : 0.0;
    return Semantics(
      label: semanticsLabel,
      value: semanticsLabel == null ? null : '${(target * 100).round()}%',
      // Own layer: the sweep animation never repaints the card around it,
      // and scrolling never repaints the ring.
      child: RepaintBoundary(
        child: SizedBox.square(
        dimension: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: target),
          duration: KMotion.of(context, duration),
          curve: KMotion.emphasizedCurve,
          builder: (context, v, child) => CustomPaint(
            painter: _RingPainter(
              progress: v,
              colors: colors,
              stroke: stroke,
              track: trackColor ?? KColor.fg.withValues(alpha: KColor.isDark ? 0.07 : 0.06),
              lap: colors.isNotEmpty && colors.first == KColor.ink ? KColor.bg : KColor.ink,
            ),
            child: child,
          ),
          child: child == null ? null : Center(child: child),
        ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.colors,
    required this.stroke,
    required this.track,
    required this.lap,
  });

  final double progress;
  final List<Color> colors;
  final double stroke;
  final Color track;
  final Color lap;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = (size.shortestSide - stroke) / 2;
    final rect = Rect.fromCircle(center: c, radius: r);

    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );
    if (progress <= 0.001) return;

    final fill = colors.isEmpty ? KColor.ink : colors.first;
    final lap1 = progress.clamp(0.0, 1.0);
    final sweep = 2 * math.pi * lap1;

    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = fill,
    );

    // Second lap (over target): thinner overlay in a contrasting tone.
    if (progress > 1.0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * (progress - 1.0).clamp(0.0, 1.0),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * 0.45
          ..strokeCap = StrokeCap.round
          ..color = lap.withValues(alpha: 0.85),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter o) =>
      o.progress != progress || o.lap != lap || o.stroke != stroke || o.track != track || !_same(o.colors, colors);

  static bool _same(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

// ─── KBar ─────────────────────────────────────────────────────────────────────
// Animated linear progress with a flat fill.

class KBar extends StatelessWidget {
  const KBar({
    super.key,
    required this.progress,
    required this.colors,
    this.height = 8,
    this.trackColor,
    this.duration = KMotion.slow,
  });

  final double progress;
  final List<Color> colors;
  final double height;
  final Color? trackColor;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final target = progress.isFinite ? progress.clamp(0.0, 1.0) : 0.0;
    // Painted, not laid out: the fill grows by repainting one small layer,
    // never by animating a Container's width (no per-frame layout).
    return LimitedBox(
      maxWidth: 0,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: RepaintBoundary(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: target),
            duration: KMotion.of(context, duration),
            curve: KMotion.emphasizedCurve,
            builder: (context, v, _) => CustomPaint(
              painter: _BarPainter(
                progress: v,
                fill: colors.isEmpty ? KColor.ink : colors.first,
                track: trackColor ?? KColor.fg.withValues(alpha: KColor.isDark ? 0.07 : 0.06),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({required this.progress, required this.fill, required this.track});

  final double progress;
  final Color fill;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height);
    final p = Paint()..color = track;
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, r), p);
    final w = size.width * progress;
    if (w <= 0) return;
    p.color = fill;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, size.height), r), p);
  }

  @override
  bool shouldRepaint(covariant _BarPainter o) =>
      o.progress != progress || o.fill != fill || o.track != track;
}

// ─── showKSheet ───────────────────────────────────────────────────────────────
// Bottom sheet with the app's sheet chrome. Enters on KMotion.sheetSpring
// (firm landing, no visible bounce), leaves quickly on an accelerating curve.
// Figure / ground: the scene behind softly blurs (sigma 0 to 6) and dims
// (52% dark, 26% light) as the sheet rises, both driven by the route's own
// animation, so dragging the sheet down un-blurs the page with the finger.
// Reduced motion: no animation, and a static light blur.
// Every sheet draws its own handle (KDragHandle / KSheetHeader), so none is
// added here.

Future<T?> showKSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool useSafeArea = true,
  bool isDismissible = true,
  bool enableDrag = true,
  Color? backgroundColor,
}) {
  // Same wiring as showModalBottomSheet, with our own barrier.
  final navigator = Navigator.of(context);
  final reduced = KMotion.reduced(context);
  return navigator.push<T>(
    _KSheetRoute<T>(
      builder: builder,
      capturedThemes: InheritedTheme.capture(from: context, to: navigator.context),
      isScrollControlled: isScrollControlled,
      useSafeArea: useSafeArea,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      backgroundColor: backgroundColor ?? KColor.surface,
      modalBarrierColor: Colors.black.withValues(alpha: KColor.isDark ? 0.52 : 0.26),
      barrierLabel: MaterialLocalizations.of(context).scrimLabel,
      barrierOnTapHint: MaterialLocalizations.of(context)
          .scrimOnTapHint(MaterialLocalizations.of(context).bottomSheetLabel),
      reducedMotion: reduced,
      sheetAnimationStyle: reduced
          ? AnimationStyle.noAnimation
          : AnimationStyle(
              duration: KMotion.sheetDuration,
              reverseDuration: const Duration(milliseconds: 240),
              curve: KMotion.sheetCurve,
              reverseCurve: KMotion.accelerate,
            ),
    ),
  );
}

/// A modal bottom sheet route whose barrier blurs the scene behind it.
class _KSheetRoute<T> extends ModalBottomSheetRoute<T> {
  _KSheetRoute({
    required super.builder,
    required super.capturedThemes,
    required super.isScrollControlled,
    required super.useSafeArea,
    required super.isDismissible,
    required super.enableDrag,
    required super.backgroundColor,
    required super.modalBarrierColor,
    required super.barrierLabel,
    required super.barrierOnTapHint,
    required super.sheetAnimationStyle,
    required this.reducedMotion,
  });

  final bool reducedMotion;

  /// Blur at rest, in logical px.
  static const _sigma = 6.0;

  /// Static blur under reduced motion: present, but lighter.
  static const _reducedSigma = 3.0;

  @override
  Widget buildModalBarrier() {
    // The stock barrier (tap to dismiss, semantics, animated dim) on top of
    // a blur of whatever is behind the route.
    final barrier = super.buildModalBarrier();
    final anim = animation;
    if (reducedMotion || anim == null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          const _SheetBlur(sigma: _reducedSigma),
          barrier,
        ],
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedBuilder(
          animation: anim,
          builder: (context, _) => _SheetBlur(
            // The route animation is the sheet's position, so the blur
            // tracks a drag too. Easing in late keeps the first frames of
            // the rise cheap.
            sigma: _sigma * Curves.easeOut.transform(anim.value.clamp(0.0, 1.0)),
          ),
        ),
        barrier,
      ],
    );
  }
}

class _SheetBlur extends StatelessWidget {
  const _SheetBlur({required this.sigma});
  final double sigma;

  @override
  Widget build(BuildContext context) {
    // Under ~0.1 a blur is invisible; skip the filter entirely.
    if (sigma < 0.1) return const SizedBox.expand();
    return IgnorePointer(
      child: ExcludeSemantics(
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.clamp),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

// ─── KGradientText ────────────────────────────────────────────────────────────

class KGradientText extends StatelessWidget {
  const KGradientText(this.text, {super.key, required this.style, required this.colors, this.textAlign});
  final String text;
  final TextStyle style;
  final List<Color> colors;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    // Flat: the first colour only. The name stays so callers compile.
    return Text(
      text,
      style: style.copyWith(color: colors.isEmpty ? style.color : colors.first),
      textAlign: textAlign,
    );
  }
}

// ─── Editorial building blocks ───────────────────────────────────────────────
// Group with type, space and hairlines instead of boxes. Cards are for objects
// (a meal, a session, a product); these are for everything around them.

/// A 1px rule in the foreground colour. Indent it to sit under text.
class KHairline extends StatelessWidget {
  const KHairline({super.key, this.indent = 0, this.endIndent = 0, this.thickness = 1, this.strong = false});
  final double indent;
  final double endIndent;
  final double thickness;

  /// Ink-coloured rule, for the heavy bars of the nutrition label.
  final bool strong;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsetsDirectional.only(start: indent, end: endIndent),
        child: SizedBox(
          height: thickness,
          width: double.infinity,
          child: ColoredBox(
            color: strong
                ? KColor.fg.withValues(alpha: KColor.isDark ? 0.22 : 0.2)
                : KColor.fg.withValues(alpha: KColor.isDark ? 0.08 : 0.08),
          ),
        ),
      );
}

/// One number keyed to its meaning by a colour dot: "● 201 kcal".
/// The number is tabular and carries the weight; the unit stays quiet.
class KDotStat extends StatelessWidget {
  const KDotStat(this.value, this.unit, {super.key, Color? color, this.size = 13})
      : _color = color;
  final String value;
  final String unit;
  final Color? _color;
  Color get color => _color ?? KColor.textMuted;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        KDot(color: color, size: (size * 0.46).roundToDouble()),
        SizedBox(width: size * 0.42),
        Flexible(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                text: value,
                style: KText.numSmall.copyWith(
                  fontSize: size,
                  fontWeight: FontWeight.w600,
                  color: KColor.textPrimary,
                ),
              ),
              if (unit.isNotEmpty)
                TextSpan(
                  text: ' $unit',
                  style: KText.caption.copyWith(fontSize: size, color: KColor.textSecondary),
                ),
            ]),
          ),
        ),
      ],
    );
  }
}

/// A run of [KDotStat]s with even spacing; wraps under large text.
class KDotStats extends StatelessWidget {
  const KDotStats(this.stats, {super.key, this.spacing = 14});
  final List<Widget> stats;
  final double spacing;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: spacing,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: stats,
      );
}

/// A full-width choice in a sheet or list: neutral outlined icon, title,
/// one line of help, chevron. Separate rows with [KHairline]; never box them.
class KOptionRow extends StatelessWidget {
  const KOptionRow({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.leading,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  /// Replaces the icon (e.g. a [KynoMark]).
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      haptic: true,
      semanticLabel: subtitle == null ? title : '$title. $subtitle',
      borderRadius: KRadius.sm,
      scale: 0.985,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: leading ?? KIcon(icon, size: 22, color: KColor.textPrimary),
                ),
              ),
              const SizedBox(width: KSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: KText.h3.copyWith(fontSize: 16)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: KText.caption.copyWith(fontSize: 13.5)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: KSpacing.sm),
              KIcon(KIcons.next, size: KIcons.md, color: KColor.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// A quiet text action ("Edit target", "Pick another day"): underlined ink
/// text, optional leading icon, 48dp tall, no container.
class KTextAction extends StatelessWidget {
  const KTextAction(
    this.label, {
    super.key,
    required this.onTap,
    this.icon,
    this.semanticLabel,
    Color? color,
  }) : _color = color;
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final Color? _color;
  Color get color => _color ?? KColor.textPrimary;

  @override
  Widget build(BuildContext context) {
    final c = onTap == null ? KColor.textDisabled : color;
    return Pressable(
      onTap: onTap == null
          ? null
          : () {
              KHaptics.select();
              onTap!();
            },
      semanticLabel: semanticLabel ?? label,
      borderRadius: KRadius.sm,
      scale: 0.96,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                KIcon(icon!, size: 18, color: c),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  style: KText.bodyMedium.copyWith(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: c,
                    decoration: TextDecoration.underline,
                    decorationColor: c.withValues(alpha: 0.35),
                    decorationThickness: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The way into Kyno from any screen: a plain ink pill with Kyno's mark.
/// No gradient rim, no sparkle.
class KAskKyno extends StatelessWidget {
  const KAskKyno({super.key, required this.onTap, this.label = 'Ask Kyno'});
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      haptic: true,
      semanticLabel: label,
      borderRadius: KRadius.pill,
      child: Container(
        height: 52,
        padding: const EdgeInsets.fromLTRB(9, 0, 20, 0),
        decoration: BoxDecoration(
          color: KColor.ink,
          borderRadius: KRadius.pill,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            KynoMark(size: 32, color: KColor.onInk),
            const SizedBox(width: 10),
            Text(
              label,
              style: KText.bodyMedium.copyWith(
                color: KColor.onInk,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
