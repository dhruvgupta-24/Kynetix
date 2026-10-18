import 'dart:async';
import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../models/exercise_definition.dart';
import '../models/workout_split.dart' show Exercise;
import '../services/exercise_library_service.dart';
import '../services/exercise_media_service.dart';
import 'muscle_body_map.dart';

/// Controller governing exercise demonstration loop playback and observation.
///
/// Decouples loop completion detection from arbitrary asynchronous GIF timers.
/// In production, GIF frame decoders or the media player report loops to this controller.
/// In tests, this controller allows deterministic, instantaneous loop simulation.
class ExerciseDemoPlaybackController extends ChangeNotifier {
  final int targetLoops;
  int _completedLoops = 0;
  bool _isCompleted = false;

  ExerciseDemoPlaybackController({this.targetLoops = 2});

  int get completedLoops => _completedLoops;
  bool get isCompleted => _isCompleted;

  /// Simulates or reports that 1 loop finished.
  void recordLoop() {
    if (_isCompleted) return;
    _completedLoops++;
    if (_completedLoops >= targetLoops) {
      _isCompleted = true;
    }
    notifyListeners();
  }

  /// Instantly completes all target loops.
  void completeLoops() {
    if (_isCompleted) return;
    _completedLoops = targetLoops;
    _isCompleted = true;
    notifyListeners();
  }

  /// Resets loop count back to 0.
  void reset() {
    _completedLoops = 0;
    _isCompleted = false;
    notifyListeners();
  }
}

/// Offline-safe, license-compliant Exercise Media & Demonstration Widget.
/// Supports animated GIFs, thumbnail previews, GymVisual attribution,
/// graceful anatomical vector fallbacks, and 2-loop completion callbacks
/// for smooth progression reveals without frame-rate thrashing.
class ExerciseMediaWidget extends StatefulWidget {
  /// Static testing flag to disable network GIF downloads in widget tests.
  static bool disableNetworkForTesting = false;

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
  final Duration? singleLoopDuration;
  final bool disableNetwork;
  final ExerciseDemoPlaybackController? playbackController;

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
    this.singleLoopDuration,
    this.disableNetwork = false,
    this.playbackController,
  });

  @override
  State<ExerciseMediaWidget> createState() => _ExerciseMediaWidgetState();
}

class _ExerciseMediaWidgetState extends State<ExerciseMediaWidget> {
  Timer? _loopCountdownTimer;
  Timer? _watchdogTimer;
  Timer? _loadTimeoutTimer;
  bool _loopsCompleted = false;
  // True once the demo could not be shown (missing file, offline, or no
  // first frame in time). The card then shows the anatomy fallback and
  // drops the attribution and zoom affordances.
  bool _loadFailed = false;
  // The CDN is tried first; the raw GitHub copy is the one retry.
  bool _usingMirror = false;

  /// How long a demo may take to show its first frame before the card gives
  /// up and shows the anatomy fallback instead of a skeleton forever.
  static const Duration _loadTimeout = Duration(seconds: 15);
  bool _firstFrameRendered = false;
  String? _resolvedUrl;
  ExerciseDefinition? _resolvedDefinition;

  int _currentLoop = 1;

  @override
  void initState() {
    super.initState();
    _resolveMedia();
    _attachPlaybackController(widget.playbackController);
    _checkInitialTrigger();
  }

