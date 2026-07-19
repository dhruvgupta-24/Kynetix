import 'workout_split.dart';

// ─── SetType ──────────────────────────────────────────────────────────────────
//
// Tags a set for progression analysis and visual grouping.
// Warm-up sets are excluded from progression logic.
// Drop / superset sets are counted as working volume but progression
// analysis uses working sets only.

enum SetType {
  normal,     // Primary working set — used for progression decisions
  warmUp,     // Excluded from progression; shown muted in UI
  dropSet,    // Reduced weight after working set; counts for volume
  supersetA,  // Paired exercise A in superset
  supersetB,  // Paired exercise B in superset
  burnout,    // Max reps at end; counts for volume, not progression
}

extension SetTypeX on SetType {
  String get label => switch (this) {
    SetType.normal    => 'Working',
    SetType.warmUp    => 'Warm-up',
    SetType.dropSet   => 'Drop',
    SetType.supersetA => 'SS-A',
    SetType.supersetB => 'SS-B',
    SetType.burnout   => 'Burnout',
  };

  String get shortLabel => switch (this) {
    SetType.normal    => 'W',
    SetType.warmUp    => 'WU',
    SetType.dropSet   => 'D',
    SetType.supersetA => 'A',
    SetType.supersetB => 'B',
    SetType.burnout   => '🔥',
  };
}

// ─── SetEntry ─────────────────────────────────────────────────────────────────

class SetEntry {
  final double  weight; // kg
  final int     reps;
  final double? rpe;    // 1–10, optional
  final SetType setType;

  const SetEntry({
    required this.weight,
    required this.reps,
    this.rpe,
    this.setType = SetType.normal,
  });

  /// Only normal + superset sets drive progression decisions.
  /// Warm-up sets are intentionally lighter and skew the analysis.
  bool get isMainWorkingSet =>
      setType == SetType.normal ||
      setType == SetType.supersetA ||
      setType == SetType.supersetB;

  bool get drivesProgression => setType == SetType.normal;

  bool get countsAsVolume => setType != SetType.warmUp;

  /// Epley one-rep max estimate: weight × (1 + reps / 30)
  double get estimatedOneRepMax => weight * (1 + reps / 30.0);

  /// Volume for this set
  double get volume => weight * reps;

  Map<String, dynamic> toJson() => {
        'weight':  weight,
        'reps':    reps,
        'setType': setType.name,
        if (rpe != null) 'rpe': rpe,
      };

  factory SetEntry.fromJson(Map<String, dynamic> j) => SetEntry(
        weight:  (j['weight']  as num?)?.toDouble() ?? 0,
        reps:    (j['reps']    as num?)?.toInt()    ?? 0,
        rpe:     (j['rpe']     as num?)?.toDouble(),
        setType: _parseSetType(j['setType'] as String?),
      );

  static SetType _parseSetType(String? raw) {
    if (raw == null) return SetType.normal;
    try {
      return SetType.values.byName(raw);
    } catch (_) {
      return SetType.normal;
    }
  }

  @override
  String toString() =>
      '${weight.toStringAsFixed(1)} kg × $reps'
      '${rpe != null ? " @ RPE $rpe" : ""}'
      ' [${setType.label}]';
}

// ─── ExerciseEntry ────────────────────────────────────────────────────────────

class ExerciseEntry {
  final Exercise       exercise;
  final List<SetEntry> sets;
  final String?        notes;

  // Planned vs Executed State tracking fields
  final bool isSkipped;
  final String? skipReason;
  final bool isSubstitution;
  final String? substitutedForExerciseId;
  final String? substitutedForExerciseName;
  final bool isTemporaryAddition;

  const ExerciseEntry({
    required this.exercise,
    required this.sets,
    this.notes,
    this.isSkipped = false,
    this.skipReason,
    this.isSubstitution = false,
    this.substitutedForExerciseId,
    this.substitutedForExerciseName,
    this.isTemporaryAddition = false,
  });

  bool get isEmpty => sets.isEmpty && !isSkipped;

  bool get isCompleted {
    if (isSkipped) return true;
    return completedWorkingSetsCount >= exercise.targetSets;
  }

