import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_theme.dart';
import '../models/workout_split.dart';
import '../models/workout_session.dart';
import '../models/day_log.dart';
import '../services/workout_service.dart';
import '../services/persistence_service.dart';
import 'workout_setup_screen.dart' show showCreateCustomExerciseSheet;

// ─── WorkoutSessionScreen ─────────────────────────────────────────────────────
//
// Gym-First Workout Operating System. Rebuilt from first principles.
//
// Visual Design & Interaction Paradigms:
//   1. PageView Swiping: Left-right horizontal swipes between exercises.
//   2. Custom Dial Selectors: No text inputs. ListWheelScrollView snapping dial controllers.
//   3. Bottom Dock Command Center: Bottom-weighted logging CTA + progress tracker + chevrons.
//   4. Dynamic planned targets (exercise.targetSets) instead of hardcoded numbers.
//   5. Hero progression recommendations & Bezier sparkline history curves.
//   6. Anatomical vector torso custom painted silhouette.
//   7. Non-blocking sliding PR toasts.
//   8. State isolation at the page level for locked 60 FPS.
//   9. Fullscreen complete session dashboard.
//   10. Auto-save recovery on every change to prevent data loss.

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

class _WorkoutSessionScreenState extends State<WorkoutSessionScreen> with WidgetsBindingObserver {
  late final PageController _pageController;
  int _selectedIndex = 0;
  bool _isSaving = false;
  bool _isDiscarding = false;

  // Active exercises
  late List<Exercise> _sessionExercises;

  // Set entries per exercise
  final Map<String, List<SetEntry>> _sets = {};

  // Dial selections and inputs cached per exercise to enable recovery
  final Map<String, double> _weightSelections = {};
  final Map<String, int> _repsSelections = {};
  final Map<String, double?> _rpeSelections = {};
  final Map<String, SetType> _setTypeSelections = {};
  final Map<String, String> _exerciseNotes = {};
  final Map<String, double> _scrollOffsets = {};
  String _sessionNotes = '';

  final _service = WorkoutService.instance;
  late DateTime _startTime;

  // Floating text particles tracker
  final List<_FloatingTextData> _floatingTexts = [];
  final ValueNotifier<int> _scoreNotifier = ValueNotifier<int>(0);

  // PR Celebration State (Non-blocking)
  bool _showPrToast = false;
  String _prToastMsg = '';

  // Completion State
  bool _showCompletionScreen = false;
  late WorkoutSession _completedSessionSummary;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    _startTime = widget.draftSession?.date ?? DateTime.now();
    _pageController = PageController(initialPage: _selectedIndex);

    final draft = widget.draftSession;
    if (draft != null) {
      _sessionNotes = draft.notes ?? '';
    }
    _sessionExercises = draft != null
        ? draft.entries.map((e) => e.exercise).toList()
        : List.of(widget.splitDay.exercises);

    for (final ex in _sessionExercises) {
      _sets[ex.id] = [];
      _setTypeSelections[ex.id] = SetType.normal;
      _rpeSelections[ex.id] = 8.0; // default RPE target

      if (draft != null) {
        final matchingEntry = draft.entries.where((e) => e.exercise.id == ex.id).firstOrNull;
        if (matchingEntry != null) {
          _sets[ex.id] = matchingEntry.sets.toList();
          if (matchingEntry.notes != null) {
            _exerciseNotes[ex.id] = matchingEntry.notes!;
          }
        }
      }

      // Initialize default dial values
      final lastEntry = _service.lastEntryFor(ex.id, widget.splitDay.name);
      final lastTop = lastEntry?.topSet;
      if (lastTop != null) {
        _weightSelections[ex.id] = lastTop.weight;
        _repsSelections[ex.id] = lastTop.reps;
      } else {
        _weightSelections[ex.id] = 40.0;
        _repsSelections[ex.id] = 10;
      }
    }

