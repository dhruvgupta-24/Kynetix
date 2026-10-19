import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/day_log.dart';
import '../models/day_status.dart';
import '../screens/day_detail_screen.dart';
import '../services/persistence_service.dart';

// ─── Consistency heatmap ──────────────────────────────────────────────────────
// The last sixteen weeks as a grid: one column per week (Monday on top), one
// square per day. Empty days sit on the track, logged days are a soft brass,
// days that met the calorie target are full brass, today wears an ink ring.
// The whole grid is one CustomPainter; taps resolve by position through the
// same geometry the painter used, and open that day.

const _kMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// One immutable snapshot of the grid: which day sits in each cell and how
/// it went. Built from the logs, never mutated; the painter just reads it.
@immutable
class ConsistencyScene {
  const ConsistencyScene._({
    required this.start,
    required this.today,
    required this.marks,
    required this.loggedDays,
    required this.streak,
  });

  static const weeks = 16;

  /// Monday of the first (leftmost) column.
  final DateTime start;
  final DateTime today;

  /// Column-major, `weeks * 7` long. Null for days after today.
  final List<DayMark?> marks;
  final int loggedDays;
  final int streak;

  /// The grid ending in the week of [today], read through [markOf].
  factory ConsistencyScene.build(DateTime today, DayMark Function(DateTime day) markOf) {
    final t = DateUtils.dateOnly(today);
    final thisMonday = DateTime(t.year, t.month, t.day - (t.weekday - 1));
    final start = DateTime(thisMonday.year, thisMonday.month, thisMonday.day - (weeks - 1) * 7);
    final marks = List<DayMark?>.filled(weeks * 7, null);
    var logged = 0;
    for (var i = 0; i < weeks * 7; i++) {
      final day = DateTime(start.year, start.month, start.day + i);
      if (day.isAfter(t)) continue;
      final m = markOf(day);
      marks[i] = m;
      if (m != DayMark.none) logged++;
    }
    // Streak: consecutive logged days ending today, or yesterday while today
    // is still open. Counted inside the grid's window.
    var i = _daysBetween(start, t);
    if (i >= 0 && marks[i] == DayMark.none) i--;
    var streak = 0;
    while (i >= 0 && marks[i] != null && marks[i] != DayMark.none) {
      streak++;
      i--;
    }
    return ConsistencyScene._(start: start, today: t, marks: marks, loggedDays: logged, streak: streak);
  }

  DateTime dayAt(int col, int row) => DateTime(start.year, start.month, start.day + col * 7 + row);

  DayMark? markAt(int col, int row) => marks[col * 7 + row];

  /// Whole calendar days from [a] to [b], immune to DST (a local
  /// difference across a clock change is an hour short of whole days).
  static int _daysBetween(DateTime a, DateTime b) =>
      DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

  int get todayCol => _daysBetween(start, today) ~/ 7;
  int get todayRow => today.weekday - 1;

  /// "23 days logged in the last 16 weeks · 5 day streak".
  String get summary {
    final days = loggedDays == 1 ? '1 day' : '$loggedDays days';
    final base = '$days logged in the last $weeks weeks';
    return streak > 0 ? '$base · $streak day streak' : base;
  }
}

/// Cell layout shared by the painter and the hit test, so a tap always lands
/// on the square that was drawn there.
@immutable
class ConsistencyGeometry {
  const ConsistencyGeometry({required this.origin, required this.cell, this.gap = 3});

  /// Top left of cell (0, 0).
  final Offset origin;
  final double cell;
  final double gap;

  double get pitch => cell + gap;

  Rect rectFor(int col, int row) =>
      Rect.fromLTWH(origin.dx + col * pitch, origin.dy + row * pitch, cell, cell);

  Size get gridSize => Size(
        ConsistencyScene.weeks * pitch - gap,
        7 * pitch - gap,
      );

  /// The cell under [p], with the gap counted as part of the cell before it
  /// so there are no dead strips between squares. Null outside the grid.
  (int, int)? cellAt(Offset p) {
    final x = p.dx - origin.dx + gap / 2;
    final y = p.dy - origin.dy + gap / 2;
    if (x < 0 || y < 0) return null;
    final col = (x / pitch).floor();
    final row = (y / pitch).floor();
    if (col >= ConsistencyScene.weeks || row >= 7) return null;
    return (col, row);
  }
}