  int get completedWorkingSetsCount =>
      sets.where((s) => s.isMainWorkingSet).length;

  int get warmUpSetsCount =>
      sets.where((s) => s.setType == SetType.warmUp).length;

  int get totalSetsCount => sets.length;

  int get remainingWorkingSetsCount {
    final rem = exercise.targetSets - completedWorkingSetsCount;
    return rem < 0 ? 0 : rem;
  }

  double get totalVolume => sets.fold(0, (sum, s) => sum + s.volume);

  /// Volume from primary working sets only (normal, supersetA, supersetB).
  /// Excludes warm-ups, drop sets, and burnouts.
  double get primaryWorkingVolume =>
      sets.where((s) => s.isMainWorkingSet).fold(0, (sum, s) => sum + s.volume);

  /// Volume from all sets providing stimulus (excludes warm-up sets only).
  double get totalStimulusVolume =>
      sets.where((s) => s.countsAsVolume).fold(0, (sum, s) => sum + s.volume);

  /// Redirected for backwards-compatibility to return primary working volume.
  double get workingVolume => primaryWorkingVolume;

  double get bestOneRepMax => sets.isEmpty
      ? 0
      : sets.map((s) => s.estimatedOneRepMax).reduce((a, b) => a > b ? a : b);

  /// Best set for progression comparison — highest 1RM from main working sets only.
  SetEntry? get topWorkingSet {
    final working = sets.where((s) => s.isMainWorkingSet).toList();
    if (working.isEmpty) return null;
    return working.reduce(
        (a, b) => a.estimatedOneRepMax >= b.estimatedOneRepMax ? a : b);
  }

  SetEntry? get topProgressionSet {
    final progression = sets.where((s) => s.drivesProgression).toList();
    if (progression.isEmpty) return topWorkingSet;
    return progression.reduce(
        (a, b) => a.estimatedOneRepMax >= b.estimatedOneRepMax ? a : b);
  }

  /// Best single set by 1RM (all types — used for history display)
  SetEntry? get topSet => sets.isEmpty
      ? null
      : sets.reduce((a, b) =>
          a.estimatedOneRepMax >= b.estimatedOneRepMax ? a : b);

  Map<String, dynamic> toJson() => {
        'exercise': exercise.toJson(),
        'sets':     sets.map((s) => s.toJson()).toList(),
        if (notes != null && notes!.trim().isNotEmpty) 'notes': notes,
        'isSkipped': isSkipped,
        if (skipReason != null) 'skipReason': skipReason,
        'isSubstitution': isSubstitution,
        if (substitutedForExerciseId != null) 'substitutedForExerciseId': substitutedForExerciseId,
        if (substitutedForExerciseName != null) 'substitutedForExerciseName': substitutedForExerciseName,
        'isTemporaryAddition': isTemporaryAddition,
      };

  factory ExerciseEntry.fromJson(Map<String, dynamic> j) => ExerciseEntry(
        exercise: Exercise.fromJson(j['exercise'] as Map<String, dynamic>? ?? {}),
        sets:     (j['sets'] as List<dynamic>? ?? [])
            .map((s) => SetEntry.fromJson(s as Map<String, dynamic>))
            .toList(),
        notes:    j['notes'] as String?,
        isSkipped: j['isSkipped'] as bool? ?? false,
        skipReason: j['skipReason'] as String?,
        isSubstitution: j['isSubstitution'] as bool? ?? false,
        substitutedForExerciseId: j['substitutedForExerciseId'] as String?,
        substitutedForExerciseName: j['substitutedForExerciseName'] as String?,
        isTemporaryAddition: j['isTemporaryAddition'] as bool? ?? false,
      );
}

// ─── SessionDelta ─────────────────────────────────────────────────────────────
//
// Comparison between two sessions for the same split day.
// Used by the completion sheet to show progress feedback.

class SessionDelta {
  final double volumeChangePct; // + = improvement, - = decline, 0 = matched
  final List<ExerciseDelta> exerciseDeltas;

  const SessionDelta({
    required this.volumeChangePct,
    required this.exerciseDeltas,
  });

  bool get isImprovement => volumeChangePct >  3.0;
  bool get isDecline     => volumeChangePct < -3.0;

