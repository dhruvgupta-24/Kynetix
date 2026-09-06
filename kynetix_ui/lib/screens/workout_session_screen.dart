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
import '../widgets/exercise_picker_sheet.dart';
import '../widgets/barbell_plate_calculator.dart';
import '../services/wakelock_service.dart';
import '../services/superset_flow_service.dart';

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
  int get selectedIndex => _selectedIndex;
  bool _isSaving = false;
  bool _isDiscarding = false;

  final GlobalKey _dockKey = GlobalKey();
  double _dockHeight = 160.0;

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

  // Execution tracking maps
  final Map<String, bool> _skippedExercises = {};
  final Map<String, String> _skipReasons = {};
  final Map<String, bool> _substitutedExercises = {};
  final Map<String, String> _substitutedForIds = {};
  final Map<String, String> _substitutedForNames = {};
  final Map<String, Exercise> _replacedOriginalExercises = {};
  final Map<String, bool> _temporaryAdditions = {};

  final _service = WorkoutService.instance;
  late DateTime _startTime;

  // Floating text particles tracker
  final List<_FloatingTextData> _floatingTexts = [];
  final ValueNotifier<int> _scoreNotifier = ValueNotifier<int>(0);
  double _scoreCompletion = 0.0;
  double _scoreVolume = 0.0;
  double _scoreSets = 0.0;
  double _scorePrs = 0.0;
  int _e1rmPrsCount = 0;

  // Rest Timer State
  int _restSecondsRemaining = 0;
  Timer? _restTimer;
  bool _isRestTimerActive = false;

  void _startRestTimer({int durationSeconds = 90}) {
    _restTimer?.cancel();
    setState(() {
      _restSecondsRemaining = durationSeconds;
      _isRestTimerActive = true;
    });
    _restTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_restSecondsRemaining <= 1) {
        timer.cancel();
        setState(() {
          _restSecondsRemaining = 0;
          _isRestTimerActive = false;
        });
        HapticFeedback.heavyImpact();
      } else {
        setState(() {
          _restSecondsRemaining--;
        });
      }
    });
  }

  void _adjustRestTimer(int deltaSeconds) {
    if (!_isRestTimerActive) return;
    setState(() {
      _restSecondsRemaining = (_restSecondsRemaining + deltaSeconds).clamp(5, 600);
    });
    HapticFeedback.selectionClick();
  }

  void _skipRestTimer() {
    _restTimer?.cancel();
    setState(() {
      _restSecondsRemaining = 0;
      _isRestTimerActive = false;
    });
    HapticFeedback.lightImpact();
  }

  // PR Celebration State (Non-blocking)
  bool _showPrToast = false;
  String _prToastMsg = '';

  // Completion State
  bool _showCompletionScreen = false;
  late WorkoutSession _completedSessionSummary;
  bool _enableRpeTracking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockService.instance.enable();
    
    print('initState _selectedIndex: $_selectedIndex');
    print('initState draftSession: ${widget.draftSession}');
    _startTime = widget.draftSession?.date ?? DateTime.now();
    _pageController = PageController(initialPage: _selectedIndex);
    _loadRpeSetting();

    final draft = widget.draftSession;
    if (draft != null) {
      _sessionNotes = draft.notes ?? '';
      _sessionExercises = draft.entries.map((e) => e.exercise).toList();

      for (final ex in _sessionExercises) {
        _sets[ex.id] = [];
        _setTypeSelections[ex.id] = SetType.normal;
        _rpeSelections[ex.id] = 8.0;

        final matchingEntry = draft.entries.where((e) => e.exercise.id == ex.id).firstOrNull;
        if (matchingEntry != null) {
          _sets[ex.id] = matchingEntry.sets.toList();
          if (matchingEntry.notes != null) {
            _exerciseNotes[ex.id] = matchingEntry.notes!;
          }
          // Restore draft execution state
          _skippedExercises[ex.id] = matchingEntry.isSkipped;
          if (matchingEntry.skipReason != null) {
            _skipReasons[ex.id] = matchingEntry.skipReason!;
          }
          _substitutedExercises[ex.id] = matchingEntry.isSubstitution;
          if (matchingEntry.substitutedForExerciseId != null) {
            _substitutedForIds[ex.id] = matchingEntry.substitutedForExerciseId!;
          }
          if (matchingEntry.substitutedForExerciseName != null) {
            _substitutedForNames[ex.id] = matchingEntry.substitutedForExerciseName!;
          }
          _temporaryAdditions[ex.id] = matchingEntry.isTemporaryAddition;
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
    } else {
      _sessionExercises = List.of(widget.splitDay.exercises);

      for (final ex in _sessionExercises) {
        _sets[ex.id] = [];
        _setTypeSelections[ex.id] = SetType.normal;
        _rpeSelections[ex.id] = 8.0;

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

      // Clear recovery state to make sure it's fresh
      SharedPreferences.getInstance().then((prefs) {
        prefs.remove('kynetix_workout_recovery');
      });
      _updateLiveScore();
    }
  }

  void _loadRpeSetting() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _enableRpeTracking = prefs.getBool('enable_rpe_tracking') ?? false;
      });
    }
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
    _restTimer?.cancel();
    WakelockService.instance.disable();
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

  void _measureDock() {
    if (!mounted) return;
    final context = _dockKey.currentContext;
    if (context != null) {
      final renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox != null && renderBox.hasSize) {
        final height = renderBox.size.height;
        if (height != _dockHeight) {
          setState(() {
            _dockHeight = height;
          });
        }
      }
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
      'sessionExercises': _sessionExercises.map((e) => e.toJson()).toList(),
      'skippedExercises': _skippedExercises,
      'skipReasons': _skipReasons,
      'substitutedExercises': _substitutedExercises,
      'substitutedForIds': _substitutedForIds,
      'substitutedForNames': _substitutedForNames,
      'replacedOriginalExercises': _replacedOriginalExercises.map((k, v) => MapEntry(k, v.toJson())),
      'temporaryAdditions': _temporaryAdditions,
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
          final rawExercises = data['sessionExercises'] as List<dynamic>?;
          if (rawExercises != null && rawExercises.isNotEmpty) {
            _sessionExercises = rawExercises
                .map((e) => Exercise.fromJson(e as Map<String, dynamic>))
                .toList();
          }

          _selectedIndex = _sessionExercises.isEmpty
              ? 0
              : (data['selectedIndex'] as int? ?? 0).clamp(0, _sessionExercises.length - 1);
          
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

          final skipped = data['skippedExercises'] as Map<String, dynamic>?;
          if (skipped != null) {
            skipped.forEach((k, v) => _skippedExercises[k] = v as bool);
          }

          final skipReasons = data['skipReasons'] as Map<String, dynamic>?;
          if (skipReasons != null) {
            skipReasons.forEach((k, v) => _skipReasons[k] = v as String);
          }

          final subbed = data['substitutedExercises'] as Map<String, dynamic>?;
          if (subbed != null) {
            subbed.forEach((k, v) => _substitutedExercises[k] = v as bool);
          }

          final subbedIds = data['substitutedForIds'] as Map<String, dynamic>?;
          if (subbedIds != null) {
            subbedIds.forEach((k, v) => _substitutedForIds[k] = v as String);
          }

          final subbedNames = data['substitutedForNames'] as Map<String, dynamic>?;
          if (subbedNames != null) {
            subbedNames.forEach((k, v) => _substitutedForNames[k] = v as String);
          }

          final replacedOrig = data['replacedOriginalExercises'] as Map<String, dynamic>?;
          if (replacedOrig != null) {
            replacedOrig.forEach((k, v) {
              try {
                _replacedOriginalExercises[k] = Exercise.fromJson(v as Map<String, dynamic>);
              } catch (_) {}
            });
          }

          final tempAdditions = data['temporaryAdditions'] as Map<String, dynamic>?;
          if (tempAdditions != null) {
            tempAdditions.forEach((k, v) => _temporaryAdditions[k] = v as bool);
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
    if (_isSaving || _isDiscarding) return;
    final entries = _sessionExercises
        .map((ex) => ExerciseEntry(
              exercise: ex,
              sets: _sets[ex.id] ?? [],
              notes: _exerciseNotes[ex.id],
              isSkipped: _skippedExercises[ex.id] ?? false,
              skipReason: _skipReasons[ex.id],
              isSubstitution: _substitutedExercises[ex.id] ?? false,
              substitutedForExerciseId: _substitutedForIds[ex.id],
              substitutedForExerciseName: _substitutedForNames[ex.id],
              isTemporaryAddition: _temporaryAdditions[ex.id] ?? false,
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

  // ── Execution Handling Operations ────────────────────────────────────────

  void _skipExercise(String exerciseId, String reason) {
    setState(() {
      _skippedExercises[exerciseId] = true;
      _skipReasons[exerciseId] = reason;
      _sets[exerciseId] = []; // Clear sets on skip
    });
    _spawnFloatingText('Exercise Skipped');
    HapticFeedback.mediumImpact();
    _updateLiveScore();
    _saveRecoveryState();
  }

  void _undoSkip(String exerciseId) {
    setState(() {
      _skippedExercises[exerciseId] = false;
      _skipReasons.remove(exerciseId);
    });
    HapticFeedback.lightImpact();
    _updateLiveScore();
    _saveRecoveryState();
  }

  @visibleForTesting
  List<Exercise> get activeSessionExercisesForTest => _sessionExercises;

  @visibleForTesting
  void replaceExerciseForTest(String originalId, Exercise replacement) => _replaceExercise(originalId, replacement);

  @visibleForTesting
  void undoReplacementForTest(String originalId) => _undoReplacement(originalId);

  void _printReplacementRuntimeAuditTrace(String action) {
    final originalWorkoutCount = widget.splitDay.exercises.length;
    final activeCount = _sessionExercises.length;
    final navCount = _sessionExercises.length;
    final progressCount = _sessionExercises.length;
    final headerTotalCount = _sessionExercises.length;
    final activeIds = _sessionExercises.map((e) => e.id).toList();
    final masterIds = _sessionExercises.map((e) => e.id).toList();
    final replacedIds = _substitutedForIds.values.toList();
    final replacementMap = _substitutedForIds.map((repId, origId) => MapEntry(origId, repId));
    final currentIdx = _selectedIndex;
    final displayedXofY = 'EXERCISE ${currentIdx + 1} OF $headerTotalCount';

    print('\n=================== EXERCISE REPLACEMENT RUNTIME AUDIT TRACE ($action) ===================');
    print('  - Original workout exercise count: $originalWorkoutCount');
    print('  - Active exercise count:           $activeCount');
    print('  - Navigation exercise count:       $navCount');
    print('  - Progress exercise count:         $progressCount');
    print('  - Header total count:              $headerTotalCount');
    print('  - Exercise IDs in active list:     $activeIds');
    print('  - Exercise IDs in master workout list: $masterIds');
    print('  - Exercise IDs marked as replaced: $replacedIds');
    print('  - Replacement mapping (old -> new): $replacementMap');
    print('  - Current exercise index:          $currentIdx');
    print('  - Displayed "X of Y":              $displayedXofY');
    print('========================================================================================\n');
  }

  void _replaceExercise(String originalId, Exercise replacement) {
    final idx = _sessionExercises.indexWhere((e) => e.id == originalId);
    if (idx == -1) return;
    
    final originalEx = _sessionExercises[idx];
    final repId = replacement.id;

    setState(() {
      _replacedOriginalExercises[originalId] = originalEx;
      _replacedOriginalExercises[repId] = originalEx;

      _sets[repId] = [];
      _setTypeSelections[repId] = SetType.normal;
      _rpeSelections[repId] = 8.0;
      _weightSelections[repId] = 40.0;
      _repsSelections[repId] = 10;
      
      _substitutedExercises[repId] = true;
      _substitutedForIds[repId] = originalId;
      _substitutedForNames[repId] = originalEx.name;
      
      // Replace IN-PLACE in the single canonical active exercise list
      _sessionExercises[idx] = replacement;
      _selectedIndex = idx;
    });

    _printReplacementRuntimeAuditTrace('REPLACE_EXERCISE');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients) {
        _pageController.animateToPage(
          _selectedIndex,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
      }
    });
    _spawnFloatingText('Substituted');
    HapticFeedback.mediumImpact();
    _updateLiveScore();
    _saveRecoveryState();
  }

  void _undoReplacement(String originalId) {
    final idx = _sessionExercises.indexWhere((e) => _substitutedForIds[e.id] == originalId || e.id == originalId);
    if (idx == -1) return;

    final replacement = _sessionExercises[idx];
    final originalEx = _replacedOriginalExercises[originalId] ?? _replacedOriginalExercises[replacement.id];

    if (originalEx != null) {
      setState(() {
        _sessionExercises[idx] = originalEx;
        _sets.remove(replacement.id);
        _weightSelections.remove(replacement.id);
        _repsSelections.remove(replacement.id);
        _rpeSelections.remove(replacement.id);
        _setTypeSelections.remove(replacement.id);
        _substitutedExercises.remove(replacement.id);
        _substitutedForIds.remove(replacement.id);
        _substitutedForNames.remove(replacement.id);
        _replacedOriginalExercises.remove(originalId);
        _replacedOriginalExercises.remove(replacement.id);
        _skippedExercises.remove(originalId);
        _skipReasons.remove(originalId);
        _selectedIndex = idx;
      });

      _printReplacementRuntimeAuditTrace('UNDO_REPLACEMENT');

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients) {
          _pageController.jumpToPage(_selectedIndex);
        }
      });
      HapticFeedback.lightImpact();
      _updateLiveScore();
      _saveRecoveryState();
    }
  }

  Future<void> _addExtraExercise(Exercise relativeTo, bool before) async {
    final currentIds = _sessionExercises.map((e) => e.id).toSet();
    final picked = await showExercisePickerSheet(
      context,
      excludeIds: currentIds,
    );

    if (!mounted || picked == null) return;
    
    final relIdx = _sessionExercises.indexOf(relativeTo);
    if (relIdx == -1) return;
    
    final insertIdx = before ? relIdx : relIdx + 1;
    
    setState(() {
      _sessionExercises.insert(insertIdx, picked);
      _sets[picked.id] = [];
      _setTypeSelections[picked.id] = SetType.normal;
      _rpeSelections[picked.id] = 8.0;
      _weightSelections[picked.id] = 40.0;
      _repsSelections[picked.id] = 10;
      _temporaryAdditions[picked.id] = true;
      _selectedIndex = insertIdx;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(_selectedIndex);
      }
    });
    _saveRecoveryState();
  }

  Future<void> _showReplacementPicker(String originalId) async {
    final currentIds = _sessionExercises.map((e) => e.id).toSet()..remove(originalId);
    final picked = await showExercisePickerSheet(
      context,
      excludeIds: currentIds,
    );

    if (picked != null) {
      _replaceExercise(originalId, picked);
    }
  }

  void _showReorderSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2C),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return _ReorderExercisesSheet(
          exercises: _sessionExercises,
          onReorder: (oldIndex, newIndex) {
            setState(() {
              if (oldIndex < newIndex) {
                newIndex -= 1;
              }
              final Exercise item = _sessionExercises.removeAt(oldIndex);
              _sessionExercises.insert(newIndex, item);
              
              if (_selectedIndex == oldIndex) {
                _selectedIndex = newIndex;
              } else if (oldIndex < _selectedIndex && newIndex >= _selectedIndex) {
                _selectedIndex -= 1;
              } else if (oldIndex > _selectedIndex && newIndex <= _selectedIndex) {
                _selectedIndex += 1;
              }
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_pageController.hasClients) {
                _pageController.jumpToPage(_selectedIndex);
              }
            });
            _saveRecoveryState();
          },
        );
      },
    );
  }

  Future<void> _addExercisePermanently(Exercise exercise) async {
    final currentSplit = _service.split;
    final days = currentSplit.days.map((day) {
      if (day.name == widget.splitDay.name) {
        if (!day.exercises.any((e) => e.id == exercise.id)) {
          return day.copyWith(exercises: [...day.exercises, exercise]);
        }
      }
      return day;
    }).toList();
    
    final updatedSplit = currentSplit.copyWith(days: days);
    await _service.saveSplit(updatedSplit);
    
    // Track recommendation acceptance
    _service.trackRecommendationAccepted(exercise.id, widget.splitDay.name);
    
    setState(() {
      _temporaryAdditions[exercise.id] = false;
    });
    
    _spawnFloatingText('Added to ${widget.splitDay.name}!');
  }

  Future<void> _replaceExercisePermanently(Exercise original, Exercise replacement) async {
    final currentSplit = _service.split;
    final days = currentSplit.days.map((day) {
      if (day.name == widget.splitDay.name) {
        final idx = day.exercises.indexWhere((e) => e.id == original.id);
        if (idx != -1) {
          final list = List<Exercise>.from(day.exercises);
          list[idx] = replacement;
          return day.copyWith(exercises: list);
        }
      }
      return day;
    }).toList();
    
    final updatedSplit = currentSplit.copyWith(days: days);
    await _service.saveSplit(updatedSplit);
    
    setState(() {
      final idx = _sessionExercises.indexWhere((e) => e.id == replacement.id);
      if (idx != -1) {
        _substitutedExercises[replacement.id] = false;
        _substitutedForIds.remove(replacement.id);
        _substitutedForNames.remove(replacement.id);
      }
      _sessionExercises.removeWhere((e) => e.id == original.id);
      _sets.remove(original.id);
      _weightSelections.remove(original.id);
      _repsSelections.remove(original.id);
      _rpeSelections.remove(original.id);
      _setTypeSelections.remove(original.id);
      
      _selectedIndex = _sessionExercises.isEmpty ? 0 : _selectedIndex.clamp(0, _sessionExercises.length - 1);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients && _sessionExercises.isNotEmpty) {
        _pageController.jumpToPage(_selectedIndex);
      }
    });

    _spawnFloatingText('Updated split permanently!');
    await _saveRecoveryState();
  }

  Future<void> _removeExercisePermanently(Exercise exercise) async {
    final currentSplit = _service.split;
    final days = currentSplit.days.map((day) {
      if (day.name == widget.splitDay.name) {
        final list = List<Exercise>.from(day.exercises)..removeWhere((e) => e.id == exercise.id);
        return day.copyWith(exercises: list);
      }
      return day;
    }).toList();
    
    final updatedSplit = currentSplit.copyWith(days: days);
    await _service.saveSplit(updatedSplit);

    setState(() {
      _sessionExercises.removeWhere((e) => e.id == exercise.id);
      _sets.remove(exercise.id);
      _weightSelections.remove(exercise.id);
      _repsSelections.remove(exercise.id);
      _rpeSelections.remove(exercise.id);
      _setTypeSelections.remove(exercise.id);
      _skippedExercises.remove(exercise.id);
      _skipReasons.remove(exercise.id);
      
      _selectedIndex = _sessionExercises.isEmpty ? 0 : _selectedIndex.clamp(0, _sessionExercises.length - 1);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients && _sessionExercises.isNotEmpty) {
        _pageController.jumpToPage(_selectedIndex);
      }
    });

    _spawnFloatingText('Removed permanently!');
    await _saveRecoveryState();
  }

  Future<void> _applyReorderPermanently(List<Exercise> newOrder) async {
    final currentSplit = _service.split;
    final days = currentSplit.days.map((day) {
      if (day.name == widget.splitDay.name) {
        return day.copyWith(exercises: newOrder);
      }
      return day;
    }).toList();
    
    final updatedSplit = currentSplit.copyWith(days: days);
    await _service.saveSplit(updatedSplit);

    setState(() {
      final newOrderIds = newOrder.map((e) => e.id).toList();
      _sessionExercises.sort((a, b) {
        final idxA = newOrderIds.indexOf(a.id);
        final idxB = newOrderIds.indexOf(b.id);
        if (idxA != -1 && idxB != -1) return idxA.compareTo(idxB);
        if (idxA != -1) return -1;
        if (idxB != -1) return 1;
        return 0;
      });
      _selectedIndex = 0;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(_selectedIndex);
      }
    });

    _spawnFloatingText('Reordered split sequence!');
    await _saveRecoveryState();
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

  double get _primaryWorkingVolume {
    double vol = 0.0;
    _sets.forEach((_, list) {
      for (final s in list) {
        if (s.isMainWorkingSet) {
          vol += s.volume;
        }
      }
    });
    return vol;
  }

  ExerciseEntry buildEntry(Exercise ex) {
    return ExerciseEntry(
      exercise: ex,
      sets: _sets[ex.id] ?? [],
      isSkipped: _skippedExercises[ex.id] ?? false,
      notes: _exerciseNotes[ex.id],
      isSubstitution: _substitutedExercises[ex.id] ?? false,
      substitutedForExerciseId: _substitutedForIds[ex.id],
      substitutedForExerciseName: _substitutedForNames[ex.id],
      isTemporaryAddition: _temporaryAdditions[ex.id] ?? false,
    );
  }

  double get _completionProgress {
    if (_sessionExercises.isEmpty) return 0.0;
    double totalRatio = 0.0;
    for (final ex in _sessionExercises) {
      final entry = buildEntry(ex);
      if (entry.isSkipped) {
        totalRatio += 1.0;
        continue;
      }
      final targetSets = entry.exercise.targetSets;
      final targetRepMin = entry.exercise.targetRepMin;
      final workingSets = entry.sets.where((s) => s.isMainWorkingSet).toList();
      
      final setRatio = targetSets > 0 ? entry.completedWorkingSetsCount / targetSets : 1.0;
      
      double totalSetRepScore = 0.0;
      for (final s in workingSets) {
        if (targetRepMin > 0) {
          totalSetRepScore += (s.reps / targetRepMin).clamp(0.0, 1.0);
        } else {
          totalSetRepScore += 1.0;
        }
      }
      final repRatio = targetSets > 0 ? totalSetRepScore / targetSets : 1.0;
      
      final ratioEx = (setRatio < repRatio ? setRatio : repRatio).clamp(0.0, 1.0);
      totalRatio += ratioEx;
    }
    return totalRatio / _sessionExercises.length;
  }

  void _updateLiveScore() {
    if (_sessionExercises.isEmpty) {
      _scoreCompletion = 0.0;
      _scoreVolume = 0.0;
      _scoreSets = 0.0;
      _scorePrs = 0.0;
      _e1rmPrsCount = 0;
      _scoreNotifier.value = 0;
      return;
    }
    
    // 1. Completion of exercises (up to 30 points) using rep midpoint ratio
    final avgCompletionRatio = _completionProgress;
    final completionScore = avgCompletionRatio * 30.0;
    
    // 2. Volume score (up to 30 points) based on primary working volume only
    final currentVolume = _primaryWorkingVolume;
    final lastVolume = widget.previousSession?.primaryWorkingVolume ?? 2000.0;
    final volumeScore = lastVolume > 0 ? (currentVolume / lastVolume * 30.0).clamp(0.0, 30.0) : 15.0;
    
    // 3. Set completion score (up to 25 points) based on primary working sets vs target
    double loggedSetsScore = 0.0;
    int activeExercises = 0;
    for (final ex in _sessionExercises) {
      final entry = buildEntry(ex);
      if (entry.isSkipped) continue;
      activeExercises++;
      final logged = entry.completedWorkingSetsCount;
      final target = entry.exercise.targetSets > 0 ? entry.exercise.targetSets : 3;
      loggedSetsScore += (logged / target).clamp(0.0, 1.0);
    }
    final setsScore = activeExercises > 0 ? (loggedSetsScore / activeExercises) * 25.0 : 25.0;
    
    // 4. PRs score (up to 15 points) based on e1RM PRs from primary working sets
    int prCount = 0;
    _sets.forEach((exId, list) {
      for (final s in list) {
        if (s.isMainWorkingSet) {
          final previousBest = _service.bestSetBefore(exId, widget.date);
          if (previousBest != null && s.estimatedOneRepMax > previousBest.estimatedOneRepMax + 0.01) {
            prCount++;
          }
        }
      }
    });
    final prScore = (prCount * 5.0).clamp(0.0, 15.0);

    // Save breakdown values
    _scoreCompletion = completionScore;
    _scoreVolume = volumeScore;
    _scoreSets = setsScore;
    _scorePrs = prScore;
    _e1rmPrsCount = prCount;

    _scoreNotifier.value = (completionScore + volumeScore + setsScore + prScore).round().clamp(0, 100);
  }

  // ── Logging Operations ───────────────────────────────────────────────────

  Future<void> _logSet() async {
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
      (_sets[ex.id] ??= []).add(newSet);
    });

    _updateLiveScore();
    await _saveRecoveryState();

    _spawnFloatingText('+1 Set\n+${(w * r).toStringAsFixed(0)} kg');
    HapticFeedback.mediumImpact();

    if (isPr) {
      HapticFeedback.heavyImpact();
      _triggerPRNotification(w, r, newSet.estimatedOneRepMax);
    }

    // Start rest timer on set completion
    _startRestTimer(durationSeconds: ex.type == ExerciseType.barbellCompound ? 90 : 60);

    // Superset round auto-navigation
    if (ex.supersetGroupId != null && ex.supersetGroupId!.isNotEmpty) {
      final status = SupersetFlowService.getStatusForGroup(
        supersetGroupId: ex.supersetGroupId!,
        allExercises: _sessionExercises,
        entriesMap: {for (final e in _sessionExercises) e.id: buildEntry(e)},
      );
      if (status != null && !status.isCompleted && status.nextExercise != null) {
        final nextEx = status.nextExercise!;
        final nextIdx = _sessionExercises.indexWhere((e) => e.id == nextEx.id);
        if (nextIdx != -1 && nextIdx != _selectedIndex) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted && _pageController.hasClients) {
              setState(() => _selectedIndex = nextIdx);
              _pageController.animateToPage(
                nextIdx,
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
              );
            }
          });
          return;
        }
      }
    }

    // Auto-advance if completed
    final entry = buildEntry(ex);
    if (entry.isCompleted) {
      if (_selectedIndex < _sessionExercises.length - 1) {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) {
            // Find current index of this exercise (in case list was modified)
            final currentIdx = _sessionExercises.indexWhere((e) => e.id == ex.id);
            if (currentIdx == _selectedIndex && _selectedIndex < _sessionExercises.length - 1) {
              final currentEntryAfterDelay = buildEntry(ex);
              if (currentEntryAfterDelay.isCompleted) {
                setState(() {
                  _selectedIndex++;
                });
                if (_pageController.hasClients) {
                  _pageController.animateToPage(
                    _selectedIndex,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                  );
                }
              }
            }
          }
        });
      }
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
    final entries = _sessionExercises
        .map((ex) => ExerciseEntry(
              exercise: ex,
              sets: _sets[ex.id] ?? [],
              notes: _exerciseNotes[ex.id],
              isSkipped: _skippedExercises[ex.id] ?? false,
              skipReason: _skipReasons[ex.id],
              isSubstitution: _substitutedExercises[ex.id] ?? false,
              substitutedForExerciseId: _substitutedForIds[ex.id],
              substitutedForExerciseName: _substitutedForNames[ex.id],
              isTemporaryAddition: _temporaryAdditions[ex.id] ?? false,
            ))
        .where((entry) => !entry.isEmpty)
        .toList();

    if (entries.isEmpty) {
      _showSnack('Log at least one set or skip/substitute an exercise before finishing.');
      return;
    }

    final statusResult = await showDialog<WorkoutStatus>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: KColor.border, width: 0.5),
        ),
        actionsOverflowDirection: VerticalDirection.down,
        title: const Text('End Workout Session', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Choose how you want to save this session. If you intentionally cut it short, choose Partial.',
          style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF9CA3AF))),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(WorkoutStatus.partial),
            child: const Text('Finish As Partial', style: TextStyle(color: Color(0xFFFFB347))),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(WorkoutStatus.completed),
            child: const Text('Finish Workout', style: TextStyle(color: Color(0xFF52B788), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (statusResult == null) return;

    setState(() => _isSaving = true);

    final session = WorkoutSession(
      id: 'ws_${DateTime.now().millisecondsSinceEpoch}',
      date: widget.date,
      splitDayName: widget.splitDay.name,
      splitDayWeekday: widget.splitDay.weekday == 0 ? null : widget.splitDay.weekday,
      wasManuallySelected: widget.wasManuallySelected,
      entries: entries,
      notes: _sessionNotes,
      durationMinutes: DateTime.now().difference(_startTime).inMinutes,
      status: statusResult,
      plannedExercises: widget.splitDay.exercises,
    );

    // Track ignored recommendations for temporary additions that were not made permanent
    for (final ex in _sessionExercises) {
      if (_temporaryAdditions[ex.id] == true &&
          _service.getRecurringAdditions(widget.splitDay.name).any((re) => re.exercise.id == ex.id)) {
        _service.trackRecommendationIgnored(ex.id, widget.splitDay.name);
      }
    }

    await _service.saveSession(session);
    await _service.clearDraftSession();

    // Save logs integration
    final log = logFor(widget.date);
    if (log.gymDay?.didGym != true) {
      if (log.gymDay != null) {
        log.gymDay = log.gymDay!.withGym(true);
      } else {
        log.gymDay = const GymDay(didGym: true);
      }
      await PersistenceService.saveDay(widget.date);
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('kynetix_workout_recovery');
      await _service.clearDraftSession();
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actionsOverflowDirection: VerticalDirection.down,
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
    final picked = await showExercisePickerSheet(
      context,
      excludeIds: currentIds,
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
    _saveRecoveryState();
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
          actionsOverflowDirection: VerticalDirection.down,
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
      _selectedIndex = _sessionExercises.isEmpty ? 0 : _selectedIndex.clamp(0, _sessionExercises.length - 1);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients && _sessionExercises.isNotEmpty) {
        _pageController.jumpToPage(_selectedIndex);
      }
    });
    _saveRecoveryState();
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
    if (MediaQuery.of(context).viewInsets.bottom == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measureDock());
    }
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
                    child: _sessionExercises.isEmpty
                        ? _buildEmptyState()
                        : LayoutBuilder(
                            builder: (context, constraints) {
                        final isWide = constraints.maxWidth > 600;
                        return PageView.builder(
                          controller: _pageController,
                          itemCount: _sessionExercises.length,
                          onPageChanged: (index) {
                            print('PageView onPageChanged called with index: $index');
                            print(StackTrace.current.toString().split('\n').take(60).join('\n'));
                            HapticFeedback.selectionClick();
                            setState(() => _selectedIndex = index);
                            _saveRecoveryState();
                          },
                          itemBuilder: (context, index) {
                            final ex = _sessionExercises[index];
                            final setsList = _sets[ex.id] ?? [];
                            final lastEntry = _service.lastEntryFor(ex.id, widget.splitDay.name);
                            final history = _service.historyFor(ex.id, limit: 5);

                            final recurringSubs = _service.getRecurringSubstitutions(widget.splitDay.name);
                            final subMatch = recurringSubs.where((s) => s.original.id == ex.id).firstOrNull;
                            final replacementEx = subMatch?.replacement;

                            final recurringSkips = _service.getRecurringSkips(widget.splitDay.name);
                            final isRecSkip = recurringSkips.any((s) => s.exercise.id == ex.id);

                            final reorderRecs = _service.getReorderRecommendations(widget.splitDay.name);
                            final reorderOrder = reorderRecs.isNotEmpty ? reorderRecs.first.newOrder : null;

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
                              dockHeight: MediaQuery.of(context).viewInsets.bottom > 0 ? 0.0 : _dockHeight,
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
                              isSkipped: _skippedExercises[ex.id] ?? false,
                              skipReason: _skipReasons[ex.id],
                              isSubstitution: _substitutedExercises[ex.id] ?? false,
                              substitutedForName: _substitutedForNames[ex.id],
                              isTemporaryAddition: _temporaryAdditions[ex.id] ?? false,
                              isRecurringAddition: _service
                                  .getRecurringAdditions(widget.splitDay.name)
                                  .any((re) => re.exercise.id == ex.id),
                              splitDayName: widget.splitDay.name,
                              onSkipExercise: (reason) => _skipExercise(ex.id, reason),
                              onUndoSkip: () => _undoSkip(ex.id),
                              onReplaceExercise: (replacement) => _showReplacementPicker(ex.id),
                              onAddExtraExercise: (relativeTo, before) => _addExtraExercise(relativeTo, before),
                              onReorderExercises: _showReorderSheet,
                              onUndoReplacement: () => _undoReplacement(ex.id),
                              onAddPermanently: () => _addExercisePermanently(ex),
                              enableRpeTracking: _enableRpeTracking,
                              recurringSubstitutionReplacement: replacementEx,
                              isRecurringSkip: isRecSkip,
                              reorderRecommendation: reorderOrder,
                              onReplacePermanently: () => _replaceExercisePermanently(ex, replacementEx!),
                              onRemovePermanently: () => _removeExercisePermanently(ex),
                              onApplyReorder: () => _applyReorderPermanently(reorderOrder!),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            // Floating Rest Timer Bar
            _buildFloatingRestTimer(),

            // Pinned Bottom Command Center Dock
            if (MediaQuery.of(context).viewInsets.bottom == 0)
              Positioned(
                key: _dockKey,
                left: 0,
                right: 0,
                bottom: 0,
                child: _BottomDockWidget(
                exercises: _sessionExercises,
                originalSplitExerciseCount: widget.splitDay.exercises.length,
                sets: _sets,
                skippedExercises: _skippedExercises,
                substitutedExercises: _substitutedExercises,
                temporaryAdditions: _temporaryAdditions,
                selectedIndex: _selectedIndex,
                splitDayName: widget.splitDay.name,
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
                onSelectExercise: (index) {
                  setState(() => _selectedIndex = index);
                  _pageController.jumpToPage(index);
                },
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
                scoreCompletion: _scoreCompletion,
                scoreVolume: _scoreVolume,
                scoreSets: _scoreSets,
                scorePrs: _scorePrs,
                e1rmPrsCount: _e1rmPrsCount,
                duration: DateTime.now().difference(_startTime),
                onDone: () => Navigator.of(context).pop(true),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingRestTimer() {
    if (!_isRestTimerActive || _restSecondsRemaining <= 0) return const SizedBox.shrink();
    final mins = _restSecondsRemaining ~/ 60;
    final secs = _restSecondsRemaining % 60;
    final timeStr = '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';

    return Positioned(
      left: 16,
      right: 16,
      bottom: _dockHeight + 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF141628),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: KColor.green.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: KColor.green,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'REST',
                style: TextStyle(
                  color: KColor.green,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                timeStr,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 12),
              _buildRestTimerBtn('-15s', () => _adjustRestTimer(-15)),
              const SizedBox(width: 6),
              _buildRestTimerBtn('+30s', () => _adjustRestTimer(30)),
              const SizedBox(width: 8),
              InkWell(
                onTap: _skipRestTimer,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'SKIP',
                    style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRestTimerBtn(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1E2034),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF2E3248)),
        ),
        child: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildSessionAppBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 24),
                onPressed: _confirmDiscard,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
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
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      children: [
                        _LiveTimerWidget(startedAt: _startTime),
                        const Text('•', style: TextStyle(color: KColor.textMuted)),
                        Text(
                          '$_totalSets sets',
                          style: const TextStyle(color: KColor.textSecondary, fontSize: 12),
                        ),
                        const Text('•', style: TextStyle(color: KColor.textMuted)),
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
            ],
          ),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
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
                      mainAxisSize: MainAxisSize.min,
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

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: KColor.green.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.fitness_center_rounded,
                color: KColor.green,
                size: 64,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Empty Workout Session',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Add your first exercise to start tracking your sets, weight, reps, and RPE.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: KColor.textSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 200,
              height: 48,
              child: ElevatedButton.icon(
                key: const Key('center_add_exercise_button'),
                onPressed: _addExerciseToSession,
                icon: const Icon(Icons.add_rounded, color: Colors.white),
                label: const Text('Add Exercise', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: KColor.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
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
  final double dockHeight;

  // Execution tracking properties
  final bool isSkipped;
  final String? skipReason;
  final bool isSubstitution;
  final String? substitutedForName;
  final bool isTemporaryAddition;
  final bool isRecurringAddition;
  final String splitDayName;
  final bool enableRpeTracking;
  final Exercise? recurringSubstitutionReplacement;
  final bool isRecurringSkip;
  final List<Exercise>? reorderRecommendation;

  // Execution callbacks
  final Function(String) onSkipExercise;
  final VoidCallback onUndoSkip;
  final Function(Exercise) onReplaceExercise;
  final Function(Exercise, bool) onAddExtraExercise;
  final VoidCallback onReorderExercises;
  final VoidCallback onUndoReplacement;
  final VoidCallback onAddPermanently;
  final VoidCallback onReplacePermanently;
  final VoidCallback onRemovePermanently;
  final VoidCallback onApplyReorder;

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
    required this.dockHeight,
    required this.isSkipped,
    required this.skipReason,
    required this.isSubstitution,
    this.substitutedForName,
    required this.isTemporaryAddition,
    required this.isRecurringAddition,
    required this.splitDayName,
    required this.enableRpeTracking,
    required this.recurringSubstitutionReplacement,
    required this.isRecurringSkip,
    required this.reorderRecommendation,
    required this.onSkipExercise,
    required this.onUndoSkip,
    required this.onReplaceExercise,
    required this.onAddExtraExercise,
    required this.onReorderExercises,
    required this.onUndoReplacement,
    required this.onAddPermanently,
    required this.onReplacePermanently,
    required this.onRemovePermanently,
    required this.onApplyReorder,
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
  bool _showCues = false;

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

      if (_weightScrollController.hasClients) {
        _weightScrollController.jumpToItem(wIndex);
      }
      if (_repsScrollController.hasClients) {
        _repsScrollController.jumpToItem(rIndex);
      }

      _notesController.text = widget.initialNotes;
      _sessionNotesController.text = widget.sessionNotes;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(widget.initialScrollOffset);
      }
    } else {
      // Exercise is the same, but values might have restored asynchronously
      if (_selectedWeight != widget.initialWeight) {
        _selectedWeight = widget.initialWeight;
        final wIndex = (_selectedWeight / 0.5).round().clamp(0, 700);
        if (_weightScrollController.hasClients) {
          _weightScrollController.jumpToItem(wIndex);
        }
      }
      if (_selectedReps != widget.initialReps) {
        _selectedReps = widget.initialReps;
        final rIndex = (_selectedReps - 1).clamp(0, 99);
        if (_repsScrollController.hasClients) {
          _repsScrollController.jumpToItem(rIndex);
        }
      }
      if (_selectedRpe != widget.initialRpe) {
        _selectedRpe = widget.initialRpe;
      }
      if (_selectedSetType != widget.initialSetType) {
        _selectedSetType = widget.initialSetType;
      }
      if (_scrollController.hasClients && _scrollController.offset != widget.initialScrollOffset) {
        _scrollController.jumpTo(widget.initialScrollOffset);
      }
    }

    if (widget.sets.length > oldWidget.sets.length) {
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
    if (_weightScrollController.hasClients) {
      _weightScrollController.animateToItem(index, duration: const Duration(milliseconds: 200), curve: Curves.easeOutCubic);
    }
  }

  void _adjustReps(int delta) {
    final newR = (_selectedReps + delta).clamp(1, 100);
    final index = newR - 1;
    if (_repsScrollController.hasClients) {
      _repsScrollController.animateToItem(index, duration: const Duration(milliseconds: 200), curve: Curves.easeOutCubic);
    }
  }

  void _showActionsMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _ExerciseActionsSheet(
        exercise: widget.exercise,
        isSkipped: widget.isSkipped,
        isSubstitution: widget.isSubstitution,
        isTemporaryAddition: widget.isTemporaryAddition,
        onSkip: widget.onSkipExercise,
        onUndoSkip: widget.onUndoSkip,
        onReplace: () => widget.onReplaceExercise(widget.exercise),
        onReorder: widget.onReorderExercises,
        onAddBefore: () => widget.onAddExtraExercise(widget.exercise, true),
        onAddAfter: () => widget.onAddExtraExercise(widget.exercise, false),
        onUndoReplacement: widget.onUndoReplacement,
      ),
    );
  }

  Widget _buildSkippedBanner() {
    final isSub = widget.skipReason == 'Substituted';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        color: const Color(0xFF141624).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: KColor.border, width: 0.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isSub ? Icons.swap_horiz_rounded : Icons.block_rounded,
            color: isSub ? KColor.blue : KColor.danger,
            size: 44,
          ),
          const SizedBox(height: 12),
          Text(
            isSub ? 'EXERCISE SUBSTITUTED' : 'EXERCISE SKIPPED',
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            isSub 
                ? 'Replaced by another exercise in this session.' 
                : 'Reason: ${widget.skipReason ?? "Not specified"}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: KColor.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: isSub ? widget.onUndoReplacement : widget.onUndoSkip,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: Text(isSub ? 'Undo Substitution' : 'Re-enable Exercise'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E1E2C),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              side: const BorderSide(color: Color(0xFF3E3E50), width: 0.5),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isSkipped) {
      if (widget.isWideLayout) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(16, 12, 16, widget.dockHeight + 16.0),
                child: _buildHeroSection(),
              ),
            ),
            Expanded(
              flex: 5,
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: EdgeInsets.fromLTRB(16, 12, 16, widget.dockHeight + 16.0),
                child: _buildSkippedBanner(),
              ),
            ),
          ],
        );
      } else {
        return ListView(
          controller: _scrollController,
          padding: EdgeInsets.fromLTRB(16, 12, 16, widget.dockHeight + 16.0),
          children: [
            _buildHeroSection(),
            const SizedBox(height: 14),
            _buildSkippedBanner(),
          ],
        );
      }
    }

    final leftCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeroSection(),
      ],
    );

    final rightCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDialConsolePanel(),
        const SizedBox(height: 12),
        _buildLoggedSetsAndSessionNotesJournal(),
      ],
    );

    if (widget.isWideLayout) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, 12, 16, widget.dockHeight + 16.0),
              child: leftCol,
            ),
          ),
          Expanded(
            flex: 5,
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: EdgeInsets.fromLTRB(16, 12, 16, widget.dockHeight + 16.0),
              child: rightCol,
            ),
          ),
        ],
      );
    } else {
      return ListView(
        controller: _scrollController,
        padding: EdgeInsets.fromLTRB(16, 12, 16, widget.dockHeight + 16.0),
        children: [
          leftCol,
          const SizedBox(height: 14),
          rightCol,
        ],
      );
    }
  }

  Widget _buildLoggedSetsAndSessionNotesJournal() {
    final groups = groupLegacyFlatSets(widget.sets);
    final workingSetsCount = groups.where((g) => g.isWorkingSet).length;
    final totalVol = groups.fold(0.0, (s, g) => s + g.totalVolume);
    final dropVol = groups.where((g) => g.isWorkingSet).fold(0.0, (s, g) => s + g.subSetsVolume);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141624).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: KColor.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'LOGGED SETS ($workingSetsCount)',
                style: const TextStyle(color: KColor.textMuted, fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 0.4),
              ),
              if (groups.isNotEmpty)
                Text(
                  dropVol > 0
                      ? 'Vol: ${totalVol.toStringAsFixed(0)} kg (Drop: ${dropVol.toStringAsFixed(0)} kg)'
                      : 'Volume: ${totalVol.toStringAsFixed(0)} kg',
                  style: const TextStyle(color: KColor.textSecondary, fontSize: 11, fontWeight: FontWeight.bold),
                ),
            ],
          ),
          const SizedBox(height: 8),
          
          if (groups.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'No sets logged yet. Complete a set below to begin.',
                  style: TextStyle(color: KColor.textMuted, fontSize: 12),
                ),
              ),
            )
          else ...[
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: groups.length,
              separatorBuilder: (context, index) => const Divider(color: KColor.border, height: 1),
              itemBuilder: (context, groupIdx) {
                final group = groups[groupIdx];
                final mainSet = group.mainSet;
                final previousBest = WorkoutService.instance.bestSetBefore(widget.exercise.id, DateTime.now());
                final isPr = previousBest == null || mainSet.estimatedOneRepMax > previousBest.estimatedOneRepMax + 0.01;
                final mainFlatIdx = widget.sets.indexOf(mainSet);

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Set number badge
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: isPr ? KColor.amber.withValues(alpha: 0.15) : const Color(0xFF13131F),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${groupIdx + 1}',
                              style: TextStyle(
                                color: isPr ? KColor.amber : KColor.textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Weight x Reps
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        '${mainSet.weight.toStringAsFixed(mainSet.weight == mainSet.weight.truncateToDouble() ? 0 : 1)} kg  ×  ${mainSet.reps} reps',
                                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: _setTypeColor(mainSet.setType).withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: Text(
                                        mainSet.setType.shortLabel,
                                        style: TextStyle(
                                          color: _setTypeColor(mainSet.setType),
                                          fontSize: 8,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  widget.enableRpeTracking && mainSet.rpe != null
                                      ? 'RPE ${mainSet.rpe} • ${mainSet.volume.toStringAsFixed(0)} kg volume'
                                      : '${mainSet.volume.toStringAsFixed(0)} kg volume',
                                  style: const TextStyle(color: KColor.textMuted, fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                          if (isPr) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: KColor.amber.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: KColor.amber.withValues(alpha: 0.3), width: 0.5),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.workspace_premium_rounded, color: KColor.amber, size: 10),
                                  SizedBox(width: 3),
                                  Text('PR', style: TextStyle(color: KColor.amber, fontSize: 8.5, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          GestureDetector(
                            onTap: () {
                              if (mainFlatIdx != -1) {
                                widget.onRemoveSet(mainFlatIdx);
                              }
                            },
                            child: const Icon(Icons.remove_circle_rounded, color: Color(0xFF3B3B4F), size: 18),
                          ),
                        ],
                      ),

                      // Child Drop Sets Nested Under Parent Set
                      if (group.subSets.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        for (int d = 0; d < group.subSets.length; d++) ...[
                          Builder(
                            builder: (context) {
                              final drop = group.subSets[d];
                              final dropFlatIdx = widget.sets.indexOf(drop);
                              return Padding(
                                padding: const EdgeInsets.only(left: 20, top: 4, bottom: 4),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF191B2A),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: KColor.amber.withValues(alpha: 0.25), width: 0.5),
                                  ),
                                  child: Row(
                                    children: [
                                      const Text(
                                        '↳',
                                        style: TextStyle(color: KColor.amber, fontSize: 14, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: KColor.amber.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          group.subSets.length > 1 ? 'DROP ${d + 1}' : 'DROP',
                                          style: const TextStyle(
                                            color: KColor.amber,
                                            fontSize: 8,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '${drop.weight.toStringAsFixed(drop.weight == drop.weight.truncateToDouble() ? 0 : 1)} kg  ×  ${drop.reps} reps  (${drop.volume.toStringAsFixed(0)} kg)',
                                          style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                      GestureDetector(
                                        onTap: () {
                                          if (dropFlatIdx != -1) {
                                            widget.onRemoveSet(dropFlatIdx);
                                          }
                                        },
                                        child: const Icon(Icons.close_rounded, color: Color(0xFF55556E), size: 16),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
          ],
          
          const Divider(color: KColor.border, height: 1),
          const SizedBox(height: 12),
          
          // Unified Session Notes at the bottom of the list
          Row(
            children: [
              const Icon(Icons.edit_note_rounded, color: KColor.textSecondary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'WORKOUT SESSION NOTES',
                  style: const TextStyle(color: KColor.textMuted, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
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

    // Sparkline historical data
    final sparkData = widget.history.reversed
        .map((h) => h.entry.topWorkingSet?.estimatedOneRepMax ?? h.entry.topSet?.estimatedOneRepMax ?? 0.0)
        .where((val) => val > 0.0)
        .toList();

    // Calculate typical trends from history
    double totalSetsCount = 0;
    int sessionsWithSetsCount = 0;
    List<int> workingRepsList = [];
    List<double> workingWeightsList = [];
    for (final h in widget.history) {
      final entry = h.entry;
      if (entry.isSkipped) continue;
      final sets = entry.sets;
      if (sets.isEmpty) continue;
      totalSetsCount += sets.length;
      sessionsWithSetsCount++;
      for (final s in sets) {
        if (s.isMainWorkingSet) {
          workingRepsList.add(s.reps);
          workingWeightsList.add(s.weight);
        }
      }
    }
    double typicalSets = 0;
    int typicalRepMin = 0;
    int typicalRepMax = 0;
    double typicalWeight = 0.0;
    if (sessionsWithSetsCount > 0) {
      typicalSets = totalSetsCount / sessionsWithSetsCount;
    }
    if (workingRepsList.isNotEmpty) {
      workingRepsList.sort();
      typicalRepMin = workingRepsList.first;
      typicalRepMax = workingRepsList.last;
    }
    if (workingWeightsList.isNotEmpty) {
      typicalWeight = workingWeightsList.reduce((a, b) => a + b) / workingWeightsList.length;
    }

    final typicalSetsStr = typicalSets > 0 ? '${typicalSets.toStringAsFixed(0)} sets' : '';
    final typicalWeightStr = typicalWeight > 0 ? '${typicalWeight.toStringAsFixed(typicalWeight == typicalWeight.truncateToDouble() ? 0 : 1)}kg' : '';
    final typicalRepsStr = (typicalRepMin > 0 && typicalRepMax > 0)
        ? (typicalRepMin == typicalRepMax ? '$typicalRepMin reps' : '$typicalRepMin-$typicalRepMax reps')
        : '';
    String typicalTrendStr = 'None';
    if (typicalWeightStr.isNotEmpty) {
      typicalTrendStr = '$typicalWeightStr × $typicalRepsStr';
      if (typicalSetsStr.isNotEmpty) {
        typicalTrendStr += ' ($typicalSetsStr)';
      }
    }

    String exTypeLabel = switch (widget.exercise.type) {
      ExerciseType.barbellCompound => 'Barbell Compound',
      ExerciseType.dumbbell => 'Dumbbell',
      ExerciseType.cableMachine => 'Cable Machine',
      ExerciseType.isolation => 'Isolation',
      ExerciseType.bodyweight => 'Bodyweight',
    };

    return Container(
      padding: EdgeInsets.zero,
      decoration: const BoxDecoration(
        color: Colors.transparent,
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
                    if (widget.isSubstitution)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: KColor.blue.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '🔄 REPLACING ${widget.substitutedForName?.toUpperCase()}',
                            style: const TextStyle(color: KColor.blue, fontSize: 8.5, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    Text(
                      widget.exercise.name,
                      style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900),
                    ),
                    Text(
                      '${widget.exercise.muscleGroup} • $exTypeLabel',
                      style: const TextStyle(color: KColor.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.insights_rounded, color: KColor.green, size: 22),
                    onPressed: widget.onOpenHistory,
                  ),
                  IconButton(
                    icon: const Icon(Icons.tune_rounded, color: KColor.textSecondary, size: 22),
                    onPressed: _showActionsMenu,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _buildHeroStatCol('Last Session', lastStr, KColor.textSecondary),
              _buildHeroStatCol('Typical Trend', typicalTrendStr, KColor.blue),
              _buildHeroStatCol('Lifetime Best', bestStr, KColor.amber),
              _buildHeroStatCol('Current Session', currentStr, KColor.green),
            ],
          ),
          const SizedBox(height: 14),
          
          // Recommended Next Set Card
          Builder(
            builder: (context) {
              final rec = WorkoutService.instance.getPersonalizedRecommendation(widget.exercise.id, widget.splitDayName);
              final hasStyle = rec.style != null && !rec.isDeload && rec.confidence >= 0.50;
              final isDeloadOrSafety = rec.isDeload || rec.style == null;
              final cardColor = isDeloadOrSafety 
                  ? KColor.danger.withValues(alpha: 0.08) 
                  : const Color(0xFF1E1E2C).withValues(alpha: 0.8);
              final borderColor = isDeloadOrSafety 
                  ? KColor.danger.withValues(alpha: 0.25) 
                  : const Color(0xFFFFB347).withValues(alpha: 0.3);
              final iconColor = isDeloadOrSafety 
                  ? KColor.danger 
                  : const Color(0xFFFFB347);

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor, width: 1.0),
                  boxShadow: [
                    BoxShadow(
                      color: iconColor.withValues(alpha: 0.08),
                      blurRadius: 10,
                      spreadRadius: 1,
                    )
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isDeloadOrSafety ? Icons.warning_amber_rounded : Icons.offline_bolt_rounded, 
                          color: iconColor, 
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            isDeloadOrSafety ? 'TRAINING ADVICE' : 'PROGRESSION RECOMMENDATION',
                            style: TextStyle(color: iconColor, fontSize: 10.5, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (hasStyle) ...[
                      Text(
                        'Style: ${rec.style!.label}',
                        style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Builder(
                        builder: (context) {
                          final history = WorkoutService.instance.historyFor(widget.exercise.id, limit: 4);
                          final sessionLines = <String>[];
                          for (final h in history) {
                            final workingSets = h.entry.sets.where((s) => s.isMainWorkingSet).toList();
                            if (workingSets.isNotEmpty) {
                              final setString = workingSets
                                  .map((s) => '${s.weight.toStringAsFixed(s.weight == s.weight.truncateToDouble() ? 0 : 1)}×${s.reps}')
                                  .join(', ');
                              sessionLines.add(setString);
                            }
                          }
                          final evidenceText = sessionLines.isNotEmpty
                              ? 'Last ${sessionLines.length} sessions:\n${sessionLines.map((line) => '• $line').join('\n')}'
                              : rec.reasoning;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Evidence:',
                                style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                evidenceText,
                                style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 10.5, fontStyle: FontStyle.italic, height: 1.35),
                              ),
                            ],
                          );
                        }
                      ),
                      const Divider(color: Color(0xFF374151), height: 12, thickness: 0.5),
                    ],
                    Text(
                      rec.recommendation,
                      style: const TextStyle(color: Colors.white, fontSize: 11.5, height: 1.35, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              );
            }
          ),

          // Temporary Exercise Permanent addition recommendation
          if (widget.isRecurringAddition && widget.isTemporaryAddition) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: KColor.green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: KColor.green.withValues(alpha: 0.15), width: 1.0),
                boxShadow: [
                  BoxShadow(
                    color: KColor.green.withValues(alpha: 0.05),
                    blurRadius: 10,
                    spreadRadius: 1,
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome_rounded, color: KColor.green, size: 14),
                      const SizedBox(width: 6),
                      const Text(
                        'RECURRING TEMPORARY ADDITION',
                        style: TextStyle(color: KColor.green, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'You added ${widget.exercise.name} in several recent ${widget.splitDayName} sessions. Add it permanently to this split program?',
                    style: const TextStyle(color: Colors.white, fontSize: 11, height: 1.3),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: widget.onAddPermanently,
                    style: TextButton.styleFrom(
                      backgroundColor: KColor.green.withValues(alpha: 0.12),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Add Permanently', style: TextStyle(color: KColor.green, fontSize: 11.5, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],

          // Recurring Substitution recommendation card
          if (widget.recurringSubstitutionReplacement != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: KColor.blue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: KColor.blue.withValues(alpha: 0.15), width: 1.0),
                boxShadow: [
                  BoxShadow(
                    color: KColor.blue.withValues(alpha: 0.05),
                    blurRadius: 10,
                    spreadRadius: 1,
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome_rounded, color: KColor.blue, size: 14),
                      const SizedBox(width: 6),
                      const Text(
                        'RECURRING SUBSTITUTION DETECTED',
                        style: TextStyle(color: KColor.blue, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Replace ${widget.exercise.name} with ${widget.recurringSubstitutionReplacement!.name} in your split?',
                    style: const TextStyle(color: Colors.white, fontSize: 11, height: 1.3),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: widget.onReplacePermanently,
                    style: TextButton.styleFrom(
                      backgroundColor: KColor.blue.withValues(alpha: 0.12),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Replace Permanently', style: TextStyle(color: KColor.blue, fontSize: 11.5, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],

          // Recurring Skip recommendation card
          if (widget.isRecurringSkip) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: KColor.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: KColor.danger.withValues(alpha: 0.15), width: 1.0),
                boxShadow: [
                  BoxShadow(
                    color: KColor.danger.withValues(alpha: 0.05),
                    blurRadius: 10,
                    spreadRadius: 1,
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome_rounded, color: KColor.danger, size: 14),
                      const SizedBox(width: 6),
                      const Text(
                        'FREQUENT SKIP DETECTED',
                        style: TextStyle(color: KColor.danger, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'You frequently skip ${widget.exercise.name}. Remove it from this split?',
                    style: const TextStyle(color: Colors.white, fontSize: 11, height: 1.3),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: widget.onRemovePermanently,
                    style: TextButton.styleFrom(
                      backgroundColor: KColor.danger.withValues(alpha: 0.12),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Remove Permanently', style: TextStyle(color: KColor.danger, fontSize: 11.5, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],

          // Reorder recommendation card
          if (widget.reorderRecommendation != null && widget.exercise.id == widget.reorderRecommendation!.first.id) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFB347).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFFB347).withValues(alpha: 0.15), width: 1.0),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFB347).withValues(alpha: 0.05),
                    blurRadius: 10,
                    spreadRadius: 1,
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome_rounded, color: Color(0xFFFFB347), size: 14),
                      const SizedBox(width: 6),
                      const Text(
                        'REORDER SEQUENCING DETECTED',
                        style: TextStyle(color: Color(0xFFFFB347), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Update exercise order to match your actual training sequence?',
                    style: TextStyle(color: Colors.white, fontSize: 11, height: 1.3),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: widget.onApplyReorder,
                    style: TextButton.styleFrom(
                      backgroundColor: const Color(0xFFFFB347).withValues(alpha: 0.12),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Update Order', style: TextStyle(color: Color(0xFFFFB347), fontSize: 11.5, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],

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

  // Cues and silhouette are integrated directly inside Unified Console card

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
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 14,
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
              const Text('×', style: TextStyle(color: KColor.textMuted, fontSize: 22)),
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

          // Contextual Barbell Plate Breakdown
          if (widget.exercise.type == ExerciseType.barbellCompound && _selectedWeight >= 20.0) ...[
            const SizedBox(height: 8),
            BarbellPlateStackView(targetWeightKg: _selectedWeight),
          ],

          // Ghost Previous Performance Indicator
          Builder(
            builder: (context) {
              final nextSetIdx = widget.sets.length;
              final lastSets = widget.lastEntry?.sets ?? [];
              final prevSet = nextSetIdx < lastSets.length ? lastSets[nextSetIdx] : null;
              if (prevSet == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.history_rounded, size: 13, color: Color(0xFF9CA3AF)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Last time: ${prevSet.weight.toStringAsFixed(1)} kg × ${prevSet.reps} reps (Set ${nextSetIdx + 1})',
                          style: const TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 14),

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

          const SizedBox(height: 16),
          const Divider(color: KColor.border, height: 1),
          const SizedBox(height: 12),

          // Set Type Selector Segmented chips
          _SetTypeSelector(
            selected: _selectedSetType,
            onChanged: (type) {
              setState(() {
                _selectedSetType = type;
              });
              widget.onInputChange(_selectedWeight, _selectedReps, _selectedRpe, type);
            },
          ),
          const SizedBox(height: 16),
          const Divider(color: KColor.border, height: 1),
          const SizedBox(height: 12),

          // Collapsible Cues & Advanced Metrics button
          InkWell(
            onTap: () {
              setState(() {
                _showCues = !_showCues;
              });
              HapticFeedback.selectionClick();
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                runSpacing: 4,
                children: [
                  Icon(
                    _showCues ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: KColor.textSecondary,
                    size: 16,
                  ),
                  Text(
                    widget.enableRpeTracking
                        ? (_showCues ? 'HIDE CUES, ANATOMY & ADVANCED METRICS' : 'SHOW CUES, ANATOMY & ADVANCED METRICS')
                        : (_showCues ? 'HIDE CUES & ANATOMY' : 'SHOW CUES & ANATOMY'),
                    style: const TextStyle(
                      color: KColor.textSecondary,
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Expandable cues, anatomy and RPE panel
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 12),
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
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (widget.enableRpeTracking) ...[
                    const SizedBox(height: 12),
                    const Divider(color: KColor.border, height: 1),
                    const SizedBox(height: 12),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('RATE OF PERCEIVED EXERTION (RPE)', style: TextStyle(color: KColor.textMuted, fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 0.4)),
                    ),
                    const SizedBox(height: 8),
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

                  const SizedBox(height: 12),
                  const Divider(color: KColor.border, height: 1),
                  const SizedBox(height: 10),
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
            ),
            crossFadeState: _showCues ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  // ── Set Type & RPE selectors ──────────────────────────────────────────────

  // Deleted _buildSetTypeAndRpeSelectors and _buildLoggedSetsCardsSection (integrated into Unified Console and Training Journal cards)

  Color _setTypeColor(SetType type) => switch (type) {
    SetType.normal => KColor.green,
    SetType.warmUp => KColor.textMuted,
    SetType.dropSet => KColor.amber,
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

// ─── Set Type Selector segmented chips ──────────────────────────────────────

class _SetTypeSelector extends StatefulWidget {
  final SetType selected;
  final ValueChanged<SetType> onChanged;
  const _SetTypeSelector({required this.selected, required this.onChanged});

  @override
  State<_SetTypeSelector> createState() => _SetTypeSelectorState();
}

class _SetTypeSelectorState extends State<_SetTypeSelector> {
  late ScrollController _scrollController;
  bool _canScrollLeft = false;
  bool _canScrollRight = false;
  final Map<SetType, GlobalKey> _chipKeys = {
    for (var type in SetType.values) type: GlobalKey(),
  };

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_updateScrollIndicators);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScrollIndicators();
      _scrollSelectedIntoView();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateScrollIndicators);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _SetTypeSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollSelectedIntoView();
      });
    }
  }

  void _updateScrollIndicators() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final offset = _scrollController.offset;
    final canScrollLeft = offset > 0.5;
    final canScrollRight = offset < maxScroll - 0.5 && maxScroll > 0;
    if (canScrollLeft != _canScrollLeft || canScrollRight != _canScrollRight) {
      setState(() {
        _canScrollLeft = canScrollLeft;
        _canScrollRight = canScrollRight;
      });
    }
  }

  void _scrollSelectedIntoView() {
    if (!_scrollController.hasClients) return;
    final key = _chipKeys[widget.selected];
    if (key != null && key.currentContext != null) {
      _scrollController.position.ensureVisible(
        key.currentContext!.findRenderObject()!,
        duration: const Duration(milliseconds: 150),
        alignment: 0.5,
        curve: Curves.easeInOut,
      );
    }
    _updateScrollIndicators();
  }

  @override
  Widget build(BuildContext context) {
    final visibleOptions = SetType.values;

    final showLeftFade = _canScrollLeft;
    final showRightFade = _canScrollRight;

    Widget scrollContent = SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: visibleOptions.map((type) {
          final isSelected = widget.selected == type;
          return GestureDetector(
            key: _chipKeys[type],
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onChanged(type);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: isSelected ? KColor.green : const Color(0xFF1E1E2C),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: isSelected ? KColor.green : const Color(0xFF3E3E50), width: 0.5),
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
    );

    if (showLeftFade || showRightFade) {
      scrollContent = ShaderMask(
        shaderCallback: (Rect bounds) {
          return LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              showLeftFade ? Colors.transparent : Colors.white,
              Colors.white,
              Colors.white,
              showRightFade ? Colors.transparent : Colors.white,
            ],
            stops: const [0.0, 0.08, 0.92, 1.0],
          ).createShader(bounds);
        },
        blendMode: BlendMode.dstIn,
        child: scrollContent,
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFF141624).withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KColor.border, width: 0.5),
      ),
      child: Center(
        widthFactor: 1.0,
        child: scrollContent,
      ),
    );
  }
}

class _BottomDockWidget extends StatelessWidget {
  final List<Exercise> exercises;
  final int originalSplitExerciseCount;
  final Map<String, List<SetEntry>> sets;
  final Map<String, bool> skippedExercises;
  final Map<String, bool> substitutedExercises;
  final Map<String, bool>? temporaryAdditions;
  final int selectedIndex;
  final String splitDayName;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onLogSet;
  final VoidCallback onAddExercise;
  final VoidCallback onRemoveExercise;
  final ValueChanged<int> onSelectExercise;

  const _BottomDockWidget({
    required this.exercises,
    required this.originalSplitExerciseCount,
    required this.sets,
    required this.skippedExercises,
    required this.substitutedExercises,
    this.temporaryAdditions,
    required this.selectedIndex,
    required this.splitDayName,
    required this.onPrevious,
    required this.onNext,
    required this.onLogSet,
    required this.onAddExercise,
    required this.onRemoveExercise,
    required this.onSelectExercise,
  });

  String _truncateName(String name, int maxLen) {
    if (name.length <= maxLen) return name;
    return '${name.substring(0, maxLen - 1)}…';
  }

  @override
  Widget build(BuildContext context) {
    final currentWorkoutCount = exercises.length;
    final completedCount = exercises.where((e) {
      final wsets = (sets[e.id] ?? []).where((s) => s.isMainWorkingSet).length;
      final isSkip = skippedExercises[e.id] ?? false;
      return isSkip || (wsets >= e.targetSets);
    }).length;
    final activeIndex = selectedIndex;
    final displayedNumber = selectedIndex + 1;
    final displayedTotal = exercises.length;

    print('=== WORKOUT SESSION STATE TRACE ===');
    print('  - originalSplitExerciseCount: $originalSplitExerciseCount (file: lib/screens/workout_session_screen.dart, class: _WorkoutSessionScreenState, field: widget.splitDay.exercises.length, line: 1402)');
    print('  - currentWorkoutExerciseCount: $currentWorkoutCount (file: lib/screens/workout_session_screen.dart, class: _WorkoutSessionScreenState, getter: _activeSessionExercises.length, line: 115)');
    print('  - completedExerciseCount: $completedCount (file: lib/screens/workout_session_screen.dart, class: _BottomDockWidget, method: build, line: 3538)');
    print('  - activeExerciseIndex: $activeIndex (file: lib/screens/workout_session_screen.dart, class: _WorkoutSessionScreenState, field: _selectedIndex, line: 95)');
    print('  - displayedExerciseNumber: $displayedNumber (file: lib/screens/workout_session_screen.dart, class: _BottomDockWidget, method: build, line: 3766)');
    print('  - displayedTotalExercises: $displayedTotal (file: lib/screens/workout_session_screen.dart, class: _BottomDockWidget, method: build, line: 3766)');
    print('  - skippedExercises: ${skippedExercises.entries.where((e) => e.value).map((e) => e.key).toList()} (file: lib/screens/workout_session_screen.dart, class: _WorkoutSessionScreenState, field: _skippedExercises, line: 85)');
    print('  - replacedExercises: ${substitutedExercises.entries.where((e) => e.value).map((e) => e.key).toList()} (file: lib/screens/workout_session_screen.dart, class: _WorkoutSessionScreenState, field: _substitutedExercises, line: 86)');
    print('  - temporaryExercises: ${temporaryAdditions?.entries.where((e) => e.value).map((e) => e.key).toList() ?? []} (file: lib/screens/workout_session_screen.dart, class: _WorkoutSessionScreenState, field: _temporaryAdditions, line: 87)');
    print('  - removedExercises: ${originalSplitExerciseCount - currentWorkoutCount} (file: lib/screens/workout_session_screen.dart, class: _WorkoutSessionScreenState, method: _removeExerciseFromSession, line: 1198)');
    print('====================================');

    if (exercises.isEmpty) {
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
        child: SafeArea(
          top: false,
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              key: const Key('bottom_add_exercise_button'),
              onPressed: onAddExercise,
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: const Text('Add Exercise', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 0.5)),
              style: ElevatedButton.styleFrom(
                backgroundColor: KColor.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
            ),
          ),
        ),
      );
    }

    final activeEx = exercises[selectedIndex];
    final loggedList = sets[activeEx.id] ?? [];
    final isSkipped = skippedExercises[activeEx.id] ?? false;
    final canLog = !isSkipped;
    final activeWsets = loggedList.where((s) => s.isMainWorkingSet).length;

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
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. Interactive Progress Capsules Row
            SizedBox(
              height: 34,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: exercises.length,
                itemBuilder: (context, idx) {
                  final ex = exercises[idx];
                  final exSets = sets[ex.id] ?? [];
                  final isSkippedEx = skippedExercises[ex.id] ?? false;
                  final wsets = exSets.where((s) => s.isMainWorkingSet).length;
                  final isSelected = idx == selectedIndex;
                  final isCompleted = wsets >= ex.targetSets;

                  Color borderCol = const Color(0xFF2E2E3E);
                  Color textCol = KColor.textMuted;

                  if (isSelected) {
                    borderCol = KColor.green;
                    textCol = Colors.white;
                  }

                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onSelectExercise(idx);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isSelected ? KColor.green.withValues(alpha: 0.15) : const Color(0xFF161622),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: borderCol, width: isSelected ? 1.5 : 0.8),
                      ),
                      child: Row(
                        children: [
                          if (isSkippedEx) ...[
                            const Icon(Icons.block_rounded, color: KColor.textMuted, size: 12),
                            const SizedBox(width: 4),
                          ] else if (isCompleted) ...[
                            const Icon(Icons.check_circle_rounded, color: KColor.green, size: 12),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            _truncateName(ex.name, 14),
                            style: TextStyle(
                              color: textCol,
                              fontSize: 11,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
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

                // Main "Log Set" CTA - UNLOCKED REGARDLESS OF COMPLETION!
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: canLog ? onLogSet : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isSkipped
                            ? const Color(0xFF1F1F2E)
                            : (activeWsets >= activeEx.targetSets
                                ? const Color(0xFF15803D)
                                : KColor.green),
                        foregroundColor: Colors.white,
                        shadowColor: KColor.green.withValues(alpha: 0.4),
                        elevation: isSkipped ? 0 : 8,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide.none,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isSkipped
                                ? Icons.block_rounded
                                : (activeWsets >= activeEx.targetSets
                                    ? Icons.check_circle_rounded
                                    : Icons.add_task_rounded),
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              isSkipped
                                  ? 'EXERCISE SKIPPED'
                                  : 'LOG SET ${loggedList.length + 1}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Delete/Remove Exercise Button
                Container(
                  width: 48,
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E2C),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF3E3E50), width: 0.5),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFF87171), size: 22),
                    onPressed: onRemoveExercise,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Exercise Actions Bottom Sheet ──────────────────────────────────────────

class _ExerciseActionsSheet extends StatelessWidget {
  final Exercise exercise;
  final bool isSkipped;
  final bool isSubstitution;
  final bool isTemporaryAddition;
  final Function(String) onSkip;
  final VoidCallback onUndoSkip;
  final VoidCallback onReplace;
  final VoidCallback onReorder;
  final VoidCallback onAddBefore;
  final VoidCallback onAddAfter;
  final VoidCallback onUndoReplacement;

  const _ExerciseActionsSheet({
    required this.exercise,
    required this.isSkipped,
    required this.isSubstitution,
    required this.isTemporaryAddition,
    required this.onSkip,
    required this.onUndoSkip,
    required this.onReplace,
    required this.onReorder,
    required this.onAddBefore,
    required this.onAddAfter,
    required this.onUndoReplacement,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Text(
              'ACTIONS: ${exercise.name.toUpperCase()}',
              style: const TextStyle(color: KColor.textMuted, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
          ),
          const Divider(height: 1, color: Color(0xFF2E2E3E)),
          if (!isSkipped) ...[
            ListTile(
              leading: const Icon(Icons.block_rounded, color: KColor.danger),
              title: const Text('Skip Exercise', style: TextStyle(color: Colors.white, fontSize: 13.5)),
              subtitle: const Text('Remove from active sets for today', style: TextStyle(color: KColor.textMuted, fontSize: 11)),
              onTap: () {
                Navigator.of(context).pop();
                _showSkipReasonsSheet(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz_rounded, color: KColor.blue),
              title: const Text('Replace Exercise (Substitute)', style: TextStyle(color: Colors.white, fontSize: 13.5)),
              subtitle: const Text('Substitute with another exercise', style: TextStyle(color: KColor.textMuted, fontSize: 11)),
              onTap: () {
                Navigator.of(context).pop();
                onReplace();
              },
            ),
          ] else ...[
            ListTile(
              leading: const Icon(Icons.refresh_rounded, color: KColor.green),
              title: Text(isSubstitution ? 'Undo Substitution' : 'Re-enable Exercise', style: const TextStyle(color: Colors.white, fontSize: 13.5)),
              onTap: () {
                Navigator.of(context).pop();
                if (isSubstitution) {
                  onUndoReplacement();
                } else {
                  onUndoSkip();
                }
              },
            ),
          ],
          ListTile(
            leading: const Icon(Icons.reorder_rounded, color: KColor.textSecondary),
            title: const Text('Reorder Exercises', style: TextStyle(color: Colors.white, fontSize: 13.5)),
            subtitle: const Text('Drag and drop the exercise sequence', style: TextStyle(color: KColor.textMuted, fontSize: 11)),
            onTap: () {
              Navigator.of(context).pop();
              onReorder();
            },
          ),
          ListTile(
            leading: const Icon(Icons.arrow_upward_rounded, color: KColor.textSecondary),
            title: const Text('Add Exercise Before', style: TextStyle(color: Colors.white, fontSize: 13.5)),
            onTap: () {
              Navigator.of(context).pop();
              onAddBefore();
            },
          ),
          ListTile(
            leading: const Icon(Icons.arrow_downward_rounded, color: KColor.textSecondary),
            title: const Text('Add Exercise After', style: TextStyle(color: Colors.white, fontSize: 13.5)),
            onTap: () {
              Navigator.of(context).pop();
              onAddAfter();
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _showSkipReasonsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final reasons = [
          'Equipment Busy',
          'Injury / Pain',
          'Time Constraint',
          'Intentional Deload',
          'Other',
        ];
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Text(
                  'SELECT SKIP REASON: ${exercise.name.toUpperCase()}',
                  style: const TextStyle(color: KColor.textMuted, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
              ),
              const Divider(height: 1, color: Color(0xFF2E2E3E)),
              ...reasons.map((r) => ListTile(
                title: Text(r, style: const TextStyle(color: Colors.white, fontSize: 13.5)),
                onTap: () {
                  Navigator.of(context).pop();
                  onSkip(r);
                },
              )),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

// ─── Reorder Exercises Bottom Sheet ─────────────────────────────────────────

class _ReorderExercisesSheet extends StatefulWidget {
  final List<Exercise> exercises;
  final Function(int, int) onReorder;

  const _ReorderExercisesSheet({
    required this.exercises,
    required this.onReorder,
  });

  @override
  State<_ReorderExercisesSheet> createState() => _ReorderExercisesSheetState();
}

class _ReorderExercisesSheetState extends State<_ReorderExercisesSheet> {
  late List<Exercise> _localExercises;

  @override
  void initState() {
    super.initState();
    _localExercises = List.from(widget.exercises);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Container(
      height: media.size.height * 0.6,
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 10),
            child: Row(
              children: [
                Icon(Icons.drag_indicator_rounded, color: KColor.blue, size: 20),
                SizedBox(width: 8),
                Text(
                  'DRAG & DROP TO REORDER WORKOUT',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF2E2E3E)),
          Expanded(
            child: ReorderableListView.builder(
              itemCount: _localExercises.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (oldIndex < newIndex) {
                    newIndex -= 1;
                  }
                  final item = _localExercises.removeAt(oldIndex);
                  _localExercises.insert(newIndex, item);
                });
                widget.onReorder(oldIndex, newIndex);
              },
              itemBuilder: (context, idx) {
                final ex = _localExercises[idx];
                return ListTile(
                  key: ValueKey(ex.id),
                  title: Text(ex.name, style: const TextStyle(color: Colors.white, fontSize: 13)),
                  subtitle: Text(ex.muscleGroup, style: const TextStyle(color: KColor.textMuted, fontSize: 11)),
                  trailing: const Icon(Icons.drag_handle_rounded, color: KColor.textSecondary),
                );
              },
            ),
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
  late final Stream<int> _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Stream<int>.periodic(const Duration(seconds: 1), (x) => x);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _ticker,
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
            opacity: _opacity.value.clamp(0.0, 1.0),
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

// ─── Custom Fullscreen Completion Dashboard ──────────────────────────────────

class _WorkoutCompletionOverlay extends StatefulWidget {
  final WorkoutSession session;
  final WorkoutSession? previousSession;
  final int score;
  final double scoreCompletion;
  final double scoreVolume;
  final double scoreSets;
  final double scorePrs;
  final int e1rmPrsCount;
  final Duration duration;
  final VoidCallback onDone;

  const _WorkoutCompletionOverlay({
    required this.session,
    this.previousSession,
    required this.score,
    required this.scoreCompletion,
    required this.scoreVolume,
    required this.scoreSets,
    required this.scorePrs,
    required this.e1rmPrsCount,
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
                          _ScoreBreakdownPanel(
                            scoreCompletion: widget.scoreCompletion,
                            scoreVolume: widget.scoreVolume,
                            scoreSets: widget.scoreSets,
                            scorePrs: widget.scorePrs,
                            e1rmPrsCount: widget.e1rmPrsCount,
                            session: session,
                            previousSession: widget.previousSession,
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

// ─── Score Breakdown Panel Widget ───────────────────────────────────────────

class _ScoreBreakdownPanel extends StatefulWidget {
  final double scoreCompletion;
  final double scoreVolume;
  final double scoreSets;
  final double scorePrs;
  final int e1rmPrsCount;
  final WorkoutSession session;
  final WorkoutSession? previousSession;

  const _ScoreBreakdownPanel({
    required this.scoreCompletion,
    required this.scoreVolume,
    required this.scoreSets,
    required this.scorePrs,
    required this.e1rmPrsCount,
    required this.session,
    this.previousSession,
  });

  @override
  State<_ScoreBreakdownPanel> createState() => _ScoreBreakdownPanelState();
}

class _ScoreBreakdownPanelState extends State<_ScoreBreakdownPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    int totalPlannedWorkingSets = 0;
    int completedWorkingSets = 0;
    for (final entry in widget.session.entries) {
      if (entry.isSkipped) continue;
      totalPlannedWorkingSets += entry.exercise.targetSets;
      completedWorkingSets += entry.sets.where((s) => s.isMainWorkingSet).length;
    }

    final currentVol = widget.session.primaryWorkingVolume;
    final prevVol = widget.previousSession?.primaryWorkingVolume ?? 0.0;
    double volDiffPct = 0.0;
    if (prevVol > 0) {
      volDiffPct = ((currentVol - prevVol) / prevVol) * 100;
    }

    double loggedSetsScore = 0.0;
    int activeExercises = 0;
    for (final entry in widget.session.entries) {
      if (entry.isSkipped) continue;
      activeExercises++;
      final logged = entry.sets.where((s) => s.isMainWorkingSet).length;
      final target = entry.exercise.targetSets > 0 ? entry.exercise.targetSets : 3;
      loggedSetsScore += (logged / target).clamp(0.0, 1.0);
    }
    final adherencePct = activeExercises > 0 ? (loggedSetsScore / activeExercises) * 100 : 100.0;

    final totalScore = (widget.scoreCompletion + widget.scoreVolume + widget.scoreSets + widget.scorePrs).round().clamp(0, 100);

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF13131F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E2E3E), width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'WORKOUT SCORE: $totalScore / 100',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _expanded = !_expanded;
                  });
                },
                child: Text(
                  _expanded ? 'Hide Details ▲' : 'Tap for Details ▼',
                  style: const TextStyle(color: KColor.blue, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildRow('├─ Completion:', '${widget.scoreCompletion.toStringAsFixed(1)} / 30'),
          _buildRow('├─ Volume:', '${widget.scoreVolume.toStringAsFixed(1)} / 30'),
          _buildRow('├─ Sets:', '${widget.scoreSets.toStringAsFixed(1)} / 25'),
          _buildRow('└─ PR Bonus:', '${widget.scorePrs.toStringAsFixed(1)} / 15'),
          
          if (_expanded) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Divider(color: Color(0xFF2E2E3E), thickness: 0.5),
            ),
            _buildDetailSection(
              'Completion',
              '$completedWorkingSets of $totalPlannedWorkingSets planned working sets completed',
            ),
            const SizedBox(height: 6),
            _buildDetailSection(
              'Volume',
              '${currentVol.toStringAsFixed(0)} kg vs ${prevVol.toStringAsFixed(0)} kg previous (${volDiffPct >= 0 ? "+" : ""}${volDiffPct.toStringAsFixed(1)}%)',
            ),
            const SizedBox(height: 6),
            _buildDetailSection(
              'Sets',
              '${adherencePct.toStringAsFixed(0)}% adherence to planned sets',
            ),
            const SizedBox(height: 6),
            _buildDetailSection(
              'PR Bonus',
              '${widget.e1rmPrsCount} e1RM PRs achieved',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(color: KColor.textSecondary, fontSize: 11.5, fontFamily: 'monospace'),
            ),
          ),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 11.5, fontFamily: 'monospace', fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailSection(String title, String detail) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '  • $title:',
          style: const TextStyle(color: KColor.textSecondary, fontSize: 11, fontWeight: FontWeight.bold),
        ),
        Text(
          '    $detail',
          style: const TextStyle(color: Colors.white, fontSize: 11),
        ),
      ],
    );
  }
}
