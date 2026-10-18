import 'package:flutter/material.dart';

import '../config/app_theme.dart';

// Moment declaration: success check
//   trigger: a commit that succeeded (meal logged, set logged, workout saved)
//   change:  a check stroke draws itself from the short arm to the long arm
//   duration role: ~300 ms draw (KSuccessCheck.drawDuration)
//   haptic:  none here; the caller fires exactly one on the commit frame
//   reduced motion: the finished check appears at once
//
// Painted as a single stroked path, so it costs one draw call per frame for
// the few frames it animates and nothing after.

/// A check mark that draws itself once.
///
/// Drive it from an outside [progress] animation (0 to 1) to sync it with a
/// larger moment, or leave [progress] null and it plays on its own the first
/// time it is shown, calling [onDrawn] when the stroke is complete.
class KSuccessCheck extends StatefulWidget {
  static const drawDuration = Duration(milliseconds: 300);

  final double size;
  final Color color;
  final double? strokeWidth;
  final Animation<double>? progress;
  final VoidCallback? onDrawn;

  const KSuccessCheck({
    super.key,
    this.size = 20,
    required this.color,
    this.strokeWidth,
    this.progress,
    this.onDrawn,
  });

  @override
  State<KSuccessCheck> createState() => _KSuccessCheckState();
}

class _KSuccessCheckState extends State<KSuccessCheck> with SingleTickerProviderStateMixin {
  AnimationController? _own;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    if (widget.progress == null) {
      _own = AnimationController(vsync: this, duration: KSuccessCheck.drawDuration);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final own = _own;
    if (_started || own == null) return;
    _started = true;
    if (KMotion.reduced(context)) {
      own.value = 1;
      if (widget.onDrawn != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onDrawn?.call();
        });
      }
    } else {
      // TickerFuture.then only fires on completion, never on cancel/dispose.
      own.animateTo(1, curve: KMotion.emphasizedCurve).then((_) {
        if (mounted) widget.onDrawn?.call();
      });
    }
  }

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final anim = widget.progress ?? _own!;
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: _CheckPainter(
            progress: anim,
            color: widget.color,
            strokeWidth: widget.strokeWidth ?? (widget.size * 0.11).clamp(1.6, 4.0),
          ),
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter({required this.progress, required this.color, required this.strokeWidth})
      : _paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = color
          ..strokeWidth = strokeWidth,
        super(repaint: progress);

  final Animation<double> progress;
  final Color color;
  final double strokeWidth;
  final Paint _paint;

  // Geometry is cached per size: paint() allocates nothing on most frames.
  Size? _cachedSize;
  late Offset _a, _b, _c;
  late double _ab, _total;

  void _layout(Size size) {
    if (_cachedSize == size) return;
    _cachedSize = size;
    final w = size.width, h = size.height;
    _a = Offset(w * 0.20, h * 0.54);
    _b = Offset(w * 0.42, h * 0.74);
    _c = Offset(w * 0.80, h * 0.30);
    _ab = (_b - _a).distance;
    _total = _ab + (_c - _b).distance;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value.clamp(0.0, 1.0);
    if (t <= 0) return;
    _layout(size);
    final len = _total * t;
    if (len <= _ab) {
      canvas.drawLine(_a, Offset.lerp(_a, _b, len / _ab)!, _paint);
      return;
    }
    final path = Path()
      ..moveTo(_a.dx, _a.dy)
      ..lineTo(_b.dx, _b.dy);
    final end = Offset.lerp(_b, _c, (len - _ab) / (_total - _ab))!;
    path.lineTo(end.dx, end.dy);
    canvas.drawPath(path, _paint);
  }

  @override
  bool shouldRepaint(_CheckPainter old) =>
      old.progress != progress || old.color != color || old.strokeWidth != strokeWidth;
}

/// The "it worked" face of a primary action: the ink pill the button was,
/// now holding a drawn check and a short past-tense label ("Logged").
///
/// Plays once: the check draws (~300 ms), the label settles in beside it,
/// the state holds for a beat, then [onFinished] fires so the caller can
/// close the screen. Under reduced motion the end state shows at once and
/// [onFinished] follows on the next frame. Never fires a haptic itself.
class KSuccessPill extends StatefulWidget {
  final String label;
  final VoidCallback? onFinished;
  final Duration hold;
  final Color? color;

  const KSuccessPill({
    super.key,
    this.label = 'Logged',
    this.onFinished,
    this.hold = const Duration(milliseconds: 420),
    this.color,
  });

  @override
  State<KSuccessPill> createState() => _KSuccessPillState();
}

class _KSuccessPillState extends State<KSuccessPill> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _draw;
  late final Animation<double> _label;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    final total = KSuccessCheck.drawDuration + widget.hold;
    _c = AnimationController(vsync: this, duration: total);
    final drawEnd = KSuccessCheck.drawDuration.inMicroseconds / total.inMicroseconds;
    _draw = CurvedAnimation(parent: _c, curve: Interval(0, drawEnd, curve: KMotion.emphasizedCurve));
    _label = CurvedAnimation(parent: _c, curve: Interval(drawEnd * 0.35, drawEnd * 1.2, curve: KMotion.decelerate));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (KMotion.reduced(context)) {
      _c.value = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onFinished?.call();
      });
    } else {
      _c.forward().then((_) {
        if (mounted) widget.onFinished?.call();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.color ?? KColor.ink;
    final fg = bg == KColor.ember ? KColor.onAccent : KColor.onInk;
    return Semantics(
      liveRegion: true,
      label: widget.label,
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        decoration: BoxDecoration(color: bg, borderRadius: KRadius.pill),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            KSuccessCheck(size: 22, color: fg, progress: _draw),
            const SizedBox(width: 8),
            Flexible(
              child: FadeTransition(
                opacity: _label,
                child: SlideTransition(
                  position: Tween(begin: const Offset(-0.08, 0), end: Offset.zero).animate(_label),
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: KText.family,
                      color: fg,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
