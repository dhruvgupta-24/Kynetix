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
}

extension SetTypeX on SetType {
  String get label => switch (this) {
    SetType.normal  => 'Working',
    SetType.warmUp  => 'Warm-up',
    SetType.dropSet => 'Drop',
  };

  String get shortLabel => switch (this) {
    SetType.normal  => 'W',
    SetType.warmUp  => 'WU',
    SetType.dropSet => 'D',
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

  SetEntry copyWith({
    double? weight,
    int? reps,
    double? rpe,
    SetType? setType,
  }) {
    return SetEntry(
      weight: weight ?? this.weight,
      reps: reps ?? this.reps,
      rpe: rpe ?? this.rpe,
      setType: setType ?? this.setType,
    );
  }

  /// Only normal sets drive primary target set completion decisions.
  bool get isMainWorkingSet => setType == SetType.normal;

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

// ─── SetPhase & SetStructure ──────────────────────────────────────────────────

enum SetPhase {
  work,
  warmUp,
}

enum SetStructure {
  straight,
  dropSet,
  restPause,
}

// ─── LogicalSetGroup ──────────────────────────────────────────────────────────
//
// Represents one logical set unit (which may have child drop-sets or rest-pause clusters).
// e.g. Set 3 (15 kg × 10) + Drop 1 (10 kg × 4) is ONE logical working set with 2 physical efforts.

class LogicalSetGroup {
  final SetEntry mainSet;
  final List<SetEntry> subSets; // Child drop sets or rest-pause clusters
  final SetPhase phase;
  final SetStructure structure;

  const LogicalSetGroup({
    required this.mainSet,
    this.subSets = const [],
    this.phase = SetPhase.work,
    this.structure = SetStructure.straight,
  });

  bool get isWorkingSet => phase == SetPhase.work && mainSet.isMainWorkingSet;
  bool get isWarmUp => phase == SetPhase.warmUp || mainSet.setType == SetType.warmUp;

  int get logicalWorkingSetsCount => isWorkingSet ? 1 : 0;
  int get physicalSetsCount => 1 + subSets.length;

  double get primaryVolume => isWarmUp ? 0.0 : mainSet.volume;
  double get subSetsVolume => subSets.where((s) => s.countsAsVolume).fold(0.0, (sum, s) => sum + s.volume);
  double get totalVolume => primaryVolume + subSetsVolume;

  /// Main set estimated 1RM (child drops do not inflate or skew 1RM calculations)
  double get estimatedOneRepMax => mainSet.estimatedOneRepMax;

  /// All physical sets belonging to this logical group (main set + subSets)
  List<SetEntry> get allPhysicalSets => [mainSet, ...subSets];

  LogicalSetGroup copyWith({
    SetEntry? mainSet,
    List<SetEntry>? subSets,
    SetPhase? phase,
    SetStructure? structure,
  }) {
    return LogicalSetGroup(
      mainSet: mainSet ?? this.mainSet,
      subSets: subSets ?? this.subSets,
      phase: phase ?? this.phase,
      structure: structure ?? this.structure,
    );
  }

  LogicalSetGroup addDrop(SetEntry drop) {
    return LogicalSetGroup(
      mainSet: mainSet,
      subSets: [...subSets, drop.copyWith(setType: SetType.dropSet)],
      phase: phase,
      structure: SetStructure.dropSet,
    );
  }

  LogicalSetGroup removeDropAt(int index) {
    if (index < 0 || index >= subSets.length) return this;
    final updated = List<SetEntry>.from(subSets)..removeAt(index);
    return LogicalSetGroup(
      mainSet: mainSet,
      subSets: updated,
      phase: phase,
      structure: updated.isEmpty ? SetStructure.straight : structure,
    );
  }

  Map<String, dynamic> toJson() => {
        'mainSet': mainSet.toJson(),
        'subSets': subSets.map((s) => s.toJson()).toList(),
        'phase': phase.name,
        'structure': structure.name,
      };

  factory LogicalSetGroup.fromJson(Map<String, dynamic> j) {
    final main = SetEntry.fromJson(j['mainSet'] as Map<String, dynamic>? ?? {});
    final sub = (j['subSets'] as List<dynamic>? ?? [])
        .map((s) => SetEntry.fromJson(s as Map<String, dynamic>))
        .toList();
    final p = (j['phase'] == 'warmUp' || main.setType == SetType.warmUp)
        ? SetPhase.warmUp
        : SetPhase.work;
    final s = j['structure'] != null
        ? SetStructure.values.byName(j['structure'] as String)
        : (sub.isNotEmpty ? SetStructure.dropSet : SetStructure.straight);
    return LogicalSetGroup(
      mainSet: main,
      subSets: sub,
      phase: p,
      structure: s,
    );
  }
}

/// Backward-compatible parser grouping legacy flat SetEntry lists into LogicalSetGroups.
List<LogicalSetGroup> groupLegacyFlatSets(List<SetEntry> flatSets) {
  if (flatSets.isEmpty) return const [];
  final List<LogicalSetGroup> groups = [];

  for (final s in flatSets) {
    if (s.setType == SetType.warmUp) {
      groups.add(LogicalSetGroup(
        mainSet: s,
        phase: SetPhase.warmUp,
        structure: SetStructure.straight,
      ));
    } else if (s.setType == SetType.dropSet) {
      if (groups.isNotEmpty && groups.last.isWorkingSet) {
        final last = groups.removeLast();
        groups.add(last.addDrop(s));
      } else {
        groups.add(LogicalSetGroup(
          mainSet: s,
          phase: SetPhase.work,
          structure: SetStructure.dropSet,
        ));
      }
    } else {
      groups.add(LogicalSetGroup(
        mainSet: s,
        phase: SetPhase.work,
        structure: SetStructure.straight,
      ));
    }
  }
  return groups;
}

// ─── ExerciseEntry ────────────────────────────────────────────────────────────

class ExerciseEntry {
  final Exercise             exercise;
  final List<LogicalSetGroup> logicalSets;
  final String?              notes;

  // Planned vs Executed State tracking fields
  final bool isSkipped;
  final String? skipReason;
  final bool isSubstitution;
  final String? substitutedForExerciseId;
  final String? substitutedForExerciseName;
  final bool isTemporaryAddition;

  factory ExerciseEntry({
    required Exercise exercise,
    List<LogicalSetGroup>? logicalSets,
    List<SetEntry>? sets,
    String? notes,
    bool isSkipped = false,
    String? skipReason,
    bool isSubstitution = false,
    String? substitutedForExerciseId,
    String? substitutedForExerciseName,
    bool isTemporaryAddition = false,
  }) {
    if (logicalSets != null) {
      return ExerciseEntry.raw(
        exercise: exercise,
        logicalSets: logicalSets,
        notes: notes,
        isSkipped: isSkipped,
        skipReason: skipReason,
        isSubstitution: isSubstitution,
        substitutedForExerciseId: substitutedForExerciseId,
        substitutedForExerciseName: substitutedForExerciseName,
        isTemporaryAddition: isTemporaryAddition,
      );
    }
    return ExerciseEntry.raw(
      exercise: exercise,
      logicalSets: sets != null ? groupLegacyFlatSets(sets) : const [],
      notes: notes,
      isSkipped: isSkipped,
      skipReason: skipReason,
      isSubstitution: isSubstitution,
      substitutedForExerciseId: substitutedForExerciseId,
      substitutedForExerciseName: substitutedForExerciseName,
      isTemporaryAddition: isTemporaryAddition,
    );
  }

  const ExerciseEntry.raw({
    required this.exercise,
    this.logicalSets = const [],
    this.notes,
    this.isSkipped = false,
    this.skipReason,
    this.isSubstitution = false,
    this.substitutedForExerciseId,
    this.substitutedForExerciseName,
    this.isTemporaryAddition = false,
  });

  /// Flattened physical sets for backwards compatibility
  List<SetEntry> get sets =>
      logicalSets.expand((g) => g.allPhysicalSets).toList();

  bool get isEmpty => logicalSets.isEmpty && !isSkipped;

  bool get isCompleted {
    if (isSkipped) return true;
    return completedWorkingSetsCount >= exercise.targetSets;
  }

  /// Logical working sets count (e.g. 3 working sets + 1 drop set = 3)
  int get completedWorkingSetsCount =>
      logicalSets.where((g) => g.isWorkingSet).length;

  int get warmUpSetsCount =>
      logicalSets.where((g) => g.isWarmUp).length;

  int get totalLogicalSetsCount => logicalSets.length;

  int get totalPhysicalSetsCount => sets.length;

  int get totalSetsCount => totalLogicalSetsCount;

  int get remainingWorkingSetsCount {
    final rem = exercise.targetSets - completedWorkingSetsCount;
    return rem < 0 ? 0 : rem;
  }

  /// Volume from primary working sets only (excludes warm-ups and drop sets)
  double get primaryWorkingVolume =>
      logicalSets.where((g) => g.isWorkingSet).fold(0.0, (sum, g) => sum + g.primaryVolume);

  /// Volume from child drop sets
  double get dropSetVolume =>
      logicalSets.where((g) => g.isWorkingSet).fold(0.0, (sum, g) => sum + g.subSetsVolume);

  /// Total physical volume providing stimulus (primary working volume + drop sets volume)
  double get totalStimulusVolume => primaryWorkingVolume + dropSetVolume;

  /// Total volume across all sets (stimulating sets)
  double get totalVolume => totalStimulusVolume;

  /// Backwards-compatibility getter for primary working volume
  double get workingVolume => primaryWorkingVolume;

  /// Best 1RM from main working sets (drop sets do not skew 1RM)
  double get bestOneRepMax {
    final working = logicalSets.where((g) => g.isWorkingSet).toList();
    if (working.isEmpty) return 0.0;
    return working.map((g) => g.estimatedOneRepMax).reduce((a, b) => a > b ? a : b);
  }

  /// Best set for progression comparison — highest 1RM from main working sets only.
  SetEntry? get topWorkingSet {
    final working = logicalSets.where((g) => g.isWorkingSet).map((g) => g.mainSet).toList();
    if (working.isEmpty) return null;
    return working.reduce(
        (a, b) => a.estimatedOneRepMax >= b.estimatedOneRepMax ? a : b);
  }

  SetEntry? get topProgressionSet => topWorkingSet;

  /// Best single set by 1RM across all physical sets
  SetEntry? get topSet => sets.isEmpty
      ? null
      : sets.reduce((a, b) =>
          a.estimatedOneRepMax >= b.estimatedOneRepMax ? a : b);

  Map<String, dynamic> toJson() => {
        'exercise': exercise.toJson(),
        'logicalSets': logicalSets.map((g) => g.toJson()).toList(),
        'sets': sets.map((s) => s.toJson()).toList(),
        if (notes != null && notes!.trim().isNotEmpty) 'notes': notes,
        'isSkipped': isSkipped,
        if (skipReason != null) 'skipReason': skipReason,
        'isSubstitution': isSubstitution,
        if (substitutedForExerciseId != null) 'substitutedForExerciseId': substitutedForExerciseId,
        if (substitutedForExerciseName != null) 'substitutedForExerciseName': substitutedForExerciseName,
        'isTemporaryAddition': isTemporaryAddition,
      };

  factory ExerciseEntry.fromJson(Map<String, dynamic> j) {
    List<LogicalSetGroup> parsedLogicalSets;
    if (j['logicalSets'] is List && (j['logicalSets'] as List).isNotEmpty) {
      parsedLogicalSets = (j['logicalSets'] as List)
          .map((g) => LogicalSetGroup.fromJson(g as Map<String, dynamic>))
          .toList();
    } else if (j['sets'] is List) {
      final flatSets = (j['sets'] as List)
          .map((s) => SetEntry.fromJson(s as Map<String, dynamic>))
          .toList();
      parsedLogicalSets = groupLegacyFlatSets(flatSets);
    } else {
      parsedLogicalSets = const [];
    }

    return ExerciseEntry(
      exercise: Exercise.fromJson(j['exercise'] as Map<String, dynamic>? ?? {}),
      logicalSets: parsedLogicalSets,
      notes: j['notes'] as String?,
      isSkipped: j['isSkipped'] as bool? ?? false,
      skipReason: j['skipReason'] as String?,
      isSubstitution: j['isSubstitution'] as bool? ?? false,
      substitutedForExerciseId: j['substitutedForExerciseId'] as String?,
      substitutedForExerciseName: j['substitutedForExerciseName'] as String?,
      isTemporaryAddition: j['isTemporaryAddition'] as bool? ?? false,
    );
  }
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
      entries.fold(0.0, (sum, e) => sum + e.totalVolume);

  /// Total primary working volume across all exercises.
  double get primaryWorkingVolume =>
      entries.fold(0.0, (sum, e) => sum + e.primaryWorkingVolume);

  /// Total drop set volume across all exercises.
  double get dropSetVolume =>
      entries.fold(0.0, (sum, e) => sum + e.dropSetVolume);

  /// Total stimulus volume across all exercises (all except warm-up).
  double get totalStimulusVolume =>
      entries.fold(0.0, (sum, e) => sum + e.totalStimulusVolume);

  /// Redirected for backwards-compatibility to return primary working volume.
  double get totalWorkingVolume => primaryWorkingVolume;

  /// Total logical sets (main working sets + warmups)
  int get totalSets =>
      entries.fold(0, (sum, e) => sum + e.totalSetsCount);

  /// Total physical sets (including all child drop sets)
  int get totalPhysicalSets =>
      entries.fold(0, (sum, e) => sum + e.totalPhysicalSetsCount);

  /// Total logical working sets across all exercises (drop sets do NOT increment this)
  int get totalWorkingSets =>
      entries.fold(0, (sum, e) => sum + e.completedWorkingSetsCount);

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
