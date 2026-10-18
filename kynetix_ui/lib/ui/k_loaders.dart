// Kynetix loaders: brand-consistent waiting states. See docs/DESIGN_SYSTEM.md.
//
// Every loader here follows the same contract:
//  * Monochrome ink chrome; the data colours (ember / mint / saffron / violet /
//    cyan) appear only as accents, read from the active palette in `build`.
//  * One AnimationController per widget, painted with a CustomPainter that
//    repaints from the controller (no rebuilds per frame), inside a
//    RepaintBoundary.
//  * Loops run only while `KLoaders.ambient(context)` is true (never under
//    reduced motion, never under `flutter test` unless a test opts in). When
//    motion is off each loader rests on a composed, legible static frame, so
//    the waiting state still reads as "loading" without movement.
//  * Loader copy follows docs/VOICE.md and rotates no faster than every 2.6s.
//
// Moment catalog
//  KOrbitLoader   brand / full-screen / app boot. Loop 3.6s.
//  KMacroLoader   nutrition and Kyno estimation waits. Loop 2.4s.
//  KRepLoader     workout and history waits. Loop 3.9s (three reps).
//  KSpinner       inline + inside buttons. Loop 1.4s.
//  KLoadingLabel  rotating VOICE.md lines, 2.8s per line.
//  KLoaderPanel   centred loader + label, a live region announced "Loading".
//  KPulseLoader / KLoadingDots are the legacy names, upgraded.
//  KShimmer*      calm static skeleton with a slow opacity pulse (1.8s);
//                 KSkeletonSwitcher cross-fades it to content.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config/app_theme.dart';

const double _tau = math.pi * 2;

// ─── Gate ─────────────────────────────────────────────────────────────────────

abstract class KLoaders {
  /// Lets a widget test exercise the running loops. `KMotion.ambientAllowed`
  /// is always false under `flutter test`; this flips only that part. Reduced
  /// motion still wins.
  @visibleForTesting
  static bool debugForceAmbient = false;

  /// Whether loader loops may run in this context.
  static bool ambient(BuildContext context) =>
      !KMotion.reduced(context) &&
      (debugForceAmbient || KMotion.ambientAllowed(context));

  /// Minimum time each loading line stays on screen (VOICE.md: >= 2.5s).
  static const Duration messageDwell = Duration(milliseconds: 2800);
}

/// Shared lifecycle for every loader: one controller, started only when
/// ambient motion is allowed, otherwise parked on [rest].
mixin _KLoop<T extends StatefulWidget>
    on State<T>, SingleTickerProviderStateMixin<T> {
  Duration get period;
  double get rest;

  late final AnimationController loop = AnimationController(
    vsync: this,
    duration: period,
    value: rest,
  );

  bool get running => loop.isAnimating;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncLoop();
  }

  void syncLoop() {
    if (KLoaders.ambient(context)) {
      final d = KMotion.of(context, period);
      if (loop.duration != d) {
        loop.duration = d;
        if (loop.isAnimating) loop.repeat();
      }
      if (!loop.isAnimating) loop.repeat();
    } else {
      if (loop.isAnimating) loop.stop();
      loop.value = rest;
    }
  }

  @override
  void dispose() {
    loop.dispose();
    super.dispose();
  }
}

Widget _labelled(String? label, Widget child) {
  if (label == null) return ExcludeSemantics(child: child);
  return Semantics(
    label: label,
    container: true,
    child: ExcludeSemantics(child: child),
  );
}

double _ease(double x) =>
    x < 0.5 ? 4 * x * x * x : 1 - math.pow(-2 * x + 2, 3) / 2; // easeInOutCubic

// ─── KOrbitLoader ─────────────────────────────────────────────────────────────
// The brand loader: three thin orbits (fuel, protein, train) with comet heads
// around a breathing ink core. Echoes the sign-in KineticOrbit.

class KOrbitLoader extends StatefulWidget {
  const KOrbitLoader({
    super.key,
    this.size = 56,
    Color? color,
    this.semanticsLabel = 'Loading',
  }) : _color = color;

  final double size;
  final Color? _color;

