import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_theme.dart';
import '../models/barcode_product.dart';
import '../models/day_log.dart';
import '../models/nutrition_result.dart';
import '../services/barcode_meal_logger.dart';
import '../services/food_link_service.dart';
import 'k_success_check.dart';

/// What the product sheet is for.
/// - [log]: the primary button logs straight to the day ("Log 40 g to
///   Breakfast"); "Edit before logging" hands off to the editor.
/// - [fill]: opened from inside the meal editor; the primary button returns
///   the portion for the editor's rows ("Add 40 g to this meal").
enum BarcodeSheetMode { log, fill }

enum BarcodeSheetAction { logged, edit, fill }

class BarcodeSheetResult {
  final BarcodeSheetAction action;
  final double grams;
  final MealSection section;
  final NutritionResult result;

  /// Set when [action] is [BarcodeSheetAction.logged].
  final MealEntry? entry;

  const BarcodeSheetResult({
    required this.action,
    required this.grams,
    required this.section,
    required this.result,
    this.entry,
  });
}

Future<BarcodeSheetResult?> showBarcodeProductSheet(
  BuildContext context, {
  required BarcodeProduct product,
  required DateTime date,
  required MealSection section,
  BarcodeSheetMode mode = BarcodeSheetMode.log,
}) {
  return showKSheet<BarcodeSheetResult>(
    context: context,
    builder: (_) => BarcodeProductSheet(
      product: product,
      date: date,
      initialSection: section,
      mode: mode,
    ),
  );
}

class BarcodeProductSheet extends StatefulWidget {
  const BarcodeProductSheet({
    super.key,
    required this.product,
    required this.date,
    required this.initialSection,
    this.mode = BarcodeSheetMode.log,
  });

  final BarcodeProduct product;
  final DateTime date;
  final MealSection initialSection;
  final BarcodeSheetMode mode;

  @override
  State<BarcodeProductSheet> createState() => _BarcodeProductSheetState();
}

class _BarcodeProductSheetState extends State<BarcodeProductSheet> {
  late final List<BarcodeAmountOption> _options;
  late BarcodeAmountOption _selected;
  bool _custom = false;

  /// Multiplier on the selected chip (2 packs, 1.5 servings).
  double _count = 1;

  final _customCtrl = TextEditingController();
  late MealSection _section;
  bool _logging = false;

  /// Presentation only: the entry is already logged and the button shows its
  /// drawn check; the sheet closes with the same result when that ends.
  BarcodeSheetResult? _loggedResult;

  static const _countStep = 0.5;
  static const _countMax = 20.0;
  static const _customStep = 10.0;
  static const _customMax = 5000.0;

  BarcodeProduct get _p => widget.product;

  /// A personal food that looks like this pack, offered once for linking.
  FoodLinkCandidate? _linkOffer;

  /// Set once the person linked [_linkOffer] here, for the undo line.
  bool _linked = false;

