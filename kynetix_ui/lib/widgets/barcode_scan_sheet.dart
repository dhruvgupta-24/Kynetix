import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../config/app_theme.dart';
import '../models/barcode_product.dart';
import '../models/nutrition_result.dart';
import '../services/barcode_food_service.dart';

/// Scan a packaged product and confirm how much of it was eaten.
///
/// Returns a [NutritionResult] built from the pack label, or null if dismissed.
/// The caller is expected to hand that straight to the ordinary edit screen —
/// the numbers here are exact, but the person still gets the last word.
Future<NutritionResult?> showBarcodeScanSheet(BuildContext context) {
  return showModalBottomSheet<NutritionResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: const Color(0xFF0C0C14),
    barrierColor: Colors.black.withValues(alpha: 0.75),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const BarcodeScanSheet(),
  );
}

class BarcodeScanSheet extends StatefulWidget {
  const BarcodeScanSheet({super.key});

  @override
  State<BarcodeScanSheet> createState() => _BarcodeScanSheetState();
}

class _BarcodeScanSheetState extends State<BarcodeScanSheet> {
  final _manualCtrl = TextEditingController();

  MobileScannerController? _scanner;
  BarcodeProduct? _product;
  int    _servingIdx = 0;
  double _quantity   = 1;
  bool   _loading    = false;
  String? _error;

  /// Guards against the detector firing the same code on consecutive frames.
  String _lastLookedUp = '';

  /// Whether this session ever opened the camera, so "Scan another" resumes it
  /// for someone who was scanning without springing it on someone who typed
  /// the digits in and never asked for a camera at all.
  bool _cameraWasUsed = false;

  @override
  void dispose() {
    _manualCtrl.dispose();
    _scanner?.dispose();
    super.dispose();
  }

  // ── Camera ────────────────────────────────────────────────────────────────

