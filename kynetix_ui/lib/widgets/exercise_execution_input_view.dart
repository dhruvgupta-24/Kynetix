import 'dart:async';
import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../models/workout_split.dart';
import '../ui/k_rolling.dart';
import 'barbell_plate_calculator.dart';
import 'k_ticking_text.dart';

/// Validation logic for exercise execution modes.
class ExecutionModeValidator {
  static String? validate({
    required ExerciseExecutionMode mode,
    required double weight,
    required int reps,
    double? externalLoadKg,
    int? durationSeconds,
    double? distanceMeters,
  }) {
    switch (mode) {
      case ExerciseExecutionMode.weightReps:
        if (reps <= 0) return 'Reps must be at least 1';
        if (weight < 0) return 'Weight cannot be negative';
        return null;
      case ExerciseExecutionMode.bodyweightReps:
      case ExerciseExecutionMode.weightedBodyweight:
        if (reps <= 0) return 'Reps must be at least 1';
        if (externalLoadKg != null && externalLoadKg < 0) return 'External load cannot be negative';
        return null;
      case ExerciseExecutionMode.timed:
        if (durationSeconds == null || durationSeconds <= 0) return 'Hold duration must be at least 1s';
        return null;
      case ExerciseExecutionMode.cardio:
        if ((durationSeconds == null || durationSeconds <= 0) &&
            (distanceMeters == null || distanceMeters <= 0)) {
          return 'Enter cardio duration or distance';
        }
        return null;
    }
  }
}

// ─── Local type ramp ──────────────────────────────────────────────────────────
// Everything derives from KText so the console speaks the design system's
// voice. Numbers always carry tabular figures so dials never jitter.
abstract class _InputText {
  static TextStyle get eyebrow => KText.caption.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: KColor.textSecondary,
        letterSpacing: 0,
      );
  static TextStyle get step => KText.numSmall.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: KColor.textPrimary,
      );
  static TextStyle get hint => KText.caption.copyWith(fontSize: 12, color: KColor.textMuted, height: 1.3);
  static TextStyle get readout => KText.numDisplay.copyWith(fontSize: 34);
  static TextStyle get readoutSmall => KText.numMedium.copyWith(fontSize: 26);
  static TextStyle get wheel => KText.numSmall.copyWith(fontSize: 16);
}

/// Hairline for console wells: a whisper of white on Carbon, the warm paper
/// border on Paper.
Color _hairline() => KColor.isDark ? KColor.fg.withValues(alpha: 0.09) : KColor.border;

/// Surface of a recessed console well.
Color _wellFill() => KColor.isDark ? KColor.card : KColor.cardHigh;

/// Unified execution input interface for WorkoutSessionScreen.
/// Encapsulates mode-specific selectors (Weight, Bodyweight External Load, Timed Hold, Cardio)
/// without scattering conditionals across the screen hierarchy.
class ExerciseExecutionInputView extends StatefulWidget {
  final Exercise exercise;
  final double selectedWeight;
  final int selectedReps;
  final double? externalLoadKg;
  final int? durationSeconds;
  final double? distanceMeters;
  final double barWeightKg;

  final ValueChanged<double> onWeightChanged;
  final ValueChanged<int> onRepsChanged;
  final ValueChanged<double> onExternalLoadChanged;
  final ValueChanged<int> onDurationChanged;
  final ValueChanged<double> onDistanceChanged;

  const ExerciseExecutionInputView({
    super.key,
    required this.exercise,
    required this.selectedWeight,
    required this.selectedReps,
    this.externalLoadKg,
    this.durationSeconds,
    this.distanceMeters,
    this.barWeightKg = 20.0,
    required this.onWeightChanged,
    required this.onRepsChanged,
    required this.onExternalLoadChanged,
    required this.onDurationChanged,
    required this.onDistanceChanged,
  });

  @override
  State<ExerciseExecutionInputView> createState() => _ExerciseExecutionInputViewState();
}

