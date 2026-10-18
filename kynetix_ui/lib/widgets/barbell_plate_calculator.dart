import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import '../config/app_theme.dart';

/// Plate calculation result for one side of the barbell.
class PlateCalculationResult {
  final double targetWeight;
  final double barWeight;
  final double weightPerSide;
  final List<double> platesPerSide; // e.g. [20, 10, 2.5]
  final double remainder; // Any unachievable remainder
  final bool isExact;

  const PlateCalculationResult({
    required this.targetWeight,
    required this.barWeight,
    required this.weightPerSide,
    required this.platesPerSide,
    required this.remainder,
    required this.isExact,
  });

  String get summaryText {
    if (targetWeight < barWeight) {
      return 'Below bar (${barWeight.toStringAsFixed(0)} kg)';
    }
    if (targetWeight == barWeight) {
      return '${barWeight.toStringAsFixed(0)} kg bar only';
    }
    if (platesPerSide.isEmpty) {
      return '${barWeight.toStringAsFixed(0)} kg bar';
    }
    final counts = <double, int>{};
    for (final p in platesPerSide) {
      counts[p] = (counts[p] ?? 0) + 1;
    }
    final parts = counts.entries.map((e) {
      final pStr = e.key == e.key.roundToDouble()
          ? e.key.toStringAsFixed(0)
          : e.key.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '');
      return e.value > 1 ? '${e.value}×$pStr' : pStr;
    }).toList();
    return '${parts.join(' + ')} kg / side';
  }
}

/// Contextual Barbell Plate Calculator for Kynetix.
class BarbellPlateCalculator {
  static const List<double> standardPlates = [
    25.0,
    20.0,
    15.0,
    10.0,
    5.0,
    2.5,
    1.25,
    0.5,
  ];

  /// Calculate required plates per side for [targetWeightKg] using [barWeightKg].
  /// Optionally constrained by available plates or specific plate inventory counts per side.
  static PlateCalculationResult calculate({
    required double targetWeightKg,
    double barWeightKg = 20.0,
    List<double> availablePlates = standardPlates,
    Map<double, int>? plateInventoryPerSide,
  }) {
    if (targetWeightKg < barWeightKg) {
      return PlateCalculationResult(
        targetWeight: targetWeightKg,
        barWeight: barWeightKg,
        weightPerSide: 0,
        platesPerSide: const [],
        remainder: targetWeightKg - barWeightKg,
        isExact: false,
      );
    }

    if (targetWeightKg == barWeightKg) {
      return PlateCalculationResult(
        targetWeight: targetWeightKg,
        barWeight: barWeightKg,
        weightPerSide: 0,
        platesPerSide: const [],
        remainder: 0,
        isExact: true,
      );
    }

    final double neededPerSide = (targetWeightKg - barWeightKg) / 2.0;
    double currentRemaining = (neededPerSide * 100).round() / 100.0;
    final List<double> chosenPlates = [];

    // Working inventory copy if inventory constraint is active
    final Map<double, int>? remainingInventory = plateInventoryPerSide != null
        ? Map<double, int>.from(plateInventoryPerSide)
        : null;

    final candidatePlates = (remainingInventory != null
        ? remainingInventory.keys.toList()
        : availablePlates);

    final sortedPlates = List<double>.from(candidatePlates)
      ..sort((a, b) => b.compareTo(a));

    for (final plate in sortedPlates) {
      while (currentRemaining >= plate - 0.001) {
        if (remainingInventory != null) {
          final count = remainingInventory[plate] ?? 0;
          if (count <= 0) break; // Plate exhausted in inventory
          remainingInventory[plate] = count - 1;
        }
        chosenPlates.add(plate);
        currentRemaining = ((currentRemaining - plate) * 100).round() / 100.0;
      }
    }

    return PlateCalculationResult(
      targetWeight: targetWeightKg,
      barWeight: barWeightKg,
      weightPerSide: neededPerSide,
      platesPerSide: chosenPlates,
      remainder: currentRemaining,
      isExact: currentRemaining.abs() < 0.01,
    );
  }

  /// Rounds [targetWeightKg] to the nearest weight that can actually be loaded
  /// on a [barWeightKg] bar from [availablePlates] (pairs, one per side),
  /// stepping in [incrementKg] (2.5 kg = a 1.25 kg plate each side).
  /// Never returns less than the empty bar.
  static double roundToLoadable(
    double targetWeightKg, {
    double barWeightKg = 20.0,
    double incrementKg = 2.5,
    List<double> availablePlates = standardPlates,
  }) {
    if (targetWeightKg <= barWeightKg) return barWeightKg;
    final steps = ((targetWeightKg - barWeightKg) / incrementKg).round();
    var candidate = barWeightKg + steps * incrementKg;
    // Walk down until the greedy plate fit is exact (it is for the standard
    // set, but a custom plate list may not cover every step).
    while (candidate > barWeightKg) {
      final r = calculate(
        targetWeightKg: candidate,
        barWeightKg: barWeightKg,
        availablePlates: availablePlates,
      );
      if (r.isExact) break;
      candidate -= incrementKg;
    }
    return (candidate * 100).round() / 100.0;
  }

