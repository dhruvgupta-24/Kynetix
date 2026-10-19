import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Any text set in the Shear style: each line cut through the middle of its
/// capitals, the top half moved forward, with an optional ember line in the
/// first cut trailing off to the left of the first letter. The brand mark's
/// treatment, for headlines on share cards and posters.
///
/// [style] should carry the font; the cut sits at mid-cap for a cap height of
/// [capHeight] (Bricolage: 0.66 em). Meant for capitals: descenders of one
/// line would be cut by the next.
class KShearText extends StatelessWidget {
  const KShearText(
    this.text, {
    super.key,
    required this.style,
    this.ember,
    this.shift = 0.07,
    this.gap = 0.022,
    this.trail = 0.17,
    this.capHeight = 0.66,
    this.maxLines,
  });

  final String text;
  final TextStyle style;

  /// The ember line in the first cut, or null for none.
  final Color? ember;
  final double shift, gap, trail, capHeight;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final fs = style.fontSize ?? 14;
      final lead = ember == null ? 0.0 : fs * trail;
      final maxW = c.maxWidth.isFinite ? math.max(0.0, c.maxWidth - fs * shift - lead) : double.infinity;
      final tp = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        maxLines: maxLines,
        ellipsis: maxLines == null ? null : '…',
        textScaler: TextScaler.noScaling,
      )..layout(maxWidth: maxW);
      return Semantics(
        label: text,
        excludeSemantics: true,
        child: SizedBox(
          width: lead + tp.width + fs * shift,
          height: tp.height,
          child: CustomPaint(painter: _ShearTextPainter(tp, fs, lead, this)),
        ),
      );
    });
  }

  /// The largest size between [min] and [max] at which [text] fits [width]
  /// in at most [maxLines] lines without breaking a word.
  static double fit(
    String text,
    TextStyle style,
    double width, {
    int maxLines = 2,
    double min = 12,
    double max = 120,
    double shift = 0.07,
    bool ember = false,
    double trail = 0.17,
  }) {
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    var size = max;
    while (size > min) {
      final avail = width - size * shift - (ember ? size * trail : 0);
      final s = style.copyWith(fontSize: size);
      final tp = TextPainter(
        text: TextSpan(text: text, style: s),
        textDirection: TextDirection.ltr,
        maxLines: maxLines,
        textScaler: TextScaler.noScaling,
      )..layout(maxWidth: math.max(1, avail));
      var ok = !tp.didExceedMaxLines;
      tp.dispose();
      if (ok) {
        for (final w in words) {
          final wp = TextPainter(
            text: TextSpan(text: w, style: s),
            textDirection: TextDirection.ltr,
            textScaler: TextScaler.noScaling,
          )..layout();
          ok = wp.width <= avail;
          wp.dispose();
          if (!ok) break;
        }
      }
      if (ok) return size;
      size *= 0.94;
    }
    return min;
  }
}

class _ShearTextPainter extends CustomPainter {
  _ShearTextPainter(this.tp, this.fs, this.lead, this.w);
  final TextPainter tp;
  final double fs, lead;
  final KShearText w;

  @override
  void paint(Canvas canvas, Size size) {
    final shift = fs * w.shift;
    final gap = fs * w.gap;
    final cap = fs * w.capHeight;
    final lines = tp.computeLineMetrics();
    // Each line owns the band from just under the previous line's baseline
    // to just under its own, so a line's halves never pick up its neighbours.
    final bounds = <double>[-1e4];
    for (var i = 1; i < lines.length; i++) {
      final prev = lines[i - 1].baseline;
      bounds.add(prev + (lines[i].baseline - cap - prev) / 2);
    }
    bounds.add(1e5);
    for (var i = 0; i < lines.length; i++) {
      final m = lines[i];
      final cut = m.baseline - cap / 2;
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(-1e4, bounds[i], 1e5, cut));
      tp.paint(canvas, Offset(lead + shift, 0));
      canvas.restore();
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(-1e4, cut + gap, 1e5, bounds[i + 1]));
      tp.paint(canvas, Offset(lead, 0));
      canvas.restore();
      if (i == 0 && w.ember != null) {
        final first = tp.getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 1));
        final right = (first.isEmpty ? m.left + fs * 0.5 : first.first.right) + lead + shift;
        final h = fs * 0.016 < 1.2 ? 1.2 : fs * 0.016;
        canvas.drawRRect(
          RRect.fromLTRBR(lead + m.left - fs * w.trail, cut + gap / 2 - h / 2, right, cut + gap / 2 + h / 2,
              Radius.circular(h / 2)),
          Paint()..color = w.ember!,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ShearTextPainter old) => old.tp != tp;
}
