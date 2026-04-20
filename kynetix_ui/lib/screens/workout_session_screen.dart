import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/workout_split.dart';
import '../models/workout_session.dart';
import '../models/day_log.dart';
import '../services/workout_service.dart';
import '../services/persistence_service.dart';
import 'workout_setup_screen.dart' show showCreateCustomExerciseSheet;

// ─── WorkoutSessionScreen ─────────────────────────────────────────────────────
//
// Active workout logging. One screen per session.
//
// Layout:
//   AppBar: split day name + sets count + "Finish" button
//   Body:
//     → horizontal exercise chip tabs (with set-count badge)
//     → current exercise card:
//         previous performance line ("Last: W×R, W×R")
//         progression hint chip
//         weight + reps input row
//         optional RPE toggle
//         "Add Set" button
//         logged sets list (numbered, delete on tap)

class WorkoutSessionScreen extends StatefulWidget {
  final SplitDay splitDay;
  final DateTime date;

  /// Previous session for this split day — used for reference display.
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
  bool _showRpe = false;
  bool _isSaving = false;
  bool _isDiscarding = false;
  SetType _selectedSetType = SetType.normal;

  // Controller pool keyed by exercise id
  final Map<String, TextEditingController> _weightCtrl = {};
  final Map<String, TextEditingController> _repsCtrl = {};
  final Map<String, TextEditingController> _rpeCtrl = {};

  // Current session data: exercise id → list of sets
  final Map<String, List<SetEntry>> _sets = {};
  late List<Exercise> _sessionExercises;

  final _service = WorkoutService.instance;