  String get volumeLabel {
    if (volumeChangePct.abs() < 3.0) return 'Matched last session';
    if (volumeChangePct > 0) return 'Volume up ${volumeChangePct.toStringAsFixed(0)}%';
    return 'Volume down ${volumeChangePct.abs().toStringAsFixed(0)}%';
  }
}

class ExerciseDelta {
  final String  exerciseName;
  final double  oneRmDelta;    // + = new PR or improvement
  final bool    isPr;
  final String  bestSetStr;    // e.g. "80 kg × 10"

  const ExerciseDelta({
    required this.exerciseName,
    required this.oneRmDelta,
    required this.isPr,
    required this.bestSetStr,
  });

  String get deltaLabel {
    if (isPr) return '🏆 New PR';
    if (oneRmDelta > 0.5) return '↑ Better than last';
    if (oneRmDelta < -0.5) return '↓ Slightly lower';
    return '↔ Matched';
  }
}

enum WorkoutStatus { active, completed, partial, abandoned }

// ─── WorkoutSession ───────────────────────────────────────────────────────────

class WorkoutSession {
  final String               id;
  final DateTime             date;
  final String               splitDayName;
  final int?                 splitDayWeekday;   // weekday the day was planned for (1–7)
  final bool                 wasManuallySelected; // true if user overrode their plan
  final List<ExerciseEntry>  entries;
  final String?              notes;
  final int?                 durationMinutes;
  final WorkoutStatus        status;
  final List<Exercise>?      plannedExercises;

  const WorkoutSession({
    required this.id,
    required this.date,
    required this.splitDayName,
    this.splitDayWeekday,
    this.wasManuallySelected = false,
    required this.entries,
    this.notes,
    this.durationMinutes,
    this.status = WorkoutStatus.completed,
    this.plannedExercises,
  });

  // ── Computed stats ──────────────────────────────────────────────────────────

  double get totalVolume =>
      entries.fold(0, (sum, e) => sum + e.totalVolume);

  /// Total primary working volume across all exercises (normal, supersetA, supersetB).
  double get primaryWorkingVolume =>
      entries.fold(0, (sum, e) => sum + e.primaryWorkingVolume);

  /// Total stimulus volume across all exercises (all except warm-up).
  double get totalStimulusVolume =>
      entries.fold(0, (sum, e) => sum + e.totalStimulusVolume);

  /// Redirected for backwards-compatibility to return primary working volume.
  double get totalWorkingVolume => primaryWorkingVolume;

  int get totalSets =>
      entries.fold(0, (sum, e) => sum + e.sets.length);

  int get totalWorkingSets =>
      entries.fold(0, (sum, e) => sum + e.sets.where((s) => s.isMainWorkingSet).length);

  bool get isEmpty => entries.every((e) => e.isEmpty);
  bool get isCustomSession => splitDayWeekday == null;

  /// All sets across all exercises (for global stats)
  List<SetEntry> get allSets =>
      entries.expand((e) => e.sets).toList();

  double get bestOneRepMax => allSets.isEmpty
      ? 0
      : allSets.map((s) => s.estimatedOneRepMax).reduce((a, b) => a > b ? a : b);

  SetEntry? get bestSetToday {
    if (allSets.isEmpty) return null;
    return allSets.reduce(
        (a, b) => a.estimatedOneRepMax >= b.estimatedOneRepMax ? a : b);
  }

