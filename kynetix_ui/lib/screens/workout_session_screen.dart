import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_theme.dart';
import '../models/workout_split.dart';
import '../models/workout_session.dart';
import '../models/day_log.dart';
import '../services/workout_service.dart';
import '../services/persistence_service.dart';
import 'workout_setup_screen.dart' show showCreateCustomExerciseSheet;

// ─── WorkoutSessionScreen ─────────────────────────────────────────────────────
//
// Flagship Workout Session Screen - Redesigned from first principles.
//
// Key Features:
//   1. Evolving Radial Gradient background based on session progress.
//   2. Pinned horizontal Exercise Progress Rail with circular status indicators.
//   3. Massive Exercise Hero detailing previous, best, current, and projected targets.
//   4. Interactive Muscle Silhouette highlight painter and execution cues.
//   5. One-Hand Stepper Console for weight/reps adjustments and RPE segmented control.
//   6. Floating Reward particles (+1 Set, +Vol) spawned dynamically.
//   7. Confetti overlay celebrations and achievement banners for Personal Records (PRs).
//   8. Full-screen custom Game Completion Dashboard with sharing card and score stats.

class WorkoutSessionScreen extends StatefulWidget {
  final SplitDay splitDay;
  final DateTime date;
  final WorkoutSession? previousSession;
  final bool wasManuallySelected;
  final WorkoutSession? draftSession;

  const WorkoutSessionScreen({
    super.key,
    required this.splitDay,
    required this.date,
    this.previousSession,
    this.wasManuallySelected = false,
    this.draftSession,
  });

  @override
  State<WorkoutSessionScreen> createState() => _WorkoutSessionScreenState();
}

class _WorkoutSessionScreenState extends State<WorkoutSessionScreen> {
  int _selectedIndex = 0;
  bool _showRpe = true;
  bool _isSaving = false;
  bool _isDiscarding = false;
  SetType _selectedSetType = SetType.normal;

  // Controllers pool keyed by exercise id
  final Map<String, TextEditingController> _weightCtrl = {};
  final Map<String, TextEditingController> _repsCtrl = {};
  final Map<String, TextEditingController> _rpeCtrl = {};

  // Current session data: exercise id → list of sets
  final Map<String, List<SetEntry>> _sets = {};
  late List<Exercise> _sessionExercises;

  final _service = WorkoutService.instance;
  late final DateTime _startTime;

  // Floating text reward particle tracker
  final List<_FloatingTextData> _floatingTexts = [];

  // PR Confetti & Celebration State
  bool _showPrConfetti = false;
  String _prCelebrationMsg = '';
  bool _showCompletionScreen = false;
  late WorkoutSession _completedSessionSummary;

  // Exercise Complete Banner State
  bool _showExerciseCompleteBanner = false;
  String _completedExerciseName = '';

  @override
  void initState() {
    super.initState();
    _startTime = widget.draftSession?.date ?? DateTime.now();

    final draft = widget.draftSession;
    _sessionExercises = draft != null 
        ? draft.entries.map((e) => e.exercise).toList()
        : List.of(widget.splitDay.exercises);
        
    for (final ex in _sessionExercises) {
      _weightCtrl[ex.id] = TextEditingController();
      _repsCtrl[ex.id] = TextEditingController();
      _rpeCtrl[ex.id] = TextEditingController();
      
      if (draft != null) {
        final matchingEntry = draft.entries.where((e) => e.exercise.id == ex.id).firstOrNull;
        _sets[ex.id] = matchingEntry?.sets.toList() ?? [];
      } else {
        _sets[ex.id] = [];
      }

      // Pre-fill weight and reps from last session
      final lastEntry = _service.lastEntryFor(ex.id, widget.splitDay.name);
      final lastTop = lastEntry?.topSet;
      if (lastTop != null) {
        _weightCtrl[ex.id]!.text = lastTop.weight.toStringAsFixed(
          lastTop.weight == lastTop.weight.truncateToDouble() ? 0 : 1,
        );
        _repsCtrl[ex.id]!.text = lastTop.reps.toString();
      } else {
        _weightCtrl[ex.id]!.text = '40';
        _repsCtrl[ex.id]!.text = '10';
      }
    }
  }

  @override
  void dispose() {
    for (final c in [
      ..._weightCtrl.values,
      ..._repsCtrl.values,
      ..._rpeCtrl.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Getters ──────────────────────────────────────────────────────────────

  Exercise get _currentExercise => _sessionExercises[_selectedIndex];
  List<SetEntry> get _currentSets => _sets[_currentExercise.id] ?? [];
  int get _totalSets => _sets.values.fold(0, (sum, sets) => sum + sets.length);

  double get _totalVolume {
    double vol = 0.0;
    _sets.forEach((_, list) {
      for (final s in list) {
        vol += s.volume;
      }
    });
    return vol;
  }

  double get _completionProgress {
    if (_sessionExercises.isEmpty) return 0.0;
    final completedCount = _sessionExercises.where((ex) => (_sets[ex.id] ?? []).isNotEmpty).length;
    return completedCount / _sessionExercises.length;
  }

  // ── Workout Score System ─────────────────────────────────────────────────

  int get _liveWorkoutScore {
    if (_sessionExercises.isEmpty) return 0;
    
    // 1. Completion of exercises (up to 30 points)
    final completedCount = _sessionExercises.where((ex) => (_sets[ex.id] ?? []).isNotEmpty).length;
    final completionScore = (completedCount / _sessionExercises.length) * 30;
    
    // 2. Volume score (up to 30 points)
    final currentVolume = _totalVolume;
    final lastVolume = widget.previousSession?.totalVolume ?? 2000.0;
    final volumeScore = lastVolume > 0 ? (currentVolume / lastVolume * 30).clamp(0.0, 30.0) : 15.0;
    
    // 3. Set completion score (up to 25 points)
    double targetSetsScore = 0.0;
    for (final ex in _sessionExercises) {
      final logged = (_sets[ex.id] ?? []).length;
      targetSetsScore += (logged / 3.0).clamp(0.0, 1.0);
    }
    final setsScore = _sessionExercises.isNotEmpty ? (targetSetsScore / _sessionExercises.length) * 25 : 0.0;
    
    // 4. PRs score (up to 15 points)
    int prCount = 0;
    _sets.forEach((exId, list) {
      for (final s in list) {
        final previousBest = _service.bestSetBefore(exId, widget.date);
        if (previousBest != null && s.estimatedOneRepMax > previousBest.estimatedOneRepMax + 0.01) {
          prCount++;
        }
      }
    });
    final prScore = (prCount * 5.0).clamp(0.0, 15.0);
    
    return (completionScore + volumeScore + setsScore + prScore).round().clamp(0, 100);
  }

  // ── Logging Operations ───────────────────────────────────────────────────

  void _addSet() {
    final exId = _currentExercise.id;
    final w = double.tryParse(_weightCtrl[exId]?.text.trim() ?? '');
    final r = int.tryParse(_repsCtrl[exId]?.text.trim() ?? '');
    final rpe = double.tryParse(_rpeCtrl[exId]?.text.trim() ?? '');

    if (w == null || w <= 0 || r == null || r <= 0) {
      _showSnack('Enter valid weight and reps.');
      return;
    }

    final newSet = SetEntry(weight: w, reps: r, rpe: rpe, setType: _selectedSetType);

    // Check for PR milestone
    final previousBest = _service.bestSetBefore(exId, widget.date);
    final isPr = previousBest == null || newSet.estimatedOneRepMax > previousBest.estimatedOneRepMax + 0.01;

    final initialCount = _currentSets.length;

    setState(() {
      _sets[exId]!.add(newSet);
    });

    // Spawn rewards particles
    _spawnFloatingText('+1 Set\n+${(w * r).toStringAsFixed(0)} kg');
    HapticFeedback.mediumImpact();

    // Trigger exercise completion check
    if (initialCount + 1 == 3) {
      HapticFeedback.heavyImpact();
      _triggerExerciseCompleteCelebration(_currentExercise.name);
    }

    // Trigger PR overlay celebration
    if (isPr) {
      HapticFeedback.heavyImpact();
      setState(() {
        _showPrConfetti = true;
        _prCelebrationMsg = '🏆 New Personal Record!\n${w.toStringAsFixed(w == w.truncateToDouble() ? 0 : 1)} kg × $r reps\ne1RM: ${newSet.estimatedOneRepMax.toStringAsFixed(1)} kg';
      });
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) {
          setState(() => _showPrConfetti = false);
        }
      });
    }
  }

