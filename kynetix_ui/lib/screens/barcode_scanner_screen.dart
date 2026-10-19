import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../config/app_theme.dart';
import '../ui/k_toast.dart';
import '../models/barcode_product.dart';
import '../models/day_log.dart';
import '../models/nutrition_result.dart';
import '../services/barcode_app_settings.dart';
import '../services/barcode_food_service.dart';
import '../services/barcode_label_reader.dart';
import '../services/barcode_meal_logger.dart';
import '../services/barcode_user_products.dart';
import '../widgets/barcode_product_form.dart';
import '../widgets/barcode_product_sheet.dart';
import '../widgets/barcode_scan_sheet.dart';
import '../widgets/barcode_viewfinder.dart';
import 'add_meal_screen.dart';
import 'day_detail_screen.dart';
import '../services/analytics_service.dart';

/// Where the scan flow was opened from.
/// - [log]: dashboard dock and day screen. The product sheet logs directly.
/// - [fill]: the meal editor. The product sheet returns a portion for its rows.
enum BarcodeFlowMode { log, fill }

/// What a finished scan flow did.
class BarcodeFlowOutcome {
  final BarcodeSheetAction action;
  final BarcodeProduct product;
  final double grams;
  final MealSection section;
  final NutritionResult result;

  /// The logged entry: set for a direct log, and for "Edit before logging"
  /// when the editor saved.
  final MealEntry? entry;

  const BarcodeFlowOutcome({
    required this.action,
    required this.product,
    required this.grams,
    required this.section,
    required this.result,
    this.entry,
  });

  BarcodeFlowOutcome withEntry(MealEntry? e) => BarcodeFlowOutcome(
    action: action,
    product: product,
    grams: grams,
    section: section,
    result: result,
    entry: e,
  );
}

/// Opens the scanner and runs the whole flow: scan or type a code, look it
/// up, fall back to reading the label or typing it in, pick an amount, log.
///
/// [section] defaults to the time-of-day section for [date]. Shows the
/// success toast and fires the success haptic itself, so callers only need
/// to refresh when the returned outcome carries an entry.
Future<BarcodeFlowOutcome?> openBarcodeFlow(
  BuildContext context, {
  required DateTime date,
  MealSection? section,
  BarcodeFlowMode mode = BarcodeFlowMode.log,
}) async {
  final toaster = KToaster.of(context);
  final navigator = Navigator.of(context);
  final accessible = MediaQuery.maybeAccessibleNavigationOf(context) ?? false;
  final sec =
      section ?? DayDetailScreen.getSectionForTimeAndDate(DateTime.now(), date);

  final outcome = await navigator.push<BarcodeFlowOutcome>(
    kFadeThroughRoute<BarcodeFlowOutcome>(
      builder: (_) =>
          BarcodeScannerScreen(date: date, section: sec, mode: mode),
    ),
  );
  if (outcome == null) return null;

  void toast(String message) {
    toaster.show(
      message,
      kind: KToastKind.success,
      duration: Duration(seconds: accessible ? 8 : 3),
    );
  }

  switch (outcome.action) {
    case BarcodeSheetAction.logged:
      KHaptics.success();
      toast(
        BarcodeMealLogger.toastFor(
          outcome.product,
          outcome.grams,
          outcome.section,
        ),
      );
      return outcome;
    case BarcodeSheetAction.edit:
      final saved = await navigator.push<dynamic>(
        kRiseRoute<dynamic>(
          builder: (_) => AddMealScreen(
            section: outcome.section,
            date: date,
            initialResult: outcome.result,
          ),
        ),
      );
      if (saved is MealEntry) {
        KHaptics.success();
        toast('Meal logged to ${saved.section.displayName}.');
        return outcome.withEntry(saved);
      }
      return outcome;
    case BarcodeSheetAction.fill:
      return outcome;
  }
}

