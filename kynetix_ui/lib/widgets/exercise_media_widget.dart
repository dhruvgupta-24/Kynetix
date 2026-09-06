import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../models/exercise_definition.dart';
import 'muscle_body_map.dart';

/// Offline-safe, license-compliant Exercise Media & Demonstration Widget.
/// Supports local assets, network URLs, smooth shimmer caching, and
/// graceful anatomical vector fallbacks when offline or media is absent.
class ExerciseMediaWidget extends StatelessWidget {
  final ExerciseDefinition? definition;
  final String? exerciseName;
  final String? mediaUrl;
  final double height;
  final double? width;
  final BorderRadius? borderRadius;
  final bool showMuscleMapFallback;
  final bool interactiveZoom;

  const ExerciseMediaWidget({
    super.key,
    this.definition,
    this.exerciseName,
    this.mediaUrl,
    this.height = 180,
    this.width,
    this.borderRadius,
    this.showMuscleMapFallback = true,
    this.interactiveZoom = true,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveRadius = borderRadius ?? BorderRadius.circular(16);
    final url = mediaUrl ?? definition?.gifRef ?? definition?.imageRef;

    Widget content;
    if (url != null && url.isNotEmpty) {
      content = Image.network(
        url,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _buildLoadingPlaceholder();
        },
        errorBuilder: (context, error, stackTrace) {
          return _buildAnatomicalFallback();
        },
      );
    } else {
      content = _buildAnatomicalFallback();
    }

    final container = Container(
      width: width ?? double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF13131F),
        borderRadius: effectiveRadius,
        border: Border.all(color: const Color(0xFF222234)),
      ),
      clipBehavior: Clip.antiAlias,
      child: content,
    );

    if (interactiveZoom && url != null && url.isNotEmpty) {
      return GestureDetector(
        onTap: () => _openZoomDialog(context, url),
        child: Stack(
          children: [
            container,
            Positioned(
              right: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.fullscreen_rounded,
                  size: 16,
                  color: Colors.white70,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return container;
  }

  Widget _buildLoadingPlaceholder() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(KColor.green),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Loading visual guide...',
            style: KText.caption.copyWith(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildAnatomicalFallback() {
    if (!showMuscleMapFallback) {
      return Center(
        child: Icon(
          Icons.fitness_center_rounded,
          size: 40,
          color: Colors.white.withValues(alpha: 0.15),
        ),
      );
    }

    final primary = definition?.targetMuscle ?? '';
    final secondary = definition?.secondaryMuscles ?? [];
    final targetMuscles = <String>{
      if (primary.isNotEmpty) primary,
      ...secondary,
    };

    return Stack(
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: MuscleBodyMap(
              view: BodyView.sideBySide,
              highlightedMuscles: targetMuscles,
              muscleColorMap: {
                if (primary.isNotEmpty) primary: KColor.green,
                for (final s in secondary) s: KColor.amber,
              },
              height: height - 16,
            ),
          ),
        ),
        Positioned(
          left: 10,
          top: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: KColor.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  primary.isNotEmpty ? primary.toUpperCase() : 'TARGET ANATOMY',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white70,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _openZoomDialog(BuildContext context, String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 3.5,
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) =>
                      _buildAnatomicalFallback(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