  /// Colour coding for Olympic and standard gym plates.
  ///
  /// These are real-world IWF plate colours (data, not theme) and are pinned
  /// by production_readiness_audit_test, so they stay literal. Size and the
  /// kg label always accompany them, so colour is never the only cue.
  static Color plateColor(double weight) {
    if (weight >= 25.0) return const Color(0xFFDC2626); // Red
    if (weight >= 20.0) return const Color(0xFF2563EB); // Blue
    if (weight >= 15.0) return const Color(0xFFEAB308); // Yellow
    if (weight >= 10.0) return const Color(0xFF16A34A); // Green
    if (weight >= 5.0) return const Color(0xFFF1F5F9); // White
    if (weight >= 2.5) return const Color(0xFF334155); // Black / Dark Slate
    return const Color(0xFF94A3B8); // Silver / Micro-plates
  }
}

String _plateLabel(double p) =>
    p.toStringAsFixed(p == p.roundToDouble() ? 0 : 2);

/// Hairline that separates a plate from whatever surface sits behind it.
Color _plateEdge() => KColor.fg.withValues(alpha: KColor.isDark ? 0.18 : 0.22);

/// Compact Visual Plate Stack Widget to embed directly under weight dials.
class BarbellPlateStackView extends StatelessWidget {
  final double targetWeightKg;
  final double barWeightKg;
  final VoidCallback? onTap;

  const BarbellPlateStackView({
    super.key,
    required this.targetWeightKg,
    this.barWeightKg = 20.0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final result = BarbellPlateCalculator.calculate(
      targetWeightKg: targetWeightKg,
      barWeightKg: barWeightKg,
    );

    return Semantics(
      button: true,
      label: 'Plate breakdown, ${result.summaryText}',
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap ?? () => _showPlateBreakdownModal(context, result),
          borderRadius: KRadius.sm,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: KColor.isDark ? KColor.card : KColor.cardHigh,
              borderRadius: KRadius.sm,
              border: Border.all(
                color: KColor.isDark
                    ? KColor.fg.withValues(alpha: 0.08)
                    : KColor.border,
                width: 1,
              ),
            ),
            // 34 + 12 padding + 2 border = 48dp touch target.
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 34),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.line_weight_rounded,
                    size: 15,
                    color: KColor.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      result.summaryText,
                      style: KText.numSmall.copyWith(
                        color: KColor.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: KSpacing.sm),
                  // Mini visual stack — plates spring onto the sleeve when the
                  // weight changes; unchanged plates keep their key and stay put.
                  if (result.platesPerSide.isNotEmpty)
                    SizedBox(
                      height: 22,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 5,
                            height: 3,
                            decoration: BoxDecoration(
                              color: KColor.textMuted,
                              borderRadius: KRadius.pill,
                            ),
                          ),
                          for (
                            var i = 0;
                            i < result.platesPerSide.length && i < 4;
                            i++
                          )
                            _SpringPlate(
                              key: ValueKey('$i:${result.platesPerSide[i]}'),
                              weight: result.platesPerSide[i],
                            ),
                          Container(
                            width: 7,
                            height: 3,
                            margin: const EdgeInsetsDirectional.only(start: 1),
                            decoration: BoxDecoration(
                              color: KColor.textMuted,
                              borderRadius: KRadius.pill,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showPlateBreakdownModal(
    BuildContext context,
    PlateCalculationResult result,
  ) {
    showKSheet<void>(
      context: context,
      builder: (ctx) => _PlateBreakdownSheet(result: result),
    );
  }
}

/// One mini plate that springs onto the bar the first time it appears.
class _SpringPlate extends StatelessWidget {
  const _SpringPlate({super.key, required this.weight});
  final double weight;

  @override
  Widget build(BuildContext context) {
    final color = BarbellPlateCalculator.plateColor(weight);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: KMotion.of(context, KMotion.slow),
      curve: KMotion.spring,
      builder: (context, v, child) => Transform.translate(
        offset: Offset((1 - v) * 8, 0),
        child: Transform.scale(scaleY: v.clamp(0.0, 1.25), child: child),
      ),
      child: Container(
        margin: const EdgeInsetsDirectional.only(start: 2),
        width: 5,
        height: (12 + (weight / 25.0) * 10).clamp(10.0, 22.0),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(1.5),
          border: Border.all(color: _plateEdge(), width: 0.5),
        ),
      ),
    );
  }
}

// ─── Breakdown sheet ──────────────────────────────────────────────────────────

class _PlateBreakdownSheet extends StatelessWidget {
  const _PlateBreakdownSheet({required this.result});
  final PlateCalculationResult result;

