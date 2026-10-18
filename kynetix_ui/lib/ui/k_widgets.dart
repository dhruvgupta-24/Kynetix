import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/app_theme.dart';

// ─── KRing ────────────────────────────────────────────────────────────────────
// Liquid progress ring: animates to new values with a spring, sweep gradient,
// soft under-glow and a bright leading cap. Over 100% it keeps sweeping in a
// second, brighter lap so "over target" is visible without colour alone.

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

  /// Soft under-glow + bright leading cap. Defaults on for Carbon, off for
  /// Paper; pass `false` for a calm ring on data-dense screens.
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
      // Own layer: the sweep animation (and the blurred under-glow) never
      // repaints the card around it, and scrolling never repaints the ring.
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
              glow: glow ?? false,
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
    required this.glow,
  });

  final double progress;
  final List<Color> colors;
  final double stroke;
  final Color track;
  final bool glow;

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

    final cols = colors.length == 1 ? [colors.first, colors.first] : colors;
    final shader = SweepGradient(
      colors: [...cols, cols.first],
      transform: const GradientRotation(-math.pi / 2),
    ).createShader(rect);

    final lap1 = progress.clamp(0.0, 1.0);
    final sweep = 2 * math.pi * lap1;

    if (glow) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..shader = shader
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * 0.55),
      );
    }
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = shader,
    );

    // Second lap (over target): thinner, brighter overlay.
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
          ..color = Colors.white.withValues(alpha: 0.85),
      );
    }

    // Leading cap highlight.
    if (glow && sweep > 0) {
      final a = -math.pi / 2 + sweep;
      final cap = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
      canvas.drawCircle(cap, stroke * 0.26, Paint()..color = Colors.white.withValues(alpha: 0.9));
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter o) =>
      o.progress != progress || o.glow != glow || o.stroke != stroke || o.track != track || !_same(o.colors, colors);

  static bool _same(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

// ─── KBar ─────────────────────────────────────────────────────────────────────
// Animated linear progress with gradient fill and glow head.

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
    return LayoutBuilder(
      builder: (context, box) => Container(
        height: height,
        decoration: BoxDecoration(
          color: trackColor ?? KColor.fg.withValues(alpha: KColor.isDark ? 0.07 : 0.06),
          borderRadius: BorderRadius.circular(height),
        ),
        alignment: AlignmentDirectional.centerStart,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: target),
          duration: KMotion.of(context, duration),
          curve: KMotion.emphasizedCurve,
          builder: (context, v, _) => Container(
            width: box.maxWidth.isFinite ? box.maxWidth * v : 0,
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(height),
              gradient: LinearGradient(
                colors: colors.length == 1 ? [colors.first, colors.first] : colors,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── showKSheet ───────────────────────────────────────────────────────────────
// Bottom sheet with the app's sheet chrome and a softer, springier entrance.

Future<T?> showKSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool useSafeArea = true,
  bool isDismissible = true,
  bool enableDrag = true,
  Color? backgroundColor,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    backgroundColor: backgroundColor ?? KColor.surface,
    barrierColor: Colors.black.withValues(alpha: KColor.isDark ? 0.6 : 0.3),
    sheetAnimationStyle: KMotion.reduced(context)
        ? AnimationStyle.noAnimation
        : const AnimationStyle(
            duration: KMotion.emphasized,
            reverseDuration: KMotion.standard,
            curve: KMotion.emphasizedCurve,
            reverseCurve: KMotion.accelerate,
          ),
    builder: builder,
  );
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
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (r) => LinearGradient(colors: colors).createShader(r),
      child: Text(text, style: style, textAlign: textAlign),
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
