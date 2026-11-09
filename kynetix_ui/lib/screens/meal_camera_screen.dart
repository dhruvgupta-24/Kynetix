import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../config/app_theme.dart';
import '../models/day_log.dart';
import '../models/nutrition_result.dart';
import '../services/barcode_app_settings.dart';
import '../services/meal_photo_logger.dart';
import '../services/meal_photo_service.dart';
import '../services/meal_repeat_service.dart';
import '../ui/k_meal_mark.dart';
import '../ui/k_rolling.dart';
import '../ui/k_toast.dart';
import 'add_meal_screen.dart';
import 'barcode_scanner_screen.dart';
import 'day_detail_screen.dart';

// ─── Snap a meal ──────────────────────────────────────────────────────────────
//
// Point the camera at a plate, tap once. Kyno names each food and its portion
// (purpose meal_photo), then the app prices every food through the same
// pipeline as a typed meal, so a photo of "3 roti and dal" logs the same
// numbers as typing it. The result lands on the photo: Log meal (one tap) or
// Review (the full editor). Nothing is logged without that tap.

/// Where the flow was opened from.
/// - [log]: the + sheet and the day screen. The result panel logs directly.
/// - [fill]: the meal editor. The result goes back into its rows.
enum MealPhotoMode { log, fill }

/// What a finished photo flow did.
class MealPhotoOutcome {
  /// The logged entry (one-tap log, or saved from the editor).
  final MealEntry? entry;

  /// Fill mode: the estimate and its text for the editor's rows.
  final NutritionResult? result;
  final String? text;

  /// Fill mode: the photo, for the editor's header.
  final Uint8List? photo;

  const MealPhotoOutcome({this.entry, this.result, this.text, this.photo});
}

/// Opens the camera and runs the whole flow. [section] defaults to the
/// time-of-day section for [date]. Shows the success toast (with Undo for a
/// one-tap log) itself; [onChanged] runs after a log and after an undo so
/// the caller can refresh.
Future<MealPhotoOutcome?> openMealPhotoFlow(
  BuildContext context, {
  required DateTime date,
  MealSection? section,
  MealPhotoMode mode = MealPhotoMode.log,
  VoidCallback? onChanged,
}) async {
  final toaster = KToaster.of(context);
  final navigator = Navigator.of(context);
  final accessible = MediaQuery.maybeAccessibleNavigationOf(context) ?? false;
  final sec = section ?? DayDetailScreen.getSectionForTimeAndDate(DateTime.now(), date);

  final done = await navigator.push<_CameraDone>(
    kFadeThroughRoute<_CameraDone>(
      builder: (_) => MealCameraScreen(date: date, section: sec, mode: mode),
    ),
  );
  if (done == null) return null;

  switch (done.kind) {
    case _DoneKind.logged:
      final entry = done.entry!;
      onChanged?.call();
      toaster.show(
        MealPhotoLogger.toastFor(entry),
        kind: KToastKind.success,
        actionLabel: 'Undo',
        duration: accessible ? const Duration(seconds: 12) : null,
        onAction: () async {
          await MealRepeatService.undo(date, [entry]);
          onChanged?.call();
        },
      );
      return MealPhotoOutcome(entry: entry);

    case _DoneKind.review:
      final saved = await navigator.push<dynamic>(
        kRiseRoute<dynamic>(
          builder: (_) => AddMealScreen(
            section: done.section ?? sec,
            date: date,
            initialResult: done.result,
            photo: done.photo,
          ),
        ),
      );
      if (saved is MealEntry) {
        onChanged?.call();
        KHaptics.success();
        toaster.show(
          'Meal logged to ${saved.section.displayName}.',
          kind: KToastKind.success,
          duration: Duration(seconds: accessible ? 8 : 3),
        );
        return MealPhotoOutcome(entry: saved);
      }
      return null;

    case _DoneKind.fill:
      return MealPhotoOutcome(result: done.result, text: done.text, photo: done.photo);

    case _DoneKind.barcode:
      if (!context.mounted) return null;
      final scanned = await openBarcodeFlow(
        context,
        date: date,
        section: sec,
        mode: mode == MealPhotoMode.fill ? BarcodeFlowMode.fill : BarcodeFlowMode.log,
      );
      if (scanned?.entry != null) onChanged?.call();
      return MealPhotoOutcome(entry: scanned?.entry, result: scanned?.result);

    case _DoneKind.describe:
      if (mode == MealPhotoMode.fill) return null;
      final saved = await navigator.push<dynamic>(
        kRiseRoute<dynamic>(builder: (_) => AddMealScreen(section: sec, date: date)),
      );
      if (saved is MealEntry) {
        onChanged?.call();
        return MealPhotoOutcome(entry: saved);
      }
      return null;
  }
}

enum _DoneKind { logged, review, fill, barcode, describe }

class _CameraDone {
  const _CameraDone(this.kind, {this.entry, this.result, this.text, this.photo, this.section});
  final _DoneKind kind;
  final MealSection? section;
  final MealEntry? entry;
  final NutritionResult? result;
  final String? text;
  final Uint8List? photo;
}

/// Where the screen is in its flow.
enum _Stage { starting, live, noCamera, reading, pricing, result, failed }

class MealCameraScreen extends StatefulWidget {
  const MealCameraScreen({
    super.key,
    required this.date,
    required this.section,
    this.mode = MealPhotoMode.log,
  });

  final DateTime date;
  final MealSection section;
  final MealPhotoMode mode;

  /// Tests have no camera plugin: the screen opens on its no-camera state,
  /// where the gallery button still works through [debugPickPhoto].
  @visibleForTesting
  static bool debugCameraEnabled = true;

  /// Tests replace the gallery picker.
  @visibleForTesting
  static Future<Uint8List?> Function()? debugPickPhoto;

