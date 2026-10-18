import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_theme.dart';
import '../models/barcode_product.dart';
import '../services/barcode_food_service.dart' show BarcodePartial;
import '../services/barcode_label_reader.dart';

/// How the form was reached: Kyno read a label photo (values pre-filled and
/// to be checked), or the person types everything.
enum BarcodeFormMode { labelPhoto, manual }

/// Opens the confirmation form and returns the confirmed product, or null.
///
/// In [BarcodeFormMode.labelPhoto] pass [reading]: the form shows a loading
/// state until it resolves, then pre-fills every field. Nothing is saved or
/// logged until the person taps "Save product".
Future<BarcodeProduct?> showBarcodeProductForm(
  BuildContext context, {
  required String barcode,
  required BarcodeFormMode mode,
  BarcodePartial? partial,
  Future<LabelReading>? reading,
}) {
  return showKSheet<BarcodeProduct>(
    context: context,
    builder: (_) => BarcodeProductForm(
      barcode: barcode,
      mode: mode,
      partial: partial,
      reading: reading,
    ),
  );
}

class BarcodeProductForm extends StatefulWidget {
  const BarcodeProductForm({
    super.key,
    required this.barcode,
    required this.mode,
    this.partial,
    this.reading,
  });

  final String barcode;
  final BarcodeFormMode mode;
  final BarcodePartial? partial;
  final Future<LabelReading>? reading;

  @override
  State<BarcodeProductForm> createState() => _BarcodeProductFormState();
}

class _BarcodeProductFormState extends State<BarcodeProductForm> {
  final _name = TextEditingController();
  final _net = TextEditingController();
  final _kcal = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();
  final _fibre = TextEditingController();
  final _sugar = TextEditingController();

  String _unit = 'g';
  bool _reading = false;
  String? _readError;
  String? _error;
  double? _servingSize;

  bool get _isLabel => widget.mode == BarcodeFormMode.labelPhoto;

  List<TextEditingController> get _all =>
      [_name, _net, _kcal, _protein, _carbs, _fat, _fibre, _sugar];

  @override
  void initState() {
    super.initState();
    final p = widget.partial;
    if (p != null) {
      if (p.name != null) _name.text = p.name!;
      if (p.netQuantity != null) _net.text = _fmt(p.netQuantity!);
      _unit = p.unit;
    }
    final reading = widget.reading;
    if (reading != null) {
      _reading = true;
      unawaited(_await(reading));
    }
  }

  Future<void> _await(Future<LabelReading> reading) async {
    try {
      final r = await reading;
      if (!mounted) return;
      setState(() {
        _reading = false;
        if (r.productName != null && _name.text.trim().isEmpty) {
          _name.text = r.brand != null &&
                  !r.productName!.toLowerCase().contains(r.brand!.toLowerCase())
              ? '${r.brand} ${r.productName}'
              : r.productName!;
        }
        if (r.netQuantity != null) _net.text = _fmt(r.netQuantity!);
        _unit = r.unit;
        _servingSize = r.servingSize;
        _kcal.text = _fmt(r.calories);
        _protein.text = _fmt(r.proteinG);
        _carbs.text = _fmt(r.carbsG);
        _fat.text = _fmt(r.fatG);
        if (r.fiberG != null) _fibre.text = _fmt(r.fiberG!);
        if (r.sugarG != null) _sugar.text = _fmt(r.sugarG!);
      });
    } on LabelReadException catch (e) {
      if (!mounted) return;
      setState(() {
        _reading = false;
        _readError = e.userMessage;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _reading = false;
        _readError = const LabelReadException(LabelReadFailure.offline).userMessage;
      });
    }
  }