  /// Null paints the brand tri-colour. A colour tints all three comets.
  Color? get color => _color;
  final String? semanticsLabel;

  @override
  State<KOrbitLoader> createState() => _KOrbitLoaderState();
}

class _KOrbitLoaderState extends State<KOrbitLoader>
    with SingleTickerProviderStateMixin, _KLoop {
  @override
  Duration get period => const Duration(milliseconds: 3600);
  @override
  double get rest => 0.14;

  @override
  Widget build(BuildContext context) {
    final dark = KColor.isDark;
    final tint = widget.color;
    final comets = tint == null
        // One accent comet; the other two are ink and a set-back ink tint.
        ? [KColor.ember, KColor.ink, KColor.fat]
        : [tint, tint.withValues(alpha: 0.75), tint.withValues(alpha: 0.5)];
    return _labelled(
      widget.semanticsLabel,
      SizedBox.square(
        dimension: widget.size,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _OrbitLoaderPainter(
              t: loop,
              track: KColor.fg.withValues(alpha: dark ? 0.10 : 0.12),
              core: KColor.ink,
              c0: comets[0],
              c1: comets[1],
              c2: comets[2],
              cometAlpha: dark ? 1.0 : 0.92,
            ),
          ),
        ),
      ),
    );
  }
}

class _OrbitLoaderPainter extends CustomPainter {
  _OrbitLoaderPainter({
    required this.t,
    required this.track,
    required this.core,
    required this.c0,
    required this.c1,
    required this.c2,
    required this.cometAlpha,
  }) : super(repaint: t);

  final Animation<double> t;
  final Color track, core, c0, c1, c2;
  final double cometAlpha;

  // Radius (fraction of half-size), integer turns per loop (seamless), start
  // angle and base comet length in radians.
  static const _radii = [0.42, 0.70, 0.97];
  static const _turns = [2, -1, 1];
  static const _start = [0.4, 2.6, 4.4];
  static const _sweep = [2.0, 1.6, 1.25];
  static const _segments = 14;

  final Paint _track = Paint()..style = PaintingStyle.stroke;
  final Paint _arc = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final Paint _fill = Paint()..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final head = (s * 0.05).clamp(1.4, 3.6).toDouble();
    final stroke = (s * 0.036).clamp(1.2, 2.6).toDouble();
    final c = size.center(Offset.zero);
    final half = s / 2 - head - 0.5;
    final v = t.value;

    _track
      ..color = track
      ..strokeWidth = (s * 0.012).clamp(0.6, 1.0).toDouble();
    _arc.strokeWidth = stroke;

    for (var i = 0; i < 3; i++) {
      final color = i == 0 ? c0 : (i == 1 ? c1 : c2);
      final r = half * _radii[i];
      canvas.drawCircle(c, r, _track);

      final dir = _turns[i] >= 0 ? 1.0 : -1.0;
      final angle = _start[i] + v * _tau * _turns[i];
      // Comet length breathes gently (integer frequency keeps it seamless).
      final sweep =
          _sweep[i] * (0.82 + 0.18 * math.sin(_tau * (v * 2 + i / 3)));
      final rect = Rect.fromCircle(center: c, radius: r);
      final seg = sweep / _segments;
      for (var k = 0; k < _segments; k++) {
        final f = (k + 1) / _segments; // tail 0 → head 1
        _arc.color = color.withValues(alpha: color.a * cometAlpha * f * f);
        canvas.drawArc(
          rect,
          angle - dir * sweep + dir * seg * k,
          dir * seg,
          false,
          _arc,
        );
      }
      final p = c + Offset.fromDirection(angle, r);
      _fill.color = color.withValues(alpha: color.a * cometAlpha * 0.18);
      canvas.drawCircle(p, head * 2.1, _fill);
      _fill.color = color.withValues(alpha: color.a * cometAlpha);
      canvas.drawCircle(p, head, _fill);
    }