  @override
  State<MealCameraScreen> createState() => _MealCameraScreenState();
}

class _MealCameraScreenState extends State<MealCameraScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  CameraController? _camera;
  bool _cameraDenied = false;
  bool _torch = false;

  _Stage _stage = _Stage.starting;

  /// The meal this goes to: the time-of-day guess until the person picks.
  late MealSection _section = widget.section;
  Uint8List? _photo;
  String? _note;
  MealPhotoReading? _reading;
  NutritionResult? _result;
  MealPhotoException? _failure;

  /// Bumped per read, so a late answer from an abandoned read is ignored.
  int _readToken = 0;

  /// The plate guide reading arc, and the settle into the result layout.
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: KMotion.emphasized,
  );

  /// Tap-to-focus ring.
  Offset? _focusAt;
  int _focusTick = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (MealCameraScreen.debugCameraEnabled) {
      unawaited(_startCamera());
    } else {
      _stage = _Stage.noCamera;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _readToken++;
    _spin.dispose();
    _settle.dispose();
    final c = _camera;
    _camera = null;
    unawaited(c?.dispose());
    super.dispose();
  }

  // ── Camera ────────────────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!MealCameraScreen.debugCameraEnabled) return;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      // Release the camera while away; the plugin can't hold it in the
      // background anyway.
      final c = _camera;
      if (c != null) {
        _camera = null;
        _torch = false;
        unawaited(c.dispose());
        if (mounted) setState(() {});
      }
    } else if (state == AppLifecycleState.resumed) {
      // Only the live viewfinder needs it back; a frozen photo doesn't.
      if (_camera == null && (_stage == _Stage.live || _stage == _Stage.starting)) {
        unawaited(_startCamera());
      }
    }
  }

  Future<void> _startCamera() async {
    if (mounted && _stage != _Stage.starting) setState(() => _stage = _Stage.starting);
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) throw CameraException('NoCamera', 'No camera on this device');
      final back = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      final c = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await c.initialize();
      if (!mounted) {
        unawaited(c.dispose());
        return;
      }
      try {
        await c.setFlashMode(FlashMode.off);
      } catch (_) {}
      setState(() {
        _camera = c;
        _cameraDenied = false;
        if (_stage == _Stage.starting) _stage = _Stage.live;
      });
    } on CameraException catch (e) {
      debugPrint('[MealCamera] camera failed: ${e.code}');
      if (!mounted) return;
      setState(() {
        _cameraDenied = e.code.startsWith('CameraAccess');
        if (_stage == _Stage.starting) _stage = _Stage.noCamera;
      });
    } catch (e) {
      debugPrint('[MealCamera] camera failed: ${e.runtimeType}');
      if (!mounted) return;
      setState(() {
        if (_stage == _Stage.starting) _stage = _Stage.noCamera;
      });
    }
  }

  Future<void> _toggleTorch() async {
    final c = _camera;
    if (c == null) return;
    KHaptics.select();
    final on = !_torch;
    try {
      await c.setFlashMode(on ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _torch = on);
    } catch (_) {
      // No torch on this lens: the button simply does nothing.
    }
  }

  void _focus(TapUpDetails d, Size size) {
    final c = _camera;
    if (c == null || _stage != _Stage.live) return;
    final p = Offset(
      (d.localPosition.dx / size.width).clamp(0.0, 1.0),
      (d.localPosition.dy / size.height).clamp(0.0, 1.0),
    );
    unawaited(c.setFocusPoint(p).catchError((_) {}));
    unawaited(c.setExposurePoint(p).catchError((_) {}));
    setState(() {
      _focusAt = d.localPosition;
      _focusTick++;
    });
  }

  Future<void> _shoot() async {
    final c = _camera;
    if (c == null || !c.value.isInitialized || c.value.isTakingPicture || _stage != _Stage.live) {
      return;
    }
    KHaptics.commit();
    try {
      final file = await c.takePicture();
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      // The torch has done its job; switch it off with the shot.
      if (_torch) {
        unawaited(c.setFlashMode(FlashMode.off).catchError((_) {}));
        _torch = false;
      }
      unawaited(c.pausePreview().catchError((_) {}));
      await _read(bytes);
    } catch (e) {
      debugPrint('[MealCamera] capture failed: ${e.runtimeType}');
      if (!mounted) return;
      KToaster.of(context).show("Couldn't take the photo. Try again.");
    }
  }

  Future<void> _pickFromGallery() async {
    KHaptics.select();
    Uint8List? bytes;
    final override = MealCameraScreen.debugPickPhoto;
    try {
      if (override != null) {
        bytes = await override();
      } else {
        final file = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: _maxEdge.toDouble(),
          maxHeight: _maxEdge.toDouble(),
          imageQuality: 82,
        );
        bytes = file == null ? null : await file.readAsBytes();
      }
    } catch (e) {
      debugPrint('[MealCamera] gallery failed: ${e.runtimeType}');
    }
    if (bytes == null || !mounted) return;
    unawaited(_camera?.pausePreview().catchError((_) {}));
    await _read(bytes);
  }

  // ── Reading ───────────────────────────────────────────────────────────────

  /// Longest edge sent to Kyno. Plenty for naming food; keeps the upload
  /// small on a slow connection.
  static const _maxEdge = 1280;

  /// Bytes above this are re-encoded before sending (the router caps a
  /// photo at about 2 MB).
  static const _maxBytes = 1400000;

  Future<void> _read(Uint8List raw, {String? note}) async {
    final token = ++_readToken;
    setState(() {
      _photo ??= raw;
      _stage = _Stage.reading;
      _failure = null;
      _reading = null;
      _result = null;
    });
    _settle.value = 0;
    _syncSpin();

    try {
      final jpeg = await _shrink(raw);
      final reading = await MealPhotoService.instance.read(jpeg, note: note ?? _note);
      if (!mounted || token != _readToken) return;
      setState(() {
        _reading = reading;
        _stage = _Stage.pricing;
      });
      final result = await reading.estimate();
      if (!mounted || token != _readToken) return;
      setState(() {
        _result = result;
        _stage = _Stage.result;
      });
      _syncSpin();
      KHaptics.success();
      if (KMotion.reduced(context)) {
        _settle.value = 1;
      } else {
        unawaited(_settle.animateTo(1, curve: KMotion.emphasizedCurve));
      }
    } on MealPhotoException catch (e) {
      if (!mounted || token != _readToken) return;
      KHaptics.reject();
      setState(() {
        _failure = e;
        _stage = _Stage.failed;
      });
      _syncSpin();
    } catch (e) {
      debugPrint('[MealCamera] read failed: ${e.runtimeType}');
      if (!mounted || token != _readToken) return;
      KHaptics.reject();
      setState(() {
        _failure = const MealPhotoException(MealPhotoFailure.unreadable);
        _stage = _Stage.failed;
      });
      _syncSpin();
    }
  }

  /// Keeps the photo under the router's cap: a big camera JPEG is decoded
  /// natively at [_maxEdge] and re-encoded off the UI isolate. Small photos
  /// go as they are.
  static Future<Uint8List> _shrink(Uint8List raw) async {
    if (raw.lengthInBytes <= _maxBytes) return raw;
    final codec = await ui.instantiateImageCodec(raw);
    final first = await codec.getNextFrame();
    final w = first.image.width, h = first.image.height;
    first.image.dispose();
    codec.dispose();
    final scale = _maxEdge / math.max(w, h);
    final tw = scale < 1 ? (w * scale).round() : w;
    final th = scale < 1 ? (h * scale).round() : h;
    final sized = await ui.instantiateImageCodec(raw, targetWidth: tw, targetHeight: th);
    final frame = await sized.getNextFrame();
    final rgba = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    frame.image.dispose();
    sized.dispose();
    if (rgba == null) return raw;
    return compute(_encodeJpeg, (rgba.buffer.asUint8List(), tw, th));
  }

  void _syncSpin() {
    final busy = _stage == _Stage.reading || _stage == _Stage.pricing;
    if (busy && KMotion.ambientAllowed(context)) {
      if (!_spin.isAnimating) unawaited(_spin.repeat());
    } else {
      _spin.stop();
    }
  }

  Future<void> _retake() async {
    KHaptics.select();
    _readToken++;
    setState(() {
      _photo = null;
      _reading = null;
      _result = null;
      _failure = null;
      _note = null;
      _stage = _camera != null ? _Stage.live : (MealCameraScreen.debugCameraEnabled ? _Stage.starting : _Stage.noCamera);
    });
    _settle.value = 0;
    _syncSpin();
    final c = _camera;
    if (c != null) {
      unawaited(c.resumePreview().catchError((_) {}));
    } else if (MealCameraScreen.debugCameraEnabled) {
      await _startCamera();
    }
  }

  Future<void> _addNote() async {
    final photo = _photo;
    if (photo == null) return;
    final note = await showKSheet<String>(
      context: context,
      builder: (_) => _NoteSheet(initial: _note),
    );
    if (note == null || !mounted) return;
    _note = note.trim().isEmpty ? null : note.trim();
    await _read(photo, note: _note);
  }

  /// The meal is guessed from the clock; a late lunch at 4 pm is still lunch.
  Future<void> _pickSection() async {
    KHaptics.select();
    final picked = await showKSheet<MealSection>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const KSheetHeader('Log to'),
            Padding(
              padding: const EdgeInsets.fromLTRB(KSpacing.p, KSpacing.md, KSpacing.p, KSpacing.xl),
              child: KMealSectionPicker(
                value: _section,
                onChanged: (s) => Navigator.of(ctx).pop(s),
              ),
            ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _section = picked);
  }

  // ── Finishing ─────────────────────────────────────────────────────────────

  void _log() {
    final result = _result;
    final reading = _reading;
    if (result == null || reading == null) return;
    if (widget.mode == MealPhotoMode.fill) {
      Navigator.of(context).pop(_CameraDone(_DoneKind.fill, result: result, text: reading.mealText, photo: _photo));
      return;
    }
    final entry = MealPhotoLogger.log(
      result: result,
      text: reading.mealText,
      date: widget.date,
      section: _section,
    );
    KHaptics.success();
    Navigator.of(context).pop(_CameraDone(_DoneKind.logged, entry: entry));
  }

  void _review() {
    final result = _result;
    final reading = _reading;
    if (result == null || reading == null) return;
    KHaptics.select();
    Navigator.of(context).pop(
      widget.mode == MealPhotoMode.fill
          ? _CameraDone(_DoneKind.fill, result: result, text: reading.mealText, photo: _photo)
          : _CameraDone(_DoneKind.review, result: result, text: reading.mealText, photo: _photo, section: _section),
    );
  }

  /// Foods Kyno flagged as unsure, by the name the pipeline used.
  Set<String> get _unsure {
    final reading = _reading;
    if (reading == null) return const {};
    return {
      for (final f in reading.foods)
        if (f.unsure) f.parsed.normalizedName.toLowerCase(),
    };
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = _Cam.p;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: PopScope(
        // Back from a frozen photo goes back to the camera, not out.
        canPop: _photo == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _photo != null) unawaited(_retake());
        },
        child: Scaffold(
          backgroundColor: p.bg,
          resizeToAvoidBottomInset: false,
          body: LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;
              final pad = MediaQuery.paddingOf(context);
              return AnimatedBuilder(
                animation: _settle,
                builder: (context, _) {
                  final plate = _PlateGeometry.of(size, pad, _settle.value);
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      _surface(size),
                      if (_stage != _Stage.noCamera)
                        IgnorePointer(
                          child: _PlateGuide(
                            plate: plate,
                            stage: _stage,
                            spin: _spin,
                          ),
                        ),
                      if (_focusAt != null && _stage == _Stage.live)
                        _FocusRing(key: ValueKey(_focusTick), at: _focusAt!),
                      if (_stage == _Stage.noCamera)
                        _NoCamera(
                          denied: _cameraDenied,
                          onOpenSettings: () async {
                            final toaster = KToaster.of(context);
                            final ok = await BarcodeAppSettings.open();
                            if (!ok) toaster.show(BarcodeAppSettings.manualPath);
                          },
                          onGallery: _pickFromGallery,
                          onDescribe: () => Navigator.of(context).pop(const _CameraDone(_DoneKind.describe)),
                          fill: widget.mode == MealPhotoMode.fill,
                        ),
                      if (_stage == _Stage.live || _stage == _Stage.starting)
                        Positioned(
                          left: KSpacing.p,
                          right: KSpacing.p,
                          top: plate.center.dy + plate.radius + KSpacing.xl,
                          child: _Hint(starting: _stage == _Stage.starting),
                        ),
                      if (_stage == _Stage.live || _stage == _Stage.starting)
                        _ShutterBar(
                          canShoot: _stage == _Stage.live,
                          onShoot: _shoot,
                          onGallery: _pickFromGallery,
                          onBarcode: () {
                            KHaptics.select();
                            Navigator.of(context).pop(const _CameraDone(_DoneKind.barcode));
                          },
                        ),
                      if (_stage == _Stage.reading || _stage == _Stage.pricing)
                        Positioned(
                          left: KSpacing.p,
                          right: KSpacing.p,
                          top: plate.center.dy + plate.radius + KSpacing.xl,
                          child: _ReadingStatus(pricing: _stage == _Stage.pricing, found: _reading?.foods.length),
                        ),
                      if (_stage == _Stage.result && _result != null)
                        _ResultPanel(
                          result: _result!,
                          title: _reading?.title,
                          unsure: _unsure,
                          reveal: _settle,
                          fill: widget.mode == MealPhotoMode.fill,
                          section: _section,
                          onSection: _pickSection,
                          onLog: _log,
                          onReview: _review,
                          onRetake: _retake,
                          onNote: _addNote,
                        ),
                      if (_stage == _Stage.failed && _failure != null)
                        _FailedPanel(
                          failure: _failure!,
                          onRetake: _retake,
                          onTryAgain: () => _read(_photo!, note: _note),
                          onNote: _addNote,
                          onDescribe: widget.mode == MealPhotoMode.fill
                              ? null
                              : () => Navigator.of(context).pop(const _CameraDone(_DoneKind.describe)),
                        ),
                      _TopBar(
                        section: _section,
                        fill: widget.mode == MealPhotoMode.fill,
                        showTorch: _camera != null && _stage == _Stage.live,
                        torch: _torch,
                        onTorch: _toggleTorch,
                        onClose: () {
                          if (_photo != null) {
                            unawaited(_retake());
                          } else {
                            Navigator.of(context).maybePop();
                          }
                        },
                        closeIsBack: _photo != null,
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  /// The camera feed, or the frozen photo once one is taken.
  Widget _surface(Size size) {
    final photo = _photo;
    if (photo != null) {
      return Image.memory(
        photo,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        excludeFromSemantics: true,
      );
    }
    final c = _camera;
    if (c == null || !c.value.isInitialized) return ColoredBox(color: _Cam.p.bg);
    final preview = c.value.previewSize;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) => _focus(d, size),
      child: ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            // previewSize is landscape; the phone is portrait.
            width: preview?.height ?? size.width,
            height: preview?.width ?? size.height,
            child: CameraPreview(c),
          ),
        ),
      ),
    );
  }
}

