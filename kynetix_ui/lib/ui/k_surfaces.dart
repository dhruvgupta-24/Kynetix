import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../config/app_theme.dart';

// ─── KTone ────────────────────────────────────────────────────────────────────
// The app's three worlds each own a light. The ambient aurora re-tints when you
// move between them, so the colour of the room tells you where you are.

enum KTone { fuel, train, kyno, neutral }

class _AuroraPalette {
  const _AuroraPalette(this.a, this.b, this.c);
  final Color a; // top-left key light
  final Color b; // right fill light
  final Color c; // bottom bounce

  // Graphite paints no aurora (auroraStrength is 0). If it is ever turned
  // back on, it stays inside the palette: one accent light, the rest ink.
  static _AuroraPalette of(KTone t) => switch (t) {
        KTone.neutral => _AuroraPalette(KColor.ink, KColor.ink, KColor.ink),
        _ => _AuroraPalette(KColor.ember, KColor.ink, KColor.ink),
      };

  static _AuroraPalette lerp(_AuroraPalette x, _AuroraPalette y, double t) =>
      _AuroraPalette(
        Color.lerp(x.a, y.a, t)!,
        Color.lerp(x.b, y.b, t)!,
        Color.lerp(x.c, y.c, t)!,
      );
}

// ─── KAurora ──────────────────────────────────────────────────────────────────
// Ambient light field: three very soft radial glows on the page background.
//
// Performance: the field is painted into its own RepaintBoundary and only
// repaints while it is changing — the one-shot tone crossfade when you move
// between worlds (during which the glows also glide to a new resting place),
// or a theme switch. There is no endless ticker: an always-running drift
// forced the whole screen (and the dock's backdrop) to be re-composited ~24
// times a second, forever, which competed with scrolling on mid-range phones.
// At rest the aurora costs nothing per frame. Pure gradients, no blur filters.

class KAurora extends StatefulWidget {
  const KAurora({
    super.key,
    this.tone = KTone.neutral,
    this.intensity = 1.0,
    this.child,
  });

  final KTone tone;

  /// 0..1 multiplier on glow strength (use lower for dense data screens).
  final double intensity;
  final Widget? child;

  @override
  State<KAurora> createState() => _KAuroraState();
}

class _KAuroraState extends State<KAurora> with SingleTickerProviderStateMixin {
  late final AnimationController _morph;

  late _AuroraPalette _from;
  late _AuroraPalette _to;
  late Brightness _brightness;

  /// Drift phase (0..1 = one full orbit of the glows). Each tone change glides
  /// the glows from [_phaseFrom] to [_phaseTo] along with the colour morph.
  double _phaseFrom = 0;
  double _phaseTo = 0;

  /// How far the glows travel on each world change (fraction of an orbit).
  static const _phaseStep = 0.14;

  @override
  void initState() {
    super.initState();
    _from = _to = _AuroraPalette.of(widget.tone);
    _brightness = KColor.palette.brightness;
    _morph = AnimationController(vsync: this, duration: KMotion.slow, value: 1);
  }

