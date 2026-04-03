import 'dart:convert';
import 'dart:math' show max;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/workout_split.dart';
import '../models/workout_session.dart';

// ─── WorkoutService ───────────────────────────────────────────────────────────
//
// Singleton service — owns the workout split config, custom exercises,
// and session history.
//
// Persistence: SharedPreferences + JSON under key 'workout_data_v2'.
//
// Key design decisions:
//   • isSetupDone gates the one-time wizard in WorkoutScreen.
//   • Custom exercises live alongside built-in ones; same Exercise model.
//   • Progression is typed — different increment per ExerciseType.
//   • progressionHint() only analyses isMainWorkingSet sets (excludes warm-ups).
//   • Sessions are pruned at 200 entries (oldest first).

class WorkoutService extends ChangeNotifier {
  WorkoutService._();
  static final WorkoutService instance = WorkoutService._();

  static const _kData = 'workout_data_v2';
  static const _maxSessions = 200;

  WorkoutSplit? _split;
  List<WorkoutSession> _sessions = [];
  List<Exercise> _customExercises = [];
  WorkoutSession? _draftSession;
  bool _setupDone = false;
  bool _ready = false;

  // ── Public read API ──────────────────────────────────────────────────────

  WorkoutSplit get split => _split ?? defaultWorkoutSplit;

  List<WorkoutSession> get sessions => List.unmodifiable(_sessions);

  WorkoutSession? get draftSession => _draftSession;

  bool get isReady => _ready;
  bool get isSetupDone => _setupDone;

  /// Custom exercises added by the user.
  List<Exercise> get customExercises => List.unmodifiable(_customExercises);

  /// Full library: built-in (deduped) + user-created custom exercises.
  List<Exercise> get allExercises {
    final seen = <String>{};
    final base = deduplicatedLibrary.where((e) => seen.add(e.id)).toList();
    for (final c in _customExercises) {
      if (seen.add(c.id)) base.add(c);
    }
    return base;
  }

  // ── Split day queries ────────────────────────────────────────────────────

  /// SplitDay for today (weekday), or null if rest/no split.
  SplitDay? get todaySplitDay {
    final d = split.dayFor(DateTime.now().weekday);
    return (d != null && !d.isRestDay) ? d : null;
  }

