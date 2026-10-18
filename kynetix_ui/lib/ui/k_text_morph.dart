import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// Which way a [KTextMorph] rolls its changed letters. [up] for moving
/// forward (next month, a later day): old letters leave upward and new ones
/// rise in from below. [down] for moving back.
enum KMorphDirection { up, down }

/// A short label that morphs letter by letter when its text changes.
///
/// Letters shared at the start and the end stay whole (easing sideways
/// when the middle changes width); changed letters roll a few pixels in the
/// direction of travel with a plain fade, staggered left to right. While
/// idle it is an ordinary [Text], so no ticker runs and no layer is added.
/// Under reduced motion the new text just appears. Screen readers get the
/// plain text, never the moving glyphs.
class KTextMorph extends StatefulWidget {
  const KTextMorph(
    this.text, {
    super.key,
    required this.style,
    this.direction = KMorphDirection.up,
    this.order,
  });

  final String text;
  final TextStyle style;

  /// Which way changed letters roll. Ignored when [order] is given.
  final KMorphDirection direction;

  /// Optional position of [text] in a sequence (a month index, a day
  /// number). When set, the roll goes up if it grew and down if it shrank,
  /// so the caller does not have to remember the previous value.
  final int? order;

  /// Per changed letter: how long its roll takes, and how far behind the
  /// letter before it each one starts.
  static const Duration letterDuration = Duration(milliseconds: 280);
  static const Duration letterStagger = Duration(milliseconds: 18);

  /// How far a letter travels while it fades.
  static const double travel = 5;

  @override
  State<KTextMorph> createState() => _KTextMorphState();
}

class _KTextMorphState extends State<KTextMorph> with SingleTickerProviderStateMixin {
  // Created on the first change, so a label that never changes never owns a
  // controller.
  AnimationController? _ctrl;
  _MorphScene? _scene;

  @override
  void didUpdateWidget(covariant KTextMorph old) {
    super.didUpdateWidget(old);
    if (old.text == widget.text) return;
    _scene?.dispose();
    _scene = null;
    final d = KMotion.of(context, KTextMorph.letterDuration);
    if (d == Duration.zero) {
      _ctrl?.stop();
      return;
    }
    final o = old.order, n = widget.order;
    final dir = (o != null && n != null && o != n)
        ? (n > o ? KMorphDirection.up : KMorphDirection.down)
        : widget.direction;
    final scene = _MorphScene.build(
      from: old.text,
      to: widget.text,
      style: _resolvedStyle(context),
      scaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
      up: dir == KMorphDirection.up,
    );
    if (scene == null) return;
    _scene = scene;
    final stagger = KTextMorph.letterStagger * math.max(0, scene.changedCount - 1);
    final ctrl = _ctrl ??= AnimationController(vsync: this)..addStatusListener(_onStatus);
    scene.staggerShare = stagger.inMicroseconds / (d + stagger).inMicroseconds;
    ctrl
      ..duration = d + stagger
      ..forward(from: 0);
  }

  void _onStatus(AnimationStatus s) {
    if (s != AnimationStatus.completed || !mounted) return;
    // Settled: back to a plain Text.
    setState(() {
      _scene?.dispose();
      _scene = null;
    });
  }

  TextStyle _resolvedStyle(BuildContext context) => DefaultTextStyle.of(context).style.merge(widget.style);

  @override
  void dispose() {
    _scene?.dispose();
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scene = _scene;
    final ctrl = _ctrl;
    final Widget body;
    if (scene == null || ctrl == null || !ctrl.isAnimating) {
      body = Text(widget.text, style: widget.style, maxLines: 1, softWrap: false, overflow: TextOverflow.fade);
    } else {
      body = ClipRect(
        child: CustomPaint(
          size: scene.size,
          painter: _MorphPainter(scene: scene, t: ctrl),
        ),
      );
    }
    return Semantics(label: widget.text, excludeSemantics: true, child: body);
  }
}

/// One glyph of the old or new text, laid out alone and placed where the
/// full string's layout put it.
class _Glyph {
  _Glyph(this.painter, this.offset);
  final TextPainter painter;
  final Offset offset;
}

/// What one morph draws: for each index, the old glyph and the new one,
/// and whether that index changed.
class _MorphScene {
  _MorphScene._(this.size, this.olds, this.news, this.changedRank, this.changedCount, this.up);

  final Size size;
  final List<_Glyph?> olds;
  final List<_Glyph?> news;

  /// For a changed index, its place among the changed letters (0, 1, ...);
  /// -1 for a letter that stays.
  final List<int> changedRank;
  final int changedCount;
  final bool up;

  /// Share of the run spent on the stagger (set once the duration is known).
  double staggerShare = 0;