  @override
  void initState() {
    super.initState();
    _linkOffer = FoodLinkService.instance.suggestionFor(_p);
    FoodLinkService.instance.refreshProduct(_p).ignore();
    _options = _p.amountOptions;
    final d = _p.defaultAmount;
    _selected = _options.firstWhere(
      (o) => o.kind == d.kind && o.grams == d.grams,
      orElse: () => _options.first,
    );
    _section = widget.initialSection;
    _customCtrl.text = _fmt(_selected.grams);
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  static String _fmt(double v) {
    final r = double.parse(v.toStringAsFixed(1));
    return r == r.roundToDouble() ? r.round().toString() : r.toStringAsFixed(1);
  }

  double get _grams {
    if (_custom) {
      final v = double.tryParse(_customCtrl.text.trim().replaceAll(',', '.'));
      if (v == null || !v.isFinite || v <= 0) return 0;
      return v.clamp(0, _customMax).toDouble();
    }
    return _selected.grams * _count;
  }

  void _pick(BarcodeAmountOption o) {
    KHaptics.select();
    setState(() {
      _custom = false;
      _selected = o;
      _count = 1;
    });
  }

  void _pickCustom() {
    KHaptics.select();
    setState(() {
      _customCtrl.text = _fmt(_grams > 0 ? _grams : _selected.grams);
      _custom = true;
    });
  }

  void _step(int dir) {
    KHaptics.select();
    setState(() {
      if (_custom) {
        final next = (_grams + dir * _customStep).clamp(_customStep, _customMax);
        _customCtrl.text = _fmt(next.toDouble());
      } else {
        _count = (_count + dir * _countStep).clamp(_countStep, _countMax).toDouble();
      }
    });
  }

  Future<void> _link() async {
    final offer = _linkOffer;
    if (offer == null) return;
    KHaptics.commit();
    setState(() => _linked = true);
    await FoodLinkService.instance.link(_p, offer.name);
  }

  Future<void> _undoLink() async {
    final offer = _linkOffer;
    if (offer == null) return;
    KHaptics.select();
    setState(() => _linked = false);
    await FoodLinkService.instance.unlink(_p.barcode, alias: offer.name);
  }

  Future<void> _notSame() async {
    final offer = _linkOffer;
    if (offer == null) return;
    KHaptics.select();
    setState(() => _linkOffer = null);
    await FoodLinkService.instance.decline(_p, offer.name);
  }

  void _commit(BarcodeSheetAction action) {
    final grams = _grams;
    if (grams <= 0 || _logging) return;
    final result = _p.resultForAmount(grams);
    if (action == BarcodeSheetAction.logged) {
      setState(() => _logging = true);
      final entry = BarcodeMealLogger.log(
        product: _p,
        grams: grams,
        date: widget.date,
        section: _section,
      );
      // Logged. The button turns into its "Logged" face (the commit haptic
      // already fired once on the tap), then the sheet closes as before.
      setState(() => _loggedResult = BarcodeSheetResult(
        action: action,
        grams: grams,
        section: _section,
        result: entry.result,
        entry: entry,
      ));
      return;
    }
    Navigator.of(context).pop(BarcodeSheetResult(
      action: action,
      grams: grams,
      section: _section,
      result: result,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final grams = _grams;
    final n = _p.nutrimentsFor(grams);
    final amount = _p.amountLabel(grams);
    final valid = grams > 0;
    final primary = widget.mode == BarcodeSheetMode.log
        ? 'Log $amount to ${_section.displayName}'
        : 'Add $amount to this meal';

    return PopScope(
      // Hold the sheet while the "Logged" moment plays so the caller still
      // receives the logged entry.
      canPop: _loggedResult == null,
      child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: KSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const KDragHandle(),
              Padding(
                padding: const EdgeInsets.fromLTRB(KSpacing.p, KSpacing.sm, KSpacing.p, 0),
                child: _Header(product: _p),
              ),
              AnimatedSize(
                duration: KMotion.of(context, KMotion.standard),
                curve: KMotion.emphasizedCurve,
                alignment: Alignment.topCenter,
                child: _linkOffer == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(KSpacing.p, KSpacing.lg, KSpacing.p, 0),
                        child: _LinkPrompt(
                          name: _linkOffer!.name,
                          linked: _linked,
                          onLink: _link,
                          onNotSame: _notSame,
                          onUndo: _undoLink,
                        ),
                      ),
              ),
              const SizedBox(height: KSpacing.xl),
              _Label('How much?'),
              const SizedBox(height: KSpacing.sm),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: KSpacing.p),
                child: Wrap(
                  spacing: KSpacing.sm,
                  runSpacing: KSpacing.sm,
                  children: [
                    for (final o in _options)
                      _AmountChip(
                        label: o.chipLabel,
                        selected: !_custom && identical(o, _selected),
                        onTap: () => _pick(o),
                      ),
                    _AmountChip(
                      label: 'Custom',
                      icon: Icons.edit_outlined,
                      selected: _custom,
                      onTap: _pickCustom,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: KSpacing.md),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: KSpacing.p),
                child: _Stepper(
                  onMinus: () => _step(-1),
                  onPlus: () => _step(1),
                  minusEnabled: _custom ? grams > _customStep : _count > _countStep,
                  plusEnabled: _custom ? grams < _customMax : _count < _countMax,
                  child: _custom
                      ? _CustomField(
                          controller: _customCtrl,
                          unit: _p.unit,
                          onChanged: (_) => setState(() {}),
                        )
                      : _CountLabel(
                          count: _count,
                          option: _selected,
                          totalLabel: amount,
                        ),
                ),
              ),
              const SizedBox(height: KSpacing.lg),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: KSpacing.p),
                child: _Macros(
                  calories: n.calories,
                  protein: n.proteinG,
                  carbs: n.carbsG,
                  fat: n.fatG,
                  amount: amount,
                ),
              ),
              if (widget.mode == BarcodeSheetMode.log) ...[
                const SizedBox(height: KSpacing.xl),
                _Label('Log to'),
                const SizedBox(height: KSpacing.sm),
                // Every section in view at once (wraps), so none hides
                // half-cut off the edge of the sheet.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: KSpacing.p),
                  child: Wrap(
                    spacing: KSpacing.sm,
                    runSpacing: KSpacing.sm,
                    children: [
                      for (final s in MealSection.values)
                        _AmountChip(
                          label: s.displayName,
                          icon: KIcons.meal(s),
                          selected: s == _section,
                          onTap: () {
                            if (s == _section) return;
                            KHaptics.select();
                            setState(() => _section = s);
                          },
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: KSpacing.xl),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: KSpacing.p),
                child: AnimatedSwitcher(
                  duration: KMotion.of(context, KMotion.quick),
                  switchInCurve: KMotion.decelerate,
                  switchOutCurve: KMotion.accelerate,
                  layoutBuilder: (current, previous) => Stack(
                    fit: StackFit.passthrough,
                    alignment: Alignment.center,
                    children: [...previous, ?current],
                  ),
                  child: _loggedResult != null
                      ? KSuccessPill(
                          key: const ValueKey('logged'),
                          label: 'Logged',
                          onFinished: () {
                            final r = _loggedResult;
                            if (mounted && r != null) Navigator.of(context).pop(r);
                          },
                        )
                      : KButton(
                          key: const ValueKey('log'),
                          label: primary,
                          icon: widget.mode == BarcodeSheetMode.log
                              ? Icons.check_rounded
                              : Icons.add_rounded,
                          loading: _logging,
                          onTap: valid
                              ? () => _commit(widget.mode == BarcodeSheetMode.log
                                  ? BarcodeSheetAction.logged
                                  : BarcodeSheetAction.fill)
                              : null,
                        ),
                ),
              ),
              if (widget.mode == BarcodeSheetMode.log) ...[
                const SizedBox(height: KSpacing.xs),
                Center(
                  child: TextButton.icon(
                    onPressed: valid ? () => _commit(BarcodeSheetAction.edit) : null,
                    style: TextButton.styleFrom(
                      foregroundColor: KColor.textSecondary,
                      minimumSize: const Size(48, 48),
                      textStyle: KText.bodyMedium,
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit before logging'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      ),
    );
  }
}

// ─── Pieces ───────────────────────────────────────────────────────────────────

/// "Same as your X?" One quiet choice; linking makes the scanned pack the
/// source of truth for both names.
class _LinkPrompt extends StatelessWidget {
  const _LinkPrompt({
    required this.name,
    required this.linked,
    required this.onLink,
    required this.onNotSame,
    required this.onUndo,
  });

  final String name;
  final bool linked;
  final VoidCallback onLink;
  final VoidCallback onNotSame;
  final VoidCallback onUndo;

  String get _display => name.isEmpty ? name : name[0].toUpperCase() + name.substring(1);

  @override
  Widget build(BuildContext context) {
    ButtonStyle style(Color fg) => TextButton.styleFrom(
          foregroundColor: fg,
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: KSpacing.md),
          textStyle: KText.bodyMedium,
        );
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(KSpacing.md, KSpacing.md, KSpacing.sm, KSpacing.xs),
        decoration: BoxDecoration(
          color: KColor.cardHigh,
          borderRadius: KRadius.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    linked ? Icons.check_circle_outline_rounded : Icons.link_rounded,
                    size: 18,
                    color: linked ? KColor.ink : KColor.textSecondary,
                  ),
                ),
                const SizedBox(width: KSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        linked ? 'Linked to "$_display"' : 'Same as your "$_display"?',
                        style: KText.bodyMedium.copyWith(color: KColor.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        linked
                            ? 'Typing either name now logs this pack.'
                            : 'Link them and both names log this pack.',
                        style: KText.caption,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: linked
                  ? TextButton(
                      onPressed: onUndo,
                      style: style(KColor.textSecondary),
                      child: const Text('Undo'),
                    )
                  : Wrap(
                      spacing: KSpacing.xs,
                      children: [
                        TextButton(
                          onPressed: onNotSame,
                          style: style(KColor.textSecondary),
                          child: const Text('Not the same'),
                        ),
                        TextButton(
                          onPressed: onLink,
                          style: style(KColor.textPrimary),
                          child: const Text('Link'),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KSpacing.p),
      child: Semantics(
        header: true,
        child: Text(text, style: KText.h3.copyWith(color: KColor.textSecondary, fontSize: 14)),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.product});
  final BarcodeProduct product;

  IconData get _sourceIcon => switch (product.source) {
        BarcodeSource.openFoodFacts => Icons.verified_outlined,
        BarcodeSource.labelPhoto    => Icons.photo_camera_outlined,
        BarcodeSource.userEntered   => Icons.edit_note_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final brand = product.brand;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ProductImage(url: product.imageUrl),
        const SizedBox(width: KSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product.name,
                style: KText.h2,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              if (brand != null && brand.isNotEmpty && brand != product.name) ...[
                const SizedBox(height: 2),
                Text(brand, style: KText.caption.copyWith(fontSize: 13)),
              ],
              const SizedBox(height: KSpacing.sm),
              Row(
                children: [
                  Icon(_sourceIcon, size: 14, color: KColor.textMuted),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      product.source.note(product.unit),
                      style: KText.caption,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.url});
  final String? url;

  static const double _size = 72;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: _size,
      height: _size,
      color: KColor.cardHigh,
      alignment: Alignment.center,
      child: Icon(Icons.inventory_2_outlined, color: KColor.textMuted, size: 28),
    );
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return ExcludeSemantics(
      child: Container(
        width: _size,
        height: _size,
        decoration: BoxDecoration(
          borderRadius: KRadius.md,
          border: Border.all(color: KColor.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: url == null
            ? placeholder
            : Image.network(
                url!,
                width: _size,
                height: _size,
                fit: BoxFit.cover,
                cacheWidth: (_size * dpr).round(),
                frameBuilder: (context, child, frame, sync) {
                  if (sync || frame != null) return child;
                  return placeholder;
                },
                errorBuilder: (_, _, _) => placeholder,
              ),
      ),
    );
  }
}

class _AmountChip extends StatelessWidget {
  const _AmountChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? KColor.onInk : KColor.textPrimary;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        borderRadius: KRadius.sm,
        scale: 0.97,
        child: AnimatedContainer(
          duration: KMotion.of(context, KMotion.quick),
          curve: KMotion.emphasizedCurve,
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? KColor.ink : null,
            borderRadius: KRadius.sm,
            border: Border.all(
              color: selected ? KColor.ink : KColor.fg.withValues(alpha: KColor.isDark ? 0.16 : 0.16),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: selected ? fg : KColor.textSecondary),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  style: KText.bodyMedium.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
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

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.onMinus,
    required this.onPlus,
    required this.minusEnabled,
    required this.plusEnabled,
    required this.child,
  });

  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final bool minusEnabled;
  final bool plusEnabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, String tip, bool enabled, VoidCallback onTap) {
      return IconButton(
        tooltip: tip,
        onPressed: enabled ? onTap : null,
        icon: Icon(icon),
        color: KColor.textPrimary,
        disabledColor: KColor.textDisabled,
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          backgroundColor: KColor.cardHigh,
        ),
      );
    }

    return KCard(
      padding: const EdgeInsets.all(KSpacing.sm),
      boxShadow: const [],
      child: Row(
        children: [
          btn(Icons.remove_rounded, 'Less', minusEnabled, onMinus),
          Expanded(child: Center(child: child)),
          btn(Icons.add_rounded, 'More', plusEnabled, onPlus),
        ],
      ),
    );
  }
}

class _CountLabel extends StatelessWidget {
  const _CountLabel({
    required this.count,
    required this.option,
    required this.totalLabel,
  });

  final double count;
  final BarcodeAmountOption option;
  final String totalLabel;

  @override
  Widget build(BuildContext context) {
    final c = count == count.roundToDouble()
        ? count.round().toString()
        : count.toStringAsFixed(1);
    final noun = option.noun;
    final caption = noun.isEmpty
        ? null
        : '$c $noun${count == 1 ? '' : 's'}';
    return Semantics(
      liveRegion: true,
      label: '${caption ?? ''} $totalLabel'.trim(),
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$c × ${option.amount}',
            style: KText.numSmall.copyWith(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            caption == null ? totalLabel : '$caption · $totalLabel',
            style: KText.caption,
          ),
        ],
      ),
    );
  }
}

class _CustomField extends StatelessWidget {
  const _CustomField({
    required this.controller,
    required this.unit,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String unit;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textAlign: TextAlign.center,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          LengthLimitingTextInputFormatter(6),
        ],
        style: KText.numMedium,
        cursorColor: KColor.ink,
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          suffixText: unit,
          suffixStyle: KText.caption.copyWith(fontSize: 14),
          semanticCounterText: 'Amount in $unit',
        ),
      ),
    );
  }
}

