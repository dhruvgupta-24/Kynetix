import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_theme.dart';
import '../models/workout_split.dart';
import 'barbell_plate_calculator.dart';

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
  // Live stopwatch for timed holds
  Timer? _stopwatchTimer;
  int _stopwatchElapsedSeconds = 0;
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
      widget.onDurationChanged(_stopwatchElapsedSeconds);
      HapticFeedback.mediumImpact();
    } else {
      setState(() {
        _isStopwatchRunning = true;
        _stopwatchElapsedSeconds = 0;
      });
      _stopwatchTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        setState(() {
          _stopwatchElapsedSeconds++;
        });
      });
      HapticFeedback.lightImpact();
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
          children: [
            // Left: Weight dial wheel
            Expanded(
              child: Column(
                children: [
                  const Text(
                    'WEIGHT (KG)',
                    style: TextStyle(color: KColor.textMuted, fontSize: 8.5, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _StepButton(label: '-5', onTap: () => _adjustWeight(-5)),
                      const SizedBox(width: 4),
                      _StepButton(label: '-2.5', onTap: () => _adjustWeight(-2.5)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _Kynetix3DWheelPicker<double>(
                    controller: _weightController,
                    items: _weightOptions,
                    selectedItem: widget.selectedWeight,
                    labelBuilder: (w) => '${w.toStringAsFixed(1)} kg',
                    onSelectedItemChanged: _onWeightWheelChanged,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _StepButton(label: '+2.5', onTap: () => _adjustWeight(2.5)),
                      const SizedBox(width: 4),
                      _StepButton(label: '+5', onTap: () => _adjustWeight(5)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),

            // Right: Reps dial wheel
            Expanded(
              child: Column(
                children: [
                  const Text(
                    'REPS SELECTOR',
                    style: TextStyle(color: KColor.textMuted, fontSize: 8.5, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _StepButton(label: '-5', onTap: () => _adjustReps(-5)),
                      const SizedBox(width: 4),
                      _StepButton(label: '-1', onTap: () => _adjustReps(-1)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _Kynetix3DWheelPicker<int>(
                    controller: _repsController,
                    items: _repsOptions,
                    selectedItem: widget.selectedReps,
                    labelBuilder: (r) => '$r reps',
                    onSelectedItemChanged: _onRepsWheelChanged,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _StepButton(label: '+1', onTap: () => _adjustReps(1)),
                      const SizedBox(width: 4),
                      _StepButton(label: '+5', onTap: () => _adjustReps(5)),
                    ],
                  ),
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
          children: [
            // Left: External load selector
            Expanded(
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF22C55E).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'BODYWEIGHT',
                          style: TextStyle(color: KColor.green, fontSize: 8.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        '+ LOAD (KG)',
                        style: TextStyle(color: KColor.textMuted, fontSize: 8.5, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _StepButton(label: '-5', onTap: () => _adjustExternalLoad(-5)),
                      const SizedBox(width: 4),
                      _StepButton(label: '-2.5', onTap: () => _adjustExternalLoad(-2.5)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 148,
                    decoration: BoxDecoration(
                      color: const Color(0xFF141624),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: KColor.border, width: 0.5),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            currentExternal > 0 ? '+${currentExternal.toStringAsFixed(1)} kg' : 'BODYWEIGHT ONLY',
                            style: TextStyle(
                              color: currentExternal > 0 ? const Color(0xFF60A5FA) : KColor.green,
                              fontSize: currentExternal > 0 ? 16 : 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (currentExternal > 0)
                            const Text(
                              'External Load',
                              style: TextStyle(color: KColor.textMuted, fontSize: 10),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _StepButton(label: '+2.5', onTap: () => _adjustExternalLoad(2.5)),
                      const SizedBox(width: 4),
                      _StepButton(label: '+5', onTap: () => _adjustExternalLoad(5)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),

            // Right: Reps dial wheel
            Expanded(
              child: Column(
                children: [
                  const Text(
                    'REPS SELECTOR',
                    style: TextStyle(color: KColor.textMuted, fontSize: 8.5, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _StepButton(label: '-5', onTap: () => _adjustReps(-5)),
                      const SizedBox(width: 4),
                      _StepButton(label: '-1', onTap: () => _adjustReps(-1)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _Kynetix3DWheelPicker<int>(
                    controller: _repsController,
                    items: _repsOptions,
                    selectedItem: widget.selectedReps,
                    labelBuilder: (r) => '$r reps',
                    onSelectedItemChanged: _onRepsWheelChanged,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _StepButton(label: '+1', onTap: () => _adjustReps(1)),
                      const SizedBox(width: 4),
                      _StepButton(label: '+5', onTap: () => _adjustReps(5)),
                    ],
                  ),
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            // Left: Live Hold Stopwatch Button
            Expanded(
              child: Column(
                children: [
                  const Text(
                    'HOLD STOPWATCH',
                    style: TextStyle(color: KColor.textMuted, fontSize: 8.5, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _toggleStopwatch,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      height: 154,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: _isStopwatchRunning
                            ? const Color(0xFFEF4444).withValues(alpha: 0.12)
                            : const Color(0xFF141624),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _isStopwatchRunning ? const Color(0xFFEF4444) : KColor.border,
                          width: _isStopwatchRunning ? 1.5 : 0.5,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isStopwatchRunning ? Icons.stop_circle_rounded : Icons.play_circle_fill_rounded,
                            size: 38,
                            color: _isStopwatchRunning ? const Color(0xFFEF4444) : KColor.green,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _isStopwatchRunning
                                ? '${(_stopwatchElapsedSeconds ~/ 60).toString().padLeft(2, '0')}:${(_stopwatchElapsedSeconds % 60).toString().padLeft(2, '0')}'
                                : 'START TIMER',
                            style: TextStyle(
                              color: _isStopwatchRunning ? Colors.white : KColor.green,
                              fontSize: _isStopwatchRunning ? 20 : 12,
                              fontWeight: FontWeight.bold,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _isStopwatchRunning ? 'Tap to stop & record' : 'Live stopwatch',
                            style: const TextStyle(color: KColor.textMuted, fontSize: 9.5),
                          ),
                        ],
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
                  const Text(
                    'TARGET DURATION',
                    style: TextStyle(color: KColor.textMuted, fontSize: 8.5, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _StepButton(label: '-15s', onTap: () => _adjustDuration(-15)),
                      const SizedBox(width: 4),
                      _StepButton(label: '-5s', onTap: () => _adjustDuration(-5)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 100,
                    decoration: BoxDecoration(
                      color: const Color(0xFF141624),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: KColor.border, width: 0.5),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            durStr,
                            style: const TextStyle(
                              color: KColor.green,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          Text(
                            '$curDuration seconds',
                            style: const TextStyle(color: KColor.textMuted, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _StepButton(label: '+5s', onTap: () => _adjustDuration(5)),
                      const SizedBox(width: 4),
                      _StepButton(label: '+15s', onTap: () => _adjustDuration(15)),
                    ],
                  ),
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
          children: [
            // Left: Duration
            Expanded(
              child: Column(
                children: [
                  const Text('DURATION', style: TextStyle(color: KColor.textMuted, fontSize: 8.5, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _StepButton(label: '-5m', onTap: () => _adjustDuration(-300)),
                      const SizedBox(width: 4),
                      _StepButton(label: '-1m', onTap: () => _adjustDuration(-60)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 100,
                    decoration: BoxDecoration(
                      color: const Color(0xFF141624),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: KColor.border, width: 0.5),
                    ),
                    child: Center(
                      child: Text(
                        '${curDuration ~/ 60}m ${(curDuration % 60).toString().padLeft(2, '0')}s',
                        style: const TextStyle(color: KColor.green, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _StepButton(label: '+1m', onTap: () => _adjustDuration(60)),
                      const SizedBox(width: 4),
                      _StepButton(label: '+5m', onTap: () => _adjustDuration(300)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),

            // Right: Distance
            Expanded(
              child: Column(
                children: [
                  const Text('DISTANCE', style: TextStyle(color: KColor.textMuted, fontSize: 8.5, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _StepButton(label: '-500m', onTap: () => _adjustDistance(-500)),
                      const SizedBox(width: 4),
                      _StepButton(label: '-100m', onTap: () => _adjustDistance(-100)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 100,
                    decoration: BoxDecoration(
                      color: const Color(0xFF141624),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: KColor.border, width: 0.5),
                    ),
                    child: Center(
                      child: Text(
                        curMeters >= 1000
                            ? '${(curMeters / 1000).toStringAsFixed(2)} km'
                            : '${curMeters.toStringAsFixed(0)} m',
                        style: const TextStyle(color: Color(0xFF60A5FA), fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _StepButton(label: '+100m', onTap: () => _adjustDistance(100)),
                      const SizedBox(width: 4),
                      _StepButton(label: '+500m', onTap: () => _adjustDistance(500)),
                    ],
                  ),
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
    if (idx < 0 || idx >= _weightOptions.length) return;
    final w = _weightOptions[idx];
    if (w != widget.selectedWeight) {
      _isInternalUpdating = true;
      widget.onWeightChanged(w);
      _isInternalUpdating = false;
      HapticFeedback.selectionClick();
    }
  }

  void _onRepsWheelChanged(int idx) {
    if (_isInternalUpdating) return;
    if (idx < 0 || idx >= _repsOptions.length) return;
    final r = _repsOptions[idx];
    if (r != widget.selectedReps) {
      _isInternalUpdating = true;
      widget.onRepsChanged(r);
      _isInternalUpdating = false;
      HapticFeedback.selectionClick();
    }
  }

  void _adjustWeight(double delta) {
    final next = (widget.selectedWeight + delta).clamp(0.0, 350.0);
    _isInternalUpdating = true;
    widget.onWeightChanged(next);
    _isInternalUpdating = false;
    final idx = (next / 0.5).round().clamp(0, 700);
    if (_weightController.hasClients) {
      _weightController.animateToItem(idx, duration: const Duration(milliseconds: 200), curve: Curves.easeOutCubic);
    }
    HapticFeedback.selectionClick();
  }

  void _adjustReps(int delta) {
    final next = (widget.selectedReps + delta).clamp(1, 100);
    _isInternalUpdating = true;
    widget.onRepsChanged(next);
    _isInternalUpdating = false;
    final idx = (next - 1).clamp(0, 99);
    if (_repsController.hasClients) {
      _repsController.animateToItem(idx, duration: const Duration(milliseconds: 200), curve: Curves.easeOutCubic);
    }
    HapticFeedback.selectionClick();
  }

  void _adjustExternalLoad(double delta) {
    final current = widget.externalLoadKg ?? 0.0;
    final next = (current + delta).clamp(0.0, 150.0);
    widget.onExternalLoadChanged(next);
    HapticFeedback.selectionClick();
  }

  void _adjustDuration(int deltaSeconds) {
    final cur = widget.durationSeconds ?? 60;
    final next = (cur + deltaSeconds).clamp(5, 7200);
    widget.onDurationChanged(next);
    HapticFeedback.selectionClick();
  }

  void _adjustDistance(double deltaMeters) {
    final cur = widget.distanceMeters ?? 2000.0;
    final next = (cur + deltaMeters).clamp(50.0, 50000.0);
    widget.onDistanceChanged(next);
    HapticFeedback.selectionClick();
  }
}

class _StepButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _StepButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF1B1D2E),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: KColor.border, width: 0.5),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 10.5,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

/// Premium 3D cylindrical wheel picker utilizing Flutter's native [ListWheelScrollView].
///
/// Features:
/// - Selected item centered, prominently magnified (~1.42×) with Kynetix green accent.
/// - Immediately adjacent items are progressively smaller (~0.90×, 0.52 opacity).
/// - Second-nearest items are even smaller (~0.72×, 0.22 opacity).
/// - Farther items progressively fade down to 0.04 into top/bottom cylinder depth gradients.
/// - Smooth continuous interpolation during scrolling, not only after scroll completion.
/// - Fixed-extent snapping physics with natural inertia and flings.
/// - Center framing lens with subtle green border and glassmorphic highlight.
/// - Zero heavy per-frame calculations for 60+ FPS scrolling smoothness.
class _Kynetix3DWheelPicker<T> extends StatelessWidget {
  final FixedExtentScrollController controller;
  final List<T> items;
  final T selectedItem;
  final String Function(T item) labelBuilder;
  final ValueChanged<int> onSelectedItemChanged;
  final double height;
  final double itemExtent;

  const _Kynetix3DWheelPicker({
    required this.controller,
    required this.items,
    required this.selectedItem,
    required this.labelBuilder,
    required this.onSelectedItemChanged,
    this.height = 148.0,
    this.itemExtent = 36.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF141624),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: KColor.border, width: 0.5),
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
                color: KColor.green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.symmetric(
                  horizontal: BorderSide(
                    color: KColor.green.withValues(alpha: 0.35),
                    width: 1.0,
                  ),
                ),
              ),
            ),
          ),

          // Native 3D ListWheelScrollView with cylindrical perspective & momentum physics
          ListWheelScrollView.useDelegate(
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
                final item = items[index];

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
                    // Center (0.0): ~1.42x magnification, KColor.green, 1.0 opacity, boldest weight
                    // Immediately adjacent (1.0): ~0.90x, white70, 0.52 opacity, medium bold
                    // Second-nearest (2.0): ~0.72x, muted slate, 0.22 opacity
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
                      textColor = Color.lerp(const Color(0xFF94A3B8), KColor.green, smoothT)!;
                      fontWeight = smoothT > 0.5 ? FontWeight.w900 : FontWeight.w700;
                    } else if (absDelta <= 2.0) {
                      final t = (2.0 - absDelta).clamp(0.0, 1.0);
                      final smoothT = Curves.easeOutCubic.transform(t);
                      scale = 0.72 + (0.90 - 0.72) * smoothT;
                      opacity = (0.22 + (0.52 - 0.22) * smoothT).clamp(0.0, 1.0);
                      textColor = Color.lerp(const Color(0xFF64748B), const Color(0xFF94A3B8), smoothT)!;
                      fontWeight = FontWeight.w600;
                    } else {
                      final t = (3.0 - absDelta).clamp(0.0, 1.0);
                      scale = 0.58 + (0.72 - 0.58) * t;
                      opacity = (0.04 + (0.22 - 0.04) * t).clamp(0.0, 1.0);
                      textColor = const Color(0xFF64748B);
                      fontWeight = FontWeight.w500;
                    }

                    return Center(
                      child: Opacity(
                        opacity: opacity,
                        child: Transform.scale(
                          scale: scale,
                          child: Text(
                            labelBuilder(item),
                            style: TextStyle(
                              color: textColor,
                              fontSize: 13.5,
                              fontWeight: fontWeight,
                              letterSpacing: absDelta < 0.4 ? 0.2 : 0.0,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
              childCount: items.length,
            ),
          ),

          // Top cylinder depth fade
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 32,
            child: IgnorePointer(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFF141624),
                      Colors.transparent,
                    ],
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
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Color(0xFF141624),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