/// JPEG encode for [_MealCameraScreenState._shrink], on a background isolate.
Uint8List _encodeJpeg((Uint8List, int, int) args) {
  final (rgba, w, h) = args;
  final image = img.Image.fromBytes(
    width: w,
    height: h,
    bytes: rgba.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return img.encodeJpg(image, quality: 82);
}

// ─── Geometry ─────────────────────────────────────────────────────────────────

/// The plate circle: centred a little above the middle while shooting, then
/// lifted and shrunk ([settle] 0 to 1) to sit above the result panel.
class _PlateGeometry {
  const _PlateGeometry(this.center, this.radius);
  final Offset center;
  final double radius;

  static _PlateGeometry of(Size size, EdgeInsets pad, double settle) {
    final shootR = math.min(size.width * 0.42, size.height * 0.27);
    final shootC = Offset(size.width / 2, pad.top + (size.height - pad.top) * 0.40);
    // Result layout: the panel takes the lower part, the plate rides above.
    final resultR = math.min(size.width * 0.27, size.height * 0.15);
    final resultC = Offset(size.width / 2, pad.top + 64 + resultR + 8);
    final t = KMotion.emphasizedCurve.transform(settle.clamp(0.0, 1.0));
    return _PlateGeometry(
      Offset.lerp(shootC, resultC, t)!,
      ui.lerpDouble(shootR, resultR, t)!,
    );
  }
}

// ─── Plate guide ──────────────────────────────────────────────────────────────

/// A dark scrim with a round window for the plate, a bezel of fine ticks
/// (the same dial language as the fuel rings), and while Kyno reads, an
/// ember arc walking the rim. On the result the arc closes into a full ring.
class _PlateGuide extends StatelessWidget {
  const _PlateGuide({required this.plate, required this.stage, required this.spin});

  final _PlateGeometry plate;
  final _Stage stage;
  final Animation<double> spin;

  @override
  Widget build(BuildContext context) {
    final p = _Cam.p;
    final reading = stage == _Stage.reading || stage == _Stage.pricing;
    final ambient = KMotion.ambientAllowed(context);
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _PlatePainter(
            center: plate.center,
            radius: plate.radius,
            scrim: p.bg.withValues(alpha: stage == _Stage.result ? 0.72 : (reading ? 0.62 : 0.5)),
            tick: p.fg.withValues(alpha: 0.42),
            rim: p.fg.withValues(alpha: 0.26),
            arc: p.ember,
            done: stage == _Stage.result,
            spin: reading && ambient ? spin : null,
            still: reading && !ambient,
          ),
        ),
      ),
    );
  }
}

