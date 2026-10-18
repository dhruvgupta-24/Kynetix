import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../config/app_theme.dart';

/// A number whose digits roll like an odometer when it changes.
///
/// Each digit is its own clipped column of 0 to 9 sliding under a window, so
/// only the digits that changed move, with an ease-out over ~450 ms. Tabular
/// figures keep every digit the same width; when the digit count changes the
/// box eases to its new width instead of jumping, and a new leading digit
/// rolls up from 0. In a slot narrower than the number it scales down
/// instead of overflowing. A rebuild with the same text does nothing. Under reduced
/// motion the new value just appears. Screen readers get the whole number
/// once, never the rolling glyphs.
class KRollingNumber extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Duration? duration;
  final String? semanticsLabel;

  /// Roll up from 0 the first time it shows (a reveal), not only on change.
  final bool fromZero;

  /// Where the digits sit while the box eases to a new width. Right keeps
  /// the units column still, the way an odometer reads.
  final AlignmentGeometry alignment;

  const KRollingNumber(
    this.text, {
    super.key,
    required this.style,
    this.duration,
    this.semanticsLabel,
    this.fromZero = false,
    this.alignment = AlignmentDirectional.centerEnd,
  });

  /// Formats an int with thousands commas, e.g. 2,350.
  KRollingNumber.int(
    int value, {
    Key? key,
    required TextStyle style,
    Duration? duration,
    String? semanticsLabel,
    bool fromZero = false,
    AlignmentGeometry alignment = AlignmentDirectional.centerEnd,
  }) : this(
          thousandsOf(value),
          key: key,
          style: style,
          duration: duration,
          semanticsLabel: semanticsLabel,
          fromZero: fromZero,
          alignment: alignment,
        );

  /// The roll: long enough to read the digits pass, short enough to feel
  /// like an answer to the tap that changed it.
  static const Duration rollDuration = Duration(milliseconds: 450);
  static const Curve rollCurve = Curves.easeOutCubic;

  static String thousandsOf(int v) {
    final neg = v < 0;
    final s = v.abs().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return neg ? '-$b' : b.toString();
  }

  /// True when [s] is something worth rolling: it has a digit and nothing
  /// but digits, separators, signs and short unit letters (h, m).
  static bool isRollable(String s) =>
      s.isNotEmpty && _hasDigit.hasMatch(s) && _rollable.hasMatch(s);
  static final RegExp _hasDigit = RegExp(r'\d');
  static final RegExp _rollable = RegExp(r'^[-+]?[\d.,]+(?:[hm]?(?: \d+[hm])?)?$');

  @override
  State<KRollingNumber> createState() => _KRollingNumberState();
}

class _KRollingNumberState extends State<KRollingNumber> {
  // After the first frame, a column that appears (999 to 1,000) rolls up
  // from 0 rather than popping in.
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    // Measure and draw with the same, fully resolved style.
    final st = DefaultTextStyle.of(context).style.merge(
          widget.style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        );
    final d = KMotion.of(context, widget.duration ?? KRollingNumber.rollDuration);
    final text = widget.text;
    final n = text.length;
    final newFromZero = widget.fromZero || _shown;
    _shown = true;
    return RepaintBoundary(
      child: Semantics(
        label: widget.semanticsLabel ?? text,
        excludeSemantics: true,
        // Too wide for its slot (big text, a narrow ring): shrink to fit
        // rather than overflow, the way a scaleDown FittedBox would.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: widget.alignment,
          child: AnimatedSize(
            duration: d,
            curve: KRollingNumber.rollCurve,
            alignment: widget.alignment,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                for (var i = 0; i < n; i++)
                  // Keyed from the right so adding a digit on the left doesn't
                  // make every other column roll.
                  _isDigit(text.codeUnitAt(i))
                      ? _DigitColumn(
                          key: ValueKey('d${n - i}'),
                          digit: text.codeUnitAt(i) - 48,
                          style: st,
                          duration: d,
                          fromZero: newFromZero,
                        )
                      : Text(text[i], key: ValueKey('c${n - i}${text[i]}'), style: st),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static bool _isDigit(int c) => c >= 48 && c <= 57;
}

class _DigitColumn extends StatefulWidget {
  final int digit;
  final TextStyle style;
  final Duration duration;
  final bool fromZero;
  const _DigitColumn({super.key, required this.digit, required this.style, required this.duration, this.fromZero = false});

  @override
  State<_DigitColumn> createState() => _DigitColumnState();
}

class _DigitColumnState extends State<_DigitColumn> {
  // Glyph metrics, measured once per style / text scale, not every build.
  TextStyle? _measuredStyle;
  TextScaler? _measuredScaler;
  double _w = 0, _h = 0, _baseline = 0;
  Widget? _strip;

  void _measure(TextScaler scaler) {
    if (_measuredStyle == widget.style && _measuredScaler == scaler) return;
    final tp = TextPainter(
      text: TextSpan(text: '0', style: widget.style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    _w = tp.width;
    _h = tp.height;
    _baseline = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    tp.dispose();
    _measuredStyle = widget.style;
    _measuredScaler = scaler;
    // The 0 to 9 strip is laid out once and only translated while rolling.
    _strip = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var n = 0; n <= 9; n++)
          SizedBox(width: _w, height: _h, child: Text('$n', style: widget.style, maxLines: 1, softWrap: false)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    _measure(MediaQuery.textScalerOf(context));
    final h = _h;
    return _Baseline(
      baseline: _baseline,
      child: SizedBox(
        width: _w,
        height: h,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minHeight: 0,
            maxHeight: double.infinity,
            child: TweenAnimationBuilder<double>(
              // `begin` is read once, at mount; later changes of `end` roll
              // from wherever the column is now.
              tween: Tween(begin: widget.fromZero ? 0.0 : null, end: widget.digit.toDouble()),
              duration: widget.duration,
              curve: KRollingNumber.rollCurve,
              child: _strip,
              builder: (context, v, strip) => Transform.translate(
                offset: Offset(0, -v * h),
                child: strip,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lets a fixed-size box take part in a baseline-aligned Row.
class _Baseline extends SingleChildRenderObjectWidget {
  final double baseline;
  const _Baseline({required this.baseline, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderBaseline(baseline);

  @override
  void updateRenderObject(BuildContext context, _RenderBaseline renderObject) => renderObject.value = baseline;
}

class _RenderBaseline extends RenderProxyBox {
  _RenderBaseline(this._value);
  double _value;
  set value(double v) {
    if (v == _value) return;
    _value = v;
    markNeedsLayout();
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => _value;
}