  @override
  void initState() {
    super.initState();
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

      // Pre-fill weight from last session
      final lastEntry = _service.lastEntryFor(ex.id, widget.splitDay.name);
      final lastTop = lastEntry?.topSet;
      if (lastTop != null) {
        _weightCtrl[ex.id]!.text = lastTop.weight.toStringAsFixed(
          lastTop.weight == lastTop.weight.truncateToDouble() ? 0 : 1,
        );
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

  // ── Current exercise ──────────────────────────────────────────────────────

  Exercise get _currentExercise => _sessionExercises[_selectedIndex];

  List<SetEntry> get _currentSets => _sets[_currentExercise.id] ?? [];

  ExerciseEntry? _lastEntry(Exercise ex) =>
      _service.lastEntryFor(ex.id, widget.splitDay.name);

  String _lastDisplay(Exercise ex) =>
      _service.lastSessionDisplay(_lastEntry(ex));

  String _progressionHint(Exercise ex) =>
      _service.progressionHint(_lastEntry(ex), ex);

  int get _totalSets => _sets.values.fold(0, (sum, sets) => sum + sets.length);

  // ── Add / remove sets ─────────────────────────────────────────────────────

  void _addSet() {
    final exId = _currentExercise.id;
    final w = double.tryParse(_weightCtrl[exId]?.text.trim() ?? '');
    final r = int.tryParse(_repsCtrl[exId]?.text.trim() ?? '');
    final rpe = double.tryParse(_rpeCtrl[exId]?.text.trim() ?? '');

    if (w == null || w <= 0 || r == null || r <= 0) {
      _showSnack('Enter valid weight and reps.');
      return;
    }

    setState(() {
      _sets[exId]!.add(
        SetEntry(weight: w, reps: r, rpe: rpe, setType: _selectedSetType),
      );
      _repsCtrl[exId]!.clear();
      _rpeCtrl[exId]!.clear();
      // Keep weight pre-filled for fast same-weight sets
    });
    HapticFeedback.lightImpact();
  }

  void _duplicateLastSet() {
    final exId = _currentExercise.id;
    final sets = _sets[exId];
    if (sets == null || sets.isEmpty) return;
    final last = sets.last;
    setState(
      () => sets.add(
        SetEntry(
          weight: last.weight,
          reps: last.reps,
          rpe: last.rpe,
          setType: last.setType,
        ),
      ),
    );
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
    if (!mounted) return;
    if (picked == null) return;
    setState(() {
      _sessionExercises.add(picked);
      _weightCtrl[picked.id] = TextEditingController();
      _repsCtrl[picked.id] = TextEditingController();
      _rpeCtrl[picked.id] = TextEditingController();
      _sets[picked.id] = [];
      _selectedIndex = _sessionExercises.length - 1;
    });
  }

  void _reorderSessionExercise(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final exercise = _sessionExercises.removeAt(oldIndex);
      _sessionExercises.insert(newIndex, exercise);
      if (_selectedIndex == oldIndex) {
        _selectedIndex = newIndex;
      } else if (oldIndex < _selectedIndex && newIndex >= _selectedIndex) {
        _selectedIndex -= 1;
      } else if (oldIndex > _selectedIndex && newIndex <= _selectedIndex) {
        _selectedIndex += 1;
      }
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
            'You already logged sets for "${ex.name}". Removing it will discard those sets for today only — your split is unchanged.',
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

  // ── Save ──────────────────────────────────────────────────────────────────

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
      splitDayWeekday: widget.splitDay.weekday == 0
          ? null
          : widget.splitDay.weekday,
      wasManuallySelected: widget.wasManuallySelected,
      entries: entries,
    );

    await _service.saveSession(session);

    // ── Nutrition integration ────────────────────────────────────────────────
    // Mark today as a gym day so training-day calorie/protein targets apply.
    final log = logFor(widget.date);
    if (log.gymDay?.didGym != true) {
      log.gymDay = const GymDay(didGym: true);
      await PersistenceService.saveDayLogs();
    }

    setState(() => _isSaving = false);
    if (mounted) {
      await _showSuccessDialog(session);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    }
  }

  Future<void> _showSuccessDialog(WorkoutSession session) async {
    final vol = session.totalVolume;
    final previous = widget.previousSession;
    final delta = previous != null
        ? _service.compareWithPrevious(session, previous)
        : null;
    final best = session.bestSetToday;
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Workout done! 🔥',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatLine('Total sets', '${session.totalSets}'),
            _StatLine('Total volume', '${vol.toStringAsFixed(0)} kg'),
            _StatLine('Exercises', '${session.entries.length}'),
            if (best != null)
              _StatLine(
                'Best set today',
                '${best.weight.toStringAsFixed(best.weight.truncateToDouble() == best.weight ? 0 : 1)} kg × ${best.reps}',
              ),
            if (delta != null) ...[
              const SizedBox(height: 6),
              Text(
                delta.volumeLabel,
                style: TextStyle(
                  color: delta.isImprovement
                      ? const Color(0xFF52B788)
                      : const Color(0xFF9CA3AF),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (delta.exerciseDeltas.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    delta.exerciseDeltas.first.isPr
                        ? '${delta.exerciseDeltas.first.exerciseName}: new PR'
                        : '${delta.exerciseDeltas.first.exerciseName}: ${delta.exerciseDeltas.first.deltaLabel}',
                    style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 8),
            const Text(
              'Training day targets are now active.',
              style: TextStyle(color: Color(0xFF52B788), fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Done',
              style: TextStyle(
                color: Color(0xFF52B788),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
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

  // ── Exercise history sheet ─────────────────────────────────────────────────

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

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final exercises = _sessionExercises;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) _saveDraftState();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF13131F),
        appBar: AppBar(
          backgroundColor: const Color(0xFF13131F),
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: _confirmDiscard,
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.splitDay.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                '$_totalSets set${_totalSets == 1 ? "" : "s"} logged',
                style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: _isSaving ? null : _finish,
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFF2D6A4F),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Finish',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            // ── Exercise chip tabs ────────────────────────────────────────────
            _ExerciseChipBar(
              exercises: exercises,
              selectedIndex: _selectedIndex,
              setCounts: {
                for (final ex in exercises) ex.id: (_sets[ex.id]?.length ?? 0),
              },
              onSelect: (i) => setState(() => _selectedIndex = i),
              onAddExercise: _addExerciseToSession,
              onReorder: _reorderSessionExercise,
              onRemoveExercise: _removeExerciseFromSession,
            ),
            // ── Exercise body ─────────────────────────────────────────────────
            Expanded(child: _buildExerciseBody()),
          ],
        ),
      ),
    );
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

  Widget _buildExerciseBody() {
    final ex = _currentExercise;
    final sets = _currentSets;
    final lastStr = _lastDisplay(ex);
    final hint = _progressionHint(ex);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      children: [
        // ── Exercise header ──────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ex.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ex.muscleGroup,
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ex.notes?.trim().isNotEmpty == true
                        ? '${ex.repRangeLabel} • ${ex.notes!.trim()}'
                        : ex.repRangeLabel,
                    style: const TextStyle(
                      color: Color(0xFF4B5563),
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            // History tap
            TextButton.icon(
              onPressed: () => _openHistory(ex),
              icon: const Icon(
                Icons.history_rounded,
                color: Color(0xFF6B7280),
                size: 16,
              ),
              label: const Text(
                'History',
                style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
              ),
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
            ),
          ],
        ),

        // ── Last session reference ────────────────────────────────────────
        if (lastStr.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2C),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF2E2E3E)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.access_time_rounded,
                  color: Color(0xFF6B7280),
                  size: 14,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    lastStr,
                    style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // ── Progression hint ──────────────────────────────────────────────
        if (hint.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFFFB347).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFFFFB347).withValues(alpha: 0.25),
              ),
            ),
            child: Text(
              hint,
              style: const TextStyle(
                color: Color(0xFFFFB347),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],

        const SizedBox(height: 20),

        const SizedBox(height: 12),
        _SetTypeSelector(
          selected: _selectedSetType,
          onChanged: (v) => setState(() => _selectedSetType = v),
        ),
        const SizedBox(height: 10),

        // ── Input row ────────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: _InputField(
                controller: _weightCtrl[ex.id]!,
                label: 'Weight (kg)',
                icon: Icons.fitness_center_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _InputField(
                controller: _repsCtrl[ex.id]!,
                label: 'Reps',
                icon: Icons.repeat_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // ── RPE toggle ───────────────────────────────────────────────────
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: _showRpe
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _InputField(
                    controller: _rpeCtrl[ex.id]!,
                    label: 'RPE (1–10, optional)',
                    icon: Icons.speed_rounded,
                  ),
                )
              : const SizedBox.shrink(),
        ),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _addSet,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text(
                  'Add Set',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2D6A4F),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            if (sets.isNotEmpty) ...[
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: _duplicateLastSet,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF6B7280),
                  side: const BorderSide(color: Color(0xFF2E2E3E)),
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Icon(Icons.copy_rounded, size: 16),
              ),
            ],
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: () => setState(() => _showRpe = !_showRpe),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF6B7280),
                side: const BorderSide(color: Color(0xFF2E2E3E)),
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'RPE',
                style: TextStyle(
                  fontSize: 12,
                  color: _showRpe
                      ? const Color(0xFF52B788)
                      : const Color(0xFF6B7280),
                ),
              ),
            ),
          ],
        ),

        // ── Logged sets ──────────────────────────────────────────────────
        if (sets.isNotEmpty) ...[
          const SizedBox(height: 20),
          Row(
            children: [
              Text(
                '${sets.length} set${sets.length == 1 ? "" : "s"}',
                style: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                'Vol: ${sets.fold(0.0, (s, e) => s + e.volume).toStringAsFixed(0)} kg',
                style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (int i = 0; i < sets.length; i++)
            _SetRow(
              index: i,
              set: sets[i],
              onDelete: () => _removeSet(ex.id, i),
            ),
        ],
      ],
    );
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
      Navigator.of(context).pop();
    }
  }
}

