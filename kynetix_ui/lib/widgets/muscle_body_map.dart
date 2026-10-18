import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../config/app_theme.dart';
import '../utils/svg_path_parser.dart';
import 'muscle_regions.dart';

enum BodyView {
  front,
  back,
  sideBySide,
}

// ─── Body-map palette (train world) ───────────────────────────────────────────
// Silhouette sits in ink; targeted muscles light up in the train light.
// The volume heat ramp runs cool → hot through three distinct stops
// (cyan → violet → ember) so low / medium / high stay distinguishable.

// Every value is a getter so a theme switch is picked up on the next paint.
// Resting muscles sit one clear step off the card; inert parts (head, hands,
// feet, joints) sit half a step, so the silhouette reads on both Carbon and
// Paper without competing with the targeted muscles.
Color get _kDefaultHighlight => KColor.violet;
Color get _kBaseFill => Color.alphaBlend(
      KColor.fg.withValues(alpha: KColor.isDark ? 0.08 : 0.16),
      KColor.card,
    );
Color get _kInertFill => Color.alphaBlend(
      KColor.fg.withValues(alpha: KColor.isDark ? 0.04 : 0.09),
      KColor.card,
    );
// Carbon: a faint light seam between muscles. Paper: the card tone itself,
// engraving the muscle boundaries like a printed plate.
Color get _kOutline => KColor.isDark
    ? KColor.fg.withValues(alpha: 0.1)
    : KColor.card.withValues(alpha: 0.95);
Color get _kHeatFloor => Color.alphaBlend(
      KColor.cyan.withValues(alpha: KColor.isDark ? 0.14 : 0.16),
      _kBaseFill,
    );

/// Premium Vector Anatomical Muscle Map for Kynetix.
/// Displays high-fidelity front/back body silhouettes with dynamic muscle targeting,
/// heatmaps, and volume visualization.
class MuscleBodyMap extends StatefulWidget {
  final BodyView view;
  final Set<String>? highlightedMuscles;
  final Map<String, Color>? muscleColorMap;
  final Map<String, double>? muscleHeatmap; // 0.0 to 1.0 intensity
  final double? width;
  final double? height;
  final Function(String muscle)? onMuscleTap;

  const MuscleBodyMap({
    super.key,
    this.view = BodyView.front,
    this.highlightedMuscles,
    this.muscleColorMap,
    this.muscleHeatmap,
    this.width,
    this.height,
    this.onMuscleTap,
  });

  /// Preloads anatomical vector definitions into memory.
  static Future<void> preload() async {
    await _MuscleBodyMapState.preload();
  }

  /// Sets cached geometry directly for unit/widget tests.
  static void setCachedGeometryForTesting(Map<String, dynamic> data) {
    _MuscleBodyMapState._cachedGeometry = data;
  }

  @override
  State<MuscleBodyMap> createState() => _MuscleBodyMapState();
}

class _MuscleBodyMapState extends State<MuscleBodyMap> {
  static Map<String, dynamic>? _cachedGeometry;
  static bool _isLoading = false;

  static Future<void> preload() async {
    if (_cachedGeometry != null) return;
    _isLoading = true;
    try {
      final jsonStr = await rootBundle
          .loadString('assets/data/body_paths.json')
          .timeout(const Duration(milliseconds: 300));
      _cachedGeometry = jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Error preloading body_paths.json: $e');
    } finally {
      _isLoading = false;
    }
  }

  @override
  void initState() {
    super.initState();
    if (_cachedGeometry == null && !_isLoading) {
      _loadGeometry();
    }
  }

  /// 1 when the geometry was already cached at mount (no fade needed);
  /// 0 when it arrives later, so the silhouette fades in once.
  double _fadeFrom = 1;