    // Ink core: two slow breaths per loop.
    final breath = 0.5 - 0.5 * math.cos(_tau * v * 2);
    _fill.color = core.withValues(alpha: 0.10 + 0.08 * breath);
    canvas.drawCircle(c, half * 0.22 * (1 + 0.12 * breath), _fill);
    _fill.color = core.withValues(alpha: 0.9);
    canvas.drawCircle(c, (half * 0.085).clamp(1.2, 5.0).toDouble(), _fill);
  }

  @override
  bool shouldRepaint(covariant _OrbitLoaderPainter old) =>
      old.t != t ||
      old.track != track ||
      old.core != core ||
      old.c0 != c0 ||
      old.c1 != c1 ||
      old.c2 != c2 ||
      old.cometAlpha != cometAlpha;
}

// ─── KMacroLoader ─────────────────────────────────────────────────────────────
// Three rounded macro bars (calories ember, protein mint, carbs saffron) that
// rise and fall like an equaliser over faint full-height ghosts.

class KMacroLoader extends StatefulWidget {
  const KMacroLoader({
    super.key,
    this.size = 44,
    this.semanticsLabel = 'Loading',
  });

  final double size;
  final String? semanticsLabel;

  @override
  State<KMacroLoader> createState() => _KMacroLoaderState();
}

class _KMacroLoaderState extends State<KMacroLoader>
    with SingleTickerProviderStateMixin, _KLoop {
  @override
  Duration get period => const Duration(milliseconds: 2400);
  @override
  double get rest => 0.0;

  @override
  Widget build(BuildContext context) {
    return _labelled(
      widget.semanticsLabel,
      SizedBox.square(
        dimension: widget.size,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _MacroPainter(
              t: loop,
              running: running,
              // Calories, protein, carbs: the same series colours as the app.
              c0: KColor.calorie,
              c1: KColor.protein,
              c2: KColor.carbs,
              ghostAlpha: KColor.isDark ? 0.14 : 0.16,
            ),
          ),
        ),
      ),
    );
  }
}

class _MacroPainter extends CustomPainter {
  _MacroPainter({
    required this.t,
    required this.running,
    required this.c0,
    required this.c1,
    required this.c2,
    required this.ghostAlpha,
  }) : super(repaint: t);

  final Animation<double> t;
  final bool running;
  final Color c0, c1, c2;
  final double ghostAlpha;

  // Two integer harmonics per bar so the loop is seamless but never in sync.
  static const _k1 = [1, 2, 1];
  static const _k2 = [2, 3, 3];
  static const _o1 = [0.0, 0.30, 0.62];
  static const _o2 = [0.15, 0.55, 0.85];
  static const _restLevels = [0.62, 0.92, 0.48];

  final Paint _p = Paint()..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final barW = s * 0.2;
    final gap = s * 0.12;
    final total = barW * 3 + gap * 2;
    final left = (size.width - total) / 2;
    final top = (size.height - s) / 2 + s * 0.08;
    final bottom = top + s * 0.84;
    final h = bottom - top;
    final radius = Radius.circular(barW / 2);
    final v = t.value;

    for (var i = 0; i < 3; i++) {
      final color = i == 0 ? c0 : (i == 1 ? c1 : c2);
      final x = left + i * (barW + gap);
      _p.color = color.withValues(alpha: ghostAlpha);
      canvas.drawRRect(RRect.fromLTRBR(x, top, x + barW, bottom, radius), _p);

      double level;
      if (running) {
        final a = 0.5 - 0.5 * math.cos(_tau * (v * _k1[i] + _o1[i]));
        final b = 0.5 - 0.5 * math.cos(_tau * (v * _k2[i] + _o2[i]));
        level = 0.24 + 0.76 * (0.65 * a + 0.35 * b);
      } else {
        level = _restLevels[i];
      }
      final barTop = bottom - math.max(barW, h * level);
      _p.color = color;
      canvas.drawRRect(
        RRect.fromLTRBR(x, barTop, x + barW, bottom, radius),
        _p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MacroPainter old) =>
      old.t != t ||
      old.running != running ||
      old.c0 != c0 ||
      old.c1 != c1 ||
      old.c2 != c2 ||
      old.ghostAlpha != ghostAlpha;
}

// ─── KRepLoader ───────────────────────────────────────────────────────────────
// A barbell plate whose rim fills like a rep, snaps full, fades and resets.
// Three pips on the hub count the reps in each set.

class KRepLoader extends StatefulWidget {
  const KRepLoader({
    super.key,
    this.size = 52,
    this.semanticsLabel = 'Loading',
  });