    _restoreState().then((_) {
      _updateLiveScore();
    });
  }

  Timer? _debounceTimer;

  void _queueRecoverySave() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _saveRecoveryState();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    _scoreNotifier.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _saveRecoveryState();
    }
  }

  // ── Recovery Persistence ─────────────────────────────────────────────────

  Future<void> _saveRecoveryState() async {
    final prefs = await SharedPreferences.getInstance();
    final recoveryData = <String, dynamic>{
      'selectedIndex': _selectedIndex,
      'setTypeSelections': _setTypeSelections.map((k, v) => MapEntry(k, v.name)),
      'rpeSelections': _rpeSelections.map((k, v) => MapEntry(k, v ?? 8.0)),
      'weightSelections': _weightSelections,
      'repsSelections': _repsSelections,
      'timerStartedAt': _startTime.toIso8601String(),
      'sessionNotes': _sessionNotes,
      'exerciseNotes': _exerciseNotes,
      'scrollOffsets': _scrollOffsets,
    };
    await prefs.setString('kynetix_workout_recovery', jsonEncode(recoveryData));
    _saveDraftSessionState();
  }

  Future<void> _restoreState() async {
    final prefs = await SharedPreferences.getInstance();
    final recoveryJson = prefs.getString('kynetix_workout_recovery');
    if (recoveryJson != null) {
      try {
        final data = jsonDecode(recoveryJson) as Map<String, dynamic>;
        setState(() {
          _selectedIndex = (data['selectedIndex'] as int? ?? 0).clamp(0, _sessionExercises.length - 1);
          
          final setTypeMap = data['setTypeSelections'] as Map<String, dynamic>?;
          if (setTypeMap != null) {
            setTypeMap.forEach((k, v) {
              try {
                _setTypeSelections[k] = SetType.values.byName(v as String);
              } catch (_) {}
            });
          }

          final rpeMap = data['rpeSelections'] as Map<String, dynamic>?;
          if (rpeMap != null) {
            rpeMap.forEach((k, v) {
              _rpeSelections[k] = (v as num).toDouble();
            });
          }

          final weightMap = data['weightSelections'] as Map<String, dynamic>?;
          if (weightMap != null) {
            weightMap.forEach((k, v) {
              _weightSelections[k] = (v as num).toDouble();
            });
          }

          final repsMap = data['repsSelections'] as Map<String, dynamic>?;
          if (repsMap != null) {
            repsMap.forEach((k, v) {
              _repsSelections[k] = (v as num).toInt();
            });
          }

          _sessionNotes = data['sessionNotes'] as String? ?? _sessionNotes;

          final exNotesMap = data['exerciseNotes'] as Map<String, dynamic>?;
          if (exNotesMap != null) {
            exNotesMap.forEach((k, v) {
              _exerciseNotes[k] = v as String;
            });
          }

          final scrollMap = data['scrollOffsets'] as Map<String, dynamic>?;
          if (scrollMap != null) {
            scrollMap.forEach((k, v) {
              _scrollOffsets[k] = (v as num).toDouble();
            });
          }

          final timerStartedAt = data['timerStartedAt'] as String?;
          if (timerStartedAt != null) {
            final parsed = DateTime.tryParse(timerStartedAt);
            if (parsed != null) {
              _startTime = parsed;
            }
          }
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_pageController.hasClients) {
            _pageController.jumpToPage(_selectedIndex);
          }
        });
      } catch (e) {
        debugPrint('Error restoring draft state: $e');
      }
    }
  }

  void _saveDraftSessionState() {
    if (_isSaving || _isDiscarding || _totalSets == 0) return;
    final entries = _sessionExercises
        .where((ex) => (_sets[ex.id] ?? []).isNotEmpty)
        .map((ex) => ExerciseEntry(
              exercise: ex,
              sets: _sets[ex.id]!,
              notes: _exerciseNotes[ex.id],
            ))
        .toList();
    if (entries.isEmpty) return;

    final draft = WorkoutSession(
      id: widget.draftSession?.id ?? 'ws_draft_${DateTime.now().millisecondsSinceEpoch}',
      date: widget.date,
      splitDayName: widget.splitDay.name,
      splitDayWeekday: widget.splitDay.weekday == 0 ? null : widget.splitDay.weekday,
      wasManuallySelected: widget.wasManuallySelected,
      entries: entries,
      notes: _sessionNotes,
    );
    _service.saveDraftSession(draft, startedAt: _startTime);
  }

  // ── Getters & Stats ──────────────────────────────────────────────────────

  Exercise get _currentExercise => _sessionExercises[_selectedIndex];
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

  void _updateLiveScore() {
    if (_sessionExercises.isEmpty) {
      _scoreNotifier.value = 0;
      return;
    }
    
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
      targetSetsScore += (logged / ex.targetSets.toDouble()).clamp(0.0, 1.0);
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

    _scoreNotifier.value = (completionScore + volumeScore + setsScore + prScore).round().clamp(0, 100);
  }

  // ── Logging Operations ───────────────────────────────────────────────────

  void _logSet() {
    final ex = _currentExercise;
    final w = _weightSelections[ex.id] ?? 40.0;
    final r = _repsSelections[ex.id] ?? 10;
    final rpe = _rpeSelections[ex.id];
    final type = _setTypeSelections[ex.id] ?? SetType.normal;

    final newSet = SetEntry(weight: w, reps: r, rpe: rpe, setType: type);

    // Check for PR milestone
    final previousBest = _service.bestSetBefore(ex.id, widget.date);
    final isPr = previousBest == null || newSet.estimatedOneRepMax > previousBest.estimatedOneRepMax + 0.01;

    setState(() {
      _sets[ex.id]!.add(newSet);
    });

    _spawnFloatingText('+1 Set\n+${(w * r).toStringAsFixed(0)} kg');
    HapticFeedback.mediumImpact();
    _updateLiveScore();
    _saveRecoveryState();

    if (isPr) {
      HapticFeedback.heavyImpact();
      _triggerPRNotification(w, r, newSet.estimatedOneRepMax);
    }

    // Auto-advance to next exercise if all planned sets completed
    final completedSets = _sets[ex.id]!.length;
    if (completedSets >= ex.targetSets && _selectedIndex < _sessionExercises.length - 1) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _pageController.nextPage(duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
        }
      });
    }
  }

  void _triggerPRNotification(double weight, int reps, double e1rm) {
    setState(() {
      _showPrToast = true;
      _prToastMsg = '🏆 NEW PERSONAL RECORD!\n${weight.toStringAsFixed(weight == weight.truncateToDouble() ? 0 : 1)} kg × $reps reps (e1RM: ${e1rm.toStringAsFixed(1)} kg)';
    });
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => _showPrToast = false);
      }
    });
  }

  void _adjustInputValue(String exId, double weight, int reps, double? rpe, SetType setType) {
    _weightSelections[exId] = weight;
    _repsSelections[exId] = reps;
    _rpeSelections[exId] = rpe;
    _setTypeSelections[exId] = setType;
    _saveRecoveryState();
  }

  void _removeSet(String exId, int index) {
    setState(() {
      _sets[exId]!.removeAt(index);
    });
    HapticFeedback.selectionClick();
    _updateLiveScore();
    _saveRecoveryState();
  }

  void _duplicateLastSet() {
    final exId = _currentExercise.id;
    final setsList = _sets[exId];
    if (setsList == null || setsList.isEmpty) return;
    final last = setsList.last;
    
    setState(() {
      setsList.add(
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
    _updateLiveScore();
    _saveRecoveryState();
  }

  // ── Completion Screen & Finish ───────────────────────────────────────────

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

    // Reset draft and recovery values
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('kynetix_workout_recovery');

    setState(() {
      _isSaving = false;
      _completedSessionSummary = session;
      _showCompletionScreen = true;
    });
    HapticFeedback.heavyImpact();
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('kynetix_workout_recovery');
      await _service.clearDraftSession();
      if (mounted) Navigator.of(context).pop();
    } else if (result == 'save') {
      _saveRecoveryState();
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

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF1E1E2C),
        behavior: SnackBarBehavior.floating,
      ),
    );
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
      _sets[picked.id] = [];
      _setTypeSelections[picked.id] = SetType.normal;
      _rpeSelections[picked.id] = 8.0;
      _weightSelections[picked.id] = 40.0;
      _repsSelections[picked.id] = 10;
      _selectedIndex = _sessionExercises.length - 1;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(_selectedIndex);
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
          title: const Text('Remove exercise?', style: TextStyle(color: Colors.white)),
          content: Text(
            'You logged sets for "${ex.name}". Removing it will discard those sets for today.',
            style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF9CA3AF))),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Remove', style: TextStyle(color: Color(0xFFF87171), fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() {
      _sessionExercises.removeAt(index);
      _sets.remove(ex.id);
      _weightSelections.remove(ex.id);
      _repsSelections.remove(ex.id);
      _rpeSelections.remove(ex.id);
      _setTypeSelections.remove(ex.id);
      if (_selectedIndex >= _sessionExercises.length) {
        _selectedIndex = (_sessionExercises.length - 1).clamp(0, double.maxFinite.toInt());
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(_selectedIndex);
      }
    });
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

  // ── Layout Builder & Rendering ───────────────────────────────────────────

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
        backgroundColor: const Color(0xFF0C0C14),
        body: Stack(
          children: [
            // Ambient evolving glows (RepaintBoundary keeps it isolated)
            Positioned.fill(
              child: RepaintBoundary(
                child: _AmbientBackgroundGlow(progress: progress),
              ),
            ),

            SafeArea(
              child: Column(
                children: [
                  _buildSessionAppBar(),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth > 600;
                        return PageView.builder(
                          controller: _pageController,
                          itemCount: _sessionExercises.length,
                          onPageChanged: (index) {
                            HapticFeedback.selectionClick();
                            setState(() => _selectedIndex = index);
                            _saveRecoveryState();
                          },
                          itemBuilder: (context, index) {
                            final ex = _sessionExercises[index];
                            final setsList = _sets[ex.id] ?? [];
                            final lastEntry = _service.lastEntryFor(ex.id, widget.splitDay.name);
                            final history = _service.historyFor(ex.id, limit: 5);

                            return _ExerciseWorkoutPage(
                              exercise: ex,
                              sets: setsList,
                              lastEntry: lastEntry,
                              history: history,
                              initialWeight: _weightSelections[ex.id] ?? 40.0,
                              initialReps: _repsSelections[ex.id] ?? 10,
                              initialRpe: _rpeSelections[ex.id],
                              initialSetType: _setTypeSelections[ex.id] ?? SetType.normal,
                              isWideLayout: isWide,
                              initialNotes: _exerciseNotes[ex.id] ?? '',
                              onNotesChange: (notes) {
                                _exerciseNotes[ex.id] = notes;
                                _queueRecoverySave();
                              },
                              sessionNotes: _sessionNotes,
                              onSessionNotesChange: (notes) {
                                setState(() {
                                  _sessionNotes = notes;
                                });
                                _queueRecoverySave();
                              },
                              initialScrollOffset: _scrollOffsets[ex.id] ?? 0.0,
                              onScrollOffsetChange: (offset) {
                                _scrollOffsets[ex.id] = offset;
                                _queueRecoverySave();
                              },
                              onInputChange: (w, r, rpe, type) {
                                _adjustInputValue(ex.id, w, r, rpe, type);
                              },
                              onRemoveSet: (setIdx) {
                                _removeSet(ex.id, setIdx);
                              },
                              onDuplicateSets: _duplicateLastSet,
                              onOpenHistory: () => _openHistory(ex),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  // Bottom dock height offset
                  const SizedBox(height: 120),
                ],
              ),
            ),

            // Pinned Bottom Command Center Dock
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _BottomDockWidget(
                exercises: _sessionExercises,
                sets: _sets,
                selectedIndex: _selectedIndex,
                onPrevious: () {
                  if (_selectedIndex > 0) {
                    _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
                  }
                },
                onNext: () {
                  if (_selectedIndex < _sessionExercises.length - 1) {
                    _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
                  }
                },
                onLogSet: _logSet,
                onAddExercise: _addExerciseToSession,
                onRemoveExercise: () => _removeExerciseFromSession(_selectedIndex),
              ),
            ),

            // Drifting particles overlay
            IgnorePointer(
              child: _buildFloatingTextOverlay(),
            ),

            // Non-blocking PR Celebration sliding toast
            _PRToastWidget(
              isVisible: _showPrToast,
              message: _prToastMsg,
            ),

            // Fullscreen completion finish screen
            if (_showCompletionScreen)
              _WorkoutCompletionOverlay(
                session: _completedSessionSummary,
                previousSession: widget.previousSession,
                score: _scoreNotifier.value,
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                    fontSize: 15,
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
                    _AnimatedCountUpText(
                      value: _totalVolume,
                      suffix: ' kg',
                      style: const TextStyle(color: KColor.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Isolated Live Score ValueListenableBuilder
          ValueListenableBuilder<int>(
            valueListenable: _scoreNotifier,
            builder: (context, score, child) {
              return Container(
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
                    _AnimatedCountUpText(
                      value: score,
                      prefix: 'SCORE: ',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              );
            },
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
                : const Text('Finish', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingTextOverlay() {
    return Stack(
      children: _floatingTexts.map((data) {
        return _FloatingTextWidget(
          key: ValueKey(data.id),
          text: data.text,
        );
      }).toList(),
    );
  }
}

// ─── Ambient Glow Background ──────────────────────────────────────────────

class _AmbientBackgroundGlow extends StatelessWidget {
  final double progress;
  const _AmbientBackgroundGlow({required this.progress});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: progress < 0.3
              ? [const Color(0xFF0C0C14), const Color(0xFF130F1F)]
              : progress < 0.7
                  ? [const Color(0xFF0C0C14), const Color(0xFF0F1528)]
                  : [const Color(0xFF0C0C14), const Color(0xFF0C1F18)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -120,
            right: -120,
            child: AnimatedContainer(
              duration: const Duration(seconds: 1),
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: progress < 0.3
                        ? const Color(0xFF6366F1).withValues(alpha: 0.08)
                        : progress < 0.7
                            ? const Color(0xFF3B82F6).withValues(alpha: 0.08)
                            : const Color(0xFF10B981).withValues(alpha: 0.08),
                    blurRadius: 120,
                    spreadRadius: 40,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Single Page Exercise View ──────────────────────────────────────────────

class _ExerciseWorkoutPage extends StatefulWidget {
  final Exercise exercise;
  final List<SetEntry> sets;
  final ExerciseEntry? lastEntry;
  final List<({DateTime date, ExerciseEntry entry})> history;
  final double initialWeight;
  final int initialReps;
  final double? initialRpe;
  final SetType initialSetType;
  final bool isWideLayout;
  final String initialNotes;
  final Function(String) onNotesChange;
  final String sessionNotes;
  final ValueChanged<String> onSessionNotesChange;
  final double initialScrollOffset;
  final Function(double) onScrollOffsetChange;
  final Function(double, int, double?, SetType) onInputChange;
  final Function(int) onRemoveSet;
  final VoidCallback onDuplicateSets;
  final VoidCallback onOpenHistory;

  const _ExerciseWorkoutPage({
    required this.exercise,
    required this.sets,
    required this.lastEntry,
    required this.history,
    required this.initialWeight,
    required this.initialReps,
    required this.initialRpe,
    required this.initialSetType,
    required this.isWideLayout,
    required this.initialNotes,
    required this.onNotesChange,
    required this.sessionNotes,
    required this.onSessionNotesChange,
    required this.initialScrollOffset,
    required this.onScrollOffsetChange,
    required this.onInputChange,
    required this.onRemoveSet,
    required this.onDuplicateSets,
    required this.onOpenHistory,
  });

  @override
  State<_ExerciseWorkoutPage> createState() => _ExerciseWorkoutPageState();
}

class _ExerciseWorkoutPageState extends State<_ExerciseWorkoutPage> {
  late FixedExtentScrollController _weightScrollController;
  late FixedExtentScrollController _repsScrollController;
  late ScrollController _scrollController;
  late TextEditingController _notesController;
  late TextEditingController _sessionNotesController;

  late double _selectedWeight;
  late int _selectedReps;
  double? _selectedRpe;
  late SetType _selectedSetType;
  bool _showGlowPulse = false;

  // Cache dial options
  final List<double> _weightOptions = List.generate(701, (i) => i * 0.5); // 0.0 to 350.0 kg
  final List<int> _repsOptions = List.generate(100, (i) => i + 1); // 1 to 100 reps

  @override
  void initState() {
    super.initState();
    _selectedWeight = widget.initialWeight;
    _selectedReps = widget.initialReps;
    _selectedRpe = widget.initialRpe;
    _selectedSetType = widget.initialSetType;

    // Calculate item indices
    final wIndex = (_selectedWeight / 0.5).round().clamp(0, 700);
    final rIndex = (_selectedReps - 1).clamp(0, 99);

    _weightScrollController = FixedExtentScrollController(initialItem: wIndex);
    _repsScrollController = FixedExtentScrollController(initialItem: rIndex);

    _scrollController = ScrollController(initialScrollOffset: widget.initialScrollOffset);
    _scrollController.addListener(() {
      if (_scrollController.hasClients) {
        widget.onScrollOffsetChange(_scrollController.offset);
      }
    });

    _notesController = TextEditingController(text: widget.initialNotes);
    _notesController.addListener(() {
      widget.onNotesChange(_notesController.text);
    });

    _sessionNotesController = TextEditingController(text: widget.sessionNotes);
    _sessionNotesController.addListener(() {
      widget.onSessionNotesChange(_sessionNotesController.text);
    });
  }

  @override
  void didUpdateWidget(_ExerciseWorkoutPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.exercise.id != widget.exercise.id) {
      _selectedWeight = widget.initialWeight;
      _selectedReps = widget.initialReps;
      _selectedRpe = widget.initialRpe;
      _selectedSetType = widget.initialSetType;

      final wIndex = (_selectedWeight / 0.5).round().clamp(0, 700);
      final rIndex = (_selectedReps - 1).clamp(0, 99);

      _weightScrollController.jumpToItem(wIndex);
      _repsScrollController.jumpToItem(rIndex);

      _notesController.text = widget.initialNotes;
      _sessionNotesController.text = widget.sessionNotes;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(widget.initialScrollOffset);
      }
    } else if (widget.sets.length > oldWidget.sets.length) {
      setState(() {
        _showGlowPulse = true;
      });
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) {
          setState(() {
            _showGlowPulse = false;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _weightScrollController.dispose();
    _repsScrollController.dispose();
    _scrollController.dispose();
    _notesController.dispose();
    _sessionNotesController.dispose();
    super.dispose();
  }

  void _onWeightScroll(int index) {
    final w = _weightOptions[index];
    setState(() {
      _selectedWeight = w;
    });
    HapticFeedback.selectionClick();
    widget.onInputChange(w, _selectedReps, _selectedRpe, _selectedSetType);
  }

  void _onRepsScroll(int index) {
    final r = _repsOptions[index];
    setState(() {
      _selectedReps = r;
    });
    HapticFeedback.selectionClick();
    widget.onInputChange(_selectedWeight, r, _selectedRpe, _selectedSetType);
  }

  void _adjustWeight(double delta) {
    final newW = (_selectedWeight + delta).clamp(0.0, 350.0);
    final index = (newW / 0.5).round();
    _weightScrollController.animateToItem(index, duration: const Duration(milliseconds: 200), curve: Curves.easeOutCubic);
  }

  void _adjustReps(int delta) {
    final newR = (_selectedReps + delta).clamp(1, 100);
    final index = newR - 1;
    _repsScrollController.animateToItem(index, duration: const Duration(milliseconds: 200), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final hint = WorkoutService.instance.progressionHint(widget.lastEntry, widget.exercise);

    final leftCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeroSection(),
        const SizedBox(height: 12),
        _buildVisualTorsoCuesCard(),
        const SizedBox(height: 12),
        _buildCoachingBanner(hint),
      ],
    );

    final rightCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDialConsolePanel(),
        const SizedBox(height: 12),
        _buildSetTypeAndRpeSelectors(),
        const SizedBox(height: 16),
        _buildLoggedSetsCardsSection(),
        const SizedBox(height: 16),
        _buildSessionNotesCard(),
      ],
    );

    if (widget.isWideLayout) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: leftCol,
            ),
          ),
          Expanded(
            flex: 5,
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: rightCol,
            ),
          ),
        ],
      );
    } else {
      return ListView(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          leftCol,
          const SizedBox(height: 14),
          rightCol,
        ],
      );
    }
  }

  Widget _buildSessionNotesCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KColor.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: KColor.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.edit_note_rounded, color: KColor.textSecondary, size: 18),
              SizedBox(width: 8),
              Text(
                'WORKOUT SESSION NOTES',
                style: TextStyle(color: KColor.textMuted, fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 0.4),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _sessionNotesController,
            maxLines: 2,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: const InputDecoration(
              hintText: 'Add general notes about energy levels, injuries, rest cycles...',
              hintStyle: TextStyle(color: KColor.textMuted, fontSize: 11),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  // ── Exercise Info & Bezier Sparkline ──────────────────────────────────────

  Widget _buildHeroSection() {
    final lastStr = widget.lastEntry != null 
        ? WorkoutService.instance.lastSessionDisplay(widget.lastEntry).replaceAll('Last: ', '') 
        : 'None';
    final bestVal = WorkoutService.instance.bestSetEver(widget.exercise.id);
    final bestStr = bestVal != null 
        ? '${bestVal.weight.toStringAsFixed(bestVal.weight == bestVal.weight.truncateToDouble() ? 0 : 1)}kg × ${bestVal.reps}' 
        : 'None';
    final currentStr = widget.sets.isNotEmpty 
        ? widget.sets.map((s) => '${s.weight.toStringAsFixed(s.weight == s.weight.truncateToDouble() ? 0 : 1)}×${s.reps}').join(', ')
        : 'None';

    // Projected target
    String projectedStr = 'Pending';
    final lastTop = widget.lastEntry?.topSet;
    if (lastTop != null) {
      final nextWeight = lastTop.weight + (widget.exercise.type == ExerciseType.barbellCompound ? 2.5 : 2.0);
      projectedStr = '${nextWeight.toStringAsFixed(nextWeight == nextWeight.truncateToDouble() ? 0 : 1)}kg × ${widget.exercise.targetRepMin}';
    } else {
      projectedStr = '40kg × ${widget.exercise.targetRepMin}';
    }

    // Sparkline historical data
    final sparkData = widget.history.reversed
        .map((h) => h.entry.topWorkingSet?.estimatedOneRepMax ?? h.entry.topSet?.estimatedOneRepMax ?? 0.0)
        .where((val) => val > 0.0)
        .toList();

    // Progression coaching logic
    final lastTopSet = widget.lastEntry?.topSet;
    String recSet = '';
    String recReason = '';
    
    if (widget.exercise.type == ExerciseType.bodyweight) {
      recSet = 'Bodyweight × Max Reps';
      recReason = widget.lastEntry != null 
          ? 'Completed ${widget.lastEntry!.topSet?.reps ?? 10} reps last session. Focus on pushing past failure today.'
          : 'First bodyweight training session. Find your max repetition baseline.';
    } else if (lastTopSet != null) {
      final targetMax = widget.exercise.targetRepMax;
      final targetMin = widget.exercise.targetRepMin;
      
      if (lastTopSet.reps >= targetMax) {
        final step = (widget.exercise.type == ExerciseType.barbellCompound) ? 2.5 : 2.0;
        final newWeight = lastTopSet.weight + step;
        recSet = '${newWeight.toStringAsFixed(newWeight == newWeight.truncateToDouble() ? 0 : 1)} kg × $targetMin reps';
        recReason = 'You hit $targetMax reps last workout (target achieved). Stepping up by +$step kg today.';
      } else if (lastTopSet.reps < targetMin) {
        recSet = '${lastTopSet.weight.toStringAsFixed(lastTopSet.weight == lastTopSet.weight.truncateToDouble() ? 0 : 1)} kg × $targetMin reps';
        recReason = 'Previous session was below target range ($targetMin reps). Keep same weight and focus on control.';
      } else {
        recSet = '${lastTopSet.weight.toStringAsFixed(lastTopSet.weight == lastTopSet.weight.truncateToDouble() ? 0 : 1)} kg × $targetMax reps';
        recReason = 'You completed ${lastTopSet.reps} reps last session. Aim to reach the max target of $targetMax reps before weight jump.';
      }
    } else {
      recSet = '40 kg × ${widget.exercise.targetRepMin} reps';
      recReason = 'No historical log. Establish your starting volume baseline today.';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KColor.surface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: KColor.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.exercise.name,
                      style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900),
                    ),
                    Text(
                      '${widget.exercise.muscleGroup} • target: ${widget.exercise.targetSets} sets • ${widget.exercise.repRangeLabel}',
                      style: const TextStyle(color: KColor.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.insights_rounded, color: KColor.green, size: 22),
                onPressed: widget.onOpenHistory,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _buildHeroStatCol('LAST SESSION', lastStr, KColor.textSecondary),
              _buildHeroStatCol('BEST SET', bestStr, KColor.amber),
              _buildHeroStatCol('CURRENT SETS', currentStr, KColor.green),
              _buildHeroStatCol('PROJECTED 1RM', projectedStr, KColor.blue),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFB347).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFB347).withValues(alpha: 0.15), width: 0.8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.offline_bolt_rounded, color: Color(0xFFFFB347), size: 14),
                    const SizedBox(width: 6),
                    Text(
                      'RECOMMENDED NEXT SET: $recSet',
                      style: const TextStyle(color: Color(0xFFFFB347), fontSize: 11, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  recReason,
                  style: const TextStyle(color: Colors.white, fontSize: 11.5, height: 1.3),
                ),
              ],
            ),
          ),
          if (sparkData.length >= 2) ...[
            const SizedBox(height: 14),
            const Divider(color: KColor.border, height: 1),
            const SizedBox(height: 12),
            const Text('PROGRESSION TREND (1RM)', style: TextStyle(color: KColor.textMuted, fontSize: 8.5, fontWeight: FontWeight.bold, letterSpacing: 0.4)),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              width: double.infinity,
              child: CustomPaint(
                painter: _SparklinePainter(sparkData),
              ),
            ),
          ]
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

  // ── Stylized Torso Visual Card ────────────────────────────────────────────

  Widget _buildVisualTorsoCuesCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141624).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: KColor.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 44,
                height: 60,
                child: CustomPaint(
                  painter: _AnatomicalSilhouettePainter(widget.exercise.muscleGroup),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('EXECUTION CUES', style: TextStyle(color: KColor.textMuted, fontSize: 8.5, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 3),
                    Text(
                      widget.exercise.notes?.trim().isNotEmpty == true
                          ? widget.exercise.notes!.trim()
                          : 'Maintain alignment, control the eccentric phase, and focus on the stretch-mediated hypertrophy.',
                      style: const TextStyle(color: Colors.white, fontSize: 11.5, height: 1.35, fontStyle: FontStyle.italic),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(color: KColor.border, height: 1),
          const SizedBox(height: 8),
          const Text('EXERCISE NOTES', style: TextStyle(color: KColor.textMuted, fontSize: 8.5, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          TextField(
            controller: _notesController,
            maxLines: 2,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: const InputDecoration(
              hintText: 'Tap to add setup details (e.g., seat height, machine settings)...',
              hintStyle: TextStyle(color: KColor.textMuted, fontSize: 11),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }



  Widget _buildCoachingBanner(String hint) {
    if (hint.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF13131F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: KColor.border, width: 0.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.psychology_rounded, color: KColor.green, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              hint,
              style: const TextStyle(color: Colors.white, fontSize: 11.5, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  // ── Wheel Dials selectors (Change 1) ──────────────────────────────────────

  Widget _buildDialConsolePanel() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KColor.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: _showGlowPulse ? KColor.green : KColor.border,
          width: _showGlowPulse ? 2.0 : 0.8,
        ),
        boxShadow: _showGlowPulse
            ? [
                BoxShadow(
                  color: KColor.green.withValues(alpha: 0.25),
                  blurRadius: 15,
                  spreadRadius: 2,
                )
              ]
            : [],
      ),
      child: Column(
        children: [
          // Large digital readout header
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${_selectedWeight.toStringAsFixed(1)} kg',
                style: const TextStyle(
                  color: KColor.green,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 14),
              const Text('×', style: TextStyle(color: KColor.textMuted, fontSize: 22)),
              const SizedBox(width: 14),
              Text(
                '$_selectedReps reps',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Double vertical selector wheels
          Row(
            children: [
              // Weight Dial wheel
              Expanded(
                child: Column(
                  children: [
                    const Text('WEIGHT SELECTOR', style: TextStyle(color: KColor.textMuted, fontSize: 8.5, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _DialAdjusterBtn(label: '-5', onTap: () => _adjustWeight(-5)),
                        const SizedBox(width: 4),
                        _DialAdjusterBtn(label: '-2.5', onTap: () => _adjustWeight(-2.5)),
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
                      child: ListWheelScrollView.useDelegate(
                        controller: _weightScrollController,
                        itemExtent: 32,
                        physics: const FixedExtentScrollPhysics(),
                        onSelectedItemChanged: _onWeightScroll,
                        childDelegate: ListWheelChildBuilderDelegate(
                          builder: (context, index) {
                            final w = _weightOptions[index];
                            final isSel = _selectedWeight == w;
                            return Center(
                              child: Text(
                                '${w.toStringAsFixed(1)} kg',
                                style: TextStyle(
                                  color: isSel ? KColor.green : KColor.textMuted,
                                  fontSize: isSel ? 15 : 12,
                                  fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            );
                          },
                          childCount: 701,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _DialAdjusterBtn(label: '+2.5', onTap: () => _adjustWeight(2.5)),
                        const SizedBox(width: 4),
                        _DialAdjusterBtn(label: '+5', onTap: () => _adjustWeight(5)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              // Reps Dial wheel
              Expanded(
                child: Column(
                  children: [
                    const Text('REPS SELECTOR', style: TextStyle(color: KColor.textMuted, fontSize: 8.5, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _DialAdjusterBtn(label: '-5', onTap: () => _adjustReps(-5)),
                        const SizedBox(width: 4),
                        _DialAdjusterBtn(label: '-1', onTap: () => _adjustReps(-1)),
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
                      child: ListWheelScrollView.useDelegate(
                        controller: _repsScrollController,
                        itemExtent: 32,
                        physics: const FixedExtentScrollPhysics(),
                        onSelectedItemChanged: _onRepsScroll,
                        childDelegate: ListWheelChildBuilderDelegate(
                          builder: (context, index) {
                            final r = _repsOptions[index];
                            final isSel = _selectedReps == r;
                            return Center(
                              child: Text(
                                '$r reps',
                                style: TextStyle(
                                  color: isSel ? Colors.white : KColor.textMuted,
                                  fontSize: isSel ? 15 : 12,
                                  fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            );
                          },
                          childCount: 100,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _DialAdjusterBtn(label: '+1', onTap: () => _adjustReps(1)),
                        const SizedBox(width: 4),
                        _DialAdjusterBtn(label: '+5', onTap: () => _adjustReps(5)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Set Type & RPE selectors ──────────────────────────────────────────────

  Widget _buildSetTypeAndRpeSelectors() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SetTypeSelector(
          selected: _selectedSetType,
          onChanged: (type) {
            setState(() {
              _selectedSetType = type;
            });
            widget.onInputChange(_selectedWeight, _selectedReps, _selectedRpe, type);
          },
        ),
        const SizedBox(height: 12),
        const Text('RATE OF PERCEIVED EXERTION (RPE)', style: TextStyle(color: KColor.textMuted, fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 0.4)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: KColor.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: KColor.border, width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Snapping target scale', style: TextStyle(color: KColor.textMuted, fontSize: 9, fontWeight: FontWeight.bold)),
                  Text(
                    _selectedRpe == null ? 'None' : 'RPE $_selectedRpe — ${_rpeDescription(_selectedRpe!)}',
                    style: const TextStyle(color: KColor.green, fontSize: 10.5, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [6.0, 7.0, 8.0, 8.5, 9.0, 9.5, 10.0].map((val) {
                  final isSel = _selectedRpe == val;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _selectedRpe = val;
                          });
                          widget.onInputChange(_selectedWeight, _selectedReps, val, _selectedSetType);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: isSel ? KColor.green : const Color(0xFF13131F),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSel ? KColor.green : KColor.border,
                              width: 0.5,
                            ),
                          ),
                          child: Text(
                            val.toString().replaceAll('.0', ''),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: isSel ? Colors.white : KColor.textSecondary,
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
      ],
    );
  }

  // ── Logged sets list ──────────────────────────────────────────────────────

  Widget _buildLoggedSetsCardsSection() {
    if (widget.sets.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'LOGGED SETS (${widget.sets.length})',
              style: const TextStyle(color: KColor.textMuted, fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 0.4),
            ),
            Text(
              'Total Volume: ${widget.sets.fold(0.0, (s, e) => s + e.volume).toStringAsFixed(0)} kg',
              style: const TextStyle(color: KColor.textSecondary, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: widget.sets.length,
          itemBuilder: (context, i) {
            final s = widget.sets[i];
            final previousBest = WorkoutService.instance.bestSetBefore(widget.exercise.id, DateTime.now());
            final isPr = previousBest == null || s.estimatedOneRepMax > previousBest.estimatedOneRepMax + 0.01;

            return TweenAnimationBuilder<double>(
              key: ValueKey(s.hashCode ^ i),
              tween: Tween<double>(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutBack,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: 0.92 + (value * 0.08),
                  child: Opacity(
                    opacity: value,
                    child: child,
                  ),
                );
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: KColor.surface.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(16),
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
                      onTap: () => widget.onRemoveSet(i),
                      child: const Icon(Icons.remove_circle_rounded, color: Color(0xFF3B3B4F), size: 18),
                    ),
                  ],
                ),
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
}

// ─── Sparkline Bezier Painter ───────────────────────────────────────────────

class _SparklinePainter extends CustomPainter {
  final List<double> data;
  _SparklinePainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) {
      final paint = Paint()
        ..color = const Color(0xFF374151)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), paint);
      return;
    }

    final maxVal = data.reduce(max);
    final minVal = data.reduce(min);
    final range = maxVal == minVal ? 1.0 : (maxVal - minVal);

    final paintLine = Paint()
      ..color = KColor.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final paintGlow = Paint()
      ..style = PaintingStyle.fill;

    final path = Path();
    final glowPath = Path();

    final stepX = size.width / (data.length - 1);
    
    for (int i = 0; i < data.length; i++) {
      final x = i * stepX;
      final y = size.height - ((data[i] - minVal) / range) * (size.height - 8) - 4;
      
      if (i == 0) {
        path.moveTo(x, y);
        glowPath.moveTo(x, size.height);
        glowPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        glowPath.lineTo(x, y);
      }
    }
    glowPath.lineTo(size.width, size.height);
    glowPath.close();

    final gradient = LinearGradient(
      colors: [KColor.green.withValues(alpha: 0.15), Colors.transparent],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );
    paintGlow.shader = gradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(glowPath, paintGlow);

    canvas.drawPath(path, paintLine);

    final lastX = size.width;
    final lastY = size.height - ((data.last - minVal) / range) * (size.height - 8) - 4;
    final paintCircle = Paint()
      ..color = KColor.green
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(lastX, lastY), 3.5, paintCircle);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ─── Dial Adjuster Large Pill Button ────────────────────────────────────────

class _DialAdjusterBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _DialAdjusterBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 54,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2C),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF3E3E50), width: 0.5),
        ),
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

// ─── Pinned Bottom Command Center Dock (Change 2) ───────────────────────────

class _BottomDockWidget extends StatelessWidget {
  final List<Exercise> exercises;
  final Map<String, List<SetEntry>> sets;
  final int selectedIndex;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onLogSet;
  final VoidCallback onAddExercise;
  final VoidCallback onRemoveExercise;

  const _BottomDockWidget({
    required this.exercises,
    required this.sets,
    required this.selectedIndex,
    required this.onPrevious,
    required this.onNext,
    required this.onLogSet,
    required this.onAddExercise,
    required this.onRemoveExercise,
  });

  String _truncateName(String name, int maxLen) {
    if (name.length <= maxLen) return name;
    return '${name.substring(0, maxLen - 1)}…';
  }

  @override
  Widget build(BuildContext context) {
    final activeEx = exercises[selectedIndex];
    final loggedList = sets[activeEx.id] ?? [];
    final targetSets = activeEx.targetSets;
    final isDone = loggedList.length >= targetSets;

    final hasPrev = selectedIndex > 0;
    final hasNext = selectedIndex < exercises.length - 1;

    final prevName = hasPrev ? exercises[selectedIndex - 1].name : '';
    final nextName = hasNext ? exercises[selectedIndex + 1].name : '';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: const Color(0xFF0C0C14).withValues(alpha: 0.95),
        border: const Border(top: BorderSide(color: Color(0xFF1E1E2F), width: 0.8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Progress Dots representing Exercise-level completion
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(exercises.length, (idx) {
              final ex = exercises[idx];
              final lSets = sets[ex.id]?.length ?? 0;
              final done = lSets >= ex.targetSets;
              final active = idx == selectedIndex;

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: active ? 16 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: done 
                      ? KColor.green 
                      : (active ? KColor.blue : const Color(0xFF2E2E3E)),
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),

          // 2. Exercise Navigation Row (Pill Buttons with Prev/Next Names)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Previous Exercise Button
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: hasPrev
                      ? TextButton.icon(
                          onPressed: onPrevious,
                          icon: const Icon(Icons.chevron_left_rounded, color: KColor.textSecondary, size: 18),
                          label: Text(
                            _truncateName(prevName, 12),
                            style: const TextStyle(color: KColor.textSecondary, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
              
              // Active Exercise Short Stats
              Text(
                'EXERCISE ${selectedIndex + 1} OF ${exercises.length}',
                style: const TextStyle(color: KColor.textMuted, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.6),
              ),

              // Next Exercise Button
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: hasNext
                      ? Directionality(
                          textDirection: TextDirection.rtl,
                          child: TextButton.icon(
                            onPressed: onNext,
                            icon: const Icon(Icons.chevron_right_rounded, color: KColor.textSecondary, size: 18),
                            label: Text(
                              _truncateName(nextName, 12),
                              style: const TextStyle(color: KColor.textSecondary, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 3. Command Center Action Row: Add Exercise, Log Set, Delete Exercise
          Row(
            children: [
              // Add Exercise Button (Thumb size)
              Container(
                width: 48,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2C),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF3E3E50), width: 0.5),
                ),
                child: IconButton(
                  icon: const Icon(Icons.playlist_add_rounded, color: Colors.white, size: 24),
                  onPressed: onAddExercise,
                ),
              ),
              const SizedBox(width: 8),

              // Main "Log Set" CTA
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: onLogSet,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDone ? const Color(0xFF1B6A47) : KColor.green,
                      foregroundColor: Colors.white,
                      shadowColor: KColor.green.withValues(alpha: 0.4),
                      elevation: isDone ? 0 : 8,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: isDone ? const BorderSide(color: KColor.green, width: 1.0) : BorderSide.none,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.add_task_rounded, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          isDone ? 'LOG EXTRA SET' : 'LOG SET ${loggedList.length + 1}',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 0.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Remove Exercise Button (Thumb size)
              Container(
                width: 48,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFF2C1E1E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF503E3E), width: 0.5),
                ),
                child: IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: KColor.danger, size: 22),
                  onPressed: onRemoveExercise,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Non-Blocking PR Toast (Change 4) ───────────────────────────────────────

class _PRToastWidget extends StatelessWidget {
  final bool isVisible;
  final String message;
  const _PRToastWidget({required this.isVisible, required this.message});

  @override
  Widget build(BuildContext context) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutBack,
      top: isVisible ? 60 : -100,
      left: 16,
      right: 16,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E2C),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: KColor.amber, width: 1.0),
            boxShadow: [
              BoxShadow(
                color: KColor.amber.withValues(alpha: 0.15),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              const Text('🏆', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Anatomical Vector Silhouette Painter ────────────────────────────────────

class _AnatomicalSilhouettePainter extends CustomPainter {
  final String muscleGroup;
  _AnatomicalSilhouettePainter(this.muscleGroup);

  @override
  void paint(Canvas canvas, Size size) {
    final paintBase = Paint()
      ..color = const Color(0xFF161622)
      ..style = PaintingStyle.fill;

    final paintOutline = Paint()
      ..color = const Color(0xFF2E2E3E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final paintActive = Paint()
      ..color = KColor.green.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;

    final paintActiveOutline = Paint()
      ..color = KColor.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    // 1. Head
    canvas.drawCircle(Offset(cx, h * 0.1), w * 0.12, paintBase);
    canvas.drawCircle(Offset(cx, h * 0.1), w * 0.12, paintOutline);

    // 2. Neck
    final neckPath = Path()
      ..moveTo(cx - w * 0.04, h * 0.15)
      ..lineTo(cx + w * 0.04, h * 0.15)
      ..lineTo(cx + w * 0.04, h * 0.2)
      ..lineTo(cx - w * 0.04, h * 0.2)
      ..close();
    canvas.drawPath(neckPath, paintBase);
    canvas.drawPath(neckPath, paintOutline);

    // 3. Torso
    final torsoPath = Path()
      ..moveTo(cx - w * 0.22, h * 0.22) // Left Shoulder
      ..lineTo(cx + w * 0.22, h * 0.22) // Right Shoulder
      ..lineTo(cx + w * 0.16, h * 0.5)  // Right Waist
      ..lineTo(cx - w * 0.16, h * 0.5)  // Left Waist
      ..close();
    canvas.drawPath(torsoPath, paintBase);
    canvas.drawPath(torsoPath, paintOutline);

    // 4. Hips
    final hipsPath = Path()
      ..moveTo(cx - w * 0.16, h * 0.5)
      ..lineTo(cx + w * 0.16, h * 0.5)
      ..lineTo(cx + w * 0.18, h * 0.58)
      ..lineTo(cx - w * 0.18, h * 0.58)
      ..close();
    canvas.drawPath(hipsPath, paintBase);
    canvas.drawPath(hipsPath, paintOutline);

    // 5. Left Arm
    final leftArmPath = Path()
      ..moveTo(cx - w * 0.22, h * 0.22)
      ..lineTo(cx - w * 0.32, h * 0.38)
      ..lineTo(cx - w * 0.28, h * 0.52)
      ..lineTo(cx - w * 0.22, h * 0.5)
      ..lineTo(cx - w * 0.24, h * 0.38)
      ..lineTo(cx - w * 0.18, h * 0.26)
      ..close();
    canvas.drawPath(leftArmPath, paintBase);
    canvas.drawPath(leftArmPath, paintOutline);

    // 6. Right Arm
    final rightArmPath = Path()
      ..moveTo(cx + w * 0.22, h * 0.22)
      ..lineTo(cx + w * 0.32, h * 0.38)
      ..lineTo(cx + w * 0.28, h * 0.52)
      ..lineTo(cx + w * 0.22, h * 0.5)
      ..lineTo(cx + w * 0.24, h * 0.38)
      ..lineTo(cx + w * 0.18, h * 0.26)
      ..close();
    canvas.drawPath(rightArmPath, paintBase);
    canvas.drawPath(rightArmPath, paintOutline);

    // 7. Left Leg
    final leftLegPath = Path()
      ..moveTo(cx - w * 0.16, h * 0.58)
      ..lineTo(cx - w * 0.02, h * 0.58)
      ..lineTo(cx - w * 0.04, h * 0.95)
      ..lineTo(cx - w * 0.14, h * 0.95)
      ..close();
    canvas.drawPath(leftLegPath, paintBase);
    canvas.drawPath(leftLegPath, paintOutline);

    // 8. Right Leg
    final rightLegPath = Path()
      ..moveTo(cx + w * 0.02, h * 0.58)
      ..lineTo(cx + w * 0.16, h * 0.58)
      ..lineTo(cx + w * 0.14, h * 0.95)
      ..lineTo(cx + w * 0.04, h * 0.95)
      ..close();
    canvas.drawPath(rightLegPath, paintBase);
    canvas.drawPath(rightLegPath, paintOutline);

    // Highlight target muscle group
    final normalized = muscleGroup.toLowerCase();
    
    if (normalized.contains('chest')) {
      final chestPath = Path()
        ..moveTo(cx - w * 0.18, h * 0.24)
        ..lineTo(cx + w * 0.18, h * 0.24)
        ..lineTo(cx + w * 0.14, h * 0.34)
        ..lineTo(cx - w * 0.14, h * 0.34)
        ..close();
      canvas.drawPath(chestPath, paintActive);
      canvas.drawPath(chestPath, paintActiveOutline);
    } else if (normalized.contains('back') || normalized.contains('lat')) {
      final backPath = Path()
        ..moveTo(cx - w * 0.16, h * 0.26)
        ..lineTo(cx + w * 0.16, h * 0.26)
        ..lineTo(cx + w * 0.12, h * 0.44)
        ..lineTo(cx - w * 0.12, h * 0.44)
        ..close();
      canvas.drawPath(backPath, paintActive);
      canvas.drawPath(backPath, paintActiveOutline);
    } else if (normalized.contains('arm') || normalized.contains('bicep') || normalized.contains('tricep')) {
      canvas.drawPath(leftArmPath, paintActive);
      canvas.drawPath(leftArmPath, paintActiveOutline);
      canvas.drawPath(rightArmPath, paintActive);
      canvas.drawPath(rightArmPath, paintActiveOutline);
    } else if (normalized.contains('shoulder') || normalized.contains('delt')) {
      final leftShoulder = Path()
        ..moveTo(cx - w * 0.24, h * 0.22)
        ..lineTo(cx - w * 0.16, h * 0.22)
        ..lineTo(cx - w * 0.2, h * 0.3)
        ..close();
      final rightShoulder = Path()
        ..moveTo(cx + w * 0.16, h * 0.22)
        ..lineTo(cx + w * 0.24, h * 0.22)
        ..lineTo(cx + w * 0.2, h * 0.3)
        ..close();
      canvas.drawPath(leftShoulder, paintActive);
      canvas.drawPath(leftShoulder, paintActiveOutline);
      canvas.drawPath(rightShoulder, paintActive);
      canvas.drawPath(rightShoulder, paintActiveOutline);
    } else if (normalized.contains('leg') || normalized.contains('quad') || normalized.contains('hamstring') || normalized.contains('glute') || normalized.contains('calf')) {
      canvas.drawPath(leftLegPath, paintActive);
      canvas.drawPath(leftLegPath, paintActiveOutline);
      canvas.drawPath(rightLegPath, paintActive);
      canvas.drawPath(rightLegPath, paintActiveOutline);
    } else if (normalized.contains('core') || normalized.contains('abs')) {
      final absPath = Path()
        ..moveTo(cx - w * 0.12, h * 0.36)
        ..lineTo(cx + w * 0.12, h * 0.36)
        ..lineTo(cx + w * 0.14, h * 0.48)
        ..lineTo(cx - w * 0.14, h * 0.48)
        ..close();
      canvas.drawPath(absPath, paintActive);
      canvas.drawPath(absPath, paintActiveOutline);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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

// ─── Confetti Physics & Celebrations overlay ────────────────────────────────

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

// ─── Exercise Picker bottom sheet ──────────────────────────────────────────

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

// ─── Custom Fullscreen Completion Dashboard ──────────────────────────────────

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
      color: const Color(0xFF0C0C14),
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
                              _buildMetricCol(
                                'WORKOUT SCORE',
                                Row(
                                  children: [
                                    _AnimatedCountUpText(
                                      value: widget.score,
                                      style: const TextStyle(color: KColor.amber, fontSize: 16, fontWeight: FontWeight.w900),
                                    ),
                                    const Text(
                                      ' / 100',
                                      style: TextStyle(color: KColor.textMuted, fontSize: 13, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                              _buildMetricCol(
                                'ACCUMULATED VOLUME',
                                _AnimatedCountUpText(
                                  value: totalVol,
                                  suffix: ' kg',
                                  style: const TextStyle(color: KColor.green, fontSize: 16, fontWeight: FontWeight.w900),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              _buildMetricCol(
                                'SETS COMPLETED',
                                _AnimatedCountUpText(
                                  value: totalSets,
                                  suffix: ' sets',
                                  style: const TextStyle(color: KColor.blue, fontSize: 16, fontWeight: FontWeight.w900),
                                ),
                              ),
                              _buildMetricCol(
                                'SESSION DURATION',
                                Text(
                                  minStr,
                                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
                                ),
                              ),
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

  Widget _buildMetricCol(String title, Widget valueChild) {
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
            valueChild,
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

// ─── Animated Count-Up Text Widget ──────────────────────────────────────────

class _AnimatedCountUpText extends StatefulWidget {
  final num value;
  final TextStyle style;
  final String suffix;
  final String prefix;

  const _AnimatedCountUpText({
    required this.value,
    required this.style,
    this.suffix = '',
    this.prefix = '',
  });

  @override
  State<_AnimatedCountUpText> createState() => _AnimatedCountUpTextState();
}

class _AnimatedCountUpTextState extends State<_AnimatedCountUpText> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  num _oldValue = 0;

  @override
  void initState() {
    super.initState();
    _oldValue = widget.value;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _animation = Tween<double>(begin: widget.value.toDouble(), end: widget.value.toDouble()).animate(_controller);
  }

  @override
  void didUpdateWidget(_AnimatedCountUpText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _oldValue = oldWidget.value;
      _controller.reset();
      _animation = Tween<double>(
        begin: _oldValue.toDouble(),
        end: widget.value.toDouble(),
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final currentVal = _animation.value;
        final valStr = currentVal.toStringAsFixed(0);
        return Text(
          '${widget.prefix}$valStr${widget.suffix}',
          style: widget.style,
        );
      },
    );
  }
}
