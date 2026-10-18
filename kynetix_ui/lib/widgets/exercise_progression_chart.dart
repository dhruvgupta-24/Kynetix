import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/workout_session.dart';

/// Available progression metrics to visualize.
enum ProgressionMetric {
  overall('Overall Progress', 'pts'),
  volume('Total Volume', 'kg'),
  topWeight('Top Weight', 'kg'),
  reps('Best Reps', 'reps'),
  estimated1RM('Estimated 1RM', 'kg');

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
  final double overallScore;

  const ExerciseProgressionPoint({
    required this.date,
    required this.topWeight,
    required this.bestReps,
    required this.totalVolume,
    required this.estimatedOneRepMax,
    this.overallScore = 100.0,
  });

  ExerciseProgressionPoint copyWith({
    DateTime? date,
    double? topWeight,
    int? bestReps,
    double? totalVolume,
    double? estimatedOneRepMax,
    double? overallScore,
  }) {
    return ExerciseProgressionPoint(
      date: date ?? this.date,
      topWeight: topWeight ?? this.topWeight,
      bestReps: bestReps ?? this.bestReps,
      totalVolume: totalVolume ?? this.totalVolume,
      estimatedOneRepMax: estimatedOneRepMax ?? this.estimatedOneRepMax,
      overallScore: overallScore ?? this.overallScore,
    );
  }

  double valueFor(ProgressionMetric metric) {
    return switch (metric) {
      ProgressionMetric.overall => overallScore,
      ProgressionMetric.volume => totalVolume,
      ProgressionMetric.topWeight => topWeight,
      ProgressionMetric.reps => bestReps.toDouble(),
      ProgressionMetric.estimated1RM => estimatedOneRepMax,
    };
  }