class _PlatePainter extends CustomPainter {
  _PlatePainter({
    required this.center,
    required this.radius,
    required this.scrim,
    required this.tick,
    required this.rim,
    required this.arc,
    required this.done,
    required this.spin,
    required this.still,
  }) : super(repaint: spin);

  final Offset center;
  final double radius;
  final Color scrim, tick, rim, arc;
  final bool done;
  final Animation<double>? spin;

  /// Reading under reduced motion: a still quarter arc says "working".
  final bool still;

  @override
  void paint(Canvas canvas, Size size) {
    // Scrim with the plate cut out.
    final hole = Path()..addOval(Rect.fromCircle(center: center, radius: radius));
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), hole),
      Paint()..color = scrim,
    );

    // Rim hairline.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = rim,
    );

    // Bezel ticks just outside the rim: 60 fine, every 15th long.
    final t = Paint()
      ..strokeCap = StrokeCap.round
      ..color = tick;
    for (var i = 0; i < 60; i++) {
      final a = i / 60 * math.pi * 2 - math.pi / 2;
      final major = i % 15 == 0;
      final r0 = radius + 7;
      final r1 = radius + (major ? 17 : 11);
      t.strokeWidth = major ? 2 : 1;
      canvas.drawLine(
        center + Offset(math.cos(a), math.sin(a)) * r0,
        center + Offset(math.cos(a), math.sin(a)) * r1,
        t,
      );
    }

    final ring = Rect.fromCircle(center: center, radius: radius);
    final a = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = arc;
    if (done) {
      canvas.drawArc(ring, -math.pi / 2, math.pi * 2, false, a);
    } else if (spin != null) {
      final v = spin!.value;
      // The arc breathes as it walks: 40 to 110 degrees long.
      final sweep = (40 + 70 * (0.5 - 0.5 * math.cos(v * math.pi * 2))) / 180 * math.pi;
      canvas.drawArc(ring, v * math.pi * 2 - math.pi / 2, sweep, false, a);
    } else if (still) {
      canvas.drawArc(ring, -math.pi / 2, math.pi / 2, false, a);
    }
  }

  @override
  bool shouldRepaint(_PlatePainter old) =>
      old.center != center ||
      old.radius != radius ||
      old.scrim != scrim ||
      old.tick != tick ||
      old.rim != rim ||
      old.arc != arc ||
      old.done != done ||
      old.spin != spin ||
      old.still != still;
}

