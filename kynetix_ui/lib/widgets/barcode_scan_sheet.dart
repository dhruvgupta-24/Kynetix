import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_theme.dart';
import '../services/barcode_food_service.dart';

/// "Type the code": the digits printed under the barcode, for a crumpled
/// wrapper, a glare-y pack, or no camera. Lands on exactly the same lookup as
/// a scan. Returns the code, or null if dismissed.
Future<String?> showBarcodeCodeSheet(BuildContext context) {
  return showKSheet<String>(
    context: context,
    builder: (_) => const BarcodeCodeSheet(),
  );
}

class BarcodeCodeSheet extends StatefulWidget {
  const BarcodeCodeSheet({super.key});

  @override
  State<BarcodeCodeSheet> createState() => _BarcodeCodeSheetState();
}

class _BarcodeCodeSheetState extends State<BarcodeCodeSheet> {
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _ctrl.removeListener(_onChanged);
    _ctrl.dispose();
    super.dispose();
  }

  bool get _valid => BarcodeFoodService.isBarcode(_ctrl.text);

  void _submit() {
    if (!_valid) return;
    Navigator.of(context).pop(_ctrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final digits = _ctrl.text.trim().length;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: KSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const KSheetHeader(
                'Type the code',
                subtitle: 'The digits under the barcode. Indian packs usually start with 890.',
              ),
              const SizedBox(height: KSpacing.lg),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: KSpacing.p),
                child: TextField(
                  controller: _ctrl,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.search,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(14),
                  ],
                  onSubmitted: (_) => _submit(),
                  style: KText.numMedium.copyWith(letterSpacing: 1.0),
                  cursorColor: KColor.ink,
                  decoration: InputDecoration(
                    hintText: '8901491101837',
                    hintStyle: KText.numMedium.copyWith(
                      color: KColor.textDisabled,
                      letterSpacing: 1.0,
                    ),
                    prefixIcon: Icon(Icons.qr_code_2_rounded, color: KColor.textMuted),
                    suffixText: digits == 0 ? null : '$digits digits',
                    suffixStyle: KText.caption,
                    filled: true,
                    fillColor: KColor.card,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: KSpacing.lg,
                      vertical: KSpacing.lg,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: KRadius.md,
                      borderSide: BorderSide(color: KColor.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: KRadius.md,
                      borderSide: BorderSide(color: KColor.ink, width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: KSpacing.lg),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: KSpacing.p),
                child: KButton(
                  label: 'Find',
                  icon: Icons.search_rounded,
                  onTap: _valid ? _submit : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