  List<WorkoutSession> sessionsForSplitDay(String splitDayName) =>
      _sessions
          .where((s) => s.splitDayName == splitDayName && !s.isEmpty)
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));

  /// SplitDay for a given date.
  SplitDay? splitDayFor(DateTime date) {
    final d = split.dayFor(date.weekday);
    return (d != null && !d.isRestDay) ? d : null;
  }

  /// All non-rest SplitDays in the configured split (for day picker).
  List<SplitDay> get trainingDays =>
      split.days.where((d) => !d.isRestDay).toList();

  // ── Session queries ──────────────────────────────────────────────────────

  /// Already-saved session for [date], or null.
  WorkoutSession? sessionFor(DateTime date) {
    final key = _dateKey(date);
    for (final s in _sessions.reversed) {
      if (_dateKey(s.date) == key) return s;
    }
    return null;
  }

  WorkoutSession? sessionForDateAndSplit(DateTime date, String splitDayName) {
    final key = _dateKey(date);
    for (final s in _sessions.reversed) {
      if (_dateKey(s.date) == key && s.splitDayName == splitDayName) return s;
    }
    return null;
  }

  List<WorkoutSession> sessionsForDate(DateTime date) {
    final key = _dateKey(date);
    return _sessions.where((s) => _dateKey(s.date) == key).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  /// Most recent logged session for a split day name (for previous-best UI).
  WorkoutSession? lastSessionFor(String splitDayName) {
    for (final s in _sessions.reversed) {
      if (s.splitDayName == splitDayName && !s.isEmpty) return s;
    }
    return null;
  }

  WorkoutSession? lastSessionForWeekday(int weekday) {
    for (final s in _sessions.reversed) {
      if (s.splitDayWeekday == weekday && !s.isEmpty) return s;
    }
    return null;
  }

  /// [limit] most recent non-empty sessions, newest first.
  List<WorkoutSession> recentSessions({int limit = 10}) =>
      _sessions.where((s) => !s.isEmpty).toList().reversed.take(limit).toList();

  // ── Weekly progress queries ───────────────────────────────────────────────

  /// Number of non-empty sessions logged this week (Mon–Sun).
  int get workoutsThisWeek {
    final now = DateTime.now();
    final mon = now.subtract(Duration(days: now.weekday - 1));
    final start = DateTime(mon.year, mon.month, mon.day);
    return _sessions.where((s) {
      final d = s.date;
      return !s.isEmpty &&
          !d.isBefore(start) &&
          d.isBefore(start.add(const Duration(days: 7)));
    }).length;
  }

  int get totalSetsThisWeek {
    final now = DateTime.now();
    final mon = now.subtract(Duration(days: now.weekday - 1));
    final start = DateTime(mon.year, mon.month, mon.day);
    return _sessions
        .where((s) {
          final d = s.date;
          return !s.isEmpty &&
              !d.isBefore(start) &&
              d.isBefore(start.add(const Duration(days: 7)));
        })
        .fold(0, (sum, s) => sum + s.totalSets);
  }

  double get totalVolumeThisWeek {
    final now = DateTime.now();
    final mon = now.subtract(Duration(days: now.weekday - 1));
    final start = DateTime(mon.year, mon.month, mon.day);
    return _sessions
        .where((s) {
          final d = s.date;
          return !s.isEmpty &&
              !d.isBefore(start) &&
              d.isBefore(start.add(const Duration(days: 7)));
        })
        .fold(0.0, (sum, s) => sum + s.totalWorkingVolume);
  }

  List<String> get muscleGroupsTrainedThisWeek {
    final now = DateTime.now();
    final mon = now.subtract(Duration(days: now.weekday - 1));
    final start = DateTime(mon.year, mon.month, mon.day);
    final groups = <String>{};
    for (final s in _sessions) {
      final d = s.date;
      if (s.isEmpty ||
          d.isBefore(start) ||
          !d.isBefore(start.add(const Duration(days: 7)))) {
        continue;
      }
      for (final entry in s.entries) {
        groups.add(entry.exercise.muscleGroup);
      }
    }
    final out = groups.toList()..sort();
    return out;
  }

  List<int> weeklyWorkoutCounts({int weeks = 6}) {
    final now = DateTime.now();
    final thisMonday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    return List<int>.generate(weeks, (index) {
      final weekStart = thisMonday.subtract(
        Duration(days: (weeks - 1 - index) * 7),
      );
      final weekEnd = weekStart.add(const Duration(days: 7));
      return _sessions
          .where(
            (s) =>
                !s.isEmpty &&
                !s.date.isBefore(weekStart) &&
                s.date.isBefore(weekEnd),
          )
          .length;
    });
  }

  List<double> weeklyVolumeTrend({int weeks = 6}) {
    final now = DateTime.now();
    final thisMonday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    return List<double>.generate(weeks, (index) {
      final weekStart = thisMonday.subtract(
        Duration(days: (weeks - 1 - index) * 7),
      );
      final weekEnd = weekStart.add(const Duration(days: 7));
      return _sessions
          .where(
            (s) =>
                !s.isEmpty &&
                !s.date.isBefore(weekStart) &&
                s.date.isBefore(weekEnd),
          )
          .fold(0.0, (sum, s) => sum + s.totalWorkingVolume);
    });
  }

  List<double> exerciseOneRmTrend(String exerciseId, {int limit = 6}) {
    final history = historyFor(exerciseId, limit: limit).reversed.toList();
    return history
        .map(
          (h) =>
              h.entry.topProgressionSet?.estimatedOneRepMax ??
              h.entry.topWorkingSet?.estimatedOneRepMax ??
              h.entry.topSet?.estimatedOneRepMax ??
              0.0,
        )
        .toList();
  }

  String consistencyLabel() {
    final counts = weeklyWorkoutCounts(weeks: 4);
    if (counts.isEmpty) return 'No training history yet';
    final total = counts.fold<int>(0, (sum, value) => sum + value);
    if (total >= 16) return 'Locked in';
    if (total >= 12) return 'Very consistent';
    if (total >= 8) return 'Building consistency';
    if (total >= 4) return 'Needs more regularity';
    return 'Just getting started';
  }

  ({String title, String detail})? latestPersonalBest() {
    for (final session
        in _sessions.where((s) => !s.isEmpty).toList().reversed) {
      for (final entry in session.entries) {
        final top =
            entry.topProgressionSet ?? entry.topWorkingSet ?? entry.topSet;
        if (top == null) continue;
        final previousBest = bestSetBefore(entry.exercise.id, session.date);
        if (previousBest == null ||
            top.estimatedOneRepMax > previousBest.estimatedOneRepMax + 0.01) {
          return (
            title: 'New PR on ${entry.exercise.name}',
            detail:
                '${top.weight.toStringAsFixed(top.weight == top.weight.truncateToDouble() ? 0 : 1)} kg × ${top.reps}',
          );
        }
      }
    }
    return null;
  }

  /// Consecutive-day training streak ending today.
  int get currentStreak {
    final today = DateTime.now();
    int streak = 0;
    for (int offset = 0; offset <= 60; offset++) {
      final day = today.subtract(Duration(days: offset));
      final key = _dateKey(day);
      final trained = _sessions.any(
        (s) => _dateKey(s.date) == key && !s.isEmpty,
      );
      if (trained) {
        streak++;
      } else if (offset > 0) {
        // Gap — streak ends (allow 1-day gap only for today never logged yet)
        break;
      }
    }
    return streak;
  }

  // ── Performance queries ──────────────────────────────────────────────────

  /// All sessions for a specific exercise (newest first).
  List<({DateTime date, ExerciseEntry entry})> historyFor(
    String exerciseId, {
    int limit = 10,
  }) {
    final out = <({DateTime date, ExerciseEntry entry})>[];
    for (final s in _sessions.reversed) {
      for (final e in s.entries) {
        if (e.exercise.id == exerciseId && !e.isEmpty) {
          out.add((date: s.date, entry: e));
          break;
        }
      }
      if (out.length >= limit) break;
    }
    return out;
  }

  double exerciseTrendDelta(String exerciseId, {int lookback = 3}) {
    final history = historyFor(exerciseId, limit: lookback);
    if (history.length < 2) return 0;
    final latest =
        history.first.entry.topProgressionSet?.estimatedOneRepMax ??
        history.first.entry.topWorkingSet?.estimatedOneRepMax ??
        0;
    final oldest =
        history.last.entry.topProgressionSet?.estimatedOneRepMax ??
        history.last.entry.topWorkingSet?.estimatedOneRepMax ??
        0;
    return latest - oldest;
  }

  String exerciseTrendLabel(String exerciseId) {
    final delta = exerciseTrendDelta(exerciseId);
    if (delta > 1.5) {
      return 'Trending up';
    }
    if (delta < -1.5) {
      return 'Slight dip';
    }
    return 'Stable';
  }

  String exerciseProgressNote(Exercise exercise, String splitDayName) {
    final last = lastEntryFor(exercise.id, splitDayName);
    final trend = exerciseTrendDelta(exercise.id);
    final hint = progressionHint(
      last,
      exercise,
      targetRepsMin: exercise.targetRepMin,
      targetRepsMax: exercise.targetRepMax,
    );
    if (last == null) {
      return 'Use a controlled first session and find a stable working weight.';
    }
    if (trend > 1.5) {
      return 'Recent performance is improving. $hint';
    }
    if (trend < -1.5) {
      return 'Performance is slightly down. Keep execution tight and don’t force load jumps.';
    }
    return hint.replaceFirst('→ ', '').replaceFirst('↑ ', '');
  }

  /// Last session's ExerciseEntry for a given exercise + split day.
  ExerciseEntry? lastEntryFor(String exerciseId, String splitDayName) {
    final last = lastSessionFor(splitDayName);
    if (last == null) return null;
    for (final e in last.entries) {
      if (e.exercise.id == exerciseId && !e.isEmpty) return e;
    }
    return null;
  }

  /// All-time best set for an exercise (highest estimated 1RM).
  SetEntry? bestSetEver(String exerciseId) {
    SetEntry? best;
    for (final s in _sessions) {
      for (final e in s.entries) {
        if (e.exercise.id != exerciseId) continue;
        final top = e.topWorkingSet ?? e.topSet;
        if (top == null) continue;
        if (best == null || top.estimatedOneRepMax > best.estimatedOneRepMax) {
          best = top;
        }
      }
    }
    return best;
  }

  SetEntry? bestSetBefore(String exerciseId, DateTime beforeDate) {
    SetEntry? best;
    for (final s in _sessions) {
      if (!s.date.isBefore(beforeDate)) continue;
      for (final e in s.entries) {
        if (e.exercise.id != exerciseId) continue;
        final top = e.topProgressionSet ?? e.topWorkingSet ?? e.topSet;
        if (top == null) continue;
        if (best == null || top.estimatedOneRepMax > best.estimatedOneRepMax) {
          best = top;
        }
      }
    }
    return best;
  }

  // ── Session comparison (for completion screen) ────────────────────────────

  SessionDelta compareWithPrevious(
    WorkoutSession current,
    WorkoutSession previous,
  ) {
    // Volume comparison
    final currVol = current.totalWorkingVolume;
    final prevVol = previous.totalWorkingVolume;
    final volChangePct = prevVol > 0
        ? ((currVol - prevVol) / prevVol) * 100
        : 0.0;

    // Per-exercise deltas
    final deltas = <ExerciseDelta>[];
    for (final entry in current.entries) {
      final top =
          entry.topProgressionSet ?? entry.topWorkingSet ?? entry.topSet;
      if (top == null) continue;

      // Find matching entry in previous session
      ExerciseEntry? prevEntry;
      for (final pe in previous.entries) {
        if (pe.exercise.id == entry.exercise.id) {
          prevEntry = pe;
          break;
        }
      }

      final prevTop =
          prevEntry?.topProgressionSet ??
          prevEntry?.topWorkingSet ??
          prevEntry?.topSet;
      final oneRmNow = top.estimatedOneRepMax;
      final oneRmPrev = prevTop?.estimatedOneRepMax ?? 0.0;
      final delta = oneRmNow - oneRmPrev;
      final isPr =
          oneRmNow >
          (bestSetBefore(entry.exercise.id, current.date)?.estimatedOneRepMax ??
                  0) +
              0.01;
      final bestStr =
          '${top.weight.toStringAsFixed(top.weight == top.weight.truncateToDouble() ? 0 : 1)} kg × ${top.reps}';

      deltas.add(
        ExerciseDelta(
          exerciseName: entry.exercise.name,
          oneRmDelta: delta,
          isPr: isPr,
          bestSetStr: bestStr,
        ),
      );
    }

    return SessionDelta(volumeChangePct: volChangePct, exerciseDeltas: deltas);
  }

  // ── Progression hints ────────────────────────────────────────────────────
  //
  // IMPORTANT: only analyses isMainWorkingSet sets (excludes warm-ups and
  // drop sets from the progression decision — they are lighter by design).
  //
  // Type-specific increment logic:
  //   barbellCompound  → +2.5 kg when all working sets hit top of rep range
  //   dumbbell         → +2 kg (nearest dumbbell increment practical)
  //   cableMachine     → +5 kg (standard stack increment)
  //   isolation        → prefer beating reps first; load only after 2 sessions
  //   bodyweight       → reps-first; suggest +2.5 kg plate/vest after 2 sessions
  //
  // [targetRepsMin] / [targetRepsMax]: working rep range. Default 8–12.

  String progressionHint(
    ExerciseEntry? lastEntry,
    Exercise exercise, {
    int? targetRepsMin,
    int? targetRepsMax,
  }) {
    final repMin = targetRepsMin ?? exercise.targetRepMin;
    final repMax = targetRepsMax ?? exercise.targetRepMax;

    if (lastEntry == null || lastEntry.isEmpty) {
      return '💡 First time — start light and focus on form';
    }

    // Prioritise true working sets. Fall back to superset working sets if needed.
    final progressionSets = lastEntry.sets
        .where((s) => s.drivesProgression)
        .toList();
    final sets = progressionSets.isNotEmpty
        ? progressionSets
        : lastEntry.sets.where((s) => s.isMainWorkingSet).toList();
    if (sets.isEmpty) {
      // Last session had only warm-ups logged — treat as first time
      return '💡 No working sets last time — find your working weight';
    }

    final topW = sets.map((s) => s.weight).reduce(max);
    final avgReps =
        sets.fold<double>(0, (sum, s) => sum + s.reps) / sets.length;
    final allTop = sets.every((s) => s.reps >= repMax);
    final allMin = sets.every((s) => s.reps >= repMin);
    final missed = sets.any((s) => s.reps < repMin - 1);

    if (missed) return '→ Same weight — hit all reps before progressing';
    if (!allMin) return '→ Keep same weight and beat reps next time';
    if (!allTop && avgReps >= repMin + ((repMax - repMin) / 2)) {
      return '→ This looks like a stable working weight — try one more rep before adding load';
    }
    if (!allTop) return '→ Push reps — aim for $repMax on your working sets';

    // All working sets hit top range — type-specific progression
    switch (exercise.type) {
      case ExerciseType.barbellCompound:
        final next = topW + 2.5;
        return '↑ You can likely increase weight next session — try ${next.toStringAsFixed(1)} kg';

      case ExerciseType.dumbbell:
        final next = topW + 2.0;
        return '↑ Strong session — move to ${next.toStringAsFixed(1)} kg dumbbells if form stays clean';

      case ExerciseType.cableMachine:
        final next = topW + 5.0;
        return '↑ You can likely add a plate next time — try ${next.toStringAsFixed(0)} kg';

      case ExerciseType.isolation:
        // Check if same weight for 2 consecutive sessions before adding load
        final history = historyFor(exercise.id, limit: 2);
        final repeatedAtSameWeight =
            history.length >= 2 &&
            history[0].entry.sets.isNotEmpty &&
            history[1].entry.sets.isNotEmpty &&
            (history[0].entry.sets.map((s) => s.weight).reduce(max) -
                        history[1].entry.sets.map((s) => s.weight).reduce(max))
                    .abs() <
                0.5;
        if (repeatedAtSameWeight) {
          final next = topW + 2.5;
          return '↑ Consistent at this load — step up to ${next.toStringAsFixed(1)} kg next time';
        }
        return '→ Good isolation working weight — match or beat reps once more before adding load';

      case ExerciseType.bodyweight:
        // Bodyweight: beat reps twice, then suggest adding load
        final history2 = historyFor(exercise.id, limit: 2);
        final bothMaxReps =
            history2.length >= 2 &&
            history2[0].entry.sets.every((s) => s.reps >= repMax) &&
            history2[1].entry.sets.every((s) => s.reps >= repMax);
        if (bothMaxReps) {
          return '↑ Add resistance — try a plate or resistance band next time';
        }
        return '→ Push for $repMax clean reps before adding load';
    }
  }

  List<SplitDay> selectableWorkoutDaysFor(DateTime date) {
    final planned = splitDayFor(date);
    final others = trainingDays
        .where((d) => d.weekday != planned?.weekday)
        .toList();
    return [planned, ...others].whereType<SplitDay>().toList();
  }

  SplitDay customWorkoutDay({String name = 'Custom Workout'}) =>
      SplitDay(weekday: 0, name: name, exercises: const []);

  // ── Previous performance display string ──────────────────────────────────
  //
  // Returns compact "Last: W×R, W×R" from main working sets only.

  String lastSessionDisplay(ExerciseEntry? lastEntry) {
    if (lastEntry == null || lastEntry.isEmpty) return '';
    final working = lastEntry.sets.where((s) => s.isMainWorkingSet).toList();
    if (working.isEmpty) {
      // Fall back to all sets if somehow only warm-ups were logged
      final all = lastEntry.sets.take(5);
      final parts = all
          .map(
            (s) =>
                '${s.weight.toStringAsFixed(s.weight == s.weight.truncateToDouble() ? 0 : 1)}×${s.reps}',
          )
          .join(', ');
      return 'Last: $parts (warm-ups)';
    }
    final parts = working
        .take(5)
        .map(
          (s) =>
              '${s.weight.toStringAsFixed(s.weight == s.weight.truncateToDouble() ? 0 : 1)}×${s.reps}',
        )
        .join(', ');
    return 'Last: $parts';
  }

  // ── Custom exercise write API ─────────────────────────────────────────────

  Future<void> addCustomExercise(Exercise exercise) async {
    _customExercises.removeWhere((e) => e.id == exercise.id);
    _customExercises.add(exercise);
    await _persist();
    notifyListeners();
  }

  Future<void> removeCustomExercise(String id) async {
    _customExercises.removeWhere((e) => e.id == id);
    await _persist();
    notifyListeners();
  }

  // ── Write API ────────────────────────────────────────────────────────────

  Future<void> saveSession(WorkoutSession session) async {
    _sessions.removeWhere(
      (s) =>
          _dateKey(s.date) == _dateKey(session.date) &&
          s.splitDayName == session.splitDayName,
    );
    _sessions.add(session);

    if (_sessions.length > _maxSessions) {
      _sessions = _sessions.reversed
          .take(_maxSessions)
          .toList()
          .reversed
          .toList();
    }
    
    // Once explicitly saved to active history, dispose of any matching draft.
    if (_draftSession?.splitDayName == session.splitDayName) {
      _draftSession = null;
    }

    await _persist();
    notifyListeners();
  }

  Future<void> saveDraftSession(WorkoutSession session) async {
    _draftSession = session;
    await _persist();
    notifyListeners();
  }

  Future<void> clearDraftSession() async {
    if (_draftSession == null) return;
    _draftSession = null;
    await _persist();
    notifyListeners();
  }

  Future<void> saveSplit(WorkoutSplit newSplit) async {
    _split = newSplit;
    _setupDone = true;
    await _persist();
    notifyListeners();
  }

  // ── Lifecycle ────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_ready) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kData);
      if (raw != null) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        _setupDone = data['setupDone'] as bool? ?? false;
        if (data['split'] != null) {
          _split = WorkoutSplit.fromJson(data['split'] as Map<String, dynamic>);
        }
        _sessions = (data['sessions'] as List<dynamic>? ?? [])
            .map((s) => WorkoutSession.fromJson(s as Map<String, dynamic>))
            .toList();
        _customExercises = (data['customExercises'] as List<dynamic>? ?? [])
            .map((e) => Exercise.fromJson(e as Map<String, dynamic>))
            .toList();
        if (data['draftSession'] != null) {
          _draftSession = WorkoutSession.fromJson(data['draftSession'] as Map<String, dynamic>);
        }
      }
    } catch (e) {
      debugPrint('[WorkoutService] load error: $e — starting fresh');
      _split = null;
      _sessions = [];
      _customExercises = [];
      _draftSession = null;
      _setupDone = false;
    }
    _ready = true;
    notifyListeners();
  }

  // ── Persistence ──────────────────────────────────────────────────────────

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kData,
        jsonEncode({
          'setupDone': _setupDone,
          'split': split.toJson(),
          'sessions': _sessions.map((s) => s.toJson()).toList(),
          'customExercises': _customExercises.map((e) => e.toJson()).toList(),
          if (_draftSession != null) 'draftSession': _draftSession!.toJson(),
        }),
      );
    } catch (e) {
      debugPrint('[WorkoutService] persist error: $e');
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, bool> splitCompletionThisWeek() {
    final now = DateTime.now();
    final mon = now.subtract(Duration(days: now.weekday - 1));
    final start = DateTime(mon.year, mon.month, mon.day);
    final weekSessions = _sessions.where(
      (s) =>
          !s.isEmpty &&
          !s.date.isBefore(start) &&
          s.date.isBefore(start.add(const Duration(days: 7))),
    );
    final completed = <String, bool>{
      for (final day in trainingDays) day.name: false,
    };
    for (final session in weekSessions) {
      completed[session.splitDayName] = true;
    }
    return completed;
  }

  List<String> recentImprovementHighlights({int limit = 3}) {
    final out = <String>[];
    final bySplit = <String, WorkoutSession>{};
    for (final session
        in _sessions.where((s) => !s.isEmpty).toList().reversed) {
      final prev = bySplit[session.splitDayName];
      if (prev != null) {
        final delta = compareWithPrevious(session, prev);
        final pr = delta.exerciseDeltas.where((d) => d.isPr).toList();
        if (pr.isNotEmpty) {
          out.add('${pr.first.exerciseName}: new PR');
        } else if (delta.isImprovement) {
          out.add('${session.splitDayName}: ${delta.volumeLabel}');
        }
      }
      bySplit[session.splitDayName] = session;
      if (out.length >= limit) break;
    }
    return out;
  }
}
