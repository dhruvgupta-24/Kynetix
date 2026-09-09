import 'dart:math';
import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../models/workout_session.dart';

/// Available progression metrics to visualize.
enum ProgressionMetric {
  estimated1RM('Estimated 1RM', 'kg'),
  topWeight('Top Weight', 'kg'),
  volume('Total Volume', 'kg'),
  reps('Best Reps', 'reps');

  final String label;
  final String unit;
  const ProgressionMetric(this.label, this.unit);
}

/// An immutable progression data point representing a single completed historical session.
class ExerciseProgressionPoint {
  final DateTime date;
  final double topWeight;
  final int bestReps;
  final double totalVolume;
  final double estimatedOneRepMax;

  const ExerciseProgressionPoint({
    required this.date,
    required this.topWeight,
    required this.bestReps,
    required this.totalVolume,
    required this.estimatedOneRepMax,
  });

  double valueFor(ProgressionMetric metric) {
    return switch (metric) {
      ProgressionMetric.estimated1RM => estimatedOneRepMax,
      ProgressionMetric.topWeight => topWeight,
      ProgressionMetric.volume => totalVolume,
      ProgressionMetric.reps => bestReps.toDouble(),
    };
  }

  String formattedValueFor(ProgressionMetric metric) {
    return switch (metric) {
      ProgressionMetric.estimated1RM => '${estimatedOneRepMax.toStringAsFixed(1)} kg',
      ProgressionMetric.topWeight => '${topWeight.toStringAsFixed(topWeight == topWeight.truncateToDouble() ? 0 : 1)} kg',
      ProgressionMetric.volume => totalVolume >= 1000
          ? '${(totalVolume / 1000).toStringAsFixed(1)}k kg'
          : '${totalVolume.toStringAsFixed(0)} kg',
      ProgressionMetric.reps => '$bestReps reps',
    };
  }
}

/// Pure transformation extracting progression points from actual historical sessions only.
///
/// Rules:
/// - Only valid historical stored sessions (no current uncommitted sets).
/// - Skips skipped exercises (`entry.isSkipped`).
/// - Warm-up sets are excluded (`setType != SetType.warmUp`).
/// - Top Weight = highest valid working-set weight.
/// - Reps = representative/best working-set reps (reps on top weight working set).
/// - Volume = SUM of all valid working sets (weight × reps).
/// - Estimated 1RM = highest valid estimated 1RM for the session.
/// - Chronologically sorted (oldest -> newest).
List<ExerciseProgressionPoint> extractProgressionPoints(
    List<({DateTime date, ExerciseEntry entry})> history) {
  final points = <ExerciseProgressionPoint>[];

  for (final item in history) {
    final entry = item.entry;
    if (entry.isSkipped) continue;

    // Filter valid working sets (exclude warm-up sets and invalid 0-rep entries)
    final validWorkingSets = entry.sets.where((s) {
      if (s.setType == SetType.warmUp) return false;
      if (s.reps <= 0) return false;
      final effectiveWeight = s.externalLoadKg ?? s.weight;
      return effectiveWeight >= 0 || s.durationSeconds != null;
    }).toList();

    if (validWorkingSets.isEmpty) continue;

    // 1. Top Weight: highest valid working-set weight
    double maxWeight = 0.0;
    for (final s in validWorkingSets) {
      final w = s.externalLoadKg ?? s.weight;
      if (w > maxWeight) maxWeight = w;
    }

    // 2. Best Reps: reps performed on the top weight set (or max reps among top weight sets)
    final topWeightSets = validWorkingSets.where((s) {
      final w = s.externalLoadKg ?? s.weight;
      return w == maxWeight;
    }).toList();

    int maxReps = 0;
    if (topWeightSets.isNotEmpty) {
      for (final s in topWeightSets) {
        if (s.reps > maxReps) maxReps = s.reps;
      }
    } else {
      for (final s in validWorkingSets) {
        if (s.reps > maxReps) maxReps = s.reps;
      }
    }

    // 3. Volume: SUM of all valid working sets
    double sumVolume = 0.0;
    for (final s in validWorkingSets) {
      sumVolume += s.volume;
    }

    // 4. Estimated 1RM: highest valid estimated 1RM across working sets
    double maxE1RM = 0.0;
    for (final s in validWorkingSets) {
      final e1rm = s.estimatedOneRepMax;
      if (e1rm > maxE1RM) maxE1RM = e1rm;
    }

    if (maxWeight <= 0.0 && sumVolume <= 0.0 && maxReps <= 0 && maxE1RM <= 0.0) {
      continue;
    }

    points.add(ExerciseProgressionPoint(
      date: item.date,
      topWeight: maxWeight,
      bestReps: maxReps,
      totalVolume: sumVolume,
      estimatedOneRepMax: maxE1RM,
    ));
  }

  // Sort chronologically (oldest session first to newest last)
  points.sort((a, b) => a.date.compareTo(b.date));
  return points;
}