  final double size;
  final String? semanticsLabel;

  @override
  State<KRepLoader> createState() => _KRepLoaderState();
}

class _KRepLoaderState extends State<KRepLoader>
    with SingleTickerProviderStateMixin, _KLoop {
  @override
  Duration get period => const Duration(milliseconds: 3900);
  // Rest: second rep, rim ~70% full, one pip lit.
  @override
  double get rest => (1 + 0.5) / 3;

  @override
  Widget build(BuildContext context) {
    final dark = KColor.isDark;
    return _labelled(
      widget.semanticsLabel,
      SizedBox.square(
        dimension: widget.size,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _RepPainter(
              t: loop,
              track: KColor.fg.withValues(alpha: dark ? 0.10 : 0.12),
              hub: KColor.fg.withValues(alpha: dark ? 0.22 : 0.26),
              ink: KColor.ink,
              arc: KColor.ink,
              head: KColor.ember,
            ),
          ),
        ),
      ),
    );
  }
}

class _RepPainter extends CustomPainter {
  _RepPainter({
    required this.t,
    required this.track,
    required this.hub,
    required this.ink,
    required this.arc,
    required this.head,
  }) : super(repaint: t);

  final Animation<double> t;
  final Color track, hub, ink, arc, head;

  static const _reps = 3;
  static const _fill = 0.72; // share of each rep spent filling

  final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final Paint _dot = Paint()..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = size.center(Offset.zero);
    final w = (s * 0.085).clamp(2.0, 5.0).toDouble();
    final r = s / 2 - w;

    final phase = t.value * _reps;
    final rep = phase.floor() % _reps;
    final u = phase - phase.floor();

    double progress;
    double alpha;
    double swell;
    int lit;
    if (u < _fill) {
      progress = _ease(u / _fill);
      alpha = 1;
      swell = 0;
      lit = rep;
    } else {
      final d = (u - _fill) / (1 - _fill);
      progress = 1;
      alpha = 1 - Curves.easeIn.transform(d);
      swell = math.sin(math.pi * d);
      lit = rep + 1;
    }

    // Plate rim track.
    _stroke
      ..color = track
      ..strokeWidth = w;
    canvas.drawCircle(c, r, _stroke);

    // Rep arc.
    if (progress > 0.001) {
      _stroke
        ..color = arc.withValues(alpha: alpha)
        ..strokeWidth = w * (1 + 0.25 * swell);
      const start = -math.pi / 2;
      final sweep = _tau * progress;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        start,
        sweep,
        false,
        _stroke,
      );
      _dot.color = head.withValues(alpha: alpha);
      canvas.drawCircle(
        c + Offset.fromDirection(start + sweep, r),
        w * 0.62 * (1 + 0.25 * swell),
        _dot,
      );
    }

    // Hub hairline and rep pips.
    final hubR = r * 0.46;
    _stroke
      ..color = hub
      ..strokeWidth = (s * 0.02).clamp(0.75, 1.25).toDouble();
    canvas.drawCircle(c, hubR, _stroke);
    final pip = (s * 0.04).clamp(1.2, 2.6).toDouble();
    final spacing = pip * 3;
    for (var i = 0; i < _reps; i++) {
      final on = i < lit;
      _dot.color = on ? ink : hub;
      canvas.drawCircle(c + Offset((i - 1) * spacing, 0), pip, _dot);
    }
  }

  @override
  bool shouldRepaint(covariant _RepPainter old) =>
      old.t != t ||
      old.track != track ||
      old.hub != hub ||
      old.ink != ink ||
      old.arc != arc ||
      old.head != head;
}

// ─── KSpinner ─────────────────────────────────────────────────────────────────
// A tiny arc spinner for buttons and inline spots. Replaces raw
// CircularProgressIndicator. Inside an ink KButton pass `KColor.onInk`.

class KSpinner extends StatefulWidget {
  const KSpinner({super.key, this.size = 20, Color? color, this.semanticsLabel})
    : _color = color;

  final double size;
  final Color? _color;
  Color get color => _color ?? KColor.textPrimary;