// ─── Pieces ───────────────────────────────────────────────────────────────────

/// The camera surface always uses the dark palette, whatever the app theme.
abstract final class _Cam {
  static KPalette get p => KPalette.dark;
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.section,
    required this.fill,
    required this.showTorch,
    required this.torch,
    required this.onTorch,
    required this.onClose,
    required this.closeIsBack,
  });

  final MealSection section;
  final bool fill;
  final bool showTorch;
  final bool torch;
  final VoidCallback onTorch;
  final VoidCallback onClose;
  final bool closeIsBack;

  @override
  Widget build(BuildContext context) {
    final p = _Cam.p;
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(KSpacing.md, KSpacing.sm, KSpacing.md, 0),
          child: Row(
            children: [
              _RoundButton(
                icon: closeIsBack ? Icons.arrow_back_rounded : Icons.close_rounded,
                tooltip: closeIsBack ? 'Retake' : 'Close',
                onTap: onClose,
              ),
              const SizedBox(width: KSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text('Snap a meal', style: KText.h2.copyWith(color: p.textPrimary)),
                    ),
                    Text(
                      fill ? 'Adds to the meal you\'re editing' : 'For ${section.displayName}',
                      style: KText.caption.copyWith(fontSize: 13.5, color: p.textSecondary),
                    ),
                  ],
                ),
              ),
              if (showTorch)
                _RoundButton(
                  icon: torch ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                  tooltip: torch ? 'Torch off' : 'Torch on',
                  selected: torch,
                  onTap: onTorch,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final p = _Cam.p;
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, size: 22),
      color: selected ? p.onInk : p.textPrimary,
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        backgroundColor: selected ? p.ink : p.bg.withValues(alpha: 0.42),
        side: BorderSide(color: selected ? p.ink : p.fg.withValues(alpha: 0.2)),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.starting});
  final bool starting;

  @override
  Widget build(BuildContext context) {
    final p = _Cam.p;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          starting ? 'Starting the camera…' : 'Fit the plate in the circle',
          style: KText.bodyMedium.copyWith(color: p.textPrimary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),
        Text(
          'From above, in good light. Katoris and spoons help with size.',
          style: KText.caption.copyWith(fontSize: 13, color: p.textSecondary),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// Gallery, shutter and barcode, along the bottom.
class _ShutterBar extends StatelessWidget {
  const _ShutterBar({
    required this.canShoot,
    required this.onShoot,
    required this.onGallery,
    required this.onBarcode,
  });

  final bool canShoot;
  final VoidCallback onShoot;
  final VoidCallback onGallery;
  final VoidCallback onBarcode;

  @override
  Widget build(BuildContext context) {
    final p = _Cam.p;
    Widget side(IconData icon, String label, VoidCallback onTap) => Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          child: Pressable(
            onTap: onTap,
            borderRadius: KRadius.md,
            scale: 0.94,
            child: SizedBox(
              width: 76,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: p.bg.withValues(alpha: 0.42),
                      shape: BoxShape.circle,
                      border: Border.all(color: p.fg.withValues(alpha: 0.2)),
                    ),
                    child: Icon(icon, size: 22, color: p.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    style: KText.caption.copyWith(color: p.textSecondary, fontSize: 12.5),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(KSpacing.p, 0, KSpacing.p, KSpacing.xl),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              side(Icons.photo_library_outlined, 'Gallery', onGallery),
              _Shutter(enabled: canShoot, onTap: onShoot),
              side(KIcons.scan, 'Barcode', onBarcode),
            ],
          ),
        ),
      ),
    );
  }
}