  @override
  void didUpdateWidget(covariant KAurora old) {
    super.didUpdateWidget(old);
    if (old.tone != widget.tone) {
      final t = KMotion.emphasizedCurve.transform(_morph.value);
      _from = _AuroraPalette.lerp(_from, _to, t);
      _to = _AuroraPalette.of(widget.tone);
      _phaseFrom = _phaseFrom + (_phaseTo - _phaseFrom) * t;
      _phaseTo = (_phaseFrom + _phaseStep) % 1.0;
      if (_phaseTo < _phaseFrom) _phaseFrom -= 1.0; // keep gliding forward
      final d = KMotion.of(context, KMotion.slow);
      if (d == Duration.zero) {
        _morph.value = 1;
      } else {
        _morph.duration = d;
        _morph.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _morph.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Theme switched: re-resolve the light colours for the new palette.
    if (_brightness != KColor.palette.brightness) {
      _brightness = KColor.palette.brightness;
      _from = _to = _AuroraPalette.of(widget.tone);
    }
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              isComplex: true,
              painter: _AuroraPainter(
                morph: _morph,
                from: () => _from,
                to: () => _to,
                phaseFrom: () => _phaseFrom,
                phaseTo: () => _phaseTo,
                intensity: widget.intensity,
                palette: KColor.palette,
                dpr: MediaQuery.devicePixelRatioOf(context),
              ),
            ),
          ),
        ),
        if (widget.child != null) KToneScope(tone: widget.tone, child: widget.child!),
      ],
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter({
    required this.morph,
    required this.from,
    required this.to,
    required this.phaseFrom,
    required this.phaseTo,
    required this.intensity,
    required this.palette,
    required this.dpr,
  }) : super(repaint: Listenable.merge([morph, _Grain.ready]));

  final KPalette palette;
  final double dpr;

  final Animation<double> morph;
  final _AuroraPalette Function() from;
  final _AuroraPalette Function() to;
  final double Function() phaseFrom;
  final double Function() phaseTo;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = palette.bg);
    // Grain: a fixed per-pixel speckle on the ground only (cards and text
    // sit above this layer), so flat fills read as a material instead of a
    // screen. One tiled image shader, static, a few percent strong.
    final grain = _Grain.tile(palette.isDark);
    if (grain != null) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = ImageShader(
            grain,
            TileMode.repeated,
            TileMode.repeated,
            // One grain texel per device pixel, whatever the density.
            Matrix4.diagonal3Values(1 / dpr, 1 / dpr, 1).storage,
            filterQuality: FilterQuality.none,
          ),
      );
    }

    final strength = intensity * palette.auroraStrength;
    // Graphite: no light field.
    if (strength <= 0) return;

    final m = KMotion.emphasizedCurve.transform(morph.value);
    final p = _AuroraPalette.lerp(from(), to(), m);
    final pf = phaseFrom();
    final phase = pf + (phaseTo() - pf) * m;
    final t = phase * 2 * math.pi;
    final w = size.width;
    final h = size.height;

    void glow(Color c, Offset center, double radius, double alpha) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      final paint = Paint()
        ..shader = ui.Gradient.radial(
          center,
          radius,
          [
            c.withValues(alpha: alpha * strength),
            c.withValues(alpha: alpha * 0.35 * strength),
            c.withValues(alpha: 0),
          ],
          const [0.0, 0.45, 1.0],
        );
      canvas.drawRect(rect, paint);
    }

    glow(
      p.a,
      Offset(w * (0.12 + 0.08 * math.sin(t)), h * (0.02 + 0.04 * math.cos(t))),
      w * 0.95,
      0.20,
    );
    glow(
      p.b,
      Offset(w * (0.98 + 0.06 * math.cos(t * 1.3)), h * (0.28 + 0.05 * math.sin(t))),
      w * 0.75,
      0.11,
    );
    glow(
      p.c,
      Offset(w * (0.35 + 0.10 * math.sin(t * 0.7)), h * (1.02 + 0.03 * math.cos(t))),
      w * 0.9,
      0.08,
    );
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter old) =>
      old.intensity != intensity || !identical(old.palette, palette) || old.dpr != dpr;
}

/// A 128 px tile of per-pixel noise, built once per brightness from a fixed
/// seed and decoded off the frame. Until it is ready nothing is drawn; the
/// aurora layer repaints once when it lands.
abstract final class _Grain {
  static const size = 128;

  /// Per-pixel swing around the ground tone, in 8-bit levels: about what
  /// full-range noise at 2.5% (Graphite) and 3% (Paper) opacity gives,
  /// but centred on the ground so its average tone does not shift.
  static const _darkSwing = 3.2;
  static const _lightSwing = 3.8;

  /// Tile alpha (of 255). Each texel is the ground tone offset by up to
  /// swing / alpha levels, so painted over the ground it moves it by at most
  /// the swing.
  static const _alpha8 = 77;
  static const _alpha = _alpha8 / 255;

  static ui.Image? _dark;
  static ui.Image? _light;
  static bool _started = false;

  /// Ticks when a tile has been decoded.
  static final ready = ValueNotifier<int>(0);

  static ui.Image? tile(bool dark) {
    if (!_started) {
      _started = true;
      _build(true);
      _build(false);
    }
    return dark ? _dark : _light;
  }