  /// Null by default: inside a button the button already speaks.
  final String? semanticsLabel;

  @override
  State<KSpinner> createState() => _KSpinnerState();
}

class _KSpinnerState extends State<KSpinner>
    with SingleTickerProviderStateMixin, _KLoop {
  @override
  Duration get period => const Duration(milliseconds: 1400);
  @override
  double get rest => 0.0;

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    return _labelled(
      widget.semanticsLabel,
      SizedBox.square(
        dimension: widget.size,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _SpinnerPainter(
              t: loop,
              running: running,
              color: color,
              track: color.withValues(alpha: color.a * 0.16),
            ),
          ),
        ),
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  _SpinnerPainter({
    required this.t,
    required this.running,
    required this.color,
    required this.track,
  }) : super(repaint: t);

  final Animation<double> t;
  final bool running;
  final Color color, track;

  final Paint _p = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final w = (s * 0.11).clamp(1.6, 3.0).toDouble();
    final c = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: c, radius: s / 2 - w / 2);

    _p
      ..strokeWidth = w
      ..color = track;
    canvas.drawCircle(c, s / 2 - w / 2, _p);

    _p.color = color;
    if (!running) {
      canvas.drawArc(rect, -math.pi / 2, _tau * 0.3, false, _p);
      return;
    }
    final v = t.value;
    // Two turns per loop; the arc stretches and contracts once per loop.
    final length = _tau * (0.10 + 0.52 * (0.5 - 0.5 * math.cos(_tau * v)));
    final headAngle = -math.pi / 2 + _tau * v * 2 + 0.6 * math.sin(_tau * v);
    canvas.drawArc(rect, headAngle - length, length, false, _p);
  }

  @override
  bool shouldRepaint(covariant _SpinnerPainter old) =>
      old.t != t ||
      old.running != running ||
      old.color != color ||
      old.track != track;
}

// ─── KLoadingLabel ────────────────────────────────────────────────────────────
// Crossfades through loader lines, one every 2.8s. Static (first line) when
// motion is off. Screen readers get the first line only, so it isn't chatty.

class KLoadingLabel extends StatefulWidget {
  const KLoadingLabel({
    super.key,
    required this.messages,
    this.style,
    this.textAlign = TextAlign.center,
  });

  final List<String> messages;
  final TextStyle? style;
  final TextAlign textAlign;

  @override
  State<KLoadingLabel> createState() => _KLoadingLabelState();
}