  // ── Serialization ───────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'id':                   id,
        'date':                 date.toIso8601String(),
        'splitDayName':         splitDayName,
        if (splitDayWeekday != null) 'splitDayWeekday': splitDayWeekday,
        'wasManuallySelected':  wasManuallySelected,
        'entries':              entries.map((e) => e.toJson()).toList(),
        if (notes != null) 'notes': notes,
        if (durationMinutes != null) 'durationMinutes': durationMinutes,
        'status':               status.name,
        if (plannedExercises != null)
          'plannedExercises':   plannedExercises!.map((e) => e.toJson()).toList(),
      };

  factory WorkoutSession.fromJson(Map<String, dynamic> j) => WorkoutSession(
        id:                   j['id']           as String? ?? '',
        date:                 DateTime.tryParse(j['date'] as String? ?? '') ?? DateTime.now(),
        splitDayName:         j['splitDayName'] as String? ?? '',
        splitDayWeekday:      j['splitDayWeekday'] as int?,
        wasManuallySelected:  j['wasManuallySelected'] as bool? ?? false,
        entries:              (j['entries'] as List<dynamic>? ?? [])
            .map((e) => ExerciseEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        notes:           j['notes']           as String?,
        durationMinutes: j['durationMinutes'] as int?,
        status:          _parseStatus(j['status'] as String?),
        plannedExercises: (j['plannedExercises'] as List<dynamic>?)
            ?.map((e) => Exercise.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  static WorkoutStatus _parseStatus(String? name) {
    if (name == null) return WorkoutStatus.completed;
    try {
      return WorkoutStatus.values.byName(name);
    } catch (_) {
      return WorkoutStatus.completed;
    }
  }
}

// ─── PersonalRecord ───────────────────────────────────────────────────────────

class PersonalRecord {
  final String exerciseId;
  final String exerciseName;
  
  final double bestWeight;       // kg
  final String? bestWeightDate;  // yyyy-MM-dd
  
  final double bestVolume;       // kg
  final String? bestVolumeDate;  // yyyy-MM-dd
  
  final double bestEstimatedOneRepMax; // kg
  final String? bestEstimatedOneRepMaxDate; // yyyy-MM-dd
  
  /// Map of weight -> reps representing the most reps performed at that weight
  final Map<double, int> maxRepsAtWeight;
  /// Map of weight -> date of that reps record
  final Map<double, String> maxRepsAtWeightDate;

  const PersonalRecord({
    required this.exerciseId,
    required this.exerciseName,
    required this.bestWeight,
    this.bestWeightDate,
    required this.bestVolume,
    this.bestVolumeDate,
    required this.bestEstimatedOneRepMax,
    this.bestEstimatedOneRepMaxDate,
    required this.maxRepsAtWeight,
    required this.maxRepsAtWeightDate,
  });

  Map<String, dynamic> toJson() => {
    'exerciseId': exerciseId,
    'exerciseName': exerciseName,
    'bestWeight': bestWeight,
    if (bestWeightDate != null) 'bestWeightDate': bestWeightDate,
    'bestVolume': bestVolume,
    if (bestVolumeDate != null) 'bestVolumeDate': bestVolumeDate,
    'bestEstimatedOneRepMax': bestEstimatedOneRepMax,
    if (bestEstimatedOneRepMaxDate != null) 'bestEstimatedOneRepMaxDate': bestEstimatedOneRepMaxDate,
    'maxRepsAtWeight': maxRepsAtWeight.map((k, v) => MapEntry(k.toString(), v)),
    'maxRepsAtWeightDate': maxRepsAtWeightDate.map((k, v) => MapEntry(k.toString(), v)),
  };

  factory PersonalRecord.fromJson(Map<String, dynamic> j) {
    final rawMaxReps = j['maxRepsAtWeight'] as Map<String, dynamic>? ?? {};
    final rawMaxRepsDate = j['maxRepsAtWeightDate'] as Map<String, dynamic>? ?? {};
    
    return PersonalRecord(
      exerciseId: j['exerciseId'] as String? ?? '',
      exerciseName: j['exerciseName'] as String? ?? '',
      bestWeight: (j['bestWeight'] as num?)?.toDouble() ?? 0.0,
      bestWeightDate: j['bestWeightDate'] as String?,
      bestVolume: (j['bestVolume'] as num?)?.toDouble() ?? 0.0,
      bestVolumeDate: j['bestVolumeDate'] as String?,
      bestEstimatedOneRepMax: (j['bestEstimatedOneRepMax'] as num?)?.toDouble() ?? 0.0,
      bestEstimatedOneRepMaxDate: j['bestEstimatedOneRepMaxDate'] as String?,
      maxRepsAtWeight: rawMaxReps.map((k, v) => MapEntry(double.parse(k), (v as num).toInt())),
      maxRepsAtWeightDate: rawMaxRepsDate.map((k, v) => MapEntry(double.parse(k), v as String)),
    );
  }
}
