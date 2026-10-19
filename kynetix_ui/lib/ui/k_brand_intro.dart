import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// The Kynetix opening: the Shear wordmark assembling itself.
///
///   1. The K lands, dropping in a few pixels and settling.
///   2. Y N E T I X slide out from behind the K together, like a drawer.
///   3. An ember blade slices across the word, left to right.
///   4. The top half shears forward, leaving two faint speed ghosts, and the
///      ember settles into the cut (one commit haptic here).
///   5. The ember trims back under the K: the finished mark. A short hold,
///      then the whole intro fades into the app.
///
/// Always graphite, whatever the theme: it continues the native splash. A tap
/// skips to the end. Under reduced motion the finished mark shows on its own.
class KBrandIntro extends StatefulWidget {
  const KBrandIntro({super.key, required this.onDone});

  /// Called once the intro has faded out.
  final VoidCallback onDone;

  /// The full run, hold and fade included.
  static const Duration total = Duration(milliseconds: 2600);

  @override
  State<KBrandIntro> createState() => _KBrandIntroState();
}

class _KBrandIntroState extends State<KBrandIntro> with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(vsync: this, duration: KBrandIntro.total);
  bool _hapticDone = false;
  bool _finished = false;
  bool _starting = false;
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    _t.addListener(_onTick);
    _t.addStatusListener((s) {
      if (s == AnimationStatus.completed) _finish();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_starting || _t.isAnimating || _t.value > 0) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      // Reduced motion: the finished mark, briefly, then a plain fade.
      _t.value = _Timeline.holdStart;
      _delay = Timer(const Duration(milliseconds: 700), () {
        if (mounted) _t.forward();
      });
    } else if (!_starting) {
      _starting = true;
      // Cold start is busy (session restore, first route): frames drop for a
      // moment. Start once the first frame is on screen and things settle,
      // so the K's landing is actually seen. The screen stays graphite.
      WidgetsBinding.instance.endOfFrame.then((_) {
        if (!mounted) return;
        _delay = Timer(const Duration(milliseconds: 380), () {
          if (mounted && !_t.isAnimating && _t.value == 0) _t.forward();
        });
      });
    }
  }

  void _onTick() {
    if (!_hapticDone && _t.value >= _Timeline.shear.begin) {
      _hapticDone = true;
      KHaptics.commit();
    }
  }

  void _skip() {
    _starting = true;
    if (_t.value < _Timeline.holdStart) {
      _hapticDone = true;
      _t.value = _Timeline.holdStart;
      _t.forward();
    }
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _delay?.cancel();
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Kynetix',
      container: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _skip,
        child: AnimatedBuilder(
          animation: _t,
          builder: (context, _) {
            final fade = _Timeline.fade.at(_t.value);
            return Opacity(
              opacity: 1 - Curves.easeIn.transform(fade),
              child: ColoredBox(
                color: _graphite,
                child: SizedBox.expand(
                  child: CustomPaint(painter: _ShearPainter(_t.value)),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

const _graphite = Color(0xFF0B0B0C);
const _bone = Color(0xFFF2F1EC);
const _ember = Color(0xFFFF6A3D);

/// A span of the timeline, in fractions of [KBrandIntro.total].
class _Span {
  const _Span(this.beginMs, this.endMs);
  final int beginMs, endMs;
  static const _total = 2600;
  double get begin => beginMs / _total;
  double get end => endMs / _total;

  /// 0 before the span, 1 after it, linear inside.
  double at(double t) => ((t - begin) / (end - begin)).clamp(0.0, 1.0);
}

abstract final class _Timeline {
  static const k = _Span(0, 460);
  static const letters = _Span(380, 1040);
  static const blade = _Span(1020, 1360);
  static const shear = _Span(1360, 1680);
  static const trim = _Span(1680, 1980);
  static const fade = _Span(2280, 2600);
  static double get holdStart => trim.end;
}

class _ShearPainter extends CustomPainter {
  _ShearPainter(this.t);
  final double t;

  // Proportions of the Shear mark, in units of the font size (Bricolage 800,
  // cap height 0.66, baseline 0.93 below the line top).
  static const _cutFromTop = 0.59;
  static const _gap = 0.022;
  static const _shift = 0.07;
  static const _trail = 0.17;

  @override
  void paint(Canvas canvas, Size size) {
    // Size the word to about 78% of the shorter side, never above 120 px type.
    final fontSize = math.min(size.width * 0.78 / 3.54, 120.0);
    final style = TextStyle(
      fontFamily: KText.brandFace,
      fontWeight: FontWeight.w800,
      fontSize: fontSize,
      letterSpacing: -0.03 * fontSize,
      color: _bone,
      height: 1,
    );
    const word = 'KYNETIX';
    final full = TextPainter(
      text: TextSpan(text: word, style: style),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();
    final origin = Offset((size.width - full.width) / 2, (size.height - full.height) / 2 - fontSize * 0.1);

    final glyphs = <({TextPainter p, double x, double right})>[];
    for (var i = 0; i < word.length; i++) {
      final box = full.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1)).first;
      final p = TextPainter(
        text: TextSpan(text: word[i], style: style.copyWith(letterSpacing: 0)),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
      )..layout();
      glyphs.add((p: p, x: box.left, right: box.right));
    }
    full.dispose();

    final kRight = origin.dx + glyphs.first.right;
    final wordRight = origin.dx + glyphs.last.right;
    final cutY = origin.dy + fontSize * _cutFromTop;

    final kIn = _Timeline.k.at(t);
    final shear = Curves.easeOutBack.transform(_Timeline.shear.at(t));
    final shearLinear = _Timeline.shear.at(t);
    final shift = fontSize * _shift * shear;
    final gap = fontSize * _gap * Curves.easeOut.transform(shearLinear);

    // Everything above or below the cut, painted with its own offset.
    void paintWord(Canvas c, {required double dx, required double opacityScale}) {
      for (var i = 0; i < glyphs.length; i++) {
        final g = glyphs[i];
        double ox = 0, oy = 0, alpha = 1;
        if (i == 0) {
          final e = Curves.easeOutBack.transform(kIn);
          oy = -fontSize * 0.14 * (1 - e);
          alpha = Curves.easeOut.transform(kIn);
        } else {
          // The whole tail slides out from behind the K as one piece, so no
          // letter ever crosses another.
          final p = _Timeline.letters.at(t);
          final e = Curves.easeOutExpo.transform(p);
          ox = -(wordRight - kRight) * (1 - e);
        }
        alpha *= opacityScale;
        if (alpha <= 0.002) continue;
        final at = Offset(origin.dx + g.x + ox + dx, origin.dy + oy);
        if (i > 0 && t < _Timeline.letters.end) {
          // Letters emerge from under the K, never in front of it.
          c.save();
          c.clipRect(Rect.fromLTRB(kRight - fontSize * 0.02, 0, 1e5, 1e5));
        }
        if (alpha < 0.999) {
          c.saveLayer(Rect.fromLTWH(at.dx - 4, at.dy - 4, g.p.width + 8, g.p.height + 8),
              Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
          g.p.paint(c, at);
          c.restore();
        } else {
          g.p.paint(c, at);
        }
        if (i > 0 && t < _Timeline.letters.end) c.restore();
      }
    }

    // ── Ember: the blade sweeping across, then the cut, then the trim.
    final emberLeft = origin.dx - fontSize * _trail;
    final blade = Curves.easeInOutCubic.transform(_Timeline.blade.at(t));
    final trim = Curves.easeInOutCubic.transform(_Timeline.trim.at(t));
    if (blade > 0) {
      final fullRight = wordRight + fontSize * 0.04;
      final settledRight = kRight + fontSize * _shift;
      final right = trim > 0
          ? fullRight + (settledRight - fullRight) * trim
          : emberLeft + (fullRight - emberLeft) * blade;
      final h = math.max(fontSize * 0.014, gap * 0.8);
      final r = RRect.fromLTRBR(emberLeft, cutY + gap / 2 - h / 2, right, cutY + gap / 2 + h / 2, Radius.circular(h / 2));
      canvas.drawRRect(r, Paint()..color = _ember);
      // The hot leading edge while the blade is moving.
      if (blade < 1) {
        canvas.drawCircle(Offset(right, cutY + gap / 2), h * 1.25, Paint()..color = const Color(0xFFFFD7C8));
      }
    }

    final bottom = Rect.fromLTRB(0, cutY + gap, size.width, size.height);
    final top = Rect.fromLTRB(0, 0, size.width, cutY);
    canvas.save();
    canvas.clipRect(bottom);
    paintWord(canvas, dx: 0, opacityScale: 1);
    canvas.restore();

    // Speed ghosts of the top half, fading as the shear lands.
    if (shearLinear > 0 && shearLinear < 1) {
      for (final (k, a) in [(0.35, 0.16), (0.7, 0.3)]) {
        canvas.save();
        canvas.clipRect(top);
        paintWord(canvas, dx: shift * k, opacityScale: a * (1 - shearLinear));
        canvas.restore();
      }
    }
    canvas.save();
    canvas.clipRect(top);
    paintWord(canvas, dx: shift, opacityScale: 1);
    canvas.restore();

    for (final g in glyphs) {
      g.p.dispose();
    }
  }

  @override
  bool shouldRepaint(_ShearPainter old) => old.t != t;
}