class _KLoadingLabelState extends State<KLoadingLabel>
    with SingleTickerProviderStateMixin, _KLoop {
  int get _n => math.max(1, widget.messages.length);

  @override
  Duration get period => KLoaders.messageDwell * _n;
  @override
  double get rest => 0.0;

  @override
  void syncLoop() {
    if (widget.messages.length < 2) {
      if (loop.isAnimating) loop.stop();
      loop.value = rest;
      return;
    }
    super.syncLoop();
  }

  @override
  void didUpdateWidget(covariant KLoadingLabel old) {
    super.didUpdateWidget(old);
    if (!listEquals(old.messages, widget.messages)) {
      loop.value = rest;
      syncLoop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.messages;
    if (messages.isEmpty) return const SizedBox.shrink();
    final style =
        widget.style ?? KText.bodyMedium.copyWith(color: KColor.textSecondary);

    Widget line(String text) =>
        Text(text, style: style, textAlign: widget.textAlign);

    return Semantics(
      container: true,
      label: messages.first,
      child: ExcludeSemantics(
        // Own layer: the line's per-frame fade never repaints the panel.
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: loop,
            builder: (context, _) {
              if (!running) return line(messages.first);
              final phase = loop.value * messages.length;
              final i = phase.floor() % messages.length;
              final u = phase - phase.floor();
              const edge = 0.11; // ~300ms fade each side of a 2.8s dwell
              final o = u < edge
                  ? u / edge
                  : (u > 1 - edge ? (1 - u) / edge : 1.0);
              final eased = Curves.easeOut.transform(o.clamp(0.0, 1.0));
              return Opacity(
                opacity: eased,
                child: Transform.translate(
                  offset: Offset(0, (1 - eased) * (u < 0.5 ? 4 : -4)),
                  child: line(messages[i]),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ─── KLoaderPanel ─────────────────────────────────────────────────────────────
// Centred loader plus a rotating label. Announced once as a live region.

class KLoaderPanel extends StatelessWidget {
  const KLoaderPanel({
    super.key,
    this.loader,
    this.messages = const [],
    this.semanticsLabel,
  });

  /// Defaults to [KOrbitLoader].
  final Widget? loader;
  final List<String> messages;

  /// Spoken label; defaults to "Loading".
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: semanticsLabel ?? 'Loading',
      value: messages.isEmpty ? null : messages.first,
      child: ExcludeSemantics(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: KSpacing.p),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                loader ?? const KOrbitLoader(size: 64, semanticsLabel: null),
                if (messages.isNotEmpty) ...[
                  const SizedBox(height: KSpacing.xl),
                  KLoadingLabel(messages: messages),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── KPulseLoader (legacy name) ──────────────────────────────────────────────
// Now the orbit look. Same constructor; `size` is the old core disc, so the
// orbit is drawn a little larger to keep the old visual footprint.

class KPulseLoader extends StatelessWidget {
  final double size;
  final Color? _color;
  Color get color => _color ?? KColor.green;

  const KPulseLoader({super.key, this.size = 40.0, Color? color})
    : _color = color;

  @override
  Widget build(BuildContext context) =>
      KOrbitLoader(size: size * 1.5, color: _color);
}

// ─── KLoadingDots (legacy name) ──────────────────────────────────────────────
// Three dots with a soft travelling swell (scale + opacity), no bounce. Same
// footprint as before: 3 × (size + 4) wide, size tall.

class KLoadingDots extends StatefulWidget {
  final double size;
  final Color? _color;
  Color get color => _color ?? KColor.textSecondary;

  const KLoadingDots({super.key, this.size = 6.0, Color? color})
    : _color = color;

  @override
  State<KLoadingDots> createState() => _KLoadingDotsState();
}

class _KLoadingDotsState extends State<KLoadingDots>
    with SingleTickerProviderStateMixin, _KLoop {
  @override
  Duration get period => const Duration(milliseconds: 1200);
  @override
  double get rest => 0.0;

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return ExcludeSemantics(
      child: SizedBox(
        width: 3 * (s + 4),
        height: s,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _DotsPainter(
              t: loop,
              running: running,
              color: widget.color,
            ),
          ),
        ),
      ),
    );
  }
}

class _DotsPainter extends CustomPainter {
  _DotsPainter({required this.t, required this.running, required this.color})
    : super(repaint: t);

  final Animation<double> t;
  final bool running;
  final Color color;

  static const _restAlpha = [1.0, 0.62, 0.32];

  final Paint _p = Paint()..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.height / 2;
    final step = size.width / 3;
    for (var i = 0; i < 3; i++) {
      double a;
      double scale;
      if (running) {
        // A swell that travels left to right, then rests briefly.
        final x = (t.value - i * 0.16) % 1.0;
        final w = x < 0.6 ? math.sin(math.pi * x / 0.6) : 0.0;
        a = 0.32 + 0.68 * w;
        scale = 0.72 + 0.28 * w;
      } else {
        a = _restAlpha[i];
        scale = 1;
      }
      _p.color = color.withValues(alpha: color.a * a);
      canvas.drawCircle(Offset(step * i + step / 2, r), r * scale, _p);
    }
  }

  @override
  bool shouldRepaint(covariant _DotsPainter old) =>
      old.t != t || old.running != running || old.color != color;
}

// ─── KShimmer family (skeletons) ─────────────────────────────────────────────
// A calm static skeleton: the child's shapes are painted in ink at ~6-7%
// alpha (children are masks; their own colour is ignored, use any opaque
// fill), breathing with a slow opacity pulse. No sweeping sheen.
//
// Cost: the tint is a static colour filter inside a RepaintBoundary, and the
// pulse is a FadeTransition, so a frame only changes one opacity value on a
// cached layer (no ShaderMask, no rebuild, no repaint). The pulse runs only
// while ambient motion is allowed: it parks at full opacity under reduced
// motion and in tests, and its ticker stops with TickerMode (an offstage tab
// or a covered route).
//
// Pair with [KSkeletonSwitcher] to cross-fade from the skeleton to content.

class KShimmer extends StatefulWidget {
  final Widget child;
  final bool enabled;

  const KShimmer({super.key, required this.child, this.enabled = true});

  @override
  State<KShimmer> createState() => _KShimmerState();
}

class _KShimmerState extends State<KShimmer>
    with SingleTickerProviderStateMixin, _KLoop {
  @override
  Duration get period => const Duration(milliseconds: 1800);
  // Rest is full opacity: a clean, flat skeleton when static.
  @override
  double get rest => 0.0;

  late final Animation<double> _pulse = loop.drive(const _Breath());

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final tone = KColor.ink.withValues(alpha: KColor.isDark ? 0.07 : 0.06);
    return RepaintBoundary(
      child: FadeTransition(
        opacity: _pulse,
        child: ColorFiltered(
          colorFilter: ColorFilter.mode(tone, BlendMode.srcIn),
          child: widget.child,
        ),
      ),
    );
  }
}

/// One slow breath per loop: full opacity at rest, down to 55% and back.
class _Breath extends Animatable<double> {
  const _Breath();

  @override
  double transform(double t) => 1.0 - 0.45 * (0.5 - 0.5 * math.cos(_tau * t));
}

/// Cross-fades from a skeleton to the real content when [loading] turns
/// false (and back, if it turns true again). Instant under reduced motion.
class KSkeletonSwitcher extends StatelessWidget {
  const KSkeletonSwitcher({
    super.key,
    required this.loading,
    required this.skeleton,
    required this.child,
    this.duration = KMotion.standard,
  });

  final bool loading;
  final Widget skeleton;
  final Widget child;
  final Duration duration;

  static Widget _stackTop(Widget? current, List<Widget> previous) =>
      Stack(alignment: Alignment.topCenter, children: [...previous, ?current]);

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: KMotion.of(context, duration),
      switchInCurve: KMotion.easeOut,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: _stackTop,
      child: loading
          ? KeyedSubtree(key: const ValueKey('k-skeleton'), child: skeleton)
          : KeyedSubtree(key: const ValueKey('k-content'), child: child),
    );
  }
}

class KShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;

  const KShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return KShimmer(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white, // mask only; KShimmer tints it
          borderRadius: borderRadius ?? KRadius.md,
        ),
      ),
    );
  }
}