/// A camera shutter: a bone ring around a disc that squeezes under the finger.
class _Shutter extends StatefulWidget {
  const _Shutter({required this.enabled, required this.onTap});
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_Shutter> createState() => _ShutterState();
}

class _ShutterState extends State<_Shutter> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = _Cam.p;
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: 'Take photo',
      child: GestureDetector(
        onTapDown: widget.enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: widget.enabled
            ? (_) {
                setState(() => _down = false);
                widget.onTap();
              }
            : null,
        child: AnimatedOpacity(
          duration: KMotion.of(context, KMotion.quick),
          opacity: widget.enabled ? 1 : 0.4,
          child: SizedBox(
            width: 84,
            height: 84,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: p.ink, width: 4),
                  ),
                ),
                AnimatedScale(
                  scale: _down ? 0.86 : 1,
                  duration: KMotion.of(context, KMotion.press),
                  curve: KMotion.easeOut,
                  child: Container(
                    width: 66,
                    height: 66,
                    decoration: BoxDecoration(color: p.ink, shape: BoxShape.circle),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small square that lands where you tapped to focus, then fades.
class _FocusRing extends StatefulWidget {
  const _FocusRing({super.key, required this.at});
  final Offset at;

  @override
  State<_FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<_FocusRing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (KMotion.reduced(context)) {
      _c.value = 1;
    } else if (!_c.isAnimating && _c.value == 0) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _Cam.p;
    return Positioned(
      left: widget.at.dx - 32,
      top: widget.at.dy - 32,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final v = _c.value;
            final scale = 1.25 - 0.25 * KMotion.easeOut.transform((v / 0.3).clamp(0.0, 1.0));
            final opacity = v < 0.7 ? 1.0 : (1 - (v - 0.7) / 0.3);
            return Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    borderRadius: KRadius.sm,
                    border: Border.all(color: p.ink, width: 1.5),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// What Kyno is doing right now. The lines name the real work of the
/// request (finding the foods, then sizing them), then the app's own
/// lookups; each holds at least 2.6 s and the last one stays.
class _ReadingStatus extends StatefulWidget {
  const _ReadingStatus({required this.pricing, required this.found});
  final bool pricing;
  final int? found;

  @override
  State<_ReadingStatus> createState() => _ReadingStatusState();
}

class _ReadingStatusState extends State<_ReadingStatus> {
  static const _lines = ['Looking at your plate…', 'Picking out each food…', 'Sizing the portions…'];
  int _i = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 2600), (_) {
      if (!mounted || widget.pricing) return;
      if (_i < _lines.length - 1) setState(() => _i++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _Cam.p;
    final found = widget.found;
    final line = widget.pricing
        ? (found == null ? 'Checking your saved numbers…' : 'Found ${plural(found, 'food')}. Checking your saved numbers…')
        : _lines[_i];
    return Semantics(
      liveRegion: true,
      child: AnimatedSwitcher(
        duration: KMotion.of(context, KMotion.standard),
        switchInCurve: KMotion.decelerate,
        switchOutCurve: KMotion.accelerate,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(anim),
            child: child,
          ),
        ),
        child: Text(
          line,
          key: ValueKey(line),
          style: KText.bodyMedium.copyWith(color: p.textPrimary, fontSize: 15),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/// The answer, rising over the photo: the plate's total, each food with its
/// amount and calories, and the two ways on (log now, or review first).
class _ResultPanel extends StatelessWidget {
  const _ResultPanel({
    required this.result,
    required this.title,
    required this.unsure,
    required this.reveal,
    required this.fill,
    required this.section,
    required this.onSection,
    required this.onLog,
    required this.onReview,
    required this.onRetake,
    required this.onNote,
  });

  final NutritionResult result;
  final String? title;
  final Set<String> unsure;
  final Animation<double> reveal;
  final bool fill;
  final MealSection section;
  final VoidCallback onSection;
  final VoidCallback onLog;
  final VoidCallback onReview;
  final VoidCallback onRetake;
  final VoidCallback onNote;

  static String _sentence(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static String _amount(NutritionItem i) {
    final q = i.quantity;
    final qs = q == q.roundToDouble() ? q.round().toString() : q.toStringAsFixed(q * 2 == (q * 2).roundToDouble() ? 1 : 2);
    return switch (i.unit) {
      'g' => '$qs g',
      'ml' => '$qs ml',
      'serving' => q == 1 ? '1 pc' : '$qs pcs',
      final u => '$qs $u',
    };
  }

  @override
  Widget build(BuildContext context) {
    final items = result.items;
    final kcal = result.calories.mid.round();
    final protein = result.protein.mid;
    final carbs = result.carbohydrates?.mid ?? 0;
    final fat = result.fat?.mid ?? 0;
    final anyUnsure = items.any((i) => unsure.contains(i.name.toLowerCase()));
    final reduced = KMotion.reduced(context);
    final bottom = MediaQuery.paddingOf(context).bottom;

    final panel = Container(
      decoration: BoxDecoration(
        color: KColor.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: KColor.isDark ? KColor.fg.withValues(alpha: 0.08) : KColor.border)),
      ),
      padding: EdgeInsets.fromLTRB(KSpacing.p, KSpacing.lg, KSpacing.p, KSpacing.lg + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title == null ? 'Your plate' : _sentence(title!),
                      style: KText.h2,
                      maxLines: 2,
                    ),
                    const SizedBox(height: KSpacing.xs),
                    if (fill)
                      Text("Kyno's estimate", style: KText.caption.copyWith(color: KColor.textMuted))
                    else
                      _SectionPill(section: section, onTap: onSection),
                  ],
                ),
              ),
              const SizedBox(width: KSpacing.md),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  KRollingNumber.int(
                    kcal,
                    fromZero: !reduced,
                    style: KText.numDisplay.copyWith(fontSize: 32),
                    semanticsLabel: '$kcal kilocalories',
                  ),
                  Text('kcal', style: KText.caption.copyWith(color: KColor.textMuted)),
                ],
              ),
            ],
          ),
          const SizedBox(height: KSpacing.md),
          // Macro line: protein leads, in its own colour.
          Wrap(
            spacing: KSpacing.lg,
            runSpacing: KSpacing.xs,
            children: [
              _MacroDot(label: 'Protein', grams: protein, color: KColor.protein, strong: true),
              _MacroDot(label: 'Carbs', grams: carbs, color: KColor.carbs),
              _MacroDot(label: 'Fat', grams: fat, color: KColor.fat),
            ],
          ),
          const SizedBox(height: KSpacing.md),
          Divider(height: 1, thickness: 1, color: KColor.hairline),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.26),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: items.length,
              itemBuilder: (context, i) {
                final item = items[i];
                final check = unsure.contains(item.name.toLowerCase());
                return KReveal(
                  index: i.clamp(0, 6),
                  rise: 6,
                  child: _FoodRow(
                    name: _sentence(item.name),
                    amount: _amount(item),
                    kcal: item.calories.mid.round(),
                    protein: item.protein.mid,
                    check: check,
                  ),
                );
              },
            ),
          ),
          if (anyUnsure) ...[
            const SizedBox(height: KSpacing.sm),
            Row(
              children: [
                Container(width: 6, height: 6, decoration: BoxDecoration(color: KColor.ember, shape: BoxShape.circle)),
                const SizedBox(width: KSpacing.sm),
                Expanded(
                  child: Text(
                    'Kyno is less sure about the marked ones. A quick look keeps your numbers honest.',
                    style: KText.caption.copyWith(color: KColor.textSecondary),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: KSpacing.lg),
          Row(
            children: [
              Expanded(
                child: KButton(
                  label: anyUnsure ? 'Log as is' : 'Review',
                  outlined: true,
                  onTap: anyUnsure ? onLog : onReview,
                ),
              ),
              const SizedBox(width: KSpacing.md),
              Expanded(
                child: KButton(
                  label: anyUnsure ? 'Review' : (fill ? 'Use these' : 'Log meal'),
                  onTap: anyUnsure ? onReview : onLog,
                ),
              ),
            ],
          ),
          const SizedBox(height: KSpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              KTextAction('Retake', onTap: onRetake),
              const SizedBox(width: KSpacing.md),
              KTextAction('Add a note for Kyno', onTap: onNote),
            ],
          ),
        ],
      ),
    );

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: AnimatedBuilder(
        animation: reveal,
        builder: (context, child) {
          final t = KMotion.decelerate.transform(reveal.value.clamp(0.0, 1.0));
          return FractionalTranslation(
            translation: Offset(0, 1 - t),
            child: child,
          );
        },
        // A live region: screen readers hear the answer once when it lands.
        child: Semantics(
          liveRegion: true,
          label: 'Kyno found ${plural(items.length, 'food')}, ${thousands(kcal)} kilocalories, '
              '${protein.round()} grams of protein.',
          child: panel,
        ),
      ),
    );
  }
}

