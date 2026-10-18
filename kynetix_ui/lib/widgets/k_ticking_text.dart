import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// Clock-style text ("01:24") whose digits tick over one at a time.
///
/// Each digit is its own fixed-width tabular cell, so only the digits that
/// changed move (a short slide and fade inside a clip) and the run never
/// changes width as it counts: no layout shift once a second. Separators
/// (":" and the like) are plain text. Under reduced motion the new digit
/// simply replaces the old one. Screen readers get [semanticsLabel] (or the
/// whole string) once, never the moving glyphs.
class KTickingText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final String? semanticsLabel;

  /// True for a countdown: new digits drop in from above. False (the
  /// default) for a count-up: new digits rise from below.
  final bool countdown;

  const KTickingText(
    this.text, {
    super.key,
    required this.style,
    this.semanticsLabel,
    this.countdown = false,
  });

  static const Duration tick = Duration(milliseconds: 240);

  @override
  Widget build(BuildContext context) {
    final st = style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final d = KMotion.of(context, tick);
    final chars = text.split('');
    return Semantics(
      label: semanticsLabel ?? text,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < chars.length; i++)
            // Keyed from the right so a new leading digit doesn't make every
            // other cell animate.
            _isDigit(chars[i])
                ? _TickCell(
                    key: ValueKey('t${chars.length - i}'),
                    char: chars[i],
                    style: st,
                    duration: d,
                    countdown: countdown,
                  )
                : Text(chars[i], style: st),
        ],
      ),
    );
  }

  static bool _isDigit(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;
}

class _TickCell extends StatelessWidget {
  final String char;
  final TextStyle style;
  final Duration duration;
  final bool countdown;

  const _TickCell({
    super.key,
    required this.char,
    required this.style,
    required this.duration,
    required this.countdown,
  });

  @override
  Widget build(BuildContext context) {
    final incomingKey = ValueKey(char);
    // Count-up: new digit rises from below, old one leaves upward.
    final enterFrom = countdown ? -0.5 : 0.5;
    return ClipRect(
      child: AnimatedSwitcher(
        duration: duration,
        switchInCurve: KMotion.decelerate,
        switchOutCurve: KMotion.accelerate,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.center,
          children: [...previous, ?current],
        ),
        transitionBuilder: (child, anim) {
          final incoming = child.key == incomingKey;
          final offset = Tween<Offset>(
            begin: Offset(0, incoming ? enterFrom : -enterFrom),
            end: Offset.zero,
          ).animate(anim);
          return FadeTransition(
            opacity: anim,
            child: SlideTransition(position: offset, child: child),
          );
        },
        child: Text(char, key: incomingKey, style: style),
      ),
    );
  }
}
