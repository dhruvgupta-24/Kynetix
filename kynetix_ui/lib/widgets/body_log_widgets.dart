import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_theme.dart';
import '../services/body_metrics_service.dart';

/// Weigh-in sheet: a stepper prefilled with the last weigh-in, plus the trend
/// so a single heavy morning doesn't read as a setback. Returns the saved kg.
Future<double?> showWeightLogSheet(
  BuildContext context, {
  required DateTime date,
  required double startKg,
  double? trendKg,
  double? weeklyRateKg,
}) {
  return showKSheet<double>(
    context: context,
    builder: (ctx) => _WeightSheet(date: date, startKg: startKg, trendKg: trendKg, weeklyRateKg: weeklyRateKg),
  );
}

class _WeightSheet extends StatefulWidget {
  final DateTime date;
  final double startKg;
  final double? trendKg;
  final double? weeklyRateKg;
  const _WeightSheet({required this.date, required this.startKg, this.trendKg, this.weeklyRateKg});

  @override
  State<_WeightSheet> createState() => _WeightSheetState();
}

class _WeightSheetState extends State<_WeightSheet> {
  late double _kg = (widget.startKg * 10).round() / 10;
  bool _saving = false;
  late final _ctrl = TextEditingController(text: _kg.toStringAsFixed(1));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _step(double d) {
    KHaptics.select();
    setState(() {
      _kg = ((_kg + d).clamp(20.0, 400.0) * 10).round() / 10;
      _ctrl.text = _kg.toStringAsFixed(1);
    });
  }

  Future<void> _save() async {
    final v = double.tryParse(_ctrl.text.replaceAll(',', '.'));
    if (v == null || v < 20 || v > 400) {
      KHaptics.reject();
      return;
    }
    setState(() => _saving = true);
    await BodyMetricsService.instance.logWeight(widget.date, v);
    KHaptics.success();
    if (mounted) Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    final rate = widget.weeklyRateKg;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: KSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const KSheetHeader('Log your weight', subtitle: 'Same time, same scale, ideally first thing in the morning.'),
              const SizedBox(height: KSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _StepButton(icon: Icons.remove_rounded, label: 'Less 0.1 kilograms', onTap: () => _step(-0.1), onLongPress: () => _step(-1)),
                  const SizedBox(width: KSpacing.lg),
                  SizedBox(
                    width: 168,
                    child: TextField(
                      controller: _ctrl,
                      textAlign: TextAlign.center,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                      style: KText.display.copyWith(fontSize: 40, fontFeatures: const [FontFeature.tabularFigures()]),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        suffixText: 'kg',
                        suffixStyle: KText.caption.copyWith(fontSize: 16, color: KColor.textMuted),
                      ),
                      onChanged: (t) {
                        final v = double.tryParse(t.replaceAll(',', '.'));
                        if (v != null) _kg = v;
                      },
                      onSubmitted: (_) => _save(),
                    ),
                  ),
                  const SizedBox(width: KSpacing.lg),
                  _StepButton(icon: Icons.add_rounded, label: 'More 0.1 kilograms', onTap: () => _step(0.1), onLongPress: () => _step(1)),
                ],
              ),
              if (widget.trendKg != null) ...[
                const SizedBox(height: KSpacing.md),
                Text(
                  rate == null
                      ? 'Trend weight ${widget.trendKg!.toStringAsFixed(1)} kg'
                      : 'Trend ${widget.trendKg!.toStringAsFixed(1)} kg, ${rate >= 0 ? '+' : '−'}${rate.abs().toStringAsFixed(2)} kg a week',
                  textAlign: TextAlign.center,
                  style: KText.caption.copyWith(color: KColor.textSecondary, fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ],
              const SizedBox(height: KSpacing.lg),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: KSpacing.p),
                child: KButton(label: 'Save weigh-in', loading: _saving, onTap: _save),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _StepButton({required this.icon, required this.label, required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(28),
      semanticLabel: label,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: KColor.cardHigh,
          border: Border.all(color: KColor.border),
        ),
        child: Icon(icon, color: KColor.textPrimary),
      ),
    );
  }
}