/// Full-screen scanner. The camera sits under a page-coloured sheet with a
/// barcode-shaped window; everything else (lookup, product sheet, fallbacks)
/// is layered on top as sheets so the camera only runs while it is useful.
class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({
    super.key,
    required this.date,
    required this.section,
    this.mode = BarcodeFlowMode.log,
  });

  final DateTime date;
  final MealSection section;
  final BarcodeFlowMode mode;

  /// Tests have no camera plugin; they drive the "Type the code" path.
  @visibleForTesting
  static bool debugCameraEnabled = true;

  /// Tests replace the photo picker for the "Read the label" path.
  @visibleForTesting
  static Future<Uint8List?> Function()? debugPickLabelPhoto;

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  MobileScannerController? _camera;

  /// True from a detection (or typed code) until the flow returns to the
  /// camera. Set synchronously so a second frame can't start a second lookup.
  bool _busy = false;

  /// The code being looked up, for the status pill.
  String? _lookingUp;

  /// Debounce: the same code is ignored for a moment after the camera comes
  /// back, so a pack still in frame doesn't re-open its sheet.
  String? _lastCode;
  DateTime _lastCodeAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const _repeatWindow = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    if (BarcodeScannerScreen.debugCameraEnabled) {
      _camera = MobileScannerController(
        formats: const [
          BarcodeFormat.ean13,
          BarcodeFormat.ean8,
          BarcodeFormat.upcA,
          BarcodeFormat.upcE,
        ],
        detectionSpeed: DetectionSpeed.normal,
        detectionTimeoutMs: 300,
      );
    }
  }

  @override
  void dispose() {
    unawaited(_camera?.dispose());
    super.dispose();
  }

  // ── Camera ────────────────────────────────────────────────────────────────

  void _onDetect(BarcodeCapture capture) {
    if (_busy || !mounted) return;
    for (final b in capture.barcodes) {
      final code = b.rawValue?.trim();
      if (!BarcodeFoodService.isBarcode(code)) continue;
      final now = DateTime.now();
      if (code == _lastCode && now.difference(_lastCodeAt) < _repeatWindow) {
        return;
      }
      _busy = true;
      _lastCode = code;
      _lastCodeAt = now;
      KHaptics.select();
      unawaited(_handleCode(code!));
      return;
    }
  }

  Future<void> _pauseCamera() async {
    try {
      await _camera?.pause();
    } catch (_) {}
  }

  Future<void> _stopCamera() async {
    try {
      await _camera?.stop();
    } catch (_) {}
  }

  Future<void> _resume() async {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _lookingUp = null;
    });
    _lastCodeAt = DateTime.now();
    try {
      await _camera?.start();
    } catch (_) {}
  }

  // ── Flow ──────────────────────────────────────────────────────────────────

  Future<void> _typeCode() async {
    if (_busy) return;
    setState(() => _busy = true);
    await _pauseCamera();
    if (!mounted) return;
    final code = await showBarcodeCodeSheet(context);
    if (!mounted) return;
    if (code == null) {
      await _resume();
      return;
    }
    _lastCode = code;
    await _handleCode(code);
  }

  Future<void> _handleCode(String code) async {
    setState(() => _lookingUp = code);
    await _pauseCamera();
    final res = await BarcodeFoodService.instance.lookup(code);
    AnalyticsService.instance.track('barcode_scanned', {'found': res.isFound});
    if (!mounted) return;
    setState(() => _lookingUp = null);

    if (res.isFound) {
      await _showProduct(res.product!);
    } else {
      await _showFallback(code, res);
    }
  }

  Future<void> _showProduct(BarcodeProduct product) async {
    final r = await showBarcodeProductSheet(
      context,
      product: product,
      date: widget.date,
      section: widget.section,
      mode: widget.mode == BarcodeFlowMode.fill
          ? BarcodeSheetMode.fill
          : BarcodeSheetMode.log,
    );
    if (!mounted) return;
    if (r == null) {
      await _resume();
      return;
    }
    Navigator.of(context).pop(
      BarcodeFlowOutcome(
        action: r.action,
        product: product,
        grams: r.grams,
        section: r.section,
        result: r.result,
        entry: r.entry,
      ),
    );
  }

  Future<void> _showFallback(String code, BarcodeLookupResult res) async {
    final offline = res.status == BarcodeLookupStatus.networkError;
    final choice = await showKSheet<String>(
      context: context,
      builder: (_) => _FallbackSheet(code: code, offline: offline),
    );
    if (!mounted) return;
    switch (choice) {
      case 'retry':
        await _handleCode(code);
      case 'label':
        await _readLabel(code, res.partial);
      case 'manual':
        await _enterManually(code, res.partial);
      default:
        await _resume();
    }
  }

  Future<Uint8List?> _pickPhoto() async {
    final override = BarcodeScannerScreen.debugPickLabelPhoto;
    if (override != null) return override();
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        imageQuality: 80,
      );
      return file == null ? null : await file.readAsBytes();
    } catch (e) {
      debugPrint('[Barcode] label photo failed: $e');
      return null;
    }
  }

  Future<void> _readLabel(String code, BarcodePartial? partial) async {
    // The photo picker needs the camera this screen is holding.
    await _stopCamera();
    final bytes = await _pickPhoto();
    if (!mounted) return;
    if (bytes == null) {
      await _resume();
      return;
    }
    final product = await showBarcodeProductForm(
      context,
      barcode: code,
      mode: BarcodeFormMode.labelPhoto,
      partial: partial,
      reading: BarcodeLabelReader.instance.read(bytes),
    );
    await _saveAndShow(product);
  }

  Future<void> _enterManually(String code, BarcodePartial? partial) async {
    final product = await showBarcodeProductForm(
      context,
      barcode: code,
      mode: BarcodeFormMode.manual,
      partial: partial,
    );
    await _saveAndShow(product);
  }

  Future<void> _saveAndShow(BarcodeProduct? product) async {
    if (!mounted) return;
    if (product == null) {
      await _resume();
      return;
    }
    try {
      await BarcodeUserProducts.instance.save(product);
    } catch (e) {
      // Still usable for this log; it just won't be instant next time.
      debugPrint('[Barcode] could not save user product: $e');
    }
    if (!mounted) return;
    await _showProduct(product);
  }

  Future<void> _openSettings() async {
    final toaster = KToaster.of(context);
    final ok = await BarcodeAppSettings.open();
    if (!ok && mounted) {
      toaster.show(BarcodeAppSettings.manualPath);
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Camera UI is dark in both themes: a bright paper scrim over a live feed
    // washes the picture out and glares. Light status-bar icons to match.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
      backgroundColor: _Cam.p.bg,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final window = BarcodeViewfinder.windowFor(size);
          final camera = _camera;
          if (camera == null) return _stack(context, window, null, false);
          return ValueListenableBuilder<MobileScannerState>(
            valueListenable: camera,
            builder: (context, state, _) =>
                _stack(context, window, camera, state.error != null),
          );
        },
      ),
      ),
    );
  }

  Widget _stack(
    BuildContext context,
    Rect window,
    MobileScannerController? camera,
    bool cameraFailed,
  ) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (camera != null)
          MobileScanner(
            controller: camera,
            onDetect: _onDetect,
            scanWindow: window,
            useAppLifecycleState: !_busy,
            errorBuilder: (context, error) => _CameraError(
              error: error,
              onOpenSettings: _openSettings,
              onTypeCode: _typeCode,
            ),
            placeholderBuilder: (_) => ColoredBox(color: _Cam.p.bg),
          )
        else
          ColoredBox(color: _Cam.p.card),
        // The frame and its controls step aside when the camera is
        // refused or broken: the error state carries its own actions.
        if (!cameraFailed) ...[
          BarcodeViewfinder(window: window, scanning: !_busy),
          Positioned(
            left: KSpacing.p,
            right: KSpacing.p,
            top: window.bottom + KSpacing.lg,
            child: _StatusLine(lookingUp: _lookingUp),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  KSpacing.p,
                  0,
                  KSpacing.p,
                  KSpacing.lg,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Barcode crumpled or won\'t scan?',
                      style: KText.caption.copyWith(fontSize: 13.5, color: _Cam.p.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: KSpacing.sm),
                    _CamButton(
                      label: 'Type the code',
                      icon: Icons.keyboard_alt_outlined,
                      onTap: _lookingUp == null ? _typeCode : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        _TopBar(section: widget.section, camera: camera, mode: widget.mode),
      ],
    );
  }
}

