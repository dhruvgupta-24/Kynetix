import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../config/app_theme.dart';
import '../utils/svg_path_parser.dart';

enum BodyView {
  front,
  back,
  sideBySide,
}

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
      final jsonStr = await rootBundle.loadString('assets/data/body_paths.json');
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

  Future<void> _loadGeometry() async {
    await preload();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cachedGeometry == null) {
      return SizedBox(
        width: widget.width ?? 140,
        height: widget.height ?? 220,
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(KColor.green),
            ),
          ),
        ),
      );
    }

    if (widget.view == BodyView.sideBySide) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: _buildSingleView(
              isFront: true,
              data: _cachedGeometry!['front'] as Map<String, dynamic>,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildSingleView(
              isFront: false,
              data: _cachedGeometry!['back'] as Map<String, dynamic>,
            ),
          ),
        ],
      );
    }

    final isFront = widget.view == BodyView.front;
    final viewData = isFront
        ? _cachedGeometry!['front'] as Map<String, dynamic>
        : _cachedGeometry!['back'] as Map<String, dynamic>;

    return _buildSingleView(isFront: isFront, data: viewData);
  }

  Widget _buildSingleView({
    required bool isFront,
    required Map<String, dynamic> data,
  }) {
    final vbStr = data['viewBox'] as String? ?? '0 95 727 1280';
    final vbParts = vbStr.split(' ').map((p) => double.tryParse(p) ?? 0).toList();
    final vbRect = Rect.fromLTWH(
      vbParts.isNotEmpty ? vbParts[0] : 0,
      vbParts.length > 1 ? vbParts[1] : 95,
      vbParts.length > 2 ? vbParts[2] : 727,
      vbParts.length > 3 ? vbParts[3] : 1280,
    );

    final pathsMap = data['paths'] as Map<String, dynamic>? ?? {};

    return SizedBox(
      width: widget.width,
      height: widget.height ?? 220,
      child: CustomPaint(
        painter: _AnatomicalBodyPainter(
          viewBox: vbRect,
          pathsMap: pathsMap,
          highlightedMuscles: widget.highlightedMuscles ?? const {},
          muscleColorMap: widget.muscleColorMap ?? const {},
          muscleHeatmap: widget.muscleHeatmap ?? const {},
        ),
      ),
    );
  }
}

class _AnatomicalBodyPainter extends CustomPainter {
  final Rect viewBox;
  final Map<String, dynamic> pathsMap;
  final Set<String> highlightedMuscles;
  final Map<String, Color> muscleColorMap;
  final Map<String, double> muscleHeatmap;

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
    required this.highlightedMuscles,
    required this.muscleColorMap,
    required this.muscleHeatmap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / viewBox.width;
    final scaleY = size.height / viewBox.height;
    final scale = scaleX < scaleY ? scaleX : scaleY;

    final dx = (size.width - viewBox.width * scale) / 2.0 - viewBox.left * scale;
    final dy = (size.height - viewBox.height * scale) / 2.0 - viewBox.top * scale;

    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale, scale);

    final paintBase = Paint()
      ..color = const Color(0xFF161624)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final paintInert = Paint()
      ..color = const Color(0xFF1C1C2C)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final paintOutline = Paint()
      ..color = const Color(0xFF262638)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0 / scale
      ..isAntiAlias = true;

    // Draw all muscle parts
    pathsMap.forEach((partName, pathListRaw) {
      final isInert = _inertParts.contains(partName);
      final canonicalMuscle = _mapToCanonical(partName);

      Color? activeColor;
      if (!isInert) {
        if (muscleColorMap.containsKey(canonicalMuscle)) {
          activeColor = muscleColorMap[canonicalMuscle];
        } else if (highlightedMuscles.any((m) => _mapToCanonical(m) == canonicalMuscle)) {
          activeColor = KColor.green;
        } else if (muscleHeatmap.containsKey(canonicalMuscle)) {
          final intensity = (muscleHeatmap[canonicalMuscle] ?? 0.0).clamp(0.0, 1.0);
          if (intensity > 0.0) {
            activeColor = _calculateHeatColor(intensity);
          }
        }
      }

      final fillPaint = activeColor != null
          ? (Paint()
            ..color = activeColor
            ..style = PaintingStyle.fill
            ..isAntiAlias = true)
          : (isInert ? paintInert : paintBase);

      final List<dynamic> pathList = pathListRaw is List ? pathListRaw : [pathListRaw];
      for (final pStr in pathList) {
        if (pStr is! String || pStr.isEmpty) continue;
        final path = SvgPathParser.parse(pStr);
        canvas.drawPath(path, fillPaint);
        canvas.drawPath(path, paintOutline);
      }
    });

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AnatomicalBodyPainter oldDelegate) {
    return !setEquals(oldDelegate.highlightedMuscles, highlightedMuscles) ||
        !mapEquals(oldDelegate.muscleColorMap, muscleColorMap) ||
        !mapEquals(oldDelegate.muscleHeatmap, muscleHeatmap) ||
        oldDelegate.viewBox != viewBox;
  }

  Color _calculateHeatColor(double intensity) {
    if (intensity < 0.3) {
      return Color.lerp(const Color(0xFF1E293B), KColor.blue, intensity / 0.3)!;
    } else if (intensity < 0.7) {
      return Color.lerp(KColor.blue, KColor.green, (intensity - 0.3) / 0.4)!;
    } else {
      return Color.lerp(KColor.green, KColor.amber, (intensity - 0.7) / 0.3)!;
    }
  }

  static String _mapToCanonical(String raw) {
    final m = raw.toLowerCase().trim();
    if (m.contains('chest') || m.contains('pec')) return 'chest';
    if (m.contains('abs') || m.contains('core') || m.contains('waist')) return 'abs';
    if (m.contains('oblique')) return 'obliques';
    if (m.contains('shoulder') || m.contains('delt')) return 'deltoids';
    if (m.contains('bicep') || m.contains('brachialis')) return 'biceps';
    if (m.contains('tricep')) return 'triceps';
    if (m.contains('lat') || m.contains('upper back') || m.contains('rhomboid') || m.contains('back')) return 'upper-back';
    if (m.contains('lower back') || m.contains('spine')) return 'lower-back';
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