  @override
  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
    super.dispose();
  }

  static String _fmt(double v) {
    final r = double.parse(v.toStringAsFixed(1));
    return r == r.roundToDouble() ? r.round().toString() : r.toStringAsFixed(1);
  }

  static double? _parse(TextEditingController c) {
    final t = c.text.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    return v != null && v.isFinite && v >= 0 ? v : null;
  }

  /// Validates and builds the product, or sets [_error] and returns null.
  @visibleForTesting
  BarcodeProduct? buildProduct() {
    final name = _name.text.trim();
    final kcal = _parse(_kcal);
    final protein = _parse(_protein);
    final carbs = _parse(_carbs);
    final fat = _parse(_fat);
    final net = _parse(_net);
    final fibre = _parse(_fibre) ?? 0;
    final sugar = _parse(_sugar) ?? 0;

    String? error;
    if (name.isEmpty) {
      error = 'Give it a name so you can find it again.';
    } else if (kcal == null || protein == null || carbs == null || fat == null) {
      error = 'Fill in kcal, protein, carbs and fat per 100 $_unit.';
    } else if (kcal > 900) {
      error = 'That kcal is more than pure fat. Check the per 100 $_unit column.';
    } else if (protein > 100 || carbs > 100 || fat > 100 ||
        protein + carbs + fat > 105) {
      error = "Those grams add up to more than 100 $_unit. Check the per 100 $_unit column.";
    } else if (net != null && (net <= 0 || net > 100000)) {
      error = 'Check the pack size.';
    }
    if (error != null) {
      setState(() => _error = error);
      return null;
    }

    final per100 = BarcodeNutriments(
      calories: kcal!,
      proteinG: protein!,
      carbsG: carbs!,
      fatG: fat!,
      fiberG: fibre,
      sugarG: sugar,
    );
    return BarcodeProduct(
      barcode: widget.barcode,
      name: name.length > 80 ? name.substring(0, 80) : name,
      brand: widget.partial?.brand,
      per100g: per100,
      servings: const [BarcodeProduct.hundredGrams],
      netQuantity: net,
      unit: _unit,
      servingQuantity: _servingSize != null &&
              _servingSize! > 0 &&
              (net == null || _servingSize! <= net)
          ? _servingSize
          : null,
      imageUrl: widget.partial?.imageUrl,
      source: _isLabel ? BarcodeSource.labelPhoto : BarcodeSource.userEntered,
    );
  }

  void _save() {
    final product = buildProduct();
    if (product == null) {
      KHaptics.reject();
      return;
    }
    Navigator.of(context).pop(product);
  }

  /// A soft check, not a block: real labels round, so only a big mismatch
  /// between kcal and 4/4/9 is worth a second look.
  String? get _atwaterHint {
    final kcal = _parse(_kcal);
    final p = _parse(_protein), c = _parse(_carbs), f = _parse(_fat);
    if (kcal == null || p == null || c == null || f == null || kcal < 20) {
      return null;
    }
    final implied = 4 * p + 4 * c + 9 * f;
    if (implied <= 0) return null;
    return ((implied - kcal).abs() / kcal) > 0.25
        ? "The macros don't quite add up to the kcal. Worth a quick look."
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final title = _isLabel ? 'Check the numbers' : 'Enter it yourself';
    final subtitle = _isLabel
        ? "Kyno's read of your label. Fix anything that's off, then save."
        : 'Copy the per 100 $_unit column from the label.';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: KSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KSheetHeader(title, subtitle: subtitle),
              const SizedBox(height: KSpacing.md),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: KSpacing.p),
                child: AnimatedSwitcher(
                  duration: KMotion.of(context, KMotion.standard),
                  child: _reading
                      ? const _ReadingState(key: ValueKey('reading'))
                      : _buildFields(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFields() {
    final hint = _atwaterHint;
    return Column(
      key: const ValueKey('fields'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_readError != null) ...[
          _Notice(icon: Icons.info_outline_rounded, text: _readError!),
          const SizedBox(height: KSpacing.md),
        ],
        _Field(label: 'Name', controller: _name, text: true, hint: 'e.g. Parle-G Gluco'),
        const SizedBox(height: KSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: _Field(
                label: 'Net quantity',
                controller: _net,
                hint: 'Optional',
                suffix: _unit,
              ),
            ),
            const SizedBox(width: KSpacing.md),
            _UnitToggle(
              unit: _unit,
              onChanged: (u) => setState(() => _unit = u),
            ),
          ],
        ),
        const SizedBox(height: KSpacing.lg),
        Text('Per 100 $_unit', style: KText.h3.copyWith(color: KColor.textSecondary)),
        const SizedBox(height: KSpacing.sm),
        Row(
          children: [
            Expanded(child: _Field(label: 'kcal', controller: _kcal, accent: KColor.ember, onChanged: _rebuild)),
            const SizedBox(width: KSpacing.md),
            Expanded(child: _Field(label: 'Protein', controller: _protein, suffix: 'g', accent: KColor.protein, onChanged: _rebuild)),
          ],
        ),
        const SizedBox(height: KSpacing.md),
        Row(
          children: [
            Expanded(child: _Field(label: 'Carbs', controller: _carbs, suffix: 'g', accent: KColor.carbs, onChanged: _rebuild)),
            const SizedBox(width: KSpacing.md),
            Expanded(child: _Field(label: 'Fat', controller: _fat, suffix: 'g', accent: KColor.fat, onChanged: _rebuild)),
          ],
        ),
        if (_isLabel) ...[
          const SizedBox(height: KSpacing.md),
          Row(
            children: [
              Expanded(child: _Field(label: 'Fibre', controller: _fibre, suffix: 'g', accent: KColor.fiber, hint: 'Optional')),
              const SizedBox(width: KSpacing.md),
              Expanded(child: _Field(label: 'Sugar', controller: _sugar, suffix: 'g', hint: 'Optional')),
            ],
          ),
        ],
        if (hint != null) ...[
          const SizedBox(height: KSpacing.md),
          _Notice(icon: Icons.tips_and_updates_outlined, text: hint),
        ],
        if (_error != null) ...[
          const SizedBox(height: KSpacing.md),
          Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              style: KText.caption.copyWith(color: KColor.danger, fontSize: 13),
            ),
          ),
        ],
        const SizedBox(height: KSpacing.lg),
        KButton(label: 'Save product', icon: Icons.check_rounded, onTap: _save),
        const SizedBox(height: KSpacing.sm),
        Text(
          'Saved on this phone for your account, so the next scan is instant.',
          textAlign: TextAlign.center,
          style: KText.caption,
        ),
      ],
    );
  }

  void _rebuild(String _) => setState(() {});
}

