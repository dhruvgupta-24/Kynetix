import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_theme.dart';

// ─── The Shear mark ───────────────────────────────────────────────────────────
//
// KYNETIX in Bricolage 800, cut through the middle: the top half sits a little
// forward of the bottom, and an ember line runs in the cut under the K and
// trails off to its left. One geometry, used by the static wordmark, the K on
// its own, the launch intro, and (as the same numbers) the native icons.

/// Brand colours of the mark. The intro and the icons are always graphite.
const kBrandGraphite = Color(0xFF0B0B0C);
const kBrandBone = Color(0xFFF2F1EC);
const kBrandEmber = Color(0xFFFF6A3D);

/// Proportions of the mark, in units of the font size. With `height: 1`
/// Flutter splits Bricolage's 930 / 270 ascent and descent over one em, so
/// the baseline sits 0.775 below the line top and the cap top (cap height
/// 0.66) at 0.115. The cut runs 0.32 below the cap top, as in the design and
/// the native icons (590 font units from the ascender).
abstract final class KShear {
  static const cutFromTop = 0.435;
  static const gap = 0.022;
  static const shift = 0.07;
  static const trail = 0.17;
  static const emberThickness = 0.016;

  /// Centre of the K's cap box from the K's paint origin.
  static const kCenter = Offset(0.313, 0.445);

  /// The K's cap box, from the K's paint origin.
  static const kLeft = 0.05, kRight = 0.576;

  /// Size of the K in the native splash icon, in logical pixels: the intro
  /// starts from exactly this K so the hand-off does not jump.
  static const splashFontSize = 158.0;
}

/// Laid-out glyphs for one font size and ink, cached: painting a frame never
/// lays out text.
class _ShearGlyphs {
  _ShearGlyphs._(this.fontSize, this.glyphs, this.width);

  final double fontSize;
  final List<({TextPainter p, double x, double right})> glyphs;
  final double width;

  static final Map<(double, int), _ShearGlyphs> _cache = {};

  static _ShearGlyphs of(double fontSize, Color ink) {
    final key = (fontSize, ink.toARGB32());
    final hit = _cache[key];
    if (hit != null) return hit;
    if (_cache.length > 12) {
      for (final g in _cache.values) {
        for (final x in g.glyphs) {
          x.p.dispose();
        }
      }
      _cache.clear();
    }
    final style = TextStyle(
      fontFamily: KText.brandFace,
      fontWeight: FontWeight.w800,
      fontSize: fontSize,
      letterSpacing: -0.03 * fontSize,
      color: ink,
      height: 1,
    );
    const word = 'KYNETIX';
    final full = TextPainter(
      text: TextSpan(text: word, style: style),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();
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
    final width = full.width;
    full.dispose();
    return _cache[key] = _ShearGlyphs._(fontSize, glyphs, width);
  }
}

/// The finished Shear wordmark (or just the K), drawn at [fontSize].
///
/// Sizes itself to the mark, trail and shift included. Defaults follow the
/// theme: ink text with the ember accent.
class KShearWordmark extends StatelessWidget {
  const KShearWordmark({super.key, this.fontSize = 48, this.ink, this.ember, this.kOnly = false});

  final double fontSize;
  final Color? ink;
  final Color? ember;

  /// Only the K, with its cut: the icon form.
  final bool kOnly;

  @override
  Widget build(BuildContext context) {
    final g = _ShearGlyphs.of(fontSize, ink ?? KColor.textPrimary);
    final textW = kOnly ? g.glyphs.first.right : g.width;
    final w = fontSize * KShear.trail + textW + fontSize * KShear.shift;
    return Semantics(
      label: 'Kynetix',
      image: true,
      excludeSemantics: true,
      child: SizedBox(
        width: w,
        height: fontSize,
        child: CustomPaint(
          painter: _StaticShearPainter(g, ember ?? KColor.ember, kOnly),
        ),
      ),
    );
  }
}

class _StaticShearPainter extends CustomPainter {
  _StaticShearPainter(this.g, this.ember, this.kOnly);
  final _ShearGlyphs g;
  final Color ember;
  final bool kOnly;