// ─── Pieces ───────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.section,
    required this.camera,
    required this.mode,
  });

  final MealSection section;
  final MobileScannerController? camera;
  final BarcodeFlowMode mode;

  @override
  Widget build(BuildContext context) {
    final cam = camera;
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            KSpacing.md,
            KSpacing.sm,
            KSpacing.md,
            0,
          ),
          child: Row(
            children: [
              _RoundButton(
                icon: Icons.close_rounded,
                tooltip: 'Close',
                onTap: () => Navigator.of(context).maybePop(),
              ),
              const SizedBox(width: KSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text('Scan a barcode', style: KText.h2.copyWith(color: _Cam.p.textPrimary)),
                    ),
                    Text(
                      mode == BarcodeFlowMode.fill
                          ? 'Adds to the meal you\'re editing'
                          : 'For ${section.displayName}',
                      style: KText.caption.copyWith(fontSize: 13.5, color: _Cam.p.textSecondary),
                    ),
                  ],
                ),
              ),
              if (cam != null)
                ValueListenableBuilder<MobileScannerState>(
                  valueListenable: cam,
                  builder: (context, state, _) {
                    final torch = state.torchState;
                    final cams = state.availableCameras;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (state.isRunning && torch != TorchState.unavailable)
                          _RoundButton(
                            icon: torch == TorchState.on
                                ? Icons.flash_on_rounded
                                : Icons.flash_off_rounded,
                            tooltip: torch == TorchState.on
                                ? 'Torch off'
                                : 'Torch on',
                            selected: torch == TorchState.on,
                            onTap: () {
                              KHaptics.select();
                              unawaited(cam.toggleTorch());
                            },
                          ),
                        if (state.isRunning && (cams == null || cams > 1)) ...[
                          const SizedBox(width: KSpacing.sm),
                          _RoundButton(
                            icon: Icons.cameraswitch_outlined,
                            tooltip: 'Switch camera',
                            onTap: () {
                              KHaptics.select();
                              unawaited(cam.switchCamera());
                            },
                          ),
                        ],
                      ],
                    );
                  },
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
  final VoidCallback onTap;
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
        backgroundColor: selected ? p.ink : p.fg.withValues(alpha: 0.12),
        side: BorderSide(color: selected ? p.ink : p.fg.withValues(alpha: 0.18)),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.lookingUp});
  final String? lookingUp;

  @override
  Widget build(BuildContext context) {
    final busy = lookingUp != null;
    return Semantics(
      liveRegion: true,
      child: AnimatedSwitcher(
        duration: KMotion.of(context, KMotion.quick),
        child: busy
            ? Row(
                key: const ValueKey('busy'),
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  KSpinner(size: 16, color: _Cam.p.textPrimary),
                  const SizedBox(width: KSpacing.sm),
                  Flexible(
                    child: Text(
                      'Looking up $lookingUp…',
                      style: KText.bodyMedium.copyWith(color: _Cam.p.textPrimary),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              )
            : Text(
                'Line up the barcode inside the frame.',
                key: const ValueKey('idle'),
                style: KText.bodyMedium.copyWith(color: _Cam.p.textPrimary.withValues(alpha: 0.86)),
                textAlign: TextAlign.center,
              ),
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({
    required this.error,
    required this.onOpenSettings,
    required this.onTypeCode,
  });

  final MobileScannerException error;
  final VoidCallback onOpenSettings;
  final VoidCallback onTypeCode;

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    final p = _Cam.p;
    return ColoredBox(
      color: p.bg,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              KSpacing.p,
              96,
              KSpacing.p,
              KSpacing.p,
            ),
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
                    denied
                        ? Icons.no_photography_outlined
                        : Icons.videocam_off_outlined,
                    color: p.textSecondary,
                    size: 28,
                  ),
                ),
                const SizedBox(height: KSpacing.lg),
                Text(
                  denied
                      ? "Camera's off for Kynetix"
                      : "Couldn't start the camera",
                  style: KText.h2.copyWith(color: p.textPrimary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: KSpacing.sm),
                Text(
                  denied
                      ? 'Allow camera access in Settings to scan barcodes. Or type the digits under the barcode instead.'
                      : 'You can type the digits under the barcode instead.',
                  style: KText.body.copyWith(color: p.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: KSpacing.xl),
                if (denied) ...[
                  _CamButton(
                    label: 'Open settings',
                    icon: Icons.settings_outlined,
                    filled: true,
                    onTap: onOpenSettings,
                  ),
                  const SizedBox(height: KSpacing.md),
                ],
                _CamButton(
                  label: 'Type the code',
                  icon: Icons.keyboard_alt_outlined,
                  filled: !denied,
                  onTap: onTypeCode,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown when the code isn't in Open Food Facts, has no usable nutrition, or
/// the lookup couldn't reach the network.
class _FallbackSheet extends StatelessWidget {
  const _FallbackSheet({required this.code, required this.offline});

  final String code;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: KSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KSheetHeader(
              offline
                  ? "Couldn't reach the product database"
                  : "We don't have that product yet",
              subtitle: offline
                  ? 'Check your connection and try again. Or add it from the label.'
                  : 'Barcode $code. Add it from the label once and every scan after is instant.',
            ),
            const SizedBox(height: KSpacing.lg),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: KSpacing.p),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (offline) ...[
                    KOptionRow(
                      icon: Icons.refresh,
                      title: 'Try again',
                      subtitle: 'Look up $code again.',
                      onTap: () => Navigator.pop(context, 'retry'),
                    ),
                    const KHairline(indent: 40),
                  ],
                  KOptionRow(
                    icon: Icons.document_scanner_outlined,
                    title: 'Read the label',
                    subtitle:
                        'Snap the nutrition table. Kyno fills it in, you check it.',
                    onTap: () => Navigator.pop(context, 'label'),
                  ),
                  const KHairline(indent: 40),
                  KOptionRow(
                    icon: Icons.edit_note_outlined,
                    title: 'Enter it yourself',
                    subtitle: 'Name, pack size and the per 100 g numbers.',
                    onTap: () => Navigator.pop(context, 'manual'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: KSpacing.sm),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  foregroundColor: KColor.textSecondary,
                  minimumSize: const Size(48, 48),
                ),
                child: const Text('Scan something else'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The camera surface always uses the Carbon palette, whatever the app theme.
abstract final class _Cam {
  static KPalette get p => KPalette.dark;
}

/// A full-width pill for the camera surface: warm-white ink when [filled],
/// a light outline otherwise. Fixed to Carbon colours (see [_Cam]).
class _CamButton extends StatelessWidget {
  const _CamButton({required this.label, required this.icon, required this.onTap, this.filled = false});
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final p = _Cam.p;
    final enabled = onTap != null;
    final fg = filled ? p.onInk : p.textPrimary;
    return Pressable(
      onTap: enabled
          ? () {
              KHaptics.commit();
              onTap!();
            }
          : null,
      semanticLabel: label,
      borderRadius: KRadius.pill,
      child: AnimatedOpacity(
        duration: KMotion.of(context, KMotion.quick),
        opacity: enabled ? 1 : 0.45,
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
      ),
    );
  }
}