Widget _mask(double? w, double h, double r) => Container(
  width: w,
  height: h,
  decoration: BoxDecoration(
    color: Colors.white, // mask only
    borderRadius: BorderRadius.circular(r),
  ),
);

class KCardShimmer extends StatelessWidget {
  final double height;
  const KCardShimmer({super.key, this.height = 100});

  @override
  Widget build(BuildContext context) {
    return KCard(
      child: SizedBox(
        height: height,
        child: KShimmer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _mask(120, 16, 8),
              const SizedBox(height: 12),
              _mask(double.infinity, 12, 6),
              const SizedBox(height: 8),
              _mask(200, 12, 6),
            ],
          ),
        ),
      ),
    );
  }
}

class KChartShimmer extends StatelessWidget {
  final double height;
  const KChartShimmer({super.key, this.height = 140});

  @override
  Widget build(BuildContext context) {
    return KCard(
      child: SizedBox(
        height: height,
        child: KShimmer(
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [_mask(80, 16, 8), _mask(40, 12, 6)],
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(7, (index) {
                  final barHeight = (index % 3 == 0)
                      ? 60.0
                      : (index % 2 == 0 ? 100.0 : 40.0);
                  return _mask(20, barHeight, 6);
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class KMessageShimmer extends StatelessWidget {
  const KMessageShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: KShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _mask(32, 32, 16),
                const SizedBox(width: 8),
                _mask(200, 48, 16),
              ],
            ),
            const SizedBox(height: 16),
            Align(alignment: Alignment.centerRight, child: _mask(140, 40, 16)),
          ],
        ),
      ),
    );
  }
}