  @override
  void paint(Canvas canvas, Size size) {
    final f = g.fontSize;
    final origin = Offset(f * KShear.trail, 0);
    final cutY = f * KShear.cutFromTop;
    final gap = f * KShear.gap;
    final kRight = origin.dx + g.glyphs.first.right;
    final h = math.max(f * KShear.emberThickness, gap * 0.8);
    canvas.drawRRect(
      RRect.fromLTRBR(0, cutY + gap / 2 - h / 2, kRight + f * KShear.shift, cutY + gap / 2 + h / 2, Radius.circular(h / 2)),
      Paint()..color = ember,
    );
    final count = kOnly ? 1 : g.glyphs.length;
    for (final (clip, dx) in [
      (Rect.fromLTRB(-1e4, cutY + gap, 1e4, 1e4), 0.0),
      (Rect.fromLTRB(-1e4, -1e4, 1e4, cutY), f * KShear.shift),
    ]) {
      canvas.save();
      canvas.clipRect(clip);
      for (var i = 0; i < count; i++) {
        g.glyphs[i].p.paint(canvas, Offset(origin.dx + g.glyphs[i].x + dx, origin.dy));
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_StaticShearPainter old) => old.g != g || old.ember != ember || old.kOnly != kOnly;
}

// ─── The launch intro ─────────────────────────────────────────────────────────

/// The Kynetix opening, picking up where the native splash leaves off.
///
/// On Android the system splash has just played the icon animation: a K
/// appears in the middle of the screen, an ember blade slices it and the top
/// half shears forward. This intro starts from that exact K:
///
///   1. The sheared K glides from the middle into its place in the wordmark.
///   2. Y N E T I X slide out from behind it, like a drawer.
///   3. The blade carries on from the K's cut across the rest of the word,
///      and each letter shears with a snap as the blade passes it
///      (one commit haptic as the blade sets off).
///   4. The ember trims back under the K: the finished mark. A short hold,
///      then the intro fades into the app.
///
/// Always graphite. A tap skips to the end. Under reduced motion the
/// finished mark shows on its own. Text is laid out once per size, so a frame
/// only clips and translates cached glyphs.
class KBrandIntro extends StatefulWidget {
  const KBrandIntro({super.key, required this.onDone});

  /// Called once the intro has faded out.
  final VoidCallback onDone;

  /// The full run, hold and fade included.
  static const Duration total = Duration(milliseconds: 2400);

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
      _starting = true;
      _t.value = _Timeline.holdStart;
      _delay = Timer(const Duration(milliseconds: 700), () {
        if (mounted) _t.forward();
      });
    } else {
      _starting = true;
      // Hold the splash K until Android's splash has finished slicing it and
      // handed over (Android 12+), and cold start has settled, so the glide
      // is actually seen. Elsewhere the wait returns at once.
      WidgetsBinding.instance.endOfFrame.then((_) {
        if (!mounted) return;
        // Never wait more than 1.5 s for the native side.
        _fallback = Timer(const Duration(milliseconds: 1500), _go);
        _splash.invokeMethod<bool>('waitForSplash').then((_) => _go(), onError: (Object _) => _go());
      });
    }
  }

  static const _splash = MethodChannel('com.kynetix.app/splash');
  Timer? _fallback;
  bool _went = false;

  /// The native splash is gone (or we stopped waiting): a beat, then go.
  void _go() {
    if (_went || !mounted) return;
    _went = true;
    _fallback?.cancel();
    _delay = Timer(const Duration(milliseconds: 160), () {
      if (mounted && !_t.isAnimating && _t.value == 0) _t.forward();
    });
  }

  void _onTick() {
    if (!_hapticDone && _t.value >= _Timeline.blade.begin) {
      _hapticDone = true;
      KHaptics.commit();
    }
  }

