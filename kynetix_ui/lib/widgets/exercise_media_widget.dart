import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../models/exercise_definition.dart';
import '../services/exercise_media_service.dart';
import 'muscle_body_map.dart';

/// Offline-safe, license-compliant Exercise Media & Demonstration Widget.
/// Supports animated GIFs, thumbnail previews, GymVisual attribution,
/// and graceful anatomical vector fallbacks when offline or media is absent.
class ExerciseMediaWidget extends StatelessWidget {
  final ExerciseDefinition? definition;
  final String? exerciseName;
  final String? mediaUrl;
  final double height;
  final double? width;
  final BorderRadius? borderRadius;
  final bool showMuscleMapFallback;
  final bool interactiveZoom;
  final bool preferAnimation;
  final bool showAttribution;
  final BoxFit fit;

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
    this.preferAnimation = true,
    this.showAttribution = true,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveRadius = borderRadius ?? BorderRadius.circular(16);

    final resolvedUrl = mediaUrl ??
        (preferAnimation
            ? ExerciseMediaService.instance.getAnimationUrl(definition)
            : ExerciseMediaService.instance.getThumbnailUrl(definition)) ??
        ExerciseMediaService.instance.getThumbnailUrl(definition);

    Widget content;
    if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
      content = Image.network(
        resolvedUrl,
        fit: fit,
        gaplessPlayback: true,
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

    final mediaCard = Container(
      width: width ?? double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF13131F),
        borderRadius: effectiveRadius,
        border: Border.all(color: const Color(0xFF222234)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(child: content),
          if (showAttribution && resolvedUrl != null && resolvedUrl.isNotEmpty && height >= 100)
            Positioned(
              left: 8,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  ExerciseMediaService.attribution,
                  style: TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 8.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    if (interactiveZoom && resolvedUrl != null && resolvedUrl.isNotEmpty && height >= 100) {
      return GestureDetector(
        onTap: () => _openZoomDialog(context, resolvedUrl),
        child: Stack(
          children: [
            mediaCard,
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

    return mediaCard;
  }

  Widget _buildLoadingPlaceholder() {
    if (height < 70) {
      return Container(
        color: const Color(0xFF161626),
        alignment: Alignment.center,
        child: Icon(
          Icons.fitness_center_rounded,
          size: 16,
          color: Colors.white.withValues(alpha: 0.18),
        ),
      );
    }
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
          size: (height * 0.4).clamp(16.0, 40.0),
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

    if (height < 70) {
      return Center(
        child: Icon(
          Icons.fitness_center_rounded,
          size: 20,
          color: Colors.white.withValues(alpha: 0.25),
        ),
      );
    }

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
          bottom: 6,
          right: 8,
          child: Text(
            'Target Anatomy',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  void _openZoomDialog(BuildContext context, String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Stack(
            alignment: Alignment.center,
            children: [
              InteractiveViewer(
                minScale: 0.8,
                maxScale: 3.5,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 450, maxHeight: 450),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0C0C14),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF2E2E3E)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                definition?.displayName ?? exerciseName ?? 'Visual Demonstration',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              icon: const Icon(Icons.close_rounded, color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: Color(0xFF1E1E2F)),
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Image.network(
                            url,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.broken_image_rounded, color: Colors.white30, size: 60),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(8),
                        alignment: Alignment.center,
                        child: const Text(
                          ExerciseMediaService.attribution,
                          style: TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