  void _adjustWeight(double amount) {
    HapticFeedback.selectionClick();
    final exId = _currentExercise.id;
    final ctrl = _weightCtrl[exId]!;
    double current = double.tryParse(ctrl.text.trim()) ?? 0.0;
    current = max(0.0, current + amount);
    setState(() {
      ctrl.text = current.toStringAsFixed(current == current.truncateToDouble() ? 0 : 1);
    });
  }

  void _adjustReps(int amount) {
    HapticFeedback.selectionClick();
    final exId = _currentExercise.id;
    final ctrl = _repsCtrl[exId]!;
    int current = int.tryParse(ctrl.text.trim()) ?? 0;
    current = max(0, current + amount);
    setState(() {
      ctrl.text = current.toString();
    });
  }

  void _duplicateLastSet() {
    final exId = _currentExercise.id;
    final sets = _sets[exId];
    if (sets == null || sets.isEmpty) return;
    final last = sets.last;
    
    setState(() {
      sets.add(
        SetEntry(
          weight: last.weight,
          reps: last.reps,
          rpe: last.rpe,
          setType: last.setType,
        ),
      );
    });
    _spawnFloatingText('+1 Set\n+${last.volume.toStringAsFixed(0)} kg');
    HapticFeedback.lightImpact();
  }

