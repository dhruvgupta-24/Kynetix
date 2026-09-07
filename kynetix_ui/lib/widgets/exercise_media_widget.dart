import 'dart:async';
import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../models/exercise_definition.dart';
import '../models/workout_split.dart' show Exercise;
import '../services/exercise_library_service.dart';
import '../services/exercise_media_service.dart';
import 'muscle_body_map.dart';

/// Offline-safe, license-compliant Exercise Media & Demonstration Widget.
/// Supports animated GIFs, thumbnail previews, GymVisual attribution,
/// graceful anatomical vector fallbacks, and 2-loop completion callbacks
/// for smooth progression reveals without frame-rate thrashing.
class ExerciseMediaWidget extends StatefulWidget {
  final ExerciseDefinition? definition;
  final Exercise? exercise;
  final String? exerciseId;
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
  final VoidCallback? onTwoLoopsCompleted;
  final int targetLoops;

  const ExerciseMediaWidget({
    super.key,
    this.definition,
    this.exercise,
    this.exerciseId,
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
    this.onTwoLoopsCompleted,
    this.targetLoops = 2,
  });

  @override
  State<ExerciseMediaWidget> createState() => _ExerciseMediaWidgetState();
}

class _ExerciseMediaWidgetState extends State<ExerciseMediaWidget> {
  Timer? _loopCountdownTimer;
  Timer? _watchdogTimer;
  bool _loopsCompleted = false;
  bool _firstFrameRendered = false;
  String? _resolvedUrl;
  ExerciseDefinition? _resolvedDefinition;

  @override
  void initState() {
    super.initState();
    _resolveMedia();
    _checkInitialTrigger();
  }

  @override
  void didUpdateWidget(ExerciseMediaWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final exerciseChanged = oldWidget.exercise?.id != widget.exercise?.id ||
        oldWidget.definition?.id != widget.definition?.id ||
        oldWidget.exerciseId != widget.exerciseId ||
        oldWidget.exerciseName != widget.exerciseName ||
        oldWidget.mediaUrl != widget.mediaUrl;

    if (exerciseChanged) {
      _resetLoopTracking();
      _resolveMedia();
      _checkInitialTrigger();
    }
  }

  @override
  void dispose() {
    _loopCountdownTimer?.cancel();
    _watchdogTimer?.cancel();
    super.dispose();
  }

  void _resetLoopTracking() {
    _loopCountdownTimer?.cancel();
    _loopCountdownTimer = null;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _loopsCompleted = false;
    _firstFrameRendered = false;
  }

  void _resolveMedia() {
    _resolvedDefinition = widget.definition ??
        (widget.exercise != null
            ? ExerciseLibraryService.instance.getById(widget.exercise!.id)
            : widget.exerciseId != null
                ? ExerciseLibraryService.instance.getById(widget.exerciseId!)
                : null);

    if (widget.mediaUrl != null && widget.mediaUrl!.isNotEmpty) {
      _resolvedUrl = widget.mediaUrl;
      return;
    }

    final resolved = ExerciseMediaService.instance.resolveMedia(
      definition: widget.definition,
      exercise: widget.exercise,
      id: widget.exerciseId,
      name: widget.exerciseName,
    );

    if (widget.preferAnimation && resolved.gif != null && resolved.gif!.isNotEmpty) {
      _resolvedUrl = '${ExerciseMediaService.cdnBaseVideos}/${resolved.gif}';
    } else if (resolved.image != null && resolved.image!.isNotEmpty) {
      _resolvedUrl = '${ExerciseMediaService.cdnBaseImages}/${resolved.image}';
    } else if (resolved.gif != null && resolved.gif!.isNotEmpty) {
      _resolvedUrl = '${ExerciseMediaService.cdnBaseVideos}/${resolved.gif}';
    } else {
      _resolvedUrl = null;
    }
  }