  static _MorphScene? build({
    required String from,
    required String to,
    required TextStyle style,
    required TextScaler scaler,
    required TextDirection textDirection,
    required bool up,
  }) {
    final a = from.characters.toList();
    final b = to.characters.toList();
    final full = [
      for (final s in [from, to])
        TextPainter(
          text: TextSpan(text: s, style: style),
          textDirection: textDirection,
          textScaler: scaler,
          maxLines: 1,
        )..layout(),
    ];
    List<_Glyph?> place(List<String> chars, TextPainter layout) {
      final out = <_Glyph?>[];
      var at = 0;
      for (final c in chars) {
        final boxes = layout.getBoxesForSelection(TextSelection(baseOffset: at, extentOffset: at + c.length));
        at += c.length;
        if (boxes.isEmpty || c.trim().isEmpty) {
          out.add(null);
          continue;
        }
        final p = TextPainter(
          text: TextSpan(text: c, style: style),
          textDirection: textDirection,
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        out.add(_Glyph(p, Offset(boxes.first.left, 0)));
      }
      return out;
    }

    final og = place(a, full[0]);
    final ng = place(b, full[1]);
    final size = Size(
      math.max(full[0].width, full[1].width),
      math.max(full[0].height, full[1].height),
    );
    for (final p in full) {
      p.dispose();
    }
    // Pair letters by the shared start and the shared end, so "October 2026"
    // to "November 2026" keeps "ber 2026" whole (it glides sideways) and
    // only "Octo" turns into "Novem". Everything between them rolls.
    final la = a.length, lb = b.length;
    var pre = 0;
    while (pre < la && pre < lb && a[pre] == b[pre]) {
      pre++;
    }
    var suf = 0;
    while (suf < la - pre && suf < lb - pre && a[la - 1 - suf] == b[lb - 1 - suf]) {
      suf++;
    }
    final olds = <_Glyph?>[], news = <_Glyph?>[], rank = <int>[];
    for (var i = 0; i < pre; i++) {
      olds.add(og[i]);
      news.add(ng[i]);
      rank.add(-1);
    }
    final mo = la - pre - suf, mn = lb - pre - suf;
    var changed = 0;
    for (var k = 0; k < math.max(mo, mn); k++) {
      olds.add(k < mo ? og[pre + k] : null);
      news.add(k < mn ? ng[pre + k] : null);
      rank.add(changed++);
    }
    for (var k = 0; k < suf; k++) {
      olds.add(og[la - suf + k]);
      news.add(ng[lb - suf + k]);
      rank.add(-1);
    }
    return _MorphScene._(size, olds, news, rank, changed, up);
  }

  void dispose() {
    for (final g in [...olds, ...news]) {
      g?.painter.dispose();
    }
  }
}

class _MorphPainter extends CustomPainter {
  _MorphPainter({required this.scene, required this.t}) : super(repaint: t);
  final _MorphScene scene;
  final Animation<double> t;

  static const Curve _curve = KMotion.easeOut;

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    final s = scene;
    final span = 1 - s.staggerShare;
    final sign = s.up ? -1.0 : 1.0;
    // Letters that stay ease sideways over the whole run.
    final whole = _curve.transform(v);
    for (var i = 0; i < s.changedRank.length; i++) {
      final o = s.olds[i];
      final n = s.news[i];
      final rank = s.changedRank[i];
      if (rank < 0) {
        if (n == null) continue;
        final x = o == null ? n.offset.dx : o.offset.dx + (n.offset.dx - o.offset.dx) * whole;
        n.painter.paint(canvas, Offset(x, n.offset.dy));
        continue;
      }
      final start = s.changedCount <= 1 ? 0.0 : s.staggerShare * rank / (s.changedCount - 1);
      final p = _curve.transform(((v - start) / span).clamp(0.0, 1.0));
      if (o != null && p < 1) _paintFaded(canvas, o, Offset(0, sign * KTextMorph.travel * p), 1 - p);
      if (n != null && p > 0) _paintFaded(canvas, n, Offset(0, -sign * KTextMorph.travel * (1 - p)), p);
    }
  }

  // A small layer per moving glyph keeps the fade exact for any text colour
  // (a glyph's own alpha, a gradient foreground); it lives for 300 ms at most.
  void _paintFaded(Canvas canvas, _Glyph g, Offset shift, double alpha) {
    if (alpha <= 0.01) return;
    final at = g.offset + shift;
    if (alpha >= 0.99) {
      g.painter.paint(canvas, at);
      return;
    }
    final bounds = (at & g.painter.size).inflate(2);
    canvas.saveLayer(bounds, Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
    g.painter.paint(canvas, at);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MorphPainter old) => old.scene != scene || old.t != t;
}