  void _skip() {
    _starting = true;
    _delay?.cancel();
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
    _fallback?.cancel();
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
                color: kBrandGraphite,
                child: SizedBox.expand(
                  child: RepaintBoundary(child: CustomPaint(painter: _IntroPainter(_t.value))),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A span of the timeline, in milliseconds of [KBrandIntro.total].
class _Span {
  const _Span(this.beginMs, this.endMs);
  final int beginMs, endMs;
  static const _total = 2400;
  double get begin => beginMs / _total;
  double get end => endMs / _total;

  /// 0 before the span, 1 after it, linear inside.
  double at(double t) => ((t - begin) / (end - begin)).clamp(0.0, 1.0);
}

abstract final class _Timeline {
  static const glide = _Span(0, 560);
  static const letters = _Span(380, 980);
  static const blade = _Span(960, 1480);
  static const trim = _Span(1500, 1780);
  static const fade = _Span(2080, 2400);
  static double get holdStart => trim.end;
}

class _IntroPainter extends CustomPainter {
  _IntroPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    // The finished word: about 78% of the width, never above 120 px type.
    final f = math.min(size.width * 0.78 / 3.54, 120.0);
    final g = _ShearGlyphs.of(f, kBrandBone);
    final origin = Offset((size.width - g.width) / 2, (size.height - f) / 2 - f * 0.1);
    final cutY = origin.dy + f * KShear.cutFromTop;
    final gap = f * KShear.gap;
    final shift = f * KShear.shift;
    final kRightW = origin.dx + g.glyphs.first.right;
    final wordRight = origin.dx + g.glyphs.last.right;
    final emberH = math.max(f * KShear.emberThickness, gap * 0.8);

    // ── 1. The K: from the splash K (centre, splash size) to its place.
    final glide = Curves.easeInOutCubic.transform(_Timeline.glide.at(t));
    final s0 = KShear.splashFontSize / f; // the K's scale at the start
    final kCenterEnd = origin + Offset(KShear.kCenter.dx * f, KShear.kCenter.dy * f);
    final kCenterStart = size.center(Offset.zero);
    final kScale = s0 + (1 - s0) * glide;
    final kCenter = Offset.lerp(kCenterStart, kCenterEnd, glide)!;

    // The K is drawn in its own frame: scaled about its cap centre.
    canvas.save();
    canvas.translate(kCenter.dx, kCenter.dy);
    canvas.scale(kScale);
    canvas.translate(-kCenterEnd.dx, -kCenterEnd.dy);
    // The K's ember: its own cut, trailing left (as the splash left it).
    final kEmberRight = kRightW + shift;
    final kEmberLeft = origin.dx - f * KShear.trail;
    canvas.drawRRect(
      RRect.fromLTRBR(kEmberLeft, cutY + gap / 2 - emberH / 2, kEmberRight, cutY + gap / 2 + emberH / 2, Radius.circular(emberH / 2)),
      Paint()..color = kBrandEmber,
    );
    _paintHalves(canvas, g, 0, 1, origin, cutY, gap, shift);
    canvas.restore();

    // ── 2. The tail slides out from behind the K, unsheared at first.
    final tailIn = Curves.easeOutExpo.transform(_Timeline.letters.at(t));
    if (tailIn <= 0) return;
    final tailDx = -(wordRight - kRightW) * (1 - tailIn);

    // ── 3. The blade runs from the K's cut across the tail; each letter
    // shears as the blade passes its middle.
    final blade = Curves.easeInOutCubic.transform(_Timeline.blade.at(t));
    final trim = Curves.easeInOutCubic.transform(_Timeline.trim.at(t));
    final bladeEnd = wordRight + f * 0.04;
    if (blade > 0) {
      final right = trim > 0
          ? bladeEnd + (kEmberRight - bladeEnd) * trim
          : kEmberRight + (bladeEnd - kEmberRight) * blade;
      if (right > kEmberRight) {
        canvas.drawRRect(
          RRect.fromLTRBR(kEmberRight - emberH, cutY + gap / 2 - emberH / 2, right, cutY + gap / 2 + emberH / 2, Radius.circular(emberH / 2)),
          Paint()..color = kBrandEmber,
        );
      }
      if (blade < 1) {
        canvas.drawCircle(Offset(right, cutY + gap / 2), emberH * 1.25, Paint()..color = const Color(0xFFFFD7C8));
      }
    }
    final bladeX = kEmberRight + (bladeEnd - kEmberRight) * blade;

    canvas.save();
    // Letters emerge from under the K, never in front of it.
    if (tailIn < 1) canvas.clipRect(Rect.fromLTRB(kRightW - f * 0.02, -1e4, 1e5, 1e5));
    for (var i = 1; i < g.glyphs.length; i++) {
      final gl = g.glyphs[i];
      final mid = origin.dx + (gl.x + gl.right) / 2;
      // 0 until the blade reaches the letter, snapping to 1 just after.
      final p = ((bladeX - (mid - f * 0.08)) / (f * 0.22)).clamp(0.0, 1.0);
      final snap = Curves.easeOutBack.transform(p);
      _paintHalves(canvas, g, i, i + 1, origin.translate(tailDx, 0), cutY, gap * Curves.easeOut.transform(p), shift * snap);
    }
    canvas.restore();
  }

  /// Glyphs [from]..[to) of [g] at [origin]: the bottom half in place, the
  /// top half moved forward by [dx], with a [gap] between.
  static void _paintHalves(Canvas canvas, _ShearGlyphs g, int from, int to, Offset origin, double cutY, double gap,
      double dx) {
    for (final (clip, ox) in [
      (Rect.fromLTRB(-1e4, cutY + gap, 1e5, 1e5), 0.0),
      (Rect.fromLTRB(-1e4, -1e4, 1e5, cutY), dx),
    ]) {
      canvas.save();
      canvas.clipRect(clip);
      for (var i = from; i < to; i++) {
        g.glyphs[i].p.paint(canvas, Offset(origin.dx + g.glyphs[i].x + ox, origin.dy));
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_IntroPainter old) => old.t != t;
}