  void _checkInitialTrigger() {
    if (widget.onTwoLoopsCompleted == null) return;

    // If there is genuinely no media URL, notify after brief graceful delay
    // so progression UI is never locked out.
    if (_resolvedUrl == null || _resolvedUrl!.isEmpty) {
      _scheduleGracefulFallbackTrigger();
      return;
    }

    // Safety watchdog: If network or frame decoding is delayed,
    // trigger progression after timeout so the workout screen is never blocked.
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer(Duration(milliseconds: widget.targetLoops * 3000 + 1000), () {
      if (mounted && !_loopsCompleted) {
        _loopsCompleted = true;
        widget.onTwoLoopsCompleted?.call();
      }
    });
  }

  void _scheduleGracefulFallbackTrigger() {
    if (_loopsCompleted) return;
    _loopCountdownTimer?.cancel();
    _watchdogTimer?.cancel();
    _loopCountdownTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted && !_loopsCompleted) {
        _loopsCompleted = true;
        widget.onTwoLoopsCompleted?.call();
      }
    });
  }

  void _onFirstFrameDecoded() {
    if (_firstFrameRendered || _loopsCompleted) return;
    _firstFrameRendered = true;
    _watchdogTimer?.cancel();

    if (widget.onTwoLoopsCompleted == null) return;

    // A single GymVisual loop averages 3.0s (12 frames @ 250ms).
    // Target 2 full loops = 6.0s duration.
    final durationMs = widget.targetLoops * 3000;
    _loopCountdownTimer?.cancel();
    _loopCountdownTimer = Timer(Duration(milliseconds: durationMs), () {
      if (mounted && !_loopsCompleted) {
        _loopsCompleted = true;
        widget.onTwoLoopsCompleted?.call();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final effectiveRadius = widget.borderRadius ?? BorderRadius.circular(16);

    Widget content;
    if (_resolvedUrl != null && _resolvedUrl!.isNotEmpty) {
      content = Image.network(
        _resolvedUrl!,
        fit: widget.fit,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (frame != null && !_firstFrameRendered) {
            _onFirstFrameDecoded();
          }
          return child;
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _buildLoadingPlaceholder();
        },
        errorBuilder: (context, error, stackTrace) {
          if (!_loopsCompleted && _loopCountdownTimer == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && !_loopsCompleted && _loopCountdownTimer == null) {
                _scheduleGracefulFallbackTrigger();
              }
            });
          }
          return _buildAnatomicalFallback();
        },
      );
    } else {
      content = _buildAnatomicalFallback();
    }

    final mediaCard = Container(
      width: widget.width ?? double.infinity,
      height: widget.height,
      decoration: BoxDecoration(
        color: const Color(0xFF13131F),
        borderRadius: effectiveRadius,
        border: Border.all(color: const Color(0xFF222234)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(child: content),
          if (widget.showAttribution &&
              _resolvedUrl != null &&
              _resolvedUrl!.isNotEmpty &&
              widget.height >= 100)
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

    if (widget.interactiveZoom &&
        _resolvedUrl != null &&
        _resolvedUrl!.isNotEmpty &&
        widget.height >= 100) {
      return GestureDetector(
        onTap: () => _openZoomDialog(context, _resolvedUrl!),
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
    if (widget.height < 70) {
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
    if (!widget.showMuscleMapFallback) {
      return Center(
        child: Icon(
          Icons.fitness_center_rounded,
          size: (widget.height * 0.4).clamp(16.0, 40.0),
          color: Colors.white.withValues(alpha: 0.15),
        ),
      );
    }

    final primary = _resolvedDefinition?.targetMuscle ?? widget.exercise?.muscleGroup ?? '';
    final secondary = _resolvedDefinition?.secondaryMuscles ?? [];
    final targetMuscles = <String>{
      if (primary.isNotEmpty) primary,
      ...secondary,
    };

    if (widget.height < 70) {
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
              height: widget.height - 16,
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
        final title = _resolvedDefinition?.displayName ??
            widget.exercise?.name ??
            widget.exerciseName ??
            'Visual Demonstration';

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
                                title,
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