  Future<void> _loadGeometry() async {
    await preload();
    if (mounted) {
      setState(() => _fadeFrom = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cachedGeometry == null) {
      return SizedBox(
        key: const ValueKey('body-placeholder'),
        width: widget.width ?? 140,
        height: widget.height ?? 220,
        child: Center(
          child: ExcludeSemantics(
            child: Icon(
              Icons.accessibility_new_rounded,
              size: 28,
              color: KColor.textDisabled,
            ),
          ),
        ),
      );
    }

    final Widget body;
    if (widget.view == BodyView.sideBySide) {
      body = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: _buildSingleView(
              data: _cachedGeometry!['front'] as Map<String, dynamic>,
            ),
          ),
          const SizedBox(width: KSpacing.md),
          Expanded(
            child: _buildSingleView(
              data: _cachedGeometry!['back'] as Map<String, dynamic>,
            ),
          ),
        ],
      );
    } else {
      final isFront = widget.view == BodyView.front;
      final viewData = isFront
          ? _cachedGeometry!['front'] as Map<String, dynamic>
          : _cachedGeometry!['back'] as Map<String, dynamic>;
      body = _buildSingleView(data: viewData);
    }

    // The painted silhouette is opaque to screen readers; speak the answer
    // (which muscles are targeted) instead of the shape.
    // The silhouette fades in once when the geometry first arrives; after
    // that, fill changes are tweened per muscle below.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: _fadeFrom, end: 1),
      duration: KMotion.of(context, KMotion.standard),
      curve: KMotion.emphasizedCurve,
      builder: (context, o, child) => Opacity(opacity: o, child: child),
      child: Semantics(
        container: true,
        label: _semanticsLabel(),
        child: ExcludeSemantics(child: body),
      ),
    );
  }

  String _semanticsLabel() {
    final named = <String>{
      ...?widget.muscleColorMap?.keys,
      ...?widget.highlightedMuscles,
    };
    if (named.isNotEmpty) {
      return 'Muscle map. Targeted: ${named.join(', ')}';
    }
    final heat = widget.muscleHeatmap;
    if (heat != null && heat.isNotEmpty) {
      final ranked = heat.entries.where((e) => e.value > 0).toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      if (ranked.isEmpty) return 'Muscle volume map. Nothing trained recently';
      final top = ranked.take(3).map((e) => e.key).join(', ');
      return 'Muscle volume map. Most trained: $top';
    }
    return 'Muscle map';
  }

  Widget _buildSingleView({required Map<String, dynamic> data}) {
    final vbStr = data['viewBox'] as String? ?? '0 95 727 1280';
    final vbParts = vbStr.split(' ').map((p) => double.tryParse(p) ?? 0).toList();
    final vbRect = Rect.fromLTWH(
      vbParts.isNotEmpty ? vbParts[0] : 0,
      vbParts.length > 1 ? vbParts[1] : 95,
      vbParts.length > 2 ? vbParts[2] : 727,
      vbParts.length > 3 ? vbParts[3] : 1280,
    );

    final pathsMap = data['paths'] as Map<String, dynamic>? ?? {};

    // Resolve every muscle's target fill once, upstream of paint().
    final target = _MuscleFills.resolve(
      partNames: pathsMap.keys,
      highlightedMuscles: widget.highlightedMuscles ?? const {},
      muscleColorMap: widget.muscleColorMap ?? const {},
      muscleHeatmap: widget.muscleHeatmap ?? const {},
    );

    return SizedBox(
      width: widget.width,
      height: widget.height ?? 220,
      child: RepaintBoundary(
        // Implicit tween: when the selection changes, each muscle's fill
        // glides from its current colour to the new one (interruptible —
        // a mid-flight change continues from wherever it is).
        child: TweenAnimationBuilder<_MuscleFills>(
          tween: _MuscleFillsTween(begin: target, end: target),
          duration: KMotion.of(context, KMotion.standard),
          curve: KMotion.emphasizedCurve,
          builder: (context, fills, _) => CustomPaint(
            painter: _AnatomicalBodyPainter(
              viewBox: vbRect,
              pathsMap: pathsMap,
              fills: fills,
              dark: KColor.isDark,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Scene: resolved per-muscle fills ─────────────────────────────────────────

@immutable
class _MuscleFills {
  const _MuscleFills(this.colors);

  /// canonical muscle → active fill. Absent = resting (base) fill.
  final Map<String, Color> colors;

  static const empty = _MuscleFills({});

  /// Same priority as always: explicit colour map → highlighted set →
  /// heatmap intensity.
  static _MuscleFills resolve({
    required Iterable<String> partNames,
    required Set<String> highlightedMuscles,
    required Map<String, Color> muscleColorMap,
    required Map<String, double> muscleHeatmap,
  }) {
    // Inputs are muscle-group labels ("Back", "Rear Delts", "Glutes") or raw
    // region ids; both resolve through [muscleRegionsFor] so a label lights
    // the right region instead of whatever its letters happen to contain.
    final colorByRegion = <String, Color>{};
    muscleColorMap.forEach((name, color) {
      for (final r in _regionsOf(name)) {
        colorByRegion.putIfAbsent(r, () => color);
      }
    });
    final highlightedRegions = {
      for (final name in highlightedMuscles) ..._regionsOf(name),
    };
    final heatByRegion = <String, double>{};
    muscleHeatmap.forEach((name, v) {
      for (final r in _regionsOf(name)) {
        final prev = heatByRegion[r];
        if (prev == null || v > prev) heatByRegion[r] = v;
      }
    });
    final out = <String, Color>{};
    for (final partName in partNames) {
      if (_AnatomicalBodyPainter._inertParts.contains(partName)) continue;
      final canonicalMuscle = _AnatomicalBodyPainter._mapToCanonical(partName);
      if (out.containsKey(canonicalMuscle)) continue;

      Color? activeColor;
      if (colorByRegion.containsKey(canonicalMuscle)) {
        activeColor = colorByRegion[canonicalMuscle];
      } else if (highlightedRegions.contains(canonicalMuscle)) {
        activeColor = _kDefaultHighlight;
      } else if (heatByRegion.containsKey(canonicalMuscle)) {
        final intensity = (heatByRegion[canonicalMuscle] ?? 0.0).clamp(0.0, 1.0);
        if (intensity > 0.0) {
          activeColor = _calculateHeatColor(intensity);
        }
      }
      if (activeColor != null) out[canonicalMuscle] = activeColor;
    }
    return _MuscleFills(out);
  }

  /// Region ids named by [name]; an unmapped name falls back to the
  /// painter's own canonical form so raw part ids still work.
  static Set<String> _regionsOf(String name) {
    final mapped = muscleRegionsFor(name);
    if (mapped.isNotEmpty) return mapped;
    return {_AnatomicalBodyPainter._mapToCanonical(name)};
  }

  static Color _calculateHeatColor(double intensity) {
    if (intensity < 0.3) {
      return Color.lerp(_kHeatFloor, KColor.cyan, intensity / 0.3)!;
    } else if (intensity < 0.7) {
      return Color.lerp(KColor.cyan, KColor.violet, (intensity - 0.3) / 0.4)!;
    } else {
      return Color.lerp(KColor.violet, KColor.ember, (intensity - 0.7) / 0.3)!;
    }
  }

  static _MuscleFills lerp(_MuscleFills a, _MuscleFills b, double t) {
    if (t <= 0) return a;
    if (t >= 1) return b;
    final keys = {...a.colors.keys, ...b.colors.keys};
    final out = <String, Color>{};
    for (final k in keys) {
      final from = a.colors[k] ?? _kBaseFill;
      final to = b.colors[k] ?? _kBaseFill;
      out[k] = Color.lerp(from, to, t)!;
    }
    return _MuscleFills(out);
  }

  @override
  bool operator ==(Object other) =>
      other is _MuscleFills && mapEquals(other.colors, colors);

  @override
  int get hashCode => Object.hashAllUnordered(
        colors.entries.map((e) => Object.hash(e.key, e.value)),
      );
}

class _MuscleFillsTween extends Tween<_MuscleFills> {
  _MuscleFillsTween({super.begin, super.end});

  @override
  _MuscleFills lerp(double t) =>
      _MuscleFills.lerp(begin ?? _MuscleFills.empty, end ?? _MuscleFills.empty, t);
}

// ─── Painter ──────────────────────────────────────────────────────────────────

class _AnatomicalBodyPainter extends CustomPainter {
  final Rect viewBox;
  final Map<String, dynamic> pathsMap;
  final _MuscleFills fills;

  static const Set<String> _inertParts = {
    'head',
    'hair',
    'neck',
    'hands',
    'feet',
    'knees',
    'ankles',
  };

  _AnatomicalBodyPainter({
    required this.viewBox,
    required this.pathsMap,
    required this.fills,
    required this.dark,
    this.stroke = 1.0,
  });

  /// Seam width in logical pixels; thumbnails use a finer seam.
  final double stroke;

  /// Active palette; compared in shouldRepaint so a theme switch repaints
  /// the resting and inert fills (which are not part of [fills]).
  final bool dark;

  // Paints are fields — nothing hoistable is allocated in paint().
  final Paint _fill = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;
  final Paint _outline = Paint()
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;
  final Paint _rim = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;

  @override
  void paint(Canvas canvas, Size size) {
    if (viewBox.width <= 0 || viewBox.height <= 0) return;
    final scaleX = size.width / viewBox.width;
    final scaleY = size.height / viewBox.height;
    final scale = scaleX < scaleY ? scaleX : scaleY;
    if (scale <= 0) return;

    final dx = (size.width - viewBox.width * scale) / 2.0 - viewBox.left * scale;
    final dy = (size.height - viewBox.height * scale) / 2.0 - viewBox.top * scale;

    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale, scale);

    _outline
      ..color = _kOutline
      ..strokeWidth = stroke / scale;
    _rim.strokeWidth = 1.6 * stroke / scale;

    pathsMap.forEach((partName, pathListRaw) {
      final isInert = _inertParts.contains(partName);
      final active = isInert ? null : fills.colors[_mapToCanonical(partName)];

      _fill.color = active ?? (isInert ? _kInertFill : _kBaseFill);

      final List<dynamic> pathList = pathListRaw is List ? pathListRaw : [pathListRaw];
      for (final pStr in pathList) {
        if (pStr is! String || pStr.isEmpty) continue;
        final path = SvgPathParser.parse(pStr); // cached by the parser
        canvas.drawPath(path, _fill);
        // Thumbnails (stroke 0) are fill only: strokes on these tiny paths
        // smear across the screen on Impeller.
        if (stroke <= 0) continue;
        if (active != null) {
          // A rim gives targeted muscles a shape cue, not only hue: lifted
          // toward white on Carbon, deepened toward ink on Paper.
          _rim.color = dark
              ? Color.lerp(active, KColor.fg, 0.35)!.withValues(alpha: 0.9)
              : Color.lerp(active, KColor.fg, 0.28)!.withValues(alpha: 0.85);
          canvas.drawPath(path, _rim);
        } else {
          canvas.drawPath(path, _outline);
        }
      }
    });

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AnatomicalBodyPainter oldDelegate) {
    return oldDelegate.fills != fills ||
        oldDelegate.dark != dark ||
        oldDelegate.stroke != stroke ||
        !identical(oldDelegate.pathsMap, pathsMap) ||
        oldDelegate.viewBox != viewBox;
  }

  static String _mapToCanonical(String raw) {
    final m = raw.toLowerCase().trim();
    // Path ids in body_paths.json are already canonical.
    if (kFrontRegions.contains(m) || kBackRegions.contains(m)) return m;
    if (m.contains('lower back') || m.contains('spine')) return 'lower-back';
    if (m.contains('chest') || m.contains('pec')) return 'chest';
    if (m.contains('abs') || m.contains('core') || m.contains('waist')) return 'abs';
    if (m.contains('oblique')) return 'obliques';
    if (m.contains('shoulder') || m.contains('delt')) return 'deltoids';
    if (m.contains('bicep') || m.contains('brachialis')) return 'biceps';
    if (m.contains('tricep')) return 'triceps';
    if (m.contains('lat') || m.contains('upper back') || m.contains('rhomboid') || m.contains('back')) return 'upper-back';
    if (m.contains('trap')) return 'trapezius';
    if (m.contains('forearm') || m.contains('wrist')) return 'forearm';
    if (m.contains('quad')) return 'quadriceps';
    if (m.contains('hamstring') || m.contains('ham')) return 'hamstring';
    if (m.contains('glute') || m.contains('abductor')) return 'gluteal';
    if (m.contains('calf') || m.contains('calves') || m.contains('soleus')) return 'calves';
    if (m.contains('adductor') || m.contains('inner thigh')) return 'adductors';
    if (m.contains('shin') || m.contains('tibialis')) return 'tibialis';
    if (m.contains('hip flexor')) return 'hip-flexors';
    if (m.contains('serratus')) return 'serratus';
    return m;
  }
}


// ─── Thumbnail ────────────────────────────────────────────────────────────────

/// A small one-sided body with [group]'s muscle lit, for chips and headers.
///
/// The side (front or back) comes from [muscleTargetFor], so lats, traps,
/// glutes, hamstrings, calves, triceps and rear delts show on the back, and
/// chest, biceps, quads, abs, adductors and shoulders on the front. A group
/// with no muscle on the map ("Cardio", "Other") renders nothing: wrong
/// imagery is worse than none. Geometry and parsed paths are shared caches;
/// each thumb is one cheap painter behind its own [RepaintBoundary].
class MuscleThumb extends StatefulWidget {
  const MuscleThumb(this.group, {super.key, this.height = 36, Color? color})
      : _color = color;

  final String group;
  final double height;
  final Color? _color;

  /// Whether [group] has a muscle to show; lets callers skip the gap too.
  static bool canShow(String group) => muscleTargetFor(group) != null;

  @override
  State<MuscleThumb> createState() => _MuscleThumbState();
}

class _MuscleThumbState extends State<MuscleThumb> {
  // Drawing the full body at a thumbnail's tiny scale (about 1/50) makes
  // Impeller smear the paths across the screen, so each thumbnail is drawn
  // once at a sane scale into an image and shown shrunk. Images are cached
  // per muscle, colour and theme.
  static final Map<String, Future<ui.Image?>> _cache = {};
  static const double _renderHeight = 320;

  @override
  void initState() {
    super.initState();
    if (_MuscleBodyMapState._cachedGeometry == null) {
      MuscleBodyMap.preload().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  static Future<ui.Image?> _render(MuscleTarget target, Color color, bool dark) async {
    final geometry = _MuscleBodyMapState._cachedGeometry;
    final data = geometry?[target.view == BodyView.back ? 'back' : 'front'];
    if (data is! Map<String, dynamic>) return null;
    final vb = (data['viewBox'] as String? ?? '0 95 727 1280')
        .split(' ')
        .map((p) => double.tryParse(p) ?? 0)
        .toList();
    final viewBox = vb.length == 4 ? Rect.fromLTWH(vb[0], vb[1], vb[2], vb[3]) : const Rect.fromLTWH(0, 95, 727, 1280);
    final size = Size(_renderHeight * viewBox.width / viewBox.height, _renderHeight);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    _AnatomicalBodyPainter(
      viewBox: viewBox,
      pathsMap: data['paths'] as Map<String, dynamic>? ?? const {},
      fills: _MuscleFills({for (final r in target.regions) r: color}),
      dark: dark,
      stroke: 0,
    ).paint(canvas, size);
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.width.ceil(), size.height.ceil());
    picture.dispose();
    return image;
  }

  @override
  Widget build(BuildContext context) {
    final target = muscleTargetFor(widget.group);
    if (target == null) return const SizedBox.shrink();
    final width = widget.height * 0.57;
    final box = SizedBox(width: width, height: widget.height);
    if (_MuscleBodyMapState._cachedGeometry == null) return box;
    final color = widget._color ?? _kDefaultHighlight;
    final dark = KColor.isDark;
    final key = '${target.view.name}|${target.regions.join(',')}|${color.toARGB32()}|$dark';
    final future = _cache.putIfAbsent(key, () => _render(target, color, dark));
    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: widget.height,
        child: FutureBuilder<ui.Image?>(
          future: future,
          builder: (context, snap) {
            final img = snap.data;
            if (img == null) return const SizedBox.shrink();
            return RawImage(image: img, fit: BoxFit.contain, filterQuality: FilterQuality.medium);
          },
        ),
      ),
    );
  }
}