class _ExerciseExecutionInputViewState extends State<ExerciseExecutionInputView> {
  // Live stopwatch for timed holds. The ticking value lives in a notifier so a
  // tick repaints only the readout, never the whole console.
  Timer? _stopwatchTimer;
  final ValueNotifier<int> _stopwatchElapsed = ValueNotifier<int>(0);
  bool _isStopwatchRunning = false;

  late FixedExtentScrollController _weightController;
  late FixedExtentScrollController _repsController;
  late FixedExtentScrollController _durationController;

  static final List<double> _weightOptions = List.generate(701, (i) => i * 0.5); // 0 to 350 kg
  static final List<int> _repsOptions = List.generate(100, (i) => i + 1); // 1 to 100
  static final List<int> _durationOptions = [
    5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60,
    75, 90, 105, 120, 150, 180, 240, 300, 360, 420, 480, 600,
  ];

  bool _isInternalUpdating = false;

  /// Index a stepper is gliding the dial to, or null when the dial is free.
  int? _weightGlideTarget;
  int? _repsGlideTarget;

  @override
  void initState() {
    super.initState();
    final wIdx = (widget.selectedWeight / 0.5).round().clamp(0, 700);
    _weightController = FixedExtentScrollController(initialItem: wIdx);

    final rIdx = (widget.selectedReps - 1).clamp(0, 99);
    _repsController = FixedExtentScrollController(initialItem: rIdx);

    final curDur = widget.durationSeconds ?? 60;
    final dIdx = _durationOptions.indexOf(curDur);
    _durationController = FixedExtentScrollController(initialItem: dIdx >= 0 ? dIdx : 11);
  }

