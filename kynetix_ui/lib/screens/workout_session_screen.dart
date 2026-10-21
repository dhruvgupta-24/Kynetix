import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_theme.dart';
import '../ui/k_toast.dart';
import '../models/workout_split.dart';
import '../models/workout_session.dart';
import '../models/day_log.dart';
import '../services/workout_service.dart';
import '../services/persistence_service.dart';
import '../widgets/exercise_picker_sheet.dart';
import '../widgets/kyno_stage_slot.dart';
import '../widgets/exercise_execution_input_view.dart';
import '../widgets/exercise_progression_chart.dart';
import '../services/wakelock_service.dart';
import '../services/kyno_progression_engine.dart';
import '../services/kyno_coach_planner.dart';
import '../services/exercise_library_service.dart';
import '../services/rest_timer_prefs.dart';
import '../services/rest_timer_notifications.dart';
import '../services/previous_set_lookup.dart';
import '../services/pr_classifier.dart';
import '../services/superset_advance.dart';
import '../services/warmup_calculator.dart';
import '../widgets/pr_celebration.dart';
import '../widgets/workout_share_card.dart';
import '../widgets/muscle_body_map.dart';
import '../data/exercise_classification.dart';
import '../data/form_cues.dart';
import '../widgets/workout_session_sheets.dart';
import '../widgets/k_success_check.dart';
import '../widgets/k_ticking_text.dart';
import '../ui/k_rolling.dart';
import 'package:flutter/services.dart' show HapticFeedback, SystemSound, SystemSoundType;
import '../services/analytics_service.dart';

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
//
// Performance contract (Ember Night overhaul):
//   - Ticking values (rest timer, floating rewards) live in ValueNotifiers and
//     rebuild only their own leaf, never this 5k-line state.
//   - The dock is measured only when its size can actually change (first
//     layout, MediaQuery changes, SizeChangedLayoutNotification).
//   - Celebrations are painter-driven (`repaint: controller`), bounded and
//     skippable with a tap.

// ─── Local type ramp ─────────────────────────────────────────────────────────
// Every style on this screen derives from KText. Numbers (weights, reps,
// timers, scores) always use tabular figures so values never jitter.
abstract class _WsText {
  static TextStyle get title => KText.h1.copyWith(fontSize: 24, height: 1.15);
  static TextStyle get body => KText.body.copyWith(fontSize: 14, height: 1.45);
  static TextStyle get bodySmall => KText.caption.copyWith(fontSize: 13, height: 1.4);
  static TextStyle get meta => KText.caption.copyWith(fontSize: 13, color: KColor.textSecondary);
  static TextStyle get button => KText.bodyMedium.copyWith(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.1);
  static TextStyle get chip => KText.caption.copyWith(fontSize: 13, fontWeight: FontWeight.w600);
  static TextStyle get num => KText.numSmall.copyWith(fontSize: 14);
  /// The hero readout: weight and reps you are about to lift.
  static TextStyle get numHero => KText.numDisplay.copyWith(fontSize: 64, height: 1.0, letterSpacing: -2.6);
  static TextStyle get timer => KText.numMedium.copyWith(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.8);
  static TextStyle get dialogTitle => KText.h2;
  static TextStyle get dialogBody => KText.body.copyWith(fontSize: 14, color: KColor.textSecondary);
}

/// Theme hairline: a whisper of white on Carbon, the warm paper border on Paper.
Color _hairline() => KColor.isDark ? KColor.fg.withValues(alpha: 0.09) : KColor.border;