// ─── _ExerciseChipBar ─────────────────────────────────────────────────────────

class _ExerciseChipBar extends StatelessWidget {
  final List<Exercise> exercises;
  final int selectedIndex;
  final Map<String, int> setCounts;
  final ValueChanged<int> onSelect;
  final VoidCallback onAddExercise;
  final void Function(int oldIndex, int newIndex) onReorder;
  final Future<void> Function(int index) onRemoveExercise;

  const _ExerciseChipBar({
    required this.exercises,
    required this.selectedIndex,
    required this.setCounts,
    required this.onSelect,
    required this.onAddExercise,
    required this.onReorder,
    required this.onRemoveExercise,
  });

  @override
  Widget build(BuildContext context) => Container(
    height: 52,
    color: const Color(0xFF1A1A28),
    child: Row(
      children: [
        Expanded(
          child: ReorderableListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            buildDefaultDragHandles: false,
            onReorder: onReorder,
            itemCount: exercises.length,
            itemBuilder: (_, i) {
              final ex = exercises[i];
              final selected = i == selectedIndex;
              final count = setCounts[ex.id] ?? 0;

              return Padding(
                key: ValueKey(ex.id),
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => onSelect(i),
                  onLongPress: () async {
                    if (exercises.length <= 1) return; // can't remove last exercise
                    await showModalBottomSheet(
                      context: context,
                      backgroundColor: const Color(0xFF1E1E2C),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      builder: (_) => SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Center(
                                child: Container(
                                  width: 36, height: 4,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF4B5563),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                ex.name,
                                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                ex.muscleGroup,
                                style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
                              ),
                              const SizedBox(height: 16),
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Container(
                                  width: 36, height: 36,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF87171).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFF87171), size: 18),
                                ),
                                title: const Text(
                                  'Remove from today',
                                  style: TextStyle(color: Color(0xFFF87171), fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                                subtitle: const Text(
                                  "Split is unchanged — today only",
                                  style: TextStyle(color: Color(0xFF6B7280), fontSize: 11),
                                ),
                                onTap: () async {
                                  Navigator.of(context).pop();
                                  await onRemoveExercise(i);
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF2D6A4F)
                          : const Color(0xFF1E1E2C),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF52B788)
                            : const Color(0xFF2E2E3E),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ReorderableDragStartListener(
                          index: i,
                          child: Icon(
                            Icons.drag_indicator_rounded,
                            color: selected
                                ? Colors.white70
                                : const Color(0xFF6B7280),
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          ex.name,
                          style: TextStyle(
                            color: selected
                                ? Colors.white
                                : const Color(0xFF9CA3AF),
                            fontSize: 12.5,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        if (count > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 18,
                            height: 18,
                            decoration: const BoxDecoration(
                              color: Color(0xFF52B788),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '$count',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: GestureDetector(
            onTap: onAddExercise,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFF2D6A4F).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF52B788).withValues(alpha: 0.4),
                ),
              ),
              child: const Icon(
                Icons.add_rounded,
                color: Color(0xFF52B788),
                size: 18,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

// ─── _SetRow ──────────────────────────────────────────────────────────────────

class _SetRow extends StatelessWidget {
  final int index;
  final SetEntry set;
  final VoidCallback onDelete;
  const _SetRow({
    required this.index,
    required this.set,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFF1E1E2C),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFF2E2E3E)),
    ),
    child: Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: const Color(0xFF2D6A4F).withValues(alpha: 0.3),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                color: Color(0xFF52B788),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            '${set.weight.toStringAsFixed(set.weight == set.weight.truncateToDouble() ? 0 : 1)} kg  ×  ${set.reps} reps'
            '${set.rpe != null ? "  ·  RPE ${set.rpe}" : ""}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: _setTypeColor(set.setType).withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            set.setType.shortLabel,
            style: TextStyle(
              color: _setTypeColor(set.setType),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${set.volume.toStringAsFixed(0)} kg',
          style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onDelete,
          child: const Icon(
            Icons.remove_circle_rounded,
            color: Color(0xFF3B3B4F),
            size: 20,
          ),
        ),
      ],
    ),
  );

  Color _setTypeColor(SetType type) => switch (type) {
    SetType.normal => const Color(0xFF52B788),
    SetType.warmUp => const Color(0xFF6B7280),
    SetType.dropSet => const Color(0xFFFFB347),
    SetType.supersetA => const Color(0xFF60A5FA),
    SetType.supersetB => const Color(0xFFA78BFA),
    SetType.burnout => const Color(0xFFF87171),
  };
}

// ─── _InputField ──────────────────────────────────────────────────────────────

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  const _InputField({
    required this.controller,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    textAlign: TextAlign.center,
    style: const TextStyle(
      color: Colors.white,
      fontSize: 18,
      fontWeight: FontWeight.w700,
    ),
    decoration: InputDecoration(
      hintText: label,
      hintStyle: const TextStyle(
        color: Color(0xFF4B5563),
        fontSize: 13,
        fontWeight: FontWeight.w400,
      ),
      filled: true,
      fillColor: const Color(0xFF1E1E2C),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF52B788), width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 16),
      prefixIcon: Icon(icon, color: const Color(0xFF6B7280), size: 18),
    ),
  );
}

// ─── _StatLine ────────────────────────────────────────────────────────────────

class _StatLine extends StatelessWidget {
  final String label;
  final String value;
  const _StatLine(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

// ─── _ExerciseHistorySheet ────────────────────────────────────────────────────
//
// Bottom sheet: last 5 sessions for this exercise + best set ever.

class _ExerciseHistorySheet extends StatelessWidget {
  final Exercise exercise;
  final String splitDayName;
  const _ExerciseHistorySheet({
    required this.exercise,
    required this.splitDayName,
  });

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
                    Text(
                      exercise.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      exercise.muscleGroup,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      trend,
                      style: const TextStyle(
                        color: Color(0xFF52B788),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (best != null) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'Best 1RM',
                      style: TextStyle(color: Color(0xFF6B7280), fontSize: 10),
                    ),
                    Text(
                      '${best.estimatedOneRepMax.toStringAsFixed(1)} kg',
                      style: const TextStyle(
                        color: Color(0xFFFFB347),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '(${best.weight.toStringAsFixed(0)}×${best.reps})',
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 11,
                      ),
                    ),
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
            child: Text(
              note,
              style: const TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (history.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No history yet',
                  style: TextStyle(color: Color(0xFF4B5563)),
                ),
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
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((type) {
        final isSelected = selected == type;
        return GestureDetector(
          onTap: () => onChanged(type),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF2D6A4F).withValues(alpha: 0.18)
                  : const Color(0xFF1E1E2C),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF52B788)
                    : const Color(0xFF2E2E3E),
              ),
            ),
            child: Text(
              type.label,
              style: TextStyle(
                color: isSelected
                    ? const Color(0xFF52B788)
                    : const Color(0xFF9CA3AF),
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

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
            // Search bar
            TextField(
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search exercises...',
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: Color(0xFF6B7280),
                  size: 18,
                ),
                filled: true,
                fillColor: const Color(0xFF13131F),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Create Custom always at top
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D6A4F).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF52B788).withValues(alpha: 0.3),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.add_rounded, color: Color(0xFF52B788), size: 20),
                    SizedBox(width: 10),
                    Text(
                      '+ Add Custom Exercise',
                      style: TextStyle(
                        color: Color(0xFF52B788),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1, color: Color(0xFF2E2E3E)),
            const SizedBox(height: 4),

            // Exercise list
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final ex = filtered[i];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 0,
                    ),
                    title: Text(
                      ex.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                      ),
                    ),
                    subtitle: Text(
                      '${ex.muscleGroup} • ${ex.repRangeLabel}',
                      style: const TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 12,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.add_rounded,
                      color: Color(0xFF52B788),
                      size: 20,
                    ),
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

class _HistoryRow extends StatelessWidget {
  final DateTime date;
  final ExerciseEntry entry;
  const _HistoryRow({required this.date, required this.entry});

  @override
  Widget build(BuildContext context) {
    final dateStr = '${date.day}/${date.month}/${date.year % 100}';
    final setsStr = entry.sets
        .map(
          (s) =>
              '${s.weight.toStringAsFixed(s.weight == s.weight.truncateToDouble() ? 0 : 1)}×${s.reps}',
        )
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
          Text(
            dateStr,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              setsStr,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          Text(
            '${entry.totalVolume.toStringAsFixed(0)} kg',
            style: const TextStyle(color: Color(0xFF4B5563), fontSize: 11),
          ),
        ],
      ),
    );
  }
}