class ConsistencyHeatmap extends StatefulWidget {
  const ConsistencyHeatmap({super.key, required this.avgTarget});

  /// Average daily calorie target; a day at 88% or more counts as met.
  final double avgTarget;

  @override
  State<ConsistencyHeatmap> createState() => _ConsistencyHeatmapState();
}

class _ConsistencyHeatmapState extends State<ConsistencyHeatmap> with SingleTickerProviderStateMixin {
  /// The fill-in plays once per app session, the first time the grid shows.
  static bool _played = false;

  late final AnimationController _fill = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
    value: _played ? 1 : 0,
  );

  ConsistencyScene? _scene;
  Object? _sceneKey;
  ConsistencyLabels? _labels;
  Object? _labelsKey;

  @override
  void initState() {
    super.initState();
    PersistenceService.dayLogNotifier.addListener(_onLogs);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Wait until the tab is actually on screen (the shell keeps it alive
    // with tickers muted), then play once.
    if (_fill.value == 1 || _fill.isAnimating || !TickerMode.valuesOf(context).enabled) return;
    if (KMotion.reduced(context)) {
      _fill.value = 1;
    } else {
      _fill.forward();
    }
    _played = true;
  }

  @override
  void dispose() {
    PersistenceService.dayLogNotifier.removeListener(_onLogs);
    _labels?.dispose();
    _fill.dispose();
    super.dispose();
  }

  void _onLogs() {
    if (mounted) setState(() => _sceneKey = null);
  }

  ConsistencyScene _currentScene() {
    final today = DateUtils.dateOnly(DateTime.now());
    final key = (PersistenceService.dayLogNotifier.value, widget.avgTarget, today);
    if (_scene == null || _sceneKey != key) {
      final marks = DayMarks(widget.avgTarget);
      _scene = ConsistencyScene.build(today, (d) => marks.of(dateKey(d)));
      _sceneKey = key;
    }
    return _scene!;
  }

  ConsistencyLabels _currentLabels(ConsistencyScene scene, TextStyle style, TextScaler scaler) {
    final key = (scene, style, scaler);
    if (_labels == null || _labelsKey != key) {
      _labels?.dispose();
      _labels = ConsistencyLabels(scene, style, scaler);
      _labelsKey = key;
    }
    return _labels!;
  }

  void _open(DateTime day) {
    KHaptics.commit();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => DayDetailScreen(date: day)));
  }

  @override
  Widget build(BuildContext context) {
    final scene = _currentScene();
    final labels = _currentLabels(
      scene,
      KText.caption.copyWith(fontSize: 10, height: 1.0, color: KColor.textMuted),
      MediaQuery.textScalerOf(context),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Spoken once, by the grid's label below.
        ExcludeSemantics(
          child: Text(scene.summary, style: KText.caption.copyWith(fontSize: 12.5, color: KColor.textSecondary)),
        ),
        const SizedBox(height: KSpacing.md),
        LayoutBuilder(
          builder: (context, box) {
            final left = labels.weekdayWidth + 6;
            final top = labels.monthHeight + 5;
            const gap = 3.0;
            final cell = ((box.maxWidth - left - (ConsistencyScene.weeks - 1) * gap) / ConsistencyScene.weeks)
                .clamp(7.0, 18.0);
            final geo = ConsistencyGeometry(origin: Offset(left, top), cell: cell, gap: gap);
            final size = Size(left + geo.gridSize.width, top + geo.gridSize.height);
            return Semantics(
              label: 'Consistency, ${scene.summary.replaceAll(' · ', ', ')}',
              child: ExcludeSemantics(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) {
                    final hit = geo.cellAt(d.localPosition);
                    if (hit == null) return;
                    final (col, row) = hit;
                    if (scene.markAt(col, row) == null) return; // a day still to come
                    _open(scene.dayAt(col, row));
                  },
                  child: RepaintBoundary(
                    child: CustomPaint(
                      size: size,
                      painter: ConsistencyPainter(
                        scene: scene,
                        geometry: geo,
                        labels: labels,
                        progress: _fill,
                        track: KColor.track,
                        fill: KColor.goal,
                        ring: KColor.ink,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Month and weekday labels, laid out once per scene and theme.
class ConsistencyLabels {
  ConsistencyLabels(ConsistencyScene scene, TextStyle style, TextScaler scaler) {
    TextPainter tp(String s) =>
        TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr, textScaler: scaler)
          ..layout();
    for (final (row, s) in const [(0, 'M'), (2, 'W'), (4, 'F')]) {
      weekdays.add((row, tp(s)));
    }
    // A month label sits over the first column whose Monday falls in a new
    // month. The first column only gets one if the next label is far enough
    // away not to collide.
    final cols = <(int, int)>[];
    for (var c = 0; c < ConsistencyScene.weeks; c++) {
      final m = scene.dayAt(c, 0).month;
      if (c == 0 || m != scene.dayAt(c - 1, 0).month) cols.add((c, m));
    }
    if (cols.length > 1 && cols[1].$1 < 3) cols.removeAt(0);
    for (final (c, m) in cols) {
      months.add((c, tp(_kMonths[m - 1])));
    }
    weekdayWidth = weekdays.fold(0.0, (w, e) => math.max(w, e.$2.width));
    monthHeight = months.isEmpty ? 0 : months.first.$2.height;
  }

  final List<(int, TextPainter)> weekdays = [];
  final List<(int, TextPainter)> months = [];
  late final double weekdayWidth;
  late final double monthHeight;

  void dispose() {
    for (final (_, tp) in [...weekdays, ...months]) {
      tp.dispose();
    }
  }
}

class ConsistencyPainter extends CustomPainter {
  ConsistencyPainter({
    required this.scene,
    required this.geometry,
    required this.progress,
    required this.track,
    required this.fill,
    required this.ring,
    this.labels,
  }) : super(repaint: progress);

  final ConsistencyScene scene;
  final ConsistencyGeometry geometry;
  final Animation<double> progress;
  final Color track, fill, ring;
  final ConsistencyLabels? labels;

  final Paint _fill = Paint();
  final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;

  static const _span = (ConsistencyScene.weeks - 1) + 6;

  @override
  void paint(Canvas canvas, Size size) {
    final labels = this.labels;
    if (labels != null) {
      final pitch = geometry.pitch;
      for (final (c, tp) in labels.months) {
        tp.paint(canvas, Offset(geometry.origin.dx + c * pitch, 0));
      }
      for (final (r, tp) in labels.weekdays) {
        final y = geometry.origin.dy + r * pitch + (geometry.cell - tp.height) / 2;
        tp.paint(canvas, Offset(0, y));
      }
    }

    final p = progress.value;
    final radius = Radius.circular(math.min(3.0, geometry.cell / 4));
    final soft = fill.withValues(alpha: 0.38);
    for (var c = 0; c < ConsistencyScene.weeks; c++) {
      for (var r = 0; r < 7; r++) {
        final mark = scene.markAt(c, r);
        if (mark == null) continue; // days still to come stay blank
        // Diagonal stagger: top left first, bottom right last. Each cell
        // takes the last 40% of the timeline from its start.
        var t = 1.0;
        if (p < 1) {
          final begin = (c + r) / _span * 0.6;
          t = ((p - begin) / 0.4).clamp(0.0, 1.0);
          if (t == 0) continue;
        }
        final base = switch (mark) {
          DayMark.none => track,
          DayMark.logged => soft,
          DayMark.completed => fill,
        };
        final rect = geometry.rectFor(c, r);
        final scale = 0.6 + 0.4 * KMotion.easeOut.transform(t);
        final cellRect = scale == 1
            ? rect
            : Rect.fromCenter(center: rect.center, width: rect.width * scale, height: rect.height * scale);
        _fill.color = t == 1 ? base : base.withValues(alpha: base.a * t);
        canvas.drawRRect(RRect.fromRectAndRadius(cellRect, radius), _fill);
        if (c == scene.todayCol && r == scene.todayRow) {
          _stroke.color = t == 1 ? ring : ring.withValues(alpha: ring.a * t);
          canvas.drawRRect(RRect.fromRectAndRadius(cellRect.deflate(0.75), radius), _stroke);
        }
      }
    }
  }

  @override
  bool shouldRepaint(ConsistencyPainter old) =>
      !identical(old.scene, scene) ||
      old.geometry.origin != geometry.origin ||
      old.geometry.cell != geometry.cell ||
      old.track != track ||
      old.fill != fill ||
      old.ring != ring ||
      !identical(old.labels, labels);
}