  @override
  void didUpdateWidget(ExerciseExecutionInputView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isInternalUpdating) return;
    if (oldWidget.selectedWeight != widget.selectedWeight && _weightController.hasClients) {
      final wIdx = (widget.selectedWeight / 0.5).round().clamp(0, 700);
      if (_weightController.selectedItem != wIdx) {
        _isInternalUpdating = true;
        _weightController.jumpToItem(wIdx);
        _isInternalUpdating = false;
      }
    }
    if (oldWidget.selectedReps != widget.selectedReps && _repsController.hasClients) {
      final rIdx = (widget.selectedReps - 1).clamp(0, 99);
      if (_repsController.selectedItem != rIdx) {
        _isInternalUpdating = true;
        _repsController.jumpToItem(rIdx);
        _isInternalUpdating = false;
      }
    }
  }

  @override
  void dispose() {
    _stopwatchTimer?.cancel();
    _stopwatchElapsed.dispose();
    _weightController.dispose();
    _repsController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  void _toggleStopwatch() {
    if (_isStopwatchRunning) {
      _stopwatchTimer?.cancel();
      setState(() {
        _isStopwatchRunning = false;
      });
      widget.onDurationChanged(_stopwatchElapsed.value);
      KHaptics.commit();
    } else {
      _stopwatchElapsed.value = 0;
      setState(() {
        _isStopwatchRunning = true;
      });
      _stopwatchTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        _stopwatchElapsed.value++;
      });
      KHaptics.commit();
    }
  }

  bool get _isBarbellExercise {
    final nameLower = widget.exercise.name.toLowerCase();
    return widget.exercise.type == ExerciseType.barbellCompound ||
        nameLower.contains('barbell') ||
        nameLower.contains('bench press') ||
        nameLower.contains('deadlift') ||
        nameLower.contains('squat') && !nameLower.contains('dumbbell');
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.exercise.effectiveExecutionMode) {
      case ExerciseExecutionMode.timed:
        return _buildTimedInput();
      case ExerciseExecutionMode.bodyweightReps:
      case ExerciseExecutionMode.weightedBodyweight:
        return _buildBodyweightInput();
      case ExerciseExecutionMode.cardio:
        return _buildCardioInput();
      case ExerciseExecutionMode.weightReps:
        return _buildWeightRepsInput();
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 1. STANDARD WEIGHT × REPS (with Contextual Barbell Plate Calculator)
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildWeightRepsInput() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left: Weight dial wheel
            Expanded(
              child: Column(
                children: [
                  Text('Weight (kg)', style: _InputText.eyebrow, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  _StepRow(children: [
                    _StepButton(label: '-5', onTap: () => _adjustWeight(-5)),
                    _StepButton(label: '-2.5', onTap: () => _adjustWeight(-2.5)),
                  ]),
                  const SizedBox(height: 8),
                  _Kynetix3DWheelPicker<double>(
                    controller: _weightController,
                    items: _weightOptions,
                    selectedItem: widget.selectedWeight,
                    labelBuilder: (w) => '${w.toStringAsFixed(1)} kg',
                    onSelectedItemChanged: _onWeightWheelChanged,
                    onUserDrag: () => _weightGlideTarget = null,
                  ),
                  const SizedBox(height: 8),
                  _StepRow(children: [
                    _StepButton(label: '+2.5', onTap: () => _adjustWeight(2.5)),
                    _StepButton(label: '+5', onTap: () => _adjustWeight(5)),
                  ]),
                ],
              ),
            ),
            const SizedBox(width: 14),

            // Right: Reps dial wheel
            Expanded(
              child: Column(
                children: [
                  Text('Reps', style: _InputText.eyebrow, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  _StepRow(children: [
                    _StepButton(label: '-5', onTap: () => _adjustReps(-5)),
                    _StepButton(label: '-1', onTap: () => _adjustReps(-1)),
                  ]),
                  const SizedBox(height: 8),
                  _Kynetix3DWheelPicker<int>(
                    controller: _repsController,
                    items: _repsOptions,
                    selectedItem: widget.selectedReps,
                    labelBuilder: (r) => '$r reps',
                    onSelectedItemChanged: _onRepsWheelChanged,
                    onUserDrag: () => _repsGlideTarget = null,
                  ),
                  const SizedBox(height: 8),
                  _StepRow(children: [
                    _StepButton(label: '+1', onTap: () => _adjustReps(1)),
                    _StepButton(label: '+5', onTap: () => _adjustReps(5)),
                  ]),
                ],
              ),
            ),
          ],
        ),

        // Contextual Barbell Plate Stack View (underneath weight dials)
        if (_isBarbellExercise) ...[
          const SizedBox(height: 10),
          BarbellPlateStackView(
            targetWeightKg: widget.selectedWeight,
            barWeightKg: widget.barWeightKg,
          ),
        ],
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 2. BODYWEIGHT (BW Base + External Load kg × Reps)
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildBodyweightInput() {
    final currentExternal = widget.externalLoadKg ?? 0.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left: External load selector
            Expanded(
              child: Column(
                children: [
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: KColor.fg.withValues(alpha: KColor.isDark ? 0.08 : 0.06),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Bodyweight',
                          style: _InputText.eyebrow.copyWith(color: KColor.textPrimary),
                        ),
                      ),
                      Text('+ load (kg)', style: _InputText.eyebrow),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _StepRow(children: [
                    _StepButton(label: '-5', onTap: () => _adjustExternalLoad(-5)),
                    _StepButton(label: '-2.5', onTap: () => _adjustExternalLoad(-2.5)),
                  ]),
                  const SizedBox(height: 8),
                  _ReadoutWell(
                    height: 164,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (currentExternal > 0)
                          _RollingReadout(
                            prefix: '+',
                            value: currentExternal.toStringAsFixed(1),
                            unit: ' kg',
                            style: _InputText.readoutSmall,
                          )
                        else
                          Text(
                            'Bodyweight only',
                            textAlign: TextAlign.center,
                            style: _InputText.eyebrow.copyWith(fontSize: 15, color: KColor.textPrimary),
                          ),
                        if (currentExternal > 0)
                          Text('External load', style: _InputText.hint),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _StepRow(children: [
                    _StepButton(label: '+2.5', onTap: () => _adjustExternalLoad(2.5)),
                    _StepButton(label: '+5', onTap: () => _adjustExternalLoad(5)),
                  ]),
                ],
              ),
            ),
            const SizedBox(width: 14),

            // Right: Reps dial wheel
            Expanded(
              child: Column(
                children: [
                  Text('Reps', style: _InputText.eyebrow, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  _StepRow(children: [
                    _StepButton(label: '-5', onTap: () => _adjustReps(-5)),
                    _StepButton(label: '-1', onTap: () => _adjustReps(-1)),
                  ]),
                  const SizedBox(height: 8),
                  _Kynetix3DWheelPicker<int>(
                    controller: _repsController,
                    items: _repsOptions,
                    selectedItem: widget.selectedReps,
                    labelBuilder: (r) => '$r reps',
                    onSelectedItemChanged: _onRepsWheelChanged,
                    onUserDrag: () => _repsGlideTarget = null,
                  ),
                  const SizedBox(height: 8),
                  _StepRow(children: [
                    _StepButton(label: '+1', onTap: () => _adjustReps(1)),
                    _StepButton(label: '+5', onTap: () => _adjustReps(5)),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 3. TIMED EXECUTION (Hold Duration in seconds/minutes + Stopwatch)
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildTimedInput() {
    final curDuration = widget.durationSeconds ?? 60;
    final mins = curDuration ~/ 60;
    final secs = curDuration % 60;
    final durStr = '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    final running = _isStopwatchRunning;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left: Live Hold Stopwatch Button
            Expanded(
              child: Column(
                children: [
                  Text('Hold timer', style: _InputText.eyebrow, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Semantics(
                    button: true,
                    label: running ? 'Stop the hold timer and use that time' : 'Start the hold timer',
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        onTap: _toggleStopwatch,
                        borderRadius: KRadius.md,
                        child: AnimatedContainer(
                          duration: KMotion.of(context, KMotion.quick),
                          curve: KMotion.emphasizedCurve,
                          constraints: const BoxConstraints(minHeight: 154),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          // Running = ink fill: the one live thing on the console.
                          decoration: BoxDecoration(
                            color: running ? KColor.ink : _wellFill(),
                            borderRadius: KRadius.md,
                            border: Border.all(
                              color: running ? KColor.ink : _hairline(),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ExcludeSemantics(
                                child: Icon(
                                  running ? Icons.stop_circle_rounded : Icons.play_circle_fill_rounded,
                                  size: 40,
                                  color: running ? KColor.onInk : KColor.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (running)
                                ValueListenableBuilder<int>(
                                  valueListenable: _stopwatchElapsed,
                                  // Digits tick over in fixed tabular cells.
                                  builder: (context, elapsed, _) => KTickingText(
                                    '${(elapsed ~/ 60).toString().padLeft(2, '0')}:${(elapsed % 60).toString().padLeft(2, '0')}',
                                    style: _InputText.readout.copyWith(fontSize: 28, color: KColor.onInk),
                                  ),
                                )
                              else
                                Text(
                                  'Start timer',
                                  style: _InputText.eyebrow.copyWith(fontSize: 15, color: KColor.textPrimary),
                                ),
                              const SizedBox(height: 4),
                              Text(
                                running ? 'Tap to stop, time fills in' : 'Times your hold',
                                textAlign: TextAlign.center,
                                style: running
                                    ? _InputText.hint.copyWith(color: KColor.onInk.withValues(alpha: 0.72))
                                    : _InputText.hint,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),

            // Right: Duration Selector wheel
            Expanded(
              child: Column(
                children: [
                  Text('Target duration', style: _InputText.eyebrow, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  _StepRow(children: [
                    _StepButton(label: '-15s', onTap: () => _adjustDuration(-15)),
                    _StepButton(label: '-5s', onTap: () => _adjustDuration(-5)),
                  ]),
                  const SizedBox(height: 8),
                  _ReadoutWell(
                    height: 100,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _RollingReadout(value: durStr, style: _InputText.readout),
                        Text('$curDuration seconds', style: _InputText.hint),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _StepRow(children: [
                    _StepButton(label: '+5s', onTap: () => _adjustDuration(5)),
                    _StepButton(label: '+15s', onTap: () => _adjustDuration(15)),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 4. CARDIO EXECUTION (Duration min/sec + Distance km/m)
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildCardioInput() {
    final curDuration = widget.durationSeconds ?? 900; // 15 mins default
    final curMeters = widget.distanceMeters ?? 2000.0; // 2.0 km default

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left: Duration
            Expanded(
              child: Column(
                children: [
                  Text('Duration', style: _InputText.eyebrow, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  _StepRow(children: [
                    _StepButton(label: '-5m', onTap: () => _adjustDuration(-300)),
                    _StepButton(label: '-1m', onTap: () => _adjustDuration(-60)),
                  ]),
                  const SizedBox(height: 8),
                  _ReadoutWell(
                    height: 100,
                    child: _RollingReadout(
                      value: '${curDuration ~/ 60}m ${(curDuration % 60).toString().padLeft(2, '0')}s',
                      style: _InputText.readoutSmall,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _StepRow(children: [
                    _StepButton(label: '+1m', onTap: () => _adjustDuration(60)),
                    _StepButton(label: '+5m', onTap: () => _adjustDuration(300)),
                  ]),
                ],
              ),
            ),
            const SizedBox(width: 14),

            // Right: Distance
            Expanded(
              child: Column(
                children: [
                  Text('Distance', style: _InputText.eyebrow, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  _StepRow(children: [
                    _StepButton(label: '-500m', onTap: () => _adjustDistance(-500)),
                    _StepButton(label: '-100m', onTap: () => _adjustDistance(-100)),
                  ]),
                  const SizedBox(height: 8),
                  _ReadoutWell(
                    height: 100,
                    child: _RollingReadout(
                      value: curMeters >= 1000
                          ? (curMeters / 1000).toStringAsFixed(2)
                          : curMeters.toStringAsFixed(0),
                      unit: curMeters >= 1000 ? ' km' : ' m',
                      style: _InputText.readoutSmall,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _StepRow(children: [
                    _StepButton(label: '+100m', onTap: () => _adjustDistance(100)),
                    _StepButton(label: '+500m', onTap: () => _adjustDistance(500)),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Helper adjusters & wheel callbacks
  // ───────────────────────────────────────────────────────────────────────────
  void _onWeightWheelChanged(int idx) {
    if (_isInternalUpdating) return;
    if (_weightGlideTarget != null) {
      if (idx == _weightGlideTarget) _weightGlideTarget = null;
      return;
    }
    if (idx < 0 || idx >= _weightOptions.length) return;
    final w = _weightOptions[idx];
    if (w != widget.selectedWeight) {
      _isInternalUpdating = true;
      widget.onWeightChanged(w);
      _isInternalUpdating = false;
      KHaptics.select();
    }
  }

  void _onRepsWheelChanged(int idx) {
    if (_isInternalUpdating) return;
    if (_repsGlideTarget != null) {
      if (idx == _repsGlideTarget) _repsGlideTarget = null;
      return;
    }
    if (idx < 0 || idx >= _repsOptions.length) return;
    final r = _repsOptions[idx];
    if (r != widget.selectedReps) {
      _isInternalUpdating = true;
      widget.onRepsChanged(r);
      _isInternalUpdating = false;
      KHaptics.select();
    }
  }

  /// Glide the dial to [idx]; jumps under reduced motion. Returns false
  /// when there was nothing to move.
  bool _animateWheel(FixedExtentScrollController controller, int idx, {required bool weight}) {
    void setTarget(int? t) => weight ? _weightGlideTarget = t : _repsGlideTarget = t;
    int? target() => weight ? _weightGlideTarget : _repsGlideTarget;
    if (!controller.hasClients) return false;
    if (controller.selectedItem == idx) {
      setTarget(null);
      return false;
    }
    final d = KMotion.of(context, const Duration(milliseconds: 200));
    if (d == Duration.zero) {
      setTarget(null);
      _isInternalUpdating = true;
      controller.jumpToItem(idx);
      _isInternalUpdating = false;
    } else {
      setTarget(idx);
      controller.animateToItem(idx, duration: d, curve: KMotion.emphasizedCurve).whenComplete(() {
        // A newer glide (rapid taps, hold-to-repeat) owns the target now.
        if (mounted && target() == idx) setTarget(null);
      });
    }
    return true;
  }

  /// A stepper tick: one value change, one selection haptic. At a limit the
  /// value can't move, so nothing ticks.
  void _adjustWeight(double delta) {
    final next = (widget.selectedWeight + delta).clamp(0.0, 350.0);
    if (next == widget.selectedWeight) return;
    _isInternalUpdating = true;
    widget.onWeightChanged(next);
    _isInternalUpdating = false;
    final idx = (next / 0.5).round().clamp(0, 700);
    _animateWheel(_weightController, idx, weight: true);
    KHaptics.select();
  }

  void _adjustReps(int delta) {
    final next = (widget.selectedReps + delta).clamp(1, 100);
    if (next == widget.selectedReps) return;
    _isInternalUpdating = true;
    widget.onRepsChanged(next);
    _isInternalUpdating = false;
    final idx = (next - 1).clamp(0, 99);
    _animateWheel(_repsController, idx, weight: false);
    KHaptics.select();
  }

  void _adjustExternalLoad(double delta) {
    final current = widget.externalLoadKg ?? 0.0;
    final next = (current + delta).clamp(0.0, 150.0);
    if (next == current && widget.externalLoadKg != null) return;
    widget.onExternalLoadChanged(next);
    KHaptics.select();
  }

  void _adjustDuration(int deltaSeconds) {
    final cur = widget.durationSeconds ?? 60;
    final next = (cur + deltaSeconds).clamp(5, 7200);
    if (next == cur && widget.durationSeconds != null) return;
    widget.onDurationChanged(next);
    KHaptics.select();
  }

  void _adjustDistance(double deltaMeters) {
    final cur = widget.distanceMeters ?? 2000.0;
    final next = (cur + deltaMeters).clamp(50.0, 50000.0);
    if (next == cur && widget.distanceMeters != null) return;
    widget.onDistanceChanged(next);
    KHaptics.select();
  }
}

/// A row of quick-adjust buttons that reflows onto a second line instead of
/// overflowing when the column is narrow or the text scale is large.
class _StepRow extends StatelessWidget {
  final List<Widget> children;
  const _StepRow({required this.children});

  @override
  Widget build(BuildContext context) {
    // Side by side, equal widths: the step buttons used to wrap into a tall
    // column because each one stretched to the full dial width.
    return Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: children[i]),
        ],
      ],
    );
  }
}

/// Recessed well that frames a read-only value (load, duration, distance).
class _ReadoutWell extends StatelessWidget {
  final double height;
  final Widget child;
  const _ReadoutWell({required this.height, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: height),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _wellFill(),
        borderRadius: KRadius.md,
        border: Border.all(color: _hairline(), width: 1),
      ),
      child: child,
    );
  }
}

/// A value in a readout well whose digits roll when it changes. Letters and
/// units ("m", "s", "kg") stay put. Fits the well instead of overflowing.
class _RollingReadout extends StatelessWidget {
  final String prefix;
  final String value;
  final String unit;
  final TextStyle style;
  const _RollingReadout({this.prefix = '', required this.value, this.unit = '', required this.style});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$prefix$value$unit',
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            if (prefix.isNotEmpty) Text(prefix, style: style),
            KRollingNumber(value, style: style, duration: KMotion.standard),
            if (unit.isNotEmpty) Text(unit, style: style),
          ],
        ),
      ),
    );
  }
}

/// Quick-adjust step. Tap for one step; press and hold to repeat, starting
/// slow and speeding up (about 3 then 6 then 12 steps a second). Each step
/// is one value change and one selection haptic, fired by [onTap].
class _StepButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _StepButton({required this.label, required this.onTap});

  @override
  State<_StepButton> createState() => _StepButtonState();
}

class _StepButtonState extends State<_StepButton> {
  Timer? _repeat;
  int _repeats = 0;

  void _startRepeat() {
    _repeats = 0;
    widget.onTap();
    _scheduleNext();
  }

  void _scheduleNext() {
    final ms = _repeats < 4 ? 320 : (_repeats < 12 ? 160 : 80);
    _repeat = Timer(Duration(milliseconds: ms), () {
      if (!mounted) return;
      _repeats++;
      widget.onTap();
      _scheduleNext();
    });
  }

  void _stopRepeat() {
    _repeat?.cancel();
    _repeat = null;
  }

  @override
  void dispose() {
    _stopRepeat();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.label;
    // 48dp minimum for sweaty, mid-set thumbs. The outer detector owns the
    // hold (start / release); the ink well owns the single tap.
    return GestureDetector(
      onLongPressStart: (_) => _startRepeat(),
      onLongPressEnd: (_) => _stopRepeat(),
      onLongPressCancel: _stopRepeat,
      child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: KRadius.sm,
        splashColor: KColor.fg.withValues(alpha: KColor.isDark ? 0.14 : 0.10),
        highlightColor: KColor.fg.withValues(alpha: KColor.isDark ? 0.06 : 0.05),
        child: Container(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: KColor.isDark ? KColor.cardHigh : KColor.card,
            borderRadius: KRadius.sm,
            border: Border.all(color: _hairline(), width: 1),
          ),
          child: Text(label, style: _InputText.step),
        ),
      ),
      ),
    );
  }
}

/// Premium 3D cylindrical wheel picker utilizing Flutter's native [ListWheelScrollView].
///
/// Features:
/// - Selected item centered, prominently magnified (~1.42×) in full-strength ink.
/// - Immediately adjacent items are progressively smaller (~0.90×, 0.52 opacity).
/// - Second-nearest items are even smaller (~0.72×, 0.22 opacity).
/// - Farther items progressively fade down to 0.04 into top/bottom cylinder depth gradients.
/// - Smooth continuous interpolation during scrolling, not only after scroll completion.
/// - Fixed-extent snapping physics with natural inertia and flings.
/// - Center framing lens drawn with theme hairlines.
/// - Isolated behind a RepaintBoundary so wheel scrolling never re-rasters the console.
class _Kynetix3DWheelPicker<T> extends StatelessWidget {
  final FixedExtentScrollController controller;
  final List<T> items;
  final T selectedItem;
  final String Function(T item) labelBuilder;
  final ValueChanged<int> onSelectedItemChanged;
  final VoidCallback? onUserDrag;
  final double height;
  final double itemExtent;

  const _Kynetix3DWheelPicker({
    required this.controller,
    required this.items,
    required this.selectedItem,
    required this.labelBuilder,
    required this.onSelectedItemChanged,
    this.onUserDrag,
    this.height = 164.0,
    this.itemExtent = 40.0,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: _wellFill(),
          borderRadius: KRadius.md,
          border: Border.all(color: _hairline(), width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Cylindrical center selection lens highlight
            IgnorePointer(
              child: Container(
                height: itemExtent + 4,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: KColor.isDark
                      ? KColor.fg.withValues(alpha: 0.07)
                      : KColor.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: KColor.fg.withValues(alpha: KColor.isDark ? 0.14 : 0.12),
                    width: 1.0,
                  ),
                  boxShadow: KColor.isDark ? null : KShadow.card,
                ),
              ),
            ),

            // Native 3D ListWheelScrollView with cylindrical perspective & momentum physics
            NotificationListener<ScrollStartNotification>(
              onNotification: (n) {
                if (n.dragDetails != null) onUserDrag?.call();
                return false;
              },
              child: ListWheelScrollView.useDelegate(
              controller: controller,
              itemExtent: itemExtent,
              physics: const FixedExtentScrollPhysics(),
              perspective: 0.0035,
              diameterRatio: 1.25,
              squeeze: 1.04,
              useMagnifier: false,
              onSelectedItemChanged: onSelectedItemChanged,
              childDelegate: ListWheelChildBuilderDelegate(
                builder: (context, index) {
                  if (index < 0 || index >= items.length) return null;
                  final label = labelBuilder(items[index]);

                  return AnimatedBuilder(
                    animation: controller,
                    builder: (context, child) {
                      double delta = 0.0;
                      if (controller.hasClients) {
                        final offset = controller.offset;
                        delta = (index * itemExtent - offset) / itemExtent;
                      } else {
                        delta = (index - controller.initialItem).toDouble();
                      }

                      final absDelta = delta.abs();

                      // Continuous smooth scale, opacity and color interpolation:
                      // Center (0.0): ~1.42x magnification, full ink, 1.0 opacity, boldest weight
                      // Immediately adjacent (1.0): ~0.90x, secondary ink, 0.52 opacity
                      // Second-nearest (2.0): ~0.72x, muted ink, 0.22 opacity
                      // Farther (>2.0): progressively fading down to 0.04 into cylinder depth
                      final double scale;
                      final double opacity;
                      final Color textColor;
                      final FontWeight fontWeight;

                      if (absDelta <= 1.0) {
                        final t = (1.0 - absDelta).clamp(0.0, 1.0);
                        final smoothT = Curves.easeOutCubic.transform(t);
                        scale = 0.90 + (1.42 - 0.90) * smoothT;
                        opacity = (0.52 + (1.0 - 0.52) * smoothT).clamp(0.0, 1.0);
                        textColor = Color.lerp(KColor.textSecondary, KColor.textPrimary, smoothT)!;
                        fontWeight = smoothT > 0.5 ? FontWeight.w800 : FontWeight.w700;
                      } else if (absDelta <= 2.0) {
                        final t = (2.0 - absDelta).clamp(0.0, 1.0);
                        final smoothT = Curves.easeOutCubic.transform(t);
                        scale = 0.72 + (0.90 - 0.72) * smoothT;
                        opacity = (0.22 + (0.52 - 0.22) * smoothT).clamp(0.0, 1.0);
                        textColor = Color.lerp(KColor.textMuted, KColor.textSecondary, smoothT)!;
                        fontWeight = FontWeight.w600;
                      } else {
                        final t = (3.0 - absDelta).clamp(0.0, 1.0);
                        scale = 0.58 + (0.72 - 0.58) * t;
                        opacity = (0.04 + (0.22 - 0.04) * t).clamp(0.0, 1.0);
                        textColor = KColor.textMuted;
                        fontWeight = FontWeight.w500;
                      }

                      // The fade rides on the text colour: no Opacity layer
                      // (and its offscreen pass) per row per scroll frame.
                      return Center(
                        child: Transform.scale(
                          scale: scale,
                          child: Text(
                            label,
                            style: _InputText.wheel.copyWith(
                              color: textColor.withValues(alpha: textColor.a * opacity),
                              fontWeight: fontWeight,
                              letterSpacing: absDelta < 0.4 ? -0.4 : 0.0,
                            ),
                            maxLines: 1,
                            softWrap: false,
                          ),
                        ),
                      );
                    },
                  );
                },
                childCount: items.length,
              ),
            ),
            ),

            // Top cylinder depth fade
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 32,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [_wellFill(), _wellFill().withValues(alpha: 0)],
                    ),
                  ),
                ),
              ),
            ),

            // Bottom cylinder depth fade
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 32,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [_wellFill(), _wellFill().withValues(alpha: 0)],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
