import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../config/app_theme.dart';

// ─── KThemeReveal ─────────────────────────────────────────────────────────────
// Theme switch as a circular reveal. When KThemeController is about to flip
// light / dark, the current frame is snapshotted, the new palette is applied
// underneath, and the snapshot is laid on top with a circular hole that grows
// from the last touch point to the farthest corner. Then the snapshot is
// dropped.
//
// No flicker: the snapshot is in place in the same frame the new palette
// first paints. Cost: one full-screen image draw clipped by a circle for
// ~560 ms; nothing runs when idle. Reduced motion, or a failed snapshot,
// switches instantly.

class KThemeReveal extends StatefulWidget {
  const KThemeReveal({super.key, required this.child});
  final Widget child;

  @override
  State<KThemeReveal> createState() => _KThemeRevealState();
}

class _KThemeRevealState extends State<KThemeReveal>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 560);

  final _boundary = GlobalKey();
  late final AnimationController _ctrl;
  late final CurvedAnimation _t;

  /// Last pointer-down, in global (= this widget's) coordinates.
  Offset? _tap;
  ui.Image? _image;
  Offset _center = Offset.zero;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: _duration)
      ..addStatusListener(_onStatus);
    _t = CurvedAnimation(parent: _ctrl, curve: KMotion.easeOut);
    KThemeController.instance.beforeFlip = _capture;
  }

  @override
  void dispose() {
    if (KThemeController.instance.beforeFlip == _capture) {
      KThemeController.instance.beforeFlip = null;
    }
    _t.dispose();
    _ctrl.dispose();
    _image?.dispose();
    super.dispose();
  }

  void _onStatus(AnimationStatus s) {
    if (s == AnimationStatus.completed) _drop();
  }

  void _drop() {
    final img = _image;
    if (img == null) return;
    if (mounted) setState(() => _image = null);
    img.dispose();
  }

  /// Snapshots the current frame and covers the screen with it, so the new
  /// palette can paint underneath. Returns once the cover is in place (the
  /// caller then applies the theme in the same frame).
  Future<void> _capture() async {
    if (!mounted || KMotion.reduced(context)) return;
    // A flip during a reveal: settle the old one first.
    _ctrl.stop();
    _drop();
    try {
      // Wait for a painted frame so the boundary is clean to read.
      await SchedulerBinding.instance.endOfFrame;
      if (!mounted) return;
      final ro = _boundary.currentContext?.findRenderObject();
      if (ro is! RenderRepaintBoundary || !ro.hasSize) return;
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final img = await ro.toImage(pixelRatio: dpr);
      if (!mounted) {
        img.dispose();
        return;
      }
      final size = ro.size;
      _center = _tap ?? size.center(Offset.zero);
      setState(() => _image = img);
      _ctrl.forward(from: 0);
    } catch (_) {
      // No snapshot: the theme just switches.
    }
  }

  @override
  Widget build(BuildContext context) {
    final img = _image;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) => _tap = e.position,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(key: _boundary, child: widget.child),
          if (img != null)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _RevealPainter(image: img, center: _center, t: _t),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The old frame with a circular hole of growing radius at [center].
class _RevealPainter extends CustomPainter {
  _RevealPainter({required this.image, required this.center, required this.t})
      : super(repaint: t);

  final ui.Image image;
  final Offset center;
  final Animation<double> t;

  @override
  void paint(Canvas canvas, Size size) {
    var far = 0.0;
    for (final c in [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ]) {
      far = math.max(far, (c - center).distance);
    }
    final r = far * t.value;
    final rect = Offset.zero & size;
    canvas.save();
    if (r > 0) {
      canvas.clipPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(rect)
          ..addOval(Rect.fromCircle(center: center, radius: r)),
      );
    }
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      rect,
      Paint()..filterQuality = FilterQuality.low,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RevealPainter o) =>
      !identical(o.image, image) || o.center != center || o.t != t;
}