  Future<void> _addExerciseToSession() async {
    final currentIds = _sessionExercises.map((e) => e.id).toSet();
    final available = _service.allExercises
        .where((e) => !currentIds.contains(e.id))
        .toList();
    
    final picked = await showModalBottomSheet<Exercise>(
      context: context,
      backgroundColor: const Color(0xFF1E1E2C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _SessionExercisePickerSheet(exercises: available),
    );

    if (!mounted || picked == null) return;
    
    setState(() {
      _sessionExercises.add(picked);
      _weightCtrl[picked.id] = TextEditingController(text: '40');
      _repsCtrl[picked.id] = TextEditingController(text: '10');
      _rpeCtrl[picked.id] = TextEditingController();
      _sets[picked.id] = [];
      _selectedIndex = _sessionExercises.length - 1;
    });
  }

  Future<void> _removeExerciseFromSession(int index) async {
    if (index < 0 || index >= _sessionExercises.length) return;
    final ex = _sessionExercises[index];
    final hasSets = (_sets[ex.id] ?? []).isNotEmpty;

    if (hasSets) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2C),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Remove exercise?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          content: Text(
            'You already logged sets for "${ex.name}". Removing it will discard those sets for today.',
            style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF9CA3AF))),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Remove', style: TextStyle(color: Color(0xFFF87171), fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() {
      _sessionExercises.removeAt(index);
      _sets.remove(ex.id);
      _weightCtrl.remove(ex.id)?.dispose();
      _repsCtrl.remove(ex.id)?.dispose();
      _rpeCtrl.remove(ex.id)?.dispose();
      if (_selectedIndex >= _sessionExercises.length) {
        _selectedIndex = (_sessionExercises.length - 1).clamp(0, double.maxFinite.toInt());
      }
    });
  }

  void _removeSet(String exId, int index) {
    setState(() => _sets[exId]!.removeAt(index));
    HapticFeedback.selectionClick();
  }

  // ── Success Flow & Persistence ───────────────────────────────────────────

  Future<void> _finish() async {
    if (_totalSets == 0) {
      _showSnack('Log at least one set before finishing.');
      return;
    }

    setState(() => _isSaving = true);

    final entries = _sessionExercises
        .where((ex) => (_sets[ex.id] ?? []).isNotEmpty)
        .map((ex) => ExerciseEntry(exercise: ex, sets: _sets[ex.id]!))
        .toList();

    final session = WorkoutSession(
      id: 'ws_${DateTime.now().millisecondsSinceEpoch}',
      date: widget.date,
      splitDayName: widget.splitDay.name,
      splitDayWeekday: widget.splitDay.weekday == 0 ? null : widget.splitDay.weekday,
      wasManuallySelected: widget.wasManuallySelected,
      entries: entries,
    );

    await _service.saveSession(session);

    // Save logs integration
    final log = logFor(widget.date);
    if (log.gymDay?.didGym != true) {
      log.gymDay = const GymDay(didGym: true);
      await PersistenceService.saveDayLogs();
    }

    setState(() {
      _isSaving = false;
      _completedSessionSummary = session;
      _showCompletionScreen = true;
    });
    HapticFeedback.heavyImpact();
  }

  void _saveDraftState() {
    if (_isSaving || _isDiscarding || _totalSets == 0) return;
    final entries = _sessionExercises
        .where((ex) => (_sets[ex.id] ?? []).isNotEmpty)
        .map((ex) => ExerciseEntry(exercise: ex, sets: _sets[ex.id]!))
        .toList();
    if (entries.isEmpty) return;

    final draft = WorkoutSession(
      id: widget.draftSession?.id ?? 'ws_draft_${DateTime.now().millisecondsSinceEpoch}',
      date: widget.date,
      splitDayName: widget.splitDay.name,
      splitDayWeekday: widget.splitDay.weekday == 0 ? null : widget.splitDay.weekday,
      wasManuallySelected: widget.wasManuallySelected,
      entries: entries,
    );
    _service.saveDraftSession(draft);
  }

  Future<void> _confirmDiscard() async {
    if (_totalSets == 0) {
      Navigator.of(context).pop();
      return;
    }
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Pause Workout?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Do you want to save this as a draft and resume later, or discard it entirely?',
          style: TextStyle(color: Color(0xFF9CA3AF)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('cancel'),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF9CA3AF))),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('discard'),
            child: const Text('Discard', style: TextStyle(color: Color(0xFFF87171))),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('save'),
            child: const Text('Save & Leave', style: TextStyle(color: Color(0xFF52B788))),
          ),
        ],
      ),
    );
    if (!mounted || result == null || result == 'cancel') return;

    if (result == 'discard') {
      _isDiscarding = true;
      await _service.clearDraftSession();
      if (mounted) Navigator.of(context).pop();
    } else if (result == 'save') {
      _saveDraftState();
      Navigator.of(context).pop();
    }
  }

  void _spawnFloatingText(String text) {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    setState(() {
      _floatingTexts.add(_FloatingTextData(id: id, text: text));
    });
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) {
        setState(() => _floatingTexts.removeWhere((t) => t.id == id));
      }
    });
  }

  void _triggerExerciseCompleteCelebration(String name) {
    setState(() {
      _completedExerciseName = name;
      _showExerciseCompleteBanner = true;
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _showExerciseCompleteBanner = false);
      }
    });
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF1E1E2C),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _openHistory(Exercise ex) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _ExerciseHistorySheet(
        exercise: ex,
        splitDayName: widget.splitDay.name,
      ),
    );
  }

  // ── Build Main Screen Layout ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final progress = _completionProgress;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _confirmDiscard();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F0F1A),
        body: Stack(
          children: [
            // Evolving background gradients
            Positioned.fill(
              child: AnimatedContainer(
                duration: const Duration(seconds: 1),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: progress < 0.3
                        ? [const Color(0xFF0F0F1A), const Color(0xFF131326)]
                        : progress < 0.7
                            ? [const Color(0xFF0F1520), const Color(0xFF132230)]
                            : [const Color(0xFF0F1B1A), const Color(0xFF132D27)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),

            // Pulsing radial glow elements
            Positioned(
              top: -100,
              right: -100,
              child: AnimatedContainer(
                duration: const Duration(seconds: 1),
                width: 350,
                height: 350,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: progress < 0.3
                          ? const Color(0xFF4C1D95).withValues(alpha: 0.12)
                          : progress < 0.7
                              ? const Color(0xFF2563EB).withValues(alpha: 0.12)
                              : const Color(0xFF10B981).withValues(alpha: 0.12),
                      blurRadius: 100,
                      spreadRadius: 50,
                    ),
                  ],
                ),
              ),
            ),

            // Main Contents
            SafeArea(
              child: Column(
                children: [
                  _buildSessionAppBar(),
                  _buildExerciseProgressRail(),
                  Expanded(
                    child: RepaintBoundary(
                      child: _buildMainWorkoutBody(),
                    ),
                  ),
                ],
              ),
            ),

            // Floating rewards particle layer
            _buildFloatingTextOverlay(),

            // Exercise complete pop banner
            if (_showExerciseCompleteBanner)
              _buildExerciseCompleteBanner(),

            // Confetti and PR Celebration Overlay
            if (_showPrConfetti)
              _buildPRCelebrationOverlay(),

            // Fullscreen Game-like completion overlay
            if (_showCompletionScreen)
              _WorkoutCompletionOverlay(
                session: _completedSessionSummary,
                previousSession: widget.previousSession,
                score: _liveWorkoutScore,
                duration: DateTime.now().difference(_startTime),
                onDone: () => Navigator.of(context).pop(true),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionAppBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white, size: 24),
            onPressed: _confirmDiscard,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.splitDay.name.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
                Row(
                  children: [
                    _LiveTimerWidget(startedAt: _startTime),
                    const SizedBox(width: 6),
                    const Text('•', style: TextStyle(color: KColor.textMuted)),
                    const SizedBox(width: 6),
                    Text(
                      '$_totalSets sets',
                      style: const TextStyle(color: KColor.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(width: 6),
                    const Text('•', style: TextStyle(color: KColor.textMuted)),
                    const SizedBox(width: 6),
                    Text(
                      '${_totalVolume.toStringAsFixed(0)} kg',
                      style: const TextStyle(color: KColor.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Game-like score display widget
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2C).withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: KColor.border, width: 0.5),
            ),
            child: Row(
              children: [
                const Icon(Icons.bolt_rounded, color: KColor.amber, size: 16),
                const SizedBox(width: 4),
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: _liveWorkoutScore.toDouble()),
                  duration: const Duration(milliseconds: 500),
                  builder: (context, score, child) {
                    return Text(
                      'SCORE: ${score.toInt()}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: _isSaving ? null : _finish,
            style: ElevatedButton.styleFrom(
              backgroundColor: KColor.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Finish', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  // ── Pinned Exercise Progress Rail ─────────────────────────────────────────

  Widget _buildExerciseProgressRail() {
    return Container(
      height: 62,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF141624).withValues(alpha: 0.6),
        border: const Border.symmetric(horizontal: BorderSide(color: Color(0xFF2E2E3E), width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _sessionExercises.length,
              itemBuilder: (context, i) {
                final ex = _sessionExercises[i];
                final isActive = i == _selectedIndex;
                final loggedSets = _sets[ex.id]?.length ?? 0;
                final targetSets = 3; // default target sets planned
                final completionRatio = (loggedSets / targetSets).clamp(0.0, 1.0);
                final isDone = loggedSets >= targetSets;

                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedIndex = i);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: isActive ? KColor.surface : const Color(0xFF13131F),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isActive 
                            ? KColor.green 
                            : (loggedSets > 0 ? KColor.green.withValues(alpha: 0.3) : KColor.border),
                        width: isActive ? 1.5 : 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Completion ring indicator
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: isDone
                              ? const Icon(Icons.check_circle_rounded, color: KColor.green, size: 14)
                              : CircularProgressIndicator(
                                  value: completionRatio,
                                  strokeWidth: 2,
                                  backgroundColor: const Color(0xFF2E2E3E),
                                  valueColor: const AlwaysStoppedAnimation<Color>(KColor.green),
                                ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          ex.name,
                          style: TextStyle(
                            color: isActive ? Colors.white : KColor.textSecondary,
                            fontWeight: isActive ? FontWeight.w900 : FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => _removeExerciseFromSession(i),
                          child: Icon(
                            Icons.close_rounded,
                            size: 12,
                            color: isActive ? KColor.textSecondary : Colors.transparent,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: KColor.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: KColor.green.withValues(alpha: 0.3), width: 0.5),
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.add_rounded, color: KColor.green, size: 20),
                onPressed: _addExerciseToSession,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Main Workout Dashboard Contents ───────────────────────────────────────

  Widget _buildMainWorkoutBody() {
    if (_sessionExercises.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.fitness_center_rounded, color: KColor.textMuted, size: 48),
            const SizedBox(height: 12),
            const Text('No exercises in this session', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('Tap "+" in the rail to add one.', style: TextStyle(color: KColor.textMuted)),
          ],
        ),
      );
    }

    final ex = _currentExercise;
    final hint = _service.progressionHint(_service.lastEntryFor(ex.id, widget.splitDay.name), ex);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      children: [
        _buildExerciseHeroSection(ex),
        const SizedBox(height: 12),
        _buildMuscleVisualizationCard(ex),
        const SizedBox(height: 14),
        _buildSmartCoachingBanner(hint),
        const SizedBox(height: 14),
        _buildSetTypeAndRpeConsole(ex),
        const SizedBox(height: 14),
        _buildSetLoggingConsole(ex),
        const SizedBox(height: 20),
        _buildLoggedSetsCardsSection(ex),
      ],
    );
  }

  // ── Massive Exercise Hero Section ─────────────────────────────────────────

  Widget _buildExerciseHeroSection(Exercise ex) {
    final lastEntry = _service.lastEntryFor(ex.id, widget.splitDay.name);
    final lastStr = lastEntry != null ? _service.lastSessionDisplay(lastEntry).replaceAll('Last: ', '') : 'None';
    final bestVal = _service.bestSetEver(ex.id);
    final bestStr = bestVal != null 
        ? '${bestVal.weight.toStringAsFixed(bestVal.weight == bestVal.weight.truncateToDouble() ? 0 : 1)}kg × ${bestVal.reps}' 
        : 'None';
    final currentStr = _currentSets.isNotEmpty 
        ? _currentSets.map((s) => '${s.weight.toStringAsFixed(s.weight == s.weight.truncateToDouble() ? 0 : 1)}×${s.reps}').join(', ')
        : 'None';

    // Projected target based on last session top set or target reps
    String projectedStr = 'Pending';
    final lastTop = lastEntry?.topSet;
    if (lastTop != null) {
      final nextWeight = lastTop.weight + (ex.type == ExerciseType.barbellCompound ? 2.5 : 2.0);
      projectedStr = '${nextWeight.toStringAsFixed(nextWeight == nextWeight.truncateToDouble() ? 0 : 1)}kg × ${ex.targetRepMin}';
    } else {
      projectedStr = '42.5kg × ${ex.targetRepMin}';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KColor.surface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: KColor.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ex.name,
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                  ),
                  Text(
                    '${ex.muscleGroup} • Target Range: ${ex.repRangeLabel}',
                    style: const TextStyle(color: KColor.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.history_rounded, color: KColor.textMuted),
                onPressed: () => _openHistory(ex),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 4-Column stats grid
          Row(
            children: [
              _buildHeroStatCol('LAST WORKOUT', lastStr, KColor.textSecondary),
              _buildHeroStatCol('BEST EVER', bestStr, KColor.amber),
              _buildHeroStatCol('CURRENT', currentStr, KColor.green),
              _buildHeroStatCol('PROJECTED', projectedStr, KColor.blue),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroStatCol(String title, String val, Color highlight) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: KColor.textMuted, fontSize: 8.5, fontWeight: FontWeight.bold, letterSpacing: 0.4)),
          const SizedBox(height: 4),
          Text(
            val,
            style: TextStyle(color: highlight, fontSize: 12, fontWeight: FontWeight.bold),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ── Exercise Custom Pain Highlight Card ───────────────────────────────────

  Widget _buildMuscleVisualizationCard(Exercise ex) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF141624).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: KColor.border, width: 0.5),
      ),
      child: Row(
        children: [
          CustomPaint(
            size: const Size(40, 56),
            painter: _MuscleHighlightPainter(ex.muscleGroup),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('FORM CUE', style: TextStyle(color: KColor.textMuted, fontSize: 8.5, fontWeight: FontWeight.bold)),
                const SizedBox(height: 3),
                Text(
                  ex.notes?.trim().isNotEmpty == true 
                      ? ex.notes!.trim() 
                      : 'Control the eccentric phase and squeeze at the peak contraction.',
                  style: const TextStyle(color: Colors.white, fontSize: 11.5, height: 1.3, fontStyle: FontStyle.italic),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Smart Coaching Banners ───────────────────────────────────────────────

  Widget _buildSmartCoachingBanner(String hint) {
    if (hint.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFB347).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFB347).withValues(alpha: 0.2), width: 0.8),
      ),
      child: Row(
        children: [
          const Icon(Icons.psychology_alt_rounded, color: Color(0xFFFFB347), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hint,
              style: const TextStyle(color: Color(0xFFFFB347), fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  // ── Segmented Control Console ─────────────────────────────────────────────

  Widget _buildSetTypeAndRpeConsole(Exercise ex) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SetTypeSelector(
          selected: _selectedSetType,
          onChanged: (v) => setState(() => _selectedSetType = v),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('INTENSITY LOGGING', style: TextStyle(color: KColor.textMuted, fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 0.4)),
            GestureDetector(
              onTap: () => setState(() => _showRpe = !_showRpe),
              child: Text(
                _showRpe ? 'Hide RPE scale' : 'Show RPE scale',
                style: const TextStyle(color: KColor.blue, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        if (_showRpe) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: KColor.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: KColor.border, width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('RPE scale selection', style: TextStyle(color: KColor.textMuted, fontSize: 9, fontWeight: FontWeight.bold)),
                    Text(
                      _rpeCtrl[ex.id]!.text.isEmpty 
                          ? 'Tap to select RPE' 
                          : 'RPE ${_rpeCtrl[ex.id]!.text} — ${_rpeDescription(double.tryParse(_rpeCtrl[ex.id]!.text) ?? 8)}',
                      style: const TextStyle(color: KColor.green, fontSize: 10.5, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [6.0, 7.0, 8.0, 8.5, 9.0, 9.5, 10.0].map((val) {
                    final selected = _rpeCtrl[ex.id]!.text == val.toString();
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1.5),
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _rpeCtrl[ex.id]!.text = val.toString();
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: selected ? KColor.green : const Color(0xFF13131F),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: selected ? KColor.green : KColor.border,
                                width: 0.5,
                              ),
                            ),
                            child: Text(
                              val.toString().replaceAll('.0', ''),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: selected ? Colors.white : KColor.textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ]
      ],
    );
  }

  // ── Steppers Set Logging Console (Tactile Increment Systems) ──────────────

  Widget _buildSetLoggingConsole(Exercise ex) {
    return Row(
      children: [
        // Weight Stepper Console
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: KColor.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: KColor.border, width: 0.5),
            ),
            child: Column(
              children: [
                const Text('WEIGHT (KG)', style: TextStyle(color: KColor.textMuted, fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 0.4)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _StepperBtn(label: '-5', onTap: () => _adjustWeight(-5)),
                    _StepperBtn(label: '-1', onTap: () => _adjustWeight(-1)),
                    Expanded(
                      child: TextField(
                        controller: _weightCtrl[ex.id],
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 4),
                        ),
                      ),
                    ),
                    _StepperBtn(label: '+1', onTap: () => _adjustWeight(1)),
                    _StepperBtn(label: '+5', onTap: () => _adjustWeight(5)),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Reps Stepper Console
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: KColor.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: KColor.border, width: 0.5),
            ),
            child: Column(
              children: [
                const Text('REPS', style: TextStyle(color: KColor.textMuted, fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 0.4)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _StepperBtn(label: '-5', onTap: () => _adjustReps(-5)),
                    _StepperBtn(label: '-1', onTap: () => _adjustReps(-1)),
                    Expanded(
                      child: TextField(
                        controller: _repsCtrl[ex.id],
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 4),
                        ),
                      ),
                    ),
                    _StepperBtn(label: '+1', onTap: () => _adjustReps(1)),
                    _StepperBtn(label: '+5', onTap: () => _adjustReps(5)),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Large circular CTA buttons
        Column(
          children: [
            GestureDetector(
              onTap: _addSet,
              child: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: KColor.green,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: KColor.green, blurRadius: 8, offset: Offset(0, 2)),
                  ],
                ),
                child: const Icon(Icons.add_rounded, color: Colors.white, size: 24),
              ),
            ),
            if (_currentSets.isNotEmpty) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _duplicateLastSet,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E2C),
                    shape: BoxShape.circle,
                    border: Border.all(color: KColor.border),
                  ),
                  child: const Icon(Icons.copy_rounded, color: KColor.textSecondary, size: 18),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  // ── Logged Set Cards List Section ─────────────────────────────────────────

  Widget _buildLoggedSetsCardsSection(Exercise ex) {
    final sets = _sets[ex.id] ?? [];
    if (sets.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'LOGGED SETS (${sets.length})',
              style: const TextStyle(color: KColor.textMuted, fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 0.4),
            ),
            Text(
              'Total Volume: ${sets.fold(0.0, (s, e) => s + e.volume).toStringAsFixed(0)} kg',
              style: const TextStyle(color: KColor.textSecondary, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: sets.length,
          itemBuilder: (context, i) {
            final s = sets[i];
            final previousBest = _service.bestSetBefore(ex.id, widget.date);
            final isPr = previousBest == null || s.estimatedOneRepMax > previousBest.estimatedOneRepMax + 0.01;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: KColor.surface.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isPr ? KColor.amber.withValues(alpha: 0.3) : KColor.border, width: 0.8),
              ),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: isPr ? KColor.amber.withValues(alpha: 0.15) : const Color(0xFF13131F),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        color: isPr ? KColor.amber : KColor.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '${s.weight.toStringAsFixed(s.weight == s.weight.truncateToDouble() ? 0 : 1)} kg  ×  ${s.reps} reps',
                              style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _setTypeColor(s.setType).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                s.setType.shortLabel,
                                style: TextStyle(
                                  color: _setTypeColor(s.setType),
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (s.rpe != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'RPE ${s.rpe} • ${s.volume.toStringAsFixed(0)} kg volume',
                            style: const TextStyle(color: KColor.textMuted, fontSize: 10.5),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (isPr) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: KColor.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: KColor.amber.withValues(alpha: 0.3), width: 0.5),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.workspace_premium_rounded, color: KColor.amber, size: 12),
                          SizedBox(width: 4),
                          Text('PR', style: TextStyle(color: KColor.amber, fontSize: 9, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  GestureDetector(
                    onTap: () => _removeSet(ex.id, i),
                    child: const Icon(Icons.remove_circle_rounded, color: Color(0xFF3B3B4F), size: 18),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Color _setTypeColor(SetType type) => switch (type) {
    SetType.normal => KColor.green,
    SetType.warmUp => KColor.textMuted,
    SetType.dropSet => KColor.amber,
    SetType.supersetA => KColor.blue,
    SetType.supersetB => const Color(0xFFA78BFA),
    SetType.burnout => KColor.danger,
  };

  // ── Overlay Reward Particles & PR Confetti Celebrations ───────────────────

  Widget _buildFloatingTextOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: _floatingTexts.map((data) {
            return _FloatingTextWidget(
              key: ValueKey(data.id),
              text: data.text,
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildExerciseCompleteBanner() {
    return Positioned(
      top: 80,
      left: 20,
      right: 20,
      child: IgnorePointer(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: _showExerciseCompleteBanner ? 1.0 : 0.0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E3C2C), Color(0xFF0F1B1A)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: KColor.green.withValues(alpha: 0.3), width: 1.0),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4)),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: KColor.green, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('EXERCISE COMPLETE', style: TextStyle(color: KColor.green, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                      Text(
                        'Logged all planned sets for $_completedExerciseName!',
                        style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPRCelebrationOverlay() {
    return Stack(
      children: [
        _PRConfettiOverlay(
          onFinished: () {
            setState(() => _showPrConfetti = false);
          },
        ),
        Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2C).withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: KColor.amber, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: KColor.amber.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🏆', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 12),
                const Text(
                  'PERSONAL RECORD!',
                  style: TextStyle(color: KColor.amber, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                ),
                const SizedBox(height: 14),
                Text(
                  _prCelebrationMsg,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 13.5, height: 1.45, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 18),
                ElevatedButton(
                  onPressed: () => setState(() => _showPrConfetti = false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: KColor.amber,
                    foregroundColor: const Color(0xFF0F0F1A),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  ),
                  child: const Text('Awesome!', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Live Timer Stateful Widget ─────────────────────────────────────────────

class _LiveTimerWidget extends StatefulWidget {
  final DateTime startedAt;
  const _LiveTimerWidget({required this.startedAt});

  @override
  State<_LiveTimerWidget> createState() => _LiveTimerWidgetState();
}

class _LiveTimerWidgetState extends State<_LiveTimerWidget> {
  Stream<int> _timerStream() async* {
    while (true) {
      await Future.delayed(const Duration(seconds: 1));
      yield 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _timerStream(),
      builder: (context, snapshot) {
        final now = DateTime.now();
        final diff = now.difference(widget.startedAt);
        final mins = diff.inMinutes.toString().padLeft(2, '0');
        final secs = (diff.inSeconds % 60).toString().padLeft(2, '0');
        return Text(
          '$mins:$secs',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 12,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        );
      },
    );
  }
}

// ─── Floating Particle Reward Widget ────────────────────────────────────────

class _FloatingTextData {
  final String id;
  final String text;
  const _FloatingTextData({required this.id, required this.text});
}

class _FloatingTextWidget extends StatefulWidget {
  final String text;
  const _FloatingTextWidget({required super.key, required this.text});

  @override
  State<_FloatingTextWidget> createState() => _FloatingTextWidgetState();
}

class _FloatingTextWidgetState extends State<_FloatingTextWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _position;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: 1.0), weight: 15),
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 50),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 0.0), weight: 35),
    ]).animate(_controller);

    _position = Tween<Offset>(
      begin: const Offset(0.0, 0.2),
      end: const Offset(0.0, -0.6),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Opacity(
            opacity: _opacity.value,
            child: FractionalTranslation(
              translation: _position.value,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [KColor.green, Color(0xFF1B6A47)]),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(color: KColor.green.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: Text(
                  widget.text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── PR Confetti Canvas Animation Overlay ───────────────────────────────────

class _ConfettiParticle {
  double x, y;
  double vx, vy;
  Color color;
  double size;
  double rotation;
  double rotationSpeed;

  _ConfettiParticle({
    required this.x, required this.y,
    required this.vx, required this.vy,
    required this.color, required this.size,
    required this.rotation, required this.rotationSpeed,
  });

  void update() {
    x += vx;
    y += vy;
    vy += 0.2; // gravity
    vx *= 0.98; // friction
    rotation += rotationSpeed;
  }
}

class _PRConfettiOverlay extends StatefulWidget {
  final VoidCallback onFinished;
  const _PRConfettiOverlay({required this.onFinished});

  @override
  State<_PRConfettiOverlay> createState() => _PRConfettiOverlayState();
}

class _PRConfettiOverlayState extends State<_PRConfettiOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final List<_ConfettiParticle> _particles = [];
  final Random _rand = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..addListener(_tick);

    final colors = [
      Colors.red, Colors.blue, Colors.green, Colors.yellow,
      Colors.pink, Colors.purple, Colors.orange, const Color(0xFFFFB347),
    ];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final size = MediaQuery.of(context).size;
      for (int i = 0; i < 50; i++) {
        _particles.add(_ConfettiParticle(
          x: 0,
          y: size.height * 0.8,
          vx: _rand.nextDouble() * 10 + 5,
          vy: -(_rand.nextDouble() * 15 + 10),
          color: colors[_rand.nextInt(colors.length)],
          size: _rand.nextDouble() * 8 + 6,
          rotation: _rand.nextDouble() * pi * 2,
          rotationSpeed: _rand.nextDouble() * 0.2 - 0.1,
        ));
      }
      for (int i = 0; i < 50; i++) {
        _particles.add(_ConfettiParticle(
          x: size.width,
          y: size.height * 0.8,
          vx: -(_rand.nextDouble() * 10 + 5),
          vy: -(_rand.nextDouble() * 15 + 10),
          color: colors[_rand.nextInt(colors.length)],
          size: _rand.nextDouble() * 8 + 6,
          rotation: _rand.nextDouble() * pi * 2,
          rotationSpeed: _rand.nextDouble() * 0.2 - 0.1,
        ));
      }
      _controller.forward().then((_) => widget.onFinished());
    });
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _ConfettiPainter(_particles),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiParticle> particles;
  _ConfettiPainter(this.particles);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final p in particles) {
      paint.color = p.color;
      canvas.save();
      canvas.translate(p.x, p.y);
      canvas.rotate(p.rotation);
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 1.5), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ─── Muscle Silhouette Custom Painter ──────────────────────────────────────

class _MuscleHighlightPainter extends CustomPainter {
  final String muscleGroup;
  _MuscleHighlightPainter(this.muscleGroup);

  @override
  void paint(Canvas canvas, Size size) {
    final paintBody = Paint()
      ..color = const Color(0xFF374151)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final paintActive = Paint()
      ..color = KColor.green
      ..style = PaintingStyle.fill;

    final cx = size.width / 2;
    final cy = size.height / 2;

    canvas.drawCircle(Offset(cx, cy - 18), 6, paintBody);
    canvas.drawLine(Offset(cx, cy - 12), Offset(cx, cy + 12), paintBody);
    canvas.drawLine(Offset(cx - 12, cy - 8), Offset(cx + 12, cy - 8), paintBody);
    canvas.drawLine(Offset(cx - 12, cy - 8), Offset(cx - 16, cy + 8), paintBody);
    canvas.drawLine(Offset(cx + 12, cy - 8), Offset(cx + 16, cy + 8), paintBody);
    canvas.drawLine(Offset(cx - 8, cy + 12), Offset(cx + 8, cy + 12), paintBody);
    canvas.drawLine(Offset(cx - 6, cy + 12), Offset(cx - 8, cy + 28), paintBody);
    canvas.drawLine(Offset(cx + 6, cy + 12), Offset(cx + 8, cy + 28), paintBody);

    final normalized = muscleGroup.toLowerCase();
    if (normalized.contains('chest')) {
      canvas.drawCircle(Offset(cx - 4, cy - 4), 3, paintActive);
      canvas.drawCircle(Offset(cx + 4, cy - 4), 3, paintActive);
    } else if (normalized.contains('back') || normalized.contains('lat')) {
      canvas.drawRect(Rect.fromCenter(center: Offset(cx, cy - 2), width: 8, height: 10), paintActive);
    } else if (normalized.contains('bicep') || normalized.contains('arm') || normalized.contains('tricep')) {
      canvas.drawCircle(Offset(cx - 14, cy), 3, paintActive);
      canvas.drawCircle(Offset(cx + 14, cy), 3, paintActive);
    } else if (normalized.contains('shoulder') || normalized.contains('delt')) {
      canvas.drawCircle(Offset(cx - 12, cy - 8), 3.5, paintActive);
      canvas.drawCircle(Offset(cx + 12, cy - 8), 3.5, paintActive);
    } else if (normalized.contains('leg') || normalized.contains('quad') || normalized.contains('hamstring') || normalized.contains('glute')) {
      canvas.drawCircle(Offset(cx - 7, cy + 18), 4, paintActive);
      canvas.drawCircle(Offset(cx + 7, cy + 18), 4, paintActive);
    } else if (normalized.contains('core') || normalized.contains('abs')) {
      canvas.drawCircle(Offset(cx, cy + 3), 4, paintActive);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Set Stepper Button ─────────────────────────────────────────────────────

class _StepperBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _StepperBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2C),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF3E3E50), width: 0.5),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

// ─── Set Type Selector segmented chips ──────────────────────────────────────

class _SetTypeSelector extends StatelessWidget {
  final SetType selected;
  final ValueChanged<SetType> onChanged;
  const _SetTypeSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final options = [
      SetType.normal,
      SetType.warmUp,
      SetType.dropSet,
      SetType.supersetA,
      SetType.supersetB,
      SetType.burnout,
    ];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFF141624).withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KColor.border, width: 0.5),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: options.map((type) {
            final isSelected = selected == type;
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged(type);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: isSelected ? KColor.green : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  type.label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : KColor.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ─── Exercise picker inside session bottom sheet ────────────────────────────

class _SessionExercisePickerSheet extends StatefulWidget {
  final List<Exercise> exercises;
  const _SessionExercisePickerSheet({required this.exercises});

  @override
  State<_SessionExercisePickerSheet> createState() =>
      _SessionExercisePickerSheetState();
}

class _SessionExercisePickerSheetState
    extends State<_SessionExercisePickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.exercises
        .where(
          (e) =>
              e.name.toLowerCase().contains(_query.toLowerCase()) ||
              e.muscleGroup.toLowerCase().contains(_query.toLowerCase()),
        )
        .toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search exercises...',
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF6B7280), size: 18),
                filled: true,
                fillColor: const Color(0xFF13131F),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () async {
                final navigator = Navigator.of(context);
                final ex = await showCreateCustomExerciseSheet(context);
                if (!mounted || ex == null) return;
                navigator.pop(ex);
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: KColor.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: KColor.green.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.add_rounded, color: KColor.green, size: 20),
                    SizedBox(width: 10),
                    Text(
                      '+ Add Custom Exercise',
                      style: TextStyle(color: KColor.green, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1, color: Color(0xFF2E2E3E)),
            const SizedBox(height: 4),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final ex = filtered[i];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                    title: Text(ex.name, style: const TextStyle(color: Colors.white, fontSize: 13)),
                    subtitle: Text('${ex.muscleGroup} • ${ex.repRangeLabel}', style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11.5)),
                    trailing: const Icon(Icons.add_rounded, color: KColor.green, size: 20),
                    onTap: () => Navigator.of(context).pop(ex),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Single exercise history display sheet ──────────────────────────────────

class _ExerciseHistorySheet extends StatelessWidget {
  final Exercise exercise;
  final String splitDayName;
  const _ExerciseHistorySheet({required this.exercise, required this.splitDayName});

  @override
  Widget build(BuildContext context) {
    final svc = WorkoutService.instance;
    final history = svc.historyFor(exercise.id, limit: 5);
    final best = svc.bestSetEver(exercise.id);
    final trend = svc.exerciseTrendLabel(exercise.id);
    final note = svc.exerciseProgressNote(exercise, splitDayName);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(exercise.name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                    Text(exercise.muscleGroup, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
                    const SizedBox(height: 3),
                    Text(trend, style: const TextStyle(color: KColor.green, fontSize: 11.5, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              if (best != null) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Best 1RM', style: TextStyle(color: Color(0xFF6B7280), fontSize: 10)),
                    Text('${best.estimatedOneRepMax.toStringAsFixed(1)} kg', style: const TextStyle(color: KColor.amber, fontSize: 16, fontWeight: FontWeight.w900)),
                    Text('(${best.weight.toStringAsFixed(0)}×${best.reps})', style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11)),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF13131F),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2E2E3E)),
            ),
            child: Text(note, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12.5, height: 1.35)),
          ),
          const SizedBox(height: 16),
          if (history.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('No history yet', style: TextStyle(color: Color(0xFF4B5563))),
              ),
            )
          else ...[
            for (final h in history) ...[
              _HistoryRow(date: h.date, entry: h.entry),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final DateTime date;
  final ExerciseEntry entry;
  const _HistoryRow({required this.date, required this.entry});

  @override
  Widget build(BuildContext context) {
    final dateStr = '${date.day}/${date.month}/${date.year % 100}';
    final setsStr = entry.sets
        .map((s) => '${s.weight.toStringAsFixed(s.weight == s.weight.truncateToDouble() ? 0 : 1)}×${s.reps}')
        .join(', ');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFF13131F),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2E2E3E)),
      ),
      child: Row(
        children: [
          Text(dateStr, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11.5, fontWeight: FontWeight.bold)),
          const SizedBox(width: 12),
          Expanded(child: Text(setsStr, style: const TextStyle(color: Colors.white, fontSize: 12.5))),
          Text('${entry.totalVolume.toStringAsFixed(0)} kg', style: const TextStyle(color: Color(0xFF4B5563), fontSize: 10.5)),
        ],
      ),
    );
  }
}

String _rpeDescription(double rpe) {
  if (rpe >= 10) return 'Max Effort (0 reps left)';
  if (rpe >= 9.5) return 'Hard (~0.5 reps left)';
  if (rpe >= 9) return '1 rep left';
  if (rpe >= 8.5) return '1.5 reps left';
  if (rpe >= 8) return '2 reps left';
  if (rpe >= 7.5) return '2.5 reps left';
  if (rpe >= 7) return '3 reps left';
  return 'Warm-up / Light effort';
}

// ─── Custom Fullscreen Completion Screen Dashboard ──────────────────────────

class _WorkoutCompletionOverlay extends StatefulWidget {
  final WorkoutSession session;
  final WorkoutSession? previousSession;
  final int score;
  final Duration duration;
  final VoidCallback onDone;

  const _WorkoutCompletionOverlay({
    required this.session,
    this.previousSession,
    required this.score,
    required this.duration,
    required this.onDone,
  });

  @override
  State<_WorkoutCompletionOverlay> createState() => _WorkoutCompletionOverlayState();
}

class _WorkoutCompletionOverlayState extends State<_WorkoutCompletionOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _celebrationController;
  final List<_ConfettiParticle> _confetti = [];
  final Random _rand = Random();

  @override
  void initState() {
    super.initState();
    _celebrationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..addListener(() {
        setState(() {
          for (final p in _confetti) {
            p.update();
          }
        });
      });

    final colors = [
      Colors.red, Colors.blue, Colors.green, Colors.yellow,
      Colors.pink, Colors.purple, Colors.orange, const Color(0xFFFFB347),
    ];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final size = MediaQuery.of(context).size;
      for (int i = 0; i < 60; i++) {
        _confetti.add(_ConfettiParticle(
          x: 0,
          y: size.height * 0.9,
          vx: _rand.nextDouble() * 12 + 6,
          vy: -(_rand.nextDouble() * 18 + 12),
          color: colors[_rand.nextInt(colors.length)],
          size: _rand.nextDouble() * 8 + 6,
          rotation: _rand.nextDouble() * pi * 2,
          rotationSpeed: _rand.nextDouble() * 0.2 - 0.1,
        ));
      }
      for (int i = 0; i < 60; i++) {
        _confetti.add(_ConfettiParticle(
          x: size.width,
          y: size.height * 0.9,
          vx: -(_rand.nextDouble() * 12 + 6),
          vy: -(_rand.nextDouble() * 18 + 12),
          color: colors[_rand.nextInt(colors.length)],
          size: _rand.nextDouble() * 8 + 6,
          rotation: _rand.nextDouble() * pi * 2,
          rotationSpeed: _rand.nextDouble() * 0.2 - 0.1,
        ));
      }
      _celebrationController.forward();
    });
  }

  @override
  void dispose() {
    _celebrationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final totalSets = session.totalSets;
    final totalVol = session.totalVolume;
    final minStr = '${widget.duration.inMinutes}m';
    
    // Performance delta calculations
    double deltaPct = 0.0;
    if (widget.previousSession != null) {
      final prevVol = widget.previousSession!.totalVolume;
      if (prevVol > 0) {
        deltaPct = ((totalVol - prevVol) / prevVol) * 100;
      }
    }

    final prCount = session.entries.fold(0, (sum, entry) {
      int count = 0;
      for (final s in entry.sets) {
        final prevBest = WorkoutService.instance.bestSetBefore(entry.exercise.id, session.date);
        if (prevBest == null || s.estimatedOneRepMax > prevBest.estimatedOneRepMax + 0.01) {
          count++;
        }
      }
      return sum + count;
    });

    final muscles = session.entries.map((e) => e.exercise.muscleGroup).toSet().toList();

    return Container(
      color: const Color(0xFF0F0F1A),
      child: Stack(
        children: [
          // Background glowing accents
          Positioned(
            bottom: -50,
            left: -50,
            right: -50,
            child: Container(
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: KColor.green.withValues(alpha: 0.12),
                    blurRadius: 120,
                    spreadRadius: 50,
                  ),
                ],
              ),
            ),
          ),
          
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 20),
                const Text('🔥', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 10),
                const Text(
                  'MISSION ACCOMPLISHED',
                  style: TextStyle(color: KColor.green, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1.5),
                ),
                Text(
                  session.splitDayName.toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 20),
                
                // Dashboard Share Card
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: KColor.surface,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: KColor.border, width: 1.0),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 15, offset: const Offset(0, 8)),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('KYNETIX FLAGSHIP PERFORMANCE', style: TextStyle(color: KColor.textMuted, fontSize: 8.5, fontWeight: FontWeight.bold, letterSpacing: 0.4)),
                              Text('${session.date.day}/${session.date.month}/${session.date.year}', style: const TextStyle(color: KColor.textSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 18),
                          
                          // 2x2 Stats Dashboard Grid
                          Row(
                            children: [
                              _buildMetricCol('WORKOUT SCORE', '${widget.score} / 100', KColor.amber, true),
                              _buildMetricCol('ACCUMULATED VOLUME', '${totalVol.toStringAsFixed(0)} kg', KColor.green, false),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              _buildMetricCol('SETS COMPLETED', '$totalSets sets', KColor.blue, false),
                              _buildMetricCol('SESSION DURATION', minStr, Colors.white, false),
                            ],
                          ),
                          
                          const SizedBox(height: 20),
                          const Divider(color: KColor.border, height: 1),
                          const SizedBox(height: 18),
                          
                          // Achievements Summary
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildCompletionBadge('💪 $totalSets working sets'),
                              if (prCount > 0)
                                _buildCompletionBadge('🏆 $prCount PRs Hit!'),
                              if (deltaPct > 0)
                                _buildCompletionBadge('📈 +${deltaPct.toStringAsFixed(0)}% volume'),
                            ],
                          ),
                          
                          const SizedBox(height: 20),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text('MUSCLES TRAINED', style: TextStyle(color: KColor.textMuted, fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 0.4)),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: muscles.map((m) => KChip(m)).toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                
                // Sticky CTA
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: widget.onDone,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: KColor.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Log Workout & Continue', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Confetti painter
          IgnorePointer(
            child: CustomPaint(
              size: Size.infinite,
              painter: _ConfettiPainter(_confetti),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCol(String title, String value, Color color, bool pulse) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF13131F),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: KColor.textMuted, fontSize: 8.5, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompletionBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF13131F),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}