class _Macros extends StatelessWidget {
  const _Macros({
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.amount,
  });

  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final String amount;

  @override
  Widget build(BuildContext context) {
    final kcal = calories.round();
    return Semantics(
      container: true,
      label: '$amount: $kcal kcal, ${protein.toStringAsFixed(1)} grams protein, '
          '${carbs.toStringAsFixed(1)} grams carbs, ${fat.toStringAsFixed(1)} grams fat',
      excludeSemantics: true,
      // Set like the pack's own nutrition panel: an ink rule, the energy
      // figure, then the macros on one line.
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: KColor.textPrimary, width: 4),
            bottom: BorderSide(color: KColor.textPrimary, width: 1),
          ),
        ),
        child: Padding(
        padding: const EdgeInsets.symmetric(vertical: KSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('In $amount', style: KText.caption.copyWith(fontSize: 13)),
            const SizedBox(height: 2),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 6,
              children: [
                Text('$kcal', style: KText.numDisplay.copyWith(fontSize: 44, letterSpacing: -1.8)),
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      KDot(color: KColor.ember, size: 7),
                      const SizedBox(width: 5),
                      Text(
                        'kcal',
                        style: KText.caption.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: KSpacing.sm),
            Wrap(
              spacing: KSpacing.lg,
              runSpacing: 6,
              children: [
                _MacroLine(label: 'Protein', value: protein, color: KColor.protein, strong: true),
                _MacroLine(label: 'Carbs', value: carbs, color: KColor.carbs),
                _MacroLine(label: 'Fat', value: fat, color: KColor.fat),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _MacroLine extends StatelessWidget {
  const _MacroLine({
    required this.label,
    required this.value,
    required this.color,
    this.strong = false,
  });

  final String label;
  final double value;
  final Color color;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$label ',
                  style: KText.caption.copyWith(fontSize: 13, color: KColor.textSecondary),
                ),
                TextSpan(
                  text: '${amount(value)} g',
                  style: KText.numSmall.copyWith(
                    fontSize: strong ? 15 : 13,
                    fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
                    color: KColor.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
