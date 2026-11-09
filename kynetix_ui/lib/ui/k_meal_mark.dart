import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/day_log.dart';

// ─── KMealMark ────────────────────────────────────────────────────────────────
//
// One drawn glyph for every meal time instead of five unrelated icons (or
// emoji): the day's arc over a horizon, with the sun where that meal sits in
// the day. Breakfast rises on the left, lunch is overhead, the evening snack
// is low on the right, dinner sinks into the horizon, and late night is a
// crescent at the top of a faint, dashed sky. The part of the arc the day has
// travelled is drawn solid, the rest faint, the same "lap" language as the
// fuel rings. The family reads at a glance, and its order is its meaning.

/// Where [section] sits along the day's arc, 0 (sunrise) to 1 (sunset).
double mealArcPosition(MealSection s) => switch (s) {
      MealSection.breakfast => 0.16,
      MealSection.lunch => 0.5,
      MealSection.eveningSnack => 0.8,
      MealSection.dinner => 1.0,
      MealSection.lateNight => 0.5,
    };

/// The short label for tight places ("Snack", "Late").
String mealShortName(MealSection s) => switch (s) {
      MealSection.breakfast => 'Breakfast',
      MealSection.lunch => 'Lunch',
      MealSection.eveningSnack => 'Snack',
      MealSection.dinner => 'Dinner',
      MealSection.lateNight => 'Late',
    };

class KMealMark extends StatelessWidget {
  const KMealMark(this.section, {super.key, this.size = 20, this.color, this.track, this.active = true});

  final MealSection section;
  final double size;

  /// The sun and the travelled arc. Defaults to ember when [active], muted
  /// otherwise.
  final Color? color;

  /// The untravelled sky and horizon. Defaults to a faint foreground.
  final Color? track;

  /// Whether this meal has food in it (or is the one picked).
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = color ?? (active ? KColor.ember : KColor.textMuted);
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.square(size),
          painter: _MealMarkPainter(
            section: section,
            color: c,
            faint: track ?? KColor.fg.withValues(alpha: KColor.isDark ? 0.26 : 0.24),
          ),
        ),
      ),
    );
  }
}

class _MealMarkPainter extends CustomPainter {
  _MealMarkPainter({required this.section, required this.color, required this.faint});

  final MealSection section;
  final Color color;
  final Color faint;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final stroke = math.max(1.2, s / 15);
    final horizonY = s * 0.74;
    final left = s * 0.12, right = s * 0.88;
    final cx = s / 2;
    final rx = (right - left) / 2;
    final ry = horizonY - s * 0.2;
    final arcRect = Rect.fromCenter(center: Offset(cx, horizonY), width: rx * 2, height: ry * 2);

    final faintPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = faint;
    final solid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;

    // Horizon.
    canvas.drawLine(Offset(s * 0.04, horizonY), Offset(s * 0.96, horizonY), faintPaint);

    Offset onArc(double t) {
      final a = math.pi + t * math.pi; // pi (left) to 2pi (right), upper half
      return Offset(cx + rx * math.cos(a), horizonY + ry * math.sin(a));
    }

    final sunR = s * 0.13;
    if (section == MealSection.lateNight) {
      // Night: the whole sky faint and dashed, a crescent overhead.
      const dashes = 7;
      for (var i = 0; i < dashes; i++) {
        final a0 = math.pi + (i / dashes) * math.pi;
        canvas.drawArc(arcRect, a0, math.pi / dashes * 0.55, false, faintPaint);
      }
      final c = onArc(0.5);
      final moon = Path.combine(
        PathOperation.difference,
        Path()..addOval(Rect.fromCircle(center: c, radius: sunR * 1.1)),
        Path()..addOval(Rect.fromCircle(center: c + Offset(sunR * 0.7, -sunR * 0.45), radius: sunR * 0.95)),
      );
      canvas.drawPath(moon, Paint()..color = color);
      return;
    }

    final t = mealArcPosition(section);
    // The day still ahead, faint; the day travelled, solid.
    canvas.drawArc(arcRect, math.pi + t * math.pi, (1 - t) * math.pi, false, faintPaint);
    if (t > 0) canvas.drawArc(arcRect, math.pi, t * math.pi, false, solid);

    final sun = onArc(t);
    final fill = Paint()..color = color;
    if (section == MealSection.dinner) {
      // Setting: only the half above the horizon shows.
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(0, 0, s, horizonY));
      canvas.drawCircle(sun, sunR * 1.15, fill);
      canvas.restore();
    } else {
      canvas.drawCircle(sun, sunR, fill);
    }
  }

  @override
  bool shouldRepaint(_MealMarkPainter old) =>
      old.section != section || old.color != color || old.faint != faint;
}

// ─── KMealSectionPicker ───────────────────────────────────────────────────────
//
// Which meal this goes to, as the day reads: five chips in time order, each
// with its mark. Every chip stays in view (they wrap), selection is ink, and
// the mark lights up in ember on the picked one.

class KMealSectionPicker extends StatelessWidget {
  const KMealSectionPicker({super.key, required this.value, required this.onChanged});

  final MealSection value;
  final ValueChanged<MealSection> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: KSpacing.sm,
      runSpacing: KSpacing.sm,
      children: [
        for (final s in MealSection.values)
          _SectionChip(
            section: s,
            selected: s == value,
            onTap: () {
              if (s == value) return;
              KHaptics.select();
              onChanged(s);
            },
          ),
      ],
    );
  }
}

class _SectionChip extends StatelessWidget {
  const _SectionChip({required this.section, required this.selected, required this.onTap});

  final MealSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? KColor.onInk : KColor.textPrimary;
    return Semantics(
      button: true,
      selected: selected,
      label: section.displayName,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        borderRadius: KRadius.sm,
        scale: 0.97,
        child: AnimatedContainer(
          duration: KMotion.of(context, KMotion.quick),
          curve: KMotion.emphasizedCurve,
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            gradient: selected ? KShade.convex(KColor.ink) : null,
            boxShadow: selected ? KShadow.lifted : null,
            borderRadius: KRadius.sm,
            border: Border.all(
              color: selected ? KColor.ink : KColor.fg.withValues(alpha: 0.16),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              KMealMark(
                section,
                size: 18,
                active: selected,
                color: selected ? KColor.ember : KColor.textSecondary,
                track: selected ? KColor.onInk.withValues(alpha: 0.32) : null,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  section.displayName,
                  style: KText.bodyMedium.copyWith(color: fg, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