  void _startCamera() {
    setState(() {
      _error = null;
      _cameraWasUsed = true;
      _scanner = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
        formats: const [
          BarcodeFormat.ean13,
          BarcodeFormat.ean8,
          BarcodeFormat.upcA,
          BarcodeFormat.upcE,
          BarcodeFormat.code128,
        ],
      );
    });
  }

  Future<void> _stopCamera() async {
    final scanner = _scanner;
    if (scanner == null) return;
    setState(() => _scanner = null);
    await scanner.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue;
      if (BarcodeFoodService.isBarcode(code) && code != _lastLookedUp) {
        HapticFeedback.mediumImpact();
        _lookup(code!);
        return;
      }
    }
  }

  // ── Lookup ────────────────────────────────────────────────────────────────

  Future<void> _lookup(String code) async {
    if (_loading) return;
    // Set synchronously, before the first await: the detector can fire again
    // on the very next frame, and an async gap here lets two lookups through
    // the guard so the slower one overwrites the product from the faster.
    _loading = true;
    _lastLookedUp = code;

    setState(() => _error = null);
    await _stopCamera();
    if (!mounted) return;

    final res = await BarcodeFoodService.instance.lookup(code);
    if (!mounted) return;

    setState(() {
      _loading = false;
      switch (res.status) {
        case BarcodeLookupStatus.found:
          _product    = res.product;
          _servingIdx = 0;
          _quantity   = 1;
        case BarcodeLookupStatus.notFound:
          // Allow the same code to be retried after a miss.
          _lastLookedUp = '';
          _error = "We don't have that product yet. Try logging it by name "
              'instead.';
        case BarcodeLookupStatus.networkError:
          _lastLookedUp = '';
          _error = "Couldn't reach the product database. Check your "
              'connection and try again.';
        case BarcodeLookupStatus.invalidCode:
          _lastLookedUp = '';
          _error = "That doesn't look like a barcode.";
      }
    });
  }

  /// "Scan another" puts the camera straight back up for someone who was
  /// scanning — dropping them on the "Open camera" button makes a second item
  /// a two-tap job.
  void _reset() {
    setState(() {
      _product      = null;
      _error        = null;
      _lastLookedUp = '';
      _manualCtrl.clear();
    });
    if (_cameraWasUsed) _startCamera();
  }

  void _submit() {
    final product = _product;
    if (product == null) return;
    Navigator.of(context).pop(
      product.toNutritionResult(
        servingIdx: _servingIdx,
        quantity: _quantity,
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            const SizedBox(height: 18),
            if (_product != null) ..._review(_product!) else ..._scan(),
            if (_loading) ...[
              const SizedBox(height: 16),
              const Center(
                child: SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: KColor.green,
                  ),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              _errorBox(_error!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header() => Row(
        children: [
          Expanded(
            child: Text(
              _product == null ? 'Scan barcode' : 'Confirm portion',
              style: const TextStyle(
                color: KColor.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, color: KColor.textSecondary),
            tooltip: 'Close',
          ),
        ],
      );

  // ── Scan stage ────────────────────────────────────────────────────────────

  List<Widget> _scan() => [
        if (_scanner != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 220,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(
                    controller: _scanner,
                    onDetect: _onDetect,
                    errorBuilder: (_, error) => _cameraUnavailable(error),
                  ),
                  IgnorePointer(
                    child: Center(
                      child: Container(
                        height: 96,
                        margin: const EdgeInsets.symmetric(horizontal: 28),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.85),
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          FilledButton.icon(
            onPressed: _startCamera,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Open camera'),
            style: FilledButton.styleFrom(
              backgroundColor: KColor.green,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          _scanner != null
              ? 'Line the barcode up inside the box'
              : 'Point your camera at the barcode on the pack',
          textAlign: TextAlign.center,
          style: const TextStyle(color: KColor.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 20),
        const Text(
          'Or type the number under the barcode',
          style: TextStyle(color: KColor.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _manualCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(14),
                ],
                onChanged: (_) => setState(() {}),
                onSubmitted: (v) {
                  if (BarcodeFoodService.isBarcode(v)) _lookup(v);
                },
                style: const TextStyle(color: KColor.textPrimary),
                decoration: InputDecoration(
                  hintText: '8901491101837',
                  hintStyle: const TextStyle(color: KColor.textDisabled),
                  filled: true,
                  fillColor: KColor.surface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: KColor.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: KColor.border),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: BarcodeFoodService.isBarcode(_manualCtrl.text) && !_loading
                  ? () => _lookup(_manualCtrl.text)
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: KColor.green,
                foregroundColor: Colors.black,
                disabledBackgroundColor: KColor.cardHigh,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 18,
                ),
              ),
              child: const Text('Find'),
            ),
          ],
        ),
      ];

  Widget _cameraUnavailable(MobileScannerException error) => ColoredBox(
        color: KColor.surface,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              error.errorCode == MobileScannerErrorCode.permissionDenied
                  ? 'Camera access was blocked. Type the number under the '
                      'barcode instead.'
                  : "Couldn't start the camera. Type the number under the "
                      'barcode instead.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: KColor.textSecondary, fontSize: 13),
            ),
          ),
        ),
      );

  // ── Review stage ──────────────────────────────────────────────────────────

  List<Widget> _review(BarcodeProduct product) {
    final grams = product.gramsFor(_servingIdx, _quantity);
    final scale = grams / 100.0;
    double at(double per100) =>
        double.parse((per100 * scale).toStringAsFixed(1));

    return [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: KColor.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: KColor.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              product.name,
              style: const TextStyle(
                color: KColor.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'From the pack label · '
              '${product.per100g.calories.round()} kcal per 100 g',
              style: const TextStyle(color: KColor.textMuted, fontSize: 12),
            ),
          ],
        ),
      ),
      if (product.servings.length > 1) ...[
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < product.servings.length; i++)
              _servingChip(product.servings[i].label, i),
          ],
        ),
      ],
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: KColor.border),
        ),
        child: Row(
          children: [
            const Text(
              'How many?',
              style: TextStyle(color: KColor.textPrimary, fontSize: 14),
            ),
            const Spacer(),
            _stepButton(Icons.remove, () {
              setState(() => _quantity = (_quantity - 0.5).clamp(0.5, 20));
            }),
            SizedBox(
              width: 96,
              child: Text(
                '${_trim(_quantity)} × ${product.servings[_servingIdx].grams.round()} g',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: KColor.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _stepButton(Icons.add, () {
              setState(() => _quantity = (_quantity + 0.5).clamp(0.5, 20));
            }),
          ],
        ),
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          _macroTile('${at(product.per100g.calories).round()}', 'kcal',
              KColor.calorie),
          _macroTile('${_trim(at(product.per100g.proteinG))}g', 'protein',
              KColor.protein),
          _macroTile('${_trim(at(product.per100g.carbsG))}g', 'carbs',
              KColor.amber),
          _macroTile('${_trim(at(product.per100g.fatG))}g', 'fat', KColor.blue),
        ],
      ),
      const SizedBox(height: 18),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _reset,
              style: OutlinedButton.styleFrom(
                foregroundColor: KColor.textSecondary,
                side: const BorderSide(color: KColor.border),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Scan another'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                backgroundColor: KColor.green,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Review & add'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      const Text(
        'You can adjust these numbers on the next screen.',
        textAlign: TextAlign.center,
        style: TextStyle(color: KColor.textMuted, fontSize: 11),
      ),
    ];
  }

  Widget _servingChip(String label, int index) {
    final selected = index == _servingIdx;
    return GestureDetector(
      onTap: () => setState(() => _servingIdx = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? KColor.green : KColor.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? KColor.green : KColor.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : KColor.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _stepButton(IconData icon, VoidCallback onTap) => IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 18, color: KColor.textPrimary),
        style: IconButton.styleFrom(
          side: const BorderSide(color: KColor.border),
          shape: const CircleBorder(),
        ),
      );

  Widget _macroTile(String value, String label, Color color) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: KColor.border),
          ),
          child: Column(
            children: [
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(color: KColor.textMuted, fontSize: 10),
              ),
            ],
          ),
        ),
      );

  Widget _errorBox(String message) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: KColor.danger.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: KColor.danger.withValues(alpha: 0.4)),
        ),
        child: Text(
          message,
          style: const TextStyle(color: KColor.danger, fontSize: 13),
        ),
      );

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
}
