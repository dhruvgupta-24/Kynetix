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
    if (targetWeight <= barWeight) {
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
  static const List<double> standardPlates = [25.0, 20.0, 15.0, 10.0, 5.0, 2.5, 1.25, 0.5];

  /// Calculate required plates per side for [targetWeightKg] using [barWeightKg].
  static PlateCalculationResult calculate({
    required double targetWeightKg,
    double barWeightKg = 20.0,
    List<double> availablePlates = standardPlates,
  }) {
    if (targetWeightKg <= barWeightKg) {
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

    final sortedPlates = List<double>.from(availablePlates)..sort((a, b) => b.compareTo(a));

    for (final plate in sortedPlates) {
      while (currentRemaining >= plate - 0.001) {
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

  /// Color coding for Olympic and standard gym plates
  static Color plateColor(double weight) {
    if (weight >= 25.0) return const Color(0xFFDC2626); // Red
    if (weight >= 20.0) return const Color(0xFF2563EB); // Blue
    if (weight >= 15.0) return const Color(0xFFEAB308); // Yellow
    if (weight >= 10.0) return const Color(0xFF16A34A); // Green
    if (weight >= 5.0)  return const Color(0xFFF1F5F9); // White
    if (weight >= 2.5)  return const Color(0xFF334155); // Black / Dark Slate
    return const Color(0xFF94A3B8); // Silver / Micro-plates
  }
}

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

    return InkWell(
      onTap: onTap ?? () => _showPlateBreakdownModal(context, result),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF13131F),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF232336)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.line_weight_rounded, size: 14, color: KColor.green),
            const SizedBox(width: 6),
            Text(
              result.summaryText,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(width: 6),
            // Mini visual stack
            if (result.platesPerSide.isNotEmpty)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: result.platesPerSide.take(4).map((p) {
                  return Container(
                    margin: const EdgeInsets.only(left: 2),
                    width: 4,
                    height: (12 + (p / 25.0) * 10).clamp(10.0, 22.0),
                    decoration: BoxDecoration(
                      color: BarbellPlateCalculator.plateColor(p),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  void _showPlateBreakdownModal(BuildContext context, PlateCalculationResult result) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F0F1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'BARBELL PLATE CALCULATOR',
                      style: TextStyle(color: KColor.green, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${result.targetWeight.toStringAsFixed(1)} kg Total',
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Bar: ${result.barWeight.toStringAsFixed(0)} kg',
                    style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: Color(0xFF1E1E2F)),
            const SizedBox(height: 12),
            Text(
              'Plates Per Side (${result.weightPerSide.toStringAsFixed(2)} kg):',
              style: const TextStyle(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            if (result.platesPerSide.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Bar only. No extra plates needed.', style: TextStyle(color: Colors.white38)),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: result.platesPerSide.map((p) {
                  final pColor = BarbellPlateCalculator.plateColor(p);
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: pColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: pColor.withOpacity(0.6), width: 1.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(color: pColor, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${p.toStringAsFixed(p == p.roundToDouble() ? 0 : 2)} kg',
                          style: TextStyle(
                            color: pColor == const Color(0xFFF1F5F9) ? Colors.white : pColor,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            if (!result.isExact) ...[
              const SizedBox(height: 12),
              Text(
                'Note: ${result.remainder.toStringAsFixed(2)} kg remainder cannot be evenly loaded with standard plates.',
                style: const TextStyle(color: KColor.amber, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