/// Compact, responsive progression graph widget for the workout hero area.
class ExerciseProgressionChart extends StatefulWidget {
  final List<({DateTime date, ExerciseEntry entry})> history;
  final String exerciseName;

  const ExerciseProgressionChart({
    super.key,
    required this.history,
    required this.exerciseName,
  });

  @override
  State<ExerciseProgressionChart> createState() => _ExerciseProgressionChartState();
}

class _ExerciseProgressionChartState extends State<ExerciseProgressionChart> {
  ProgressionMetric _selectedMetric = ProgressionMetric.estimated1RM;
  int? _hoveredIndex;

  // Memoized points based on history reference
  List<({DateTime date, ExerciseEntry entry})>? _lastHistoryRef;
  List<ExerciseProgressionPoint> _cachedPoints = const [];

  List<ExerciseProgressionPoint> get _points {
    if (!identical(_lastHistoryRef, widget.history)) {
      _lastHistoryRef = widget.history;
      _cachedPoints = extractProgressionPoints(widget.history);
    }
    return _cachedPoints;
  }

  @override
  Widget build(BuildContext context) {
    final points = _points;

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF13131C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: KColor.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Row with Title
          Row(
            children: [
              const Icon(Icons.show_chart_rounded, color: KColor.green, size: 16),
              const SizedBox(width: 6),
              const Text(
                'EXERCISE PROGRESSION',
                style: TextStyle(
                  color: KColor.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
              const Spacer(),
              if (points.length >= 2)
                Text(
                  '${points.length} sessions',
                  style: const TextStyle(
                    color: KColor.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
          if (points.length >= 2) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _buildMetricChip(ProgressionMetric.estimated1RM, '1RM'),
                  const SizedBox(width: 6),
                  _buildMetricChip(ProgressionMetric.topWeight, 'Weight'),
                  const SizedBox(width: 6),
                  _buildMetricChip(ProgressionMetric.volume, 'Volume'),
                  const SizedBox(width: 6),
                  _buildMetricChip(ProgressionMetric.reps, 'Reps'),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),

          // Content body based on number of stored points
          if (points.isEmpty)
            _buildEmptyState()
          else if (points.length == 1)
            _buildSinglePointState(points.first)
          else
            _buildChart(points),
        ],
      ),
    );
  }

  Widget _buildMetricChip(ProgressionMetric metric, String label) {
    final isSelected = _selectedMetric == metric;
    return GestureDetector(
      onTap: () {
        if (_selectedMetric != metric) {
          setState(() {
            _selectedMetric = metric;
            _hoveredIndex = null;
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? KColor.green.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? KColor.green : KColor.border.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? KColor.green : KColor.textSecondary,
            fontSize: 9.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      alignment: Alignment.center,
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_rounded, size: 14, color: KColor.textMuted),
          SizedBox(width: 6),
          Flexible(
            child: Text(
              'No previous history for this exercise.',
              style: TextStyle(color: KColor.textMuted, fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSinglePointState(ExerciseProgressionPoint point) {
    final dateStr = '${point.date.day}/${point.date.month}';
    final valStr = point.formattedValueFor(_selectedMetric);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: KColor.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: KColor.green.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.fiber_manual_record, color: KColor.green, size: 10),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '1 Previous Session ($dateStr): $valStr',
                  style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                const Text(
                  'Complete another session to plot trend.',
                  style: TextStyle(color: KColor.textSecondary, fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChart(List<ExerciseProgressionPoint> points) {
    final values = points.map((p) => p.valueFor(_selectedMetric)).toList();
    final delta = values.last - values.first;

    final firstDateStr = '${points.first.date.day}/${points.first.date.month}';
    final lastDateStr = '${points.last.date.day}/${points.last.date.month}';

    final activePoint = (_hoveredIndex != null && _hoveredIndex! < points.length)
        ? points[_hoveredIndex!]
        : points.last;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Summary bar: current selected value + change
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  activePoint.formattedValueFor(_selectedMetric),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '(${activePoint.date.day}/${activePoint.date.month})',
                  style: const TextStyle(color: KColor.textMuted, fontSize: 10),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: delta >= 0
                    ? KColor.green.withValues(alpha: 0.12)
                    : Colors.redAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                delta >= 0
                    ? '+${delta.toStringAsFixed(1)} ${_selectedMetric.unit}'
                    : '${delta.toStringAsFixed(1)} ${_selectedMetric.unit}',
                style: TextStyle(
                  color: delta >= 0 ? KColor.green : Colors.redAccent,
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Polyline Canvas
        SizedBox(
          height: 54,
          width: double.infinity,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                onPanDown: (details) => _handleTouch(details.localPosition.dx, constraints.maxWidth, points.length),
                onPanUpdate: (details) => _handleTouch(details.localPosition.dx, constraints.maxWidth, points.length),
                child: CustomPaint(
                  size: Size(constraints.maxWidth, 54),
                  painter: _ProgressionPolylinePainter(
                    points: points,
                    metric: _selectedMetric,
                    selectedIndex: _hoveredIndex ?? (points.length - 1),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),

        // Date bounds footer
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(firstDateStr, style: const TextStyle(color: KColor.textMuted, fontSize: 9)),
            Text(
              '${points.length} Sessions Trend',
              style: const TextStyle(color: KColor.textSecondary, fontSize: 9, fontWeight: FontWeight.w500),
            ),
            Text(lastDateStr, style: const TextStyle(color: KColor.textMuted, fontSize: 9)),
          ],
        ),
      ],
    );
  }

  void _handleTouch(double localX, double totalWidth, int count) {
    if (count <= 1 || totalWidth <= 0) return;
    final stepX = totalWidth / (count - 1);
    final index = (localX / stepX).round().clamp(0, count - 1);
    if (_hoveredIndex != index) {
      setState(() {
        _hoveredIndex = index;
      });
    }
  }
}

/// Custom painter rendering crisp, discrete polyline segments and distinct point markers.
/// No misleading spline smoothing that fabricates non-existent intermediate workouts.
class _ProgressionPolylinePainter extends CustomPainter {
  final List<ExerciseProgressionPoint> points;
  final ProgressionMetric metric;
  final int selectedIndex;

  _ProgressionPolylinePainter({
    required this.points,
    required this.metric,
    required this.selectedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final values = points.map((p) => p.valueFor(metric)).toList();
    final minVal = values.reduce(min);
    final maxVal = values.reduce(max);
    final range = maxVal == minVal ? 1.0 : (maxVal - minVal);

    // Padding bounds
    const topPad = 8.0;
    const bottomPad = 8.0;
    final usableHeight = size.height - topPad - bottomPad;

    // Grid lines (min and max reference levels)
    final gridPaint = Paint()
      ..color = const Color(0xFF222230)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawLine(Offset(0, topPad), Offset(size.width, topPad), gridPaint);
    canvas.drawLine(Offset(0, size.height - bottomPad), Offset(size.width, size.height - bottomPad), gridPaint);

    if (points.length == 1) {
      // Single center point
      final cy = size.height / 2;
      final cx = size.width / 2;
      canvas.drawCircle(Offset(cx, cy), 5, Paint()..color = KColor.green);
      return;
    }

    final stepX = size.width / (points.length - 1);

    // Calculate discrete points
    final offsets = <Offset>[];
    for (int i = 0; i < points.length; i++) {
      final x = i * stepX;
      final normalized = (values[i] - minVal) / range;
      final y = size.height - bottomPad - (normalized * usableHeight);
      offsets.add(Offset(x, y));
    }

    // Shaded gradient under polyline
    final fillPath = Path();
    fillPath.moveTo(offsets.first.dx, size.height);
    for (final pt in offsets) {
      fillPath.lineTo(pt.dx, pt.dy);
    }
    fillPath.lineTo(offsets.last.dx, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          KColor.green.withValues(alpha: 0.18),
          KColor.green.withValues(alpha: 0.0),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(fillPath, fillPaint);

    // Straight polyline connecting verified historical points
    final linePath = Path();
    linePath.moveTo(offsets.first.dx, offsets.first.dy);
    for (int i = 1; i < offsets.length; i++) {
      linePath.lineTo(offsets[i].dx, offsets[i].dy);
    }

    final linePaint = Paint()
      ..color = KColor.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(linePath, linePaint);

    // Point dots
    final dotPaint = Paint()..style = PaintingStyle.fill;
    final haloPaint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < offsets.length; i++) {
      final isSelected = i == selectedIndex;
      final pt = offsets[i];

      if (isSelected) {
        haloPaint.color = KColor.green.withValues(alpha: 0.3);
        canvas.drawCircle(pt, 7.0, haloPaint);

        dotPaint.color = Colors.white;
        canvas.drawCircle(pt, 3.8, dotPaint);

        final ringPaint = Paint()
          ..color = KColor.green
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        canvas.drawCircle(pt, 4.0, ringPaint);
      } else {
        dotPaint.color = KColor.green.withValues(alpha: 0.85);
        canvas.drawCircle(pt, 2.5, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ProgressionPolylinePainter oldDelegate) {
    return oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.metric != metric ||
        oldDelegate.points != points;
  }
}