  @override
  void didUpdateWidget(ExerciseMediaWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playbackController != widget.playbackController) {
      _detachPlaybackController(oldWidget.playbackController);
      _attachPlaybackController(widget.playbackController);
    }
    if (oldWidget.exercise?.id != widget.exercise?.id ||
        oldWidget.definition?.id != widget.definition?.id ||
        oldWidget.exerciseId != widget.exerciseId ||
        oldWidget.exerciseName != widget.exerciseName ||
        oldWidget.mediaUrl != widget.mediaUrl) {
      _resetLoopTracking();
      _resolveMedia();
      _checkInitialTrigger();
    }
  }

  bool get _isTestEnvironment =>
      widget.disableNetwork ||
      ExerciseMediaWidget.disableNetworkForTesting ||
      WidgetsBinding.instance.runtimeType.toString().contains('Test');

  void _armLoadTimeout() {
    _loadTimeoutTimer?.cancel();
    _loadTimeoutTimer = null;
    if (_isTestEnvironment || _resolvedUrl == null || _resolvedUrl!.isEmpty) {
      return;
    }
    _loadTimeoutTimer = Timer(_loadTimeout, () {
      if (mounted && !_firstFrameRendered && !_loadFailed) {
        _markLoadFailed();
      }
    });
  }

  /// Swaps a failed CDN url for the raw GitHub mirror once, then gives up.
  void _onImageError(String failedUrl) {
    // Ignore late reports for a url that has already been replaced.
    if (_loadFailed || failedUrl != _resolvedUrl) return;
    final url = _resolvedUrl;
    if (!_usingMirror && url != null) {
      final mirror = ExerciseMediaService.mirrorUrlFor(url);
      if (mirror != null) {
        setState(() {
          _usingMirror = true;
          _resolvedUrl = mirror;
        });
        _armLoadTimeout();
        return;
      }
    }
    _markLoadFailed();
  }

  void _markLoadFailed() {
    _loadTimeoutTimer?.cancel();
    _loadTimeoutTimer = null;
    setState(() => _loadFailed = true);
    if (!_loopsCompleted && _loopCountdownTimer == null) {
      _scheduleGracefulFallbackTrigger();
    }
  }

  @override
  void dispose() {
    _detachPlaybackController(widget.playbackController);
    _loopCountdownTimer?.cancel();
    _watchdogTimer?.cancel();
    _loadTimeoutTimer?.cancel();
    super.dispose();
  }

  void _attachPlaybackController(ExerciseDemoPlaybackController? controller) {
    controller?.addListener(_onPlaybackControllerChanged);
    if (controller != null && controller.isCompleted && !_loopsCompleted) {
      _loopsCompleted = true;
      widget.onTwoLoopsCompleted?.call();
    }
  }

  void _detachPlaybackController(ExerciseDemoPlaybackController? controller) {
    controller?.removeListener(_onPlaybackControllerChanged);
  }

  void _onPlaybackControllerChanged() {
    if (!mounted) return;
    final controller = widget.playbackController;
    if (controller != null && controller.isCompleted && !_loopsCompleted) {
      _loopsCompleted = true;
      widget.onTwoLoopsCompleted?.call();
    }
  }

  void _resetLoopTracking() {
    _loopCountdownTimer?.cancel();
    _loopCountdownTimer = null;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _loopsCompleted = false;
    _firstFrameRendered = false;
    _currentLoop = 1;
  }

  /// True when a demo url is set and has not failed.
  bool get _hasLiveMedia =>
      !_loadFailed && _resolvedUrl != null && _resolvedUrl!.isNotEmpty;

  void _resolveMedia() {
    _loadFailed = false;
    _usingMirror = false;
    _resolveMediaUrl();
    _armLoadTimeout();
  }

  void _resolveMediaUrl() {
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
    if (widget.playbackController != null) {
      return;
    }

    if (widget.onTwoLoopsCompleted == null) return;

    final isTest = widget.disableNetwork ||
        ExerciseMediaWidget.disableNetworkForTesting ||
        WidgetsBinding.instance.runtimeType.toString().contains('Test');

    if (isTest) {
      _scheduleGracefulFallbackTrigger();
      return;
    }

    if (_resolvedUrl == null || _resolvedUrl!.isEmpty) {
      _scheduleGracefulFallbackTrigger();
      return;
    }

    final loopMs = widget.singleLoopDuration?.inMilliseconds ?? 3000;
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer(Duration(milliseconds: widget.targetLoops * loopMs + 1000), () {
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
    final delay = widget.singleLoopDuration != null || ExerciseMediaWidget.disableNetworkForTesting
        ? const Duration(milliseconds: 20)
        : const Duration(milliseconds: 600);
    _loopCountdownTimer = Timer(delay, () {
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
    _loadTimeoutTimer?.cancel();
    _loadTimeoutTimer = null;

    if (widget.onTwoLoopsCompleted == null) return;

    final loopMs = widget.singleLoopDuration?.inMilliseconds ??
        (ExerciseMediaWidget.disableNetworkForTesting ? 20 : 3000);
    
    if (!ExerciseMediaWidget.disableNetworkForTesting && widget.targetLoops > 1) {
      Timer(Duration(milliseconds: loopMs), () {
        if (mounted && !_loopsCompleted) {
          setState(() => _currentLoop = 2);
        }
      });
    }

    final durationMs = widget.targetLoops * loopMs;
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
    final effectiveRadius = widget.borderRadius ?? KRadius.md;
    Widget mediaContent;
    // True when a real demo image is on screen (not the anatomy fallback).
    var showsPhoto = false;
    final isTest = _isTestEnvironment;
    if (isTest) {
      mediaContent = _buildAnatomicalFallback();
    } else if (_hasLiveMedia) {
      final image = Image.network(
        _resolvedUrl!,
        fit: widget.fit,
        // Never decode demo media wider than the screen (they are often
        // large GIFs; every frame is decoded at this size).
        cacheWidth: _decodeWidth(context),
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (frame != null && !_firstFrameRendered) {
            _onFirstFrameDecoded();
          }
          if (frame != null && frame >= 12 && _currentLoop == 1) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _currentLoop == 1) {
                setState(() => _currentLoop = 2);
              }
            });
          }
          return child;
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return _MediaFadeIn(child: child);
          return _buildLoadingPlaceholder();
        },
        errorBuilder: (context, error, stackTrace) {
          final failedUrl = _resolvedUrl!;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _onImageError(failedUrl);
          });
          // Paint over the photo matte so the fallback sits on the card.
          return ColoredBox(
            color: KColor.isDark ? KColor.card : KColor.cardHigh,
            child: _buildAnatomicalFallback(),
          );
        },
      );
      // Demo images are drawn on white. Give them a white matte that fills the
      // frame, so the picture reads as one plate rather than a white box
      // inside a cream one. On Carbon the plate is dimmed a touch so it
      // doesn't glare against true black.
      showsPhoto = true;
      mediaContent = KColor.isDark
          ? ColorFiltered(
              colorFilter: const ColorFilter.matrix(<double>[
                0.86, 0, 0, 0, 0,
                0, 0.86, 0, 0, 0,
                0, 0, 0.86, 0, 0,
                0, 0, 0, 1, 0,
              ]),
              child: ColoredBox(color: Colors.white, child: image),
            )
          : ColoredBox(color: Colors.white, child: image);
    } else {
      mediaContent = _buildAnatomicalFallback();
    }

    final dark = KColor.isDark;
    final mediaCard = Container(
      height: widget.height,
      width: widget.width,
      decoration: BoxDecoration(
        color: showsPhoto ? null : (dark ? KColor.card : KColor.cardHigh),
        borderRadius: effectiveRadius,
        border: Border.all(
          color: dark ? KColor.fg.withValues(alpha: 0.08) : KColor.border,
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(child: mediaContent),

          if (widget.showAttribution && _hasLiveMedia && widget.height >= 100)
            Positioned(
              left: KSpacing.sm,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: KColor.surface.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: KColor.fg.withValues(alpha: dark ? 0.08 : 0.10), width: 0.6),
                ),
                child: Text(
                  ExerciseMediaService.attribution,
                  style: KText.caption.copyWith(
                    color: KColor.textSecondary,
                    fontSize: 10,
                    height: 1.2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    if (widget.interactiveZoom && _hasLiveMedia && widget.height >= 100) {
      return Semantics(
        button: true,
        label: 'Expand exercise demonstration',
        child: GestureDetector(
          onTap: () => _openZoomDialog(context, _resolvedUrl!),
          child: Stack(
            children: [
              mediaCard,
              Positioned(
                right: KSpacing.sm,
                top: KSpacing.sm,
                child: ExcludeSemantics(
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: KColor.surface.withValues(alpha: 0.82),
                      shape: BoxShape.circle,
                      border: Border.all(color: KColor.fg.withValues(alpha: dark ? 0.12 : 0.10), width: 0.8),
                    ),
                    child: Icon(
                      Icons.fullscreen_rounded,
                      size: 18,
                      color: KColor.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return mediaCard;
  }

  Widget _buildLoadingPlaceholder() {
    if (widget.height < 70) {
      return ColoredBox(
        color: KColor.cardHigh,
        child: Center(
          child: Icon(
            Icons.fitness_center_rounded,
            size: 16,
            color: KColor.textDisabled,
          ),
        ),
      );
    }
    // Skeleton shaped like the media slot; the label keeps "loading" legible
    // even when the shimmer is static (reduced motion).
    return Stack(
      children: [
        Positioned.fill(
          child: KShimmer(
            child: ColoredBox(color: KColor.cardHigh),
          ),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.fitness_center_rounded, size: 22, color: KColor.textMuted),
              const SizedBox(height: KSpacing.sm),
              Text(
                'Loading the demo…',
                style: KText.caption.copyWith(color: KColor.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAnatomicalFallback() {
    if (!widget.showMuscleMapFallback ||
        widget.disableNetwork ||
        ExerciseMediaWidget.disableNetworkForTesting) {
      return Center(
        child: ExcludeSemantics(
          child: Icon(
            Icons.fitness_center_rounded,
            size: (widget.height * 0.4).clamp(16.0, 40.0),
            color: KColor.textDisabled,
          ),
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
        child: ExcludeSemantics(
          child: Icon(
            Icons.fitness_center_rounded,
            size: 20,
            color: KColor.textMuted,
          ),
        ),
      );
    }

    return Stack(
      children: [
        // Quiet light pool behind the silhouette (neutral, not a hue).
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                radius: 0.75,
                colors: [
                  KColor.fg.withValues(alpha: KColor.isDark ? 0.05 : 0.035),
                  KColor.fg.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(KSpacing.sm),
            child: MuscleBodyMap(
              view: BodyView.sideBySide,
              highlightedMuscles: targetMuscles,
              // Primary = full ink, secondary = set-back ink, so the two
              // read apart by weight without a new hue.
              muscleColorMap: {
                if (primary.isNotEmpty) primary: KColor.ink,
                for (final s in secondary) s: KColor.fat,
              },
              height: widget.height - 16,
            ),
          ),
        ),
        Positioned(
          bottom: 6,
          right: KSpacing.sm,
          child: Text(
            'Target anatomy',
            style: KText.caption.copyWith(
              color: KColor.textMuted,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }

  void _openZoomDialog(BuildContext context, String url) {
    showDialog(
      context: context,
      barrierColor: KColor.bg.withValues(alpha: 0.9),
      builder: (ctx) {
        final title = _resolvedDefinition?.displayName ??
            widget.exercise?.name ??
            widget.exerciseName ??
            'Visual demonstration';

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(KSpacing.lg),
          child: Stack(
            alignment: Alignment.center,
            children: [
              InteractiveViewer(
                minScale: 0.8,
                maxScale: 3.5,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 450, maxHeight: 450),
                  decoration: BoxDecoration(
                    color: KColor.surface,
                    borderRadius: KRadius.xl,
                    border: Border.all(
                      color: KColor.isDark ? KColor.fg.withValues(alpha: 0.08) : KColor.border,
                    ),
                    boxShadow: KShadow.card,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(KSpacing.lg, KSpacing.md, KSpacing.xs, KSpacing.sm),
                        child: Row(
                          children: [
                            Container(
                              width: 3,
                              height: 16,
                              margin: const EdgeInsetsDirectional.only(end: KSpacing.sm),
                              decoration: BoxDecoration(
                                borderRadius: KRadius.pill,
                                color: KColor.ink,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                title,
                                style: KText.h3,
                                maxLines: 2,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Close',
                              onPressed: () => Navigator.of(ctx).pop(),
                              icon: Icon(Icons.close_rounded, color: KColor.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: KColor.isDark ? KColor.fg.withValues(alpha: 0.08) : KColor.border),
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.all(KSpacing.md),
                          child: ClipRRect(
                            borderRadius: KRadius.md,
                            child: Image.network(
                              url,
                              fit: BoxFit.contain,
                              cacheWidth: _decodeWidth(context),
                              gaplessPlayback: true,
                              errorBuilder: (context, error, stackTrace) => Padding(
                                padding: const EdgeInsets.all(KSpacing.lg),
                                child: Text(
                                  'The demo could not load right now.',
                                  textAlign: TextAlign.center,
                                  style: KText.body.copyWith(color: KColor.textSecondary),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(KSpacing.sm),
                        alignment: Alignment.center,
                        child: Text(
                          ExerciseMediaService.attribution,
                          style: KText.caption.copyWith(color: KColor.textMuted, fontSize: 11),
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

/// Fades decoded media in once on mount instead of popping it onto the card.
class _MediaFadeIn extends StatelessWidget {
  const _MediaFadeIn({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: KMotion.of(context, KMotion.quick),
      curve: KMotion.decelerate,
      builder: (context, v, child) => Opacity(opacity: v, child: child),
      child: child,
    );
  }
}

/// Decode width for exercise media: the screen's physical width.
int _decodeWidth(BuildContext context) =>
    (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(1, 1440);
