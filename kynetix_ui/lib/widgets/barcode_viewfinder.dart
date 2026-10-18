import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// The scan window: a dark camera scrim (in both themes, like any camera UI)
/// with a barcode-shaped hole cut in it, warm-white corner brackets, and an
/// ember sweep line while it is looking.
///
/// The sweep is decoration only. It runs when [scanning] and ambient motion is
/// allowed (off under reduced motion and in tests), and stops otherwise; the
/// frame reads the same without it.
class BarcodeViewfinder extends StatefulWidget {
  const BarcodeViewfinder({
    super.key,
    required this.window,
    required this.scanning,
  });

  /// The hole, in this widget's coordinates.
  final Rect window;
  final bool scanning;

  /// Shape of the window for a given screen: barcode-wide, a bit above
  /// centre so the thumb-side controls stay clear.
  static Rect windowFor(Size size) {
    final w = (size.width - 64).clamp(200.0, 340.0);
    final h = w * 0.62;
    final top = (size.height * 0.40 - h / 2).clamp(120.0, double.infinity);
    return Rect.fromLTWH((size.width - w) / 2, top, w, h);
  }

  @override
  State<BarcodeViewfinder> createState() => _BarcodeViewfinderState();
}

class _BarcodeViewfinderState extends State<BarcodeViewfinder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  late final Animation<double> _curve =
      CurvedAnimation(parent: _sweep, curve: Curves.easeInOut);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant BarcodeViewfinder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scanning != widget.scanning) _sync();
  }

  void _sync() {
    final run = widget.scanning && KMotion.ambientAllowed(context);
    if (run) {
      if (!_sweep.isAnimating) _sweep.repeat(reverse: true);
    } else {
      _sweep.stop();
    }
  }

  @override
  void dispose() {
    (_curve as CurvedAnimation).dispose();
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showSweep = widget.scanning && KMotion.ambientAllowed(context);
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _ViewfinderPainter(
            window: widget.window,
            scrim: KPalette.dark.bg.withValues(alpha: 0.66),
            hairline: KPalette.dark.fg.withValues(alpha: 0.22),
            bracket: KPalette.dark.ink,
            sweepColor: KPalette.dark.ember,
            sweep: showSweep ? _curve : null,
          ),
        ),
      ),
    );
  }
}

class _ViewfinderPainter extends CustomPainter {
  _ViewfinderPainter({
    required this.window,
    required this.scrim,
    required this.hairline,
    required this.bracket,
    required this.sweepColor,
    required this.sweep,
  }) : super(repaint: sweep);

  final Rect window;
  final Color scrim;
  final Color hairline;
  final Color bracket;
  final Color sweepColor;
  final Animation<double>? sweep;

  static const _radius = 22.0;
  static const _arm = 30.0;
  static const _stroke = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(window, const Radius.circular(_radius));

    // Scrim with the window cut out.
    final scrimPath = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(rrect);
    canvas.drawPath(scrimPath, Paint()..color = scrim);

    // Hairline around the window.
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = hairline,
    );

    // Corner brackets.
    final b = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..color = bracket;
    final l = window.left, t = window.top, r = window.right, btm = window.bottom;
    Path corner(Offset a, Offset ctrl, Offset c) => Path()
      ..moveTo(a.dx, a.dy)
      ..quadraticBezierTo(ctrl.dx, ctrl.dy, c.dx, c.dy);
    for (final p in [
      // top-left
      corner(Offset(l, t + _arm), Offset(l, t), Offset(l + _arm, t)),
      // top-right
      corner(Offset(r - _arm, t), Offset(r, t), Offset(r, t + _arm)),
      // bottom-right
      corner(Offset(r, btm - _arm), Offset(r, btm), Offset(r - _arm, btm)),
      // bottom-left
      corner(Offset(l + _arm, btm), Offset(l, btm), Offset(l, btm - _arm)),
    ]) {
      canvas.drawPath(p, b);
    }

    // Sweep line.
    final s = sweep;
    if (s != null) {
      final inset = window.deflate(14);
      final y = inset.top + inset.height * s.value;
      final line = Rect.fromLTWH(inset.left, y - 1, inset.width, 2);
      canvas.drawRect(
        line,
        Paint()
          ..shader = LinearGradient(
            colors: [
              sweepColor.withValues(alpha: 0),
              sweepColor.withValues(alpha: 0.95),
              sweepColor.withValues(alpha: 0),
            ],
          ).createShader(line),
      );
    }
  }

  @override
  bool shouldRepaint(_ViewfinderPainter old) =>
      old.window != window ||
      old.scrim != scrim ||
      old.hairline != hairline ||
      old.bracket != bracket ||
      old.sweepColor != sweepColor ||
      old.sweep != sweep;
}