/// "Kyno's estimate · Lunch ▾": which meal this logs to, one tap to change.
class _SectionPill extends StatelessWidget {
  const _SectionPill({required this.section, required this.onTap});
  final MealSection section;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Logs to ${section.displayName}. Change meal',
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        borderRadius: KRadius.pill,
        scale: 0.97,
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
          decoration: BoxDecoration(
            borderRadius: KRadius.pill,
            border: Border.all(color: KColor.fg.withValues(alpha: 0.16)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              KMealMark(section, size: 16),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  section.displayName,
                  style: KText.bodyMedium.copyWith(fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.expand_more_rounded, size: 18, color: KColor.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _MacroDot extends StatelessWidget {
  const _MacroDot({required this.label, required this.grams, required this.color, this.strong = false});
  final String label;
  final double grams;
  final Color color;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(
          '${grams.round()} g',
          style: KText.numSmall.copyWith(fontSize: 14, color: strong ? KColor.textPrimary : KColor.textSecondary),
        ),
        const SizedBox(width: 4),
        Text(label.toLowerCase(), style: KText.caption.copyWith(color: KColor.textMuted)),
      ],
    );
  }
}

class _FoodRow extends StatelessWidget {
  const _FoodRow({
    required this.name,
    required this.amount,
    required this.kcal,
    required this.protein,
    required this.check,
  });

