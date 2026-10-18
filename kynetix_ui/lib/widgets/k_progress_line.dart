import 'package:flutter/material.dart';

import '../config/app_theme.dart';

// Moment declaration: honest wait
//   trigger: a request with a known rough duration starts (AI estimate, 3-8 s)
//   change:  a thin ticked line fills in ink, quickly at first, then easing
//            toward ~90% over the expected wait; it never claims to be done
//   on done: it closes the last stretch in ~320 ms, then calls onCompleted
//            so the caller can swap the result in
//   haptic:  none
//   reduced motion: the line holds still (track only) and completes at once
//
// One controller, one CustomPaint behind a RepaintBoundary: the fill moves
// at paint time only, nothing above it rebuilds per frame.

/// A calm, ticked progress line for waits that have a typical length but no
/// real progress signal.
class KProgressLine extends StatefulWidget {
  /// Flip to true when the work finishes; the line completes, then
  /// [onCompleted] fires once.
  final bool done;

  /// The typical wait. The line reaches ~90% around here and then rests.
  final Duration expected;

  final VoidCallback? onCompleted;

  /// Thickness of the fill.
  final double thickness;

  /// Number of tick marks along the track.
  final int ticks;

  const KProgressLine({
    super.key,
    this.done = false,
    this.expected = const Duration(seconds: 7),
    this.onCompleted,
    this.thickness = 2,
    this.ticks = 24,
  });

  /// Where the line rests while it waits.
  static const double ceiling = 0.9;

  /// How long the last stretch takes once the work is done.
  static const finishDuration = Duration(milliseconds: 320);

  @override
  State<KProgressLine> createState() => _KProgressLineState();
}

class _KProgressLineState extends State<KProgressLine> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  bool _started = false;
  bool _finishing = false;

  // Fast out of the gate, then a long, slowing approach to the ceiling.
  static const Curve _approach = Cubic(0.15, 0.65, 0.25, 1.0);

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.done) {
      _finish();
    } else if (!KMotion.reduced(context)) {
      _c.animateTo(KProgressLine.ceiling, duration: widget.expected, curve: _approach);
    }
  }

  @override
  void didUpdateWidget(KProgressLine old) {
    super.didUpdateWidget(old);
    if (widget.done && !old.done) _finish();
  }

  void _finish() {
    if (_finishing) return;
    _finishing = true;
    if (KMotion.reduced(context)) {
      _c.value = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onCompleted?.call();
      });
      return;
    }
    // TickerFuture.then fires on completion only, never when disposed.
    _c
        .animateTo(1, duration: KProgressLine.finishDuration, curve: KMotion.emphasizedCurve)
        .then((_) {
      if (mounted) widget.onCompleted?.call();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: SizedBox(
          height: 8,
          width: double.infinity,
          child: CustomPaint(
            painter: _LinePainter(
              progress: _c,
              fill: KColor.ink,
              track: KColor.fg.withValues(alpha: KColor.isDark ? 0.14 : 0.12),
              thickness: widget.thickness,
              ticks: widget.ticks,
            ),
          ),
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.progress,
    required this.fill,
    required this.track,
    required this.thickness,
    required this.ticks,
  })  : _fillPaint = Paint()
          ..color = fill
          ..strokeCap = StrokeCap.round,
        _trackPaint = Paint()
          ..color = track
          ..strokeCap = StrokeCap.round,
        super(repaint: progress);

  final Animation<double> progress;
  final Color fill;
  final Color track;
  final double thickness;
  final int ticks;
  final Paint _fillPaint;
  final Paint _trackPaint;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final mid = size.height / 2;
    final p = progress.value.clamp(0.0, 1.0);
    final filledTo = w * p;

    // Tick marks: short uprights, inked once the fill has passed them.
    _trackPaint.strokeWidth = 1;
    _fillPaint.strokeWidth = 1;
    if (ticks > 1) {
      final step = w / (ticks - 1);
      for (var i = 0; i < ticks; i++) {
        final x = (i * step).clamp(0.5, w - 0.5);
        canvas.drawLine(
          Offset(x, mid - 3),
          Offset(x, mid + 3),
          x <= filledTo ? _fillPaint : _trackPaint,
        );
      }
    }

    // Base track, then the fill.
    _trackPaint.strokeWidth = thickness * 0.5;
    canvas.drawLine(Offset(0, mid), Offset(w, mid), _trackPaint);
    if (filledTo > 0) {
      _fillPaint.strokeWidth = thickness;
      canvas.drawLine(Offset(0, mid), Offset(filledTo, mid), _fillPaint);
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.progress != progress ||
      old.fill != fill ||
      old.track != track ||
      old.thickness != thickness ||
      old.ticks != ticks;
}