  String formattedValueFor(ProgressionMetric metric) {
    return switch (metric) {
      ProgressionMetric.overall => '${overallScore.toStringAsFixed(1)} pts',
      ProgressionMetric.volume =>
        totalVolume >= 1000
            ? '${(totalVolume / 1000).toStringAsFixed(1)}k kg'
            : '${totalVolume.toStringAsFixed(0)} kg',
      ProgressionMetric.topWeight =>
        '${topWeight.toStringAsFixed(topWeight == topWeight.truncateToDouble() ? 0 : 1)} kg',
      ProgressionMetric.reps => '$bestReps reps',
      ProgressionMetric.estimated1RM =>
        '${estimatedOneRepMax.toStringAsFixed(1)} kg',
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
/// - Overall Progress = relative index (100 baseline at oldest session) derived from historical 1RM and Volume.
List<ExerciseProgressionPoint> extractProgressionPoints(
  List<({DateTime date, ExerciseEntry entry})> history,
) {
  final rawPoints = <ExerciseProgressionPoint>[];

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

    if (maxWeight <= 0.0 &&
        sumVolume <= 0.0 &&
        maxReps <= 0 &&
        maxE1RM <= 0.0) {
      continue;
    }

    rawPoints.add(
      ExerciseProgressionPoint(
        date: item.date,
        topWeight: maxWeight,
        bestReps: maxReps,
        totalVolume: sumVolume,
        estimatedOneRepMax: maxE1RM,
      ),
    );
  }

  // Sort chronologically (oldest session first to newest last)
  rawPoints.sort((a, b) => a.date.compareTo(b.date));
  if (rawPoints.isEmpty) return const [];

  // Compute Overall composite progression index relative to oldest session (100.0 baseline).
  // Formula Specification:
  // - Baseline: Oldest valid chronological historical point = 100.0 pts.
  // - Primary Composite: 60% Strength (1RM ratio) + 40% Work Capacity (Volume ratio), scaled by 100:
  //     Score = 100.0 * (0.6 * (1RM / base_1RM) + 0.4 * (Volume / base_Volume))
  // - Deterministic Fallbacks for missing/zero baseline components:
  //     1. base_1RM > 0 and base_Volume > 0: 60/40 (1RM / base_1RM) + (Volume / base_Volume)
  //     2. base_1RM > 0 only: 100.0 * (1RM / base_1RM)
  //     3. base_Volume > 0 only: 100.0 * (Volume / base_Volume)
  //     4. base_Weight > 0 and base_Reps > 0: 60/40 (Weight / base_Weight) + (Reps / base_Reps)
  //     5. base_Weight > 0 only: 100.0 * (Weight / base_Weight)
  //     6. base_Reps > 0 only: 100.0 * (Reps / base_Reps)
  //     7. Otherwise: 100.0 (neutral baseline)
  // - Historical purity: Computed exclusively from completed historical sessions. Uncommitted
  //   current session data is never passed to extractProgressionPoints.
  final base = rawPoints.first;
  final baseE1rm = base.estimatedOneRepMax;
  final baseVol = base.totalVolume;
  final baseWeight = base.topWeight;
  final baseReps = base.bestReps;

  final points = <ExerciseProgressionPoint>[];
  for (int i = 0; i < rawPoints.length; i++) {
    final pt = rawPoints[i];
    if (i == 0) {
      points.add(pt.copyWith(overallScore: 100.0));
    } else {
      double score;
      if (baseE1rm > 0 && baseVol > 0) {
        final strengthRatio = pt.estimatedOneRepMax / baseE1rm;
        final volRatio = pt.totalVolume / baseVol;
        score = 100.0 * (0.6 * strengthRatio + 0.4 * volRatio);
      } else if (baseE1rm > 0) {
        score = 100.0 * (pt.estimatedOneRepMax / baseE1rm);
      } else if (baseVol > 0) {
        score = 100.0 * (pt.totalVolume / baseVol);
      } else if (baseWeight > 0 && baseReps > 0) {
        final weightRatio = pt.topWeight / baseWeight;
        final repsRatio = pt.bestReps / baseReps;
        score = 100.0 * (0.6 * weightRatio + 0.4 * repsRatio);
      } else if (baseWeight > 0) {
        score = 100.0 * (pt.topWeight / baseWeight);
      } else if (baseReps > 0) {
        score = 100.0 * (pt.bestReps / baseReps);
      } else {
        score = 100.0;
      }
      points.add(pt.copyWith(overallScore: score));
    }
  }

  return points;
}

/// Compact, responsive progression graph widget for the workout hero area.
///
/// Train world (violet → cyan). The polyline draws in once on first show via a
/// path-length reveal driven by an [AnimationController] passed to the painter
/// as `repaint:`, so the reveal never rebuilds the widget tree. Touching the
/// plot scrubs the summary read-out above it.
class ExerciseProgressionChart extends StatefulWidget {
  final List<({DateTime date, ExerciseEntry entry})> history;
  final String exerciseName;

  const ExerciseProgressionChart({
    super.key,
    required this.history,
    required this.exerciseName,
  });

  @override
  State<ExerciseProgressionChart> createState() =>
      _ExerciseProgressionChartState();
}

class _ExerciseProgressionChartState extends State<ExerciseProgressionChart>
    with SingleTickerProviderStateMixin {
  ProgressionMetric _selectedMetric = ProgressionMetric.overall;
  int? _hoveredIndex;

  late final AnimationController _reveal;
  bool _revealStarted = false;

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
  void initState() {
    super.initState();
    _reveal = AnimationController(vsync: this, duration: KMotion.slow);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeStartReveal();
  }

  @override
  void didUpdateWidget(covariant ExerciseProgressionChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeStartReveal();
  }

  /// Plays the draw-in exactly once, the first time a plottable chart exists.
  /// Under reduced motion it cuts straight to the end state.
  void _maybeStartReveal() {
    if (_revealStarted || _points.length < 2) return;
    _revealStarted = true;
    final d = KMotion.of(context, KMotion.slow);
    if (d == Duration.zero) {
      _reveal.value = 1;
    } else {
      _reveal.duration = d;
      _reveal.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final points = _points;

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(
        KSpacing.md,
        KSpacing.md,
        KSpacing.md,
        10,
      ),
      // A recessed well: the page tone sunk into the card, hairline edge.
      decoration: BoxDecoration(
        color: KColor.isDark ? KColor.bg.withValues(alpha: 0.6) : KColor.bg,
        borderRadius: KRadius.md,
        border: Border.all(
          color: KColor.fg.withValues(alpha: KColor.isDark ? 0.07 : 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Row with Title
          Row(
            children: [
              const ExcludeSemantics(
                child: _TrainGlyph(icon: Icons.show_chart_rounded),
              ),
              const SizedBox(width: KSpacing.sm),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    'Exercise progression',
                    style: KText.label.copyWith(
                      fontSize: 13,
                      color: KColor.textPrimary,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
              if (points.length >= 2)
                Text(
                  plural(points.length, 'session'),
                  style: KText.caption.copyWith(
                    fontSize: 11,
                    color: KColor.textMuted,
                    fontFeatures: _tabular,
                  ),
                ),
            ],
          ),
          if (points.length >= 2) ...[
            const SizedBox(height: KSpacing.xs),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _buildMetricChip(ProgressionMetric.overall, 'Overall'),
                  const SizedBox(width: 6),
                  _buildMetricChip(ProgressionMetric.volume, 'Volume'),
                  const SizedBox(width: 6),
                  _buildMetricChip(ProgressionMetric.topWeight, 'Weight'),
                  const SizedBox(width: 6),
                  _buildMetricChip(ProgressionMetric.reps, 'Reps'),
                  const SizedBox(width: 6),
                  _buildMetricChip(ProgressionMetric.estimated1RM, '1RM'),
                ],
              ),
            ),
          ],
          const SizedBox(height: KSpacing.xs),

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

  static const _tabular = [FontFeature.tabularFigures()];

  Widget _buildMetricChip(ProgressionMetric metric, String label) {
    final isSelected = _selectedMetric == metric;
    return Semantics(
      button: true,
      selected: isSelected,
      label: '$label metric',
      excludeSemantics: true,
      child: Pressable(
        scale: 0.94,
        borderRadius: KRadius.pill,
        onTap: () {
          if (_selectedMetric != metric) {
            KHaptics.select();
            setState(() {
              _selectedMetric = metric;
              _hoveredIndex = null;
            });
          }
        },
        // 48dp hit area around a compact 32dp visual pill.
        child: SizedBox(
          height: 48,
          child: Center(
            child: AnimatedContainer(
              duration: KMotion.of(context, KMotion.quick),
              curve: KMotion.emphasizedCurve,
              alignment: Alignment.center,
              constraints: const BoxConstraints(minHeight: 32),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? KColor.ink
                    : KColor.fg.withValues(alpha: KColor.isDark ? 0.04 : 0.035),
                borderRadius: KRadius.pill,
                border: Border.all(
                  color: isSelected
                      ? KColor.ink
                      : KColor.fg.withValues(alpha: KColor.isDark ? 0.09 : 0.1),
                ),
              ),
              child: Text(
                label,
                style: KText.caption.copyWith(
                  fontSize: 12,
                  color: isSelected ? KColor.onInk : KColor.textSecondary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ExcludeSemantics(
            child: Icon(
              Icons.history_rounded,
              size: 14,
              color: KColor.textMuted,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'No previous history for this exercise.',
              style: KText.caption.copyWith(
                fontSize: 12,
                color: KColor.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSinglePointState(ExerciseProgressionPoint point) {
    final dateStr = '${point.date.day}/${point.date.month}';
    final valStr = point.formattedValueFor(_selectedMetric);
    final isOverall = _selectedMetric == ProgressionMetric.overall;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: KColor.card.withValues(alpha: KColor.isDark ? 0.6 : 1),
        borderRadius: KRadius.sm,
        border: Border.all(
          color: KColor.fg.withValues(alpha: KColor.isDark ? 0.06 : 0.08),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: KColor.violet.withValues(alpha: KColor.isDark ? 0.16 : 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.fiber_manual_record,
                color: KColor.violet,
                size: 9,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isOverall
                      ? 'Last session ($dateStr): $valStr · your baseline'
                      : 'Last session ($dateStr): $valStr',
                  style: KText.caption.copyWith(
                    fontSize: 12.5,
                    color: KColor.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontFeatures: _tabular,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isOverall
                      ? '100 is where you started. One more session and the trend shows up.'
                      : 'One more session and the trend shows up.',
                  style: KText.caption.copyWith(
                    fontSize: 11.5,
                    color: KColor.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChart(List<ExerciseProgressionPoint> points) {
    final values = points
        .map((p) => p.valueFor(_selectedMetric))
        .toList(growable: false);
    final delta = values.last - values.first;
    final up = delta >= 0;

    final firstDateStr = '${points.first.date.day}/${points.first.date.month}';
    final lastDateStr = '${points.last.date.day}/${points.last.date.month}';

    final activePoint =
        (_hoveredIndex != null && _hoveredIndex! < points.length)
        ? points[_hoveredIndex!]
        : points.last;

    var lo = values.first;
    var hi = values.first;
    for (final v in values) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }

    final scene = _PolylineScene(
      values: values,
      selectedIndex: _hoveredIndex ?? (points.length - 1),
      scrubbing: _hoveredIndex != null,
      hairline: 1.0 / MediaQuery.devicePixelRatioOf(context),
      dark: KColor.isDark,
    );

    // A dip is information, not a failure: it reads in neutral ink with a
    // down arrow; only a gain earns the success colour.
    final deltaColor = up ? KColor.green : KColor.textSecondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Scrub read-out: current / touched value + overall change.
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: 6,
                runSpacing: 2,
                children: [
                  AnimatedSwitcher(
                    duration: KMotion.of(context, KMotion.quick),
                    switchInCurve: KMotion.emphasizedCurve,
                    switchOutCurve: KMotion.accelerate,
                    child: Text(
                      activePoint.formattedValueFor(_selectedMetric),
                      key: ValueKey(
                        activePoint.formattedValueFor(_selectedMetric),
                      ),
                      style: KText.numMedium.copyWith(fontSize: 20),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      '(${activePoint.date.day}/${activePoint.date.month})',
                      style: KText.caption.copyWith(
                        fontSize: 11,
                        color: KColor.textMuted,
                        fontFeatures: _tabular,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: KSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: deltaColor.withValues(alpha: KColor.isDark ? 0.12 : 0.09),
                borderRadius: KRadius.pill,
                border: Border.all(color: deltaColor.withValues(alpha: 0.25)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExcludeSemantics(
                    child: Icon(
                      up
                          ? Icons.trending_up_rounded
                          : Icons.trending_down_rounded,
                      size: 12,
                      color: deltaColor,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    up
                        ? '+${delta.toStringAsFixed(1)} ${_selectedMetric.unit}'
                        : '${delta.toStringAsFixed(1)} ${_selectedMetric.unit}',
                    style: KText.numSmall.copyWith(
                      fontSize: 11.5,
                      color: deltaColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: KSpacing.sm),

        // Plot + y-axis labels (max on top, min at the bottom).
        SizedBox(
          height: 72,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final geo = _PlotGeometry(
                      constraints.maxWidth,
                      values.length,
                    );
                    return Semantics(
                      label:
                          '${_selectedMetric.label}: '
                          '${points.first.formattedValueFor(_selectedMetric)} on $firstDateStr, '
                          '${points.last.formattedValueFor(_selectedMetric)} on $lastDateStr, '
                          '${plural(points.length, 'session')}',
                      child: ExcludeSemantics(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanDown: (details) => _handleTouch(
                            geo.indexAt(details.localPosition.dx),
                          ),
                          onPanUpdate: (details) => _handleTouch(
                            geo.indexAt(details.localPosition.dx),
                          ),
                          child: RepaintBoundary(
                            child: CustomPaint(
                              size: Size(constraints.maxWidth, 72),
                              isComplex: true,
                              painter: _ProgressionPolylinePainter(
                                scene: scene,
                                reveal: _reveal,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 6),
              ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _compact(hi),
                      style: KText.numSmall.copyWith(
                        fontSize: 10.5,
                        color: KColor.textSecondary,
                      ),
                    ),
                    Text(
                      _compact(lo),
                      style: KText.numSmall.copyWith(
                        fontSize: 10.5,
                        color: KColor.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),

        // Date bounds footer (x-axis labels)
        Row(
          children: [
            Text(
              firstDateStr,
              style: KText.caption.copyWith(
                fontSize: 10.5,
                color: KColor.textSecondary,
                fontFeatures: _tabular,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                _selectedMetric == ProgressionMetric.overall
                    ? '${plural(points.length, 'session')}, 100 = baseline'
                    : '${points.length}-session trend',
                textAlign: TextAlign.center,
                style: KText.caption.copyWith(
                  fontSize: 10.5,
                  color: KColor.textMuted,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              lastDateStr,
              style: KText.caption.copyWith(
                fontSize: 10.5,
                color: KColor.textSecondary,
                fontFeatures: _tabular,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _compact(double v) {
    if (v.abs() >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v == v.truncateToDouble()
        ? v.toStringAsFixed(0)
        : v.toStringAsFixed(1);
  }

  void _handleTouch(int? index) {
    if (index == null) return;
    if (_hoveredIndex != index) {
      KHaptics.select();
      setState(() {
        _hoveredIndex = index;
      });
    }
  }
}

/// Small gradient glyph used as the chart's leading icon.
class _TrainGlyph extends StatelessWidget {
  const _TrainGlyph({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            KColor.violet.withValues(alpha: KColor.isDark ? 0.2 : 0.12),
            KColor.cyan.withValues(alpha: KColor.isDark ? 0.1 : 0.06),
          ],
        ),
      ),
      child: Icon(icon, color: KColor.violet, size: 14),
    );
  }
}

/// The ONE mapping between point index and canvas x, read by both the painter
/// and the touch handler so they can never disagree.
@immutable
class _PlotGeometry {
  const _PlotGeometry(this.width, this.count);
  final double width;
  final int count;

  static const double inset = 6.0;

  double get _step => count <= 1 ? 0 : (width - 2 * inset) / (count - 1);

  double xFor(int i) => count <= 1 ? width / 2 : inset + i * _step;

  int? indexAt(double dx) {
    if (count <= 1 || width <= 2 * inset) return null;
    return ((dx - inset) / _step).round().clamp(0, count - 1);
  }
}

/// Everything the polyline painter needs, with value equality so
/// `shouldRepaint` is a single compare.
@immutable
class _PolylineScene {
  const _PolylineScene({
    required this.values,
    required this.selectedIndex,
    required this.scrubbing,
    required this.hairline,
    required this.dark,
  });

  final List<double> values;
  final int selectedIndex;
  final bool scrubbing;
  final double hairline;

  /// Active palette; part of equality so a theme switch repaints.
  final bool dark;

  @override
  bool operator ==(Object other) =>
      other is _PolylineScene &&
      other.selectedIndex == selectedIndex &&
      other.scrubbing == scrubbing &&
      other.hairline == hairline &&
      other.dark == dark &&
      listEquals(other.values, values);

  @override
  int get hashCode =>
      Object.hash(
        selectedIndex, scrubbing, hairline, dark, Object.hashAll(values),
      );
}

/// Custom painter rendering crisp, discrete polyline segments and distinct point markers.
/// No misleading spline smoothing that fabricates non-existent intermediate workouts.
class _ProgressionPolylinePainter extends CustomPainter {
  _ProgressionPolylinePainter({required this.scene, required this.reveal})
    : super(repaint: reveal);

  final _PolylineScene scene;
  final Animation<double> reveal;

  static const double _topPad = 8.0;
  static const double _bottomPad = 8.0;

  // Paints are fields — nothing hoistable is allocated per frame.
  final Paint _grid = Paint()..style = PaintingStyle.stroke;
  final Paint _fill = Paint()..style = PaintingStyle.fill;
  final Paint _line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final Paint _dot = Paint()..style = PaintingStyle.fill;
  final Paint _ring = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0
    ..color = KColor.cyan;

  // Geometry cached per size; this painter instance lives for one scene and is
  // repainted per animation frame through `repaint:`.
  Size? _cachedSize;
  List<Offset> _offsets = const [];
  Path _linePath = Path();
  Path _areaPath = Path();
  ui.PathMetric? _metric;
  List<double> _gridYs = const [];

  void _layout(Size size) {
    if (_cachedSize == size) return;
    _cachedSize = size;
    final values = scene.values;
    var lo = values.first;
    var hi = values.first;
    for (final v in values) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    final range = hi == lo ? 1.0 : (hi - lo);
    final usable = size.height - _topPad - _bottomPad;
    final geo = _PlotGeometry(size.width, values.length);
    _offsets = [
      for (var i = 0; i < values.length; i++)
        Offset(
          geo.xFor(i),
          hi == lo
              ? size.height / 2
              : size.height - _bottomPad - ((values[i] - lo) / range) * usable,
        ),
    ];
    _gridYs = [_topPad, size.height / 2, size.height - _bottomPad];
    _linePath = Path()..moveTo(_offsets.first.dx, _offsets.first.dy);
    for (var i = 1; i < _offsets.length; i++) {
      _linePath.lineTo(_offsets[i].dx, _offsets[i].dy);
    }
    _areaPath = Path.from(_linePath)
      ..lineTo(_offsets.last.dx, size.height)
      ..lineTo(_offsets.first.dx, size.height)
      ..close();
    final metrics = _linePath.computeMetrics().toList();
    _metric = metrics.isEmpty ? null : metrics.first;

    final rect = Offset.zero & size;
    _line.shader = LinearGradient(
      colors: KGradient.train,
    ).createShader(rect);
    _fill.shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        KColor.violet.withValues(alpha: scene.dark ? 0.24 : 0.14),
        KColor.cyan.withValues(alpha: 0.0),
      ],
    ).createShader(rect);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (scene.values.isEmpty || size.width <= 0) return;
    _layout(size);

    // Hairline grid: max, mid, min reference levels.
    _grid
      ..strokeWidth = scene.hairline
      ..color = KColor.fg.withValues(alpha: scene.dark ? 0.08 : 0.1);
    for (final y in _gridYs) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), _grid);
    }

    if (_offsets.length == 1) {
      _dot.color = KColor.violet;
      canvas.drawCircle(_offsets.first, 5, _dot);
      return;
    }

    final metric = _metric;
    if (metric == null) return;
    final t = KMotion.emphasizedCurve.transform(reveal.value.clamp(0.0, 1.0));
    final done = t >= 1.0;
    final len = metric.length * t;
    final tipX = done
        ? size.width
        : (metric.getTangentForOffset(len)?.position.dx ?? size.width);

    // Area fill revealed in lock-step with the line tip.
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, tipX + 0.5, size.height));
    canvas.drawPath(_areaPath, _fill);
    canvas.restore();

    canvas.drawPath(done ? _linePath : metric.extractPath(0, len), _line);

    // Scrub crosshair (only while the user is touching).
    final sel = scene.selectedIndex.clamp(0, _offsets.length - 1);
    if (scene.scrubbing && done) {
      _grid
        ..strokeWidth = 1.0
        ..color = KColor.fg.withValues(alpha: scene.dark ? 0.22 : 0.26);
      canvas.drawLine(
        Offset(_offsets[sel].dx, 0),
        Offset(_offsets[sel].dx, size.height),
        _grid,
      );
    }

    // Point markers appear as the line reaches them.
    for (var i = 0; i < _offsets.length; i++) {
      final pt = _offsets[i];
      if (pt.dx > tipX + 0.5) break;
      if (i == sel) {
        _dot.color = KColor.cyan.withValues(alpha: scene.dark ? 0.28 : 0.18);
        canvas.drawCircle(pt, 7.5, _dot);
        _dot.color = KColor.textPrimary;
        canvas.drawCircle(pt, 3.6, _dot);
        canvas.drawCircle(pt, 4.2, _ring);
      } else {
        _dot.color = KColor.bg;
        canvas.drawCircle(pt, 3.4, _dot);
        _dot.color = Color.lerp(
          KColor.violet,
          KColor.cyan,
          pt.dx / size.width,
        )!;
        canvas.drawCircle(pt, 2.3, _dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ProgressionPolylinePainter oldDelegate) =>
      oldDelegate.scene != scene;
}
