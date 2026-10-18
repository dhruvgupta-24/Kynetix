import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../config/app_theme.dart';

/// A number whose digits roll like an odometer when it changes.
///
/// Each digit is its own column of 0–9 sliding under a clip, so only the
/// digits that changed move. Tabular figures keep the width steady. Under
/// reduced motion the new value just appears. Screen readers get the whole
/// number once, never the rolling glyphs.
class KRollingNumber extends StatelessWidget {
  final String text;
  final TextStyle style;
  final Duration? duration;
  final String? semanticsLabel;

  /// Roll up from 0 the first time it shows (a reveal), not only on change.
  final bool fromZero;

  const KRollingNumber(this.text, {super.key, required this.style, this.duration, this.semanticsLabel, this.fromZero = false});

  /// Formats an int with Indian-style thousands commas, e.g. 2,350.
  KRollingNumber.int(int value, {Key? key, required TextStyle style, Duration? duration, String? semanticsLabel, bool fromZero = false})
      : this(thousandsOf(value), key: key, style: style, duration: duration, semanticsLabel: semanticsLabel, fromZero: fromZero);

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

  @override
  Widget build(BuildContext context) {
    final st = style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final d = KMotion.of(context, duration ?? KMotion.emphasized);
    final chars = text.split('');
    return Semantics(
      label: semanticsLabel ?? text,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          for (var i = 0; i < chars.length; i++)
            // Keyed from the right so adding a digit on the left doesn't
            // make every other column roll.
            _isDigit(chars[i])
                ? _DigitColumn(key: ValueKey('d${chars.length - i}'), digit: int.parse(chars[i]), style: st, duration: d, fromZero: fromZero)
                : Text(chars[i], style: st),
        ],
      ),
    );
  }

  static bool _isDigit(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;
}

class _DigitColumn extends StatelessWidget {
  final int digit;
  final TextStyle style;
  final Duration duration;
  final bool fromZero;
  const _DigitColumn({super.key, required this.digit, required this.style, required this.duration, this.fromZero = false});

  @override
  Widget build(BuildContext context) {
    final tp = TextPainter(
      text: TextSpan(text: '0', style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final w = tp.width;
    final h = tp.height;
    final baseline = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: fromZero ? 0.0 : null, end: digit.toDouble()),
      duration: duration,
      curve: KMotion.emphasizedCurve,
      builder: (context, v, _) {
        return _Baseline(
          baseline: baseline,
          child: SizedBox(
            width: w,
            height: h,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.topCenter,
                minHeight: 0,
                maxHeight: double.infinity,
                child: Transform.translate(
                  offset: Offset(0, -v * h),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var n = 0; n <= 9; n++)
                        SizedBox(height: h, child: Text('$n', style: style)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
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
  _RenderBaseline(this.value);
  double value;

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => value;
}