/// Dialog chrome shared by the session's confirmations.
ShapeBorder _dialogShape() => RoundedRectangleBorder(
      borderRadius: KRadius.xl,
      side: BorderSide(color: _hairline(), width: 1),
    );

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
  bool _isPageAnimating = false;
  Timer? _pendingAutoAdvanceTimer;

  void _cancelPendingAutoAdvance() {
    if (_pendingAutoAdvanceTimer != null) {
      debugPrint('[WORKOUT_AUTO_ADVANCE] Cancelling pending auto-advance timer');
      _pendingAutoAdvanceTimer?.cancel();
      _pendingAutoAdvanceTimer = null;
    }
  }

  void _navigateToExercise(int targetIndex) {
    if (targetIndex < 0 || targetIndex >= _sessionExercises.length) return;
    if (_selectedIndex == targetIndex && !_isPageAnimating) return;
    _cancelPendingAutoAdvance();
    // Rest belongs to the session, not the page: moving to the next exercise
    // (by hand, auto-advance or a superset hop) keeps the countdown running.
    if (!_pageController.hasClients) {
      setState(() => _selectedIndex = targetIndex);
      return;
    }
    if (_isPageAnimating) {
      debugPrint('[WORKOUT_NAV] Ignoring navigateToExercise($targetIndex) - animation already in progress');
      return;
    }
    _isPageAnimating = true;
    debugPrint('[WORKOUT_NAV] Navigating to index $targetIndex');
    // A long hop (chip tap three exercises away) would otherwise sweep
    // through, and build, every page in between. Land on the neighbour
    // first, then glide the last page: same destination, one smooth move.
    final from = _pageController.page?.round() ?? _selectedIndex;
    if ((targetIndex - from).abs() > 1 && !KMotion.reduced(context)) {
      _pageController.jumpToPage(targetIndex > from ? targetIndex - 1 : targetIndex + 1);
    }
    _animateToPage(targetIndex, const Duration(milliseconds: 300)).then((_) {
      if (mounted) {
        _isPageAnimating = false;
      }
    }).catchError((_) {
      if (mounted) {
        _isPageAnimating = false;
      }
    });
  }
  /// Page transition honouring reduced motion (jump instead of animate).
  Future<void> _animateToPage(int index, Duration duration) {
    final d = KMotion.of(context, duration);
    if (d == Duration.zero) {
      _pageController.jumpToPage(index);
      return Future<void>.value();
    }
    return _pageController.animateToPage(index, duration: d, curve: KMotion.emphasizedCurve);
  }

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
  final Map<String, double?> _externalLoadSelections = {};
  final Map<String, int?> _durationSelections = {};
  final Map<String, double?> _distanceSelections = {};
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

  // History-derived page inputs. They read only stored sessions and the saved
  // split (never this live session), yet each scans the whole history, and the
  // page builder ran all of them on every session rebuild (each logged set,
  // rest start/stop). Cached here and dropped whenever WorkoutService changes.
  _SplitDayRecs? _splitRecsCache;
  final Map<String, List<({DateTime date, ExerciseEntry entry})>> _historyCache = {};

  void _onServiceChanged() {
    _splitRecsCache = null;
    _historyCache.clear();
    _priorSetsCache.clear();
  }

  /// Every set of [exerciseId] from sessions before this one (record checks).
  final Map<String, List<SetEntry>> _priorSetsCache = {};
  List<SetEntry> _priorSetsFor(String exerciseId) => _priorSetsCache[exerciseId] ??= [
        for (final s in _service.sessions)
          if (s.date.isBefore(widget.date))
            for (final e in s.entries)
              if (e.exercise.id == exerciseId) ...e.sets,
      ];

  /// Warm-up ramps queued from the exercise menu: the head of each list is
  /// loaded in the dials; logging a warm-up advances to the next step.
  final Map<String, List<WarmUpStep>> _warmUpPlans = {};

  _SplitDayRecs get _splitRecs => _splitRecsCache ??= _SplitDayRecs(
        substitutions: _service.getRecurringSubstitutions(widget.splitDay.name),
        skips: _service.getRecurringSkips(widget.splitDay.name),
        reorders: _service.getReorderRecommendations(widget.splitDay.name),
        additions: _service.getRecurringAdditions(widget.splitDay.name),
      );

  List<({DateTime date, ExerciseEntry entry})> _historyForCached(String exerciseId) =>
      _historyCache[exerciseId] ??= _service.historyFor(exerciseId, limit: 15);
  late DateTime _startTime;

  // Floating text particles tracker. A notifier so spawning/expiring a reward
  // pill rebuilds only the overlay, not the session tree.
  final ValueNotifier<List<_FloatingTextData>> _floatingTexts =
      ValueNotifier<List<_FloatingTextData>>(const []);
  final ValueNotifier<int> _scoreNotifier = ValueNotifier<int>(0);

  // Rest Timer State
  // The per-second countdown lives in a ValueNotifier: a tick rebuilds only the
  // timer readout (ValueListenableBuilder), never this whole session tree.
  // `_isRestTimerActive` changes only on start/stop, so setState runs twice per
  // rest period instead of once per second.
  final ValueNotifier<int> _restSecondsRemaining = ValueNotifier<int>(0);
  Timer? _restTimer;
  bool _isRestTimerActive = false;
  int? _lastCountdownHapticSec;
  // Wall-clock anchors: the countdown is derived from these, so a tick that
  // arrives late (app backgrounded, a janky frame) never drifts the rest.
  int _restTotalSeconds = 0;
  DateTime? _restEndsAt;
  /// Exercise whose rest is running (its remembered duration is what the
  /// picker edits).
  String? _restExerciseId;
  /// Pending pulses of the rest-over haptic pattern; cancelled on dispose.
  final List<Timer> _restOverPulses = [];
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  bool get _appInForeground => _lifecycle == AppLifecycleState.resumed;

  int _restRemainingNow() {
    final end = _restEndsAt;
    if (end == null) return 0;
    final ms = end.difference(DateTime.now()).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  void _startRestTimer({required Exercise forExercise, int? durationSeconds}) {
    final seconds = durationSeconds ?? RestTimerPrefs.instance.durationFor(forExercise);
    debugPrint('[WORKOUT_TIMER] Started rest timer: ${seconds}s');
    _restTimer?.cancel();
    _cancelRestOverPulses();
    _lastCountdownHapticSec = null;
    _restExerciseId = forExercise.id;
    _restTotalSeconds = seconds;
    _restEndsAt = DateTime.now().add(Duration(seconds: seconds));
    _restSecondsRemaining.value = seconds;
    setState(() {
      _isRestTimerActive = true;
    });
    // First rest of the account: ask for notifications once, without waiting.
    unawaited(RestTimerNotifications.instance.requestPermissionOnce());
    // One tick a second. The count is resynced from the wall-clock end time
    // whenever the app returns to the foreground (see
    // didChangeAppLifecycleState), so a suspended app never drifts the rest.
    _restTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final remaining = _restSecondsRemaining.value - 1;
      if (remaining <= 0) {
        timer.cancel();
        _restTimer = null;
        _restSecondsRemaining.value = 0;
        setState(() {
          _isRestTimerActive = false;
        });
        _onRestOver();
        return;
      }
      _restSecondsRemaining.value = remaining;
      if (remaining <= 3 && _lastCountdownHapticSec != remaining && _appInForeground) {
        _lastCountdownHapticSec = remaining;
        KHaptics.select();
      }
    });
  }

  /// Rest is over: felt (a strong three-pulse pattern), heard (a short system
  /// sound) and, when the phone is in a pocket, seen as a notification naming
  /// the next set.
  void _onRestOver() {
    debugPrint('[WORKOUT_TIMER] Rest timer completed');
    _restEndsAt = null;
    if (_appInForeground) {
      _cancelRestOverPulses();
      KHaptics.milestone();
      if (KHaptics.enabled) {
        _restOverPulses
          ..add(Timer(const Duration(milliseconds: 170), HapticFeedback.heavyImpact))
          ..add(Timer(const Duration(milliseconds: 340), HapticFeedback.heavyImpact));
      }
      SystemSound.play(SystemSoundType.alert);
      SystemSound.play(SystemSoundType.click);
      unawaited(RestTimerNotifications.instance.cancelPending());
    } else {
      unawaited(RestTimerNotifications.instance.showRestOver(nextLine: _restNextLine()));
    }
  }

  void _cancelRestOverPulses() {
    for (final t in _restOverPulses) {
      t.cancel();
    }
    _restOverPulses.clear();
  }

  /// "Next: Bench Press set 3, target 62.5 kg × 8" for the notification.
  String _restNextLine() {
    if (_sessionExercises.isEmpty) return 'Time for your next set.';
    var idx = _selectedIndex.clamp(0, _sessionExercises.length - 1);
    // If the page in view is finished, point at the next unfinished one.
    for (var i = idx; i < _sessionExercises.length; i++) {
      final e = buildEntry(_sessionExercises[i]);
      if (!e.isSkipped && !e.isCompleted) {
        idx = i;
        break;
      }
    }
    final ex = _sessionExercises[idx];
    final mode = ex.effectiveExecutionMode;
    final done = (_sets[ex.id] ?? const <SetEntry>[]).where((s) => s.isMainWorkingSet).length;
    final weight = switch (mode) {
      ExerciseExecutionMode.weightReps => _weightSelections[ex.id],
      ExerciseExecutionMode.bodyweightReps ||
      ExerciseExecutionMode.weightedBodyweight =>
        (_externalLoadSelections[ex.id] ?? 0) > 0 ? _externalLoadSelections[ex.id] : null,
      _ => null,
    };
    return restNextLine(
      exerciseName: ex.name,
      setNumber: done + 1,
      weight: weight,
      reps: mode == ExerciseExecutionMode.timed || mode == ExerciseExecutionMode.cardio ? null : _repsSelections[ex.id],
      fmt: amount,
    );
  }

  void _adjustRestTimer(int deltaSeconds) {
    if (!_isRestTimerActive || _restEndsAt == null) return;
    final next = (_restSecondsRemaining.value + deltaSeconds).clamp(5, 600);
    _restTotalSeconds += next - _restSecondsRemaining.value;
    _restEndsAt = DateTime.now().add(Duration(seconds: next));
    _restSecondsRemaining.value = next;
    _lastCountdownHapticSec = null;
    KHaptics.select();
  }

  /// Tap on the countdown: pick this exercise's rest (30 s to 5 min). The
  /// choice is remembered for the exercise and applied to the running rest.
  Future<void> _editRestDuration({Exercise? forExercise}) async {
    if (_sessionExercises.isEmpty) return;
    final ex = forExercise ??
        _sessionExercises.where((e) => e.id == _restExerciseId).firstOrNull ??
        _currentExercise;
    final picked = await showRestPickerSheet(
      context,
      exerciseName: ex.name,
      currentSeconds: RestTimerPrefs.instance.durationFor(ex),
    );
    if (picked == null || !mounted) return;
    await RestTimerPrefs.instance.setDuration(ex.id, picked);
    if (!mounted) return;
    if (_isRestTimerActive && _restExerciseId == ex.id) {
      // Keep the time already rested; the new length applies from the start.
      final elapsed = _restTotalSeconds - _restSecondsRemaining.value;
      final next = (picked - elapsed).clamp(1, 600);
      _restTotalSeconds = picked;
      _restEndsAt = DateTime.now().add(Duration(seconds: next));
      _restSecondsRemaining.value = next;
    }
    _spawnFloatingText('Rest for ${ex.name}: ${restLabel(picked)}');
    setState(() {});
  }

  void _skipRestTimer() {
    _cancelRestTimer();
    KHaptics.commit();
  }

  void _cancelRestTimer() {
    debugPrint('[WORKOUT_TIMER] Cancelled rest timer');
    _restTimer?.cancel();
    _restTimer = null;
    _lastCountdownHapticSec = null;
    _restEndsAt = null;
    // Also drops the scheduled "Rest over" alarm.
    unawaited(RestTimerNotifications.instance.cancelPending());
    if (_isRestTimerActive) {
      _restSecondsRemaining.value = 0;
      setState(() {
        _isRestTimerActive = false;
      });
    }
  }

  // PR Celebration State (Non-blocking)
  bool _showPrToast = false;
  String _prToastTitle = '';
  String _prToastMsg = '';
  /// Bumped per record; re-keys the one-shot spark burst.
  int _prEpoch = 0;
  Timer? _prToastTimer;

  // Completion State
  bool _showCompletionScreen = false;

  /// Set once the session is saved. From then on nothing writes a draft or
  /// recovery copy: closing the app on the summary must not bring the
  /// finished workout back as something to resume.
  bool _finished = false;

  /// One id for this workout from its first draft to its saved session, so a
  /// second Finish replaces the first instead of adding a copy.
  late final String _draftId =
      widget.draftSession?.id ?? 'ws_draft_${DateTime.now().millisecondsSinceEpoch}';
  late WorkoutSession _completedSessionSummary;
  bool _enableRpeTracking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _service.addListener(_onServiceChanged);
    WakelockService.instance.enable();
    _loadRpeSetting();
    // Remembered per-exercise rest lengths for this account.
    unawaited(RestTimerPrefs.instance.load());

    final draft = widget.draftSession;
    if (draft != null) {
      _startTime = draft.date;
      _sessionNotes = draft.notes ?? '';
      _sessionExercises = draft.entries.map((e) => e.exercise).toList();
      _selectedIndex = _sessionExercises.isEmpty
          ? 0
          : draft.lastExerciseIndex.clamp(0, _sessionExercises.length - 1);

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

        _seedDials(ex);
      }

      _restoreState().then((_) {
        // The score notifier is disposed with the screen.
        if (mounted) _updateLiveScore();
      });
    } else {
      _startTime = DateTime.now();
      AnalyticsService.instance.track('workout_started', {'exercises': widget.splitDay.exercises.length});
      _sessionExercises = List.of(widget.splitDay.exercises);
      _selectedIndex = 0;

      for (final ex in _sessionExercises) {
        _sets[ex.id] = [];
        _setTypeSelections[ex.id] = SetType.normal;
        _rpeSelections[ex.id] = 8.0;

        _seedDials(ex);
      }

      // Clear recovery state to make sure it's fresh
      SharedPreferences.getInstance().then((prefs) {
        prefs.remove(WorkoutService.instance.recoveryPrefKey);
      });
      _updateLiveScore();
    }

    _pageController = PageController(initialPage: _selectedIndex);
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
    if (_finished) return;
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _saveRecoveryState();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _service.removeListener(_onServiceChanged);
    _cancelPendingAutoAdvance();
    _restTimer?.cancel();
    _cancelRestOverPulses();
    unawaited(RestTimerNotifications.instance.cancelAll());
    _restSecondsRemaining.dispose();
    _prToastTimer?.cancel();
    WakelockService.instance.disable();
    _pageController.dispose();
    _scoreNotifier.dispose();
    _floatingTexts.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _saveRecoveryState();
    }
    final endsAt = _restEndsAt;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      // Pocketed mid-rest: hand the countdown to the system chronometer.
      if (_isRestTimerActive && endsAt != null) {
        unawaited(RestTimerNotifications.instance.showCountdown(
          endsAt: endsAt,
          nextLine: _restNextLine(),
        ));
        // Armed with the alarm manager: fires even if Android freezes the
        // app before the in-app timer reaches zero.
        unawaited(RestTimerNotifications.instance.scheduleRestOver(
          endsAt: endsAt,
          nextLine: _restNextLine(),
        ));
      }
    } else if (state == AppLifecycleState.resumed) {
      // Back in the app: the in-app bar takes over again.
      unawaited(RestTimerNotifications.instance.cancelAll());
      if (_isRestTimerActive && _restEndsAt != null) {
        _restSecondsRemaining.value = max(1, _restRemainingNow());
      }
    }
  }

  // Dock measurement is scheduled only when the dock's size can change: on the
  // first frame and on MediaQuery changes (didChangeDependencies), and when the
  // dock itself reports a new size (SizeChangedLayoutNotification). Never per
  // build. `_dockMeasureScheduled` coalesces bursts into one post-frame read.
  bool _dockMeasureScheduled = false;

  void _scheduleDockMeasure() {
    if (_dockMeasureScheduled) return;
    _dockMeasureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dockMeasureScheduled = false;
      _measureDock();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Size, text scale, safe-area or keyboard insets changed (or first build).
    _scheduleDockMeasure();
  }

  void _measureDock() {
    if (!mounted) return;
    // The dock is not mounted while the keyboard is up; keep the last height.
    if (MediaQuery.viewInsetsOf(this.context).bottom > 0) return;
    final context = _dockKey.currentContext;
    if (context != null) {
      final renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox != null && renderBox.hasSize) {
        final height = renderBox.size.height;
        if ((height - _dockHeight).abs() > 1.0) {
          setState(() {
            _dockHeight = height;
          });
        }
      }
    }
  }

  // ── Recovery Persistence ─────────────────────────────────────────────────

  Future<void> _saveRecoveryState() async {
    if (_finished) return;
    final prefs = await SharedPreferences.getInstance();
    if (_finished) return;
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
      'externalLoadSelections': _externalLoadSelections,
      'durationSelections': _durationSelections,
      'distanceSelections': _distanceSelections,
    };
    await prefs.setString(WorkoutService.instance.recoveryPrefKey, jsonEncode(recoveryData));
    _saveDraftSessionState();
  }

  Future<void> _restoreState() async {
    final prefs = await SharedPreferences.getInstance();
    final recoveryJson = prefs.getString(WorkoutService.instance.recoveryPrefKey);
    if (!mounted) return;
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

          final extMap = data['externalLoadSelections'] as Map<String, dynamic>?;
          if (extMap != null) {
            extMap.forEach((k, v) {
              if (v != null) _externalLoadSelections[k] = (v as num).toDouble();
            });
          }

          final durMap = data['durationSelections'] as Map<String, dynamic>?;
          if (durMap != null) {
            durMap.forEach((k, v) {
              if (v != null) _durationSelections[k] = (v as num).toInt();
            });
          }

          final distMap = data['distanceSelections'] as Map<String, dynamic>?;
          if (distMap != null) {
            distMap.forEach((k, v) {
              if (v != null) _distanceSelections[k] = (v as num).toDouble();
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

        debugPrint('[WORKOUT_RESUME] Verified PageController index $_selectedIndex');
        if (_pageController.hasClients && _pageController.page?.round() != _selectedIndex) {
          _pageController.jumpToPage(_selectedIndex);
        }
      } catch (e) {
        debugPrint('Error restoring draft state: $e');
      }
    }
  }

  void _saveDraftSessionState() {
    if (_isSaving || _isDiscarding || _finished) return;
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
      id: _draftId,
      date: widget.date,
      splitDayName: widget.splitDay.name,
      splitDayWeekday: widget.splitDay.weekday == 0 ? null : widget.splitDay.weekday,
      wasManuallySelected: widget.wasManuallySelected,
      entries: entries,
      notes: _sessionNotes,
      lastExerciseIndex: _selectedIndex,
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
    _spawnFloatingText('Skipped for today');
    KHaptics.commit();
    _updateLiveScore();
    _saveRecoveryState();
  }

  void _undoSkip(String exerciseId) {
    setState(() {
      _skippedExercises[exerciseId] = false;
      _skipReasons.remove(exerciseId);
    });
    KHaptics.commit();
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
    final displayedXofY = 'Exercise ${currentIdx + 1} of $headerTotalCount';

    debugPrint('\n=================== EXERCISE REPLACEMENT RUNTIME AUDIT TRACE ($action) ===================');
    debugPrint('  - Original workout exercise count: $originalWorkoutCount');
    debugPrint('  - Active exercise count:           $activeCount');
    debugPrint('  - Navigation exercise count:       $navCount');
    debugPrint('  - Progress exercise count:         $progressCount');
    debugPrint('  - Header total count:              $headerTotalCount');
    debugPrint('  - Exercise IDs in active list:     $activeIds');
    debugPrint('  - Exercise IDs in master workout list: $masterIds');
    debugPrint('  - Exercise IDs marked as replaced: $replacedIds');
    debugPrint('  - Replacement mapping (old -> new): $replacementMap');
    debugPrint('  - Current exercise index:          $currentIdx');
    debugPrint('  - Displayed "X of Y":              $displayedXofY');
    debugPrint('========================================================================================\n');
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
      if (mounted && _pageController.hasClients) {
        _animateToPage(_selectedIndex, const Duration(milliseconds: 400));
      }
    });
    _spawnFloatingText('Swapped in');
    KHaptics.commit();
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
      KHaptics.commit();
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
    showKSheet(
      context: context,
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
    // The split is saved; the user may have left the session meanwhile.
    if (!mounted) return;

    // Track recommendation acceptance
    _service.trackRecommendationAccepted(exercise.id, widget.splitDay.name);

    setState(() {
      _temporaryAdditions[exercise.id] = false;
    });

    _spawnFloatingText('Added to ${widget.splitDay.name}');
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
    // The split is saved; the user may have left the session meanwhile.
    if (!mounted) return;

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

    _spawnFloatingText('Split updated');
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
    // The split is saved; the user may have left the session meanwhile.
    if (!mounted) return;

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

    _spawnFloatingText('Removed from your split');
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
    // The split is saved; the user may have left the session meanwhile.
    if (!mounted) return;

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

    _spawnFloatingText('Split order saved');
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
          if (WorkoutService.beatsPreviousBest(s, previousBest)) {
            prCount++;
          }
        }
      }
    });
    final prScore = (prCount * 5.0).clamp(0.0, 15.0);

    _scoreNotifier.value = (completionScore + volumeScore + setsScore + prScore).round().clamp(0, 100);
  }

  // ── Logging Operations ───────────────────────────────────────────────────

  Future<void> _logSet() async {
    final ex = _currentExercise;
    final mode = ex.effectiveExecutionMode;
    final w = _weightSelections[ex.id] ?? (mode == ExerciseExecutionMode.bodyweightReps ? 0.0 : 40.0);
    final r = _repsSelections[ex.id] ?? (mode == ExerciseExecutionMode.timed ? 1 : 10);
    final rpe = _rpeSelections[ex.id];
    final type = _setTypeSelections[ex.id] ?? SetType.normal;
    final externalLoad = _externalLoadSelections[ex.id];
    final duration = _durationSelections[ex.id] ?? (mode == ExerciseExecutionMode.timed ? 60 : null);
    final distance = _distanceSelections[ex.id] ?? (mode == ExerciseExecutionMode.cardio ? 1000.0 : null);

    // Explicit validation for timed, bodyweight, cardio and weight sets
    final validationError = ExecutionModeValidator.validate(
      mode: mode,
      weight: w,
      reps: r,
      externalLoadKg: externalLoad,
      durationSeconds: duration,
      distanceMeters: distance,
    );
    if (validationError != null) {
      // Rejected input: acknowledged (icon + text + haptic), never punished.
      KHaptics.reject();
      showKToast(
        context,
        validationError,
        kind: KToastKind.error,
        duration: const Duration(seconds: 2),
      );
      return;
    }

    final isBodyweight =
        mode == ExerciseExecutionMode.bodyweightReps || mode == ExerciseExecutionMode.weightedBodyweight;
    final newSet = SetEntry(
      // Bodyweight sets carry their belt / vest load in externalLoadKg; the
      // weight dial of another exercise must never leak in as "40 kg".
      weight: isBodyweight ? 0.0 : w,
      reps: r,
      rpe: rpe,
      setType: type,
      externalLoadKg: isBodyweight ? (externalLoad ?? 0.0) : null,
      durationSeconds: (mode == ExerciseExecutionMode.timed || mode == ExerciseExecutionMode.cardio) ? duration : null,
      distanceMeters: mode == ExerciseExecutionMode.cardio ? distance : null,
    );

    // Record check against earlier sessions and the sets already done today,
    // so a record celebrates once, not on every heavy set after it. Never on
    // the first-ever log of an exercise (nothing to beat).
    final earlierToday = List<SetEntry>.of(_sets[ex.id] ?? const <SetEntry>[]);
    final prResult = PrClassifier.classify(
      set: newSet,
      history: _priorSetsFor(ex.id),
      earlierToday: earlierToday,
    );
    final isPr = prResult.isPr;

    setState(() {
      (_sets[ex.id] ??= []).add(newSet);
      _advanceWarmUpPlan(ex, newSet);
    });

    _updateLiveScore();
    await _saveRecoveryState();

    String floatMsg;
    if (mode == ExerciseExecutionMode.timed) {
      floatMsg = 'Set logged. Breathe.\n${duration ?? 0}s hold';
    } else if (mode == ExerciseExecutionMode.cardio) {
      final distStr = (distance ?? 0) >= 1000
          ? '${((distance ?? 0) / 1000).toStringAsFixed(1)}km'
          : '${(distance ?? 0).toStringAsFixed(0)}m';
      floatMsg = 'Set logged. Breathe.\n$distStr';
    } else if (mode == ExerciseExecutionMode.bodyweightReps || mode == ExerciseExecutionMode.weightedBodyweight) {
      final ext = externalLoad ?? 0.0;
      floatMsg = ext > 0
          ? 'Set logged. Breathe.\nBW + ${ext.toStringAsFixed(1)}kg × $r'
          : 'Set logged. Breathe.\nBW × $r';
    } else {
      floatMsg = 'Set logged. Breathe.\n+${(w * r).toStringAsFixed(0)} kg';
    }

    _spawnFloatingText(floatMsg);

    // Exactly one haptic per logged set: a PR is the milestone, otherwise the
    // set itself is a commit. Never both.
    if (isPr) {
      KHaptics.milestone();
      _triggerPRNotification(prResult, ex.name);
    } else {
      KHaptics.commit();
    }

    // Superset: mid-round, go straight to the partner exercise with no rest;
    // the rest runs once the round closes.
    final supersetStep = SupersetAdvance.afterSet(
      logged: ex,
      allExercises: _sessionExercises,
      entriesMap: {for (final e in _sessionExercises) e.id: buildEntry(e)},
    );

    // Rest on set completion, unless the next set is a drop (straight into
    // it) or the superset round is still going.
    final nextType = _setTypeSelections[ex.id] ?? SetType.normal;
    if (!supersetStep.skipRest && RestTimerPrefs.shouldStartRest(nextSetType: nextType)) {
      final remembered = RestTimerPrefs.instance.durationFor(ex);
      _startRestTimer(
        forExercise: ex,
        // Warm-ups are light: cap their rest at a minute.
        durationSeconds: type == SetType.warmUp ? min(remembered, 60) : remembered,
      );
    } else if (_isRestTimerActive) {
      _cancelRestTimer();
    }

    final nextEx = supersetStep.goTo;
    if (nextEx != null) {
      final nextIdx = _sessionExercises.indexWhere((e) => e.id == nextEx.id);
      if (nextIdx != -1 && nextIdx != _selectedIndex && !_isPageAnimating) {
        debugPrint('[WORKOUT_NAV] Superset round scheduling advance to index $nextIdx: ${nextEx.name}');
        _cancelPendingAutoAdvance();
        _pendingAutoAdvanceTimer = Timer(const Duration(milliseconds: 500), () {
          _pendingAutoAdvanceTimer = null;
          if (mounted) {
            _navigateToExercise(nextIdx);
          }
        });
        return;
      }
    }

    // Auto-advance if completed
    final entry = buildEntry(ex);
    if (entry.isCompleted) {
      _requestAutoAdvance(ex.id);
    }
  }

  void _requestAutoAdvance(String completedExId) {
    _cancelPendingAutoAdvance();
    if (_isPageAnimating) {
      debugPrint('[WORKOUT_AUTO_ADVANCE] Ignored auto-advance request - page animation in progress');
      return;
    }
    if (_selectedIndex >= _sessionExercises.length - 1) return;

    final currentEx = _sessionExercises[_selectedIndex];
    if (currentEx.id != completedExId) return;

    final entry = buildEntry(currentEx);
    if (!entry.isCompleted) return;

    final nextIdx = _selectedIndex + 1;
    debugPrint('[WORKOUT_AUTO_ADVANCE] Scheduling auto-advance to index $nextIdx in 600ms');

    _pendingAutoAdvanceTimer = Timer(const Duration(milliseconds: 600), () {
      _pendingAutoAdvanceTimer = null;
      if (!mounted || _isPageAnimating) return;
      if (_selectedIndex >= _sessionExercises.length - 1) return;

      // Verify current exercise is still the completed one
      if (_sessionExercises[_selectedIndex].id != completedExId) return;
      if (!buildEntry(_sessionExercises[_selectedIndex]).isCompleted) return;

      debugPrint('[WORKOUT_AUTO_ADVANCE] Executing auto-advance to index $nextIdx');
      _navigateToExercise(nextIdx);
    });
  }

  void _triggerPRNotification(PrResult result, String exerciseName) {
    _prToastTimer?.cancel();
    final copy = prBannerCopy(result, exerciseName: exerciseName);
    setState(() {
      _showPrToast = true;
      _prToastTitle = copy.title;
      _prToastMsg = copy.detail;
      _prEpoch++;
    });
    _prToastTimer = Timer(const Duration(milliseconds: 4500), () {
      if (mounted) {
        setState(() => _showPrToast = false);
      }
    });
  }

  // ── Warm-ups ─────────────────────────────────────────────────────────────

  /// Exercise menu → "Add warm-up sets": asks for today's working weight
  /// (prefilled), then queues the ramp. Each warm-up loads into the dials as
  /// a warm-up set; logging it moves to the next step, and after the last
  /// one the dials return to the working weight.
  Future<void> _addWarmUpSets(Exercise ex) async {
    final suggested = WarmUpCalculator.suggestWorkingWeight(
      todaySets: _sets[ex.id] ?? const [],
      lastSessionSets: _service.lastEntryFor(ex.id, widget.splitDay.name)?.sets ?? const [],
      fallback: _weightSelections[ex.id],
    );
    final plan = await showWarmUpSheet(context, exercise: ex, suggestedWorkingWeight: suggested);
    if (!mounted || plan == null || plan.steps.isEmpty) return;
    setState(() {
      _warmUpPlans[ex.id] = List.of(plan.steps);
      _warmUpWorkingWeight[ex.id] = plan.workingWeight;
      _loadWarmUpStep(ex.id);
    });
    _spawnFloatingText('${plural(plan.steps.length, 'warm-up set')} queued');
    KHaptics.commit();
    _queueRecoverySave();
  }

  /// Working weight the ramp was built for (kept so the dials return to it).
  final Map<String, double> _warmUpWorkingWeight = {};

  void _loadWarmUpStep(String exId) {
    final plan = _warmUpPlans[exId];
    if (plan == null || plan.isEmpty) return;
    _weightSelections[exId] = plan.first.weight;
    _repsSelections[exId] = plan.first.reps;
    _setTypeSelections[exId] = SetType.warmUp;
  }

  /// Called inside setState after a set lands.
  void _advanceWarmUpPlan(Exercise ex, SetEntry logged) {
    final plan = _warmUpPlans[ex.id];
    if (plan == null || plan.isEmpty || logged.setType != SetType.warmUp) return;
    plan.removeAt(0);
    if (plan.isNotEmpty) {
      _loadWarmUpStep(ex.id);
    } else {
      _warmUpPlans.remove(ex.id);
      final working = _warmUpWorkingWeight.remove(ex.id);
      if (working != null && working > 0) _weightSelections[ex.id] = working;
      _setTypeSelections[ex.id] = SetType.normal;
    }
  }

  /// "Log all": records every queued warm-up at once, ahead of today's
  /// working sets, and returns the dials to the working weight.
  void _logAllWarmUps(Exercise ex) {
    final plan = _warmUpPlans[ex.id];
    if (plan == null || plan.isEmpty) return;
    setState(() {
      final list = _sets[ex.id] ??= [];
      final insertAt = list.takeWhile((s) => s.setType == SetType.warmUp).length;
      list.insertAll(insertAt, plan.map((s) => s.toSetEntry()));
      _warmUpPlans.remove(ex.id);
      final working = _warmUpWorkingWeight.remove(ex.id);
      if (working != null && working > 0) _weightSelections[ex.id] = working;
      _setTypeSelections[ex.id] = SetType.normal;
    });
    _spawnFloatingText('Warm-ups logged');
    KHaptics.commit();
    _updateLiveScore();
    _saveRecoveryState();
  }

  /// One tap on last session's ghost value loads it into the dials.
  void _copyPreviousSet(Exercise ex, SetEntry prev) {
    setState(() {
      if (prev.weight > 0) _weightSelections[ex.id] = prev.weight;
      if (prev.reps > 0) _repsSelections[ex.id] = prev.reps;
      if (prev.externalLoadKg != null) _externalLoadSelections[ex.id] = prev.externalLoadKg;
    });
    KHaptics.select();
    _queueRecoverySave();
  }

  /// Opening dial values: Kyno's first planned set when there is a plan,
  /// else last time's top set, else a neutral 40 kg × 10.
  void _seedDials(Exercise ex) {
    PlannedSet? first;
    try {
      first = KynoProgressionEngine.instance.planFor(ex).setAt(0);
    } catch (_) {}
    if (first != null) {
      _weightSelections[ex.id] = first.bodyweight ? 0.0 : first.load;
      _repsSelections[ex.id] = first.reps;
      if (first.bodyweight) _externalLoadSelections[ex.id] = first.load;
      return;
    }
    final lastTop = _service.lastEntryFor(ex.id, widget.splitDay.name)?.topSet;
    if (lastTop != null) {
      _weightSelections[ex.id] = lastTop.weight;
      _repsSelections[ex.id] = lastTop.reps;
      if (lastTop.externalLoadKg != null) _externalLoadSelections[ex.id] = lastTop.externalLoadKg;
    } else {
      _weightSelections[ex.id] = 40.0;
      _repsSelections[ex.id] = 10;
    }
  }

  void _clearWarmUpPlan(String exId) {
    setState(() {
      _warmUpPlans.remove(exId);
      final working = _warmUpWorkingWeight.remove(exId);
      if (working != null && working > 0) _weightSelections[exId] = working;
      _setTypeSelections[exId] = SetType.normal;
    });
    KHaptics.select();
  }

  void _adjustInputValue(
    String exId,
    double weight,
    int reps,
    double? rpe,
    SetType setType, {
    double? externalLoadKg,
    int? durationSeconds,
    double? distanceMeters,
  }) {
    // Queuing a drop right after a set: straight into it, no rest.
    if (setType == SetType.dropSet &&
        _setTypeSelections[exId] != SetType.dropSet &&
        _isRestTimerActive &&
        _restExerciseId == exId) {
      _cancelRestTimer();
    }
    // Leaving a drop chain (drop → working/warm-up) after logging the drops:
    // that's when the rest the drop skipped should run.
    final lastLogged = _sets[exId]?.lastOrNull;
    if (_setTypeSelections[exId] == SetType.dropSet &&
        setType != SetType.dropSet &&
        lastLogged?.setType == SetType.dropSet &&
        !_isRestTimerActive) {
      final ex = _sessionExercises.where((e) => e.id == exId).firstOrNull;
      if (ex != null) _startRestTimer(forExercise: ex);
    }
    _weightSelections[exId] = weight;
    _repsSelections[exId] = reps;
    _rpeSelections[exId] = rpe;
    _setTypeSelections[exId] = setType;
    if (externalLoadKg != null) _externalLoadSelections[exId] = externalLoadKg;
    if (durationSeconds != null) _durationSelections[exId] = durationSeconds;
    if (distanceMeters != null) _distanceSelections[exId] = distanceMeters;
    _queueRecoverySave();
  }

  void _removeSet(String exId, int index) {
    setState(() {
      _sets[exId]!.removeAt(index);
    });
    KHaptics.select();
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
    _spawnFloatingText('Set added\n+${last.volume.toStringAsFixed(0)} kg');
    KHaptics.commit();
    _updateLiveScore();
    _saveRecoveryState();
  }

  // ── Completion Screen & Finish ───────────────────────────────────────────

  /// True from the Finish tap until the save resolves, so a second tap (or a
  /// tap landing before the dialog route is up) can never save twice.
  bool _finishInFlight = false;

  Future<void> _finish() async {
    if (_finishInFlight || _isSaving) return;
    _finishInFlight = true;
    try {
      await _finishInner();
    } finally {
      _finishInFlight = false;
    }
  }

  Future<void> _finishInner() async {
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
      _showSnack('Log a set first, or skip or swap an exercise, then finish.');
      return;
    }

    final statusResult = await showDialog<WorkoutStatus>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: KColor.surface,
        shape: _dialogShape(),
        actionsOverflowDirection: VerticalDirection.down,
        title: Text('End this workout?', style: _WsText.dialogTitle),
        content: Text(
          'Save it as complete, or as partial if you cut it short on purpose.',
          style: _WsText.dialogBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Keep going', style: _WsText.button.copyWith(color: KColor.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(WorkoutStatus.partial),
            child: Text('Save as partial', style: _WsText.button.copyWith(color: KColor.textPrimary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(WorkoutStatus.completed),
            child: Text('Finish workout', style: _WsText.button.copyWith(color: KColor.textPrimary, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );

    if (statusResult == null || !mounted) return;

    setState(() => _isSaving = true);

    final session = WorkoutSession(
      id: WorkoutService.finishedIdFor(_draftId),
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

    try {
      await _service.saveSession(session);
      _finished = true;
      _debounceTimer?.cancel();
    } catch (e) {
      // Nothing was cleared: the draft and recovery copy still hold every set,
      // so the user can simply tap Finish again.
      debugPrint('[WORKOUT_FINISH] Save failed: $e');
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showSnack('Couldn\'t save your workout. Your sets are safe, so tap Finish to try again.');
      return;
    }

    try {
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
      await prefs.remove(WorkoutService.instance.recoveryPrefKey);
    } catch (e) {
      // The session itself is saved; housekeeping failures must not strand the
      // user on a spinner.
      debugPrint('[WORKOUT_FINISH] Post-save cleanup failed: $e');
    }

    if (!mounted) return;
    _cancelRestTimer();
    WakelockService.instance.disable();

    setState(() {
      _isSaving = false;
      _completedSessionSummary = session;
      _showCompletionScreen = true;
    });
    // A finished workout is a genuine milestone (DESIGN_SYSTEM.md, Haptics).
    KHaptics.milestone();
    AnalyticsService.instance.track('workout_finished', {
      'sets': session.totalSets,
      'duration_min': session.durationMinutes,
      'prs': _WorkoutCompletionOverlayState._findBests(session).length,
    });
  }

  Future<void> _confirmDiscard() async {
    if (_totalSets == 0) {
      _cancelRestTimer();
      WakelockService.instance.disable();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(WorkoutService.instance.recoveryPrefKey);
      await _service.clearDraftSession();
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: KColor.surface,
        shape: _dialogShape(),
        actionsOverflowDirection: VerticalDirection.down,
        title: Text('Pause workout?', style: _WsText.dialogTitle),
        content: Text(
          'Save a draft and pick up where you left off, or discard this session.',
          style: _WsText.dialogBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('cancel'),
            child: Text('Keep going', style: _WsText.button.copyWith(color: KColor.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('discard'),
            child: Text('Discard', style: _WsText.button.copyWith(color: KColor.danger)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('save'),
            child: Text('Save and leave', style: _WsText.button.copyWith(color: KColor.textPrimary, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (!mounted || result == null || result == 'cancel') return;

    if (result == 'discard') {
      _cancelRestTimer();
      WakelockService.instance.disable();
      _isDiscarding = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(WorkoutService.instance.recoveryPrefKey);
      await _service.clearDraftSession();
      if (mounted) Navigator.of(context).pop();
    } else if (result == 'save') {
      _cancelRestTimer();
      WakelockService.instance.disable();
      _saveRecoveryState();
      Navigator.of(context).pop();
    }
  }

  void _spawnFloatingText(String text) {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    _floatingTexts.value = [..._floatingTexts.value, _FloatingTextData(id: id, text: text)];
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) {
        _floatingTexts.value = _floatingTexts.value.where((t) => t.id != id).toList();
      }
    });
  }

  /// Both callers report a finish that could not go through.
  void _showSnack(String msg) {
    showKToast(context, msg, kind: KToastKind.error);
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
          backgroundColor: KColor.surface,
          shape: _dialogShape(),
          actionsOverflowDirection: VerticalDirection.down,
          title: Text('Remove exercise?', style: _WsText.dialogTitle),
          content: Text(
            'You\'ve logged sets for ${ex.name}. Removing it drops those sets from today.',
            style: _WsText.dialogBody,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel', style: _WsText.button.copyWith(color: KColor.textSecondary)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('Remove exercise', style: _WsText.button.copyWith(color: KColor.danger)),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
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
    showKSheet(
      context: context,
      isScrollControlled: false,
      builder: (context) => _ExerciseHistorySheet(
        exercise: ex,
        splitDayName: widget.splitDay.name,
      ),
    );
  }

  // ── Layout Builder & Rendering ───────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Computed once per build and shared by the glow and the progress bar.
    final progress = _completionProgress;
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // The workout is already saved behind the summary: back means Done,
        // not "discard this session?".
        if (_showCompletionScreen) {
          Navigator.of(context).pop(true);
          return;
        }
        _confirmDiscard();
      },
      child: Scaffold(
        backgroundColor: KColor.bg,
        body: Stack(
          children: [
            // Quiet ambient light. Painted once per progress stage from plain
            // radial gradients (no blur, no loop), isolated in its own layer.
            Positioned.fill(
              child: RepaintBoundary(
                child: _AmbientBackgroundGlow(progress: progress, isDark: KColor.isDark),
              ),
            ),

            SafeArea(
              child: Column(
                children: [
                  _buildSessionAppBar(),
                  // A PR opens a strip under the header and pushes the page
                  // down; it never covers the header or the readout.
                  _PRToastWidget(
                    isVisible: _showPrToast,
                    title: _prToastTitle,
                    message: _prToastMsg,
                    epoch: _prEpoch,
                  ),
                  _buildWorkoutProgressBar(progress),
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
                            debugPrint('[WORKOUT_PAGE] Swiped/Changed to index $index');
                            if (_selectedIndex == index) {
                              return;
                            }
                            _cancelPendingAutoAdvance();
                            _cancelRestTimer();
                            // A swipe ticks here; a chip / chevron / auto
                            // advance already gave its feedback (once).
                            if (!_isPageAnimating) KHaptics.select();
                            setState(() => _selectedIndex = index);
                            _queueRecoverySave();
                          },
                          itemBuilder: (context, index) {
                            final ex = _sessionExercises[index];
                            final setsList = _sets[ex.id] ?? [];
                            final lastEntry = _service.lastEntryFor(ex.id, widget.splitDay.name);
                            final history = _historyForCached(ex.id);
                            final recs = _splitRecs;

                            final recurringSubs = recs.substitutions;
                            final subMatch = recurringSubs.where((s) => s.original.id == ex.id).firstOrNull;
                            final replacementEx = subMatch?.replacement;

                            final recurringSkips = recs.skips;
                            final isRecSkip = recurringSkips.any((s) => s.exercise.id == ex.id);

                            final reorderRecs = recs.reorders;
                            final reorderOrder = reorderRecs.isNotEmpty ? reorderRecs.first.newOrder : null;

                            return _ExerciseWorkoutPage(
                              key: ValueKey(ex.id),
                              exercise: ex,
                              sets: setsList,
                              lastEntry: lastEntry,
                              history: history,
                              initialWeight: _weightSelections[ex.id] ?? 40.0,
                              initialReps: _repsSelections[ex.id] ?? 10,
                              initialRpe: _rpeSelections[ex.id],
                              initialSetType: _setTypeSelections[ex.id] ?? SetType.normal,
                              initialExternalLoad: _externalLoadSelections[ex.id],
                              initialDurationSeconds: _durationSelections[ex.id],
                              initialDistanceMeters: _distanceSelections[ex.id],
                              onExternalLoadChange: (load) {
                                _externalLoadSelections[ex.id] = load;
                                _queueRecoverySave();
                              },
                              onDurationChange: (dur) {
                                _durationSelections[ex.id] = dur;
                                _queueRecoverySave();
                              },
                              onDistanceChange: (dist) {
                                _distanceSelections[ex.id] = dist;
                                _queueRecoverySave();
                              },
                              isWideLayout: isWide,
                              initialNotes: _exerciseNotes[ex.id] ?? '',
                              onNotesChange: (notes) {
                                _exerciseNotes[ex.id] = notes;
                                _queueRecoverySave();
                              },
                              dockHeight: keyboardUp ? 0.0 : _dockHeight,
                              sessionNotes: _sessionNotes,
                              onSessionNotesChange: (notes) {
                                // Read only when pages mount and on save, so a
                                // keystroke needs no rebuild of the session.
                                if (_sessionNotes == notes) return;
                                _sessionNotes = notes;
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
                              isRecurringAddition: recs.additions.any((re) => re.exercise.id == ex.id),
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
                              warmUpPlan: _warmUpPlans[ex.id],
                              onAddWarmUps: () => _addWarmUpSets(ex),
                              onLogAllWarmUps: () => _logAllWarmUps(ex),
                              onClearWarmUps: () => _clearWarmUpPlan(ex.id),
                              restSeconds: RestTimerPrefs.instance.durationFor(ex),
                              onEditRest: () => _editRestDuration(forExercise: ex),
                              onCopyPrevious: (prev) => _copyPreviousSet(ex, prev),
                              onSwapSuggested: (replacement) => _replaceExercise(ex.id, replacement),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            // Pinned Bottom Command Center Dock. It reports its own size
            // changes, so it is re-measured only when it actually resizes.
            if (!keyboardUp)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: NotificationListener<SizeChangedLayoutNotification>(
                  onNotification: (_) {
                    _scheduleDockMeasure();
                    return true;
                  },
                  child: SizeChangedLayoutNotifier(
                    child: KeyedSubtree(
                      key: _dockKey,
                      child: _BottomDockWidget(
                    restBar: _isRestTimerActive ? _buildRestTimerBar() : null,
                    exercises: _sessionExercises,
                    originalSplitExerciseCount: widget.splitDay.exercises.length,
                    sets: _sets,
                    skippedExercises: _skippedExercises,
                    substitutedExercises: _substitutedExercises,
                    temporaryAdditions: _temporaryAdditions,
                    selectedIndex: _selectedIndex,
                    splitDayName: widget.splitDay.name,
                    onPrevious: () => _navigateToExercise(_selectedIndex - 1),
                    onNext: () => _navigateToExercise(_selectedIndex + 1),
                    onLogSet: _logSet,
                    onAddExercise: _addExerciseToSession,
                    onRemoveExercise: () => _removeExerciseFromSession(_selectedIndex),
                    onSelectExercise: (index) => _navigateToExercise(index),
                  ),
                    ),
                  ),
                ),
              ),

            // Drifting particles overlay
            IgnorePointer(
              child: RepaintBoundary(
                child: _buildFloatingTextOverlay(),
              ),
            ),

            // Fullscreen completion finish screen
            // Fades over the session (no hard cut), then runs its own intro.
            if (_showCompletionScreen)
              _RiseIn(
                rise: 0,
                child: _WorkoutCompletionOverlay(
                session: _completedSessionSummary,
                previousSession: widget.previousSession,
                score: _scoreNotifier.value,
                duration: DateTime.now().difference(_startTime),
                onDone: () => Navigator.of(context).pop(true),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Glanceable rest copy: a nudge before the final working set, otherwise
  /// just "Rest up".
  String _restLabel() {
    if (_sessionExercises.isEmpty || _selectedIndex >= _sessionExercises.length) return 'Rest up';
    final ex = _currentExercise;
    final done = (_sets[ex.id] ?? const <SetEntry>[]).where((s) => s.isMainWorkingSet).length;
    return ex.targetSets - done == 1 ? 'Last set, make it count' : 'Rest up';
  }

  /// Rest countdown, shown at the top of the dock while resting. Only the
  /// readout and the ring listen to the per-second tick; the ring sweeps
  /// continuously between ticks on its own ticker (see [_RestRing]).
  Widget _buildRestTimerBar() {
    final readout = ValueListenableBuilder<int>(
      valueListenable: _restSecondsRemaining,
      builder: (context, remaining, _) {
        final mins = remaining ~/ 60;
        final secs = remaining % 60;
        final timeStr = '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
        // Tabular digits in fixed cells: each second ticks over in place,
        // so the row never shifts.
        return KTickingText(
          timeStr,
          countdown: true,
          semanticsLabel: 'Rest time remaining $mins minutes $secs seconds',
          style: _WsText.timer.copyWith(color: KColor.textPrimary),
        );
      },
    );

    final ring = ValueListenableBuilder<int>(
      valueListenable: _restSecondsRemaining,
      builder: (context, remaining, _) => _RestRing(
        endsAt: _restEndsAt,
        totalSeconds: _restTotalSeconds,
        remainingSeconds: remaining,
      ),
    );

    final labelColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                _restLabel(),
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: _WsText.meta.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: readout,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.edit_rounded, size: 14, color: KColor.textMuted),
          ],
        ),
      ],
    );
    // Tap the countdown to set this exercise's rest (remembered per exercise).
    final label = Semantics(
      button: true,
      hint: 'Change rest length',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: _editRestDuration,
          borderRadius: KRadius.sm,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: 1,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ring,
                  const SizedBox(width: 10),
                  Flexible(child: labelColumn),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final buttons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildRestTimerBtn('-15s', () => _adjustRestTimer(-15), semantic: 'Subtract 15 seconds of rest'),
        const SizedBox(width: 6),
        _buildRestTimerBtn('+15s', () => _adjustRestTimer(15), semantic: 'Add 15 seconds of rest'),
        const SizedBox(width: 6),
        _buildRestTimerBtn('Skip', _skipRestTimer, semantic: 'Skip rest', emphasized: true),
      ],
    );

    return LayoutBuilder(
      builder: (context, c) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        // Narrow or large text: stack the controls under the countdown.
        if (c.maxWidth < 300 * scale) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              label,
              const SizedBox(height: 6),
              Align(alignment: AlignmentDirectional.centerEnd, child: buttons),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: label),
            const SizedBox(width: 8),
            buttons,
          ],
        );
      },
    );
  }

  Widget _buildRestTimerBtn(String label, VoidCallback onTap, {required String semantic, bool emphasized = false}) {
    return Semantics(
      button: true,
      label: semantic,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: KRadius.pill,
          child: Container(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            alignment: Alignment.center,
            // Skip is the ink action; the adjusters stay quiet.
            decoration: BoxDecoration(
              color: emphasized ? KColor.ink : KColor.fg.withValues(alpha: KColor.isDark ? 0.07 : 0.05),
              borderRadius: KRadius.pill,
            ),
            child: Text(
              label,
              style: _WsText.num.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: emphasized ? KColor.onInk : KColor.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Session header: one aligned row. Close sits in a 48dp slot on the left,
  /// the day's name and live meta take the middle, Finish anchors the right.
  /// No wrapping, so nothing drifts off-centre at any width or text scale.
  Widget _buildSessionAppBar() {
    final metaStyle = _WsText.num.copyWith(fontSize: 13, fontWeight: FontWeight.w600, color: KColor.textSecondary);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 16, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            tooltip: 'Pause or leave workout',
            icon: Icon(Icons.close_rounded, color: KColor.textPrimary, size: KIcons.lg),
            onPressed: _confirmDiscard,
            style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    widget.splitDay.name,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: KText.h3.copyWith(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3),
                  ),
                ),
                const SizedBox(height: 2),
                // Live meta, spaced by layout rather than middle dots.
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 2,
                  children: [
                    // Live dot (the accent, no glow) beside the timer; separate
                    // Wrap items so large text can reflow instead of overflowing.
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        KDot(color: KColor.ember),
                        const SizedBox(width: 6),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerStart,
                            child: _LiveTimerWidget(startedAt: _startTime),
                          ),
                        ),
                      ],
                    ),
                    // Set count and volume roll digit by digit as sets land.
                    _RollingMeta(
                      value: KRollingNumber.thousandsOf(_totalSets),
                      unit: _totalSets == 1 ? ' set' : ' sets',
                      style: metaStyle,
                    ),
                    _RollingMeta(
                      value: KRollingNumber.thousandsOf(_totalVolume.round()),
                      unit: ' kg',
                      style: metaStyle,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _isSaving ? null : _finish,
            style: ElevatedButton.styleFrom(
              backgroundColor: KColor.ink,
              foregroundColor: KColor.onInk,
              disabledBackgroundColor: KColor.ink.withValues(alpha: 0.4),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              minimumSize: const Size(72, 48),
              shape: const RoundedRectangleBorder(borderRadius: KRadius.pill),
              elevation: 0,
            ),
            child: _isSaving
                ? KSpinner(size: 16, color: KColor.onInk, semanticsLabel: 'Saving your workout')
                : Text('Finish', style: _WsText.button.copyWith(color: KColor.onInk)),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkoutProgressBar(double rawProgress) {
    final progress = rawProgress.clamp(0.0, 1.0);
    final percent = (progress * 100).round();
    final done = progress >= 1.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text('Workout progress', style: _WsText.meta.copyWith(fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Live score rides quietly beside the percentage.
                  ValueListenableBuilder<int>(
                    valueListenable: _scoreNotifier,
                    builder: (context, score, _) => Semantics(
                      label: 'Workout score $score',
                      excludeSemantics: true,
                      child: _RollingMeta(
                        prefix: 'Score ',
                        value: '$score',
                        style: _WsText.num.copyWith(fontSize: 13, fontWeight: FontWeight.w600, color: KColor.textMuted),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (done) ...[
                    Icon(Icons.check_rounded, color: KColor.green, size: 15),
                    const SizedBox(width: 3),
                  ],
                  Text(
                    '$percent%',
                    key: const Key('workout_progress_percent_text'),
                    style: _WsText.num.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: done ? KColor.green : KColor.textPrimary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: KRadius.pill,
            child: SizedBox(
              height: 6,
              // Ink throughout; done is marked by the check glyph and 100% above,
              // so colour is never the only signal.
              child: LinearProgressIndicator(
                key: const Key('workout_progress_bar'),
                value: progress,
                minHeight: 6,
                backgroundColor: KColor.fg.withValues(alpha: KColor.isDark ? 0.08 : 0.07),
                valueColor: AlwaysStoppedAnimation<Color>(KColor.ink),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingTextOverlay() {
    return ValueListenableBuilder<List<_FloatingTextData>>(
      valueListenable: _floatingTexts,
      builder: (context, texts, _) {
        if (texts.isEmpty) return const SizedBox.shrink();
        // Confirmation rises just above the dock, never over the readout.
        return Padding(
          padding: EdgeInsets.only(bottom: _dockHeight + 12),
          child: Stack(
          children: [
            for (final data in texts)
              _FloatingTextWidget(
                key: ValueKey(data.id),
                text: data.text,
              ),
          ],
        ),
        );
      },
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
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(
                color: KColor.isDark ? KColor.card : KColor.cardHigh,
                shape: BoxShape.circle,
                border: Border.all(color: _hairline()),
              ),
              child: Icon(
                Icons.fitness_center_rounded,
                color: KColor.textSecondary,
                size: 56,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Empty workout',
              textAlign: TextAlign.center,
              style: KText.h1.copyWith(fontSize: 24),
            ),
            const SizedBox(height: 12),
            Text(
              'Add your first exercise to start tracking your sets, weight, reps, and RPE.',
              textAlign: TextAlign.center,
              style: KText.body.copyWith(color: KColor.textSecondary),
            ),
            const SizedBox(height: 32),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 220, minHeight: 56),
              child: ElevatedButton.icon(
                key: const Key('center_add_exercise_button'),
                onPressed: _addExerciseToSession,
                icon: Icon(Icons.add_rounded, color: KColor.onInk),
                label: Text('Add exercise', style: _WsText.button.copyWith(color: KColor.onInk)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: KColor.ink,
                  foregroundColor: KColor.onInk,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: const RoundedRectangleBorder(borderRadius: KRadius.pill),
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

/// The session ground. Graphite is flat: it paints the base colour only, no
/// light field, no glow. Repaints only when the progress stage changes.
class _AmbientBackgroundGlow extends StatelessWidget {
  final double progress;
  final bool isDark;
  const _AmbientBackgroundGlow({required this.progress, required this.isDark});

  @override
  Widget build(BuildContext context) {
    // 0..4 stages; repaint only when the stage changes.
    final stage = (progress.clamp(0.0, 1.0) * 4).floor();
    return CustomPaint(
      painter: _AmbientGlowPainter(
        stage: stage,
        isDark: isDark,
        base: KColor.bg,
        keyLight: KColor.bg,
        bounce: KColor.bg,
      ),
      isComplex: false,
      willChange: false,
    );
  }
}

class _AmbientGlowPainter extends CustomPainter {
  _AmbientGlowPainter({
    required this.stage,
    required this.isDark,
    required this.base,
    required this.keyLight,
    required this.bounce,
  });

  final int stage;
  final bool isDark;
  final Color base, keyLight, bounce;

  final Paint _base = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    // Graphite: a flat ground, no light field.
    _base.color = base;
    canvas.drawRect(Offset.zero & size, _base);
  }

  @override
  bool shouldRepaint(covariant _AmbientGlowPainter old) =>
      old.stage != stage || old.isDark != isDark || old.base != base || old.keyLight != keyLight || old.bounce != bounce;
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
  final double? initialExternalLoad;
  final int? initialDurationSeconds;
  final double? initialDistanceMeters;
  final ValueChanged<double>? onExternalLoadChange;
  final ValueChanged<int>? onDurationChange;
  final ValueChanged<double>? onDistanceChange;

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

  // Warm-up ramp, rest length and last-session ghost values.
  final List<WarmUpStep>? warmUpPlan;
  final VoidCallback onAddWarmUps;
  final VoidCallback onLogAllWarmUps;
  final VoidCallback onClearWarmUps;
  final int restSeconds;
  final VoidCallback onEditRest;
  final ValueChanged<SetEntry> onCopyPrevious;

  /// Swap this exercise for Kyno's suggestion, for today's session.
  final ValueChanged<Exercise>? onSwapSuggested;

  const _ExerciseWorkoutPage({
    super.key,
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
    this.initialExternalLoad,
    this.initialDurationSeconds,
    this.initialDistanceMeters,
    this.onExternalLoadChange,
    this.onDurationChange,
    this.onDistanceChange,
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
    this.warmUpPlan,
    required this.onAddWarmUps,
    required this.onLogAllWarmUps,
    required this.onClearWarmUps,
    required this.restSeconds,
    required this.onEditRest,
    required this.onCopyPrevious,
    this.onSwapSuggested,
  });

  @override
  State<_ExerciseWorkoutPage> createState() => _ExerciseWorkoutPageState();
}

class _ExerciseWorkoutPageState extends State<_ExerciseWorkoutPage> {
  late ScrollController _scrollController;
  late TextEditingController _notesController;
  late TextEditingController _sessionNotesController;

  late double _selectedWeight;

  /// Load added on top of bodyweight (belt, vest, dumbbell), in kg.
  double? _externalLoad;

  bool get _isBodyweight {
    final m = widget.exercise.effectiveExecutionMode;
    return m == ExerciseExecutionMode.bodyweightReps || m == ExerciseExecutionMode.weightedBodyweight;
  }
  late int _selectedReps;

  /// Bumped on every weight/reps dial change. Only the dial readout, the plate
  /// stack and the input view listen, so spinning a wheel (one callback per
  /// detent) no longer rebuilds the hero, journal and cues of this page.
  final ValueNotifier<int> _dialTick = ValueNotifier<int>(0);
  double? _selectedRpe;
  late SetType _selectedSetType;
  /// Bumped each time a set lands; keys the console's one-shot jade pulse.
  int _pulseEpoch = 0;

  /// The session appends to the same list instance, so `oldWidget.sets` is
  /// this list too: remember the counts to notice a set landing.
  int _seenSetCount = 0;
  int _seenGroupCount = 0;

  /// Journal row that just appeared (rises in once), keyed by [_pulseEpoch].
  int? _enteringGroup;
  bool _showCues = false;
  late KynoProgressionAdvice _progressionAdvice;

  void _loadProgressionAdvice() {
    _progressionAdvice = KynoProgressionEngine.instance.computeAdvice(
      exercise: widget.exercise,
      splitDayName: widget.splitDayName,
    );
  }

  @override
  void initState() {
    super.initState();
    _loadProgressionAdvice();
    _selectedWeight = widget.initialWeight;
    _externalLoad = widget.initialExternalLoad;
    _selectedReps = widget.initialReps;
    _selectedRpe = widget.initialRpe;
    _selectedSetType = widget.initialSetType;
    _seenSetCount = widget.sets.length;
    _seenGroupCount = groupLegacyFlatSets(widget.sets).length;

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
      _loadProgressionAdvice();
      _selectedWeight = widget.initialWeight;
      _externalLoad = widget.initialExternalLoad;
      _selectedReps = widget.initialReps;
      _selectedRpe = widget.initialRpe;
      _selectedSetType = widget.initialSetType;

      _notesController.text = widget.initialNotes;
      _sessionNotesController.text = widget.sessionNotes;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(widget.initialScrollOffset);
      }
    } else {
      // Exercise is the same, but values might have restored asynchronously
      if (_selectedWeight != widget.initialWeight) {
        _selectedWeight = widget.initialWeight;
      }
      // Loaded from outside (last session's value, a restore).
      if (oldWidget.initialExternalLoad != widget.initialExternalLoad) {
        _externalLoad = widget.initialExternalLoad;
      }
      if (_selectedReps != widget.initialReps) {
        _selectedReps = widget.initialReps;
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

    final setCount = widget.sets.length;
    if (oldWidget.exercise.id != widget.exercise.id) {
      _enteringGroup = null;
    } else if (setCount > _seenSetCount) {
      // didUpdateWidget is always followed by build, so no setState is needed.
      // The new epoch re-keys a one-shot tween (no timers).
      _pulseEpoch++;
      final groups = groupLegacyFlatSets(widget.sets).length;
      // A new working / warm-up row rises in; a drop set joins its parent.
      _enteringGroup = groups > _seenGroupCount ? groups - 1 : null;
    }
    if (setCount != _seenSetCount) {
      _seenSetCount = setCount;
      _seenGroupCount = groupLegacyFlatSets(widget.sets).length;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _notesController.dispose();
    _sessionNotesController.dispose();
    _dialTick.dispose();
    super.dispose();
  }

  void _showActionsMenu() {
    showKSheet(
      context: context,
      isScrollControlled: false,
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
        onAddWarmUps: widget.onAddWarmUps,
        restSeconds: widget.restSeconds,
        onEditRest: widget.onEditRest,
      ),
    );
  }

  Widget _buildSkippedBanner() {
    final isSub = widget.skipReason == 'Substituted';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        color: KColor.card,
        borderRadius: KRadius.lg,
        border: Border.all(color: _hairline(), width: 1),
        boxShadow: KShadow.card,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isSub ? Icons.swap_horiz_rounded : Icons.block_rounded,
            color: isSub ? KColor.textSecondary : KColor.danger,
            size: 44,
          ),
          const SizedBox(height: 12),
          Text(
            isSub ? 'Swapped out' : 'Skipped for today',
            textAlign: TextAlign.center,
            style: KText.h3.copyWith(fontSize: 17, letterSpacing: 0.4),
          ),
          const SizedBox(height: 6),
          Text(
            isSub
                ? 'Another exercise took its place today.'
                : 'Reason: ${widget.skipReason ?? "none given"}',
            textAlign: TextAlign.center,
            style: _WsText.body.copyWith(color: KColor.textMuted),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: isSub ? widget.onUndoReplacement : widget.onUndoSkip,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: Text(isSub ? 'Undo swap' : 'Bring it back', style: _WsText.button.copyWith(color: KColor.onInk)),
            style: ElevatedButton.styleFrom(
              backgroundColor: KColor.ink,
              foregroundColor: KColor.onInk,
              elevation: 0,
              shape: const RoundedRectangleBorder(borderRadius: KRadius.pill),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              minimumSize: const Size(0, 52),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTitleRow(),
                    const SizedBox(height: 12),
                    _buildStatsStrip(),
                    const SizedBox(height: 14),
                    _buildInsightsSection(),
                  ],
                ),
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
            _buildTitleRow(),
            const SizedBox(height: 14),
            _buildSkippedBanner(),
            const SizedBox(height: 14),
            _buildInsightsSection(),
          ],
        );
      }
    }

    final consolePanel = _buildDialConsolePanel();
    final journal = _buildLoggedSetsAndSessionNotesJournal();

    if (widget.isWideLayout) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, 12, 16, widget.dockHeight + 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTitleRow(),
                  const SizedBox(height: 12),
                  _buildStatsStrip(),
                  const SizedBox(height: 14),
                  _buildInsightsSection(),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: EdgeInsets.fromLTRB(16, 12, 16, widget.dockHeight + 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  consolePanel,
                  const SizedBox(height: 12),
                  journal,
                ],
              ),
            ),
          ),
        ],
      );
    }

    // Phone: the set you're about to lift comes first, right under the name.
    // History and Kyno's context follow; nothing important hides under the
    // dock because the list pads by the dock's measured height.
    return ListView(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(16, 8, 16, widget.dockHeight + 16.0),
      children: [
        _buildTitleRow(),
        const SizedBox(height: 12),
        consolePanel,
        const SizedBox(height: 16),
        _buildStatsStrip(),
        const SizedBox(height: 16),
        journal,
        const SizedBox(height: 16),
        _buildInsightsSection(),
      ],
    );
  }

  Widget _buildLoggedSetsAndSessionNotesJournal() {
    final groups = groupLegacyFlatSets(widget.sets);
    final workingSetsCount = groups.where((g) => g.isWorkingSet).length;
    final totalVol = groups.fold(0.0, (s, g) => s + g.totalVolume);
    final dropVol = groups.where((g) => g.isWorkingSet).fold(0.0, (s, g) => s + g.subSetsVolume);

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
      decoration: BoxDecoration(
        color: KColor.card,
        borderRadius: KRadius.lg,
        border: Border.all(color: _hairline(), width: 1),
        boxShadow: KShadow.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                'Logged sets ($workingSetsCount)',
                style: KText.h3.copyWith(fontSize: 15),
              ),
              if (groups.isNotEmpty)
                Text(
                  dropVol > 0
                      ? 'Vol: ${totalVol.toStringAsFixed(0)} kg (Drop: ${dropVol.toStringAsFixed(0)} kg)'
                      : 'Volume: ${totalVol.toStringAsFixed(0)} kg',
                  style: _WsText.num.copyWith(fontSize: 13, color: KColor.textSecondary),
                ),
            ],
          ),
          const SizedBox(height: 6),

          if (groups.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'No sets yet. Log your first one below.',
                  textAlign: TextAlign.center,
                  style: _WsText.body.copyWith(color: KColor.textMuted),
                ),
              ),
            )
          else ...[
            Builder(builder: (context) {
            // Same answer for every row: look it up once, not per set.
            final previousBest = WorkoutService.instance.bestSetBefore(widget.exercise.id, DateTime.now());
            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: groups.length,
              separatorBuilder: (context, index) => Divider(color: _hairline(), height: 1),
              itemBuilder: (context, groupIdx) {
                final group = groups[groupIdx];
                final mainSet = group.mainSet;
                final isPr = WorkoutService.beatsPreviousBest(mainSet, previousBest);
                final mainFlatIdx = widget.sets.indexOf(mainSet);

                final isWarmUp = mainSet.setType == SetType.warmUp;
                // Same set last session (matched by type and order), as a hint.
                final prevForRow = PreviousSetLookup.forLoggedSet(
                  previousSets: widget.lastEntry?.sets ?? const [],
                  todaySets: widget.sets,
                  indexInToday: mainFlatIdx,
                );
                // Completed working sets in ink; PRs wear the accent (with the PR
                // label); warm-ups stay quiet.
                final badgeColor = isPr ? KColor.ember : (isWarmUp ? KColor.textSecondary : KColor.ink);

                final row = Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Set number badge with an ink (or accent PR) ring
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: badgeColor.withValues(alpha: KColor.isDark ? 0.14 : 0.10),
                              shape: BoxShape.circle,
                              border: Border.all(color: badgeColor.withValues(alpha: 0.55), width: 1),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${groupIdx + 1}',
                              style: _WsText.num.copyWith(fontSize: 14, fontWeight: FontWeight.w700, color: badgeColor),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Weight x Reps
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${mainSet.loadLabel}  ×  ${plural(mainSet.reps, 'rep')}',
                                  style: _WsText.num.copyWith(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.3),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  [
                                    if (mainSet.setType == SetType.warmUp) 'Warm-up set',
                                    if (mainSet.setType == SetType.dropSet) 'Drop set',
                                    if (widget.enableRpeTracking && mainSet.rpe != null) 'RPE ${amount(mainSet.rpe!)}',
                                    '${whole(mainSet.volume)} kg volume',
                                    if (prevForRow != null) 'last ${PreviousSetLookup.format(prevForRow)}',
                                  ].join(', '),
                                  style: _WsText.bodySmall.copyWith(
                                    fontSize: 13,
                                    color: mainSet.setType == SetType.normal ? KColor.textSecondary : _setTypeColor(mainSet.setType),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isPr) ...[
                            Semantics(
                              label: 'Personal record',
                              excludeSemantics: true,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  KIcon(KIcons.record, size: KIcons.sm, color: KColor.ember),
                                  const SizedBox(width: 3),
                                  Text('PR', style: _WsText.chip.copyWith(color: KColor.ember, fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                          Semantics(
                            button: true,
                            label: 'Remove set ${groupIdx + 1}',
                            excludeSemantics: true,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                if (mainFlatIdx != -1) {
                                  widget.onRemoveSet(mainFlatIdx);
                                }
                              },
                              child: SizedBox(
                                width: 48,
                                height: 48,
                                child: Center(
                                  child: Icon(Icons.remove_circle_rounded, color: KColor.textMuted, size: 22),
                                ),
                              ),
                            ),
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
                                  padding: const EdgeInsets.fromLTRB(12, 0, 0, 0),
                                  decoration: BoxDecoration(
                                    color: KColor.fg.withValues(alpha: KColor.isDark ? 0.04 : 0.03),
                                    borderRadius: KRadius.sm,
                                    border: Border(left: BorderSide(color: KColor.fat, width: 2)),
                                  ),
                                  child: Row(
                                    children: [
                                      Text(
                                        '↳',
                                        style: KText.bodyMedium.copyWith(color: KColor.textSecondary, fontSize: 14, fontWeight: FontWeight.w700),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        group.subSets.length > 1 ? 'Drop set ${d + 1}' : 'Drop set',
                                        style: _WsText.chip.copyWith(color: KColor.textSecondary),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '${drop.loadLabel}  ×  ${plural(drop.reps, 'rep')}  (${drop.volume.toStringAsFixed(0)} kg)',
                                          style: _WsText.num.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                      Semantics(
                                        button: true,
                                        label: 'Remove drop set',
                                        excludeSemantics: true,
                                        child: GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () {
                                            if (dropFlatIdx != -1) {
                                              widget.onRemoveSet(dropFlatIdx);
                                            }
                                          },
                                          child: SizedBox(
                                            width: 48,
                                            height: 48,
                                            child: Center(
                                              child: Icon(Icons.close_rounded, color: KColor.textMuted, size: 18),
                                            ),
                                          ),
                                        ),
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
                return groupIdx == _enteringGroup
                    ? _RiseIn(key: ValueKey('set-rise-$_pulseEpoch'), child: row)
                    : row;
              },
            );
            }),
            const SizedBox(height: 12),
          ],

          Divider(color: _hairline(), height: 1),
          const SizedBox(height: 12),

          // Unified Session Notes at the bottom of the list
          Row(
            children: [
              Icon(Icons.edit_note_rounded, color: KColor.textSecondary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Session notes',
                  style: _WsText.meta.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _sessionNotesController,
            maxLines: 2,
            style: _WsText.body.copyWith(color: KColor.textPrimary),
            cursorColor: KColor.textPrimary,
            decoration: InputDecoration(
              hintText: 'Energy, niggles, rest, anything worth remembering',
              hintStyle: _WsText.bodySmall.copyWith(color: KColor.textMuted),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  // ── Exercise title, stats strip and Kyno insights ────────────────────────

  /// Equipment and movement, e.g. "Bodyweight" or "Barbell, isolation".
  String get _exTypeLabel => ExerciseClassifier.forExercise(widget.exercise).label;

  /// Name, muscle group and the two page actions. The muscle mark comes from
  /// the shared icon language.
  Widget _buildTitleRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.isSubstitution && widget.substitutedForName != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      KIcon(Icons.swap_horiz_rounded, size: KIcons.sm, color: KColor.textSecondary),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'Replacing ${widget.substitutedForName}',
                          style: _WsText.meta.copyWith(color: KColor.textSecondary, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              Text(widget.exercise.name, style: _WsText.title),
              const SizedBox(height: 4),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      widget.exercise.muscleGroup,
                      style: _WsText.meta.copyWith(fontWeight: FontWeight.w600, color: KColor.textPrimary),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(_exTypeLabel, style: _WsText.meta),
                  ),
                ],
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Exercise history',
          icon: Icon(Icons.insights_rounded, color: KColor.textPrimary, size: 22),
          onPressed: widget.onOpenHistory,
        ),
        IconButton(
          tooltip: 'Exercise actions',
          icon: Icon(Icons.tune_rounded, color: KColor.textSecondary, size: 22),
          onPressed: _showActionsMenu,
        ),
      ],
    );
  }

  /// Last / Typical / Best / Today. A brand-new exercise has none of these,
  /// so it gets one honest line instead of a row of blanks.
  Widget _buildStatsStrip() {
    String kg(double w) => amount(w);
    final lastStr = widget.lastEntry != null
        ? WorkoutService.instance.lastSessionDisplay(widget.lastEntry).replaceAll('Last: ', '')
        : '';
    final bestVal = WorkoutService.instance.bestSetEver(widget.exercise.id);
    final bestStr = bestVal != null ? '${bestVal.loadLabel} × ${bestVal.reps}' : '';
    final currentStr = widget.sets.map((s) => s.shortLabel).join(', ');

    // Typical working weight and rep range from history.
    double totalSetsCount = 0;
    int sessionsWithSetsCount = 0;
    final workingRepsList = <int>[];
    final workingWeightsList = <double>[];
    for (final h in widget.history) {
      final entry = h.entry;
      if (entry.isSkipped || entry.sets.isEmpty) continue;
      totalSetsCount += entry.sets.length;
      sessionsWithSetsCount++;
      for (final s in entry.sets) {
        if (s.isMainWorkingSet) {
          workingRepsList.add(s.reps);
          workingWeightsList.add(s.weight);
        }
      }
    }
    String typicalStr = '';
    if (workingWeightsList.isNotEmpty) {
      workingRepsList.sort();
      final lo = workingRepsList.first;
      final hi = workingRepsList.last;
      final w = workingWeightsList.reduce((a, b) => a + b) / workingWeightsList.length;
      final reps = lo == hi ? '$lo' : '$lo-$hi';
      typicalStr = '${kg(w)} kg × $reps';
      if (sessionsWithSetsCount > 0) {
        typicalStr += ', ${plural((totalSetsCount / sessionsWithSetsCount).round(), 'set')}';
      }
    }

    final strip = BoxDecoration(
      border: Border(
        top: BorderSide(color: _hairline()),
        bottom: BorderSide(color: _hairline()),
      ),
    );

    final firstTime = lastStr.isEmpty && bestStr.isEmpty && typicalStr.isEmpty;
    if (firstTime) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: strip,
        child: Row(
          children: [
            KIcon(KIcons.baseline, size: KIcons.sm, color: KColor.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: 'First time: ',
                    style: _WsText.body.copyWith(fontWeight: FontWeight.w700, color: KColor.textPrimary),
                  ),
                  TextSpan(
                    text: 'find your working weight',
                    style: _WsText.body.copyWith(color: KColor.textSecondary),
                  ),
                ]),
              ),
            ),
            if (currentStr.isNotEmpty) ...[
              const SizedBox(width: 12),
              Flexible(child: _buildHeroStatCol('Today', currentStr, KColor.textPrimary, expand: false)),
            ],
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: strip,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeroStatCol('Last session', lastStr, KColor.textPrimary),
          _buildHeroStatCol('Typical', typicalStr, KColor.textPrimary),
          _buildHeroStatCol('Best', bestStr, KColor.ember),
          _buildHeroStatCol('Today', currentStr, KColor.textPrimary),
        ],
      ),
    );
  }

  /// Kyno's stage (demo and progression advice), the progression chart and
  /// any split suggestions. Context, so it sits below the controls.
  Widget _buildInsightsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KynoStageSlot(
          exercise: widget.exercise,
          advice: _progressionAdvice,
        ),
        if (_progressionAdvice.plan case final plan? when plan.sets.isNotEmpty) ...[
          const SizedBox(height: 12),
          _CoachPlanCard(
            plan: plan,
            doneSets: widget.sets.where((s) => s.setType == SetType.normal).length,
            onSwap: plan.swap == null || widget.onSwapSuggested == null
                ? null
                : () {
                    final def = ExerciseLibraryService.instance.getById(plan.swap!.exerciseId);
                    if (def == null) return;
                    KHaptics.commit();
                    widget.onSwapSuggested!(def.toExercise());
                  },
          ),
        ],
        // A first-timer has no curve to draw; the stats strip already says so.
        if (widget.history.isNotEmpty) ...[
          const SizedBox(height: 12),
          ExerciseProgressionChart(
            history: widget.history,
            exerciseName: widget.exercise.name,
          ),
        ],
        if (_hasContextualPrompts) ...[
          const SizedBox(height: 8),
          _buildContextualPrompts(),
        ],
      ],
    );
  }

  bool get _hasContextualPrompts =>
      (widget.isRecurringAddition && widget.isTemporaryAddition) ||
      widget.recurringSubstitutionReplacement != null ||
      widget.isRecurringSkip ||
      (widget.reorderRecommendation != null && widget.exercise.id == widget.reorderRecommendation!.first.id);

  Widget _buildContextualPrompts() {
    return Column(
      children: [
        if (widget.isRecurringAddition && widget.isTemporaryAddition) ...[
          const SizedBox(height: 8),
          _buildPromptCard(
            tone: KColor.ink,
            title: 'You keep adding this',
            body: 'You\'ve added ${widget.exercise.name} to your last few ${widget.splitDayName} sessions. Make it part of the split?',
            actionLabel: 'Add to split',
            onAction: widget.onAddPermanently,
          ),
        ],

        if (widget.recurringSubstitutionReplacement != null) ...[
          const SizedBox(height: 8),
          _buildPromptCard(
            tone: KColor.textSecondary,
            title: 'You keep swapping this',
            body: 'You keep doing ${widget.recurringSubstitutionReplacement!.name} instead of ${widget.exercise.name}. Swap it in your split?',
            actionLabel: 'Swap in split',
            onAction: widget.onReplacePermanently,
          ),
        ],

        if (widget.isRecurringSkip) ...[
          const SizedBox(height: 8),
          _buildPromptCard(
            tone: KColor.danger,
            destructive: true,
            title: 'You often skip this',
            body: '${widget.exercise.name} keeps getting skipped. Drop it from this split?',
            actionLabel: 'Remove from split',
            onAction: widget.onRemovePermanently,
          ),
        ],

        if (widget.reorderRecommendation != null && widget.exercise.id == widget.reorderRecommendation!.first.id) ...[
          const SizedBox(height: 8),
          _buildPromptCard(
            tone: KColor.textSecondary,
            title: 'Your order has changed',
            body: 'You\'ve been training in a different order. Save it to your split?',
            actionLabel: 'Update order',
            onAction: widget.onApplyReorder,
          ),
        ],
      ],
    );
  }

  /// Kyno's contextual suggestion card: tinted surface, sparkle glyph, eyebrow
  /// title, one sentence and a single tonal action. The tone is paired with a
  /// distinct title, so colour is never the only signal.
  Widget _buildPromptCard({
    required Color tone,
    bool destructive = false,
    required String title,
    required String body,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: KColor.card,
        borderRadius: KRadius.md,
        border: Border.all(color: _hairline(), width: 1.0),
        boxShadow: KShadow.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: tone, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: KText.h3.copyWith(fontSize: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: _WsText.body.copyWith(color: KColor.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: destructive ? KColor.danger : KColor.textPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: KRadius.pill,
                side: BorderSide(
                  color: destructive
                      ? KColor.danger.withValues(alpha: 0.5)
                      : KColor.fg.withValues(alpha: KColor.isDark ? 0.18 : 0.2),
                ),
              ),
              minimumSize: const Size(0, 48),
            ),
            child: Text(
              actionLabel,
              style: _WsText.chip.copyWith(
                fontSize: 14,
                color: destructive ? KColor.danger : KColor.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildHeroStatCol(String title, String val, Color highlight, {bool expand = true}) {
    final empty = val.isEmpty;
    final col = Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: _WsText.bodySmall.copyWith(fontSize: 12, color: KColor.textMuted)),
          const SizedBox(height: 4),
          Semantics(
            label: empty ? 'none yet' : null,
            child: Text(
              empty ? '-' : val,
              style: _WsText.num.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: empty ? KColor.textMuted : highlight,
              ),
            ),
          ),
        ],
      ),
    );
    return expand ? Expanded(child: col) : col;
  }

  // Cues and silhouette are integrated directly inside Unified Console card

  // ── Wheel Dials selectors (Change 1) ──────────────────────────────────────

  /// Kyno's planned set for the next working set ("62.5 × 8", "BW+10 × 8"):
  /// set N of today's plan, or its last set once the plan is done. Null with
  /// no plan yet (first session, timed work).
  PlannedSet? get _kynoTarget {
    final plan = _progressionAdvice.plan;
    if (plan == null || plan.sets.isEmpty) return null;
    final done = widget.sets.where((s) => s.setType == SetType.normal).length;
    return plan.setAt(done) ?? plan.sets.last;
  }

  Widget _buildGhostRow() {
    final prev = PreviousSetLookup.forNextSet(
      previousSets: widget.lastEntry?.sets ?? const [],
      todaySets: widget.sets,
      nextType: _selectedSetType,
    );
    final kyno = _selectedSetType == SetType.normal ? _kynoTarget : null;
    if (prev == null && kyno == null) return const SizedBox.shrink();
    final ordinal = widget.sets.where((s) => s.setType == _selectedSetType).length + 1;
    final setWord = switch (_selectedSetType) {
      SetType.warmUp => 'warm-up $ordinal',
      SetType.dropSet => 'drop $ordinal',
      SetType.normal => 'set $ordinal',
    };
    final ghostStyle = _WsText.bodySmall.copyWith(
      color: KColor.textSecondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          if (prev != null)
            Semantics(
              button: true,
              label: 'Last time, $setWord: ${PreviousSetLookup.format(prev).replaceAll('×', 'for')} reps. Double tap to use it.',
              excludeSemantics: true,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  key: const Key('ghost_previous_set'),
                  onTap: () => widget.onCopyPrevious(prev),
                  borderRadius: KRadius.pill,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      borderRadius: KRadius.pill,
                      border: Border.all(color: KColor.fg.withValues(alpha: KColor.isDark ? 0.14 : 0.16)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.history_rounded, size: 15, color: KColor.textMuted),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(text: 'Last $setWord  '),
                              TextSpan(
                                text: PreviousSetLookup.format(prev),
                                style: ghostStyle.copyWith(color: KColor.textPrimary, fontWeight: FontWeight.w700),
                              ),
                            ]),
                            style: ghostStyle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(Icons.north_west_rounded, size: 13, color: KColor.textMuted),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (kyno != null)
            Semantics(
              button: true,
              label: "Kyno's target for $setWord: ${kyno.label.replaceAll('×', 'for')} reps. Double tap to use it.",
              excludeSemantics: true,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  key: const Key('ghost_kyno_target'),
                  // Loads Kyno's set into the dials, like last time's value.
                  onTap: () => widget.onCopyPrevious(SetEntry(
                    weight: kyno.bodyweight ? 0 : kyno.load,
                    reps: kyno.reps,
                    externalLoadKg: kyno.bodyweight ? kyno.load : null,
                  )),
                  borderRadius: KRadius.pill,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      borderRadius: KRadius.pill,
                      border: Border.all(color: KColor.fg.withValues(alpha: KColor.isDark ? 0.14 : 0.16)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const KynoMark(size: 14),
                        const SizedBox(width: 6),
                        Text('Kyno  ', style: ghostStyle.copyWith(color: KColor.textMuted)),
                        Text(kyno.label, style: ghostStyle.copyWith(color: KColor.textPrimary, fontWeight: FontWeight.w700)),
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

  /// Queued warm-ups: the current one is in the dials; "Log all" records the
  /// rest at once.
  Widget _buildWarmUpQueue() {
    final plan = widget.warmUpPlan!;
    final chipStyle = _WsText.num.copyWith(fontSize: 13, fontWeight: FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        decoration: BoxDecoration(
          color: KColor.inset,
          borderRadius: KRadius.md,
          border: Border.all(color: KColor.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plan.length == 1 ? 'Last warm-up' : '${plan.length} warm-ups to go',
                    style: _WsText.meta.copyWith(fontWeight: FontWeight.w700, color: KColor.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 10,
                    runSpacing: 2,
                    children: [
                      for (var i = 0; i < plan.length; i++)
                        Text(
                          '${amount(plan[i].weight)}×${plan[i].reps}',
                          style: chipStyle.copyWith(
                            color: i == 0 ? KColor.textPrimary : KColor.textSecondary,
                            fontWeight: i == 0 ? FontWeight.w800 : FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: widget.onLogAllWarmUps,
              style: TextButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: KColor.textPrimary),
              child: Text('Log all', style: _WsText.chip.copyWith(color: KColor.textPrimary, fontWeight: FontWeight.w700)),
            ),
            IconButton(
              tooltip: 'Clear warm-ups',
              onPressed: widget.onClearWarmUps,
              icon: Icon(Icons.close_rounded, size: 18, color: KColor.textMuted),
              style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDialConsolePanel() {
    // The console's border pulses jade once when a set lands (the
    // completed-set colour). The pulse is a keyed one-shot overlay, so the
    // console itself (and its wheel state) is never rebuilt or remounted.
    final console = Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      decoration: BoxDecoration(
        color: KColor.isDark ? KColor.surface : KColor.card,
        borderRadius: KRadius.xl,
        border: Border.all(color: _hairline(), width: 1),
        boxShadow: KShadow.card,
      ),
      child: Column(
        children: [
          // Hero readout, plate stack and dials: the only parts of the page
          // that depend on the dial values, rebuilt alone on each detent.
          ValueListenableBuilder<int>(
            valueListenable: _dialTick,
            builder: (context, _, _) => Column(
              children: [
          // Hero readout: the set you are about to lift, as big as the screen allows.
          Semantics(
            label: _isBodyweight
                ? 'Next set: bodyweight${(_externalLoad ?? 0) > 0 ? ' plus ${amount(_externalLoad!)} kilograms' : ''} for ${plural(_selectedReps, 'rep')}'
                : 'Next set: ${amount(_selectedWeight)} kilograms for ${plural(_selectedReps, 'rep')}',
            excludeSemantics: true,
            // One line always: a longer "BW + 5 kg" scales down rather than
            // wrapping and shoving the steppers down mid-tap.
            child: FittedBox(fit: BoxFit.scaleDown, child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 12,
              runSpacing: 4,
              children: [
                // Digits roll as the dials and steppers move; tabular, so
                // the readout never reflows mid-spin. On a very narrow
                // screen at large text it scales down instead of overflowing.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      // Bodyweight lifts read "BW", plus the belt load when there is one.
                      if (_isBodyweight) ...[
                        Text('BW', style: _WsText.numHero),
                        if ((_externalLoad ?? 0) > 0) ...[
                          Text(
                            ' + ',
                            style: _WsText.num.copyWith(fontSize: 22, fontWeight: FontWeight.w600, color: KColor.textSecondary),
                          ),
                          KRollingNumber(amount(_externalLoad!), style: _WsText.numHero, duration: KMotion.standard),
                          Text(
                            ' kg',
                            style: _WsText.num.copyWith(fontSize: 18, fontWeight: FontWeight.w600, color: KColor.textSecondary),
                          ),
                        ],
                      ] else ...[
                        KRollingNumber(amount(_selectedWeight), style: _WsText.numHero, duration: KMotion.standard),
                        Text(
                          ' kg',
                          style: _WsText.num.copyWith(fontSize: 18, fontWeight: FontWeight.w600, color: KColor.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('×', style: KText.h2.copyWith(color: KColor.textMuted, fontSize: 24)),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      KRollingNumber('$_selectedReps', style: _WsText.numHero, duration: KMotion.standard),
                      Text(
                        ' reps',
                        style: _WsText.num.copyWith(fontSize: 18, fontWeight: FontWeight.w600, color: KColor.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            )),
          ),

              ],
            ),
          ),

          // Warm-up ramp queue, then last session's value for this set
          // (tap to load it) and Kyno's target beside it.
          if (widget.warmUpPlan != null && widget.warmUpPlan!.isNotEmpty) _buildWarmUpQueue(),
          _buildGhostRow(),
          const SizedBox(height: 14),

          // Execution Mode Input View (Standard, Bodyweight, Timed, Cardio)
          ValueListenableBuilder<int>(
            valueListenable: _dialTick,
            builder: (context, _, _) => ExerciseExecutionInputView(
            exercise: widget.exercise,
            selectedWeight: _selectedWeight,
            selectedReps: _selectedReps,
            externalLoadKg: _externalLoad,
            durationSeconds: widget.initialDurationSeconds,
            distanceMeters: widget.initialDistanceMeters,
            onWeightChanged: (w) {
              if (w == _selectedWeight) return;
              _selectedWeight = w;
              _dialTick.value++;
              widget.onInputChange(_selectedWeight, _selectedReps, _selectedRpe, _selectedSetType);
            },
            onRepsChanged: (r) {
              if (r == _selectedReps) return;
              _selectedReps = r;
              _dialTick.value++;
              widget.onInputChange(_selectedWeight, _selectedReps, _selectedRpe, _selectedSetType);
            },
            onExternalLoadChanged: (load) {
              if (load == _externalLoad) return;
              _externalLoad = load;
              _dialTick.value++;
              widget.onExternalLoadChange?.call(load);
            },
            onDurationChanged: (dur) {
              widget.onDurationChange?.call(dur);
            },
            onDistanceChanged: (dist) {
              widget.onDistanceChange?.call(dist);
            },
          ),
          ),

          const SizedBox(height: 16),
          Divider(color: _hairline(), height: 1),
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
          const SizedBox(height: 12),
          Divider(color: _hairline(), height: 1),
          const SizedBox(height: 4),

          // Collapsible Cues & Advanced Metrics button
          InkWell(
            onTap: () {
              setState(() {
                _showCues = !_showCues;
              });
              KHaptics.select();
            },
            borderRadius: KRadius.sm,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              alignment: Alignment.center,
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
                    size: 20,
                  ),
                  Text(
                    widget.enableRpeTracking
                        ? (_showCues ? 'Hide form, notes and RPE' : 'Form, notes and RPE')
                        : (_showCues ? 'Hide form and notes' : 'Form and notes'),
                    textAlign: TextAlign.center,
                    style: _WsText.meta.copyWith(fontWeight: FontWeight.w600),
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
                  // One line of form, said the way a spotter would say it,
                  // beside the muscle it should be felt in. Lifts with no
                  // specific cue show only the muscle.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (MuscleThumb.canShow(widget.exercise.muscleGroup)) ...[
                        MuscleThumb(widget.exercise.muscleGroup, height: 56),
                        const SizedBox(width: 14),
                      ],
                      Expanded(
                        child: Builder(builder: (context) {
                          final cue = formCueFor(widget.exercise.name);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                MuscleThumb.canShow(widget.exercise.muscleGroup)
                                    ? 'Feel it in your ${widget.exercise.muscleGroup.toLowerCase()}'
                                    : widget.exercise.muscleGroup,
                                style: _WsText.meta,
                              ),
                              if (cue != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  cue,
                                  key: const Key('form_cue_line'),
                                  style: KText.h3.copyWith(
                                    fontFamily: KText.displayFamily,
                                    fontSize: 16,
                                    height: 1.3,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                              ],
                            ],
                          );
                        }),
                      ),
                    ],
                  ),
                  if (widget.enableRpeTracking) ...[
                    const SizedBox(height: 12),
                    Divider(color: _hairline(), height: 1),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Effort (RPE)', style: _WsText.meta.copyWith(fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [6.0, 7.0, 8.0, 8.5, 9.0, 9.5, 10.0].map((val) {
                        final isSel = _selectedRpe == val;
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Semantics(
                              button: true,
                              selected: isSel,
                              label: 'RPE ${val.toString().replaceAll('.0', '')}',
                              excludeSemantics: true,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  KHaptics.select();
                                  setState(() {
                                    _selectedRpe = val;
                                  });
                                  widget.onInputChange(_selectedWeight, _selectedReps, val, _selectedSetType);
                                },
                                child: AnimatedContainer(
                                  duration: KMotion.of(context, KMotion.instant),
                                  constraints: const BoxConstraints(minHeight: 48),
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isSel ? KColor.ink : KColor.fg.withValues(alpha: KColor.isDark ? 0.05 : 0.04),
                                    borderRadius: KRadius.sm,
                                    border: Border.all(
                                      color: isSel ? KColor.ink : _hairline(),
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    val.toString().replaceAll('.0', ''),
                                    textAlign: TextAlign.center,
                                    style: _WsText.num.copyWith(
                                      fontSize: 14,
                                      fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                                      color: isSel ? KColor.onInk : KColor.textSecondary,
                                    ),
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
                  Divider(color: _hairline(), height: 1),
                  const SizedBox(height: 10),
                  Text('Exercise notes', style: _WsText.meta.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _notesController,
                    maxLines: 2,
                    style: _WsText.body.copyWith(color: KColor.textPrimary),
                    cursorColor: KColor.textPrimary,
                    decoration: InputDecoration(
                      hintText: 'Setup details: seat height, pin, grip width',
                      hintStyle: _WsText.bodySmall.copyWith(color: KColor.textMuted),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ),
            crossFadeState: _showCues ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: KMotion.of(context, KMotion.quick),
            sizeCurve: KMotion.emphasizedCurve,
          ),
        ],
      ),
    );

    return Stack(
      children: [
        console,
        // One-shot ink border pulse; re-keyed per logged set, settles to nothing.
        Positioned.fill(
          child: IgnorePointer(
            child: TweenAnimationBuilder<double>(
              key: ValueKey(_pulseEpoch),
              tween: Tween(begin: _pulseEpoch == 0 ? 0.0 : 1.0, end: 0.0),
              duration: KMotion.of(context, KMotion.slow),
              curve: KMotion.decelerate,
              builder: (context, v, _) => v <= 0.001
                  ? const SizedBox.shrink()
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: KRadius.xl,
                        border: Border.all(
                          color: KColor.ink.withValues(alpha: v),
                          width: 2,
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Set Type & RPE selectors ──────────────────────────────────────────────

  // Deleted _buildSetTypeAndRpeSelectors and _buildLoggedSetsCardsSection (integrated into Unified Console and Training Journal cards)

  Color _setTypeColor(SetType type) => switch (type) {
    SetType.normal => KColor.ink,
    SetType.warmUp => KColor.textSecondary,
    SetType.dropSet => KColor.textPrimary,
  };
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
        duration: KMotion.of(context, KMotion.quick),
        alignment: 0.5,
        curve: KMotion.emphasizedCurve,
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
          return Semantics(
            key: _chipKeys[type],
            button: true,
            selected: isSelected,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                KHaptics.select();
                widget.onChanged(type);
              },
              child: AnimatedContainer(
                duration: KMotion.of(context, KMotion.quick),
                curve: KMotion.emphasizedCurve,
                constraints: const BoxConstraints(minHeight: 48, minWidth: 72),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                margin: const EdgeInsetsDirectional.only(end: 4),
                decoration: BoxDecoration(
                  color: isSelected ? KColor.ink : Colors.transparent,
                  borderRadius: KRadius.pill,
                ),
                child: Text(
                  type.label,
                  style: _WsText.chip.copyWith(
                    fontSize: 14,
                    color: isSelected ? KColor.onInk : KColor.textSecondary,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
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
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: KColor.fg.withValues(alpha: KColor.isDark ? 0.05 : 0.04),
        borderRadius: KRadius.pill,
        border: Border.all(color: _hairline(), width: 1),
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
  final Widget? restBar;

  const _BottomDockWidget({
    this.restBar,
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

    // Debug-only trace: compiled out of profile/release so the dock build stays
    // cheap on the hot path (it rebuilds on every set log and page change).
    assert(() {
      debugPrint('=== WORKOUT SESSION STATE TRACE ===');
      debugPrint('  - originalSplitExerciseCount: $originalSplitExerciseCount (file: lib/screens/workout_session_screen.dart, class: _WorkoutSessionScreenState, field: widget.splitDay.exercises.length, line: 1402)');
      debugPrint('  - currentWorkoutExerciseCount: $currentWorkoutCount (file: lib/screens/workout_session_screen.dart, class: _WorkoutSessionScreenState, getter: _activeSessionExercises.length, line: 115)');
      debugPrint('  - completedExerciseCount: $completedCount (file: lib/screens/workout_session_screen.dart, class: _BottomDockWidget, method: build, line: 3538)');
      debugPrint('  - activeExerciseIndex: $activeIndex (file: lib/screens/workout_session_screen.dart, class: _WorkoutSessionScreenState, field: _selectedIndex, line: 95)');
      debugPrint('  - displayedExerciseNumber: $displayedNumber (file: lib/screens/workout_session_screen.dart, class: _BottomDockWidget, method: build, line: 3766)');
      debugPrint('  - displayedTotalExercises: $displayedTotal (file: lib/screens/workout_session_screen.dart, class: _BottomDockWidget, method: build, line: 3766)');
      debugPrint('  - skippedExercises: ${skippedExercises.entries.where((e) => e.value).map((e) => e.key).toList()} (file: lib/screens/workout_session_screen.dart, class: _WorkoutSessionScreenState, field: _skippedExercises, line: 85)');
      debugPrint('  - replacedExercises: ${substitutedExercises.entries.where((e) => e.value).map((e) => e.key).toList()} (file: lib/screens/workout_session_screen.dart, class: _WorkoutSessionScreenState, field: _substitutedExercises, line: 86)');
      debugPrint('  - temporaryExercises: ${temporaryAdditions?.entries.where((e) => e.value).map((e) => e.key).toList() ?? []} (file: lib/screens/workout_session_screen.dart, class: _WorkoutSessionScreenState, field: _temporaryAdditions, line: 87)');
      debugPrint('  - removedExercises: ${originalSplitExerciseCount - currentWorkoutCount} (file: lib/screens/workout_session_screen.dart, class: _WorkoutSessionScreenState, method: _removeExerciseFromSession, line: 1198)');
      debugPrint('====================================');
      return true;
    }());

    if (exercises.isEmpty) {
      return _DockShell(
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            key: const Key('bottom_add_exercise_button'),
            onPressed: onAddExercise,
            icon: Icon(Icons.add_rounded, color: KColor.onInk),
            label: Text('Add exercise', style: _WsText.button.copyWith(fontSize: 16, color: KColor.onInk)),
            style: ElevatedButton.styleFrom(
              backgroundColor: KColor.ink,
              foregroundColor: KColor.onInk,
              shape: const RoundedRectangleBorder(borderRadius: KRadius.pill),
              elevation: 0,
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

    return _DockShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 0. Rest timer lives inside the dock, so it never floats over the
          // page; the page pads by the dock's measured height.
          if (restBar != null) ...[
            restBar!,
            Divider(color: _hairline(), height: 13),
          ],
          // 2. Where you are: position on the left, previous / next on the
          // right. Names live in the capsules below, so nothing is truncated.
          SizedBox(
            height: 48,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Exercise ${selectedIndex + 1} of ${exercises.length}',
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: _WsText.meta.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: hasPrev ? 'Previous: $prevName' : 'No previous exercise',
                  onPressed: hasPrev
                      ? () {
                          KHaptics.select();
                          onPrevious();
                        }
                      : null,
                  icon: Icon(Icons.chevron_left_rounded, size: KIcons.lg),
                  color: KColor.textPrimary,
                  disabledColor: KColor.textDisabled,
                ),
                IconButton(
                  tooltip: hasNext ? 'Next: $nextName' : 'No next exercise',
                  onPressed: hasNext
                      ? () {
                          KHaptics.select();
                          onNext();
                        }
                      : null,
                  icon: Icon(Icons.chevron_right_rounded, size: KIcons.lg),
                  color: KColor.textPrimary,
                  disabledColor: KColor.textDisabled,
                ),
              ],
            ),
          ),

          // 1. Interactive Progress Capsules Row. Keeps the selected capsule
          // in view, gliding the strip as you move between exercises.
          _ExerciseChipStrip(
            exercises: exercises,
            sets: sets,
            skippedExercises: skippedExercises,
            selectedIndex: selectedIndex,
            onSelectExercise: onSelectExercise,
          ),
          const SizedBox(height: 2),

          // 3. Command Center Action Row: Add Exercise, Log Set, Delete Exercise
          Row(
            children: [
              // Add Exercise Button (Thumb size)
              _DockIconButton(
                icon: Icons.playlist_add_rounded,
                color: KColor.textPrimary,
                tooltip: 'Add exercise',
                onPressed: onAddExercise,
              ),
              const SizedBox(width: 8),

              // Main "Log Set" CTA - UNLOCKED REGARDLESS OF COMPLETION!
              Expanded(
                child: _LogSetButton(
                  exerciseId: activeEx.id,
                  loggedCount: loggedList.length,
                  isSkipped: isSkipped,
                  targetMet: activeWsets >= activeEx.targetSets,
                  onPressed: canLog ? onLogSet : null,
                ),
              ),
              const SizedBox(width: 8),

              // Delete/Remove Exercise Button
              _DockIconButton(
                icon: Icons.delete_outline_rounded,
                color: KColor.danger,
                tooltip: 'Remove exercise from session',
                onPressed: onRemoveExercise,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The dock's surface: an opaque raised sheet (no BackdropFilter, so content
/// scrolling beneath it never forces a blur pass) with a top hairline and
/// generous rounded shoulders. Carbon separates by hairline alone; Paper adds
/// a soft warm shadow cast upward.
class _DockShell extends StatelessWidget {
  final Widget child;
  const _DockShell({required this.child});

  static const _radius = BorderRadius.vertical(top: Radius.circular(28));

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          // Opaque in both themes: nothing should ghost through the dock.
          color: KColor.isDark ? KColor.surface : KColor.card,
          borderRadius: _radius,
          border: Border(
            top: BorderSide(color: KColor.fg.withValues(alpha: KColor.isDark ? 0.12 : 0.08), width: 1),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The dock's exercise capsules. All capsules are laid out (a session has a
/// handful), so the selected one can always be glided into view when you
/// move between exercises by swipe, chevron, chip or auto-advance.
class _ExerciseChipStrip extends StatefulWidget {
  final List<Exercise> exercises;
  final Map<String, List<SetEntry>> sets;
  final Map<String, bool> skippedExercises;
  final int selectedIndex;
  final ValueChanged<int> onSelectExercise;

  const _ExerciseChipStrip({
    required this.exercises,
    required this.sets,
    required this.skippedExercises,
    required this.selectedIndex,
    required this.onSelectExercise,
  });

  @override
  State<_ExerciseChipStrip> createState() => _ExerciseChipStripState();
}

class _ExerciseChipStripState extends State<_ExerciseChipStrip> {
  final List<GlobalKey> _keys = [];

  void _syncKeys() {
    final n = widget.exercises.length;
    while (_keys.length < n) {
      _keys.add(GlobalKey());
    }
    if (_keys.length > n) _keys.removeRange(n, _keys.length);
  }

  @override
  void initState() {
    super.initState();
    _syncKeys();
    // Restored sessions can open on a later exercise.
    if (widget.selectedIndex > 0) _reveal(animate: false);
  }

  @override
  void didUpdateWidget(_ExerciseChipStrip old) {
    super.didUpdateWidget(old);
    _syncKeys();
    if (old.selectedIndex != widget.selectedIndex) _reveal();
  }

  void _reveal({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final i = widget.selectedIndex;
      if (i < 0 || i >= _keys.length) return;
      final ctx = _keys[i].currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: animate ? KMotion.of(context, KMotion.standard) : Duration.zero,
        curve: KMotion.emphasizedCurve,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final exercises = widget.exercises;
    return SizedBox(
      height: 48,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            for (var idx = 0; idx < exercises.length; idx++)
              KeyedSubtree(key: _keys[idx], child: _chip(context, idx)),
          ],
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, int idx) {
    final ex = widget.exercises[idx];
    final exSets = widget.sets[ex.id] ?? [];
    final isSkippedEx = widget.skippedExercises[ex.id] ?? false;
    final wsets = exSets.where((s) => s.isMainWorkingSet).length;
    final isSelected = idx == widget.selectedIndex;
    final isCompleted = wsets >= ex.targetSets;

    // Selected = ink outline; completed = ink check; skipped = block glyph.
    final Color borderCol = isSelected
        ? KColor.textPrimary
        : (isCompleted && !isSkippedEx ? KColor.green.withValues(alpha: 0.45) : _hairline());
    final textCol = isSelected ? KColor.textPrimary : KColor.textSecondary;

    return Semantics(
      button: true,
      selected: isSelected,
      label: '${ex.name}${isSkippedEx ? ', skipped' : (isCompleted ? ', complete' : '')}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          KHaptics.select();
          widget.onSelectExercise(idx);
        },
        // 48dp hit row; the visible capsule is 36dp, centred.
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: AnimatedContainer(
            duration: KMotion.of(context, KMotion.quick),
            curve: KMotion.emphasizedCurve,
            margin: const EdgeInsetsDirectional.only(end: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: isSelected
                  ? KColor.fg.withValues(alpha: KColor.isDark ? 0.10 : 0.06)
                  : Colors.transparent,
              borderRadius: KRadius.pill,
              border: Border.all(color: borderCol, width: isSelected ? 1.4 : 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSkippedEx) ...[
                  Icon(Icons.block_rounded, color: KColor.textMuted, size: 14),
                  const SizedBox(width: 4),
                ] else if (isCompleted) ...[
                  Icon(Icons.check_circle_rounded, color: KColor.green, size: 14),
                  const SizedBox(width: 4),
                ],
                Text(
                  ex.name,
                  maxLines: 1,
                  softWrap: false,
                  style: _WsText.chip.copyWith(
                    color: textCol,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A header meta figure ("12 sets", "4,250 kg") whose digits roll as it
/// changes. One phrase for screen readers.
class _RollingMeta extends StatelessWidget {
  final String prefix;
  final String value;
  final String unit;
  final TextStyle style;
  const _RollingMeta({this.prefix = '', required this.value, this.unit = '', required this.style});

  @override
  Widget build(BuildContext context) {
    // Rolling digits can't wrap like plain text, so on a very narrow
    // header at large text sizes the figure scales down instead of
    // overflowing. At normal sizes it renders at full size.
    return Semantics(
      label: '$prefix$value$unit',
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
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

/// Rest countdown ring. The ink arc is the time left; it sweeps continuously
/// from the rest's end time on its own ticker, so it never jumps once a
/// second. The ticker runs only while the app is in the foreground, the
/// route is visible (TickerMode) and ambient motion is allowed; otherwise
/// the ring steps with the per-second readout. Nothing above it rebuilds.
class _RestRing extends StatefulWidget {
  final DateTime? endsAt;
  final int totalSeconds;
  final int remainingSeconds;

  const _RestRing({
    required this.endsAt,
    required this.totalSeconds,
    required this.remainingSeconds,
  });

  @override
  State<_RestRing> createState() => _RestRingState();
}

class _RestRingState extends State<_RestRing> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker;
  final ValueNotifier<double> _fraction = ValueNotifier<double>(1);
  bool _foreground = true;
  bool _live = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker((_) => _update());
    _fraction.value = _compute();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_RestRing old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (mounted) _sync();
  }

  double _compute() {
    final total = widget.totalSeconds;
    if (total <= 0) return 0;
    final end = widget.endsAt;
    if (_live && end != null) {
      final ms = end.difference(DateTime.now()).inMilliseconds;
      return (ms / (total * 1000)).clamp(0.0, 1.0);
    }
    return (widget.remainingSeconds / total).clamp(0.0, 1.0);
  }

  void _update({bool force = false}) {
    final next = _compute();
    // Repaint only when the arc moves a visible amount (~0.25 degrees).
    if (force || (next - _fraction.value).abs() > 0.0007) _fraction.value = next;
  }

  void _sync() {
    _live = _foreground && widget.endsAt != null && KMotion.ambientAllowed(context);
    if (_live && !_ticker.isActive) {
      _ticker.start();
    } else if (!_live && _ticker.isActive) {
      _ticker.stop();
    }
    _update(force: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _fraction.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          size: const Size.square(30),
          painter: _RestRingPainter(
            fraction: _fraction,
            track: KColor.fg.withValues(alpha: KColor.isDark ? 0.12 : 0.10),
            ink: KColor.ink,
          ),
        ),
      ),
    );
  }
}

class _RestRingPainter extends CustomPainter {
  _RestRingPainter({required this.fraction, required this.track, required this.ink})
      : _track = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = track,
        _arc = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = ink,
        super(repaint: fraction);

  final ValueListenable<double> fraction;
  final Color track;
  final Color ink;
  final Paint _track;
  final Paint _arc;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(1.5);
    canvas.drawOval(rect, _track);
    final f = fraction.value;
    if (f <= 0) return;
    canvas.drawArc(rect, -pi / 2, 2 * pi * f, false, _arc);
  }

  @override
  bool shouldRepaint(_RestRingPainter old) =>
      old.fraction != fraction || old.track != track || old.ink != ink;
}

/// A freshly logged set row: rises a few pixels and fades in once.
/// Instant under reduced motion.
class _RiseIn extends StatefulWidget {
  final Widget child;

  /// How far it rises, as a fraction of its own height (0 = fade only).
  final double rise;
  const _RiseIn({super.key, required this.child, this.rise = 0.22});

  @override
  State<_RiseIn> createState() => _RiseInState();
}

class _RiseInState extends State<_RiseIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
  late final Animation<double> _fade = CurvedAnimation(parent: _c, curve: KMotion.decelerate);
  late final Animation<Offset> _rise = Tween(begin: Offset(0, widget.rise), end: Offset.zero)
      .animate(CurvedAnimation(parent: _c, curve: KMotion.emphasizedCurve));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (KMotion.reduced(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _fade, child: SlideTransition(position: _rise, child: widget.child));
}

/// Square secondary dock action (add / remove exercise), 56dp thumb target.
class _DockIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onPressed;

  const _DockIconButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: KColor.fg.withValues(alpha: KColor.isDark ? 0.06 : 0.04),
        borderRadius: KRadius.pill,
        border: Border.all(color: _hairline(), width: 1),
      ),
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, color: color, size: 23),
        onPressed: onPressed,
      ),
    );
  }
}

/// Primary "Log set n" CTA: a 56dp ink pill, the one solid action on screen.
///
/// Moment declaration — set logged:
///   trigger: logged-set count for the same exercise increases
///   change:  button pops (scale 1 → 1.06 → 1) from the point of action and
///            flashes the accent while a check draws itself (~300 ms), then
///            settles back to ink
///   duration role: KMotion.slow (pop in the first ~35%)
///   haptic:  commit (fired once by `_logSet`, never from this animation)
///   reduced motion: no pop/flash; the label, journal row and jade set badge
///            still update instantly.
class _LogSetButton extends StatefulWidget {
  final String exerciseId;
  final int loggedCount;
  final bool isSkipped;
  final bool targetMet;
  final VoidCallback? onPressed;

  const _LogSetButton({
    required this.exerciseId,
    required this.loggedCount,
    required this.isSkipped,
    required this.targetMet,
    required this.onPressed,
  });

  @override
  State<_LogSetButton> createState() => _LogSetButtonState();
}

class _LogSetButtonState extends State<_LogSetButton> with SingleTickerProviderStateMixin {
  late final AnimationController _pop;
  late final Animation<double> _scale;
  late final Animation<double> _draw;
  bool _flashing = false;

  @override
  void initState() {
    super.initState();
    _pop = AnimationController(vsync: this, duration: KMotion.slow)
      ..addStatusListener((status) {
        final flashing = status == AnimationStatus.forward;
        if (flashing != _flashing && mounted) setState(() => _flashing = flashing);
      });
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.06).chain(CurveTween(curve: KMotion.decelerate)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.06, end: 1.0).chain(CurveTween(curve: KMotion.emphasizedCurve)),
        weight: 65,
      ),
    ]).animate(_pop);
    // The check draws over the first ~300 ms of the 720 ms pop.
    _draw = CurvedAnimation(parent: _pop, curve: const Interval(0.0, 0.42, curve: KMotion.emphasizedCurve));
  }

  @override
  void didUpdateWidget(covariant _LogSetButton old) {
    super.didUpdateWidget(old);
    if (old.exerciseId != widget.exerciseId) {
      // Page change: resolve any running flourish to its end state.
      _pop.value = 0;
      return;
    }
    if (widget.loggedCount > old.loggedCount) {
      final d = KMotion.of(context, KMotion.slow);
      if (d == Duration.zero) return; // reduced motion: end state only
      _pop.duration = d;
      _pop.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skipped = widget.isSkipped;
    // The flash is the only moment the pill leaves ink: the accent, with the
    // check glyph, says "set saved".
    final flash = _flashing && !skipped;
    final Color fill = skipped ? KColor.cardHigh : (flash ? KColor.ember : KColor.ink);
    final Color ink = skipped ? KColor.textMuted : (flash ? KColor.onAccent : KColor.onInk);

    final IconData icon = skipped
        ? Icons.block_rounded
        : (widget.targetMet ? Icons.check_circle_rounded : Icons.add_task_rounded);
    // While the flash plays, the glyph is a check that draws itself in the
    // first ~300 ms of the pop; otherwise the static icon.
    final Widget glyph = flash
        ? SizedBox(
            width: 22,
            height: 22,
            child: KSuccessCheck(size: 22, color: ink, strokeWidth: 2.6, progress: _draw),
          )
        : Icon(icon, size: 22, color: ink);

    return ScaleTransition(
      scale: _scale,
      child: AnimatedContainer(
        duration: KMotion.of(context, KMotion.quick),
        curve: KMotion.emphasizedCurve,
        height: 56,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: KRadius.pill,
          boxShadow: (skipped || KColor.isDark) ? null : KShadow.card,
        ),
        child: ElevatedButton(
          onPressed: widget.onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            foregroundColor: ink,
            disabledForegroundColor: ink,
            overlayColor: ink,
            elevation: 0,
            minimumSize: const Size.fromHeight(56),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: const RoundedRectangleBorder(borderRadius: KRadius.pill),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              glyph,
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  skipped ? 'Skipped today' : 'Log set ${widget.loggedCount + 1}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _WsText.button.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: ink,
                    letterSpacing: -0.2,
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
  final VoidCallback onAddWarmUps;
  final int restSeconds;
  final VoidCallback onEditRest;

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
    required this.onAddWarmUps,
    required this.restSeconds,
    required this.onEditRest,
  });

  @override
  Widget build(BuildContext context) {
    final rampable = exercise.type != ExerciseType.bodyweight &&
        exercise.effectiveExecutionMode == ExerciseExecutionMode.weightReps;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KSheetHeader(exercise.name, subtitle: 'What do you want to do?'),
          const SizedBox(height: 10),
          Divider(height: 1, color: _hairline()),
          if (!isSkipped) ...[
            ListTile(
              leading: Icon(Icons.block_rounded, color: KColor.danger),
              title: Text('Skip exercise', style: _ActionText.title),
              subtitle: Text('Sit this one out today', style: _ActionText.subtitle),
              onTap: () {
                Navigator.of(context).pop();
                _showSkipReasonsSheet(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.swap_horiz_rounded, color: KColor.textPrimary),
              title: Text('Swap exercise', style: _ActionText.title),
              subtitle: Text('Pick something else for today', style: _ActionText.subtitle),
              onTap: () {
                Navigator.of(context).pop();
                onReplace();
              },
            ),
            if (rampable)
              ListTile(
                leading: Icon(Icons.stacked_line_chart_rounded, color: KColor.textPrimary),
                title: Text('Add warm-up sets', style: _ActionText.title),
                subtitle: Text('Ramp up to your working weight', style: _ActionText.subtitle),
                onTap: () {
                  Navigator.of(context).pop();
                  onAddWarmUps();
                },
              ),
            ListTile(
              leading: Icon(Icons.timer_outlined, color: KColor.textPrimary),
              title: Text('Rest timer: ${restLabel(restSeconds)}', style: _ActionText.title),
              subtitle: Text('Remembered for this exercise', style: _ActionText.subtitle),
              onTap: () {
                Navigator.of(context).pop();
                onEditRest();
              },
            ),
          ] else ...[
            ListTile(
              leading: Icon(Icons.refresh_rounded, color: KColor.textPrimary),
              title: Text(isSubstitution ? 'Undo swap' : 'Bring it back', style: _ActionText.title),
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
            leading: Icon(Icons.reorder_rounded, color: KColor.textSecondary),
            title: Text('Reorder exercises', style: _ActionText.title),
            subtitle: Text('Drag them into the order you train', style: _ActionText.subtitle),
            onTap: () {
              Navigator.of(context).pop();
              onReorder();
            },
          ),
          ListTile(
            leading: Icon(Icons.arrow_upward_rounded, color: KColor.textSecondary),
            title: Text('Add exercise before', style: _ActionText.title),
            onTap: () {
              Navigator.of(context).pop();
              onAddBefore();
            },
          ),
          ListTile(
            leading: Icon(Icons.arrow_downward_rounded, color: KColor.textSecondary),
            title: Text('Add exercise after', style: _ActionText.title),
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
    showKSheet(
      context: context,
      isScrollControlled: false,
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
              KSheetHeader(exercise.name, subtitle: 'Why skip it today? No judgement.'),
              const SizedBox(height: 10),
              Divider(height: 1, color: _hairline()),
              ...reasons.map((r) => ListTile(
                title: Text(r, style: _ActionText.title),
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

abstract class _ActionText {
  static TextStyle get title => KText.bodyMedium.copyWith(fontSize: 16, color: KColor.textPrimary);
  static TextStyle get subtitle => KText.caption.copyWith(fontSize: 13, color: KColor.textSecondary);
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
          const KSheetHeader('Reorder exercises', subtitle: 'Drag them into the order you train.'),
          const SizedBox(height: 10),
          Divider(height: 1, color: _hairline()),
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
                  title: Text(ex.name, style: _ActionText.title),
                  subtitle: Text(ex.muscleGroup, style: _ActionText.subtitle),
                  trailing: Icon(Icons.drag_handle_rounded, color: KColor.textSecondary),
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

/// Live PR banner in the Train accent. Names the record type (estimated 1RM,
/// heaviest for the reps, most reps at the weight) and plays one ~700 ms spark
/// burst from its badge (skipped under reduced motion). The milestone haptic
/// fires once in `_logSet` on the commit frame, never here.
/// Personal-record strip. Opens inline under the header (pushing content down,
/// covering nothing) and closes after a few seconds. Saffron is the PR colour;
/// the word "record" and the glyph carry the meaning too.
class _PRToastWidget extends StatelessWidget {
  final bool isVisible;
  final String title;
  final String message;
  /// Re-keys the one-shot spark burst, so each record plays it once.
  final int epoch;
  const _PRToastWidget({
    required this.isVisible,
    required this.title,
    required this.message,
    required this.epoch,
  });

  @override
  Widget build(BuildContext context) {
    // A PR is a highlight: the accent, used sparingly.
    final accent = KColor.ember;
    return AnimatedSize(
      duration: KMotion.of(context, KMotion.standard),
      curve: KMotion.emphasizedCurve,
      alignment: Alignment.topCenter,
      // The spark burst may spill past the strip for its 700 ms.
      clipBehavior: Clip.none,
      child: !isVisible
          ? const SizedBox(width: double.infinity)
          : Semantics(
              liveRegion: true,
              label: 'New personal record. $title. $message',
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 10, 14, 12),
                  decoration: BoxDecoration(
                    color: KColor.tint(accent, dark: 0.14, light: 0.08),
                    borderRadius: KRadius.md,
                    border: Border.all(color: accent.withValues(alpha: 0.5), width: 1),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Badge with the one-shot spark burst behind it.
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: [
                            Positioned(
                              left: -70,
                              top: -70,
                              width: 180,
                              height: 180,
                              child: PrBurst(key: ValueKey(epoch), color: accent),
                            ),
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                              alignment: Alignment.center,
                              child: KIcon(KIcons.record, size: KIcons.md, color: KColor.onAccent),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'New personal record',
                              style: KText.caption.copyWith(fontSize: 12, fontWeight: FontWeight.w700, color: accent),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              title,
                              style: KText.bodyMedium.copyWith(fontSize: 16, fontWeight: FontWeight.w800, color: KColor.textPrimary, height: 1.2),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              message,
                              style: KText.caption.copyWith(
                                fontSize: 13,
                                color: KColor.textSecondary,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
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
}

class _SplitDayRecs {
  const _SplitDayRecs({
    required this.substitutions,
    required this.skips,
    required this.reorders,
    required this.additions,
  });

  final List<({Exercise original, Exercise replacement, int count, int totalSessions})> substitutions;
  final List<({Exercise exercise, int count, int totalSessions})> skips;
  final List<({List<Exercise> newOrder, int count})> reorders;
  final List<({Exercise exercise, int count, int totalSessions})> additions;
}

// ─── Live Timer Stateful Widget ─────────────────────────────────────────────

class _LiveTimerWidget extends StatefulWidget {
  final DateTime startedAt;
  const _LiveTimerWidget({required this.startedAt});

  @override
  State<_LiveTimerWidget> createState() => _LiveTimerWidgetState();
}

class _LiveTimerWidgetState extends State<_LiveTimerWidget> with WidgetsBindingObserver {
  // Under `flutter test` the clock stays still (a live timer would keep
  // scheduling frames for the life of the test).
  static final bool _isTest = WidgetsBinding.instance.runtimeType.toString().contains('Test');

  /// Whole seconds elapsed. Only this leaf listens; nothing else rebuilds.
  late final ValueNotifier<int> _elapsed = ValueNotifier<int>(_now());
  Timer? _timer;

  static TextStyle get _style => KText.numSmall.copyWith(fontSize: 13, color: KColor.textPrimary);

  int _now() => DateTime.now().difference(widget.startedAt).inSeconds;

  @override
  void initState() {
    super.initState();
    if (_isTest) return;
    WidgetsBinding.instance.addObserver(this);
    _schedule();
  }

  /// One-shot timer aimed at the next whole second, so the readout changes
  /// on the beat instead of drifting against the wall clock.
  void _schedule() {
    _timer?.cancel();
    final ms = DateTime.now().difference(widget.startedAt).inMilliseconds;
    final wait = 1000 - (ms % 1000);
    _timer = Timer(Duration(milliseconds: wait + 5), () {
      if (!mounted) return;
      _elapsed.value = _now();
      _schedule();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _elapsed.value = _now();
      _schedule();
    } else {
      // Backgrounded: stop ticking; the readout catches up on resume.
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    if (!_isTest) WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _elapsed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ValueListenableBuilder<int>(
        valueListenable: _elapsed,
        builder: (context, secsTotal, _) {
          final mins = (secsTotal ~/ 60).toString().padLeft(2, '0');
          final secs = (secsTotal % 60).toString().padLeft(2, '0');
          return KTickingText(
            '$mins:$secs',
            style: _style,
            semanticsLabel: 'Workout time ${secsTotal ~/ 60} minutes ${secsTotal % 60} seconds',
          );
        },
      ),
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
    ).animate(CurvedAnimation(parent: _controller, curve: KMotion.decelerate));
  }

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (KMotion.reduced(context)) {
      // Reduced motion: hold the pill still and fully visible; the parent
      // removes it after its lifetime, so it still reads as feedback.
      _controller.value = 0.4;
    } else {
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
    // Transitions drive opacity/offset at the render layer: the pill itself is
    // built once, not once per frame.
    return Align(
      alignment: Alignment.bottomCenter,
      child: FadeTransition(
        opacity: _opacity,
        child: SlideTransition(
          position: _position,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: KColor.ink,
              borderRadius: KRadius.pill,
              boxShadow: KColor.isDark ? null : KShadow.card,
            ),
            child: Text(
              widget.text,
              textAlign: TextAlign.center,
              style: KText.bodyMedium.copyWith(
                color: KColor.onInk,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                height: 1.3,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
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
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const KDragHandle(),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(exercise.name, style: KText.h2),
                    Text(exercise.muscleGroup, style: KText.caption.copyWith(fontSize: 13, color: KColor.textSecondary)),
                    const SizedBox(height: 3),
                    Text(trend, style: KText.caption.copyWith(fontSize: 13, color: KColor.textPrimary, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              if (best != null) ...[
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Best 1RM', style: _WsText.bodySmall.copyWith(fontSize: 12, color: KColor.textMuted)),
                    Text(
                      '${best.estimatedOneRepMax.toStringAsFixed(1)} kg',
                      style: KText.numMedium.copyWith(fontSize: 24, color: KColor.ember),
                    ),
                    Text(
                      '(${best.shortLabel})',
                      style: _WsText.num.copyWith(fontSize: 13, fontWeight: FontWeight.w500, color: KColor.textSecondary),
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
              color: KColor.isDark ? KColor.card : KColor.cardHigh,
              borderRadius: KRadius.md,
              border: Border(left: BorderSide(color: KColor.fat, width: 2)),
            ),
            child: Text(note, style: KText.body.copyWith(fontSize: 14, height: 1.45, color: KColor.textSecondary)),
          ),
          const SizedBox(height: 16),
          if (history.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text('No history yet. Your first set starts it.', style: KText.body.copyWith(color: KColor.textMuted)),
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
        .map((s) => s.shortLabel)
        .join(', ');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: KColor.card,
        borderRadius: KRadius.sm,
        border: Border.all(color: _hairline(), width: 1),
      ),
      child: Row(
        children: [
          Text(dateStr, style: _WsText.num.copyWith(fontSize: 13, color: KColor.textSecondary)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(setsStr, style: _WsText.num.copyWith(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          Text(
            '${entry.totalVolume.toStringAsFixed(0)} kg',
            style: _WsText.num.copyWith(fontSize: 13, fontWeight: FontWeight.w500, color: KColor.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ─── Session scoreboard (completion screen) ─────────────────────────────────
//
// One bold moment: the session's real numbers on the Train jewel, then the
// receipt (new bests, the work, the muscles hit). No confetti, no badges.
//
// Moment declaration, workout complete:
//   trigger: overlay mounts after a successful save
//   change:  the jewel lifts in, the volume counts up from zero, the score
//            cells rise one after another; the receipt rows follow
//   duration role: KMotion.celebrate, plays once
//   haptic:  milestone, fired once by `_finish` on the commit frame
//   skip:    any pointer-down jumps to the end state
//   reduced motion: everything is in its final place on the first frame

/// A record set today, with what it beat.
class _SessionBest {
  const _SessionBest(this.name, this.set, this.previous);
  final String name;
  final SetEntry set;
  final SetEntry? previous;
}

String _liftLabel(SetEntry s) {
  final ext = s.externalLoadKg;
  if (ext != null) return ext > 0 ? 'BW + ${amount(ext)} kg × ${s.reps}' : 'BW × ${s.reps}';
  return s.weight > 0 ? '${amount(s.weight)} kg × ${s.reps}' : 'BW × ${s.reps}';
}

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
  late final AnimationController _intro;
  bool _introStarted = false;
  late final List<_SessionBest> _bests;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(vsync: this, duration: KMotion.celebrate);
    _bests = _findBests(widget.session);
  }

  /// One line per exercise: its best working set today, if it beat every
  /// earlier session's best (the same rule as the live PR count).
  static List<_SessionBest> _findBests(WorkoutSession session) {
    final out = <_SessionBest>[];
    for (final e in session.entries) {
      if (e.isSkipped) continue;
      final prev = WorkoutService.instance.bestSetBefore(e.exercise.id, session.date);
      SetEntry? best;
      for (final s in e.sets) {
        if (!s.isMainWorkingSet || !WorkoutService.beatsPreviousBest(s, prev)) continue;
        if (best == null || s.estimatedOneRepMax > best.estimatedOneRepMax) best = s;
      }
      if (best != null) out.add(_SessionBest(e.exercise.name, best, prev));
    }
    return out;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_introStarted) {
      _introStarted = true;
      if (KMotion.reduced(context)) {
        _intro.value = 1;
      } else {
        _intro.forward();
      }
    }
  }

  void _skipIntro() {
    if (_intro.isAnimating) _intro.value = 1;
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  WorkoutSession? get _prev {
    final p = widget.previousSession;
    if (p == null || p.id == widget.session.id || p.totalVolume <= 0) return null;
    return p;
  }

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  String get _dateLabel {
    final d = widget.session.date;
    return '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
  }

  /// The headline, said like a training partner would say it.
  String _verdict(double volume) {
    final day = widget.session.splitDayName.trim();
    if (_bests.length == 1) return 'New best on ${_bests.first.name}.';
    if (_bests.length > 1) return '${_bests.length} new bests. Big day.';
    final prev = _prev;
    if (prev == null) return day.isEmpty ? 'First one on the books.' : 'First $day on the books.';
    final diff = volume - prev.totalVolume;
    if (diff > prev.totalVolume * 0.02) return 'More than last time. Keep stacking.';
    if (diff < -prev.totalVolume * 0.02) return 'Lighter than last time. You still showed up.';
    return 'Matched last time, kilo for kilo.';
  }

  String? _volumeDelta(double volume) {
    final prev = _prev;
    if (prev == null) return null;
    final diff = (volume - prev.totalVolume).round();
    if (diff > 0) return '+${thousands(diff)} kg on last time';
    if (diff < 0) return '${thousands(-diff)} kg under last time';
    return 'Same as last time';
  }

  Animation<double> _phase(double begin, double end, [Curve curve = KMotion.decelerate]) =>
      CurvedAnimation(parent: _intro, curve: Interval(begin, end, curve: curve));

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final volume = session.totalVolume;
    final sets = session.totalSets;
    final minutes = widget.duration.inMinutes;
    final prev = _prev;
    final worked = session.entries.where((e) => !e.isSkipped && e.sets.isNotEmpty).toList();
    // A bodyweight-only session moved no plates: count reps instead of "0 kg".
    final byReps = volume <= 0;
    final reps = worked.fold<int>(0, (n, e) => n + e.sets.fold<int>(0, (m, s) => m + s.reps));
    final heroValue = byReps ? reps.toDouble() : volume;
    final muscles = worked.map((e) => e.exercise.muscleGroup).toSet().toList();
    final mappable = muscles.where(MuscleThumb.canShow).toSet();

    final heroIn = _phase(0.0, 0.45);
    final countUp = _phase(0.08, 0.85, Curves.easeOutCubic);

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _skipIntro(),
      child: ColoredBox(
        color: KColor.bg,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          // The saved line's check draws itself once.
                          KSuccessCheck(size: KIcons.sm + 2, color: KColor.green),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text('Saved to your log', style: KText.caption.copyWith(color: KColor.green, fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 8),
                          Text(_dateLabel, style: KText.caption.copyWith(color: KColor.textSecondary)),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // The scoreboard.
                      // Fade / rise / settle at the render layer: the card
                      // is built once, not once per frame.
                      FadeTransition(
                        opacity: heroIn,
                        child: SlideTransition(
                          position: Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(heroIn),
                          child: ScaleTransition(
                            scale: Tween(begin: 0.96, end: 1.0).animate(heroIn),
                            child: KHeroSurface(
                          key: const Key('session_scoreboard'),
                          tone: KTone.train,
                          padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                session.splitDayName,
                                style: KText.bodyMedium.copyWith(color: KHeroInk.secondary, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _verdict(volume),
                                style: KText.display.copyWith(color: KHeroInk.primary, fontSize: 26, height: 1.12),
                              ),
                              const SizedBox(height: 22),
                              Semantics(
                                label: '${thousands(volume)} kilograms moved',
                                excludeSemantics: true,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Flexible(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: AnimatedBuilder(
                                          animation: countUp,
                                          builder: (context, _) => Text(
                                            thousands(heroValue * countUp.value),
                                            style: KText.display.copyWith(
                                              color: KHeroInk.primary,
                                              fontSize: 76,
                                              height: 0.95,
                                              letterSpacing: -3.2,
                                              fontFeatures: const [FontFeature.tabularFigures()],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(byReps ? 'reps' : 'kg', style: KText.display.copyWith(color: KHeroInk.secondary, fontSize: 22)),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Container(
                                    width: 18,
                                    height: 3,
                                    decoration: BoxDecoration(
                                      borderRadius: KRadius.pill,
                                      color: KColor.ink,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      byReps ? 'Bodyweight, all of it' : (_volumeDelta(volume) ?? 'Moved today'),
                                      style: KText.bodyMedium.copyWith(color: KHeroInk.secondary),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              Container(height: 1, color: KHeroInk.rule),
                              const SizedBox(height: 16),
                              // Rules between cells are painted at the gaps over
                              // the row's own height (no IntrinsicHeight pass).
                              CustomPaint(
                                foregroundPainter: _CellRulesPainter(color: KHeroInk.rule, cells: 4, gap: _cellGap),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _scoreCell(0, '$minutes', 'min', prev?.durationMinutes == null ? null : 'was ${prev!.durationMinutes}'),
                                    const SizedBox(width: _cellGap),
                                    _scoreCell(1, '$sets', sets == 1 ? 'set' : 'sets', prev == null ? null : 'was ${prev.totalSets}'),
                                    const SizedBox(width: _cellGap),
                                    _scoreCell(2, '${_bests.length}', _bests.length == 1 ? 'PR' : 'PRs', null),
                                    const SizedBox(width: _cellGap),
                                    _scoreCell(3, '${widget.score}', 'score', null),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                          ),
                        ),
                      ),

                      if (_bests.isNotEmpty) ...[
                        const SizedBox(height: 28),
                        KReveal(index: 2, delay: const Duration(milliseconds: 500), child: Text('New bests', style: KText.h1.copyWith(fontSize: 22))),
                        const SizedBox(height: 10),
                        for (final (i, b) in _bests.indexed)
                          KReveal(
                            index: 3 + i,
                            delay: const Duration(milliseconds: 500),
                            child: _BestRow(best: b),
                          ),
                      ],

                      if (worked.isNotEmpty) ...[
                        const SizedBox(height: 28),
                        KReveal(index: 3, delay: const Duration(milliseconds: 600), child: Text('The work', style: KText.h1.copyWith(fontSize: 22))),
                        const SizedBox(height: 6),
                        for (final (i, e) in worked.indexed)
                          KReveal(
                            index: 4 + i,
                            delay: const Duration(milliseconds: 600),
                            child: _ReceiptRow(entry: e),
                          ),
                      ],

                      if (mappable.isNotEmpty) ...[
                        const SizedBox(height: 28),
                        KReveal(
                          index: 6,
                          delay: const Duration(milliseconds: 700),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 132,
                                child: MuscleBodyMap(
                                  view: BodyView.sideBySide,
                                  highlightedMuscles: mappable,
                                  height: 128,
                                ),
                              ),
                              const SizedBox(width: KSpacing.lg),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Hit today', style: KText.h1.copyWith(fontSize: 20)),
                                    const SizedBox(height: 4),
                                    Text(
                                      muscles.join(', '),
                                      style: KText.body.copyWith(color: KColor.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Share the card, or done.
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('share_workout_button'),
                        onPressed: () => showWorkoutShareSheet(
                          context,
                          WorkoutShareData.fromSession(
                            session,
                            duration: widget.duration,
                            prCount: _bests.length,
                            isPr: (id, s) => WorkoutService.beatsPreviousBest(
                              s,
                              WorkoutService.instance.bestSetBefore(id, session.date),
                            ),
                          ),
                        ),
                        icon: Icon(Icons.ios_share_rounded, size: 18, color: KColor.textPrimary),
                        label: Text('Share', style: _WsText.button.copyWith(fontSize: 16, color: KColor.textPrimary)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: KColor.textPrimary,
                          side: BorderSide(color: KColor.fg.withValues(alpha: KColor.isDark ? 0.22 : 0.24)),
                          shape: const RoundedRectangleBorder(borderRadius: KRadius.pill),
                          minimumSize: const Size.fromHeight(56),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: widget.onDone,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: KColor.ink,
                          foregroundColor: KColor.onInk,
                          shape: const RoundedRectangleBorder(borderRadius: KRadius.pill),
                          minimumSize: const Size.fromHeight(56),
                          elevation: 0,
                        ),
                        child: Text('Done', style: _WsText.button.copyWith(fontSize: 16, color: KColor.onInk)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Space between scoreboard cells; the rule sits in its middle.
  static const double _cellGap = 21;

  /// One scoreboard cell: a big number, its unit, and last time's number
  /// when there is one. Cells rise in one after another.
  Widget _scoreCell(int i, String value, String unit, String? was) {
    final a = _phase(0.3 + i * 0.1, 0.7 + i * 0.075);
    return Expanded(
      child: FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.12), end: Offset.zero).animate(a),
          child: Semantics(
          label: '$value $unit${was == null ? '' : ', $was'}',
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: KText.display.copyWith(
                    color: KHeroInk.primary,
                    fontSize: 32,
                    height: 1.0,
                    letterSpacing: -1.2,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(unit, style: KText.caption.copyWith(color: KHeroInk.secondary)),
              if (was != null)
                Text(was, style: KText.caption.copyWith(color: KHeroInk.muted, fontSize: 11)),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

/// Hairline rules between equal-width cells, centred in each [gap], drawn
/// over the full height of the row.
class _CellRulesPainter extends CustomPainter {
  _CellRulesPainter({required this.color, required this.cells, required this.gap})
      : _p = Paint()
          ..color = color
          ..strokeWidth = 1;
  final Color color;
  final int cells;
  final double gap;
  final Paint _p;

  @override
  void paint(Canvas canvas, Size size) {
    if (cells < 2) return;
    final cell = (size.width - gap * (cells - 1)) / cells;
    for (var i = 1; i < cells; i++) {
      final x = (cell * i + gap * (i - 1) + gap / 2).roundToDouble() + 0.5;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), _p);
    }
  }

  @override
  bool shouldRepaint(_CellRulesPainter old) => old.color != color || old.cells != cells || old.gap != gap;
}

/// A new best: the lift, today's set big, and the set it beat.
class _BestRow extends StatelessWidget {
  const _BestRow({required this.best});
  final _SessionBest best;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _hairline()))),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: KRadius.pill,
              color: KColor.ember,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(best.name, style: KText.bodyMedium.copyWith(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _liftLabel(best.set),
                style: KText.display.copyWith(fontSize: 22, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
              if (best.previous != null)
                Text(
                  'beat ${_liftLabel(best.previous!)}',
                  style: KText.caption.copyWith(color: KColor.textMuted),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One exercise on the receipt: name, working sets, the top set, and a
/// dotted perforation below.
class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({required this.entry});
  final ExerciseEntry entry;

  @override
  Widget build(BuildContext context) {
    final working = entry.sets.where((s) => s.isMainWorkingSet).toList();
    SetEntry? top;
    for (final s in working) {
      if (top == null || s.estimatedOneRepMax > top.estimatedOneRepMax) top = s;
    }
    final timed = top?.durationSeconds != null;
    final value = top == null
        ? plural(entry.sets.length, 'set')
        : timed
            ? '${top.durationSeconds! ~/ 60}:${(top.durationSeconds! % 60).toString().padLeft(2, '0')}'
            : _liftLabel(top);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.exercise.name, style: KText.bodyMedium.copyWith(fontSize: 15)),
                    Text(plural(working.length, 'working set'), style: KText.caption.copyWith(color: KColor.textMuted)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                value,
                style: KText.numSmall.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // The perforation between lines of a printed receipt.
          SizedBox(
            height: 2,
            child: CustomPaint(painter: _LeaderPainter(KColor.fg.withValues(alpha: 0.2))),
          ),
        ],
      ),
    );
  }
}

/// A dotted rule, like the perforation on a printed receipt.
class _LeaderPainter extends CustomPainter {
  _LeaderPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    for (var x = 1.0; x < size.width; x += 5) {
      canvas.drawCircle(Offset(x, size.height / 2), 0.9, p);
    }
  }

  @override
  bool shouldRepaint(_LeaderPainter old) => old.color != color;
}

// ─── Kyno's plan card ─────────────────────────────────────────────────────────
// Today's sets in the person's own loading pattern (done ones ticked, the next
// one marked), a swap when the lift has stalled, and how the last session
// went: when it fell short, the likely causes from food, sleep and spacing,
// each with what to change.

class _CoachPlanCard extends StatelessWidget {
  const _CoachPlanCard({required this.plan, required this.doneSets, this.onSwap});

  final CoachPlan plan;
  final int doneSets;
  final VoidCallback? onSwap;

  @override
  Widget build(BuildContext context) {
    final hair = KColor.isDark ? KColor.fg.withValues(alpha: 0.08) : KColor.border;
    final label = KText.caption.copyWith(color: KColor.textSecondary, fontSize: 12, fontWeight: FontWeight.w600);
    final body = KText.caption.copyWith(color: KColor.textSecondary, fontSize: 12.5, height: 1.4);
    final below = plan.verdict == SessionVerdict.belowPar;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: KColor.card,
        borderRadius: KRadius.md,
        border: Border.all(color: hair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const KynoMark(size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text("Kyno's plan for today", style: label)),
              Text(plan.pattern.label, style: KText.caption.copyWith(color: KColor.textMuted, fontSize: 11.5)),
            ],
          ),
          const SizedBox(height: 10),
          Text(plan.headline, style: KText.h3.copyWith(fontSize: 16)),
          const SizedBox(height: 8),
          for (var i = 0; i < plan.sets.length; i++)
            _PlanSetRow(index: i, set: plan.sets[i], done: i < doneSets, next: i == doneSets),
          if (plan.dropSetFinisher) ...[
            const SizedBox(height: 4),
            Text('Then your usual drop: take off 20 to 25% and go to a clean failure.', style: body),
          ],
          // The stage card above already says why; this card is the sets.
          if (plan.swap case final swap?) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: hair),
            const SizedBox(height: 12),
            Text('Stalled: try a swap', style: label),
            const SizedBox(height: 4),
            Text('${swap.name}. ${swap.reason}', style: body),
            if (onSwap != null) ...[
              const SizedBox(height: 8),
              _CoachPillButton(label: 'Swap for today', semantic: 'Swap to ${swap.name} for today', onTap: onSwap!),
            ],
          ],
          if (plan.verdictLine.isNotEmpty) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: hair),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  below ? Icons.trending_down_rounded : Icons.trending_up_rounded,
                  size: 16,
                  color: below ? KColor.danger : KColor.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(plan.verdictLine, style: body.copyWith(color: KColor.textPrimary))),
              ],
            ),
            if (below)
              for (final c in plan.causes) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.finding, style: body.copyWith(color: KColor.textPrimary, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(c.fix, style: body),
                    ],
                  ),
                ),
              ],
          ],
        ],
      ),
    );
  }
}

class _PlanSetRow extends StatelessWidget {
  const _PlanSetRow({required this.index, required this.set, required this.done, required this.next});
  final int index;
  final PlannedSet set;
  final bool done;
  final bool next;

  @override
  Widget build(BuildContext context) {
    final num = KText.numSmall.copyWith(
      fontSize: 14,
      fontWeight: next ? FontWeight.w700 : FontWeight.w500,
      color: done ? KColor.textMuted : KColor.textPrimary,
      decoration: done ? TextDecoration.lineThrough : null,
    );
    return Semantics(
      label: 'Set ${index + 1}: ${set.label.replaceAll('×', 'for')} reps${done ? ', done' : next ? ', next' : ''}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: done
                  ? Icon(Icons.check_rounded, size: 15, color: KColor.textMuted)
                  : next
                      ? Icon(Icons.chevron_right_rounded, size: 18, color: KColor.textPrimary)
                      : const SizedBox.shrink(),
            ),
            SizedBox(
              width: 56,
              child: Text('Set ${index + 1}', style: KText.caption.copyWith(color: KColor.textMuted, fontSize: 12)),
            ),
            Text(set.label, style: num),
          ],
        ),
      ),
    );
  }
}

class _CoachPillButton extends StatelessWidget {
  const _CoachPillButton({required this.label, required this.semantic, required this.onTap});
  final String label;
  final String semantic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semantic,
      excludeSemantics: true,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: KColor.textPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: KRadius.pill,
            side: BorderSide(color: KColor.fg.withValues(alpha: KColor.isDark ? 0.18 : 0.2)),
          ),
        ),
        child: Text(label, style: KText.caption.copyWith(color: KColor.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