  final String name;
  final String amount;
  final int kcal;
  final double protein;
  final bool check;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$name, $amount, $kcal kilocalories, ${protein.round()} grams protein'
          '${check ? '. Kyno is less sure about this one' : ''}',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: KColor.hairline))),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: Text(name, style: KText.bodyMedium.copyWith(fontSize: 15))),
                      if (check) ...[
                        const SizedBox(width: 6),
                        Container(width: 6, height: 6, decoration: BoxDecoration(color: KColor.ember, shape: BoxShape.circle)),
                      ],
                    ],
                  ),
                  Text(
                    '$amount · ${protein.round()} g protein',
                    style: KText.caption.copyWith(color: KColor.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: KSpacing.md),
            Text('${thousands(kcal)} kcal', style: KText.numSmall.copyWith(fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

class _FailedPanel extends StatelessWidget {
  const _FailedPanel({
    required this.failure,
    required this.onRetake,
    required this.onTryAgain,
    required this.onNote,
    required this.onDescribe,
  });

  final MealPhotoException failure;
  final VoidCallback onRetake;
  final VoidCallback onTryAgain;
  final VoidCallback onNote;
  final VoidCallback? onDescribe;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final offline = failure.kind == MealPhotoFailure.offline;
    final unreadable = failure.kind == MealPhotoFailure.unreadable;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: BoxDecoration(
          color: KColor.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(KSpacing.p, KSpacing.xl, KSpacing.p, KSpacing.lg + bottom),
        child: Semantics(
          liveRegion: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                switch (failure.kind) {
                  MealPhotoFailure.notFood => 'No food in that one',
                  MealPhotoFailure.rateLimited => 'Photo limit reached',
                  MealPhotoFailure.offline => "Couldn't reach Kyno",
                  MealPhotoFailure.teenMode => 'Waiting on a parent',
                  _ => "Couldn't read that plate",
                },
                style: KText.h2,
              ),
              const SizedBox(height: KSpacing.xs),
              Text(failure.userMessage, style: KText.body.copyWith(color: KColor.textSecondary)),
              const SizedBox(height: KSpacing.lg),
              if (offline)
                KButton(label: 'Try again', onTap: onTryAgain)
              else if (failure.retakeHelps)
                KButton(label: 'Retake', onTap: onRetake),
              if (onDescribe != null) ...[
                const SizedBox(height: KSpacing.sm),
                KButton(
                  label: 'Describe it instead',
                  outlined: offline || failure.retakeHelps,
                  onTap: onDescribe,
                ),
              ],
              if (unreadable) ...[
                const SizedBox(height: KSpacing.xs),
                Center(child: KTextAction('Add a note for Kyno', onTap: onNote)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NoCamera extends StatelessWidget {
  const _NoCamera({
    required this.denied,
    required this.onOpenSettings,
    required this.onGallery,
    required this.onDescribe,
    required this.fill,
  });

  final bool denied;
  final VoidCallback onOpenSettings;
  final VoidCallback onGallery;
  final VoidCallback onDescribe;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final p = _Cam.p;
    return ColoredBox(
      color: p.bg,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(KSpacing.p, 96, KSpacing.p, KSpacing.p),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: p.cardHigh,
                    shape: BoxShape.circle,
                    border: Border.all(color: p.border),
                  ),
                  child: Icon(
                    denied ? Icons.no_photography_outlined : Icons.photo_camera_outlined,
                    color: p.textSecondary,
                    size: 28,
                  ),
                ),
                const SizedBox(height: KSpacing.lg),
                Text(
                  denied ? "Camera's off for Kynetix" : "Couldn't start the camera",
                  style: KText.h2.copyWith(color: p.textPrimary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: KSpacing.sm),
                Text(
                  denied
                      ? 'Allow camera access in Settings to snap meals. Or pick a photo you already took.'
                      : 'You can pick a photo you already took instead.',
                  style: KText.body.copyWith(color: p.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: KSpacing.xl),
                if (denied) ...[
                  _CamButton(label: 'Open settings', icon: Icons.settings_outlined, filled: true, onTap: onOpenSettings),
                  const SizedBox(height: KSpacing.md),
                ],
                _CamButton(
                  label: 'Pick from gallery',
                  icon: Icons.photo_library_outlined,
                  filled: !denied,
                  onTap: onGallery,
                ),
                if (!fill) ...[
                  const SizedBox(height: KSpacing.md),
                  _CamButton(label: 'Describe it instead', icon: Icons.edit_note_outlined, onTap: onDescribe),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A full-width pill for the camera surface, fixed to the dark palette.
class _CamButton extends StatelessWidget {
  const _CamButton({required this.label, required this.icon, required this.onTap, this.filled = false});
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final p = _Cam.p;
    final fg = filled ? p.onInk : p.textPrimary;
    return Pressable(
      onTap: onTap == null
          ? null
          : () {
              KHaptics.commit();
              onTap!();
            },
      semanticLabel: label,
      borderRadius: KRadius.pill,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        decoration: BoxDecoration(
          color: filled ? p.ink : p.fg.withValues(alpha: 0.08),
          borderRadius: KRadius.pill,
          border: filled ? null : Border.all(color: p.fg.withValues(alpha: 0.28), width: 1.2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 19, color: fg),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: KText.family,
                  color: fg,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Add a note for Kyno": facts about the plate the photo can't show.
class _NoteSheet extends StatefulWidget {
  const _NoteSheet({this.initial});
  final String? initial;

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  late final TextEditingController _c = TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const KSheetHeader(
              'Add a note for Kyno',
              subtitle: "Anything the photo can't show. Kyno reads the plate again with it.",
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(KSpacing.p, KSpacing.md, KSpacing.p, 0),
              child: TextField(
                controller: _c,
                autofocus: true,
                maxLength: MealPhotoService.maxNote,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                style: KText.body.copyWith(fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'e.g. mutton, not chicken. I ate half the rice.',
                  hintStyle: KText.body.copyWith(color: KColor.textDisabled),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(KSpacing.p, KSpacing.sm, KSpacing.p, KSpacing.lg),
              child: KButton(
                label: 'Read again',
                onTap: () => Navigator.of(context).pop(_c.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