class _ReadingState extends StatelessWidget {
  const _ReadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: 'Reading the label',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: KSpacing.xl),
        child: Column(
          children: [
            KSpinner(size: 28, color: KColor.ink),
            const SizedBox(height: KSpacing.md),
            Text('Reading the label…', style: KText.bodyMedium),
            const SizedBox(height: 4),
            Text(
              "You'll check every number before it's saved.",
              style: KText.caption,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: KSpacing.lg),
            const KShimmerBox(width: double.infinity, height: 52),
            const SizedBox(height: KSpacing.md),
            const KShimmerBox(width: double.infinity, height: 52),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(KSpacing.md),
      decoration: BoxDecoration(
        color: KColor.cardHigh,
        borderRadius: KRadius.sm,
        border: Border.all(color: KColor.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: KColor.textSecondary),
          const SizedBox(width: KSpacing.sm),
          Expanded(
            child: Text(text, style: KText.caption.copyWith(fontSize: 13, color: KColor.textSecondary)),
          ),
        ],
      ),
    );
  }
}

class _UnitToggle extends StatelessWidget {
  const _UnitToggle({required this.unit, required this.onChanged});
  final String unit;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(String u) {
      final selected = unit == u;
      return Semantics(
        button: true,
        selected: selected,
        label: u == 'g' ? 'Grams' : 'Millilitres',
        excludeSemantics: true,
        child: InkWell(
          borderRadius: KRadius.pill,
          onTap: () {
            if (!selected) {
              KHaptics.select();
              onChanged(u);
            }
          },
          child: AnimatedContainer(
            duration: KMotion.of(context, KMotion.quick),
            constraints: const BoxConstraints(minWidth: 52, minHeight: 48),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? KColor.ink : Colors.transparent,
              borderRadius: KRadius.pill,
            ),
            child: Text(
              u,
              style: KText.bodyMedium.copyWith(
                color: selected ? KColor.onInk : KColor.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: KColor.card,
        borderRadius: KRadius.pill,
        border: Border.all(color: KColor.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [seg('g'), seg('ml')]),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.hint,
    this.suffix,
    this.text = false,
    Color? accent,
    this.onChanged,
  }) : _accent = accent;

  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? suffix;
  final bool text;
  final Color? _accent;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final accent = _accent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (accent != null) ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(label, style: KText.caption.copyWith(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          onChanged: onChanged,
          keyboardType: text
              ? TextInputType.text
              : const TextInputType.numberWithOptions(decimal: true),
          textCapitalization: text ? TextCapitalization.words : TextCapitalization.none,
          inputFormatters: text
              ? [LengthLimitingTextInputFormatter(80)]
              : [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  LengthLimitingTextInputFormatter(7),
                ],
          style: (text ? KText.body : KText.numSmall).copyWith(fontSize: 16),
          cursorColor: KColor.ink,
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: KText.body.copyWith(color: KColor.textDisabled),
            suffixText: suffix,
            suffixStyle: KText.caption,
            filled: true,
            fillColor: KColor.card,
            constraints: const BoxConstraints(minHeight: 48),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            enabledBorder: OutlineInputBorder(
              borderRadius: KRadius.sm,
              borderSide: BorderSide(color: KColor.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: KRadius.sm,
              borderSide: BorderSide(color: KColor.ink, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