  @override
  Widget build(BuildContext context) {
    final plates = result.platesPerSide;
    final perSideText = plates.isEmpty
        ? 'bar only'
        : '${plates.map(_plateLabel).join(', ')} kg per side';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(KSpacing.xl, 0, KSpacing.xl, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const KDragHandle(),
          const SizedBox(height: KSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        'Plate calculator',
                        style: KText.caption.copyWith(
                          color: KColor.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: KSpacing.xs),
                    Text(
                      '${result.targetWeight.toStringAsFixed(1)} kg total',
                      style: KText.numDisplay.copyWith(fontSize: 32),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: KSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: KColor.fg.withValues(
                    alpha: KColor.isDark ? 0.06 : 0.04,
                  ),
                  borderRadius: KRadius.sm,
                  border: Border.all(
                    color: KColor.isDark
                        ? KColor.fg.withValues(alpha: 0.08)
                        : KColor.border,
                  ),
                ),
                child: Text(
                  'Bar: ${result.barWeight.toStringAsFixed(0)} kg',
                  style: KText.numSmall.copyWith(
                    color: KColor.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: KSpacing.lg),

          // Painted barbell — plates spring on, outward from the collar.
          Semantics(
            label: 'Barbell diagram, $perSideText',
            child: ExcludeSemantics(
              child: RepaintBoundary(
                child: SizedBox(
                  height: 96,
                  width: double.infinity,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: KMotion.of(context, KMotion.celebrate),
                    builder: (context, progress, _) => CustomPaint(
                      painter: _BarbellPainter(
                        scene: _BarbellScene(
                          plates: plates,
                          shaft: KColor.textMuted,
                          sleeve: KColor.textSecondary,
                          collar: KColor.textPrimary,
                          rim: KColor.bg.withValues(alpha: 0.55),
                          sheen: Colors.white.withValues(
                            alpha: KColor.isDark ? 0.22 : 0.35,
                          ),
                          floor: KColor.fg.withValues(
                            alpha: KColor.isDark ? 0.05 : 0.06,
                          ),
                          colors: [
                            for (final p in plates)
                              BarbellPlateCalculator.plateColor(p),
                          ],
                          progress: progress,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: KSpacing.lg),
          Divider(
            height: 1,
            color: KColor.isDark
                ? KColor.fg.withValues(alpha: 0.08)
                : KColor.border,
          ),
          const SizedBox(height: KSpacing.md),
          Text(
            'Plates per side (${result.weightPerSide.toStringAsFixed(2)} kg)',
            style: KText.bodyMedium.copyWith(color: KColor.textSecondary),
          ),
          const SizedBox(height: KSpacing.md),
          if (plates.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: KSpacing.sm),
              child: Text(
                'Just the bar. No plates needed.',
                style: KText.body.copyWith(color: KColor.textMuted),
              ),
            )
          else
            Wrap(
              spacing: KSpacing.sm,
              runSpacing: KSpacing.sm,
              children: plates.map((p) {
                final pColor = BarbellPlateCalculator.plateColor(p);
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KSpacing.md,
                    vertical: KSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: KColor.isDark ? KColor.card : KColor.cardHigh,
                    borderRadius: KRadius.sm,
                    border: Border.all(
                      color: KColor.isDark
                          ? KColor.fg.withValues(alpha: 0.10)
                          : KColor.border,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: pColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: _plateEdge(), width: 0.8),
                        ),
                      ),
                      const SizedBox(width: KSpacing.sm),
                      Text(
                        '${_plateLabel(p)} kg',
                        style: KText.numSmall.copyWith(
                          color: KColor.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          if (!result.isExact) ...[
            const SizedBox(height: KSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: KColor.warning,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${result.remainder.toStringAsFixed(2)} kg left over. Standard plates can\'t load it evenly.',
                    style: KText.caption.copyWith(
                      color: KColor.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Barbell painter ──────────────────────────────────────────────────────────

@immutable
class _BarbellScene {
  const _BarbellScene({
    required this.plates,
    required this.colors,
    required this.progress,
    required this.shaft,
    required this.sleeve,
    required this.collar,
    required this.rim,
    required this.sheen,
    required this.floor,
  });

  final List<double> plates; // per side, heaviest first (innermost)
  final List<Color> colors;
  final double progress; // 0..1 load-in timeline
  // Theme colours travel with the scene so a theme switch repaints.
  final Color shaft, sleeve, collar, rim, sheen, floor;

  @override
  bool operator ==(Object other) =>
      other is _BarbellScene &&
      other.progress == progress &&
      other.shaft == shaft &&
      other.sleeve == sleeve &&
      other.collar == collar &&
      other.rim == rim &&
      other.sheen == sheen &&
      other.floor == floor &&
      listEquals(other.plates, plates) &&
      listEquals(other.colors, colors);

  @override
  int get hashCode => Object.hash(
    progress,
    Object.hashAll(plates),
    Object.hashAll(colors),
    shaft,
    sleeve,
    collar,
    rim,
    sheen,
    floor,
  );
}

class _BarbellPainter extends CustomPainter {
  _BarbellPainter({required this.scene});
  final _BarbellScene scene;

  final Paint _shaft = Paint();
  final Paint _sleeve = Paint();
  final Paint _collar = Paint();
  final Paint _plate = Paint();
  final Paint _sheen = Paint();
  final Paint _rim = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;
  final Paint _floor = Paint();

  static const double _sleeveLen = 0.34; // fraction of width per side

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cy = h / 2;
    _shaft.color = scene.shaft;
    _sleeve.color = scene.sleeve;
    _collar.color = scene.collar;
    _sheen.color = scene.sheen;
    _rim.color = scene.rim;
    _floor.color = scene.floor;
    final sleeveW = w * _sleeveLen;
    final shaftL = sleeveW;
    final shaftR = w - sleeveW;

    // Floor shadow.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(w / 2, h - 3),
          width: w * 0.9,
          height: 4,
        ),
        const Radius.circular(2),
      ),
      _floor,
    );

    // Shaft + sleeves + collars (symmetric).
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(shaftL, cy - 2, shaftR, cy + 2),
        const Radius.circular(2),
      ),
      _shaft,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(4, cy - 3.5, shaftL, cy + 3.5),
        const Radius.circular(3),
      ),
      _sleeve,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(shaftR, cy - 3.5, w - 4, cy + 3.5),
        const Radius.circular(3),
      ),
      _sleeve,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(shaftL, cy), width: 5, height: 16),
        const Radius.circular(2),
      ),
      _collar,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(shaftR, cy), width: 5, height: 16),
        const Radius.circular(2),
      ),
      _collar,
    );

    final n = scene.plates.length;
    if (n == 0) return;

    // Thickness ∝ weight; squeeze uniformly if the stack outgrows the sleeve.
    double thickness(double p) => 5 + (p / 25.0).clamp(0.0, 1.0) * 9;
    var total = 0.0;
    for (final p in scene.plates) {
      total += thickness(p) + 1.5;
    }
    final avail = sleeveW - 14;
    final squeeze = total > avail ? avail / total : 1.0;

    // Each plate springs in on its own slice of the timeline.
    final stagger = n <= 1 ? 0.0 : (0.45 / n).clamp(0.0, 0.08);
    const window = 0.5;

    var offset = 4.0; // distance outward from collar
    for (var i = 0; i < n; i++) {
      final p = scene.plates[i];
      final t = ((scene.progress - i * stagger) / window).clamp(0.0, 1.0);
      final s = KMotion.spring.transform(t);
      final th = thickness(p) * squeeze;
      final ph =
          h * (p >= 10 ? 0.86 : (0.40 + 0.46 * (p / 10.0).clamp(0.0, 1.0)));
      final slide = (1 - s) * (sleeveW * 0.6);
      _plate.color = scene.colors[i].withValues(
        alpha: (s * 1.4).clamp(0.0, 1.0),
      );

      for (final side in const [-1.0, 1.0]) {
        // Left side grows leftward from shaftL, right side rightward from shaftR.
        final inner = side < 0 ? shaftL - offset : shaftR + offset;
        final outer = inner + side * th;
        final dx = side * slide;
        final rect = Rect.fromLTRB(
          (side < 0 ? outer : inner) + dx,
          cy - ph / 2,
          (side < 0 ? inner : outer) + dx,
          cy + ph / 2,
        );
        final rr = RRect.fromRectAndRadius(rect, const Radius.circular(2.5));
        canvas.drawRRect(rr, _plate);
        canvas.drawRRect(rr, _rim);
        // Top sheen sells the depth.
        canvas.drawRect(
          Rect.fromLTWH(
            rect.left + 1,
            rect.top + 2,
            (rect.width - 2).clamp(0.0, 4.0),
            rect.height * 0.35,
          ),
          _sheen,
        );
      }
      offset += th + 1.5 * squeeze;
    }
  }

  @override
  bool shouldRepaint(covariant _BarbellPainter old) => old.scene != scene;
}