  static void _build(bool dark) {
    final rnd = math.Random(7);
    final px = Uint8List(size * size * 4);
    final bg = (dark ? KPalette.dark : KPalette.light).bg;
    final spread = (dark ? _darkSwing : _lightSwing) / _alpha;
    final base = [bg.r * 255, bg.g * 255, bg.b * 255];
    for (var i = 0; i < px.length; i += 4) {
      // One luminance offset per pixel (no colour noise), premultiplied.
      final n = (rnd.nextDouble() * 2 - 1) * spread;
      for (var c = 0; c < 3; c++) {
        final g = (base[c] + n).clamp(0.0, 255.0);
        px[i + c] = (g * _alpha).round();
      }
      px[i + 3] = _alpha8;
    }
    ui.decodeImageFromPixels(px, size, size, ui.PixelFormat.rgba8888, (img) {
      if (dark) {
        _dark = img;
      } else {
        _light = img;
      }
      ready.value++;
    });
  }
}

// ─── KPage ────────────────────────────────────────────────────────────────────
// Scaffold for full screens: aurora background + transparent scaffold.

class KPage extends StatelessWidget {
  const KPage({
    super.key,
    required this.body,
    this.tone = KTone.neutral,
    this.intensity = 1.0,
    this.appBar,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.resizeToAvoidBottomInset,
    this.extendBodyBehindAppBar = false,
  });

  final Widget body;
  final KTone tone;
  final double intensity;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final bool? resizeToAvoidBottomInset;
  final bool extendBodyBehindAppBar;

  @override
  Widget build(BuildContext context) {
    return KAurora(
      tone: tone,
      intensity: intensity,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: appBar,
        body: body,
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: bottomNavigationBar,
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
        extendBodyBehindAppBar: extendBodyBehindAppBar,
      ),
    );
  }
}

// ─── KGlass ───────────────────────────────────────────────────────────────────
// Floating chrome surface (dock, composer, auth form).
//
// By default this is a *solid* frosted look: a near-opaque surface tint with a
// faint top sheen and a hairline, with no BackdropFilter. A real backdrop blur
// has to re-blur everything behind it on every frame that content scrolls
// underneath, which is one of the most expensive things Flutter can draw and
// was a major source of scroll jank on mid-range Android. Content under the
// chrome is already faded into the page colour, so the visual difference is
// negligible. Pass `frosted: true` only for static content behind the glass.

class KGlass extends StatelessWidget {
  const KGlass({
    super.key,
    required this.child,
    this.borderRadius = KRadius.xl,
    this.blur = 22,
    this.tint,
    this.padding,
    this.border = true,
    this.frosted = false,
  });

  final Widget child;
  final BorderRadius borderRadius;

  /// Blur sigma, used only when [frosted] is true.
  final double blur;
  final Color? tint;
  final EdgeInsetsGeometry? padding;
  final bool border;

  /// Opt into a real BackdropFilter blur (expensive; never over scrolling
  /// content).
  final bool frosted;

  @override
  Widget build(BuildContext context) {
    final dark = KColor.isDark;
    var fill = tint ?? KColor.surface.withValues(alpha: dark ? 0.72 : 0.8);
    if (!frosted) {
      // Without a blur, translucency would show crisp content through the
      // chrome; lift it to near-opaque so it reads as frosted.
      final minAlpha = dark ? 0.94 : 0.95;
      if (fill.a < minAlpha) fill = fill.withValues(alpha: minAlpha);
    }
    final decorated = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.alphaBlend(KColor.fg.withValues(alpha: dark ? 0.035 : 0.02), fill),
            fill,
          ],
        ),
        border: border
            ? Border.all(
                color: KColor.fg.withValues(alpha: dark ? 0.09 : 0.08),
                width: 1,
              )
            : null,
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
    if (!frosted) return decorated;
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: decorated,
      ),
    );
  }
}

// ─── KGlowDot ─────────────────────────────────────────────────────────────────
// Small status light (live session, sync state).

class KGlowDot extends StatelessWidget {
  const KGlowDot({super.key, Color? color, this.size = 8}) : _color = color;
  final Color? _color;
  Color get color => _color ?? KColor.green;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}
